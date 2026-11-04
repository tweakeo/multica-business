import Foundation
import GRDB
import TLSAgents
import TLSCore

/// El correo recogido, **fuera de la carpeta**: `<Application Support>/<vault-id>/correo/AAAA-MM-DD.jsonl` (un fichero por
/// día de llegada, una línea por correo, solo se añade, permisos 0600). Es la `FuenteDeCorreo` de `tls-mcp`.
public final class AlmacenDeCorreo: FuenteDeCorreo, @unchecked Sendable {
    /// `<estado>/correo`.
    public let carpeta: URL
    public let zona: TimeZone
    /// Los ajustes de **ahora** (S3): lo privado se vuelve a aplicar al leer, por si se marcó después de recoger.
    let ajustes: @Sendable () -> AjustesDeCorreo
    private let lock = NSLock()

    public init(estado: URL, zona: TimeZone = .current, ajustes: (@Sendable () -> AjustesDeCorreo)? = nil) {
        carpeta = estado.appendingPathComponent("correo", isDirectory: true)
        self.zona = zona
        self.ajustes = ajustes ?? { AjustesDeCorreo.leer(estado) }
    }

    /// Reescribe lo guardado con lo privado de `ajustes` (al guardar los ajustes): de un remitente que ahora es privado
    /// solo quedan sus metadatos. Devuelve cuántos correos se han depurado.
    @discardableResult
    public func depurar(con ajustes: AjustesDeCorreo) throws -> Int {
        try lock.withLock {
            var cambiados = 0
            for dia in dias() {
                let url = fichero(dia)
                let antes = Self.leerFichero(url)
                let despues = antes.map { FiltroDePrivacidad.aplicar($0, ajustes: ajustes) }
                let n = zip(antes, despues).filter { $0 != $1 }.count
                guard n > 0 else { continue }
                var datos = Data()
                for m in despues {
                    datos.append(try Self.codificador.encode(m))
                    datos.append(0x0A)
                }
                try datos.write(to: url, options: [.atomic])
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                cambiados += n
            }
            return cambiados
        }
    }

    static func crearCarpeta(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// `AAAA-MM-DD.jsonl` del día.
    public func fichero(_ dia: LocalDate) -> URL {
        carpeta.appendingPathComponent(dia.description + ".jsonl")
    }

    /// Guarda los que no estén ya (por `Message-ID`). Devuelve los nuevos.
    @discardableResult
    public func guardar(_ mensajes: [MensajeDeCorreo]) throws -> [MensajeDeCorreo] {
        try lock.withLock {
            try Self.crearCarpeta(carpeta)
            var nuevos: [MensajeDeCorreo] = []
            let porDia = Dictionary(grouping: mensajes) { $0.dia(zona) }
            for dia in porDia.keys.sorted() {
                let url = fichero(dia)
                var vistos = Set(Self.leerFichero(url).map(\.id))
                var lineas = Data()
                for m in porDia[dia]!.sorted(by: { $0.fecha < $1.fecha }) where !vistos.contains(m.id) {
                    vistos.insert(m.id)
                    lineas.append(try Self.codificador.encode(m))
                    lineas.append(0x0A)
                    nuevos.append(m)
                }
                guard !lineas.isEmpty else { continue }
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
                }
                let h = try FileHandle(forWritingTo: url)
                defer { try? h.close() }
                try h.seekToEnd()
                try h.write(contentsOf: lineas)
            }
            return nuevos
        }
    }

    static func leerFichero(_ url: URL) -> [MensajeDeCorreo] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        return d.split(separator: 0x0A).compactMap { try? decodificador.decode(MensajeDeCorreo.self, from: Data($0)) }
    }

    /// Todos los días guardados.
    public func dias() -> [LocalDate] {
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        return nombres.filter { $0.hasSuffix(".jsonl") }
            .compactMap { LocalDate(parsing: String($0.dropLast(".jsonl".count)), timeZone: zona) }.sorted()
    }

    // MARK: FuenteDeCorreo

    public func mensajes(desde: Date, hasta: Date) async -> [MensajeDeCorreo] {
        let d0 = LocalDate(date: desde, timeZone: zona), d1 = LocalDate(date: hasta, timeZone: zona)
        let a = ajustes()
        return lock.withLock {
            dias().filter { $0 >= d0 && $0 <= d1 }.flatMap { Self.leerFichero(fichero($0)) }
                .filter { $0.fecha >= desde && $0.fecha <= hasta }.sorted { $0.fecha < $1.fecha }
        }.map { FiltroDePrivacidad.aplicar($0, ajustes: a) }
    }

    public func mensaje(_ id: String) async -> MensajeDeCorreo? {
        let a = ajustes()
        let m: MensajeDeCorreo? = lock.withLock {
            for d in dias().reversed() {
                if let m = Self.leerFichero(fichero(d)).first(where: { $0.es(id) }) { return m }
            }
            return nil
        }
        return m.map { FiltroDePrivacidad.aplicar($0, ajustes: a) }
    }
}

/// `estado.sqlite.cursor_correo`: hasta dónde se ha leído cada cuenta (`dateReceived` del último correo guardado).
/// Migración propia (`correo-1`), sin tocar las tablas del dominio ni del gobierno.
public final class CursorDeCorreo: Sendable {
    public let url: URL
    let db: DatabaseQueue

    public init(estado: URL) throws {
        try FileManager.default.createDirectory(at: estado, withIntermediateDirectories: true)
        url = estado.appendingPathComponent(EstadoDominio.fileName)
        var config = Configuration()
        config.label = "TLSCorreo"
        config.busyMode = .timeout(10)
        db = try DatabaseQueue(path: url.path, configuration: config)
        var m = DatabaseMigrator()
        m.registerMigration("correo-1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS cursor_correo(
                    cuenta TEXT PRIMARY KEY NOT NULL,
                    fecha REAL NOT NULL,
                    actualizado REAL NOT NULL
                );
                """)
        }
        try m.migrate(db)
    }

    public func leer(_ cuenta: String) throws -> Date? {
        try db.read { db in
            try Double.fetchOne(db, sql: "SELECT fecha FROM cursor_correo WHERE cuenta = ?", arguments: [cuenta])
                .map { Date(timeIntervalSince1970: $0) }
        }
    }

    /// Solo avanza (nunca vuelve atrás).
    public func avanzar(_ cuenta: String, a fecha: Date, ahora: Date = Date()) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO cursor_correo(cuenta, fecha, actualizado) VALUES (?, ?, ?)
                ON CONFLICT(cuenta) DO UPDATE SET fecha = MAX(fecha, excluded.fecha), actualizado = excluded.actualizado
                """, arguments: [cuenta, fecha.timeIntervalSince1970, ahora.timeIntervalSince1970])
        }
    }
}
