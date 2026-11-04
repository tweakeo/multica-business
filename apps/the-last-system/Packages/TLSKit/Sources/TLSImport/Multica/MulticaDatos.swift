import Foundation
import TLSCore

/// Un perfil de Multica (una cuenta o servidor configurado en su programa).
public struct PerfilMultica: Sendable, Hashable, Identifiable {
    public let nombre: String
    public var id: String { nombre }
    public init(nombre: String) { self.nombre = nombre }
}

/// Un espacio de trabajo de Multica.
public struct EspacioMultica: Sendable, Hashable, Identifiable {
    public let id: String
    public let nombre: String
    public init(id: String, nombre: String) { self.id = id; self.nombre = nombre }
}

/// Categoría del estado de una tarea en Multica (`status_category`).
public enum CategoriaMultica: String, Sendable, Hashable, CaseIterable, Codable {
    case backlog, todo
    case enCurso = "in_progress"
    case enRevision = "in_review"
    case blocked, done, cancelled

    /// Abiertas: todas menos las hechas y las canceladas.
    public var abierta: Bool { self != .done && self != .cancelled }

    /// El estado de la ficha de tarea (PLAN §4.2).
    public var estado: EstadoTarea {
        switch self {
        case .backlog: .sinProgramar
        case .todo: .porHacer
        case .enCurso: .enCurso
        case .enRevision: .enRevision
        case .blocked: .bloqueada
        case .done: .hecha
        case .cancelled: .cancelada
        }
    }

    /// Acepta también variantes con guion o espacio y mayúsculas («In progress», «in-review»).
    public init?(leyendo texto: String) {
        let t = texto.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "-", with: "_").replacingOccurrences(of: " ", with: "_")
        let plegado = TextFolding.fold(t).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        switch plegado {
        case "backlog", "sin_programar", "ideas", "icebox": self = .backlog
        case "todo", "to_do", "unstarted", "por_hacer", "pendiente", "pendientes", "abierta", "abierto", "nueva", "nuevo", "open":
            self = .todo
        case "in_progress", "started", "doing", "en_curso", "en_progreso", "haciendo", "empezada", "empezado": self = .enCurso
        case "in_review", "review", "en_revision", "revision", "revisar": self = .enRevision
        case "blocked", "bloqueada", "bloqueado", "en_espera", "esperando": self = .blocked
        case "done", "completed", "closed", "complete", "finished", "resolved", "hecho", "hecha", "terminado", "terminada",
             "completado", "completada", "cerrado", "cerrada", "resuelto", "resuelta", "finalizado", "finalizada", "listo", "lista":
            self = .done
        case "cancelled", "canceled", "wont_do", "wontdo", "won_t_do", "not_planned", "duplicate", "duplicated", "cancelado",
             "cancelada", "descartado", "descartada", "anulado", "anulada", "no_se_hara", "duplicada", "duplicado":
            self = .cancelled
        default: return nil
        }
    }
}

/// Una tarea de Multica tal como la da su programa (`issue list --output json`).
public struct TareaMultica: Sendable, Hashable, Identifiable {
    /// `MANU-12`.
    public let identificador: String
    public let titulo: String
    public let descripcion: String?
    /// `status` tal cual (el nombre del estado en ese espacio de trabajo).
    public let estado: String?
    public let categoria: CategoriaMultica?
    /// `priority` tal cual (`urgent`, `high`, `2`…).
    public let prioridad: String?
    public let vence: LocalDate?
    public let creada: LocalDate?

    public var id: String { identificador }

    public init(identificador: String, titulo: String, descripcion: String? = nil, estado: String? = nil,
                categoria: CategoriaMultica? = nil, prioridad: String? = nil, vence: LocalDate? = nil, creada: LocalDate? = nil) {
        self.identificador = identificador; self.titulo = titulo; self.descripcion = descripcion; self.estado = estado
        self.categoria = categoria; self.prioridad = prioridad; self.vence = vence; self.creada = creada
    }

    /// La categoría que manda: `status_category` o, si falta, la que se deduce de `status`.
    public var categoriaEfectiva: CategoriaMultica? {
        categoria ?? estado.flatMap { CategoriaMultica(leyendo: $0) }
    }

    /// Abierta = todo menos hecha y cancelada. Sin estado conocido, se trata como abierta pero sale desmarcada en la
    /// vista previa (la persona decide).
    public var abierta: Bool { categoriaEfectiva?.abierta ?? true }

    /// Tiene un estado que no sé leer (ni `status_category`): sale desmarcada.
    public var estadoDesconocido: Bool { categoriaEfectiva == nil && !(estado ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    /// El estado de la ficha: backlog → Sin programar, todo → Por hacer, in_progress → En curso,
    /// in_review → En revisión, blocked → Bloqueada. Sin categoría, Sin programar.
    public var estadoFicha: EstadoTarea { categoriaEfectiva?.estado ?? .sinProgramar }

    /// Prioridad de la ficha (Urgente · Alta · Media · Baja) o `nil` (sin prioridad).
    public var prioridadFicha: String? { Self.prioridad(prioridad) }

    static func prioridad(_ p: String?) -> String? {
        guard let p = p?.trimmingCharacters(in: .whitespaces).lowercased(), !p.isEmpty else { return nil }
        switch p {
        case "urgent", "urgente", "1", "p0", "critical": return "Urgente"
        case "high", "alta", "2", "p1": return "Alta"
        case "medium", "media", "normal", "3", "p2": return "Media"
        case "low", "baja", "4", "p3": return "Baja"
        default: return nil
        }
    }
}

/// Lee lo que devuelve el programa de Multica sin dar por hecha una forma exacta: listas sueltas u objetos con la
/// lista dentro (`issues`, `data`, `items`, `results`, `workspaces`, `profiles`), y `has_more` arriba o en `meta`.
public enum LecturaMultica {
    /// Una página de tareas: las tareas y si hay más (`nil` si no lo dice).
    public static func tareas(_ datos: Data) throws -> (tareas: [TareaMultica], hayMas: Bool?) {
        guard let raiz = try? JSONSerialization.jsonObject(with: datos, options: [.fragmentsAllowed]) else {
            throw ErrorMultica.respuestaIlegible
        }
        let objetos = lista(raiz, claves: ["issues", "data", "items", "results", "nodes"])
        guard let objetos else { throw ErrorMultica.respuestaIlegible }
        let tareas = objetos.compactMap(tarea)
        return (tareas, hayMas(raiz))
    }

    static func tarea(_ o: [String: Any]) -> TareaMultica? {
        guard let id = texto(o, ["identifier", "key", "id"]), !id.isEmpty else { return nil }
        let titulo = texto(o, ["title", "name"]) ?? id
        let estado: String? = {
            if let s = o["status"] as? [String: Any] { return texto(s, ["name", "key", "id"]) }
            return texto(o, ["status", "state"])
        }()
        let categoria: CategoriaMultica? = {
            if let s = o["status"] as? [String: Any], let c = texto(s, ["category", "type"]) { return CategoriaMultica(leyendo: c) }
            return texto(o, ["status_category", "statusCategory", "category"]).flatMap { CategoriaMultica(leyendo: $0) }
        }()
        let prioridad: String? = {
            if let n = o["priority"] as? NSNumber, !(o["priority"] is Bool) { return n.stringValue }
            if let p = o["priority"] as? [String: Any] { return texto(p, ["name", "key", "value"]) }
            return texto(o, ["priority"])
        }()
        return TareaMultica(identificador: id, titulo: titulo, descripcion: texto(o, ["description", "body"]), estado: estado,
                            categoria: categoria, prioridad: prioridad,
                            vence: texto(o, ["due_date", "dueDate", "due"]).flatMap(fecha),
                            creada: texto(o, ["created_at", "createdAt"]).flatMap(fecha))
    }

    /// Espacios de trabajo: JSON (`id` y `name`/`slug`) o, si no es JSON, líneas de texto con un identificador.
    public static func espacios(_ datos: Data) -> [EspacioMultica] {
        if let raiz = try? JSONSerialization.jsonObject(with: datos, options: [.fragmentsAllowed]),
           let objetos = lista(raiz, claves: ["workspaces", "data", "items", "results"]) {
            return objetos.compactMap { o in
                guard let id = texto(o, ["id", "workspace_id", "workspaceId"]) else { return nil }
                return EspacioMultica(id: id, nombre: texto(o, ["name", "slug", "title"]) ?? id)
            }
        }
        // Texto: una fila por espacio, con su identificador (largo, sin espacios) en alguna columna.
        let contenido = String(decoding: datos, as: UTF8.self)
        var vistos = Set<String>()
        var out: [EspacioMultica] = []
        for linea in contenido.split(whereSeparator: \.isNewline) {
            let columnas = linea.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "|" || $0 == "│" }).map(String.init)
            guard let id = columnas.first(where: esIdentificador) else { continue }
            let nombre = columnas.filter { $0 != id && !esIdentificador($0) && !$0.allSatisfy { $0 == "-" || $0 == "─" } }
                .joined(separator: " ")
            if vistos.insert(id).inserted { out.append(EspacioMultica(id: id, nombre: nombre.isEmpty ? id : nombre)) }
        }
        return out
    }

    /// Perfiles: JSON (lista de textos o de objetos con `name`) o líneas de texto, una por perfil.
    public static func perfiles(_ datos: Data) -> [PerfilMultica] {
        if let raiz = try? JSONSerialization.jsonObject(with: datos, options: [.fragmentsAllowed]) {
            var nombres: [String] = []
            if let l = raiz as? [String] { nombres = l }
            else if let o = raiz as? [String: Any], let l = o["profiles"] as? [String] { nombres = l }
            else if let objetos = lista(raiz, claves: ["profiles", "data", "items"]) {
                nombres = objetos.compactMap { texto($0, ["name", "profile", "id"]) }
            } else if let o = raiz as? [String: Any], let p = o["profiles"] as? [String: Any] {
                nombres = p.keys.sorted()
            }
            return unicos(nombres)
        }
        let lineas = String(decoding: datos, as: UTF8.self).split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "*-• ")) }
            .filter { !$0.isEmpty && !$0.contains(" ") }
        return unicos(lineas)
    }

    // MARK: Apoyo

    static func unicos(_ nombres: [String]) -> [PerfilMultica] {
        var vistos = Set<String>()
        return nombres.compactMap { n in
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, vistos.insert(t).inserted else { return nil }
            return PerfilMultica(nombre: t)
        }
    }

    static func lista(_ raiz: Any, claves: [String]) -> [[String: Any]]? {
        if let l = raiz as? [[String: Any]] { return l }
        if let l = raiz as? [Any], l.isEmpty { return [] }
        guard let o = raiz as? [String: Any] else { return nil }
        for k in claves {
            if let l = o[k] as? [[String: Any]] { return l }
            if let l = o[k] as? [Any], l.isEmpty { return [] }
            if let dentro = o[k] as? [String: Any], let l = lista(dentro, claves: claves) { return l }
        }
        return nil
    }

    static func hayMas(_ raiz: Any) -> Bool? {
        guard let o = raiz as? [String: Any] else { return nil }
        for k in ["has_more", "hasMore", "has_next_page", "hasNextPage"] {
            if let b = o[k] as? Bool { return b }
        }
        for k in ["meta", "pagination", "page_info", "pageInfo"] {
            if let m = o[k] as? [String: Any], let b = hayMas(m) { return b }
        }
        return nil
    }

    static func texto(_ o: [String: Any], _ claves: [String]) -> String? {
        for k in claves {
            if let s = o[k] as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            } else if let n = o[k] as? NSNumber, !(o[k] is Bool) {
                return n.stringValue
            }
        }
        return nil
    }

    static func fecha(_ s: String) -> LocalDate? {
        LocalDate(parsing: s) ?? (s.count >= 10 ? LocalDate(parsing: String(s.prefix(10))) : nil)
    }

    /// Algo que parece un identificador de espacio: UUID o una cadena larga de letras, cifras y guiones.
    static func esIdentificador(_ s: String) -> Bool {
        if UUID(uuidString: s) != nil { return true }
        return s.count >= 16 && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            && s.contains(where: \.isNumber)
    }
}

/// Lee de Multica (solo lectura): perfiles, espacios de trabajo y las tareas abiertas, página a página.
public struct LectorMultica: Sendable {
    public let ejecutor: any EjecutorMultica
    /// Tareas por página (lo que admite `--limit`).
    public static let porPagina = 100
    /// Tope de páginas por si el programa dijera siempre que hay más.
    public static let paginasMaximas = 50

    public init(ejecutor: any EjecutorMultica) { self.ejecutor = ejecutor }

    /// Los perfiles configurados. Si el programa no sabe listarlos, vacío: la persona escribe el suyo.
    public func perfiles() async -> [PerfilMultica] {
        guard let datos = try? await ejecutor.ejecutar(.perfiles) else { return [] }
        return LecturaMultica.perfiles(datos)
    }

    /// Espacios de trabajo de un perfil: primero en JSON y, si no lo admite, en texto.
    public func espacios(perfil: String) async throws -> [EspacioMultica] {
        let p = perfil.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw ErrorMultica.perfilVacio }
        if let datos = try? await ejecutor.ejecutar(.espacios(perfil: p, json: true)) {
            let e = LecturaMultica.espacios(datos)
            if !e.isEmpty { return e }
        }
        return LecturaMultica.espacios(try await ejecutor.ejecutar(.espacios(perfil: p, json: false)))
    }

    /// Todas las tareas abiertas de un espacio (todas menos hechas y canceladas), pidiendo páginas mientras haya más.
    public func tareasAbiertas(perfil: String, espacio: String) async throws -> [TareaMultica] {
        let p = perfil.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { throw ErrorMultica.perfilVacio }
        guard !espacio.isEmpty else { throw ErrorMultica.espacioVacio }
        var todas: [TareaMultica] = []
        var vistas = Set<String>()
        var desde = 0
        for _ in 0..<Self.paginasMaximas {
            let datos = try await ejecutor.ejecutar(.tareas(perfil: p, espacio: espacio, desde: desde, limite: Self.porPagina))
            let pagina = try LecturaMultica.tareas(datos)
            for t in pagina.tareas where vistas.insert(t.identificador.uppercased()).inserted { todas.append(t) }
            let hayMas = pagina.hayMas ?? (pagina.tareas.count >= Self.porPagina)
            guard hayMas, !pagina.tareas.isEmpty else { break }
            desde += pagina.tareas.count
        }
        return todas.filter(\.abierta)
    }
}
