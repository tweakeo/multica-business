import SwiftUI
import TLSCore
import TLSDesign

/// El ritmo de un número o de un área (PLAN §6.5 `RhythmBadge`): pastilla con icono y palabra, nunca solo color.
/// «En ritmo», «Atención», «En alerta», «Sin meta» o «Sin dato» (y «En reposo» para un área parada).
struct RhythmBadge: View {
    let ritmo: RitmoNumero
    let palabra: String?
    let sobreColor: Bool

    init(_ ritmo: RitmoNumero, palabra: String? = nil, sobreColor: Bool = false) {
        self.ritmo = ritmo
        self.palabra = palabra
        self.sobreColor = sobreColor
    }

    /// El ritmo de un área entera: «En reposo» si está parada.
    init(area datos: DatosArea, sobreColor: Bool = false) {
        self.ritmo = datos.fase == .reposo ? .sinDato : datos.ritmo
        self.palabra = datos.fase == .reposo ? "En reposo" : nil
        self.sobreColor = sobreColor
    }

    var body: some View {
        PastillaEstado(ritmo.estado, palabra: palabra ?? ritmo.palabra, sobreColor: sobreColor)
            .accessibilityLabel("Ritmo: \(palabra ?? ritmo.palabra)")
    }
}
