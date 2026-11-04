import Foundation
import TLSCore

/// Uso de los asistentes (PLAN §5.3, «Uso»).
///
/// Dentro se guarda en USD (lo que devuelve el CLI en `total_cost_usd`); en pantalla nunca se enseñan dólares:
/// «uso del mes: 34 % de tu tope» (con suscripción no es un cargo real). Si el mes está agotado no se lanza nada y
/// salta un aviso. Lo simulado se apunta aparte y no gasta tope.
public struct CostLedger: Sendable {
    public let estado: EstadoDelMotor
    public let reloj: any RelojDelMotor
    public let zona: TimeZone
    /// Por debajo de esto no merece la pena lanzar (el CLI necesita algo para empezar): `fallida(.presupuesto)`.
    public static let minimoParaLanzarUSD = 0.01

    public init(estado: EstadoDelMotor, reloj: any RelojDelMotor, zona: TimeZone) {
        self.estado = estado; self.reloj = reloj; self.zona = zona
    }

    public var mes: String { reloj.mes(zona: zona) }

    public func apuntar(ejecucion: String, agente: String, usd: Double, simulado: Bool) throws {
        guard usd > 0 else { return }
        try estado.apuntarUso(ejecucion: ejecucion, agente: agente, mes: mes, usd: usd, fecha: reloj.ahora(), simulado: simulado)
    }

    public func usado(agente: String? = nil, incluirSimulado: Bool = false) -> Double {
        (try? estado.uso(mes: mes, agente: agente, incluirSimulado: incluirSimulado)) ?? 0
    }

    /// Lo que queda del tope del mes de un asistente (nunca negativo).
    public func resto(_ a: AjustesDeAsistente) -> Double {
        max(0, a.presupuestoMesUSD - usado(agente: a.slug))
    }

    /// `--max-budget-usd` de la siguiente ejecución: `min(tope de la ejecución, resto del mes)`; `nil` si no llega al
    /// mínimo (mes agotado).
    public func topeDeEjecucion(_ a: AjustesDeAsistente) -> Double? {
        let tope = min(a.presupuestoEjecucionUSD, resto(a))
        return tope >= Self.minimoParaLanzarUSD ? tope : nil
    }

    /// 0–100+ (puede pasar de 100 si la última ejecución se comió más del resto).
    public func porcentaje(_ a: AjustesDeAsistente, incluirSimulado: Bool = false) -> Int? {
        guard a.presupuestoMesUSD > 0 else { return nil }
        return Int((usado(agente: a.slug, incluirSimulado: incluirSimulado) / a.presupuestoMesUSD * 100).rounded())
    }

    /// «uso del mes: 34 % de tu tope» (sin dólares). Lo simulado lo dice.
    public func frase(_ a: AjustesDeAsistente, simulado: Bool = false) -> String {
        guard let p = porcentaje(a, incluirSimulado: simulado) else { return "Sin tope de uso fijado" }
        return "uso del mes: \(p) % de tu tope" + (simulado ? " (Simulado)" : "")
    }

    /// De todos los asistentes juntos, contra la suma de sus topes.
    public func fraseTotal(_ ajustes: AjustesDeAsistentes, simulado: Bool = false) -> String {
        let activos = ajustes.activos
        let tope = activos.reduce(0) { $0 + $1.presupuestoMesUSD }
        guard tope > 0 else { return "Sin tope de uso fijado" }
        let usado = activos.reduce(0) { $0 + self.usado(agente: $1.slug, incluirSimulado: simulado) }
        return "uso del mes: \(Int((usado / tope * 100).rounded())) % de tu tope" + (simulado ? " (Simulado)" : "")
    }
}
