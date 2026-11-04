import Darwin
import Foundation

/// Paso de un plan tal como queda en el diario.
struct JournalStep: Sendable, Hashable, Codable {
    var accion: String          // escribir | crear | mover | renombrar | retirar
    var ruta: String
    var destino: String?
    /// Huella antes del paso (`carpeta` si es una carpeta; ausente = no existía).
    var base: String?
    /// Huella después del paso.
    var resultante: String?
    /// Bytes a escribir: fichero relativo a la carpeta de estado.
    var contenido: String?
    /// Nombre intermedio (renombrar solo mayúsculas).
    var intermedio: String?
}

/// Un plan en el diario: lo que se iba a hacer, cómo estaba cada fichero antes y cómo quedará.
struct JournalPlan: Sendable, Codable {
    var tipo = "plan"
    var id: String
    var fecha: String
    var autor: String
    var descripcion: String
    /// Resumen legible de cada operación.
    var ops: [String]
    var pasos: [JournalStep]
    var base_hashes: [String: String]
    var hash_resultante: [String: String]
    /// Pasos que deshacen el plan (copia previa incluida).
    var inverso: [JournalStep]
    /// Si este plan deshace otro, cuál.
    var deshace: String?
    /// Carpeta de la copia previa (relativa a la carpeta de estado).
    var copias: String?
    /// Carpetas que creó el plan (deshacer las quita si quedan vacías).
    var carpetas: [String]? = nil
    var estado = "pendiente"
}

/// Cambio de estado de un plan: hecho, revertido, conflicto, abandonado.
struct JournalMark: Sendable, Codable {
    var tipo = "estado"
    var id: String
    var estado: String
    var fecha: String
    var detalle: String?
}

/// Huellas de lo que escribió la app, guardadas al compactar el diario.
struct JournalSnapshot: Sendable, Codable {
    var tipo = "huellas"
    var fecha: String
    var hashes: [String: String]
}

/// Diario de escrituras: `<estado>/diario.jsonl`, solo se añade (con `fsync` en cada línea).
/// Los bytes que se van a escribir esperan en `<estado>/diario/<plan>/` hasta que el plan acaba.
final class WriteJournal {
    let directory: URL
    var url: URL { directory.appendingPathComponent("diario.jsonl") }
    var stagingRoot: URL { directory.appendingPathComponent("diario", isDirectory: true) }

    /// Plan con su estado final (el último que se apuntó).
    struct Entry {
        var plan: JournalPlan
        var estado: String
        var fecha: String
    }

    init(directory: URL) {
        self.directory = directory
    }

    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    static func stamp(_ date: Date) -> String { formatter().string(from: date) }

    static func date(_ text: String) -> Date? { formatter().date(from: text) }

    // MARK: Escritura

    func append<T: Encodable>(_ value: T) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try enc.encode(value)
        line.append(0x0A)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(url.path, O_RDWR | O_CREAT | O_APPEND, 0o600)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        // Una línea cortada (el proceso murió a mitad) no debe pegarse a la siguiente.
        var st = stat()
        if fstat(fd, &st) == 0, st.st_size > 0 {
            var last: UInt8 = 0
            if pread(fd, &last, 1, st.st_size - 1) == 1, last != 0x0A {
                var nl: UInt8 = 0x0A
                _ = write(fd, &nl, 1)
            }
        }
        try line.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                offset += n
            }
        }
        try AtomicFiles.fullSync(fd)
    }

    func mark(_ id: UUID, _ estado: String, detalle: String? = nil, now: Date) throws {
        try append(JournalMark(id: id.uuidString.lowercased(), estado: estado, fecha: Self.stamp(now), detalle: detalle))
    }

    /// Guarda los bytes de un paso hasta que el plan termine. Devuelve la ruta relativa.
    func stage(_ data: Data, plan: UUID, step: Int) throws -> String {
        let dir = stagingRoot.appendingPathComponent(plan.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let name = "\(step).dat"
        let file = dir.appendingPathComponent(name)
        _ = FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: data)
        try AtomicFiles.fullSync(handle.fileDescriptor)
        return "diario/\(plan.uuidString.lowercased())/\(name)"
    }

    func removeStaging(_ plan: UUID) {
        try? FileManager.default.removeItem(at: stagingRoot.appendingPathComponent(plan.uuidString.lowercased(), isDirectory: true))
    }

    // MARK: Lectura

    struct Contents {
        var entries: [Entry]
        var snapshot: [String: String]
        var lineCount: Int
    }

    /// Lee el diario. Las líneas que no se entienden (cortadas) se ignoran.
    func read() -> Contents {
        guard let data = FileManager.default.contents(atPath: url.path) else {
            return Contents(entries: [], snapshot: [:], lineCount: 0)
        }
        let dec = JSONDecoder()
        var order: [String] = []
        var plans: [String: Entry] = [:]
        var snapshot: [String: String] = [:]
        var count = 0
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            count += 1
            guard let head = try? dec.decode(Head.self, from: line) else { continue }
            switch head.tipo {
            case "plan":
                guard let p = try? dec.decode(JournalPlan.self, from: line) else { continue }
                if plans[p.id] == nil { order.append(p.id) }
                plans[p.id] = Entry(plan: p, estado: p.estado, fecha: p.fecha)
            case "estado":
                guard let m = try? dec.decode(JournalMark.self, from: line), plans[m.id] != nil else { continue }
                plans[m.id]?.estado = m.estado
            case "huellas":
                if let s = try? dec.decode(JournalSnapshot.self, from: line) { snapshot = s.hashes }
            default:
                continue
            }
        }
        return Contents(entries: order.compactMap { plans[$0] }, snapshot: snapshot, lineCount: count)
    }

    private struct Head: Decodable { var tipo: String }

    /// Reescribe el diario con una foto de las huellas y los últimos `keep` planes.
    func compact(snapshot: [String: String], keep: [Entry], now: Date) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var out = Data()
        out.append(try enc.encode(JournalSnapshot(fecha: Self.stamp(now), hashes: snapshot)))
        out.append(0x0A)
        for e in keep {
            var p = e.plan
            p.estado = "pendiente"
            out.append(try enc.encode(p)); out.append(0x0A)
            if e.estado != "pendiente" {
                out.append(try enc.encode(JournalMark(id: p.id, estado: e.estado, fecha: e.fecha)))
                out.append(0x0A)
            }
        }
        let tmp = directory.appendingPathComponent("diario.jsonl.nuevo")
        try out.write(to: tmp, options: [.atomic])
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}
