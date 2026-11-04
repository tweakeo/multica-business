import Foundation
import TLSCore

// F4 · rol mika. Lo que hizo Mika en un turno del chat, como tarjetas enlazadas (tarea creada, borrador, pregunta,
// propuesta…). Sale de la auditoría del Autorizador (`estado.sqlite.auditoria`): cada herramienta que escribe pasa por
// él y queda apuntada con la ejecución del chat (`chat-…`). No se fía de lo que diga el texto de la respuesta.

/// Una cosa que dejó un asistente, enlazada a su ficha.
struct TarjetaEnlazada: Sendable, Hashable, Identifiable {
    enum Clase: String, Sendable, Hashable {
        case tarea, borrador, pregunta, propuesta, comentario, seguimiento, ficha, aprobacion, encargo, trabajo

        var icono: String {
            switch self {
            case .tarea: "checklist"
            case .borrador: "envelope"
            case .pregunta: "questionmark.bubble"
            case .propuesta: "signpost.right.and.left"
            case .comentario: "text.bubble"
            case .seguimiento: "alarm"
            case .ficha: "doc.text"
            case .aprobacion: "checkmark.seal"
            case .encargo: "arrow.turn.down.right"
            case .trabajo: "sparkle"
            }
        }
    }

    var id: String { clase.rawValue + ":" + (ruta?.raw ?? titulo) }
    let clase: Clase
    /// «Tarea creada», «Borrador preparado», «Pregunta para ti».
    let etiqueta: String
    let titulo: String
    let ruta: VaultPath?
    /// Lo que espera de ti, si espera algo («Espera tu OK en Decisiones»).
    let espera: String?
    /// La ejecución del trabajo (para el estado en vivo de un encargo).
    var ejecucion: String? = nil
}

/// Lo que importa de un apunte de la auditoría para las tarjetas (de `EstadoGobierno.Apunte`).
struct ApunteDeAsistente: Sendable, Hashable {
    let fecha: Date
    let accion: String
    let rutas: [VaultPath]
    let ejecucion: String?
    let decision: String

    init(fecha: Date, accion: String, rutas: [VaultPath], ejecucion: String?, decision: String) {
        self.fecha = fecha; self.accion = accion; self.rutas = rutas; self.ejecucion = ejecucion; self.decision = decision
    }

    init(_ a: EstadoGobierno.Apunte) {
        self.init(fecha: a.fecha, accion: a.accion, rutas: a.rutas, ejecucion: a.ejecucion, decision: a.decision)
    }
}

enum TarjetasEnlazadas {
    /// Las tarjetas de lo que hizo un chat (o un trabajo) desde `desde`, sin repetir y en orden.
    /// - Parameters:
    ///   - ejecucion: prefijo de la ejecución (`chat-…`; los turnos simulados añaden `-1`, `-2`…).
    ///   - titulo: título de una ficha (el del índice).
    ///   - privado: lo privado no se enseña (un asistente no puede escribirlo, pero por si acaso).
    static func de(_ apuntes: [EstadoGobierno.Apunte], ejecucion: String, desde: Date,
                   titulo: (VaultPath) -> String, privado: (VaultPath) -> Bool) -> [TarjetaEnlazada] {
        de(apuntes.map(ApunteDeAsistente.init), ejecucion: ejecucion, desde: desde, titulo: titulo, privado: privado)
    }

    static func de(_ apuntes: [ApunteDeAsistente], ejecucion: String, desde: Date,
                   titulo: (VaultPath) -> String, privado: (VaultPath) -> Bool) -> [TarjetaEnlazada] {
        var out: [TarjetaEnlazada] = []
        for a in apuntes where a.fecha >= desde.addingTimeInterval(-1) && (a.ejecucion?.hasPrefix(ejecucion) ?? false) {
            // Lo privado ni se mira (un asistente no puede escribirlo, pero por si acaso).
            guard !(a.rutas.first.map(privado) ?? false), let t = tarjeta(a, titulo: titulo) else { continue }
            if let i = out.firstIndex(where: { $0.id == t.id }) {
                // Lo último que se decidió sobre la misma ficha manda (una propuesta después de un permiso, por ejemplo).
                out[i] = t
            } else {
                out.append(t)
            }
        }
        return out
    }

    static func tarjeta(_ a: ApunteDeAsistente, titulo: (VaultPath) -> String) -> TarjetaEnlazada? {
        let ruta = a.rutas.first
        let nombre = ruta.map(titulo) ?? "Sin título"
        switch a.decision {
        case "permitido":
            switch a.accion {
            case "tarea.crear": return TarjetaEnlazada(clase: .tarea, etiqueta: "Tarea creada", titulo: nombre, ruta: ruta, espera: nil)
            case "tarea.mover": return TarjetaEnlazada(clase: .tarea, etiqueta: "Tarea actualizada", titulo: nombre, ruta: ruta, espera: nil)
            case "borrador.preparar":
                return TarjetaEnlazada(clase: .borrador, etiqueta: "Borrador preparado", titulo: nombre, ruta: ruta,
                                       espera: "No sale nada sin tu OK")
            case "preguntar":
                return TarjetaEnlazada(clase: .pregunta, etiqueta: "Pregunta para ti", titulo: nombre, ruta: ruta,
                                       espera: "Espera tu respuesta en Decisiones")
            case "proponer":
                return TarjetaEnlazada(clase: .propuesta, etiqueta: "Propuesta", titulo: nombre, ruta: ruta,
                                       espera: "Espera tu decisión en Decisiones")
            case "comentar": return TarjetaEnlazada(clase: .comentario, etiqueta: "Comentario", titulo: nombre, ruta: ruta, espera: nil)
            case "seguimiento.programar":
                return TarjetaEnlazada(clase: .seguimiento, etiqueta: "Seguimiento programado", titulo: nombre, ruta: ruta, espera: nil)
            case "delegar": return TarjetaEnlazada(clase: .encargo, etiqueta: "Encargo a otro asistente", titulo: nombre, ruta: ruta, espera: nil)
            case "contacto.registrar": return TarjetaEnlazada(clase: .ficha, etiqueta: "Contacto apuntado", titulo: nombre, ruta: ruta, espera: nil)
            case "oportunidad.registrar", "oportunidad.etapa":
                return TarjetaEnlazada(clase: .ficha, etiqueta: "Oportunidad apuntada", titulo: nombre, ruta: ruta, espera: nil)
            case "decision.registrar":
                return TarjetaEnlazada(clase: .ficha, etiqueta: "Decisión apuntada", titulo: nombre, ruta: ruta, espera: nil)
            default: return nil
            }
        case "aprobacion_requerida":
            return TarjetaEnlazada(clase: .aprobacion, etiqueta: "Pide tu OK", titulo: nombre, ruta: ruta,
                                   espera: "Espera tu OK en Decisiones › Para aprobar")
        case "propuesta":
            return TarjetaEnlazada(clase: .propuesta, etiqueta: "Propuesta", titulo: nombre, ruta: ruta,
                                   espera: "Espera tu decisión en Decisiones")
        case "tarea_para_persona":
            return TarjetaEnlazada(clase: .tarea, etiqueta: "Tarea para ti", titulo: nombre, ruta: ruta, espera: nil)
        default:
            return nil
        }
    }
}
