import Foundation
import GRDB

// Tablas del gobierno de los asistentes en `<estado de la carpeta>/estado.sqlite` (PLAN §3.4), con su propia migración
// (`gobierno-1`), sin tocar las del dominio: `auditoria` (cada decisión del Autorizador), `aprobaciones`
// (ApprovalStore), `propuestas` (planes guardados en modo asistido), `config_confirmada` (historial de la
// configuración aceptada, con su SHA-256) y `tarjetas_vistas` (presupuesto de interrupciones).

/// `estado.sqlite` del gobierno de una carpeta. Es el mismo fichero que usa `EstadoDominio`; cada uno con sus tablas.
public final class EstadoGobierno: Sendable {
    public static let fileName = EstadoDominio.fileName

    public let url: URL
    let db: DatabaseQueue

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(Self.fileName)
        var config = Configuration()
        config.label = "TLSGobierno"
        config.busyMode = .timeout(10)
        db = try DatabaseQueue(path: url.path, configuration: config)
        try Self.migrador.migrate(db)
    }

    static var migrador: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("gobierno-1") { db in
            try db.execute(sql: """
                CREATE TABLE auditoria(
                    orden INTEGER PRIMARY KEY AUTOINCREMENT,
                    fecha REAL NOT NULL,
                    autor TEXT NOT NULL,
                    accion TEXT NOT NULL,
                    rutas TEXT NOT NULL,
                    capacidad TEXT,
                    externa TEXT,
                    ejecucion TEXT,
                    plan TEXT,
                    paso INTEGER NOT NULL,
                    decision TEXT NOT NULL,
                    motivo TEXT NOT NULL,
                    resumen INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX auditoria_ejecucion ON auditoria(ejecucion, accion, decision);
                CREATE TABLE aprobaciones(
                    id TEXT PRIMARY KEY NOT NULL,
                    entidad_id TEXT NOT NULL,
                    accion TEXT NOT NULL,
                    herramienta TEXT,
                    ruta TEXT,
                    agente TEXT NOT NULL,
                    ejecucion TEXT,
                    carga TEXT NOT NULL,
                    hash TEXT NOT NULL,
                    estado TEXT NOT NULL,
                    creada REAL NOT NULL,
                    caduca REAL NOT NULL,
                    decidida REAL,
                    decidida_por TEXT,
                    con_cambios INTEGER NOT NULL DEFAULT 0,
                    motivo TEXT,
                    ejecutada REAL,
                    resultado TEXT
                );
                CREATE INDEX aprobaciones_entidad ON aprobaciones(entidad_id, estado);
                CREATE TABLE propuestas(
                    id TEXT PRIMARY KEY NOT NULL,
                    tarea TEXT,
                    agente TEXT NOT NULL,
                    ejecucion TEXT,
                    capacidad TEXT,
                    clase TEXT NOT NULL,
                    descripcion TEXT NOT NULL,
                    plan TEXT NOT NULL,
                    estado TEXT NOT NULL,
                    creada REAL NOT NULL,
                    decidida REAL,
                    decidida_por TEXT,
                    resultado TEXT
                );
                CREATE TABLE config_confirmada(
                    orden INTEGER PRIMARY KEY AUTOINCREMENT,
                    hash TEXT NOT NULL,
                    texto TEXT NOT NULL,
                    fecha REAL NOT NULL,
                    por TEXT NOT NULL
                );
                CREATE TABLE tarjetas_vistas(
                    id TEXT PRIMARY KEY NOT NULL,
                    dia TEXT NOT NULL,
                    roja INTEGER NOT NULL DEFAULT 0,
                    notificada TEXT,
                    descartada TEXT
                );
                """)
        }
        return m
    }

    public func cerrar() { try? db.close() }

    static var codificador: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    // MARK: Auditoría

    /// Una decisión del Autorizador tal como quedó apuntada.
    public struct Apunte: Sendable, Hashable {
        public let orden: Int64
        public let fecha: Date
        public let autor: Autor
        public let accion: String
        public let rutas: [VaultPath]
        public let capacidad: String?
        public let externa: String?
        public let ejecucion: String?
        public let plan: UUID?
        public let paso: Int
        public let decision: String
        public let motivo: String
        /// Modo supervisado: se hizo y va al resumen semanal.
        public let alResumenSemanal: Bool
    }

    @discardableResult
    func apuntar(fecha: Date, autor: Autor, accion: String, rutas: [VaultPath], capacidad: String?, externa: String?,
                 ejecucion: String?, plan: UUID?, paso: Int, decision: String, motivo: String, resumen: Bool = false) throws -> Int64 {
        let rutasJSON = String(decoding: try Self.codificador.encode(rutas.map(\.raw)), as: UTF8.self)
        return try db.write { db in
            try db.execute(sql: """
                INSERT INTO auditoria(fecha, autor, accion, rutas, capacidad, externa, ejecucion, plan, paso, decision, motivo, resumen)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [fecha.timeIntervalSince1970, autor.etiqueta, accion, rutasJSON, capacidad, externa,
                                 ejecucion, plan?.uuidString.lowercased(), paso, decision, motivo, resumen ? 1 : 0])
            return db.lastInsertedRowID
        }
    }

    /// Lo que los asistentes hicieron en modo supervisado desde una fecha (para el resumen semanal).
    public func paraElResumenSemanal(desde: Date) throws -> [Apunte] {
        try auditoria().filter { $0.alResumenSemanal && $0.fecha >= desde && $0.decision == "permitido" }
    }

    /// Lo apuntado, del primero al último (o solo lo de una ejecución).
    public func auditoria(ejecucion: String? = nil) throws -> [Apunte] {
        try db.read { db in
            let rows: [Row]
            if let e = ejecucion {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM auditoria WHERE ejecucion = ? ORDER BY orden", arguments: [e])
            } else {
                rows = try Row.fetchAll(db, sql: "SELECT * FROM auditoria ORDER BY orden")
            }
            return rows.map { r in
                let rutas = (try? JSONDecoder().decode([String].self, from: Data((r["rutas"] as String? ?? "[]").utf8))) ?? []
                return Apunte(orden: r["orden"], fecha: Date(timeIntervalSince1970: r["fecha"]), autor: Autor(etiqueta: r["autor"]),
                              accion: r["accion"], rutas: rutas.map(VaultPath.init), capacidad: r["capacidad"],
                              externa: r["externa"], ejecucion: r["ejecucion"],
                              plan: (r["plan"] as String?).flatMap(UUID.init(uuidString:)), paso: r["paso"],
                              decision: r["decision"], motivo: r["motivo"], alResumenSemanal: (r["resumen"] as Int? ?? 0) != 0)
            }
        }
    }

    /// Cuántas veces se permitió esta acción en una ejecución (tope de tareas por ejecución).
    func permitidas(_ accion: String, ejecucion: String) throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM auditoria WHERE ejecucion = ? AND accion = ? AND decision = 'permitido'",
                             arguments: [ejecucion, accion]) ?? 0
        }
    }

    // MARK: Configuración confirmada

    /// La última versión de `.tls/config.yaml` que aceptó una persona (o la app al escribirla).
    public struct Confirmada: Sendable, Hashable {
        public let hash: String
        public let texto: String
        public let fecha: Date
        public let por: String
    }

    public func configConfirmada() throws -> Confirmada? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM config_confirmada ORDER BY orden DESC LIMIT 1").map {
                Confirmada(hash: $0["hash"], texto: $0["texto"], fecha: Date(timeIntervalSince1970: $0["fecha"]), por: $0["por"])
            }
        }
    }

    /// Guarda una versión confirmada (no se borra el historial). Si ya es la última, no hace nada.
    @discardableResult
    public func confirmarConfig(texto: String, por: String, fecha: Date = Date()) throws -> Confirmada {
        let hash = ContentHash.of(texto)
        if let c = try configConfirmada(), c.hash == hash { return c }
        try db.write { db in
            try db.execute(sql: "INSERT INTO config_confirmada(hash, texto, fecha, por) VALUES (?, ?, ?, ?)",
                           arguments: [hash, texto, fecha.timeIntervalSince1970, por])
        }
        return Confirmada(hash: hash, texto: texto, fecha: fecha, por: por)
    }

    // MARK: Tarjetas vistas

    /// Día en que se vio por primera vez cada tarjeta (lo apunta si es nueva).
    func primeraVez(_ ids: [(id: String, roja: Bool)], hoy: LocalDate) throws -> [String: LocalDate] {
        guard !ids.isEmpty else { return [:] }
        return try db.write { db in
            var out: [String: LocalDate] = [:]
            for (id, roja) in ids {
                try db.execute(sql: "INSERT OR IGNORE INTO tarjetas_vistas(id, dia, roja) VALUES (?, ?, ?)",
                               arguments: [id, hoy.description, roja ? 1 : 0])
                if let d = try String.fetchOne(db, sql: "SELECT dia FROM tarjetas_vistas WHERE id = ?", arguments: [id]),
                   let f = LocalDate(parsing: d) { out[id] = f }
            }
            return out
        }
    }

    /// Notificaciones que no son rojas ya mandadas ese día.
    public func notificadasNoRojas(_ dia: LocalDate) throws -> Int {
        try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tarjetas_vistas WHERE notificada = ? AND roja = 0",
                             arguments: [dia.description]) ?? 0
        }
    }

    /// F4 · corrector (R12): avisos rojos notificados ese día cuyo id empieza por `prefijo` (los de un asistente).
    public func notificadasRojas(_ dia: LocalDate, prefijo: String) throws -> Int {
        let patron = prefijo.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        return try db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tarjetas_vistas WHERE notificada = ? AND roja = 1 AND id LIKE ? ESCAPE '\\'",
                             arguments: [dia.description, patron]) ?? 0
        }
    }

    /// Marca una tarjeta como notificada hoy. `false` si ya lo estaba.
    public func marcarNotificada(_ id: String, roja: Bool, hoy: LocalDate) throws -> Bool {
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tarjetas_vistas(id, dia, roja) VALUES (?, ?, ?)",
                           arguments: [id, hoy.description, roja ? 1 : 0])
            try db.execute(sql: "UPDATE tarjetas_vistas SET notificada = ?, roja = ? WHERE id = ? AND notificada IS NULL",
                           arguments: [hoy.description, roja ? 1 : 0, id])
            return db.changesCount > 0
        }
    }

    /// Una tarjeta que fabrica la app (CRITERIO, permisos) se descarta y no vuelve.
    func descartarTarjeta(_ id: String, hoy: LocalDate) throws {
        try db.write { db in
            try db.execute(sql: "INSERT OR IGNORE INTO tarjetas_vistas(id, dia) VALUES (?, ?)", arguments: [id, hoy.description])
            try db.execute(sql: "UPDATE tarjetas_vistas SET descartada = ? WHERE id = ?", arguments: [hoy.description, id])
        }
    }

    func descartadas() throws -> Set<String> {
        try db.read { db in Set(try String.fetchAll(db, sql: "SELECT id FROM tarjetas_vistas WHERE descartada IS NOT NULL")) }
    }

    public func yaNotificada(_ id: String) throws -> Bool {
        try db.read { db in
            try String.fetchOne(db, sql: "SELECT notificada FROM tarjetas_vistas WHERE id = ?", arguments: [id]) != nil
        }
    }
}
