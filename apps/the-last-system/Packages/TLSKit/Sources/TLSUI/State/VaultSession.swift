import AppKit
import Foundation
import Observation
import OSLog
import TLSCore
import TLSDesign

/// Qué muestra la columna central de la ventana de empresa (F0; se mantiene para las vistas de F0).
public enum SidebarItem: Hashable, Sendable {
    case area(AreaCode)
    case carpeta
    case busqueda
}

/// Hojas de la ventana de empresa (F0).
public enum VaultSheet: String, Identifiable, Sendable {
    case quickOpen, palette
    public var id: String { rawValue }
}

/// Instantánea de una nota leída (inmutable y `Sendable`).
public struct NoteSnapshot: Sendable {
    public let path: VaultPath
    /// `nil` mientras se lee.
    public let content: NoteContent?
    public let summary: NoteSummary?
    public let backlinks: [NoteSummary]
    /// Cambia en cada lectura: el visor sustituye el texto solo cuando cambia.
    public let lectura: Int
    /// Tramos de estilo del Markdown, calculados fuera del hilo principal (`nil` si no aplica).
    public var spans: [MarkdownSpan]? = nil
}

/// Fila visible del árbol de la carpeta.
public struct FolderRow: Identifiable, Hashable, Sendable {
    public let entry: FolderEntry
    public let depth: Int
    public var id: VaultPath { entry.path }
}

/// Por qué la app no escribe en esta carpeta.
public enum MotivoSoloLectura: Equatable, Sendable {
    /// La carpeta real: solo se lee hasta el relevo (F6).
    case carpetaReal
    /// La persona eligió ver esta copia sin cambiar nada.
    case elegido
    /// No se pudo abrir el escritor (otro Mac, otra ventana, carpeta de otra aplicación…). Texto llano.
    case noSePudo(String)

    public var texto: String {
        switch self {
        case .carpetaReal: "Tu carpeta real no se toca"
        case .elegido: "Elegiste verla sin cambiar nada"
        case .noSePudo(let motivo): motivo
        }
    }
}

/// Si la app puede escribir en esta carpeta.
public enum ModoEscritura: Equatable, Sendable {
    case abriendo
    /// Copia o ejemplo con el escritor abierto: todo pasa por `CommandBus` y se puede deshacer.
    case escribe
    case soloLectura(MotivoSoloLectura)
}

/// Una empresa abierta. **Una por empresa y proceso**, compartida por todas sus pestañas de ventana
/// (`AppModel.retenerSesion`): un solo índice y un solo escritor. Habla con `VaultService` y con el
/// `CommandBus` fuera del hilo principal.
///
/// Contrato para las pantallas (ver `docs/F1-INTERFAZ-CONTRATOS.md`):
/// - Leer: `leer(_:)`, `LectorNota`, `resumen(de:)`, `buscar(_:)`, `abrirRapido(_:)`, `instantanea()`,
///   `areas`, `esPrivado(_:)`; `revision` sube con cada cambio aplicado (de fuera o de la app).
/// - Escribir: `escribir(_:)` / `escribir(plan:)` (deshacer con ⌘Z y aviso con «Deshacer»).
/// - Navegar: `@Environment(\.navegar)` en las vistas; `navegar(a:modo:)` desde fuera de ellas.
@Observable @MainActor
public final class VaultSession {
    public enum Phase: Sendable {
        case abriendo(IndexProgress?)
        case lista
        case sinPermiso
        case noEncontrada
        /// «Ver sin tocar»: una carpeta privada elegida ya no está (ruta relativa). Hay que volver a elegir.
        case exclusionPerdida(String)
        case error(String)
    }

    public internal(set) var entry: VaultEntry
    public private(set) var root: URL?
    public private(set) var phase: Phase = .abriendo(nil)
    public private(set) var stats: IndexStats?
    public private(set) var areas: [AreaSummary] = []
    /// Aviso si la estructura de la carpeta (`.tls/layout.json`) no se pudo leer.
    public private(set) var layoutWarning: String?

    // MARK: Escritura (F1)

    public internal(set) var modoEscritura: ModoEscritura = .abriendo
    /// Nombre de quien escribe (`Autor.persona`). Lo pone `AppModel` (Ajustes).
    public var persona: String = AppModel.personaPorDefecto
    /// Conflictos, duplicados e iCloud pendientes: las tarjetas de «Revisar».
    public internal(set) var tarjetas: [ConflictRecord] = []
    /// Lo que hizo la recuperación al abrir (solo si hizo algo y aún no se ha visto).
    public internal(set) var recuperacion: VaultWriter.RecoveryReport?
    /// Aviso breve con «Deshacer» (se enseña abajo en la ventana).
    public var aviso: Aviso?
    /// UndoManager de la pestaña de ventana con el foco: ⌘Z deshace lo último escrito (`CommandBus.deshacer`).
    @ObservationIgnored public weak var undoManagerActivo: UndoManager?
    @ObservationIgnored public internal(set) var bus: CommandBus?
    @ObservationIgnored var writer: VaultWriter?
    /// F4: la integración de los asistentes del modelo que abrió esta sesión (`AppModel.integracionDeAsistentes`).
    @ObservationIgnored public internal(set) weak var integracion: (any IntegracionDeEmpresas)?

    // MARK: Navegación (F1)

    /// Barra lateral de esta empresa (orden, ocultos, bases fijadas).
    public private(set) var barraLateral: BarraLateralModelo
    /// Fichas, notas y ficheros visitados, el último primero (Recientes de la barra y de Hoy).
    public internal(set) var recientes: [VaultPath] = []
    /// Navegación de la pestaña con el foco (para `navegar(a:)` desde fuera de las vistas). Queda apuntada en
    /// `navegaciones` para que un renombrado (o su Deshacer) llegue a todas las pestañas de la empresa.
    @ObservationIgnored public weak var navegacionActiva: Navegacion? {
        didSet { if let n = navegacionActiva { registrarNavegacion(n) } }
    }
    /// Todas las pestañas y ventanas de esta empresa que se han visto (referencias débiles).
    @ObservationIgnored private var navegaciones: [NavegacionDebil] = []
    /// Abre una pestaña o ventana nueva (lo pone la ventana con `openWindow`).
    @ObservationIgnored public var abrirVentana: (@MainActor @Sendable (VentanaRuta) -> Void)?

    // MARK: F0 (vistas de carpeta, búsqueda y visor)

    public var sidebar: SidebarItem? = .area(.direccion)
    public var sheet: VaultSheet?
    /// Panel de propiedades (⌥⌘I) de la pestaña de ventana con el foco: cada pestaña guarda el suyo
    /// (`Navegacion.inspector`). Las pantallas lo leen de su propia pestaña (`@Environment(\.navegacion)`).
    public var showInspector: Bool {
        get { navegacionActiva?.inspector ?? inspectorSinPestana }
        set {
            if let n = navegacionActiva { n.inspector = newValue } else { inspectorSinPestana = newValue }
        }
    }
    private var inspectorSinPestana = true
    public private(set) var note: NoteSnapshot?
    /// Mensaje de un enlace que no lleva a ninguna nota.
    public var linkProblem: String?
    /// Nota solo en iCloud que no ha llegado tras esperar (se deja de reintentar).
    public private(set) var downloadGaveUp: VaultPath?
    public private(set) var folderFocus: VaultPath = .root
    public private(set) var childrenCache: [VaultPath: [FolderEntry]] = [:]
    public private(set) var expanded: Set<VaultPath> = []
    public var folderSelection: VaultPath?
    public private(set) var searchQuery = ""
    public private(set) var searchHits: [SearchHit] = []
    public private(set) var searching = false
    public private(set) var searchFocusToken = 0

    /// Sube con cada lote de cambios ya aplicado (de fuera o escritos por la app).
    public private(set) var revision = 0
    /// El día que fija la carpeta (`hoy:` de `.tls/config.yaml`; el ejemplo vive el 19 de octubre), si fija uno.
    public private(set) var hoyCarpeta: LocalDate?
    /// El día de esta empresa, el mismo en Hoy, las bases y las fichas: el que fija la carpeta o, si no, hoy.
    public var hoy: LocalDate { hoyCarpeta ?? .today() }
    /// Rutas del último lote (vacío = puede haber cambiado todo).
    public private(set) var ultimasCambiadas: Set<VaultPath> = []

    @ObservationIgnored var service: VaultService?
    /// F6 · integración: ajustes de la app donde está la marca del relevo de una carpeta real (`relevo.json`). Lo pone
    /// `start(using:)` con el directorio del registro.
    @ObservationIgnored var registroDeRelevo: URL?
    /// Carpeta de estado (índice, diario, barra lateral). `nil` = la de `AppLocations`.
    @ObservationIgnored let estado: URL?
    @ObservationIgnored var lecturas = 0
    @ObservationIgnored private var noteTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var changesTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var pendingChanges: Set<VaultPath> = []
    @ObservationIgnored private var fullRescanPending = false
    @ObservationIgnored private var externosPendientes: Set<VaultPath> = []
    @ObservationIgnored private var loadingFolders: Set<VaultPath> = []
    @ObservationIgnored var titulos: [VaultPath: String] = [:]

    static let log = Logger(subsystem: "es.thelast.system", category: "VaultSession")

    /// `estado` sustituye la carpeta de estado de `AppLocations` (pruebas).
    public init(entry: VaultEntry, estado: URL? = nil) {
        self.entry = entry
        self.estado = estado
        let dir = estado ?? AppLocations.vaultState(entry.id)
        self.barraLateral = BarraLateralModelo(archivo: dir.appendingPathComponent("barra-lateral.json"))
    }

    public var isReady: Bool {
        if case .lista = phase { return true }
        return false
    }

    /// F6 · integración: la carpeta real ya pasó por «Pasar a mi carpeta real» y la app escribe en ella.
    public var esRealConRelevo: Bool { WritePolicy.realConRelevoHecho(entry, appSupport: registroDeRelevo) }

    /// `true` si la app puede escribir ahora en esta carpeta.
    public var puedeEscribir: Bool { modoEscritura == .escribe }

    /// Quien firma lo que escribe la persona desde la app.
    public var autor: Autor { .persona(persona) }

    var directorioEstado: URL { estado ?? AppLocations.vaultState(entry.id) }

    // MARK: Abrir y cerrar

    /// Resuelve la carpeta, comprueba el permiso, construye o actualiza el índice con progreso y, en
    /// una copia o en el ejemplo con escritura, abre el escritor.
    public func start(using model: AppModel) async {
        if service != nil { close() }
        if let fresh = model.entry(id: entry.id) { entry = fresh }
        persona = model.personaEfectiva
        integracion = model.integracionDeAsistentes
        registroDeRelevo = model.registry.directory
        phase = .abriendo(nil)
        modoEscritura = .abriendo
        guard let url = model.resolveURL(entry) else {
            phase = .noEncontrada
            return
        }
        root = url
        switch await FolderAccess.check(url) {
        case .ok: break
        case .sinPermiso: phase = .sinPermiso; return
        case .noExiste: phase = .noEncontrada; return
        case .otro(let detalle): phase = .error(detalle); return
        }

        var opened: VaultService?
        let progress = AsyncStream<IndexProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let progressTask = Task { [weak self] in
            for await p in progress.stream {
                guard let self, case .abriendo = self.phase else { continue }
                self.phase = .abriendo(p)
            }
        }
        defer {
            progress.continuation.finish()
            progressTask.cancel()
        }
        do {
            let service = try VaultService(entry: entry, root: url, options: VaultService.Options(stateDirectory: estado))
            opened = service
            self.service = service

            // Cambios hechos fuera (Finder, TextEdit, iCloud): se agrupan con 250 ms de espera.
            let changes = AsyncStream<[VaultPath]>.makeStream(bufferingPolicy: .unbounded)
            service.onExternalChange = { paths in changes.continuation.yield(paths) }
            changesTask = Task { [weak self] in
                for await paths in changes.stream {
                    self?.enqueueChanges(paths, externos: true)
                }
            }

            let stats = try await Task.detached(priority: .userInitiated) {
                try await service.open { progress.continuation.yield($0) }
            }.value
            progress.continuation.finish()
            progressTask.cancel()
            guard self.service === service else { return }
            self.stats = stats
            layoutWarning = service.layoutAviso
            leerHoyCarpeta()
            await reloadAreas()
            await loadChildren(of: folderFocus)
            await conectarEscritor()
            guard self.service === service else { return }
            phase = .lista
        } catch {
            if opened != nil, self.service !== opened { return }
            if error is CancellationError { return }
            Self.log.error("No se pudo abrir la carpeta: \(String(describing: type(of: error)), privacy: .public) \(error.localizedDescription, privacy: .private)")
            switch error {
            case VaultServiceError.carpetaNoEncontrada:
                phase = .noEncontrada
            case VaultServiceError.exclusionNoEncontrada(let path):
                phase = .exclusionPerdida(path)
            default:
                phase = FolderAccess.isPermissionError(error) ? .sinPermiso : .error(error.localizedDescription)
            }
        }
    }

    /// «Ver sin tocar» con una carpeta privada que ya no está: la persona vuelve a elegir.
    public func replaceMissingPrivate(_ missing: String, with elegidas: [VaultPath], using model: AppModel) async {
        do {
            try model.replaceExclusion(id: entry.id, missing: missing, with: elegidas)
        } catch {
            phase = .error(error.localizedDescription)
            return
        }
        await start(using: model)
    }

    /// «Leer de nuevo desde cero»: borra solo el índice desechable y vuelve a abrir. La carpeta no se toca.
    public func rebuildIndex(using model: AppModel) async {
        let old = service
        close()
        await old?.waitUntilIdle()
        let dir = directorioEstado
        for name in ["index.sqlite", "index.sqlite-wal", "index.sqlite-shm"] {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
        childrenCache = [:]
        await start(using: model)
    }

    /// Lee `hoy:` de `.tls/config.yaml` (sin seguir enlaces ni descargar de iCloud).
    private func leerHoyCarpeta() {
        hoyCarpeta = root.flatMap { AjustesBases.leerTexto(AjustesBases.ficheroConfig, root: $0) }.flatMap(AjustesBases.hoy(config:))
    }

    // MARK: Pestañas de la empresa

    private final class NavegacionDebil { weak var valor: Navegacion?; init(_ n: Navegacion) { valor = n } }

    /// Apunta una pestaña o ventana de esta empresa (sin retenerla). Lo hace solo `navegacionActiva`; una
    /// pantalla que crea su propia navegación también puede llamarlo.
    public func registrarNavegacion(_ n: Navegacion) {
        navegaciones.removeAll { $0.valor == nil }
        if !navegaciones.contains(where: { $0.valor === n }) { navegaciones.append(NavegacionDebil(n)) }
    }

    /// Algo se renombró o se movió (o se deshizo un renombrado): todas las pestañas, su historial y Recientes
    /// siguen llevando a su sitio (§2.1 regla 6).
    func aplicarMovimientos(_ movs: [(de: VaultPath, a: VaultPath)]) {
        guard !movs.isEmpty else { return }
        navegaciones.removeAll { $0.valor == nil }
        var hechas: [ObjectIdentifier] = []
        for n in navegaciones.compactMap(\.valor) + [navegacionActiva].compactMap({ $0 })
        where !hechas.contains(ObjectIdentifier(n)) {
            hechas.append(ObjectIdentifier(n))
            n.aplicarMovimientos(movs)
        }
        var nuevos: [VaultPath] = []
        for p in recientes.map({ p in movs.reduce(p) { $0 == $1.de ? $1.a : $0 } }) where !nuevos.contains(p) {
            nuevos.append(p)
        }
        recientes = nuevos
    }

    /// Cierra el índice y suelta el escritor (`desconectar` + `close`). Suelta también lo que las bases y las
    /// fichas guardaban de esta empresa (datos, foto de la carpeta con lo privado).
    public func close() {
        AlmacenBases.soltar(self)
        AlmacenRelaciones.soltar(self)
        changesTask?.cancel()
        debounceTask?.cancel()
        noteTask?.cancel()
        retryTask?.cancel()
        searchTask?.cancel()
        let service = self.service
        self.service = nil
        let writer = self.writer
        self.writer = nil
        bus = nil
        if let writer {
            // F4: antes de soltar el escritor, la integración para los asistentes de esta empresa (cola, servidor de
            // herramientas, chat): nada suyo escribe con un escritor cerrado y no queda ningún `tls-mcp` vivo.
            let integracion = self.integracion
            Task {
                if let integracion { await integracion.escritorSeVa(self) }
                if let service { await service.desconectar(writer) }
                await writer.close()
            }
        }
        service?.onExternalChange = nil
        service?.close()
    }

    // MARK: Áreas

    public func area(_ code: AreaCode) -> AreaSummary? {
        areas.first { $0.code == code }
    }

    func reloadAreas() async {
        guard let service else { return }
        let loaded = await Task.detached(priority: .userInitiated) { service.areas() }.value
        areas = loaded
        for a in loaded {
            barraLateral.datos[.area(a.code), default: DatoFilaBarra()].debajo = a.estado == .desconocido ? nil : a.estado.etiquetaCorta
            barraLateral.datos[.area(a.code), default: DatoFilaBarra()].atenuado = a.estado == .reposo
        }
    }

    /// Muestra el área (F0: columna central; F1: raíz nueva en la pestaña con el foco).
    public func select(area code: AreaCode) {
        sidebar = .area(code)
        navegar(a: .area(code), modo: .raiz)
    }

    // MARK: Notas (F0)

    /// Abre una ruta: en F1 navega a su pantalla (ficha, nota, fichero o carpeta) en la pestaña con el foco.
    public func open(_ path: VaultPath) {
        navegar(a: destino(para: path), modo: .automatico)
    }

    /// Carga una nota en `note` (visor de F0). Las pantallas nuevas usan `LectorNota`.
    public func cargarEnVisor(_ path: VaultPath) {
        retryTask?.cancel()
        retryTask = nil
        noteTask?.cancel()
        downloadGaveUp = nil
        lecturas += 1
        note = NoteSnapshot(path: path, content: nil, summary: nil, backlinks: [], lectura: lecturas)
        noteTask = Task { [weak self] in await self?.loadNote(path) }
    }

    public func reloadNote() {
        guard let path = note?.path else { return }
        noteTask?.cancel()
        noteTask = Task { [weak self] in await self?.loadNote(path) }
    }

    public func retryDownload() {
        guard note != nil else { return }
        downloadGaveUp = nil
        retryTask?.cancel()
        retryTask = nil
        reloadNote()
    }

    /// Intentos de lectura (cada 2 s) mientras una nota baja de iCloud: unos 3 minutos.
    static let downloadAttempts = 90

    private func loadNote(_ path: VaultPath, fromRetry: Bool = false) async {
        guard let snapshot = await leer(path) else { return }
        guard !Task.isCancelled, note?.path == path else { return }
        note = snapshot
        if case .notDownloaded? = snapshot.content {
            if !fromRetry, retryTask == nil, downloadGaveUp != path { scheduleDownloadRetry(path) }
        } else {
            retryTask?.cancel()
            retryTask = nil
        }
    }

    private func scheduleDownloadRetry(_ path: VaultPath) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            for _ in 0..<Self.downloadAttempts {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self, self.note?.path == path else { return }
                guard case .notDownloaded? = self.note?.content else { self.retryTask = nil; return }
                await self.loadNote(path, fromRetry: true)
            }
            guard !Task.isCancelled, let self, self.note?.path == path,
                  case .notDownloaded? = self.note?.content else { return }
            self.downloadGaveUp = path
            self.retryTask = nil
        }
    }

    /// Sigue un enlace escrito en una nota (`desde`; por defecto, la del visor de F0).
    public func followLink(_ target: String, desde: VaultPath? = nil) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto"].contains(scheme) {
            NSWorkspace.shared.open(url)
            return
        }
        guard let from = desde ?? note?.path, let path = resolverEnlace(trimmed, desde: from) else {
            linkProblem = "No encuentro «\(Self.visibleLinkName(trimmed))» en la carpeta de tu empresa."
            return
        }
        open(path)
    }

    /// Resuelve un enlace (wikilink o Markdown relativo) escrito en `desde`. Nunca lleva a lo excluido.
    public func resolverEnlace(_ target: String, desde from: VaultPath) -> VaultPath? {
        guard let service else { return nil }
        let isWikilink = target.hasPrefix("[[") && target.hasSuffix("]]")
        let candidates = isWikilink ? [target, String(target.dropFirst(2).dropLast(2))] : [target, "[[\(target)]]"]
        for candidate in candidates {
            if let path = service.resolveLink(candidate, from: from) { return path }
        }
        return nil
    }

    static func visibleLinkName(_ target: String) -> String {
        var s = target
        if s.hasPrefix("[["), s.hasSuffix("]]") { s = String(s.dropFirst(2).dropLast(2)) }
        return s.removingPercentEncoding ?? s
    }

    public func url(for path: VaultPath) -> URL? {
        root.map { path.url(in: $0) }
    }

    /// Muestra en Finder la ruta indicada, la nota del visor o la carpeta de la empresa.
    public func revealInFinder(_ path: VaultPath? = nil) {
        guard let root else { return }
        let target = path ?? navegacionActiva?.actual.ruta ?? note?.path ?? folderSelection ?? .root
        FolderAccess.revealInFinder(target.isRoot ? root : target.url(in: root))
        // El hito «editar y ver en Finder» del tutorial cuenta también con ⇧⌘R y el menú (no solo con la burbuja).
        TutorialEventos.registrar(.vistaEnFinder(target.isRoot ? nil : target), empresa: entry.id)
    }

    func isDirectory(_ path: VaultPath) -> Bool {
        if childrenCache[path] != nil { return true }
        guard let root, !path.isRoot else { return path.isRoot }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path.url(in: root).path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Carpeta (árbol perezoso, F0)

    public var folderRows: [FolderRow] {
        var rows: [FolderRow] = []
        func add(_ folder: VaultPath, depth: Int) {
            for child in childrenCache[folder] ?? [] {
                rows.append(FolderRow(entry: child, depth: depth))
                if child.isDirectory, expanded.contains(child.path) {
                    add(child.path, depth: depth + 1)
                }
            }
        }
        add(folderFocus, depth: 0)
        return rows
    }

    public func isLoaded(_ folder: VaultPath) -> Bool { childrenCache[folder] != nil }

    /// Enfoca el árbol en una carpeta (o en toda).
    public func showFolder(_ folder: VaultPath) {
        folderFocus = folder
        sidebar = .carpeta
        if childrenCache[folder] == nil {
            Task { await loadChildren(of: folder) }
        }
    }

    public func toggle(_ folder: VaultPath) {
        expanded.contains(folder) ? collapse(folder) : expand(folder)
    }

    public func expand(_ folder: VaultPath) {
        expanded.insert(folder)
        if childrenCache[folder] == nil {
            Task { await loadChildren(of: folder) }
        }
    }

    public func collapse(_ folder: VaultPath) {
        expanded.remove(folder)
    }

    func loadChildren(of folder: VaultPath) async {
        guard let service, !loadingFolders.contains(folder) else { return }
        loadingFolders.insert(folder)
        defer { loadingFolders.remove(folder) }
        let kids = await Task.detached(priority: .userInitiated) { service.children(of: folder) }.value
        childrenCache[folder] = kids
    }

    // MARK: ⌘O y búsqueda (F0)

    /// ⌘O: por nombre y título.
    public func quickOpen(_ query: String) async -> [NoteSummary] {
        await abrirRapido(query, limite: 20)
    }

    /// ⇧⌘F: muestra la búsqueda y lleva el foco al campo.
    public func focusSearch() {
        sidebar = .busqueda
        searchFocusToken += 1
    }

    /// Búsqueda de texto completo con 200 ms de espera entre teclas (vistas de F0).
    public func updateSearch(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let service else {
            searchHits = []
            searching = false
            return
        }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let hits = await Task.detached(priority: .userInitiated) { service.search(q, limit: 50) }.value
            guard !Task.isCancelled, let self, self.searchQuery == query else { return }
            self.searchHits = hits
            self.searching = false
        }
    }

    // MARK: Cambios (de fuera y propios)

    func enqueueChanges(_ paths: [VaultPath], externos: Bool) {
        if paths.isEmpty { fullRescanPending = true }
        pendingChanges.formUnion(paths)
        if externos { externosPendientes.formUnion(paths) }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let batch = self.pendingChanges
            let full = self.fullRescanPending
            let externos = self.externosPendientes
            self.pendingChanges = []
            self.fullRescanPending = false
            self.externosPendientes = []
            await self.applyChanges(batch, full: full, externos: externos)
        }
    }

    private func applyChanges(_ paths: Set<VaultPath>, full: Bool, externos: Set<VaultPath>) async {
        titulos = full ? [:] : titulos.filter { !paths.contains($0.key) }
        ultimasCambiadas = full ? [] : paths
        revision += 1
        if full { layoutWarning = service?.layoutAviso }
        if full || paths.contains(AjustesBases.ficheroConfig) { leerHoyCarpeta() }
        await reloadAreas()

        let touched = Set(paths.compactMap(\.parent)).union(paths)
        let loaded = Set(childrenCache.keys)
        for folder in loaded where full || touched.contains(folder) {
            await loadChildren(of: folder)
        }

        if let current = note?.path {
            let downloading: Bool = { if case .notDownloaded? = note?.content { return true }; return false }()
            if full || paths.contains(current) || (downloading && downloadGaveUp != current) {
                reloadNote()
            }
        }
        if !searchQuery.isEmpty {
            updateSearch(searchQuery)
        }
        if !externos.isEmpty { await revisarCambiosDeFuera(Array(externos)) }
        // F4: el motor de los asistentes vuelve a mirar (tareas listas, menciones, `config.yaml`, áreas).
        if let integracion {
            let rutas = full ? [] : Array(paths)
            Task { await integracion.carpetaCambio(self, rutas: rutas) }
        }
    }

    /// Avisa con las rutas que la app acaba de escribir (llamado tras reindexar).
    func escrituraAplicada(_ paths: [VaultPath]) {
        enqueueChanges(paths, externos: false)
    }
}
