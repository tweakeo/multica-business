import Foundation
import GRDB
import TLSCore

// `estado.sqlite.mapa_calendario` (PLAN §3.4): qué evento del Calendario corresponde a cada ficha (`tls://<tipo>/<id>`),
// con la huella de **lo que escribió la app** (para saber si Manu lo cambió en Calendario) y el día desde el que se
// apuntó cada ritual (para que el inicio de la serie no se mueva). Mismo fichero que `EstadoDominio` y
// `EstadoGobierno`, con su propia migración (`calendario-1`) y sin tocar sus tablas. Nunca se borra una fila:
// retirar deja la fecha en `retirado`.

/// Una fila del mapa.
public struct FilaMapaCalendario: Sendable, Hashable {
    public let clave: String
    public var tipo: String
    public var ruta: VaultPath?
    /// Sesión: la celda «Sesión» de su fila del Viaje.
    public var celda: String?
    public var eventoID: String?
    public var calendarioID: String?
    /// Huella (`HuellaEvento`) de lo último que escribió la app (o que Manu aceptó pasar a la ficha).
    public var huella: String?
    public var ancla: LocalDate?
    public var actualizado: Date
    public var retirado: Date?

    public init(clave: String, tipo: String, ruta: VaultPath? = nil, celda: String? = nil, eventoID: String? = nil,
                calendarioID: String? = nil, huella: String? = nil, ancla: LocalDate? = nil, actualizado: Date = Date(),
                retirado: Date? = nil) {
        self.clave = clave; self.tipo = tipo; self.ruta = ruta; self.celda = celda; self.eventoID = eventoID
        self.calendarioID = calendarioID; self.huella = huella; self.ancla = ancla; self.actualizado = actualizado
        self.retirado = retirado
    }

    public var activa: Bool { retirado == nil }
}

public final class MapaCalendario: Sendable {
    /// La fila que guarda nuestro calendario («The Last System»).
    public static let claveCalendario = "tls://calendario/propio"

    let db: DatabaseQueue

    /// - Parameter directory: el estado de la carpeta (`<vault-id>/`); `nil` = en memoria (pruebas).
    public init(directory: URL?) throws {
        var config = Configuration()
        config.label = "TLSCalendario"
        config.busyMode = .timeout(10)
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            db = try DatabaseQueue(path: directory.appendingPathComponent(EstadoDominio.fileName).path, configuration: config)
        } else {
            db = try DatabaseQueue(configuration: config)
        }
        try Self.migrador.migrate(db)
    }

    static var migrador: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("calendario-1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS mapa_calendario(
                    clave TEXT PRIMARY KEY NOT NULL,
                    tipo TEXT NOT NULL,
                    ruta TEXT,
                    celda TEXT,
                    evento_id TEXT,
                    calendario_id TEXT,
                    huella TEXT,
                    ancla TEXT,
                    actualizado REAL NOT NULL,
                    retirado REAL
                );
                """)
        }
        return m
    }

    public func cerrar() { try? db.close() }

    // MARK: Filas

    public func fila(_ clave: String) throws -> FilaMapaCalendario? {
        try db.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM mapa_calendario WHERE clave = ?", arguments: [clave]).map(Self.fila)
        }
    }

    /// Las de eventos (no la del calendario) que siguen apuntadas.
    public func activas() throws -> [FilaMapaCalendario] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM mapa_calendario WHERE retirado IS NULL AND tipo != 'calendario' ORDER BY clave")
                .map(Self.fila)
        }
    }

    public func todas() throws -> [FilaMapaCalendario] {
        try db.read { db in try Row.fetchAll(db, sql: "SELECT * FROM mapa_calendario ORDER BY clave").map(Self.fila) }
    }

    public func guardar(_ f: FilaMapaCalendario) throws {
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO mapa_calendario(clave, tipo, ruta, celda, evento_id, calendario_id, huella, ancla, actualizado, retirado)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(clave) DO UPDATE SET tipo = excluded.tipo, ruta = excluded.ruta, celda = excluded.celda,
                    evento_id = excluded.evento_id, calendario_id = excluded.calendario_id, huella = excluded.huella,
                    ancla = excluded.ancla, actualizado = excluded.actualizado, retirado = excluded.retirado
                """, arguments: [f.clave, f.tipo, f.ruta?.raw, f.celda, f.eventoID, f.calendarioID, f.huella,
                                 f.ancla?.description, f.actualizado.timeIntervalSince1970, f.retirado?.timeIntervalSince1970])
        }
    }

    /// Nuestro calendario, si ya se creó.
    public func calendarioPropio() throws -> String? {
        try fila(Self.claveCalendario).flatMap { $0.activa ? $0.calendarioID : nil }
    }

    public func ponerCalendarioPropio(_ id: String, fecha: Date = Date()) throws {
        try guardar(FilaMapaCalendario(clave: Self.claveCalendario, tipo: "calendario", calendarioID: id, actualizado: fecha))
    }

    /// F5 · corrector (P2-7): «Desconectar» el Calendario: la app deja de usarlo (no borra nada en Calendario; sus filas
    /// se quedan para no duplicar si vuelves a conectarlo).
    public func quitarCalendarioPropio(fecha: Date = Date()) throws {
        guard var f = try fila(Self.claveCalendario), f.activa else { return }
        f.retirado = fecha
        f.actualizado = fecha
        try guardar(f)
    }

    static func fila(_ r: Row) -> FilaMapaCalendario {
        FilaMapaCalendario(clave: r["clave"], tipo: r["tipo"], ruta: (r["ruta"] as String?).map(VaultPath.init),
                           celda: r["celda"], eventoID: r["evento_id"], calendarioID: r["calendario_id"], huella: r["huella"],
                           ancla: (r["ancla"] as String?).flatMap { LocalDate(parsing: $0) },
                           actualizado: Date(timeIntervalSince1970: r["actualizado"]),
                           retirado: (r["retirado"] as Double?).map(Date.init(timeIntervalSince1970:)))
    }
}
