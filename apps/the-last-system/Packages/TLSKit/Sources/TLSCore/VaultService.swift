import Foundation

/// Una empresa abierta: layout, índice, vigilancia y lectura. No escribe nunca: en F1 escribe
/// `VaultWriter`, que se le conecta con `conectar(_:alEscribir:)` para reindexar lo escrito.
///
/// Las firmas públicas son el contrato con TLSUI (docs/F0-CONTRATOS.md).
/// Garantías: no escribe nada en la carpeta; lo excluido no se lista, no se recorre ni se lee
/// (tampoco escrito con otras mayúsculas ni a través de un enlace simbólico); nada se descarga
/// de iCloud salvo al abrir una nota de texto (`requestDownload`).
public final class VaultService: @unchecked Sendable {
    /// Ajustes de apertura que no viven en la carpeta.
    public struct Options: Sendable {
        /// Rutas privadas añadidas a las de `.tls/layout.json` y `.tls/config.yaml`.
        public var privado: [VaultPath]
        /// Rutas que no se listan ni se recorren (además de `entry.exclusionesCopia`).
        public var excluidas: [VaultPath]
        /// Dónde vive el índice. Por defecto `AppLocations.vaultState(entry.id)`.
        /// Nunca dentro de la carpeta de la empresa ni en iCloud Drive.
        public var stateDirectory: URL?
        /// Leer también el contenido de `Archivo/` (por defecto solo nombres).
        public var indexarArchivo: Bool
        /// Arrancar la vigilancia de cambios al abrir.
        public var vigilar: Bool

        public init(privado: [VaultPath] = [], excluidas: [VaultPath] = [], stateDirectory: URL? = nil,
                    indexarArchivo: Bool = false, vigilar: Bool = true) {
            self.privado = privado; self.excluidas = excluidas; self.stateDirectory = stateDirectory
            self.indexarArchivo = indexarArchivo; self.vigilar = vigilar
        }
    }

    public let entry: VaultEntry
    public let root: URL
    public let options: Options
    /// Estructura de la carpeta (se vuelve a leer si cambia `.tls/layout.json` o `.tls/config.yaml`).
    public var layout: VaultLayout { lock.withLock { _layout } }
    /// Aviso para la persona si la estructura no se pudo leer o falta algo marcado como privado.
    public var layoutAviso: String? { lock.withLock { _layoutAviso } }

    let stateDirectory: URL
    /// Exclusiones fijas: las de la entrada (`exclusiones_copia`) y las de `options.excluidas`.
    let baseExcluded: [VaultPath]
    /// Ruta real de la raíz (`realpath`, NFC): FSEvents informa con ella (`/private/var/…`).
    let realRootPath: String
    private let indexQueue = DispatchQueue(label: "es.thelast.system.index", qos: .userInitiated)
    private let lock = NSLock()

    // Estado protegido por `lock`.
    private var _layout: VaultLayout
    private var _layoutAviso: String?
    /// Exclusiones vigentes: las fijas y, en la carpeta real, también lo `privado` de `.tls/`.
    private var _pathGuard: PathGuard
    private var _index: VaultIndex?
    private var _watcher: VaultWatcher?
    private var _matcher = QuickOpenMatcher.empty
    private var _resolver: LinkResolver?
    private var _onExternalChange: (@Sendable ([VaultPath]) -> Void)?
    /// Escrituras recientes del `VaultWriter` conectado (no cuentan como cambios de fuera).
    private var _escriturasPropias: RecentWrites?
    /// Sube con cada `close()`: lo que estaba en curso (apertura, reindexado) se para.
    private var _generation = 0

    public convenience init(entry: VaultEntry, root: URL) throws {
        try self.init(entry: entry, root: root, options: Options())
    }

    public init(entry: VaultEntry, root: URL, options: Options) throws {
        self.entry = entry
        let rootURL = root.standardizedFileURL
        self.root = rootURL
        self.realRootPath = PathGuard.realPath(rootURL) ?? rootURL.path.precomposedStringWithCanonicalMapping
        self.options = options
        self.baseExcluded = (entry.exclusionesCopia.map { VaultPath($0) } + options.excluidas).filter { !$0.isRoot }
        let state = options.stateDirectory ?? AppLocations.vaultState(entry.id)
        self.stateDirectory = state
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw VaultServiceError.carpetaNoEncontrada(rootURL.path)
        }
        // El estado técnico nunca va dentro de la carpeta de la empresa ni en iCloud Drive.
        if Self.isForbiddenStateDirectory(state, realRoot: realRootPath) {
            throw VaultServiceError.estadoNoPermitido(state.path)
        }
        let loaded = UbiquityInspector.withoutMaterializing {
            VaultLayout.load(root: rootURL, extraPrivado: options.privado)
        }
        self._layout = loaded.layout
        self._layoutAviso = loaded.aviso
        self._pathGuard = PathGuard(root: rootURL, rules: Self.rules(base: baseExcluded, layout: loaded.layout,
                                                                     clase: entry.clase))
    }

    deinit {
        _watcher?.stop()
    }

    /// Exclusiones vigentes. En la carpeta real («Ver sin tocar») lo que `.tls/` declara privado
    /// tampoco se lista ni se indexa; en una copia ya no está (no se copió).
    static func rules(base: [VaultPath], layout: VaultLayout, clase: VaultClass) -> ExclusionRules {
        var rules = ExclusionRules(paths: base)
        if clase == .real { for p in layout.privado { rules.add(p) } }
        return rules
    }

    /// `true` si `state` queda dentro de la carpeta de la empresa o de iCloud Drive.
    static func isForbiddenStateDirectory(_ state: URL, realRoot: String) -> Bool {
        // Primero solo texto: no se toca nada dentro de iCloud Drive.
        if AppLocations.isInICloudDrive(state.path) { return true }
        let canonical = PathGuard.canonicalPath(state)
        if AppLocations.isInICloudDrive(canonical) { return true }
        let real = TextFolding.pathKey(canonical)
        let rootKey = TextFolding.pathKey(realRoot)
        return real == rootKey || real.hasPrefix(rootKey + "/")
    }

    // MARK: Ciclo de vida

    /// Construye o actualiza el índice (en frío con progreso) y arranca la vigilancia.
    public func open(progress: @escaping @Sendable (IndexProgress) -> Void) async throws -> IndexStats {
        let generation = lock.withLock { _generation }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<IndexStats, Error>) in
            indexQueue.async {
                do {
                    let stats = try UbiquityInspector.withoutMaterializing {
                        try self.openOnQueue(progress, generation: generation)
                    }
                    cont.resume(returning: stats)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        lock.withLock { _generation == generation }
    }

    private func openOnQueue(_ progress: @escaping @Sendable (IndexProgress) -> Void, generation: Int) throws -> IndexStats {
        guard isCurrent(generation) else { throw CancellationError() }
        try checkExclusionsExist()
        var index = try lock.withLock { () throws -> VaultIndex in
            if let i = _index { return i }
            let i = try VaultIndex(directory: stateDirectory)
            _index = i
            return i
        }
        // Si cambió lo que decide qué entra (exclusiones, privado, estructura…), el índice se rehace
        // desde cero: así no quedan restos de lo que ahora está excluido.
        if let stored = index.storedConfig(), stored != builder(index, generation: generation).configFingerprint {
            index = try recreateIndex(index)
        }
        let result = try builder(index, generation: generation).fullScan(progress: progress)
        guard isCurrent(generation), lock.withLock({ _index === index }) else { throw CancellationError() }
        refreshCaches(index)
        if options.vigilar { startWatching(generation: generation) }
        return result.stats
    }

    /// En `indexQueue`: borra el índice y crea uno vacío en su lugar.
    private func recreateIndex(_ old: VaultIndex) throws -> VaultIndex {
        old.close()
        VaultIndex.deleteFiles(old.url)
        let fresh = try VaultIndex(directory: stateDirectory)
        try lock.withLock {
            guard _index === old else { fresh.close(); throw CancellationError() }
            _index = fresh
        }
        return fresh
    }

    /// Detiene la vigilancia y cierra el índice. Lo que estuviera en curso se para (sin escribir a medias).
    public func close() {
        let (watcher, index) = lock.withLock { () -> (VaultWatcher?, VaultIndex?) in
            _generation += 1
            defer { _watcher = nil; _index = nil; _matcher = .empty; _resolver = nil }
            return (_watcher, _index)
        }
        watcher?.stop()
        // El índice se cierra en su cola, cuando termine (o aborte) lo que esté haciendo.
        if let index { indexQueue.async { index.close() } }
    }

    /// Espera a que la cola del índice termine lo que tenía pendiente (útil tras `close()`,
    /// antes de borrar el índice o abrirlo con otro servicio).
    public func waitUntilIdle() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            indexQueue.async { cont.resume() }
        }
    }

    /// Se llama (en una cola cualquiera) con las rutas cambiadas fuera, ya reindexadas.
    /// Lista vacía = revisa todo (reescaneo o cambio de estructura).
    public var onExternalChange: (@Sendable ([VaultPath]) -> Void)? {
        get { lock.withLock { _onExternalChange } }
        set { lock.withLock { _onExternalChange = newValue } }
    }

    private func builder(_ index: VaultIndex, generation: Int) -> IndexBuilder {
        let (layout, rules) = lock.withLock { (_layout, _pathGuard.rules) }
        return IndexBuilder(root: root, layout: layout, index: index, excluded: rules.paths,
                            indexArchivoContent: options.indexarArchivo,
                            isCancelled: { [weak self] in self?.isCurrent(generation) != true })
    }

    private func refreshCaches(_ index: VaultIndex) {
        let rows = (try? index.allRows()) ?? []
        let matcher = QuickOpenMatcher(rows: rows)
        // Además de las notas, los adjuntos (PDF, imágenes, audio…) por su nombre, sin abrirlos: así
        // `resolverEnlace("[[factura.pdf]]")` encuentra el PDF aunque esté en otra carpeta (como Obsidian).
        let rules = lock.withLock { _pathGuard.rules }
        let adjuntos = IndexBuilder.rutasDeFicheros(root: root, rules: rules)
            .filter { !IndexBuilder.indexedExtensions.contains($0.ext) }
        let resolver = LinkResolver(paths: rows.map(\.path) + adjuntos, existsOnDisk: IndexBuilder.diskCheck(pathGuard))
        lock.withLock {
            guard _index === index else { return }
            _matcher = matcher
            _resolver = resolver
        }
    }

    private func startWatching(generation: Int) {
        let watcher = VaultWatcher(root: root) { [weak self] event in
            guard let self else { return }
            self.indexQueue.async { self.handle(event) }
        }
        let started = lock.withLock { () -> Bool in
            // Cerrado mientras se abría: no se deja una vigilancia huérfana.
            guard _watcher == nil, _generation == generation, _index != nil else { return false }
            _watcher = watcher
            return true
        }
        if started { watcher.start() }
    }

    /// Relee `.tls/` y recalcula las exclusiones (la carpeta real excluye también lo privado).
    private func reloadLayout() {
        let loaded = VaultLayout.load(root: root, extraPrivado: options.privado)
        let rules = Self.rules(base: baseExcluded, layout: loaded.layout, clase: entry.clase)
        lock.withLock {
            _layout = loaded.layout
            _layoutAviso = loaded.aviso
            _pathGuard = PathGuard(root: root, rules: rules)
        }
    }

    /// En `indexQueue`.
    private func handle(_ event: VaultWatcher.Event) {
        let (index, generation, propias) = lock.withLock { (_index, _generation, _escriturasPropias) }
        guard let index else { return }
        var changed: [VaultPath] = []
        var full = false
        /// `false` si todo lo que vio la vigilancia lo escribió la propia app.
        var deFuera = true
        UbiquityInspector.withoutMaterializing {
            switch event {
            case .rescan:
                // FSEvents perdió eventos: se relee también la estructura y se revisa todo.
                reloadLayout()
                full = true
                changed = (try? builder(index, generation: generation).fullScan(progress: nil).changed) ?? []
            case .paths(let urls):
                let paths = urls.compactMap(vaultPath(forEventURL:)).filter { !$0.isRoot }
                if let propias, propias.filterExternal(paths, root: root).isEmpty { deFuera = false }
                // Cambió la estructura (.tls/layout.json o config.yaml): se relee y se revisa todo.
                if Self.cambiaEstructura(paths) {
                    reloadLayout()
                    full = true
                    changed = (try? builder(index, generation: generation).fullScan(progress: nil).changed) ?? []
                } else {
                    changed = (try? builder(index, generation: generation).update(paths)) ?? []
                }
            }
        }
        guard isCurrent(generation) else { return }
        if full {
            refreshCaches(index)
            if deFuera { onExternalChange?([]) }
            return
        }
        guard !changed.isEmpty else { return }
        refreshCaches(index)
        // Lo que acaba de escribir la app ya está en el índice y no es un cambio de fuera.
        let externos = deFuera ? (propias?.filterExternal(changed, root: root) ?? changed) : []
        if !externos.isEmpty { onExternalChange?(externos) }
    }

    static func cambiaEstructura(_ paths: [VaultPath]) -> Bool {
        paths.contains { $0.raw == VaultLayout.layoutFile || $0.raw == VaultLayout.configFile }
    }

    // MARK: Escritura (F1)

    /// Escrituras recientes de la app: la vigilancia las reindexa, pero no las avisa en
    /// `onExternalChange`. Lo pone `conectar(_:alEscribir:)`.
    public var escriturasPropias: RecentWrites? {
        get { lock.withLock { _escriturasPropias } }
        set { lock.withLock { _escriturasPropias = newValue } }
    }

    /// Reindexa ya esas rutas (lo que acaba de escribir la app), sin esperar a la vigilancia.
    /// Si cambia `.tls/layout.json` o `config.yaml`, relee la estructura y revisa todo.
    /// `alTerminar` se llama en la cola del índice, con lo que cambió en él (vacío = todo).
    public func reindexar(_ paths: [VaultPath], alTerminar: (@Sendable ([VaultPath]) -> Void)? = nil) {
        let (index, generation) = lock.withLock { (_index, _generation) }
        guard let index, !paths.isEmpty else { alTerminar?([]); return }
        indexQueue.async { [weak self] in
            guard let self else { return }
            var changed: [VaultPath] = []
            let full = Self.cambiaEstructura(paths)
            UbiquityInspector.withoutMaterializing {
                if full {
                    self.reloadLayout()
                    changed = (try? self.builder(index, generation: generation).fullScan(progress: nil).changed) ?? []
                } else {
                    changed = (try? self.builder(index, generation: generation).update(paths)) ?? []
                }
            }
            guard self.isCurrent(generation) else { return }
            if full || !changed.isEmpty { self.refreshCaches(index) }
            alTerminar?(full ? [] : changed)
        }
    }

    /// Conecta el escritor de esta carpeta: tras cada plan se reindexa lo que tocó y después se
    /// llama a `alEscribir` con esas rutas (en la cola del índice); sus escrituras no llegan como
    /// cambios de fuera. Devuelve `false` (y no conecta nada) si el escritor es de otra carpeta.
    @discardableResult
    public func conectar(_ writer: VaultWriter, alEscribir: (@Sendable ([VaultPath]) -> Void)? = nil) async -> Bool {
        guard writer.entry.id == entry.id,
              PathGuard.canonicalPath(writer.root) == PathGuard.canonicalPath(root) else { return false }
        escriturasPropias = writer.recentWrites
        await writer.setOnApplied { [weak self] paths in
            guard let self else { return }
            self.reindexar(paths) { _ in alEscribir?(paths) }
        }
        return true
    }

    /// Deshace `conectar` (p. ej. al pasar a solo lectura, antes de `writer.close()`).
    public func desconectar(_ writer: VaultWriter) async {
        await writer.setOnApplied(nil)
        escriturasPropias = nil
    }

    // MARK: Exclusiones

    /// «Ver sin tocar»: cada carpeta privada elegida debe seguir ahí. Si se movió o cambió de nombre,
    /// se para (abrir sin ella mostraría lo privado) y la interfaz vuelve a preguntar.
    /// En una copia lo excluido no existe por diseño (no se copió): no se comprueba.
    func checkExclusionsExist() throws {
        guard entry.clase == .real else { return }
        for e in baseExcluded where !isPresentOrCovered(e, others: baseExcluded) {
            throw VaultServiceError.exclusionNoEncontrada(e.raw)
        }
        // Lo que la carpeta declara privado y no está: se avisa (no se puede quitar desde aquí).
        let declared = layout.privado
        if let perdida = declared.first(where: { !isPresentOrCovered($0, others: baseExcluded + declared) }) {
            let aviso = "Tu carpeta marca «\(perdida.raw)» como privada, pero no la encuentro. Si la has movido o le has cambiado el nombre, lo que contiene puede verse aquí."
            lock.withLock { _layoutAviso = aviso }
        }
    }

    /// Existe (`lstat`, que en APFS no distingue mayúsculas) o cuelga de algo que no se recorre.
    private func isPresentOrCovered(_ e: VaultPath, others: [VaultPath]) -> Bool {
        if UbiquityInspector.info(e.url(in: root)) != nil { return true }
        let rest = ExclusionRules(paths: others.filter { TextFolding.pathKey($0.raw) != TextFolding.pathKey(e.raw) })
        var ancestor = e.parent
        while let a = ancestor, !a.isRoot {
            if rest.excludes(a) { return true }
            if let i = UbiquityInspector.info(a.url(in: root)), i.dataless || i.isSymlink { return true }
            ancestor = a.parent
        }
        return false
    }

    private var pathGuard: PathGuard { lock.withLock { _pathGuard } }

    // MARK: Áreas

    /// Las 6 áreas en orden de presentación, leídas de sus `Área.md`.
    public func areas() -> [AreaSummary] {
        let resolver = currentResolver()
        let layout = self.layout
        let pathGuard = self.pathGuard
        return UbiquityInspector.withoutMaterializing {
            AreaCode.allCases.map { code in
                let folder = layout.areaFolder(code)
                let file = folder.appending(AreaReader.fileName)
                let url = file.url(in: root)
                guard let info = UbiquityInspector.info(url), !info.isDirectory, !info.isSymlink,
                      pathGuard.check(file) == .ok else {
                    return AreaReader.missing(code: code, folder: folder)
                }
                guard !info.dataless, let data = try? Data(contentsOf: url), let text = TextDecoding.decode(data) else {
                    // Sin descargar: el área existe pero su estado aún no se puede leer.
                    let m = AreaReader.missing(code: code, folder: folder)
                    return AreaSummary(code: code, folder: folder, titulo: m.titulo, estado: .desconocido, estadoTexto: "",
                                       lleva: nil, rol: nil, transforma: nil, sistemas: [], tieneFicha: true)
                }
                return AreaReader.parse(markdown: text, code: code, folder: folder) { resolver.resolve($0, from: file) }
            }
        }
    }

    // MARK: Carpeta

    /// Hijos inmediatos de una carpeta, leídos del disco sin descargar nada de iCloud.
    /// Oculta las entradas que empiezan por «.». Carpetas primero, orden natural.
    public func children(of folder: VaultPath) -> [FolderEntry] {
        let layout = self.layout
        let pathGuard = self.pathGuard
        return UbiquityInspector.withoutMaterializing { () -> [FolderEntry] in
            guard pathGuard.check(folder) == .ok else { return [] }
            let dirURL = folder.url(in: root)
            guard let info = UbiquityInspector.info(dirURL), info.isDirectory, !info.dataless,
                  let names = try? FileManager.default.contentsOfDirectory(atPath: dirURL.path) else { return [] }
            var out: [FolderEntry] = []
            for rawName in names {
                var name = rawName.precomposedStringWithCanonicalMapping
                var placeholder = false
                if name.hasPrefix(".") {
                    // Marcador antiguo de iCloud: «.Nota.md.icloud» es «Nota.md» sin descargar.
                    guard name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { continue }
                    name = String(name.dropFirst().dropLast(".icloud".count))
                    placeholder = true
                }
                let path = folder.appending(name)
                if !pathGuard.allowsByName(path) { continue }
                guard let fi = UbiquityInspector.info(path: dirURL.appendingPathComponent(rawName).path) else { continue }
                let isDir = fi.isDirectory && !placeholder
                out.append(FolderEntry(path: path, isDirectory: isDir, dataless: fi.dataless || placeholder,
                                       privado: layout.isPrivate(path), size: isDir ? nil : (placeholder ? nil : fi.size)))
            }
            return out.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.path.name.localizedStandardCompare(b.path.name) == .orderedAscending
            }
        }
    }

    // MARK: Lectura de notas

    /// Extensiones que el visor muestra como texto.
    static let textualExtensions: Set<String> = ["md", "markdown", "csv", "txt", "json", "yaml", "yml"]

    /// Contenido de una nota. Si es de texto y está solo en iCloud devuelve `.notDownloaded` y pide
    /// la descarga; lo que el visor no puede mostrar (PDF, vídeo…) nunca se descarga.
    public func read(_ path: VaultPath) -> NoteContent {
        let pathGuard = self.pathGuard
        let layout = self.layout
        return UbiquityInspector.withoutMaterializing { () -> NoteContent in
            guard !path.isRoot, pathGuard.allowsByName(path) else {
                return .unreadable(message: "Esta nota no está disponible.")
            }
            let url = path.url(in: root)
            guard let info = UbiquityInspector.info(url) else {
                return .unreadable(message: "No encuentro esta nota. Puede que se haya movido o borrado.")
            }
            if info.isSymlink { return .unreadable(message: "Es un acceso directo a otra ubicación y no se abre aquí.") }
            if info.isDirectory { return .unreadable(message: "Es una carpeta.") }
            switch pathGuard.check(path) {
            case .ok: break
            case .missing: return .unreadable(message: "No encuentro esta nota. Puede que se haya movido o borrado.")
            case .denied: return .unreadable(message: "Esta nota no está disponible.")
            }
            let ext = path.ext
            // Antes de pedir nada a iCloud: lo que no se puede ver aquí no se descarga.
            guard Self.textualExtensions.contains(ext) else { return .binary(size: info.size) }
            if info.dataless {
                UbiquityInspector.requestDownload(url)
                return .notDownloaded
            }
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                if UbiquityInspector.isDataless(url) {
                    UbiquityInspector.requestDownload(url)
                    return .notDownloaded
                }
                return .unreadable(message: "No se puede leer esta nota.")
            }
            guard let text = TextDecoding.decode(data) else {
                return .unreadable(message: "Esta nota no tiene texto legible.")
            }
            switch ext {
            case "md", "markdown":
                let doc = NoteDocument(text: text)
                let fm = doc.frontmatter
                return .markdown(text: doc.text, properties: fm.properties, body: doc.body,
                                 title: doc.title(fileStem: path.stem, frontmatter: fm),
                                 kind: NoteKindResolver.kind(of: path, frontmatter: fm, layout: layout))
            case "csv":
                let table = CSVTable.parse(text)
                return .csv(header: table.header, rows: table.rows, text: text)
            default:
                return .plain(text: text)
            }
        }
    }

    // MARK: Búsqueda

    /// ⌘O: por nombre y título, sin tildes; prefijo > palabra > subsecuencia.
    public func quickOpen(_ query: String, limit: Int = 20) -> [NoteSummary] {
        lock.withLock { _matcher }.search(query, limit: limit)
    }

    /// Búsqueda de texto completo (FTS5, sin tildes). Los términos van entre «‹» y «›».
    public func search(_ query: String, limit: Int = 50) -> [SearchHit] {
        guard let index = lock.withLock({ _index }), let match = Self.ftsQuery(query) else { return [] }
        return index.search(match: match, limit: limit).map { SearchHit(note: $0.0.summary, snippet: $0.1) }
    }

    /// Cada palabra como prefijo entre comillas: `factura cobro` → `"factura"* "cobro"*`.
    static func ftsQuery(_ query: String) -> String? {
        let terms = query.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    /// Notas que enlazan a `path`.
    public func backlinks(to path: VaultPath) -> [NoteSummary] {
        lock.withLock { _index }?.backlinks(to: path).map(\.summary) ?? []
    }

    /// Resuelve un enlace (Markdown relativo o wikilink) escrito en `from`.
    /// Nunca lleva a lo excluido, a lo oculto ni a través de un enlace simbólico.
    public func resolveLink(_ target: String, from: VaultPath) -> VaultPath? {
        guard let path = currentResolver().resolve(target, from: from) else { return nil }
        let pathGuard = self.pathGuard
        return UbiquityInspector.withoutMaterializing { pathGuard.check(path) == .ok } ? path : nil
    }

    /// Pide a iCloud que descargue un fichero (solo al abrirlo).
    public func requestDownload(_ path: VaultPath) {
        let pathGuard = self.pathGuard
        guard UbiquityInspector.withoutMaterializing({ pathGuard.check(path) == .ok }) else { return }
        UbiquityInspector.requestDownload(path.url(in: root))
    }

    public func summary(of path: VaultPath) -> NoteSummary? {
        lock.withLock { _index }?.row(for: path)?.summary
    }

    /// Índice abierto, para las consultas de solo lectura de las bases y ⌘K (`Bases/IndiceBases.swift`).
    /// `nil` si está cerrado. Añadido por el rol de bases (F1 interfaz).
    var indiceAbierto: VaultIndex? { lock.withLock { _index } }

    // MARK: Apoyo

    /// Ruta relativa de un evento de FSEvents. Se compara por texto con la ruta real de la
    /// raíz: un fichero borrado ya no se puede resolver con `resolvingSymlinksInPath`.
    func vaultPath(forEventURL url: URL) -> VaultPath? {
        let p = url.path.precomposedStringWithCanonicalMapping
        if p == realRootPath { return .root }
        if p.hasPrefix(realRootPath + "/") { return VaultPath(String(p.dropFirst(realRootPath.count + 1))) }
        return VaultPath(url: url, root: root)
    }

    static func realPath(_ url: URL) -> String {
        PathGuard.realPath(url) ?? url.path.precomposedStringWithCanonicalMapping
    }

    /// Resolvedor del índice o, si aún no se abrió, solo por ruta en disco.
    private func currentResolver() -> LinkResolver {
        if let r = lock.withLock({ _resolver }) { return r }
        return LinkResolver(paths: [], existsOnDisk: IndexBuilder.diskCheck(pathGuard))
    }

    func isExcluded(_ path: VaultPath) -> Bool {
        pathGuard.rules.excludes(path)
    }

    /// Sin `..` ni componentes ocultos: nunca se sale de la carpeta ni se entra en `.tls`.
    func isSafe(_ path: VaultPath) -> Bool {
        PathGuard.isSafe(path)
    }

    /// Volcado del índice (tests).
    func indexDump() throws -> [String] {
        guard let index = lock.withLock({ _index }) else { return [] }
        return try indexQueue.sync { try index.dump() }
    }

    /// Estado interno (tests): ¿hay vigilancia o índice abiertos?
    var debugState: (watching: Bool, indexOpen: Bool) {
        lock.withLock { (_watcher != nil, _index != nil) }
    }
}

public enum VaultServiceError: Error, LocalizedError, Sendable {
    case carpetaNoEncontrada(String)
    /// «Ver sin tocar»: una carpeta privada elegida ya no está (se movió o cambió de nombre).
    case exclusionNoEncontrada(String)
    /// El índice quedaría dentro de la carpeta de la empresa o en iCloud Drive.
    case estadoNoPermitido(String)

    public var errorDescription: String? {
        switch self {
        case .carpetaNoEncontrada(let p): "No encuentro la carpeta de tu empresa en \(p)."
        case .exclusionNoEncontrada(let p):
            "No encuentro «\(p)», una de las carpetas privadas que elegiste. Para no mostrar nada privado por error, no he abierto tu carpeta."
        case .estadoNoPermitido:
            "Los datos de trabajo de la app no pueden guardarse dentro de la carpeta de tu empresa ni en iCloud Drive."
        }
    }
}
