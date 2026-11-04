import Foundation

/// Estados de una tarea (PLAN §4.2). En pantalla se dice «En revisión».
public enum EstadoTarea: String, CaseIterable, Sendable, Codable, Hashable {
    case sinProgramar = "Sin programar"
    case porHacer = "Por hacer"
    case enCurso = "En curso"
    case enRevision = "En revisión"
    case bloqueada = "Bloqueada"
    case hecha = "Hecha"
    case cancelada = "Cancelada"

    /// Lee también los nombres heredados (Pendiente, Por revisar, Bloqueado, En progreso, Hecho) y los de Multica.
    public init?(leyendo texto: String) {
        let t = TextFolding.fold(texto.trimmingCharacters(in: .whitespaces))
        switch t {
        case "sin programar", "backlog": self = .sinProgramar
        case "por hacer", "pendiente", "todo": self = .porHacer
        case "en curso", "en progreso", "in_progress", "in progress": self = .enCurso
        case "en revision", "por revisar", "in_review", "in review", "revisar": self = .enRevision
        case "bloqueada", "bloqueado", "blocked": self = .bloqueada
        case "hecha", "hecho", "done": self = .hecha
        case "cancelada", "cancelado", "cancelled", "canceled": self = .cancelada
        default: return nil
        }
    }

    /// Equivalencia con Multica.
    public var multica: String {
        switch self {
        case .sinProgramar: "backlog"
        case .porHacer: "todo"
        case .enCurso: "in_progress"
        case .enRevision: "in_review"
        case .bloqueada: "blocked"
        case .hecha: "done"
        case .cancelada: "cancelled"
        }
    }

    /// Hecha o Cancelada.
    public var cerrada: Bool { self == .hecha || self == .cancelada }
}

/// Nombres de fichero de las tareas: `t-0042-preparar-propuesta-economica.md`.
public enum TareaArchivo {
    /// El slug va recortado para que el nombre entero (`t-0042-…`) no pase de 60 caracteres.
    public static let maximoSlug = 53

    /// Número del nombre (`t-0042-x.md` → 42).
    public static func numero(deNombre nombre: String) -> Int? {
        let n = nombre.precomposedStringWithCanonicalMapping.lowercased()
        guard n.hasPrefix("t-") else { return nil }
        let digits = n.dropFirst(2).prefix(while: \.isNumber)
        guard digits.count >= 4 else { return nil }
        let after = n.dropFirst(2 + digits.count)
        guard after.isEmpty || after.hasPrefix("-") || after.hasPrefix(".") else { return nil }
        return Int(digits)
    }

    /// Slug del nombre (`t-0042-preparar-propuesta.md` → `preparar-propuesta`).
    public static func slug(deNombre nombre: String) -> String {
        let stem = VaultPath(nombre).stem
        guard let r = stem.range(of: #"^t-\d{4,}-?"#, options: [.regularExpression, .caseInsensitive]) else { return stem }
        return String(stem[r.upperBound...])
    }

    /// `t-0042-slug.md`.
    public static func nombre(numero: Int, slug: String) -> String {
        let s = NombresDeFicha.recortar(slug, maximo: maximoSlug)
        return String(format: "t-%04d", numero) + (s.isEmpty ? "" : "-" + s) + ".md"
    }
}

/// Una ficha de tarea leída de la carpeta (`…/Tareas/t-NNNN-slug.md`).
public struct Tarea: Sendable, Hashable, Identifiable {
    public var id: VaultPath { ruta }
    public let ruta: VaultPath
    /// `id` de la ficha.
    public let uid: String?
    /// `T-0042` (de la propiedad o, si falta, del nombre).
    public let numero: String?
    public let numeroEntero: Int?
    public let titulo: String
    public let estado: EstadoTarea?
    /// Estado tal como está escrito.
    public let estadoTexto: String?
    public let prioridad: String?
    public let tipo: String?
    public let responsable: String?
    public let planificada: LocalDate?
    public let vence: LocalDate?
    public let despertar: LocalDate?
    /// Área por la ruta (la ruta manda).
    public let area: AreaCode?
    /// Proyecto al que apunta la ficha (`proyecto` o `proyecto_id` heredado).
    public let proyecto: VaultPath?
    /// Proyecto en cuya carpeta vive (`…/Proyectos/<slug>/Tareas/`).
    public let proyectoPorRuta: VaultPath?
    public let oportunidad: VaultPath?
    public let empresa: VaultPath?
    public let creada: LocalDate?
    public let cerrada: LocalDate?
    public let origen: String?

    /// La coge un asistente si: el responsable es `agente:*`, está `Por hacer` y `planificada` está
    /// vacía o es hoy o antes. `Sin programar` nunca dispara.
    public func esListaParaAgente(hoy: LocalDate) -> Bool {
        guard let r = responsable, r.hasPrefix("agente:"), estado == .porHacer else { return false }
        guard let p = planificada else { return true }
        return p <= hoy
    }

    /// ENT-04: nunca sábado ni domingo (se corre al lunes).
    public static func laborable(_ d: LocalDate) -> LocalDate {
        var cur = d
        while cur.isWeekend { cur = cur.adding(days: 1) }
        return cur
    }
}
