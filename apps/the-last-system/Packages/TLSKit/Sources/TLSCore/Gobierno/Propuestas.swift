import Foundation
import GRDB

// Propuestas (PLAN §5.2, modo `asistido`; SISTEMAS §2.4 «propuesta de mejora» y CRITERIO): lo que un asistente haría
// queda guardado entero (el `WritePlan`, en `estado.sqlite.propuestas`) junto a una tarea `tipo: decision` para ti.
// Al elegir «Aplicar», el plan se escribe **como persona** (tú), en un solo paso que se puede deshacer; nunca hay un
// cambio silencioso.

/// Una propuesta guardada.
public struct Propuesta: Sendable, Hashable, Identifiable {
    public enum Estado: String, Sendable, Hashable, Codable { case pendiente, aplicada, descartada }
    /// `propuesta` (modo asistido), `mejora` (¿qué aprendimos?) o `criterio` (3 veces igual).
    public enum Clase: String, Sendable, Hashable, Codable { case propuesta, mejora, criterio }

    /// `prop-…`.
    public let id: String
    /// La tarea `tipo: decision` que la enseña en Decisiones.
    public let tarea: VaultPath?
    public let agente: String
    public let ejecucion: String?
    public let capacidad: String?
    public let clase: Clase
    public let descripcion: String
    public let plan: WritePlan
    public let estado: Estado
    public let creada: Date
    public let decidida: Date?
    public let decididaPor: String?
    public let resultado: String?

    /// Qué cambiaría, fichero a fichero (para enseñar la diferencia antes de aplicar).
    public var cambios: [String] { plan.ops.map(\.resumen) }
}

public final class AlmacenPropuestas: Sendable {
    public let estado: EstadoGobierno
    var db: DatabaseQueue { estado.db }

    public init(estado: EstadoGobierno) {
        self.estado = estado
    }

    static func nuevoID() -> String {
        "prop-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12))
    }

    @discardableResult
    public func guardar(_ plan: WritePlan, agente: String, ejecucion: String?, capacidad: String?, clase: Propuesta.Clase = .propuesta,
                        descripcion: String? = nil, tarea: VaultPath? = nil, id: String? = nil, ahora: Date = Date()) throws -> Propuesta {
        let id = id ?? Self.nuevoID()
        let planJSON = String(decoding: try EstadoGobierno.codificador.encode(PlanGuardado(plan)), as: UTF8.self)
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO propuestas(id, tarea, agente, ejecucion, capacidad, clase, descripcion, plan, estado, creada)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pendiente', ?)
                """, arguments: [id, tarea?.raw, ConfigAgentes.slug(agente), ejecucion, capacidad, clase.rawValue,
                                 descripcion ?? plan.descripcion, planJSON, ahora.timeIntervalSince1970])
        }
        return try propuesta(id)!
    }

    func asignarTarea(_ id: String, tarea: VaultPath) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE propuestas SET tarea = ? WHERE id = ?", arguments: [tarea.raw, id])
        }
    }

    public func propuesta(_ id: String) throws -> Propuesta? {
        try db.read { db in try Row.fetchOne(db, sql: "SELECT * FROM propuestas WHERE id = ?", arguments: [id]).flatMap(Self.leer) }
    }

    public func pendientes() throws -> [Propuesta] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM propuestas WHERE estado = 'pendiente' ORDER BY creada, id").compactMap(Self.leer)
        }
    }

    /// La propuesta de una tarea de decisión, si la tiene.
    public func deTarea(_ ruta: VaultPath) throws -> Propuesta? {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM propuestas WHERE tarea IS NOT NULL ORDER BY creada DESC").compactMap(Self.leer)
                .first { $0.tarea.map { TextFolding.pathKey($0.raw) == TextFolding.pathKey(ruta.raw) } ?? false }
        }
    }

    @discardableResult
    func marcar(_ id: String, _ estado: Propuesta.Estado, por: String, resultado: String?, ahora: Date = Date()) throws -> Bool {
        try db.write { db in
            try db.execute(sql: """
                UPDATE propuestas SET estado = ?, decidida = ?, decidida_por = ?, resultado = ? WHERE id = ? AND estado = 'pendiente'
                """, arguments: [estado.rawValue, ahora.timeIntervalSince1970, por, resultado, id])
            return db.changesCount > 0
        }
    }

    static func leer(_ r: Row) -> Propuesta? {
        guard let guardado = try? JSONDecoder().decode(PlanGuardado.self, from: Data((r["plan"] as String? ?? "").utf8)),
              let plan = guardado.plan else { return nil }
        return Propuesta(id: r["id"], tarea: (r["tarea"] as String?).map(VaultPath.init), agente: r["agente"],
                         ejecucion: r["ejecucion"], capacidad: r["capacidad"],
                         clase: Propuesta.Clase(rawValue: r["clase"]) ?? .propuesta, descripcion: r["descripcion"], plan: plan,
                         estado: Propuesta.Estado(rawValue: r["estado"]) ?? .pendiente, creada: Date(timeIntervalSince1970: r["creada"]),
                         decidida: (r["decidida"] as Double?).map(Date.init(timeIntervalSince1970:)), decididaPor: r["decidida_por"],
                         resultado: r["resultado"])
    }
}

// MARK: Plan guardado (WriteOp no es Codable: se guarda con esta forma estable)

struct PlanGuardado: Codable, Hashable {
    var id: UUID
    var autor: String
    var descripcion: String
    var ops: [OpGuardada]

    init(_ p: WritePlan) {
        id = p.id; autor = p.autor.etiqueta; descripcion = p.descripcion; ops = p.ops.map(OpGuardada.init)
    }

    var plan: WritePlan? {
        let o = ops.compactMap(\.op)
        guard o.count == ops.count else { return nil }
        return WritePlan(id: id, autor: Autor(etiqueta: autor), descripcion: descripcion, ops: o)
    }
}

struct PropGuardada: Codable, Hashable {
    var clave: String
    var tipo: String
    var texto: String?
    var lista: [String]?
    var si: Bool?

    init(_ p: Property) {
        clave = p.key
        switch p.value {
        case .text(let s): tipo = "texto"; texto = s
        case .number(let s): tipo = "numero"; texto = s
        case .bool(let b): tipo = "si"; si = b
        case .list(let l): tipo = "lista"; lista = l
        case .raw(let s): tipo = "crudo"; texto = s
        case .empty: tipo = "vacio"
        }
    }

    var property: Property {
        let v: PropertyValue = switch tipo {
        case "texto": .text(texto ?? "")
        case "numero": .number(texto ?? "")
        case "si": .bool(si ?? false)
        case "lista": .list(lista ?? [])
        case "crudo": .raw(texto ?? "")
        default: .empty
        }
        return Property(key: clave, value: v)
    }
}

struct OpGuardada: Codable, Hashable {
    var tipo: String
    var ruta: String
    var destino: String?
    var datos: Data?
    var texto: String?
    var seccion: String?
    var base: String?
    var baseHash: String?
    var lineaEnBlanco: Bool?
    var poner: [PropGuardada]?
    var quitar: [String]?
    var fila: [String: String]?
    var filas: [[String: String]]?
    var clave: String?
    var tabla: TableSelector?
    var columnaClave: String?
    var valorClave: String?
    var celdas: [String: String]?
    var cambios: [TextEdit]?
    var apartado: String?

    init(tipo: String, ruta: VaultPath) {
        self.tipo = tipo; self.ruta = ruta.raw
    }

    init(_ op: WriteOp) {
        switch op {
        case .create(let p, let d): self.init(tipo: "create", ruta: p); datos = d
        case .mergeFrontmatter(let p, let set, let unset):
            self.init(tipo: "mergeFrontmatter", ruta: p); poner = set.map(PropGuardada.init); quitar = unset
        case .appendToSection(let p, let s, let t, let b):
            self.init(tipo: "appendToSection", ruta: p); seccion = s; texto = t; lineaEnBlanco = b
        case .replaceSection(let p, let s, let t, let h):
            self.init(tipo: "replaceSection", ruta: p); seccion = s; texto = t; baseHash = h
        case .replaceBody(let p, let c, let h): self.init(tipo: "replaceBody", ruta: p); texto = c; baseHash = h
        case .saveText(let p, let b, let t): self.init(tipo: "saveText", ruta: p); base = b; texto = t
        case .appendLine(let p, let l): self.init(tipo: "appendLine", ruta: p); texto = l
        case .upsertCSVRow(let p, let f, let k): self.init(tipo: "upsertCSVRow", ruta: p); fila = f; clave = k
        case .insertCSVRows(let p, let fs, let k): self.init(tipo: "insertCSVRows", ruta: p); filas = fs; clave = k
        case .setTableCells(let p, let t, let c, let v, let cells):
            self.init(tipo: "setTableCells", ruta: p); tabla = t; columnaClave = c; valorClave = v; celdas = cells
        case .appendTableRow(let p, let t, let cells): self.init(tipo: "appendTableRow", ruta: p); tabla = t; celdas = cells
        case .editRanges(let p, let e, let h): self.init(tipo: "editRanges", ruta: p); cambios = e; baseHash = h
        case .move(let a, let b): self.init(tipo: "move", ruta: a); destino = b.raw
        case .retire(let p, let a): self.init(tipo: "retire", ruta: p); apartado = a
        }
    }

    var op: WriteOp? {
        let p = VaultPath(ruta)
        switch tipo {
        case "create": return datos.map { .create(p, contents: $0) }
        case "mergeFrontmatter": return .mergeFrontmatter(p, set: (poner ?? []).map(\.property), unset: quitar ?? [])
        case "appendToSection":
            guard let s = seccion, let t = texto else { return nil }
            return .appendToSection(p, section: s, text: t, blankLine: lineaEnBlanco ?? true)
        case "replaceSection":
            guard let s = seccion, let t = texto, let h = baseHash else { return nil }
            return .replaceSection(p, section: s, text: t, baseSectionHash: h)
        case "replaceBody": return texto.map { .replaceBody(p, body: $0, baseHash: baseHash) }
        case "saveText":
            guard let b = base, let t = texto else { return nil }
            return .saveText(p, base: b, text: t)
        case "appendLine": return texto.map { .appendLine(p, line: $0) }
        case "upsertCSVRow":
            guard let f = fila, let k = clave else { return nil }
            return .upsertCSVRow(p, row: f, key: k)
        case "insertCSVRows":
            guard let fs = filas, let k = clave else { return nil }
            return .insertCSVRows(p, rows: fs, key: k)
        case "setTableCells":
            guard let t = tabla, let c = columnaClave, let v = valorClave, let cells = celdas else { return nil }
            return .setTableCells(p, table: t, keyColumn: c, keyValue: v, cells: cells)
        case "appendTableRow":
            guard let t = tabla, let cells = celdas else { return nil }
            return .appendTableRow(p, table: t, cells: cells)
        case "editRanges":
            guard let e = cambios, let h = baseHash else { return nil }
            return .editRanges(p, edits: e, baseHash: h)
        case "move": return destino.map { .move(p, to: VaultPath($0)) }
        case "retire": return .retire(p, apartado: apartado)
        default: return nil
        }
    }
}
