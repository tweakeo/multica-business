import Foundation

/// Por qué falla una ejecución (PLAN §5.3, «Cola»).
public enum FailureReason: String, Sendable, Equatable, Codable, CaseIterable {
    /// `InitGuard` encontró herramientas, servidores o permisos de más.
    case guardia
    /// Claude Code no tiene sesión iniciada.
    case sinSesion = "sin_sesion"
    /// Se agotó el tope de gasto de la ejecución o del mes.
    case presupuesto
    case limiteUso = "limite_uso"
    case red
    case sobrecarga
    /// El proceso terminó sin evento `result`.
    case sinResultado = "sin_resultado"
    /// La app se cerró con la ejecución en curso.
    case interrumpida
    case tiempoAgotado = "tiempo_agotado"
    /// Esta versión de Claude Code no tiene flags imprescindibles.
    case flagsAusentes = "flags_ausentes"
    case sinClaude = "sin_claude"
    case error

    /// Solo se reintenta ante límite de uso, red, sobrecarga o salida sin `result`.
    public var retriable: Bool {
        switch self {
        case .limiteUso, .red, .sobrecarga, .sinResultado: true
        default: false
        }
    }

    /// Texto para la persona, sin jerga.
    public var explanation: String {
        switch self {
        case .guardia: "Se paró por seguridad: el asistente tenía a mano más de lo permitido."
        case .sinSesion: "Claude no tiene la sesión iniciada en este Mac."
        case .presupuesto: "Se alcanzó el tope de uso."
        case .limiteUso: "Se alcanzó el límite de uso de tu suscripción. Se reintentará más tarde."
        case .red: "No hay conexión con el servicio. Se reintentará."
        case .sobrecarga: "El servicio está saturado. Se reintentará."
        case .sinResultado: "El asistente terminó sin cerrar el trabajo. Se reintentará."
        case .interrumpida: "Se interrumpió al cerrar la app."
        case .tiempoAgotado: "Tardó demasiado y se paró."
        case .flagsAusentes: "Esta versión de Claude no tiene opciones que la app necesita."
        case .sinClaude: "No encuentro Claude en este Mac."
        case .error: "El asistente terminó con un error."
        }
    }
}

/// Estado de una ejecución (PLAN §5.3): pendiente → en cola → en curso → esperando respuesta →
/// completada / fallida(motivo) / cancelada.
public enum RunState: Sendable, Equatable {
    case pendiente, enCola, enCurso, esperandoRespuesta, completada
    case fallida(FailureReason)
    case cancelada

    /// Estado final según el evento `result` (o su ausencia).
    public static func from(result: ResultInfo?) -> RunState {
        guard let r = result else { return .fallida(.sinResultado) }
        if !r.isError && r.subtype == "success" { return .completada }
        if r.subtype.contains("budget") { return .fallida(.presupuesto) }
        let text = (r.text ?? "").lowercased()
        switch r.apiErrorStatus {
        case 401, 403: return .fallida(.sinSesion)
        case 429: return .fallida(.limiteUso)
        case 529, 503: return .fallida(.sobrecarga)
        default: break
        }
        if text.contains("enotfound") || text.contains("can't reach") || text.contains("econnrefused")
            || text.contains("network") || text.contains("timed out") { return .fallida(.red) }
        if text.contains("overloaded") { return .fallida(.sobrecarga) }
        if text.contains("rate limit") || text.contains("usage limit") { return .fallida(.limiteUso) }
        if text.contains("/login") || text.contains("not logged in") || text.contains("authentication")
            || text.contains("oauth") { return .fallida(.sinSesion) }
        return .fallida(.error)
    }
}
