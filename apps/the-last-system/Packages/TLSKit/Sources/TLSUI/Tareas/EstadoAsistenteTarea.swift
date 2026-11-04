import Foundation
import TLSCore

/// El estado en vivo del asistente que lleva una tarea (PLAN §6.4: en cola, trabajando, esperando tu respuesta o
/// terminado). En F2 no hay asistentes que trabajen (llegan en F4), así que sale de la ficha, de forma determinista:
/// `trabajando` solo lo dará la ejecución de F4 (`enMarcha`). Las reglas son las de `Tarea.esListaParaAgente`.
enum EstadoAsistenteTarea: Hashable, Sendable {
    /// En «Sin programar»: nunca la coge sola.
    case sinEmpezar
    /// «Por hacer» con `planificada` posterior a hoy.
    case esperaSuDia(LocalDate)
    /// Lista para el asistente (`esListaParaAgente`).
    case enCola
    /// Trabajando ahora (solo con asistentes encendidos, F4).
    case trabajando
    /// En revisión o es una pregunta para ti.
    case esperaTuRespuesta
    /// Bloqueada.
    case bloqueada
    /// Hecha o cancelada.
    case terminado

    /// `nil` si la tarea no la lleva un asistente.
    static func de(_ t: Tarea, hoy: LocalDate, enMarcha: Bool = false) -> EstadoAsistenteTarea? {
        guard let r = t.responsable, r.lowercased().hasPrefix("agente:") else { return nil }
        if enMarcha { return .trabajando }
        switch t.estado {
        case .hecha?, .cancelada?: return .terminado
        case .enRevision?: return .esperaTuRespuesta
        case .bloqueada?: return .bloqueada
        case .enCurso?: return .enCola
        case .porHacer?:
            if t.esListaParaAgente(hoy: hoy) { return .enCola }
            if let p = t.planificada { return .esperaSuDia(p) }
            return .enCola
        case .sinProgramar?, nil:
            return .sinEmpezar
        }
    }

    /// La frase corta (con el nombre del asistente delante).
    func frase(asistente: String, hoy: LocalDate) -> String {
        switch self {
        case .sinEmpezar: "\(asistente) no la coge mientras esté «Sin programar». Empezará cuando la pases a Por hacer."
        case .esperaSuDia(let d): "\(asistente) la cogerá \(FormatoFicha.cuando(d, hoy: hoy)), su día planificado."
        case .enCola: "En cola: \(asistente) la cogerá en cuanto los asistentes estén encendidos."
        case .trabajando: "\(asistente) está trabajando en ella."
        case .esperaTuRespuesta: "\(asistente) espera tu respuesta: revisa lo que dejó y contéstale abajo."
        case .bloqueada: "Bloqueada: \(asistente) no sigue hasta que se resuelva lo que la bloquea."
        case .terminado: "Terminada. Ningún asistente la reabre solo."
        }
    }

    /// La palabra de la pastilla.
    var palabra: String {
        switch self {
        case .sinEmpezar: "Sin empezar"
        case .esperaSuDia: "Espera su día"
        case .enCola: "En cola"
        case .trabajando: "Trabajando"
        case .esperaTuRespuesta: "Espera tu respuesta"
        case .bloqueada: "Bloqueada"
        case .terminado: "Terminado"
        }
    }
}
