import Foundation
import GRDB

// ApprovalStore (PLAN §5.2): el único registro de aprobaciones, en `estado.sqlite.aprobaciones`.
//
// - Huella: `SHA256(accion | JSON canónico {destinatarios, asunto, cuerpo, importe, adjuntos:[sha256], entidad_id,
//   version_entidad})`. Lo que se aprueba es exactamente eso: si cambia una coma, ya no es lo aprobado.
// - Una edición hecha por otro invalida la aprobación; «Aprobar con mis cambios» calcula la huella nueva y aprueba en
//   el mismo gesto.
// - Una petición nueva sobre la misma entidad sustituye a la anterior. Caduca a los 14 días.
// - Al aprobar ejecuta la app, nunca el asistente (`Aprobaciones`, `EjecutorDeAprobaciones`).

/// Lo que se aprueba, tal cual (es lo que enseña `SensitiveConfirmSheet`: qué sale, a quién y por cuánto).
public struct CargaAprobacion: Sendable, Hashable, Codable {
    public var destinatarios: [String]
    public var asunto: String?
    public var cuerpo: String?
    /// Céntimos.
    public var importe: Int?
    /// SHA-256 de cada adjunto, en orden.
    public var adjuntos: [String]
    public var entidadId: String
    public var versionEntidad: String

    public init(destinatarios: [String] = [], asunto: String? = nil, cuerpo: String? = nil, importe: Int? = nil,
                adjuntos: [String] = [], entidadId: String, versionEntidad: String) {
        self.destinatarios = destinatarios; self.asunto = asunto; self.cuerpo = cuerpo; self.importe = importe
        self.adjuntos = adjuntos; self.entidadId = entidadId; self.versionEntidad = versionEntidad
    }

    enum CodingKeys: String, CodingKey {
        case destinatarios, asunto, cuerpo, importe, adjuntos
        case entidadId = "entidad_id"
        case versionEntidad = "version_entidad"
    }

    /// Siempre con todas las claves (las vacías, `null`): así el texto canónico no depende de lo que falte.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(destinatarios, forKey: .destinatarios)
        try c.encode(asunto, forKey: .asunto)
        try c.encode(cuerpo, forKey: .cuerpo)
        try c.encode(importe, forKey: .importe)
        try c.encode(adjuntos, forKey: .adjuntos)
        try c.encode(entidadId, forKey: .entidadId)
        try c.encode(versionEntidad, forKey: .versionEntidad)
    }

    /// La carga de un borrador (o factura) tal como está en la foto: lo que sale, a quién, por cuánto, la huella de cada
    /// adjunto y su versión. No mira si los adjuntos son privados (eso lo hace `Aprobaciones.solicitar`).
    public static func de(_ b: Borrador, snapshot: VaultSnapshot) throws -> CargaAprobacion {
        var adjuntos: [String] = []
        for p in b.adjuntos {
            guard let real = snapshot.existing(p) else { throw ErrorDeGobierno.noEncontrado(p.name) }
            let d = snapshot.data(real) ?? UbiquityInspector.withoutMaterializing { try? Data(contentsOf: real.url(in: snapshot.root)) }
            guard let d else { throw ErrorDeGobierno.noEncontrado(p.name) }
            adjuntos.append(ContentHash.of(d))
        }
        return CargaAprobacion(destinatarios: b.para, asunto: b.asunto, cuerpo: b.cuerpo, importe: b.importe, adjuntos: adjuntos,
                               entidadId: b.id ?? b.ruta.raw, versionEntidad: b.version)
    }

    /// JSON canónico: claves ordenadas, sin espacios, barras sin escapar.
    public var jsonCanonico: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? e.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// Una aprobación pedida.
public struct Aprobacion: Sendable, Hashable, Identifiable {
    /// F5 · corrector (P1-1): `ejecucion` de una aprobación que pidió una persona desde Decisiones (`persona:Manu`).
    public static let prefijoPersona = "persona:"
    /// La pidió una persona (no un asistente con `tls_solicitar_accion`).
    public var pedidaPorPersona: Bool { ejecucion?.hasPrefix(Self.prefijoPersona) == true }

    public enum Estado: String, Sendable, Hashable, Codable {
        /// Esperando tu decisión.
        case pendiente
        /// Alguien cambió el contenido: «Aprobar» ya no vale; «Aprobar con mis cambios», sí.
        case invalidada
        /// Aprobada; la app la está ejecutando.
        case aprobada
        /// La app hizo lo que tocaba (o lo dejó listo para tu clic).
        case ejecutada
        case rechazada
        /// Llegó otra petición sobre lo mismo.
        case sustituida
        /// 14 días sin decidir.
        case caducada

        /// Se puede decidir todavía.
        public var abierta: Bool { self == .pendiente || self == .invalidada }

        public var texto: String {
            switch self {
            case .pendiente: "pendiente de tu OK"
            case .invalidada: "cambiada desde que la preparó el asistente"
            case .aprobada: "aprobada"
            case .ejecutada: "hecha"
            case .rechazada: "rechazada"
            case .sustituida: "sustituida por otra"
            case .caducada: "caducada"
            }
        }
    }

    /// `apr-91c2…`.
    public let id: String
    public let entidadId: String
    public let accion: AccionExterna
    public let herramienta: String?
    /// Ficha que se aprueba (borrador o factura).
    public let ruta: VaultPath?
    public let agente: String
    public let ejecucion: String?
    public let carga: CargaAprobacion
    public let hash: String
    public let estado: Estado
    public let creada: Date
    public let caduca: Date
    public let decidida: Date?
    public let decididaPor: String?
    public let conCambios: Bool
    public let motivo: String?
    public let ejecutada: Date?
    public let resultado: String?
}

public final class ApprovalStore: Sendable {
    public static let diasDeCaducidad = 14

    public let estado: EstadoGobierno
    var db: DatabaseQueue { estado.db }

    public init(estado: EstadoGobierno) {
        self.estado = estado
    }

    /// `SHA256(accion | JSON canónico)`. Para otros programas, la acción lleva la herramienta (`externa:ext_x_y`).
    public static func hash(accion: AccionExterna, herramienta: String? = nil, carga: CargaAprobacion) -> String {
        let a = accion.rawValue + (herramienta.map { ":" + $0 } ?? "")
        return ContentHash.of(a + "|" + carga.jsonCanonico)
    }

    static func nuevoID() -> String {
        "apr-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
    }

    // MARK: Pedir

    /// Apunta una petición nueva. Las abiertas sobre la misma entidad quedan sustituidas.
    @discardableResult
    public func registrar(accion: AccionExterna, herramienta: String? = nil, ruta: VaultPath?, agente: String,
                          ejecucion: String?, carga: CargaAprobacion, ahora: Date = Date()) throws -> Aprobacion {
        let id = Self.nuevoID()
        let hash = Self.hash(accion: accion, herramienta: herramienta, carga: carga)
        let caduca = ahora.addingTimeInterval(Double(Self.diasDeCaducidad) * 86_400)
        let cargaJSON = carga.jsonCanonico
        try db.write { db in
            try db.execute(sql: """
                UPDATE aprobaciones SET estado = 'sustituida', motivo = ?, decidida = ?
                WHERE entidad_id = ? AND estado IN ('pendiente', 'invalidada')
                """, arguments: ["Llegó otra petición sobre lo mismo (\(id)).", ahora.timeIntervalSince1970, carga.entidadId])
            try db.execute(sql: """
                INSERT INTO aprobaciones(id, entidad_id, accion, herramienta, ruta, agente, ejecucion, carga, hash, estado, creada, caduca)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pendiente', ?, ?)
                """, arguments: [id, carga.entidadId, accion.rawValue, herramienta, ruta?.raw, ConfigAgentes.slug(agente), ejecucion,
                                 cargaJSON, hash, ahora.timeIntervalSince1970, caduca.timeIntervalSince1970])
        }
        return try aprobacion(id)!
    }

    // MARK: Leer

    public func aprobacion(_ id: String) throws -> Aprobacion? {
        try db.read { db in try Row.fetchOne(db, sql: "SELECT * FROM aprobaciones WHERE id = ?", arguments: [id]).map(Self.leer) }
    }

    /// Todas, de la más reciente a la más antigua.
    public func todas() throws -> [Aprobacion] {
        try db.read { db in try Row.fetchAll(db, sql: "SELECT * FROM aprobaciones ORDER BY creada DESC, id").map(Self.leer) }
    }

    /// Las que esperan decisión (sin caducar).
    public func abiertas(ahora: Date = Date()) throws -> [Aprobacion] {
        try db.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM aprobaciones WHERE estado IN ('pendiente', 'invalidada') AND caduca > ? ORDER BY creada, id
                """, arguments: [ahora.timeIntervalSince1970]).map(Self.leer)
        }
    }

    /// La abierta de una entidad, si la hay.
    public func abierta(deEntidad entidadId: String, ahora: Date = Date()) throws -> Aprobacion? {
        try abiertas(ahora: ahora).last { $0.entidadId == entidadId }
    }

    public func deEntidad(_ entidadId: String) throws -> [Aprobacion] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM aprobaciones WHERE entidad_id = ? ORDER BY creada, id",
                             arguments: [entidadId]).map(Self.leer)
        }
    }

    static func leer(_ r: Row) -> Aprobacion {
        let carga = (try? JSONDecoder().decode(CargaAprobacion.self, from: Data((r["carga"] as String? ?? "{}").utf8)))
            ?? CargaAprobacion(entidadId: r["entidad_id"], versionEntidad: "")
        return Aprobacion(id: r["id"], entidadId: r["entidad_id"], accion: AccionExterna(rawValue: r["accion"]) ?? .externa,
                          herramienta: r["herramienta"], ruta: (r["ruta"] as String?).map(VaultPath.init), agente: r["agente"],
                          ejecucion: r["ejecucion"], carga: carga, hash: r["hash"],
                          estado: Aprobacion.Estado(rawValue: r["estado"]) ?? .pendiente,
                          creada: Date(timeIntervalSince1970: r["creada"]), caduca: Date(timeIntervalSince1970: r["caduca"]),
                          decidida: (r["decidida"] as Double?).map(Date.init(timeIntervalSince1970:)),
                          decididaPor: r["decidida_por"], conCambios: (r["con_cambios"] as Int? ?? 0) != 0, motivo: r["motivo"],
                          ejecutada: (r["ejecutada"] as Double?).map(Date.init(timeIntervalSince1970:)), resultado: r["resultado"])
    }

    // MARK: Decidir (solo desde `Aprobaciones`, que comprueba antes)

    /// Pasa de abierta a aprobada (con la huella y la carga que se aprueban). `false` si ya no estaba abierta.
    @discardableResult
    func marcarAprobada(_ id: String, por persona: String, hash: String, carga: CargaAprobacion, conCambios: Bool,
                        ahora: Date = Date()) throws -> Bool {
        try db.write { db in
            try db.execute(sql: """
                UPDATE aprobaciones SET estado = 'aprobada', decidida = ?, decidida_por = ?, hash = ?, carga = ?, con_cambios = ?
                WHERE id = ? AND estado IN ('pendiente', 'invalidada') AND caduca > ?
                """, arguments: [ahora.timeIntervalSince1970, persona, hash, carga.jsonCanonico, conCambios ? 1 : 0, id,
                                 ahora.timeIntervalSince1970])
            return db.changesCount > 0
        }
    }

    func marcarEjecutada(_ id: String, resultado: String, ahora: Date = Date()) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE aprobaciones SET estado = 'ejecutada', ejecutada = ?, resultado = ? WHERE id = ? AND estado = 'aprobada'",
                           arguments: [ahora.timeIntervalSince1970, resultado, id])
        }
    }

    /// La ejecución falló: vuelve a quedar aprobada, con el motivo (se puede reintentar).
    func anotarFallo(_ id: String, motivo: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE aprobaciones SET motivo = ? WHERE id = ?", arguments: [motivo, id])
        }
    }

    /// Alguien cambió el contenido.
    @discardableResult
    func invalidar(_ id: String, motivo: String) throws -> Bool {
        try db.write { db in
            try db.execute(sql: "UPDATE aprobaciones SET estado = 'invalidada', motivo = ? WHERE id = ? AND estado = 'pendiente'",
                           arguments: [motivo, id])
            return db.changesCount > 0
        }
    }

    @discardableResult
    func rechazar(_ id: String, por persona: String, motivo: String?, ahora: Date = Date()) throws -> Bool {
        try db.write { db in
            try db.execute(sql: """
                UPDATE aprobaciones SET estado = 'rechazada', decidida = ?, decidida_por = ?, motivo = ?
                WHERE id = ? AND estado IN ('pendiente', 'invalidada')
                """, arguments: [ahora.timeIntervalSince1970, persona, motivo, id])
            return db.changesCount > 0
        }
    }

    /// Caduca las que llevan 14 días sin decidir. Devuelve las que caducaron.
    @discardableResult
    public func caducar(ahora: Date = Date()) throws -> [Aprobacion] {
        try db.write { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM aprobaciones WHERE estado IN ('pendiente', 'invalidada') AND caduca <= ?
                """, arguments: [ahora.timeIntervalSince1970])
            try db.execute(sql: """
                UPDATE aprobaciones SET estado = 'caducada', motivo = 'Lleva 14 días sin decidir.'
                WHERE estado IN ('pendiente', 'invalidada') AND caduca <= ?
                """, arguments: [ahora.timeIntervalSince1970])
            return rows.map(Self.leer)
        }
    }

    // MARK: CRITERIO

    /// Lo que se aprueba igual una y otra vez (la misma acción del mismo asistente, 3 veces seguidas sin cambios) o se
    /// corrige igual (3 veces con cambios): candidato a tarjeta CRITERIO («esto ya podría…» o «aprende esto»).
    public struct Repeticion: Sendable, Hashable {
        public let agente: String
        public let accion: AccionExterna
        public let veces: Int
        /// `true`: las corregiste; `false`: las aprobaste tal cual.
        public let conCambios: Bool
        /// La última de la serie (para no repetir la tarjeta).
        public let ultima: String
    }

    public func repeticiones(minimo: Int = 3) throws -> [Repeticion] {
        let todas = try todas().reversed().filter { [.ejecutada, .aprobada, .rechazada].contains($0.estado) }
        var out: [Repeticion] = []
        for (clave, grupo) in Dictionary(grouping: todas, by: { "\($0.agente)|\($0.accion.rawValue)" }) {
            // La racha final: las últimas decididas del mismo modo (aprobadas sin cambios, o con cambios), sin rechazos.
            var veces = 0
            var conCambios: Bool?
            for a in grupo.reversed() {
                guard a.estado != .rechazada else { break }
                if let c = conCambios, c != a.conCambios { break }
                conCambios = a.conCambios
                veces += 1
            }
            guard veces >= minimo, let c = conCambios, let ultima = grupo.last else { continue }
            let partes = clave.split(separator: "|")
            out.append(Repeticion(agente: String(partes[0]), accion: AccionExterna(rawValue: String(partes[1])) ?? .externa,
                                  veces: veces, conCambios: c, ultima: ultima.id))
        }
        return out.sorted { ($0.agente, $0.accion.rawValue) < ($1.agente, $1.accion.rawValue) }
    }
}
