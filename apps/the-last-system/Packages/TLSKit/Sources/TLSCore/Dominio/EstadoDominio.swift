import Foundation
import GRDB

// Estado del dominio fuera de la carpeta (PLAN §3.4): `<estado de la carpeta>/estado.sqlite`, en el mismo directorio
// que usa el escritor (`VaultWriter.stateDirectory`). No es desechable: guarda la bandeja de salida (outbox) de los
// eventos y lo que cada regla ya hizo, con claves únicas, para que nada se procese dos veces aunque la app se cierre
// a mitad. Otras fases añaden sus tablas con migraciones propias (`DatabaseMigrator`), nunca cambiando estas.

/// Cómo quedó un evento de la bandeja de salida.
public enum EstadoEvento: String, Sendable, Hashable, Codable {
    /// Aún no lo han mirado las reglas.
    case pendiente
    /// Las reglas ya lo procesaron.
    case procesado
    /// No dispara nada: modo importación o cadena demasiado larga.
    case omitido
    /// Una regla falló (se reintenta al volver a procesar).
    case fallido
    /// La persona deshizo el plan que lo dio (integración F2): ya no cuenta, y si lo vuelve a hacer, sale de nuevo.
    case deshecho
}

/// Un evento guardado en la bandeja de salida.
public struct EventoGuardado: Sendable, Hashable {
    public let evento: EventoDominio
    public let estado: EstadoEvento
    /// Por qué se omitió o falló.
    public let motivo: String?
    public let creado: Date
}

/// Lo que una regla hizo con un evento (una fila por regla y evento).
public struct ReglaAplicada: Sendable, Hashable {
    public let clave: String
    public let regla: String
    public let evento: String
    public let resultado: String
    public let plan: UUID?
    public let fecha: Date
}

/// `estado.sqlite` de una carpeta: outbox de eventos e idempotencia de las reglas.
public final class EstadoDominio: Sendable {
    public static let fileName = "estado.sqlite"

    public let url: URL
    let db: DatabaseQueue

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(Self.fileName)
        var config = Configuration()
        config.label = "TLSEstado"
        config.busyMode = .timeout(10)
        db = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrador.migrate(db)
    }

    static var migrador: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("dominio-1") { db in
            try db.execute(sql: """
                CREATE TABLE outbox(
                    clave TEXT PRIMARY KEY NOT NULL,
                    tipo TEXT NOT NULL,
                    entidad TEXT NOT NULL,
                    ruta TEXT NOT NULL,
                    carga TEXT NOT NULL,
                    autor TEXT NOT NULL,
                    profundidad INTEGER NOT NULL,
                    plan TEXT,
                    estado TEXT NOT NULL,
                    motivo TEXT,
                    creado REAL NOT NULL,
                    procesado REAL,
                    orden INTEGER NOT NULL
                );
                CREATE INDEX outbox_estado ON outbox(estado, orden);
                CREATE TABLE reglas_aplicadas(
                    clave TEXT PRIMARY KEY NOT NULL,
                    regla TEXT NOT NULL,
                    evento TEXT NOT NULL,
                    resultado TEXT NOT NULL,
                    plan TEXT,
                    fecha REAL NOT NULL
                );
                """)
        }
        return m
    }

    // MARK: Outbox

    /// Mete un evento en la bandeja de salida. Si ya había uno con esa clave, no hace nada y devuelve `false`
    /// (idempotencia: un cobro, un proyecto, una oportunidad ganada… se procesan una sola vez).
    @discardableResult
    public func encolar(_ e: EventoDominio, estado: EstadoEvento = .pendiente, motivo: String? = nil, ahora: Date = Date()) throws -> Bool {
        let carga = String(decoding: try Self.codificador.encode(e.carga), as: UTF8.self)
        return try db.write { db in
            let orden = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(orden), 0) + 1 FROM outbox")) ?? 1
            try db.execute(sql: """
                INSERT OR IGNORE INTO outbox(clave, tipo, entidad, ruta, carga, autor, profundidad, plan, estado, motivo, creado, orden)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [e.clave, e.tipo.rawValue, e.entidad, e.ruta.raw, carga, e.autor.etiqueta, e.profundidad,
                                 e.plan?.uuidString.lowercased(), estado.rawValue, motivo, ahora.timeIntervalSince1970, orden])
            return db.changesCount > 0
        }
    }

    /// Eventos aún sin procesar (y los que fallaron), en el orden en que llegaron.
    public func pendientes() throws -> [EventoDominio] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM outbox WHERE estado IN ('pendiente', 'fallido') ORDER BY orden").compactMap(Self.evento)
        }
    }

    public func marcar(_ clave: String, _ estado: EstadoEvento, motivo: String? = nil, ahora: Date = Date()) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE outbox SET estado = ?, motivo = ?, procesado = ? WHERE clave = ?",
                           arguments: [estado.rawValue, motivo, ahora.timeIntervalSince1970, clave])
        }
    }

    /// Todos los eventos guardados, del primero al último.
    public func eventos() throws -> [EventoGuardado] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM outbox ORDER BY orden").compactMap { r in
                guard let e = Self.evento(r) else { return nil }
                return EventoGuardado(evento: e, estado: EstadoEvento(rawValue: r["estado"]) ?? .pendiente, motivo: r["motivo"],
                                      creado: Date(timeIntervalSince1970: r["creado"]))
            }
        }
    }

    public func evento(_ clave: String) throws -> EventoGuardado? {
        try eventos().first { $0.evento.clave == clave }
    }

    static func evento(_ r: Row) -> EventoDominio? {
        guard let tipo = TipoEvento(rawValue: r["tipo"]) else { return nil }
        let carga = (try? JSONDecoder().decode([String: String].self, from: Data((r["carga"] as String? ?? "{}").utf8))) ?? [:]
        let plan = (r["plan"] as String?).flatMap(UUID.init(uuidString:))
        return EventoDominio(tipo: tipo, entidad: r["entidad"], ruta: VaultPath(r["ruta"] as String), carga: carga,
                             autor: Autor(etiqueta: r["autor"]), profundidad: r["profundidad"], plan: plan)
    }

    // MARK: Reglas

    /// ¿Esta regla ya hizo su trabajo con esta clave?
    public func yaAplicada(_ clave: String) throws -> Bool {
        try db.read { db in try Int.fetchOne(db, sql: "SELECT 1 FROM reglas_aplicadas WHERE clave = ?", arguments: [clave]) != nil }
    }

    /// Apunta que una regla terminó con un evento. `false` si ya estaba apuntada.
    @discardableResult
    public func apuntar(_ clave: String, regla: String, evento: String, resultado: String, plan: UUID?, ahora: Date = Date()) throws -> Bool {
        try db.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO reglas_aplicadas(clave, regla, evento, resultado, plan, fecha) VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [clave, regla, evento, resultado, plan?.uuidString.lowercased(), ahora.timeIntervalSince1970])
            return db.changesCount > 0
        }
    }

    public func reglasAplicadas() throws -> [ReglaAplicada] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM reglas_aplicadas ORDER BY fecha, clave").map { r in
                ReglaAplicada(clave: r["clave"], regla: r["regla"], evento: r["evento"], resultado: r["resultado"],
                              plan: (r["plan"] as String?).flatMap(UUID.init(uuidString:)), fecha: Date(timeIntervalSince1970: r["fecha"]))
            }
        }
    }

    /// La persona deshizo estos planes (el suyo y los de las reglas de su cadena): sus eventos pasan a `deshecho` y lo
    /// que las reglas apuntaron por ellos deja de contar, para que, si vuelve a hacerlo, las reglas lo atiendan otra
    /// vez (un cobro confirmado, deshecho y confirmado de nuevo, vuelve a dar Ganada y su proyecto). No se borra nada:
    /// las claves viejas se guardan con la marca `#deshecho:<id>`. Devuelve cuántos eventos dejaron de contar.
    @discardableResult
    public func olvidar(planes: [UUID], ahora: Date = Date()) throws -> Int {
        let ids = planes.map { $0.uuidString.lowercased() }
        guard !ids.isEmpty else { return 0 }
        let marca = "#deshecho:" + UUID().uuidString.lowercased()
        let huecos = Array(repeating: "?", count: ids.count).joined(separator: ", ")
        return try db.write { db in
            let claves = try String.fetchAll(db, sql: "SELECT clave FROM outbox WHERE plan IN (\(huecos))",
                                             arguments: StatementArguments(ids))
            let deEventos = claves.isEmpty ? "" : " OR evento IN (\(Array(repeating: "?", count: claves.count).joined(separator: ", ")))"
            try db.execute(sql: "UPDATE reglas_aplicadas SET clave = clave || ? WHERE plan IN (\(huecos))" + deEventos,
                           arguments: StatementArguments([marca] + ids + claves))
            var argumentos: [(any DatabaseValueConvertible)?] = [marca, EstadoEvento.deshecho.rawValue, "La persona lo deshizo.",
                                                                ahora.timeIntervalSince1970]
            argumentos.append(contentsOf: ids.map { $0 as (any DatabaseValueConvertible)? })
            try db.execute(sql: "UPDATE outbox SET clave = clave || ?, estado = ?, motivo = ?, procesado = ? WHERE plan IN (\(huecos))",
                           arguments: StatementArguments(argumentos))
            return claves.count
        }
    }

    public func cerrar() { try? db.close() }

    static var codificador: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

