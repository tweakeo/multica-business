import Darwin
import Foundation
import GRDB
import TLSCore

/// Dónde puede mirar (o escribir) un asistente: sus áreas y, si le toca, el Buzón. Fuera de las áreas y del Buzón
/// (`Empresa.md`, `Archivo/`…), se puede leer.
public struct Alcance: Sendable, Hashable {
    public var areas: Set<AreaCode>
    public var buzon: Bool

    public init(areas: Set<AreaCode>, buzon: Bool) {
        self.areas = areas; self.buzon = buzon
    }

    public static let todo = Alcance(areas: Set(AreaCode.allCases), buzon: true)

    public func permite(_ ruta: VaultPath, layout: VaultLayout) -> Bool {
        if let area = layout.area(of: ruta) { return areas.contains(area) }
        if let b = layout.buzon, let primera = ruta.components.first, TextFolding.nameKey(primera) == TextFolding.nameKey(b) {
            return buzon
        }
        return true
    }
}

/// La carpeta tal como la puede ver un asistente (PLAN §5.4 y §8, capas 1, 2, 3 y 7):
///
/// - el índice se consulta con `privado = 0` y sin `Archivo/` **en el SQL**, y cada resultado se vuelve a comprobar;
/// - las rutas se normalizan en NFC, sin `..`, sin componentes ocultos (`.tls/`, `.obsidian/`) y sin enlaces
///   simbólicos en ningún tramo;
/// - patrones denegados siempre: `*.env`, `secrets.env`, `cookies.txt`, `*.p12`, `*.key`, `escritor.json`;
/// - lo privado (de `.tls/` y de los ajustes de la app) y lo que la persona dejó fuera responden «no encontrado»,
///   igual que lo que no existe: nunca se distingue;
/// - nada se descarga de iCloud.
public final class AgentView: @unchecked Sendable {
    public static let patronesDenegados = ["*.env", "secrets.env", "cookies.txt", "*.p12", "*.key", "escritor.json"]
    /// Tope de `tls_leer`.
    public static let maximoLectura = 64 * 1024
    /// Extensiones que se leen como texto.
    public static let extensionesDeTexto: Set<String> = ["md", "markdown", "csv", "txt", "json", "yaml", "yml", "canvas"]

    public let root: URL
    let realRoot: String
    let indiceURL: URL?
    let layoutActual: @Sendable () -> VaultLayout
    let reglas: ExclusionRules
    private let lock = NSLock()
    private var _db: DatabaseQueue?

    /// Por qué una ruta no se puede ver. Al asistente todo esto se le dice igual: «no encontrado».
    public enum Motivo: String, Sendable, Hashable {
        case vacia, fueraDeLaCarpeta, oculta, patronDenegado, privada, excluida, enlaceSimbolico, noExiste, fueraDeAlcance
    }

    public enum Resolucion: Sendable, Hashable {
        case ok(VaultPath)
        case no(Motivo)

        public var ruta: VaultPath? {
            if case .ok(let p) = self { return p }
            return nil
        }
    }

    /// - Parameters:
    ///   - indice: `index.sqlite` de la empresa (solo se abre para leer).
    ///   - layout: estructura vigente **con** lo privado de los ajustes (`VaultService.layout`).
    ///   - excluidas: lo que la persona dejó fuera (`exclusiones_copia` y las del servicio).
    public init(root: URL, indice: URL?, layout: @escaping @Sendable () -> VaultLayout, excluidas: [VaultPath] = []) {
        self.root = root.standardizedFileURL
        self.realRoot = Self.realPath(root.standardizedFileURL.path)
        self.indiceURL = indice
        self.layoutActual = layout
        self.reglas = ExclusionRules(paths: excluidas, patterns: Self.patronesDenegados)
    }

    /// Vista de una empresa abierta (su índice, su estructura y sus exclusiones).
    public convenience init(service: VaultService) {
        let estado = service.options.stateDirectory ?? AppLocations.vaultState(service.entry.id)
        self.init(root: service.root, indice: estado.appendingPathComponent("index.sqlite"), layout: { service.layout },
                  excluidas: (service.entry.exclusionesCopia.map { VaultPath($0) } + service.options.excluidas).filter { !$0.isRoot })
    }

    deinit {
        try? _db?.close()
    }

    /// Suelta la conexión de solo lectura al índice (al cerrar la empresa).
    public func cerrar() {
        lock.withLock {
            try? _db?.close()
            _db = nil
        }
    }

    public var layout: VaultLayout { layoutActual() }

    // MARK: Rutas

    /// Normaliza lo que escribe el asistente y decide si la ruta se puede ver.
    /// - Parameters:
    ///   - alcance: áreas que puede ver (fuera de ellas, `fueraDeAlcance`); `nil` = todas.
    ///   - debeExistir: si no existe, `noExiste` (para escribir una ruta nueva, `false`).
    public func resolver(_ texto: String, alcance: Alcance? = nil, debeExistir: Bool = true) -> Resolucion {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        if t.hasPrefix("/") || t.hasPrefix("~") || t.contains("\0") { return .no(.fueraDeLaCarpeta) }
        while t.hasPrefix("./") { t.removeFirst(2) }
        let partes = t.split(separator: "/", omittingEmptySubsequences: true).map(String.init).filter { $0 != "." }
        if partes.contains("..") { return .no(.fueraDeLaCarpeta) }
        if partes.contains(where: { $0.hasPrefix(".") }) { return .no(.oculta) }
        let ruta = VaultPath(components: partes)
        if ruta.isRoot { return .ok(ruta) }
        if let motivo = motivoOculto(ruta) { return .no(motivo) }
        if let a = alcance, !a.permite(ruta, layout: layout) { return .no(.fueraDeAlcance) }
        // Ningún tramo puede ser un enlace simbólico (ni llevar fuera de la carpeta).
        var actual = root
        for c in partes {
            actual = actual.appendingPathComponent(c)
            var st = stat()
            // Lo que no existe tampoco puede ser un enlace: para una ruta nueva basta con lo recorrido.
            guard lstat(actual.path, &st) == 0 else { return debeExistir ? .no(.noExiste) : .ok(ruta) }
            if (st.st_mode & S_IFMT) == S_IFLNK { return .no(.enlaceSimbolico) }
            // F4 · corrector: un fichero con más de un nombre (enlace duro) puede ser lo privado con otro nombre fuera
            // de su carpeta: tampoco se enseña.
            if (st.st_mode & S_IFMT) == S_IFREG, st.st_nlink > 1 { return .no(.enlaceSimbolico) }
        }
        let real = Self.realPath(actual.path)
        guard TextFolding.pathKey(real) == TextFolding.pathKey(realRoot + "/" + ruta.raw) else { return .no(.enlaceSimbolico) }
        return .ok(ruta)
    }

    /// Motivo por el que una ruta (ya normalizada) no se enseña nunca, o `nil` si se puede enseñar.
    public func motivoOculto(_ ruta: VaultPath) -> Motivo? {
        if ruta.components.contains(where: { $0.hasPrefix(".") }) { return .oculta }
        if reglas.excludes(ruta) {
            // Distinguimos solo para la auditoría.
            return ExclusionRules(patterns: Self.patronesDenegados).excludes(ruta) ? .patronDenegado : .excluida
        }
        if layout.isPrivate(ruta) { return .privada }
        if filaPrivada(ruta) { return .privada }
        return nil
    }

    /// `true` si la ruta se puede enseñar (y está en el alcance).
    public func esVisible(_ ruta: VaultPath, alcance: Alcance? = nil) -> Bool {
        guard motivoOculto(ruta) == nil else { return false }
        if let a = alcance, !a.permite(ruta, layout: layout) { return false }
        return true
    }

    // MARK: Leer

    public enum Lectura: Sendable, Hashable {
        case texto(VaultPath, contenido: String, truncado: Bool, bytes: Int64)
        /// Solo en iCloud: no se descarga.
        case soloEnICloud(VaultPath)
        case binario(VaultPath, bytes: Int64)
        case carpeta(VaultPath)
        case no(Motivo)
    }

    /// Lee como mucho `maximo` bytes de texto, sin descargar nada de iCloud. Los PDF ya leídos por la app devuelven
    /// su texto indexado.
    public func leer(_ texto: String, alcance: Alcance? = nil, maximo: Int = AgentView.maximoLectura) -> Lectura {
        let ruta: VaultPath
        switch resolver(texto, alcance: alcance) {
        case .ok(let p): ruta = p
        case .no(let m): return .no(m)
        }
        if ruta.isRoot { return .carpeta(ruta) }
        let url = ruta.url(in: root)
        return UbiquityInspector.withoutMaterializing { () -> Lectura in
            guard let info = UbiquityInspector.info(url) else { return .no(.noExiste) }
            if info.isSymlink { return .no(.enlaceSimbolico) }
            if info.isDirectory { return .carpeta(ruta) }
            if info.dataless { return .soloEnICloud(ruta) }
            guard Self.extensionesDeTexto.contains(ruta.ext) else {
                if ruta.ext == "pdf", let t = textoDePDF(ruta) {
                    let (c, trunc) = Self.recortar(Data(t.utf8), maximo: maximo)
                    return .texto(ruta, contenido: c, truncado: trunc, bytes: info.size)
                }
                return .binario(ruta, bytes: info.size)
            }
            guard let handle = try? FileHandle(forReadingFrom: url) else { return .no(.noExiste) }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: maximo + 1) else {
                return UbiquityInspector.isDataless(url) ? .soloEnICloud(ruta) : .no(.noExiste)
            }
            if data.count <= maximo, let entero = TextDecoding.decode(data) {
                return .texto(ruta, contenido: entero, truncado: false, bytes: info.size)
            }
            let (c, trunc) = Self.recortar(data, maximo: maximo)
            return .texto(ruta, contenido: c, truncado: trunc || data.count > maximo, bytes: info.size)
        }
    }

    /// Recorta a `maximo` bytes sin partir un carácter UTF-8.
    static func recortar(_ data: Data, maximo: Int) -> (String, Bool) {
        guard data.count > maximo else { return (String(decoding: data, as: UTF8.self), false) }
        var corte = maximo
        let bytes = [UInt8](data.prefix(maximo + 1))
        // Retrocede mientras el byte del corte sea de continuación (10xxxxxx).
        while corte > 0, corte < bytes.count, (bytes[corte] & 0xC0) == 0x80 { corte -= 1 }
        return (String(decoding: bytes.prefix(corte), as: UTF8.self), true)
    }

    // MARK: Listar

    public struct Entrada: Sendable, Hashable {
        public let ruta: VaultPath
        public let esCarpeta: Bool
        public let soloEnICloud: Bool
        public let bytes: Int64?
    }

    /// Hijos visibles de una carpeta (`nil` = «no encontrado»). Nunca abre una carpeta que esté solo en iCloud.
    public func listar(_ carpeta: String, alcance: Alcance? = nil) -> [Entrada]? {
        guard let dir = resolver(carpeta, alcance: alcance).ruta else { return nil }
        let url = dir.url(in: root)
        return UbiquityInspector.withoutMaterializing { () -> [Entrada]? in
            if !dir.isRoot {
                guard let info = UbiquityInspector.info(url), info.isDirectory, !info.isSymlink else { return nil }
                if info.dataless { return [] }
            }
            guard let nombres = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return nil }
            var out: [Entrada] = []
            for n in nombres {
                let nombre = n.precomposedStringWithCanonicalMapping
                if nombre.hasPrefix(".") { continue }
                let p = dir.appending(nombre)
                guard esVisible(p, alcance: alcance),
                      let fi = UbiquityInspector.info(path: url.appendingPathComponent(n).path), !fi.isSymlink else { continue }
                out.append(Entrada(ruta: p, esCarpeta: fi.isDirectory, soloEnICloud: fi.dataless, bytes: fi.isDirectory ? nil : fi.size))
            }
            return out.sorted { a, b in
                if a.esCarpeta != b.esCarpeta { return a.esCarpeta }
                return a.ruta.name.localizedStandardCompare(b.ruta.name) == .orderedAscending
            }
        }
    }

    // MARK: Buscar (índice, filtrado en SQL)

    public struct Resultado: Sendable, Hashable {
        public let ruta: VaultPath
        public let titulo: String
        public let tipo: String
        public let area: AreaCode?
        public let fragmento: String
    }

    /// Búsqueda de texto en el índice: `privado = 0` y fuera de `Archivo/` en la consulta, y cada fila se vuelve a
    /// comprobar. Sin índice, no hay resultados.
    public func buscar(_ consulta: String, limite: Int = 20, alcance: Alcance? = nil) -> [Resultado] {
        guard let match = Self.consultaFTS(consulta), let db = abrirIndice() else { return [] }
        let tope = max(1, min(limite, 50))
        let filas: [Resultado] = (try? db.read { db -> [Resultado] in
            let notas = try Row.fetchAll(db, sql: """
                SELECT n.path, n.title, n.kind, n.area, snippet(notes_fts, -1, '‹', '›', '…', 12) AS snip
                FROM notes_fts JOIN notes n ON n.rowid = notes_fts.rowid
                WHERE notes_fts MATCH ? AND n.privado = 0 AND n.archivado = 0 AND n.path NOT LIKE '.%'
                ORDER BY bm25(notes_fts, 8.0, 1.0)
                LIMIT ?
                """, arguments: [match, tope * 2])
            let pdfs = try Row.fetchAll(db, sql: """
                SELECT p.path, p.area, snippet(pdfs_fts, -1, '‹', '›', '…', 12) AS snip
                FROM pdfs_fts JOIN pdfs p ON p.rowid = pdfs_fts.rowid
                WHERE pdfs_fts MATCH ? AND p.path NOT LIKE '.%'
                ORDER BY bm25(pdfs_fts, 8.0, 1.0)
                LIMIT ?
                """, arguments: [match, tope])
            return notas.map { r in
                Resultado(ruta: VaultPath(r["path"] as String), titulo: r["title"], tipo: r["kind"],
                          area: (r["area"] as String?).flatMap(AreaCode.init(rawValue:)), fragmento: r["snip"] ?? "")
            } + pdfs.map { r in
                let p = VaultPath(r["path"] as String)
                return Resultado(ruta: p, titulo: p.stem, tipo: "pdf",
                                 area: (r["area"] as String?).flatMap(AreaCode.init(rawValue:)), fragmento: r["snip"] ?? "")
            }
        }) ?? []
        let layout = self.layout
        return Array(filas.filter { esVisible($0.ruta, alcance: alcance) && !layout.isArchived($0.ruta) }.prefix(tope))
    }

    /// Fichas del índice de un tipo (`tls_type`), sin lo privado ni `Archivo/`.
    public func fichas(tipo: String, alcance: Alcance? = nil, limite: Int = 200) -> [Resultado] {
        guard let db = abrirIndice() else { return [] }
        let filas: [Resultado] = (try? db.read { db -> [Resultado] in
            try Row.fetchAll(db, sql: """
                SELECT path, title, kind, area FROM notes
                WHERE kind = ? AND privado = 0 AND archivado = 0 AND path NOT LIKE '.%'
                ORDER BY path LIMIT ?
                """, arguments: [tipo, limite]).map { r in
                Resultado(ruta: VaultPath(r["path"] as String), titulo: r["title"], tipo: r["kind"],
                          area: (r["area"] as String?).flatMap(AreaCode.init(rawValue:)), fragmento: "")
            }
        }) ?? []
        return filas.filter { esVisible($0.ruta, alcance: alcance) }
    }

    /// `"factura cobro"` → `"factura"* "cobro"*` (como la búsqueda de la app).
    static func consultaFTS(_ q: String) -> String? {
        let terms = q.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init).prefix(12)
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    // MARK: Índice

    /// Fila del índice marcada como privada (segunda capa: aunque la estructura no lo dijera).
    func filaPrivada(_ ruta: VaultPath) -> Bool {
        guard let db = abrirIndice() else { return false }
        let v = try? db.read { db in
            try Bool.fetchOne(db, sql: "SELECT privado FROM notes WHERE path = ?", arguments: [ruta.raw])
        }
        return (v ?? nil) ?? false
    }

    func textoDePDF(_ ruta: VaultPath) -> String? {
        guard let db = abrirIndice() else { return nil }
        let t = try? db.read { db in
            try String.fetchOne(db, sql: """
                SELECT f.body FROM pdfs_fts f JOIN pdfs p ON p.rowid = f.rowid WHERE p.path = ?
                """, arguments: [ruta.raw])
        }
        return (t ?? nil).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Abre el índice solo para leer (si existe y su esquema es el que se conoce).
    func abrirIndice() -> DatabaseQueue? {
        lock.withLock {
            if let db = _db { return db }
            guard let url = indiceURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
            var config = Configuration()
            config.readonly = true
            config.label = "TLSAgentView"
            config.busyMode = .timeout(5)
            guard let db = try? DatabaseQueue(path: url.path, configuration: config) else { return nil }
            let tablas = (try? db.read { db in
                Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
            }) ?? []
            guard ["notes", "notes_fts", "pdfs", "pdfs_fts"].allSatisfy(tablas.contains) else {
                try? db.close()
                return nil
            }
            _db = db
            return db
        }
    }

    static func realPath(_ path: String) -> String {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.realpath(path, &buf) != nil else { return path.precomposedStringWithCanonicalMapping }
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).precomposedStringWithCanonicalMapping
    }
}
