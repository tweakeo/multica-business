import SwiftUI

extension EnvironmentValues {
    /// `true` dentro de un relleno de color (cabecera azul noche, destacado violeta, botón principal):
    /// allí el anillo de foco es blanco, porque el magenta no se vería (§1.5).
    @Entry public var tlsSobreColor: Bool = false
}

/// Anillo de foco de los controles propios (§1.5, pregunta 11): 2 pt de magenta con 2 pt de hueco del
/// color de debajo; 3 pt con «Aumentar contraste»; blanco sobre rellenos de color.
struct AnilloFocoModifier: ViewModifier {
    let visible: Bool
    let radio: CGFloat
    @Environment(\.tlsSobreColor) private var sobreColor
    @Environment(\.colorSchemeContrast) private var contraste

    func body(content: Content) -> some View {
        let grosor: CGFloat = contraste == .increased ? 3 : 2
        content.overlay {
            if visible {
                RoundedRectangle(cornerRadius: radio + 2 + grosor, style: .continuous)
                    .strokeBorder(sobreColor ? TLSPaleta.sobreColor.color : TLSPaleta.anillo.color, lineWidth: grosor)
                    .padding(-(2 + grosor))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Control propio enfocable con el teclado: sin el anillo del sistema y con el anillo magenta.
struct FocoPropioModifier: ViewModifier {
    let radio: CGFloat
    @FocusState private var enfocado: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($enfocado)
            .focusEffectDisabled()
            .tlsAnilloFoco(enfocado, radio: radio)
    }
}

public extension View {
    /// Dibuja el anillo de foco de Mosaico v2 alrededor de la vista cuando `visible`.
    /// `radio` es el de la forma de la vista (999 para una cápsula).
    func tlsAnilloFoco(_ visible: Bool, radio: CGFloat) -> some View {
        modifier(AnilloFocoModifier(visible: visible, radio: radio))
    }

    /// Hace la vista enfocable con el teclado y le pone el anillo propio (sin el del sistema).
    func tlsFocoPropio(radio: CGFloat) -> some View {
        modifier(FocoPropioModifier(radio: radio))
    }

    /// Marca que lo de dentro va sobre un relleno de color (el anillo de foco pasa a blanco).
    func tlsSobreColor(_ sobre: Bool = true) -> some View {
        environment(\.tlsSobreColor, sobre)
    }
}
