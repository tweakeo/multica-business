import Foundation

/// Estados de cada tipo de ficha (SISTEMAS.md §3.5) y lo que la interfaz necesita saber de ellos: cuáles
/// cuentan como abiertos en las pestañas (§2.2 principio 3) y en qué orden va lo urgente (principio 4).
public enum EstadosDeFicha {
    /// Estados que se pueden elegir, en orden de su ciclo.
    public static func posibles(_ tipo: NoteKind) -> [String] {
        switch tipo {
        case .organization, .contact: ["Interesado", "Activo", "Antiguo cliente", "Archivado"]
        case .service: ["En pruebas", "Activo", "Retirado"]
        case .opportunity: ["Prospecto", "Diagnóstico", "Propuesta", "Aceptada", "Ganada", "Perdida", "Pausada"]
        case .meeting: ["Prevista", "Hecha", "Cancelada"]
        case .proposal, .quote, .agreement: ["Borrador", "Aprobada", "Enviada", "Aceptada", "Rechazada", "Caducada"]
        case .invoice: ["Borrador", "Emitida", "Enviada", "Cobrada", "Rectificada"]
        case .project: ["Sin empezar", "En curso", "Pausado", "Cerrado", "Archivado"]
        case .incident: ["Recibida", "En curso", "Resuelta", "Cerrada"]
        case .task: EstadoTarea.allCases.map(\.rawValue)
        case .content: ["Idea", "Borrador", "En revisión", "Aprobado", "Programado", "Publicado", "Descartado"]
        case .system: ["Falta", "A medias", "Montado", "Funciona sin ti"]
        case .area: ["Activa", "Preparada", "En reposo"]
        default: []
        }
    }

    /// Etapas de la línea de la oportunidad (§3.4): Perdida y Pausada van aparte.
    public static let etapasOportunidad = ["Prospecto", "Diagnóstico", "Propuesta", "Aceptada", "Ganada"]

    static func es(_ estado: String?, _ lista: [String]) -> Bool {
        guard let estado else { return false }
        let k = TextFolding.fold(estado)
        return lista.contains { TextFolding.fold($0) == k }
    }

    /// Cuenta como abierta en los contadores de las pestañas: oportunidades sin cerrar, reuniones previstas,
    /// facturas sin cobrar, tareas sin hacer… Lo que no tiene ciclo cuenta siempre.
    public static func abierta(_ tipo: NoteKind, estado: String?) -> Bool {
        switch tipo {
        case .opportunity: !es(estado, ["Ganada", "Perdida"])
        case .meeting: estado == nil || es(estado, ["Prevista"])
        case .proposal, .quote, .agreement: estado == nil || es(estado, ["Borrador", "Aprobada", "Enviada"])
        case .invoice: !es(estado, ["Cobrada", "Rectificada"])
        case .project: !es(estado, ["Cerrado", "Archivado"])
        case .task: !(estado.flatMap { EstadoTarea(leyendo: $0) }?.cerrada ?? false)
        case .incident: !es(estado, ["Resuelta", "Cerrada"])
        case .content: !es(estado, ["Publicado", "Descartado"])
        case .organization, .contact: !es(estado, ["Archivado", "Antiguo cliente"])
        default: true
        }
    }

    /// Está cerrada del todo (va plegada al final, «Cerradas (4)»).
    public static func cerrada(_ tipo: NoteKind, estado: String?) -> Bool { !abierta(tipo, estado: estado) }

    /// Algo que espera **tu** OK: una tarea En revisión, un documento en Borrador (insignia magenta con palabra).
    public static func esperaTuOK(_ tipo: NoteKind, estado: String?) -> Bool {
        switch tipo {
        case .task: es(estado, ["En revisión"])
        default: false
        }
    }

    /// Fecha que ordena una ficha: vence, siguiente paso, fecha del evento o planificada.
    public static func fecha(_ f: FichaGrafo) -> LocalDate? {
        for k in ["vence", "siguiente_fecha", "fecha", "planificada", "inicio"] {
            if let t = f.texto(k), let d = LocalDate(parsing: t) { return d }
        }
        return nil
    }

    /// Lo urgente primero (§2.2 principio 4): pide tu decisión → vencido → vence hoy → por fecha → sin fecha →
    /// lo cerrado al final.
    public static func urgencia(_ f: FichaGrafo, hoy: LocalDate) -> Int {
        if cerrada(f.tipo, estado: f.estado) { return 9 }
        if esperaTuOK(f.tipo, estado: f.estado) { return 0 }
        guard let d = fecha(f) else { return 5 }
        if d < hoy, ["vence", "siguiente_fecha"].contains(where: { f.texto($0) != nil }) { return 1 }
        if d == hoy { return 2 }
        return 3
    }

    /// Ordena por urgencia y, dentro, por fecha y nombre.
    public static func ordenar(_ fichas: [FichaGrafo], hoy: LocalDate) -> [FichaGrafo] {
        fichas.sorted { a, b in
            let ua = urgencia(a, hoy: hoy), ub = urgencia(b, hoy: hoy)
            if ua != ub { return ua < ub }
            let fa = fecha(a), fb = fecha(b)
            if fa != fb {
                switch (fa, fb) {
                case (let x?, let y?): return ua == 9 ? x > y : x < y
                case (nil, _): return false
                case (_, nil): return true
                }
            }
            return a.nombre.localizedStandardCompare(b.nombre) == .orderedAscending
        }
    }

    /// Escribe el estado con la forma que ya usa la ficha (los sistemas lo llevan en minúscula: `a medias`).
    public static func escrito(_ estado: String, como actual: String?) -> String {
        guard let actual, let primera = actual.first, primera.isLowercase else { return estado }
        return estado.lowercased()
    }
}
