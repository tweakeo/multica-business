import Foundation
import GRDB
import TLSCore

// Estado del motor de asistentes en `<estado de la carpeta>/estado.sqlite` (PLAN §3.4), el mismo fichero que el
// outbox del dominio y las tablas de gobierno, cada uno con su migración (`agentes-1` es la del motor; nunca se
// tocan las de otros). No es desechable: reiniciar la app con la cola llena no pierde ni duplica nada.
//
// Tablas:
// - `disparos`: clave de idempotencia UNIQUE de cada disparo (y las que se apuntan como «ya vistas» al empezar).
// - `ejecuciones`: la cola y su historia (estado, motivo, intento, sesión, coste, pregunta…).
// - `uso`: lo que cuesta cada ejecución en USD internos (`total_cost_usd`), por asistente y mes.
// - `sesiones`: la sesión de Claude de cada asistente y el hash del brief con el que se abrió.
// - `rutinas_pausadas`: autopausa (≥5 ejecuciones en 7 días y ≥90 % fallos) hasta que la persona la reanude.
// - `motor_valores`: cursores (outbox ya visto, primera pasada hecha…).

/// Una rutina parada por la autopausa.
public struct RutinaPausada: Sendable, Hashable {
    /// `<slug>.<id>`.
    public let rutina: String
    public let agente: String
    public let desde: Date
    public let motivo: String
}

public final class EstadoDelMotor: Sendable {
    public static let fileName = "estado.sqlite"

    public let url: URL
    let db: DatabaseQueue

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(Self.fileName)
        var config = Configuration()
        config.label = "TLSMotor"
        config.busyMode = .timeout(10)
        db = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrador.migrate(db)
    }

    static var migrador: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("agentes-1") { db in
            try db.execute(sql: """
                CREATE TABLE disparos(
                    clave TEXT PRIMARY KEY NOT NULL,
                    tipo TEXT NOT NULL,
                    agente TEXT NOT NULL,
                    tarea TEXT,
                    estado TEXT NOT NULL,
                    ejecucion TEXT,
                    creado REAL NOT NULL
                );
                CREATE TABLE ejecuciones(
                    id TEXT PRIMARY KEY NOT NULL,
                    disparo TEXT NOT NULL,
                    datos TEXT NOT NULL,
                    tipo TEXT NOT NULL,
                    agente TEXT NOT NULL,
                    tarea TEXT,
                    rutina TEXT,
                    estado TEXT NOT NULL,
                    motivo TEXT,
                    nota TEXT,
                    intento INTEGER NOT NULL DEFAULT 0,
                    no_antes REAL,
                    sesion TEXT,
                    sesion_iniciada INTEGER NOT NULL DEFAULT 0,
                    brief_hash TEXT,
                    pregunta TEXT,
                    pid INTEGER,
                    coste_usd REAL NOT NULL DEFAULT 0,
                    resumen TEXT,
                    simulado INTEGER NOT NULL DEFAULT 0,
                    registrada INTEGER NOT NULL DEFAULT 0,
                    orden INTEGER NOT NULL,
                    creada REAL NOT NULL,
                    empezada REAL,
                    terminada REAL
                );
                CREATE INDEX ejecuciones_estado ON ejecuciones(estado, orden);
                CREATE INDEX ejecuciones_tarea ON ejecuciones(tarea);
                CREATE INDEX ejecuciones_rutina ON ejecuciones(rutina, creada);
                CREATE TABLE uso(
                    id TEXT PRIMARY KEY NOT NULL,
                    agente TEXT NOT NULL,
                    mes TEXT NOT NULL,
                    usd REAL NOT NULL,
                    fecha REAL NOT NULL,
                    simulado INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX uso_mes ON uso(mes, agente);
                CREATE TABLE sesiones(
                    agente TEXT PRIMARY KEY NOT NULL,
                    sesion TEXT NOT NULL,
                    brief_hash TEXT NOT NULL,
                    creada REAL NOT NULL
                );
                CREATE TABLE rutinas_pausadas(
                    rutina TEXT PRIMARY KEY NOT NULL,
                    agente TEXT NOT NULL,
                    desde REAL NOT NULL,
                    motivo TEXT NOT NULL
                );
                CREATE TABLE motor_valores(
                    clave TEXT PRIMARY KEY NOT NULL,
                    valor TEXT NOT NULL
                );
                """)
        }
        return m
    }

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    // MARK: Disparos y cola

    /// Apunta el disparo y crea su ejecución (`pendiente`), todo o nada. `nil` si la clave ya estaba: el mismo
    /// hueco de rutina, el mismo evento o la misma versión de la tarea no se ejecutan dos veces.
    public func encolar(_ d: Disparo, id: String = AgentPaths.newRunID(), ahora: Date = Date(),
                        simulado: Bool = false) throws -> Ejecucion? {
        let datos = String(decoding: try Self.codificador.encode(d), as: UTF8.self)
        return try db.write { db -> Ejecucion? in
            try db.execute(sql: """
                INSERT OR IGNORE INTO disparos(clave, tipo, agente, tarea, estado, ejecucion, creado)
                VALUES (?, ?, ?, ?, 'aceptado', ?, ?)
                """, arguments: [d.clave, d.tipo.rawValue, d.agente, d.tarea?.raw, id, ahora.timeIntervalSince1970])
            guard db.changesCount > 0 else { return nil }
            let orden = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(orden), 0) + 1 FROM ejecuciones")) ?? 1
            try db.execute(sql: """
                INSERT INTO ejecuciones(id, disparo, datos, tipo, agente, tarea, rutina, estado, simulado, orden, creada)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'pendiente', ?, ?, ?)
                """, arguments: [id, d.clave, datos, d.tipo.rawValue, d.agente, d.tarea?.raw,
                                 d.rutina.map { "\(d.agente).\($0)" }, simulado ? 1 : 0, orden, ahora.timeIntervalSince1970])
            return Ejecucion(id: id, disparo: d, estado: .pendiente, motivo: nil, nota: nil, intento: 0, noAntes: nil,
                             sesion: nil, sesionIniciada: false, briefHash: nil, pregunta: nil, pid: nil, costeUSD: 0,
                             resumen: nil, simulado: simulado, creada: ahora, empezada: nil, terminada: nil,
                             registrada: false)
        }
    }

    /// Apunta una ejecución que no pasa por la cola (el chat ⌘J), ya en el estado que se diga.
    @discardableResult
    public func apuntarFueraDeCola(_ d: Disparo, id: String, estado: EstadoDeEjecucion, ahora: Date = Date(),
                                   simulado: Bool = false) throws -> Ejecucion {
        let datos = String(decoding: try Self.codificador.encode(d), as: UTF8.self)
        return try db.write { db -> Ejecucion in
            try db.execute(sql: """
                INSERT OR IGNORE INTO disparos(clave, tipo, agente, tarea, estado, ejecucion, creado)
                VALUES (?, ?, ?, ?, 'aceptado', ?, ?)
                """, arguments: [d.clave, d.tipo.rawValue, d.agente, d.tarea?.raw, id, ahora.timeIntervalSince1970])
            let orden = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(orden), 0) + 1 FROM ejecuciones")) ?? 1
            try db.execute(sql: """
                INSERT INTO ejecuciones(id, disparo, datos, tipo, agente, tarea, rutina, estado, simulado, registrada, orden,
                                        creada, empezada)
                VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?)
                """, arguments: [id, d.clave, datos, d.tipo.rawValue, d.agente, d.tarea?.raw, estado.rawValue,
                                 simulado ? 1 : 0, orden, ahora.timeIntervalSince1970, ahora.timeIntervalSince1970])
            return Ejecucion(id: id, disparo: d, estado: estado, motivo: nil, nota: nil, intento: 0, noAntes: nil, sesion: nil,
                             sesionIniciada: false, briefHash: nil, pregunta: nil, pid: nil, costeUSD: 0, resumen: nil,
                             simulado: simulado, creada: ahora, empezada: ahora, terminada: nil, registrada: true)
        }
    }

    /// Apunta claves como ya vistas sin crear ejecución (primera pasada: menciones y eventos de antes no disparan).
    public func apuntarVistos(_ ds: [Disparo], ahora: Date = Date()) throws {
        guard !ds.isEmpty else { return }
        try db.write { db in
            for d in ds {
                try db.execute(sql: """
                    INSERT OR IGNORE INTO disparos(clave, tipo, agente, tarea, estado, ejecucion, creado)
                    VALUES (?, ?, ?, ?, 'visto', NULL, ?)
                    """, arguments: [d.clave, d.tipo.rawValue, d.agente, d.tarea?.raw, ahora.timeIntervalSince1970])
            }
        }
    }

    public func existeDisparo(_ clave: String) throws -> Bool {
        try db.read { db in try Bool.fetchOne(db, sql: "SELECT 1 FROM disparos WHERE clave = ?", arguments: [clave]) ?? false }
    }

    public func numeroDeDisparos() throws -> Int {
        try db.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM disparos") ?? 0 }
    }

    // MARK: Ejecuciones

    public func ejecucion(_ id: String) throws -> Ejecucion? {
        try db.read { db in try Row.fetchOne(db, sql: "SELECT * FROM ejecuciones WHERE id = ?", arguments: [id]).flatMap(Self.ejecucion) }
    }

    /// Ejecuciones (las más recientes primero), filtradas por estado y asistente.
    public func ejecuciones(estados: [EstadoDeEjecucion]? = nil, agente: String? = nil, limite: Int = 500) throws -> [Ejecucion] {
        var sql = "SELECT * FROM ejecuciones WHERE 1"
        var args: [(any DatabaseValueConvertible)?] = []
        if let estados, !estados.isEmpty {
            sql += " AND estado IN (\(estados.map { _ in "?" }.joined(separator: ",")))"
            args += estados.map(\.rawValue)
        }
        if let agente { sql += " AND agente = ?"; args.append(agente) }
        sql += " ORDER BY orden DESC LIMIT ?"
        args.append(limite)
        let argumentos = StatementArguments(args)
        return try db.read { db in try Row.fetchAll(db, sql: sql, arguments: argumentos).compactMap(Self.ejecucion) }
    }

    /// La cola en orden de llegada: pendientes y en cola.
    public func enEspera() throws -> [Ejecucion] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ejecuciones WHERE estado IN ('pendiente', 'en_cola') ORDER BY orden")
                .compactMap(Self.ejecucion)
        }
    }

    /// Ejecución abierta (no final) de una tarea: mientras exista no se dispara otra para la misma tarea.
    public func abierta(tarea: VaultPath) throws -> Ejecucion? {
        try db.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM ejecuciones WHERE tarea = ? AND estado IN ('pendiente', 'en_cola', 'en_curso', 'esperando_respuesta')
                ORDER BY orden DESC LIMIT 1
                """, arguments: [tarea.raw]).flatMap(Self.ejecucion)
        }
    }

    /// La que espera la respuesta a esta pregunta (ruta de la ficha de pregunta o su id).
    public func esperando(pregunta: String) throws -> Ejecucion? {
        try db.read { db in
            try Row.fetchOne(db, sql: """
                SELECT * FROM ejecuciones WHERE estado = 'esperando_respuesta' AND pregunta = ? ORDER BY orden DESC LIMIT 1
                """, arguments: [pregunta]).flatMap(Self.ejecucion)
        }
    }

    public func guardar(_ e: Ejecucion) throws {
        try db.write { db in
            try db.execute(sql: """
                UPDATE ejecuciones SET estado = ?, motivo = ?, nota = ?, intento = ?, no_antes = ?, sesion = ?,
                    sesion_iniciada = ?, brief_hash = ?, pregunta = ?, pid = ?, coste_usd = ?, resumen = ?, registrada = ?,
                    empezada = ?, terminada = ?
                WHERE id = ?
                """, arguments: [e.estado.rawValue, e.motivo?.rawValue, e.nota, e.intento, e.noAntes?.timeIntervalSince1970,
                                 e.sesion?.uuidString.lowercased(), e.sesionIniciada ? 1 : 0, e.briefHash, e.pregunta,
                                 e.pid.map { Int($0) }, e.costeUSD, e.resumen, e.registrada ? 1 : 0,
                                 e.empezada?.timeIntervalSince1970, e.terminada?.timeIntervalSince1970, e.id])
        }
    }

    /// Ejecuciones de una rutina (`<slug>.<id>`) creadas desde `desde`.
    public func ejecuciones(rutina: String, desde: Date) throws -> [Ejecucion] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM ejecuciones WHERE rutina = ? AND creada >= ? ORDER BY orden",
                             arguments: [rutina, desde.timeIntervalSince1970]).compactMap(Self.ejecucion)
        }
    }

    /// Terminadas y aún sin apuntar en la Actividad (la app se cerró justo al acabar).
    public func sinRegistrar() throws -> [Ejecucion] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM ejecuciones WHERE registrada = 0 AND estado IN ('completada', 'fallida', 'cancelada', 'esperando_respuesta')
                ORDER BY orden
                """).compactMap(Self.ejecucion)
        }
    }

    /// Lo próximo que hay que mirar: el `no_antes` más cercano de lo pendiente.
    public func proximoNoAntes() throws -> Date? {
        try db.read { db in
            try Double.fetchOne(db, sql: "SELECT MIN(no_antes) FROM ejecuciones WHERE estado = 'pendiente' AND no_antes IS NOT NULL")
                .map { Date(timeIntervalSince1970: $0) }
        }
    }

    static func ejecucion(_ r: Row) -> Ejecucion? {
        let datos: String = r["datos"]
        guard let d = try? JSONDecoder().decode(Disparo.self, from: Data(datos.utf8)),
              let estado = EstadoDeEjecucion(rawValue: r["estado"]) else { return nil }
        let motivo: String? = r["motivo"]
        let sesion: String? = r["sesion"]
        let noAntes: Double? = r["no_antes"]
        let empezada: Double? = r["empezada"]
        let terminada: Double? = r["terminada"]
        let pid: Int? = r["pid"]
        return Ejecucion(id: r["id"], disparo: d, estado: estado, motivo: motivo.flatMap(FailureReason.init(rawValue:)),
                         nota: r["nota"], intento: r["intento"], noAntes: noAntes.map(Date.init(timeIntervalSince1970:)),
                         sesion: sesion.flatMap(UUID.init(uuidString:)), sesionIniciada: (r["sesion_iniciada"] as Int) != 0,
                         briefHash: r["brief_hash"], pregunta: r["pregunta"], pid: pid.map { Int32($0) },
                         costeUSD: r["coste_usd"], resumen: r["resumen"], simulado: (r["simulado"] as Int) != 0,
                         creada: Date(timeIntervalSince1970: r["creada"]), empezada: empezada.map(Date.init(timeIntervalSince1970:)),
                         terminada: terminada.map(Date.init(timeIntervalSince1970:)), registrada: (r["registrada"] as Int) != 0)
    }

    // MARK: Uso

    public func apuntarUso(ejecucion: String, agente: String, mes: String, usd: Double, fecha: Date, simulado: Bool) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO uso(id, agente, mes, usd, fecha, simulado) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET usd = excluded.usd, fecha = excluded.fecha
                """, arguments: [ejecucion, agente, mes, usd, fecha.timeIntervalSince1970, simulado ? 1 : 0])
        }
    }

    /// USD del mes (`AAAA-MM`), de un asistente o de todos.
    public func uso(mes: String, agente: String? = nil, incluirSimulado: Bool = false) throws -> Double {
        var sql = "SELECT COALESCE(SUM(usd), 0) FROM uso WHERE mes = ?"
        var args: [(any DatabaseValueConvertible)?] = [mes]
        if let agente { sql += " AND agente = ?"; args.append(agente) }
        if !incluirSimulado { sql += " AND simulado = 0" }
        let argumentos = StatementArguments(args)
        return try db.read { db in try Double.fetchOne(db, sql: sql, arguments: argumentos) ?? 0 }
    }

    // MARK: Sesiones

    public func sesion(agente: String) throws -> (sesion: UUID, briefHash: String, creada: Date)? {
        try db.read { db in
            guard let r = try Row.fetchOne(db, sql: "SELECT * FROM sesiones WHERE agente = ?", arguments: [agente]),
                  let id = UUID(uuidString: r["sesion"]) else { return nil }
            return (id, r["brief_hash"], Date(timeIntervalSince1970: r["creada"]))
        }
    }

    public func guardarSesion(agente: String, sesion: UUID, briefHash: String, creada: Date) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO sesiones(agente, sesion, brief_hash, creada) VALUES (?, ?, ?, ?)
                ON CONFLICT(agente) DO UPDATE SET sesion = excluded.sesion, brief_hash = excluded.brief_hash, creada = excluded.creada
                """, arguments: [agente, sesion.uuidString.lowercased(), briefHash, creada.timeIntervalSince1970])
        }
    }

    public func olvidarSesion(agente: String) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM sesiones WHERE agente = ?", arguments: [agente]) }
    }

    // MARK: Autopausa

    public func pausar(rutina: String, agente: String, motivo: String, desde: Date) throws {
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO rutinas_pausadas(rutina, agente, desde, motivo) VALUES (?, ?, ?, ?)",
                           arguments: [rutina, agente, desde.timeIntervalSince1970, motivo])
        }
    }

    /// La persona la reanuda (desde la tarjeta o la pantalla de Asistentes).
    public func reanudar(rutina: String) throws {
        try db.write { db in try db.execute(sql: "DELETE FROM rutinas_pausadas WHERE rutina = ?", arguments: [rutina]) }
    }

    public func rutinasPausadas() throws -> [RutinaPausada] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM rutinas_pausadas ORDER BY desde").map {
                RutinaPausada(rutina: $0["rutina"], agente: $0["agente"], desde: Date(timeIntervalSince1970: $0["desde"]),
                              motivo: $0["motivo"])
            }
        }
    }

    public func estaPausada(rutina: String) throws -> Bool {
        try db.read { db in
            try Bool.fetchOne(db, sql: "SELECT 1 FROM rutinas_pausadas WHERE rutina = ?", arguments: [rutina]) ?? false
        }
    }

    // MARK: Valores

    public func valor(_ clave: String) throws -> String? {
        try db.read { db in try String.fetchOne(db, sql: "SELECT valor FROM motor_valores WHERE clave = ?", arguments: [clave]) }
    }

    public func poner(_ clave: String, _ valor: String) throws {
        try db.write { db in
            try db.execute(sql: "INSERT INTO motor_valores(clave, valor) VALUES (?, ?) ON CONFLICT(clave) DO UPDATE SET valor = excluded.valor",
                           arguments: [clave, valor])
        }
    }

    public func cerrar() { try? db.close() }
}
