import CryptoKit
import Foundation
import GRDB

/// Construye y actualiza el índice leyendo la carpeta. Nunca escribe en ella.
///
/// - Salta lo oculto (`.tls`, `.obsidian`…), los enlaces simbólicos y las rutas excluidas
///   (se podan antes de entrar).
/// - No lee lo que está solo en iCloud (`dataless`): se indexa solo su nombre.
/// - De `Archivo/` solo se indexan los nombres (salvo que se pida lo contrario).
/// - Incremental por hash: tamaño y fecha solo deciden si hay que volver a calcularlo.
/// - Los PDF (F2, R1) solo se apuntan en `pdfs` (si no son privados ni de `Archivo/`); su texto lo lee después,
///   en segundo plano, `ColaTextoPDF`, y solo si ya están en el Mac.
///
/// Todas las llamadas deben hacerse dentro de `UbiquityInspector.withoutMaterializing`
/// y desde una sola cola.
struct IndexBuilder {
    let root: URL
    let layout: VaultLayout
    let index: VaultIndex
    let excluded: [VaultPath]
    let indexArchivoContent: Bool
    /// Exclusiones sin distinguir mayúsculas (como APFS) y comprobación de rutas en disco.
    let rules: ExclusionRules
    let pathGuard: PathGuard
    /// `true` si hay que parar (el servicio se cerró): la transacción en curso se deshace.
    let isCancelled: @Sendable () -> Bool

    init(root: URL, layout: VaultLayout, index: VaultIndex, excluded: [VaultPath], indexArchivoContent: Bool,
         isCancelled: @escaping @Sendable () -> Bool = { false }) {
        self.root = root; self.layout = layout; self.index = index; self.excluded = excluded
        self.indexArchivoContent = indexArchivoContent; self.isCancelled = isCancelled
        self.rules = ExclusionRules(paths: excluded)
        self.pathGuard = PathGuard(root: root, rules: rules)
    }

    /// Sube cuando cambia la forma de leer las notas: obliga a releerlas todas.
    static let parserVersion = 2

    /// Huella de todo lo que decide cómo se indexa (estructura, privado, exclusiones…).
    var configFingerprint: String {
        [layout.fingerprint, "archivo_contenido=\(indexArchivoContent)",
         "excluidas=" + rules.fingerprint,
         "lector=\(Self.parserVersion)"].joined(separator: "\n")
    }

    private func checkCancelled() throws {
        if isCancelled() { throw CancellationError() }
    }

    /// Extensiones que entran en el índice.
    static let indexedExtensions: Set<String> = ["md", "markdown", "csv", "txt"]

    struct ScanResult {
        var changed: [VaultPath]
        var stats: IndexStats
    }

    // MARK: Recorrido

    struct FoundFile { let path: VaultPath; let info: FileInfo }

    func isExcluded(_ path: VaultPath) -> Bool {
        rules.excludes(path)
    }

    /// Extensiones cuyo texto entra en la búsqueda desde F2 (en su propia tabla, sin ser notas).
    static let pdfExtensions: Set<String> = ["pdf"]

    /// Ficheros indexables bajo `folder` (recursivo, sin seguir enlaces ni entrar en lo excluido).
    func walk(_ folder: VaultPath = .root) throws -> [FoundFile] {
        try recorrer(folder).notas
    }

    /// Notas indexables y PDF bajo `folder` en un solo recorrido.
    func recorrer(_ folder: VaultPath = .root) throws -> (notas: [FoundFile], pdfs: [FoundFile]) {
        var out: [FoundFile] = []
        var pdfs: [FoundFile] = []
        var stack: [VaultPath] = [folder]
        let fm = FileManager.default
        while let dir = stack.popLast() {
            try checkCancelled()
            let url = dir.url(in: root)
            guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { continue }
            for name in names {
                if name.hasPrefix(".") { continue }
                let path = dir.appending(name)
                if isExcluded(path) { continue }
                guard let info = UbiquityInspector.info(path: url.appendingPathComponent(name).path),
                      !info.isSymlink else { continue }
                if info.isDirectory {
                    // Una carpeta solo en iCloud no se abre: listarla la descargaría.
                    if !info.dataless { stack.append(path) }
                } else if Self.indexedExtensions.contains(path.ext) {
                    out.append(FoundFile(path: path, info: info))
                } else if Self.pdfExtensions.contains(path.ext) {
                    pdfs.append(FoundFile(path: path, info: info))
                }
            }
        }
        return (out, pdfs)
    }

    /// Todas las rutas de ficheros de la carpeta (no solo las indexables) para resolver enlaces por nombre a
    /// adjuntos: `![[factura.pdf]]` desde otra carpeta, como Obsidian. Solo nombres y atributos: no abre ni
    /// descarga nada de iCloud, no entra en ocultos, enlaces ni lo excluido. Con tope, por si la carpeta es enorme.
    static func rutasDeFicheros(root: URL, rules: ExclusionRules, tope: Int = 100_000) -> [VaultPath] {
        var out: [VaultPath] = []
        var stack: [VaultPath] = [.root]
        let fm = FileManager.default
        while let dir = stack.popLast(), out.count < tope {
            let url = dir.url(in: root)
            guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = dir.appending(name)
                if rules.excludes(path) { continue }
                guard let info = UbiquityInspector.info(path: url.appendingPathComponent(name).path),
                      !info.isSymlink else { continue }
                if info.isDirectory {
                    if !info.dataless { stack.append(path) }
                } else {
                    out.append(path)
                }
            }
        }
        return out
    }

    // MARK: Escaneo completo (frío o en caliente)

    func fullScan(progress: (@Sendable (IndexProgress) -> Void)?) throws -> ScanResult {
        let start = Date()
        let (files, pdfs) = try recorrer()
        let existing = Dictionary(uniqueKeysWithValues: try index.allRows().map { ($0.path, $0) })
        let found = Set(files.map(\.path))
        var changed: [VaultPath] = []
        progress?(IndexProgress(processed: 0, total: files.count, currentPath: nil))
        var lastReport = Date()
        let fingerprint = configFingerprint
        let reconfigured = try index.db.write { db -> Bool in
            // Si cambió la configuración, todo se relee aunque el fichero no haya cambiado.
            let force = try VaultIndex.meta("config", in: db) != fingerprint
            for (i, f) in files.enumerated() {
                try checkCancelled()
                if try process(f, existing: existing[f.path], force: force, db: db) { changed.append(f.path) }
                if let progress, Date().timeIntervalSince(lastReport) > 0.05 || i + 1 == files.count {
                    progress(IndexProgress(processed: i + 1, total: files.count, currentPath: f.path))
                    lastReport = Date()
                }
            }
            for gone in existing.keys where !found.contains(gone) {
                try VaultIndex.delete(gone, in: db)
                changed.append(gone)
            }
            try registrarPDFs(pdfs, existentes: try VaultIndex.pdfRows(in: db), todos: true, forzar: force, db: db)
            if !changed.isEmpty || existing.isEmpty || force {
                _ = try VaultIndex.resolveLinks(resolver(db: db), in: db)
            }
            try VaultIndex.setMeta("config", fingerprint, in: db)
            return force && !existing.isEmpty
        }
        // Lo que acaba de quedar excluido no debe seguir en bruto en el fichero del índice.
        if reconfigured { index.purgeDeleted() }
        programarTextoPDF()
        let counts = index.counts()
        return ScanResult(changed: changed.sorted(),
                          stats: IndexStats(notes: counts.notes, dataless: counts.dataless,
                                            seconds: Date().timeIntervalSince(start)))
    }

    // MARK: Cambios sueltos (vigilancia)

    /// Reindexa las rutas dadas (ficheros o carpetas). Devuelve las que cambiaron de verdad.
    func update(_ paths: [VaultPath]) throws -> [VaultPath] {
        var changed: [VaultPath] = []
        try index.db.write { db in
            var seen = Set<VaultPath>()
            for path in paths where !seen.contains(path) {
                try checkCancelled()
                seen.insert(path)
                if path.components.contains(where: { $0.hasPrefix(".") }) || isExcluded(path) { continue }
                let info = UbiquityInspector.info(path: path.url(in: root).path)
                if let info, info.isDirectory, !info.isSymlink {
                    // Carpeta nueva, movida o borrada en parte: se revisa entera.
                    changed.append(path)
                    let (inside, pdfsDentro) = info.dataless ? ([], []) : try recorrer(path)
                    try registrarPDFs(pdfsDentro, existentes: try VaultIndex.pdfRows(in: db, under: path), todos: true,
                                      forzar: false, db: db)
                    let insideSet = Set(inside.map(\.path))
                    let prior = try Row.fetchAll(db, sql: "SELECT \(VaultIndex.columns) FROM notes WHERE path = ? OR path LIKE ? ESCAPE '\\'",
                                                 arguments: [path.raw, Self.likePrefix(path)]).map(VaultIndex.row)
                    let priorMap = Dictionary(uniqueKeysWithValues: prior.map { ($0.path, $0) })
                    for f in inside where try process(f, existing: priorMap[f.path], db: db) { changed.append(f.path) }
                    for p in prior where !insideSet.contains(p.path) {
                        try VaultIndex.delete(p.path, in: db); changed.append(p.path)
                    }
                    continue
                }
                let prior = try Row.fetchOne(db, sql: "SELECT \(VaultIndex.columns) FROM notes WHERE path = ?",
                                             arguments: [path.raw]).map(VaultIndex.row)
                if let info, !info.isSymlink, Self.indexedExtensions.contains(path.ext) {
                    if try process(FoundFile(path: path, info: info), existing: prior, db: db) { changed.append(path) }
                } else if let info, !info.isSymlink {
                    // PDF, imagen…: no es una nota, pero la carpeta que lo muestra debe refrescarse. Un PDF se apunta
                    // para leer su texto en segundo plano.
                    if Self.pdfExtensions.contains(path.ext) {
                        try registrarPDFs([FoundFile(path: path, info: info)],
                                          existentes: try VaultIndex.pdfRows(in: db, under: path), todos: false,
                                          forzar: false, db: db)
                    }
                    changed.append(path)
                } else if info == nil {
                    // Borrada (o carpeta borrada): fuera ella y lo que colgaba.
                    for p in try VaultIndex.pdfRows(in: db, under: path).keys { try VaultIndex.borrarPDF(p, in: db) }
                    let under = try String.fetchAll(db, sql: "SELECT path FROM notes WHERE path = ? OR path LIKE ? ESCAPE '\\'",
                                                    arguments: [path.raw, Self.likePrefix(path)])
                    for p in under { try VaultIndex.delete(VaultPath(p), in: db); changed.append(VaultPath(p)) }
                    if under.isEmpty { changed.append(path) }
                }
            }
            if !changed.isEmpty {
                _ = try VaultIndex.resolveLinks(resolver(db: db), in: db)
            }
        }
        programarTextoPDF()
        return Array(Set(changed)).sorted()
    }

    // MARK: PDF (texto para la búsqueda, F2)

    /// ¿Entra el texto de este PDF en la búsqueda? Nunca lo privado; lo de `Archivo/`, como las notas.
    func pdfIndexable(_ path: VaultPath) -> Bool {
        !layout.isPrivate(path) && (indexArchivoContent || !layout.isArchived(path))
    }

    /// Apunta los PDF encontrados. `todos` = la lista es completa para `existentes` (lo que no está, se quita).
    func registrarPDFs(_ encontrados: [FoundFile], existentes: [VaultPath: VaultIndex.PDFRow], todos: Bool,
                       forzar: Bool, db: Database) throws {
        var vistos = Set<VaultPath>()
        for f in encontrados {
            try checkCancelled()
            vistos.insert(f.path)
            guard pdfIndexable(f.path) else {
                if existentes[f.path] != nil { try VaultIndex.borrarPDF(f.path, in: db) }
                continue
            }
            try VaultIndex.registrarPDF(f.path, area: layout.area(of: f.path), size: f.info.size, mtime: f.info.mtimeNanos,
                                        dataless: f.info.dataless, existente: existentes[f.path], forzar: forzar, in: db)
        }
        if todos {
            for gone in existentes.keys where !vistos.contains(gone) { try VaultIndex.borrarPDF(gone, in: db) }
        }
    }

    /// Despierta la lectura en segundo plano con la configuración de este escaneo.
    func programarTextoPDF() {
        let layout = self.layout
        let guardia = self.pathGuard
        let archivo = indexArchivoContent
        index.textoPDF.programar(ColaTextoPDF.Trabajo(root: root) { path in
            !layout.isPrivate(path) && (archivo || !layout.isArchived(path)) && guardia.check(path) == .ok
        })
    }

    static func likePrefix(_ p: VaultPath) -> String {
        p.raw.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "/%"
    }

    // MARK: Un fichero

    /// Indexa un fichero si hace falta. Devuelve `true` si su contenido (o su estado) cambió.
    func process(_ f: FoundFile, existing: VaultIndex.NoteRow?, force: Bool = false, db: Database) throws -> Bool {
        let path = f.path
        let info = f.info
        let archived = layout.isArchived(path)
        let privado = layout.isPrivate(path)
        if !force, let e = existing, e.size == info.size, e.mtime == info.mtimeNanos, e.dataless == info.dataless,
           e.privado == privado, e.archivado == archived {
            return false  // en caliente: ni se abre
        }
        // Solo nombre: Archivo/ (por defecto) y lo que no está descargado.
        if (archived && !indexArchivoContent) || info.dataless {
            if let e = existing, info.dataless, !archived {
                // Se evictó de iCloud: el contenido indexado sigue valiendo.
                try VaultIndex.touch(path, size: info.size, mtime: info.mtimeNanos, dataless: true, in: db)
                return e.dataless != info.dataless
            }
            let row = VaultIndex.NoteRow(path: path, title: path.stem, kind: NoteKindResolver.kindByFolder(path, layout: layout),
                                         area: layout.area(of: path), hash: existing?.hash ?? "", size: info.size,
                                         mtime: info.mtimeNanos, dataless: info.dataless, privado: privado,
                                         archivado: archived, frontmatter: nil)
            try VaultIndex.upsert(.init(row: row, body: "", links: [], searchable: false), in: db)
            return existing == nil || existing?.title != row.title || existing?.kind != row.kind
        }
        guard let data = try? Data(contentsOf: path.url(in: root), options: [.uncached]) else {
            return false  // ilegible ahora (p. ej. se está guardando): la vigilancia volverá
        }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if !force, let e = existing, e.hash == hash, !e.dataless, e.privado == privado, e.archivado == archived {
            try VaultIndex.touch(path, size: info.size, mtime: info.mtimeNanos, dataless: false, in: db)
            return false
        }
        let parsed = Self.parse(data: data, path: path, layout: layout)
        let row = VaultIndex.NoteRow(path: path, title: parsed.title, kind: parsed.kind, area: layout.area(of: path),
                                     hash: hash, size: info.size, mtime: info.mtimeNanos, dataless: false,
                                     privado: privado, archivado: archived, frontmatter: parsed.frontmatterJSON)
        try VaultIndex.upsert(.init(row: row, body: parsed.searchText, links: parsed.links, searchable: true), in: db)
        if force, let e = existing {
            // Relectura forzada: solo cuenta como cambio si algo visible cambió.
            return e.hash != hash || e.title != row.title || e.kind != row.kind || e.area != row.area
                || e.privado != row.privado || e.archivado != row.archivado
        }
        return true
    }

    struct Parsed {
        var title: String
        var kind: NoteKind
        var frontmatterJSON: String?
        var searchText: String
        var links: [String]
    }

    static func parse(data: Data, path: VaultPath, layout: VaultLayout) -> Parsed {
        let text = TextDecoding.decode(data) ?? ""
        switch path.ext {
        case "md", "markdown":
            let doc = NoteDocument(text: text)
            let fm = doc.frontmatter
            var links = LinkParser.links(in: doc.body).filter { !$0.isExternal }.map(\.resolvable)
            // Wikilinks dentro de las propiedades (`empresa: "[[Ferretería]]"`).
            var propText: [String] = []
            for p in fm.properties {
                let v = p.value.displayText
                propText.append(v)
                if v.contains("[[") {
                    links += LinkParser.links(in: v).filter { $0.style == .wiki }.map(\.resolvable)
                }
            }
            let search = doc.body + (propText.isEmpty ? "" : "\n" + propText.joined(separator: "\n"))
            return Parsed(title: doc.title(fileStem: path.stem, frontmatter: fm),
                          kind: NoteKindResolver.kind(of: path, frontmatter: fm, layout: layout),
                          frontmatterJSON: doc.frontmatterText == nil ? nil : fm.json,
                          searchText: search, links: links)
        default:
            return Parsed(title: path.stem, kind: NoteKindResolver.kindByFolder(path, layout: layout),
                          frontmatterJSON: nil, searchText: text, links: [])
        }
    }

    /// Resolvedor con todas las rutas del índice (y el disco para lo que no se indexa: PDF, carpetas).
    func resolver(db: Database) throws -> LinkResolver {
        let paths = try String.fetchAll(db, sql: "SELECT path FROM notes").map(VaultPath.init)
        return LinkResolver(paths: paths, existsOnDisk: Self.diskCheck(pathGuard))
    }

    /// Para lo que no está en el índice (PDF, carpetas): existe, se puede mostrar y no pasa por enlaces
    /// ni por lo excluido, aunque se escriba con otras mayúsculas.
    static func diskCheck(_ pathGuard: PathGuard) -> @Sendable (VaultPath) -> Bool {
        { path in
            guard !path.isRoot else { return false }
            return UbiquityInspector.withoutMaterializing { pathGuard.exists(path) }
        }
    }
}
