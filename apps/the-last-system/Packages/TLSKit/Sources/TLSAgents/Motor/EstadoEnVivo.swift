import Foundation
import Observation
import TLSCore

/// Cómo va un trabajo de un asistente ahora mismo (PLAN §6.4: «en cola, trabajando, esperando tu respuesta o
/// terminado»). Se calcula del stream **sin escribir nada en la carpeta**: la Actividad se escribe una sola vez, al
/// terminar (PLAN §11, conflictos de iCloud).
public struct TrabajoEnVivo: Sendable, Hashable, Identifiable {
    public enum Fase: String, Sendable, Hashable {
        case enCola, trabajando, esperandoRespuesta, terminado, fallido, cancelado
    }

    public var id: String { ejecucion }
    public var ejecucion: String
    public var agente: String
    public var tarea: VaultPath?
    public var fase: Fase
    /// «Leyendo…», «Creando tarea…», «Esperando tu respuesta» (sin jerga).
    public var frase: String
    public var desde: Date
    public var simulado: Bool

    /// Para `EstadoAsistenteTarea.de(…, enMarcha:)` de la ficha de tarea.
    public var enMarcha: Bool { fase == .trabajando }
}

/// Estado en vivo de los trabajos de una carpeta, para la interfaz (`@Observable`, en el hilo principal).
@MainActor
@Observable
public final class EstadoEnVivo {
    public private(set) var trabajos: [String: TrabajoEnVivo] = [:]
    /// Última frase de cada asistente («Revisé a las 8:45: nada en rojo»).
    public private(set) var ultimaFrase: [String: String] = [:]

    public init() {}

    /// El trabajo vivo (no terminado) de una tarea.
    public func trabajo(deTarea ruta: VaultPath) -> TrabajoEnVivo? {
        trabajos.values.filter { $0.tarea == ruta }.max { $0.desde < $1.desde }
    }

    public func trabajo(deAgente slug: String) -> TrabajoEnVivo? {
        trabajos.values.filter { $0.agente == slug }.max { $0.desde < $1.desde }
    }

    public var enCurso: [TrabajoEnVivo] { trabajos.values.filter { $0.fase == .trabajando }.sorted { $0.desde < $1.desde } }

    public func poner(_ t: TrabajoEnVivo) {
        trabajos[t.ejecucion] = t
    }

    public func frase(_ ejecucion: String, _ frase: String) {
        guard var t = trabajos[ejecucion], t.frase != frase else { return }
        t.frase = frase
        trabajos[ejecucion] = t
    }

    /// Al terminar: queda la última frase del asistente y el trabajo sale de la lista viva (salvo si espera respuesta).
    public func terminar(_ ejecucion: String, fase: TrabajoEnVivo.Fase, frase: String) {
        guard var t = trabajos[ejecucion] else { return }
        ultimaFrase[t.agente] = frase
        if fase == .esperandoRespuesta {
            t.fase = fase; t.frase = frase
            trabajos[ejecucion] = t
        } else {
            trabajos[ejecucion] = nil
        }
    }

    public func quitar(_ ejecucion: String) { trabajos[ejecucion] = nil }

    /// Frase en directo para un evento del stream (`nil` = no cambia).
    public nonisolated static func frase(para e: AgentEvent) -> String? {
        switch e {
        case .inicio: return "Empezando…"
        case .razonamiento: return "Pensando…"
        case .texto: return "Escribiendo…"
        case .herramienta(_, let nombre, _): return frase(herramienta: nombre.replacingOccurrences(of: "mcp__tls__", with: ""))
        case .reintento: return "Esperando a que responda el servicio…"
        case .limiteUso(let r) where r.status == "rejected": return "Límite de uso alcanzado"
        case .errorAPI: return "Problema con el servicio…"
        default: return nil
        }
    }

    public nonisolated static func frase(herramienta h: String) -> String {
        switch h {
        case "tls_leer", "tls_leer_sistema", "tls_listar", "tls_tareas", "tls_agenda", "tls_expediente", "tls_bitacora",
             "tls_estado", "tls_movimientos", "tls_correo_pendiente":
            return "Leyendo…"
        case "tls_buscar": return "Buscando…"
        case "tls_diagnostico": return "Revisando los números…"
        case "tls_crear_tarea": return "Creando tarea…"
        case "tls_actualizar_tarea": return "Actualizando la tarea…"
        case "tls_comentar": return "Comentando…"
        case "tls_preparar_borrador": return "Preparando un borrador…"
        case "tls_mover_archivo": return "Ordenando el Buzón…"
        case "tls_proponer_conciliacion": return "Proponiendo conciliaciones…"
        case "tls_avisar": return "Preparando un aviso…"
        case "tls_programar_seguimiento": return "Programando un seguimiento…"
        case "tls_delegar": return "Pasando trabajo a otro asistente…"
        case "tls_registrar_contacto", "tls_registrar_oportunidad", "tls_registrar_metricas_contenido",
             "tls_registrar_cobro_externo", "tls_registrar_decision":
            return "Apuntando…"
        case "tls_preguntar": return "Preparando una pregunta para ti…"
        case "tls_proponer": return "Preparando una propuesta…"
        case "tls_solicitar_accion": return "Pidiendo tu aprobación…"
        case "tls_finalizar": return "Terminando…"
        default: return h.hasPrefix("ext_") ? "Usando otro programa…" : "Trabajando…"
        }
    }
}
