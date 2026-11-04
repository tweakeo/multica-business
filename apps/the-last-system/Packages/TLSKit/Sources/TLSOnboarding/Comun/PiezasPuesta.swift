import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. Piezas pequeñas de las pantallas de la puesta en marcha, con Mosaico v2: bloques en `superficie`
// (radio 22, sombra 1), filas y no tarjetas dentro, el origen de lo premarcado con su icono y su texto, «PENDIENTE»
// para «No lo sé», un campo de texto con el anillo de foco propio y una fila de chips que salta de línea.

/// Un bloque de la pantalla: `superficie`, radio 22 y sombra 1, con un rótulo opcional arriba.
struct BloquePuesta<Contenido: View>: View {
    var rotulo: String?
    var area: AreaCode?
    var icono: String?
    @ViewBuilder var contenido: Contenido

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e12) {
            if rotulo != nil || area != nil {
                HStack(spacing: TLSEspacio.e8) {
                    if let area {
                        IconoArea(area.tlsArea, tamano: 24)
                    } else if let icono {
                        IconoTipo(icono, tamano: 14)
                    }
                    if let rotulo {
                        Text(rotulo)
                            .tlsTexto(TLSTipo.tituloModulo)
                            .foregroundStyle(TLSPaleta.texto.color)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Spacer(minLength: 0)
                }
            }
            contenido
        }
        .padding(TLSEspacio.e20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .accessibilityElement(children: .contain)
    }
}

/// Una sección: un bloque propio o, dentro de otro bloque (los resúmenes), solo su rótulo (nunca tarjetas dentro de
/// tarjetas).
struct SeccionPuesta<Contenido: View>: View {
    let rotulo: String
    var icono: String?
    var anidada = false
    @ViewBuilder var contenido: Contenido

    var body: some View {
        if anidada {
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                HStack(spacing: 6) {
                    if let icono { IconoTipo(icono, tamano: 12) }
                    Rotulo(rotulo)
                }
                contenido
            }
            .padding(.top, TLSEspacio.e4)
            .accessibilityElement(children: .contain)
        } else {
            BloquePuesta(rotulo: rotulo, icono: icono) { contenido }
        }
    }
}

/// Filas de chips que saltan de línea cuando no caben.
struct FlujoChipsPuesta: Layout {
    var espacio: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ancho = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, fila: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > ancho { y += fila + espacio; x = 0; fila = 0 }
            x += s.width + espacio
            maxX = max(maxX, x - espacio)
            fila = max(fila, s.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + fila)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, fila: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { y += fila + espacio; x = bounds.minX; fila = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + espacio
            fila = max(fila, s.height)
        }
    }
}

/// De dónde sale una respuesta: «Lo saqué de Rumbo.md», «Propuesto: …», «Lo propone el asistente».
struct OrigenEtiqueta: View {
    let respuesta: Respuesta?

    var body: some View {
        if let r = respuesta, r.valor.esNoLoSe {
            PendienteEtiqueta()
        } else if let r = respuesta, r.origen.clase != .persona {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: Self.icono(r.origen.clase))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                Text(r.origen.texto)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    static func icono(_ c: OrigenRespuesta.Clase) -> String {
        switch c {
        case .carpeta: "doc.text"
        case .propuesta: "wand.and.stars"
        case .asistente: "sparkles"
        case .persona: "person"
        }
    }
}

/// «No lo sé»: se escribirá PENDIENTE.
struct PendienteEtiqueta: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("PENDIENTE")
                .tlsTexto(TLSTipo.rotulo)
                .foregroundStyle(TLSPaleta.texto.color)
                .padding(.horizontal, 8)
                .frame(minHeight: 20)
                .background(Capsule(style: .circular).fill(TLSEstado.sinDato.tinte.color))
            Text("Lo decides más tarde")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pendiente: lo decides más tarde")
    }
}

/// Campo de texto de Mosaico v2: `superficie`, borde de control, radio 10 y anillo de foco propio.
struct CampoPuesta: View {
    let titulo: String
    let ejemplo: String?
    @Binding var texto: String
    var varias: Bool = false
    var ancho: CGFloat? = nil
    var alGuardar: () -> Void = {}
    @FocusState private var enfocado: Bool

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous)
        Group {
            if varias {
                TextField(titulo, text: $texto, prompt: ejemplo.map { Text("Por ejemplo: \($0)") }, axis: .vertical)
                    .lineLimit(3...8)
            } else {
                TextField(titulo, text: $texto, prompt: ejemplo.map { Text("Por ejemplo: \($0)") })
                    .lineLimit(1)
            }
        }
        .textFieldStyle(.plain)
        .tlsTexto(TLSTipo.lectura)
        .foregroundStyle(TLSPaleta.texto.color)
        .focused($enfocado)
        .onSubmit(alGuardar)
        .onChange(of: enfocado) { _, ahora in if !ahora { alGuardar() } }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: ancho ?? .infinity, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
        .tlsAnilloFoco(enfocado, radio: TLSRadio.campo)
        .accessibilityLabel(titulo)
    }
}

/// Aviso en línea (lo que falta, un error, lo que se hace fuera de la carpeta): icono, texto y el color nunca solo.
struct AvisoEnLinea: View {
    let estado: TLSEstado
    let texto: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            Image(systemName: estado.simbolo)
                .foregroundStyle(estado.color.color)
                .accessibilityHidden(true)
            Text(texto)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(estado.tinte.color))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(estado.palabra): \(texto)")
    }
}

/// Nota informativa en `principalSuave` (la repregunta del entrevistador, lo que se hace fuera de la carpeta).
struct NotaPuesta: View {
    let icono: String
    let texto: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            Image(systemName: icono)
                .foregroundStyle(TLSPaleta.principal.color)
                .accessibilityHidden(true)
            Text(texto)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.principalSuave.color))
        .accessibilityElement(children: .combine)
    }
}

extension AreaCode {
    /// «Ventas» con su número: «2 · Ventas».
    var etiquetaPuesta: String { "\(numero) · \(nombre)" }
}

extension PasoPuesta {
    /// Icono del paso (barra de pasos y resúmenes).
    var icono: String {
        switch self {
        case .bienvenida, .alcance: "hand.wave"
        case .conocer: "text.magnifyingglass"
        case .ordenar: "tray.full"
        case .organizar: "square.grid.2x2"
        case .sinTi: "figure.walk.departure"
        case .diaADia: "calendar"
        case .numeros: "gauge.with.dots.needle.33percent"
        case .conectar: "cable.connector"
        case .recorrido: "map"
        }
    }
}

/// En un resumen (copia de G3), lo que no llegó premarcado: plegado en «Lo que falta (N)», con «Lo contesto luego»
/// (queda como «No lo sé» y se escribe PENDIENTE). Así el resumen enseña lo que hay que confirmar y no un cuestionario
/// largo y casi vacío. Se abre solo si, al pulsar «Siguiente», falta alguna de aquí.
struct LoQueFalta: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]
    @State private var abierto = false

    /// Lo que sigue sin contestar y no se puede dejar en blanco (las opcionales, como las ofertas 2 y 3, no cuentan).
    private var sinContestar: [Pregunta] { preguntas.filter { !$0.esOpcional && modelo.motor.estado.respuesta($0.id) == nil } }

    var body: some View {
        if !preguntas.isEmpty {
            let pendientes = sinContestar
            let ver = abierto || preguntas.contains { modelo.faltan.contains($0.id) }
            BloquePuesta(rotulo: pendientes.isEmpty ? "Lo que faltaba" : "Lo que falta (\(pendientes.count))", icono: "questionmark.circle") {
                Text(pendientes.isEmpty
                     ? "Ya está todo contestado. Lo que dijiste «No lo sé» queda como pendiente y te lo recuerdo."
                     : "No lo he encontrado en tu carpeta. Contéstalo ahora o pulsa «Lo contesto luego»: queda como pendiente y te lo recuerdo.")
                    .tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: TLSEspacio.e12) {
                    Button(ver ? "Ocultar" : "Contestarlo ahora") { abierto = !ver }
                        .tlsBoton(.enlace)
                        .accessibilityIdentifier("puesta.loQueFalta.ver")
                    Spacer(minLength: 0)
                    if !pendientes.isEmpty, !modelo.repasando {
                        Button("Lo contesto luego") { modelo.contestarLuego(pendientes.map(\.id)) }
                            .tlsBoton(.secundario)
                            .help("Lo que falta queda como «No lo sé»: se apunta PENDIENTE y lo ves en Hoy")
                            .accessibilityIdentifier("puesta.loQueFalta.luego")
                    }
                }
                if ver {
                    let grupos = Dictionary(grouping: preguntas) { $0.area }
                    let orden: [AreaCode?] = [nil] + AreaCode.allCases.map { Optional($0) }
                    VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                        ForEach(orden.filter { grupos[$0] != nil }, id: \.self) { a in
                            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                                if let a {
                                    HStack(spacing: TLSEspacio.e8) {
                                        IconoArea(a.tlsArea, tamano: 18)
                                        Text(a.nombre).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                                            .accessibilityAddTraits(.isHeader)
                                    }
                                }
                                ListaPreguntas(modelo: modelo, preguntas: grupos[a] ?? [], compacta: true)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("puesta.loQueFalta")
        }
    }
}
