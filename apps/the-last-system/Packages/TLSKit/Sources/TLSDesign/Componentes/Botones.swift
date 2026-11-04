import SwiftUI

/// Tipo de botón de Mosaico v2.
public enum TLSTipoBoton: Sendable, Hashable {
    /// Azul noche con texto blanco (en oscuro, `#7C8CFF` con texto `#0B1030`). Uno o dos por pantalla.
    case principal
    /// Cápsula con borde `bordeControl`, sin relleno.
    case secundario
    /// Sobre la cabecera azul noche: relleno blanco y texto azul noche.
    case sobreCabecera
    /// Dentro del destacado violeta: relleno blanco y texto violeta.
    case sobreDestacado
    /// Como un enlace: texto `enlace` subrayado («Deshacer», «Restaurar barra original»).
    case enlace
    /// Solo icono o texto, sin borde (barra de herramientas, filas).
    case discreto
}

/// Estilo de los botones propios: cápsula, objetivo mínimo, estados de §1.3 y anillo de foco magenta.
public struct TLSBotonStyle: ButtonStyle {
    let tipo: TLSTipoBoton
    let alto: CGFloat

    public init(_ tipo: TLSTipoBoton, alto: CGFloat? = nil) {
        self.tipo = tipo
        self.alto = alto ?? (tipo == .principal ? TLSAltura.botonPrincipal : TLSAltura.objetivoMinimo + 4)
    }

    public func makeBody(configuration: Configuration) -> some View {
        CuerpoBoton(tipo: tipo, alto: alto, configuration: configuration)
    }

    private struct CuerpoBoton: View {
        let tipo: TLSTipoBoton
        let alto: CGFloat
        let configuration: Configuration
        @Environment(\.isEnabled) private var activo
        @Environment(\.isFocused) private var enfocado
        @Environment(\.tlsSobreColor) private var sobreColor
        @State private var encima = false

        var body: some View {
            configuration.label
                .tlsTexto(TLSTipo.interfazFuerte)
                .lineLimit(1)
                .padding(.horizontal, tipo == .enlace || tipo == .discreto ? 6 : (alto < 40 ? 12 : 16))
                .frame(minWidth: TLSAltura.objetivoMinimo, minHeight: alto)
                .foregroundStyle(primerPlano)
                .underline(tipo == .enlace, pattern: .solid)
                .background(Capsule(style: .circular).fill(relleno))
                .overlay {
                    if tipo == .secundario {
                        Capsule(style: .circular).strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1)
                    } else if !activo, sobreRelleno {
                        // Desactivado sobre la cabecera o el destacado: borde blanco al 35 % (como el contorno de
                        // la cabecera), para que se vea dónde está el botón.
                        Capsule(style: .circular).strokeBorder(TLSPaleta.desactivadoSobreColorBorde.color, lineWidth: 1.5)
                    }
                }
                .contentShape(Capsule(style: .circular))
                .tlsAnilloFoco(enfocado && activo, radio: 999)
                .onHover { encima = $0 }
        }

        /// Botón que vive sobre un relleno de color (cabecera azul noche, destacado violeta).
        private var sobreRelleno: Bool { tipo == .sobreCabecera || tipo == .sobreDestacado }

        private var relleno: Color {
            guard activo else {
                return tipo == .principal ? TLSPaleta.desactivadoRelleno.color : .clear
            }
            switch tipo {
            case .principal:
                if configuration.isPressed { return TLSPaleta.principalPulsado.color }
                return encima ? TLSPaleta.principalHover.color : TLSPaleta.principal.color
            case .sobreCabecera, .sobreDestacado:
                return TLSPaleta.sobreColor.color.opacity(configuration.isPressed ? 0.85 : 1)
            case .secundario, .discreto:
                if configuration.isPressed { return TLSPaleta.principalSuave.color }
                return encima ? TLSPaleta.bandeja.color : .clear
            case .enlace:
                return .clear
            }
        }

        private var primerPlano: Color {
            // Desactivado sobre color: blanco al 70 % (≥ 4,5:1 sobre la cabecera y sobre el violeta). El gris de
            // desactivado sobre azul noche daba 1,9:1 y no se leía.
            guard activo else {
                return sobreRelleno || (sobreColor && tipo != .principal) ? TLSPaleta.desactivadoSobreColor.color
                    : TLSPaleta.desactivadoTexto.color
            }
            switch tipo {
            case .principal: return TLSPaleta.sobrePrincipal.color
            case .sobreCabecera: return TLSPaleta.cabecera.color
            case .sobreDestacado: return TLSPaleta.violeta.color
            case .secundario, .discreto: return TLSPaleta.texto.color
            // Sobre la cabecera azul noche (o el destacado), el enlace va en blanco subrayado (M2-Bases).
            case .enlace: return sobreColor ? TLSPaleta.sobreColor.color : TLSPaleta.enlace.color
            }
        }
    }
}

public extension View {
    /// Estilo de botón de Mosaico v2, sin el anillo del sistema (lleva el propio, magenta).
    func tlsBoton(_ tipo: TLSTipoBoton, alto: CGFloat? = nil) -> some View {
        buttonStyle(TLSBotonStyle(tipo, alto: alto)).focusEffectDisabled()
    }
}

/// Botón principal (azul noche, 44 pt). Si está desactivado, `motivo` dice al lado por qué (§1.3).
public struct BotonPrincipal: View {
    let titulo: String
    let icono: String?
    let motivo: String?
    let accion: () -> Void

    public init(_ titulo: String, icono: String? = nil, motivoDesactivado motivo: String? = nil, accion: @escaping () -> Void) {
        self.titulo = titulo; self.icono = icono; self.motivo = motivo; self.accion = accion
    }

    public var body: some View {
        HStack(spacing: TLSEspacio.e8) {
            Button(action: accion) {
                if let icono { Label(titulo, systemImage: icono) } else { Text(titulo) }
            }
            .tlsBoton(.principal)
            .disabled(motivo != nil)
            if let motivo {
                Text(motivo)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Botón secundario (cápsula con borde).
public struct BotonSecundario: View {
    let titulo: String
    let icono: String?
    let accion: () -> Void

    public init(_ titulo: String, icono: String? = nil, accion: @escaping () -> Void) {
        self.titulo = titulo; self.icono = icono; self.accion = accion
    }

    public var body: some View {
        Button(action: accion) {
            if let icono { Label(titulo, systemImage: icono) } else { Text(titulo) }
        }
        .tlsBoton(.secundario)
    }
}
