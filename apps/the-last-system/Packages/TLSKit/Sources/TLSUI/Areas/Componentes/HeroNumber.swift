import SwiftUI
import TLSCore
import TLSDesign

/// La cifra protagonista de un área (PLAN §6.5 `HeroNumber`), dentro del destacado violeta: el número clave con
/// su valor, su meta y su alerta, su ritmo y de dónde sale. La primera vez (sin meta decidida) el valor no se
/// enseña: se pide antes la meta. Sin dato dice «Sin dato»; nunca un 0 de relleno.
struct HeroNumber: View {
    let fila: FilaControl

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Text(fila.indicador)
                .tlsTexto(TLSTipo.interfazFuerte)
                .fixedSize(horizontal: false, vertical: true)
            if fila.valorVisible {
                CifraDestacada(fila.textoValor, contexto: contexto)
            } else {
                Text("Fija la meta antes de ver el dato")
                    .tlsTexto(TLSTipo.tituloModulo)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: TLSEspacio.e8) {
                RhythmBadge(fila.ritmo, sobreColor: true)
                Text(fila.codigo).tlsTexto(TLSTipo.codigo)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Número clave. \(fila.etiquetaAccesible)")
    }

    /// «Meta 3 meses · alerta 2 meses · Sale de…».
    var contexto: String {
        var partes: [String] = []
        if fila.tieneMeta {
            partes.append("Meta \(fila.textoMeta)")
            if let a = fila.alerta, !a.isEmpty { partes.append("alerta \(a)") }
        } else {
            partes.append("Sin meta")
        }
        if fila.lectura.estimado { partes.append("estimado") }
        if let f = fila.lectura.fuente { partes.append(f) }
        return partes.joined(separator: " · ")
    }
}
