import Foundation

/// Dónde está guardada una versión en conflicto.
public enum ConflictLocation: Sendable, Hashable, Codable {
    /// En la carpeta de la empresa (la que hay ahora en disco).
    case carpeta(VaultPath)
    /// Copia guardada por la app fuera de la carpeta (`<estado>/conflictos/<id>/<fichero>`).
    case copia(String)
}

public struct ConflictVersion: Sendable, Hashable, Codable {
    /// «Tu versión», «La de fuera», «Versión de otro Mac»…
    public var etiqueta: String
    public var ubicacion: ConflictLocation
    public var hash: String?

    public init(etiqueta: String, ubicacion: ConflictLocation, hash: String?) {
        self.etiqueta = etiqueta; self.ubicacion = ubicacion; self.hash = hash
    }
}

/// Un conflicto o duplicado pendiente: lo que la interfaz enseña como tarjeta.
public struct ConflictRecord: Sendable, Hashable, Codable, Identifiable {
    public enum Tipo: String, Sendable, Codable, Hashable {
        /// Guardado del editor frente a un cambio hecho fuera.
        case edicion
        /// Al arrancar, un fichero no estaba ni como antes ni como lo iba a dejar la app.
        case recuperacion
        /// Versiones en conflicto de iCloud (`NSFileVersion`).
        case icloud
        /// «X 2.md» con el mismo `id` que «X.md».
        case duplicado
    }

    public var id: UUID
    public var tipo: Tipo
    public var ruta: VaultPath
    /// Para duplicados: el fichero repetido («X 2.md»).
    public var otraRuta: VaultPath?
    public var fecha: Date
    /// Título de la tarjeta, en lenguaje llano.
    public var titulo: String
    public var detalle: String
    public var versiones: [ConflictVersion]
    public var plan: UUID?
    public var resuelto: Bool
    public var resolucion: String?

    public init(id: UUID = UUID(), tipo: Tipo, ruta: VaultPath, otraRuta: VaultPath? = nil, fecha: Date = Date(),
                titulo: String, detalle: String, versiones: [ConflictVersion], plan: UUID? = nil) {
        self.id = id; self.tipo = tipo; self.ruta = ruta; self.otraRuta = otraRuta; self.fecha = fecha
        self.titulo = titulo; self.detalle = detalle; self.versiones = versiones; self.plan = plan
        self.resuelto = false; self.resolucion = nil
    }
}

/// Registro de conflictos de una carpeta: `<estado>/conflictos.json` y las copias de cada
/// versión en `<estado>/conflictos/<id>/`. Fuera de la carpeta de la empresa.
public final class ConflictRegistry: Sendable {
    public let directory: URL
    private let lock = NSLock()

    public init(stateDirectory: URL) {
        self.directory = stateDirectory
    }

    var fileURL: URL { directory.appendingPathComponent("conflictos.json") }

    /// Carpeta donde se guardan las versiones de un conflicto.
    public func folder(for id: UUID) -> URL {
        directory.appendingPathComponent("conflictos", isDirectory: true)
            .appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    /// Todos los registros, los más recientes primero.
    public func todos() -> [ConflictRecord] {
        lock.withLock { read() }.sorted { $0.fecha > $1.fecha }
    }

    /// Los que esperan una decisión (las tarjetas).
    public func pendientes() -> [ConflictRecord] {
        todos().filter { !$0.resuelto }
    }

    public func record(_ id: UUID) -> ConflictRecord? {
        lock.withLock { read() }.first { $0.id == id }
    }

    /// Guarda un registro. Un duplicado o conflicto de iCloud ya pendiente para la misma
    /// pareja de rutas no se repite: devuelve el que había.
    @discardableResult
    public func registrar(_ record: ConflictRecord) throws -> ConflictRecord {
        try lock.withLock {
            var all = read()
            if record.tipo == .duplicado || record.tipo == .icloud,
               let same = all.first(where: { !$0.resuelto && $0.tipo == record.tipo && $0.ruta == record.ruta && $0.otraRuta == record.otraRuta }) {
                return same
            }
            all.append(record)
            try write(all)
            return record
        }
    }

    /// Guarda una versión (bytes) de un conflicto y devuelve su ubicación.
    func guardarVersion(_ data: Data, conflicto id: UUID, nombre: String) throws -> ConflictLocation {
        let dir = folder(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent(nombre)
        try data.write(to: url, options: [.atomic])
        return .copia("conflictos/\(id.uuidString.lowercased())/\(nombre)")
    }

    /// Bytes de una versión guardada.
    public func datos(de version: ConflictVersion, root: URL) -> Data? {
        switch version.ubicacion {
        case .carpeta(let p): return try? Data(contentsOf: p.url(in: root))
        case .copia(let rel): return try? Data(contentsOf: directory.appendingPathComponent(rel))
        }
    }

    public func marcarResuelto(_ id: UUID, como resolucion: String) throws {
        try lock.withLock {
            var all = read()
            guard let i = all.firstIndex(where: { $0.id == id }) else { throw WriteError.conflictoNoEncontrado }
            all[i].resuelto = true
            all[i].resolucion = resolucion
            try write(all)
        }
    }

    // MARK: Fichero

    private struct File: Codable {
        var version: Int
        var conflictos: [ConflictRecord]
    }

    private func read() -> [ConflictRecord] {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else { return [] }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode(File.self, from: data).conflictos) ?? []
    }

    private func write(_ all: [ConflictRecord]) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try e.encode(File(version: 1, conflictos: all)).write(to: fileURL, options: [.atomic])
    }
}
