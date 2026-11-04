import Foundation
import TLSCore

/// «¿Algo rojo?» (PLAN §5.1): antes de lanzar a Mika, el núcleo pasa los chequeos y las comprobaciones deterministas
/// (`PanelMetricas`: números en alerta y reglas duras rotas). **Solo si hay rojo** se lanza el asistente, con lo rojo
/// como dato; si no, el trabajo queda hecho sin gastar nada: «Revisé a las 8:45: nada en rojo».
public enum ChequeoPrevio {
    public static func algoRojo(_ snapshot: VaultSnapshot, reloj: Reloj, hora: String) -> Precomprobacion {
        let panel = PanelMetricas.calcular(snapshot: snapshot, reloj: reloj)
        guard panel.hayRojo else { return .noHaceFalta(panel.lineaMika(hora: hora)) }
        let lista = panel.alertas.map { "- " + $0.texto }.joined(separator: "\n")
        return .lanzar(["en_rojo": "\n" + lista, "linea": panel.lineaMika(hora: hora)])
    }

    /// `8:45` (sin cero delante, como la línea de Mika).
    public static func hora(_ fecha: Date, zona: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.hour, .minute], from: fecha)
        return "\(c.hour ?? 0):" + String(format: "%02d", c.minute ?? 0)
    }
}
