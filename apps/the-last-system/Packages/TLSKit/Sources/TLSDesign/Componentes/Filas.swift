import SwiftUI

/// Fila de lista de 44 pt (§4.4 «Lista», pestañas de una ficha, recientes de Hoy): icono o icono de área,
/// título en `interfazFuerte`, una línea de detalle y, a la derecha, lo que se pase (estado, fecha, cifra).
/// Si tiene acción, es un botón con estado al pasar el puntero, pulsado, elegido y anillo de foco.
public struct FilaLista<Derecha: View>: View {
    let titulo: String
    let detalle: String?
    let icono: String?
    let area: TLSArea?
    let seleccionada: Bool
    let etiqueta: String?
    let accion: (() -> Void)?
    let derecha: Derecha

    public init(_ titulo: String, detalle: String? = nil, icono: String? = nil, area: TLSArea? = nil,
                seleccionada: Bool = false, etiquetaAccesible: String? = nil, accion: (() -> Void)? = nil,
                @ViewBuilder derecha: () -> Derecha) {
        self.titulo = titulo; self.detalle = detalle; self.icono = icono; self.area = area
        self.seleccionada = seleccionada; self.etiqueta = etiquetaAccesible; self.accion = accion
        self.derecha = derecha()
    }

    public var body: some View {
        if let accion {
            Button(action: accion) { contenido(pulsable: true) }
                .buttonStyle(EstiloFila(seleccionada: seleccionada))
                .focusEffectDisabled()
                .accessibilityLabel(etiquetaCompleta)
        } else {
            contenido(pulsable: false)
                .padding(.horizontal, 12)
                .frame(minHeight: TLSAltura.filaLista)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(etiquetaCompleta)
        }
    }

    private var etiquetaCompleta: String {
        etiqueta ?? [titulo, detalle].compactMap { $0 }.joined(separator: ", ")
    }

    private func contenido(pulsable: Bool) -> some View {
        HStack(spacing: TLSEspacio.e12) {
            if let area {
                IconoArea(area, tamano: 24, seleccionado: seleccionada)
            } else if let icono {
                Image(systemName: icono)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(seleccionada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(seleccionada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                    .lineLimit(1)
                if let detalle, !detalle.isEmpty {
                    Text(detalle)
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(seleccionada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: TLSEspacio.e8)
            derecha
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public extension FilaLista where Derecha == EmptyView {
    init(_ titulo: String, detalle: String? = nil, icono: String? = nil, area: TLSArea? = nil,
         seleccionada: Bool = false, etiquetaAccesible: String? = nil, accion: (() -> Void)? = nil) {
        self.init(titulo, detalle: detalle, icono: icono, area: area, seleccionada: seleccionada,
                  etiquetaAccesible: etiquetaAccesible, accion: accion, derecha: { EmptyView() })
    }
}

/// Estilo de una fila pulsable: `bandeja` al pasar, `principalSuave` al pulsar, azul noche si está elegida.
public struct EstiloFila: ButtonStyle {
    let seleccionada: Bool
    let alto: CGFloat

    public init(seleccionada: Bool = false, alto: CGFloat = TLSAltura.filaLista) {
        self.seleccionada = seleccionada; self.alto = alto
    }

    public func makeBody(configuration: Configuration) -> some View {
        Cuerpo(configuration: configuration, seleccionada: seleccionada, alto: alto)
    }

    private struct Cuerpo: View {
        let configuration: Configuration
        let seleccionada: Bool
        let alto: CGFloat
        @Environment(\.isFocused) private var enfocado
        @State private var encima = false

        var body: some View {
            let forma = RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
            configuration.label
                .padding(.horizontal, 12)
                .frame(minHeight: alto)
                .background(forma.fill(relleno))
                .contentShape(forma)
                .tlsAnilloFoco(enfocado, radio: TLSRadio.fila)
                .onHover { encima = $0 }
        }

        private var relleno: Color {
            if seleccionada { return TLSPaleta.principal.color }
            if configuration.isPressed { return TLSPaleta.principalSuave.color }
            return encima ? TLSPaleta.bandeja.color : .clear
        }
    }
}
