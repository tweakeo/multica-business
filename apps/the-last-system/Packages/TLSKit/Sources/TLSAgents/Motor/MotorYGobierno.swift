import Foundation
import TLSCore

// Cómo se enchufa el motor al gobierno (TLSCore/Gobierno, rol gobierno): la configuración **confirmada** de los
// asistentes (`ConfigConfirmada`) y la comprobación de lanzamiento del único `Autorizador` (`puedeLanzar`).

/// ¿Puede salir ya un trabajo de la cola?
public enum PermisoDeLanzamiento: Sendable, Hashable {
    case puede
    /// Ahora no (interruptor, pausa, permisos cambiados fuera de la app…): el trabajo se queda en la cola.
    case espera(String)
}

/// Los ajustes que usa el motor, sacados de la configuración confirmada de gobierno: el texto confirmado (para las
/// rutinas, el modelo y los topes) restringido por la configuración efectiva (interruptor, `pausa_areas` y quién está
/// activo). Un cambio hecho fuera de la app no da más permisos hasta que la persona lo confirma.
public struct AjustesDeGobierno: FuenteDeAjustes {
    public let config: ConfigConfirmada

    public init(config: ConfigConfirmada) { self.config = config }
    public init(autorizador: Autorizador) { self.config = autorizador.config }

    public func ajustes() async -> AjustesDeAsistentes {
        let estado = config.leer()
        let texto = (try? config.estado.configConfirmada())?.texto
        return Self.combinar(confirmado: texto, efectiva: estado.efectiva)
    }

    /// El texto confirmado, con lo que la efectiva restringe.
    public static func combinar(confirmado texto: String?, efectiva e: ConfigAgentes) -> AjustesDeAsistentes {
        var a = AjustesDeAsistentes.leer(yaml: texto)
        a.interruptor = a.interruptor && e.encendido
        a.pausaAreas.formUnion(e.pausaAreas)
        for (slug, var g) in a.agentes {
            guard let ef = e.asistente(slug) else { g.activo = false; a.agentes[slug] = g; continue }
            g.activo = g.activo && ef.activo
            if !ef.areas.isEmpty { g.areas = ef.areas }
            g.maxTareasPorEjecucion = min(g.maxTareasPorEjecucion, ef.maxTareasPorEjecucion)
            if let p = ef.presupuestoEjecucionUSD { g.presupuestoEjecucionUSD = min(g.presupuestoEjecucionUSD, p) }
            if let p = ef.presupuestoMesUSD { g.presupuestoMesUSD = min(g.presupuestoMesUSD, p) }
            a.agentes[slug] = g
        }
        return a
    }
}

extension Autorizador {
    /// `puedeLanzar` para la cola: si no puede, el trabajo espera (queda apuntado en la auditoría).
    public func permisoDeLanzamiento(_ slug: String) -> PermisoDeLanzamiento {
        let d = puedeLanzar(slug)
        return d.permitido ? .puede : .espera(d.motivo)
    }
}
