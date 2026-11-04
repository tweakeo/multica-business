import SwiftUI
import TLSCore
import TLSDesign

/// Cabecera azul noche de la ficha, con la disposición de las maquetas `M2-Contacto` y `M2-Proyecto` (§3.1):
/// arriba, identidad (avatar, rótulo, título, resumen y código) y las acciones a la derecha, que saltan debajo
/// cuando no caben; abajo, a todo el ancho, la pastilla de estado editable y los datos clave, que saltan de
/// línea en vez de recortarse. Usa los valores de `TLSDesign` (`CabeceraAzulNoche` deja los datos y las acciones
/// en la misma fila, y con el destacado al lado se recortaban; ver «Cambios pedidos»).
struct CabeceraDeFicha<Identidad: View, Acciones: View>: View {
    let rotulo: String?
    let titulo: String
    let subtitulo: String?
    let codigo: String?
    let estado: EstadoCabecera?
    let datos: [DatoClave]
    let identidad: Identidad
    let acciones: Acciones

    init(rotulo: String?, titulo: String, subtitulo: String?, codigo: String?, estado: EstadoCabecera?, datos: [DatoClave],
         @ViewBuilder identidad: () -> Identidad, @ViewBuilder acciones: () -> Acciones) {
        self.rotulo = rotulo; self.titulo = titulo; self.subtitulo = subtitulo; self.codigo = codigo
        self.estado = estado; self.datos = Array(datos.prefix(3))
        self.identidad = identidad(); self.acciones = acciones()
    }

    var body: some View {
        let blanco = TLSPaleta.sobreColor.color
        let suave = TLSPaleta.subtituloCabecera.color
        VStack(alignment: .leading, spacing: TLSEspacio.e16) {
            FilaConAcciones(minimoPrincipal: 260, espacio: TLSEspacio.e16) {
                HStack(alignment: .top, spacing: TLSEspacio.e16) {
                    identidad
                    VStack(alignment: .leading, spacing: 4) {
                        if let rotulo {
                            Text(rotulo).tlsTexto(TLSTipo.secundario.peso(600)).foregroundStyle(suave)
                        }
                        Text(titulo)
                            .tlsTexto(TLSTipo.tituloPantalla)
                            .foregroundStyle(blanco)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        if let subtitulo, !subtitulo.isEmpty {
                            Text(subtitulo)
                                .tlsTexto(TLSTipo.interfaz)
                                .foregroundStyle(suave)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let codigo {
                            Text(codigo).tlsTexto(TLSTipo.codigo).foregroundStyle(suave)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: TLSEspacio.e8) { acciones }
                    .fixedSize()
            }
            if estado != nil || !datos.isEmpty {
                FlujoChips(espacio: TLSEspacio.e8) {
                    if let estado { EstadoEditableDeFicha(estado: estado) }
                    ForEach(datos) { dato in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dato.etiqueta).tlsTexto(TLSTipo.rotulo).foregroundStyle(suave)
                            Text(dato.valor).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(blanco).lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
                            .fill(TLSPaleta.sobreCabeceraSuave.color))
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.horizontal, TLSEspacio.e24)
        .padding(.vertical, TLSEspacio.e20)
        .frame(maxWidth: .infinity, minHeight: TLSAltura.cabeceraFichaMinima, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: TLSRadio.cabecera, style: .continuous).fill(TLSPaleta.cabecera.color))
        .tlsSobreColor()
        .accessibilityElement(children: .contain)
    }
}

/// Dos piezas en una fila (lo principal y las acciones a la derecha); si a lo principal le quedan menos de
/// `minimoPrincipal` puntos, las acciones pasan debajo, alineadas a la izquierda (el `flex-wrap` de las
/// maquetas).
struct FilaConAcciones: Layout {
    var minimoPrincipal: CGFloat = 260
    var espacio: CGFloat = 16
    var espacioVertical: CGFloat = 12

    private func medidas(_ ancho: CGFloat, _ subviews: Subviews) -> (enFila: Bool, principal: CGSize, acciones: CGSize) {
        let acciones = subviews[1].sizeThatFits(.unspecified)
        let enFila = ancho - acciones.width - espacio >= minimoPrincipal
        let anchoPrincipal = enFila ? ancho - acciones.width - espacio : ancho
        let principal = subviews[0].sizeThatFits(ProposedViewSize(width: anchoPrincipal, height: nil))
        return (enFila, CGSize(width: anchoPrincipal, height: principal.height), acciones)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }
        let ancho = proposal.width ?? (subviews[0].sizeThatFits(.unspecified).width + espacio + subviews[1].sizeThatFits(.unspecified).width)
        let m = medidas(ancho, subviews)
        let alto = m.enFila ? max(m.principal.height, m.acciones.height) : m.principal.height + espacioVertical + m.acciones.height
        return CGSize(width: ancho, height: alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else {
            subviews.first?.place(at: bounds.origin, proposal: proposal)
            return
        }
        let m = medidas(bounds.width, subviews)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: m.principal.width, height: m.principal.height))
        let origenAcciones = m.enFila
            ? CGPoint(x: bounds.maxX - m.acciones.width, y: bounds.minY)
            : CGPoint(x: bounds.minX, y: bounds.minY + m.principal.height + espacioVertical)
        subviews[1].place(at: origenAcciones, proposal: ProposedViewSize(m.acciones))
    }
}

/// La pastilla blanca del estado en la cabecera de la ficha: clic abre el menú con los estados posibles; los que
/// no se pueden elegir salen desactivados con su motivo (§3.1). Objetivo de 36 pt.
struct EstadoEditableDeFicha: View {
    let estado: EstadoCabecera
    @FocusState private var enfocado: Bool

    var body: some View {
        if estado.opciones.isEmpty {
            PastillaEstado(estado.estado, palabra: estado.palabra, sobreColor: true)
                .frame(minHeight: 36)
        } else {
            Menu {
                ForEach(estado.opciones) { opcion in
                    Button {
                        estado.alElegir(opcion)
                    } label: {
                        Text(opcion.titulo)
                        if let motivo = opcion.motivoDesactivado { Text(motivo) }
                    }
                    .disabled(opcion.motivoDesactivado != nil)
                }
            } label: {
                HStack(spacing: 2) {
                    PastillaEstado(estado.estado, palabra: estado.palabra, sobreColor: true)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(TLSPaleta.cabecera.color)
                        .padding(.trailing, 10)
                }
                .frame(minHeight: 36)
                .background(Capsule(style: .circular).fill(TLSPaleta.sobreColor.color))
                .contentShape(Capsule(style: .circular))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .focused($enfocado)
            .focusEffectDisabled()
            .tlsAnilloFoco(enfocado, radio: 999)
            .accessibilityLabel("Estado: \(estado.palabra)")
            .accessibilityHint("Cambia el estado")
        }
    }
}

/// Botón con contorno blanco sobre la cabecera azul noche, para las acciones que no son la principal («Nuevo»,
/// «⋯»), como en las maquetas: la principal va rellena de blanco y estas, solo con el borde.
struct EstiloContornoCabecera: ButtonStyle {
    /// 44 pt, como la acción principal de la cabecera (M2-Contacto, M2-Proyecto).
    var alto: CGFloat = TLSAltura.botonPrincipal

    func makeBody(configuration: Configuration) -> some View {
        Cuerpo(alto: alto, configuration: configuration)
    }

    private struct Cuerpo: View {
        let alto: CGFloat
        let configuration: Configuration
        @Environment(\.isEnabled) private var activo
        @Environment(\.isFocused) private var enfocado
        @State private var encima = false

        var body: some View {
            configuration.label
                .tlsTexto(TLSTipo.interfazFuerte)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: alto, minHeight: alto)
                .foregroundStyle(TLSPaleta.sobreColor.color.opacity(activo ? 1 : 0.55))
                .background(Capsule(style: .circular).fill(Color.white.opacity(configuration.isPressed ? 0.22 : (encima && activo ? 0.12 : 0))))
                .overlay(Capsule(style: .circular).strokeBorder(Color.white.opacity(activo ? 0.75 : 0.35), lineWidth: 1.5))
                .contentShape(Capsule(style: .circular))
                .tlsAnilloFoco(enfocado && activo, radio: 999)
                .onHover { encima = $0 }
        }
    }
}
