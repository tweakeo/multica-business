import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. Cómo se contesta cada tipo de pregunta (PLAN §6.7): opciones grandes y claras, escalas 1–5 con
// botones grandes, sí o no, texto corto, texto libre (en su propia pantalla), cifras con su unidad y «Sin meta», hora
// y ficheros. Cada pregunta enseña de dónde sale lo premarcado («Lo saqué de Rumbo.md»), tiene «No lo sé» (se
// escribe PENDIENTE) y, si el entrevistador repregunta, la repregunta debajo. Todo con teclado y VoiceOver.

/// Cómo se enseñan las opciones de una elección.
enum EstiloEleccion {
    /// Filas grandes con su detalle (2–4 opciones).
    case filas
    /// Cápsulas en una fila (días, estados).
    case chips
    /// Menú desplegable (muchas opciones).
    case menu
}

/// Una pregunta con su título, su control, su origen, «No lo sé» y la repregunta.
struct FilaPregunta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    var compacta = false
    var estilo: EstiloEleccion?
    /// Oculta el título (cuando el bloque ya lo dice).
    var sinTitulo = false
    /// Otro título, más corto, cuando el bloque ya dice de qué se habla («¿Lo tienes montado?»).
    var tituloPropio: String?
    /// Enseña la línea de ayuda de la pregunta.
    var conAyuda = true

    private var titulo: String { tituloPropio ?? pregunta.texto }

    private var falta: Bool { modelo.faltan.contains(pregunta.id) }

    var body: some View {
        Group {
            if compacta {
                HStack(alignment: .top, spacing: TLSEspacio.e16) {
                    VStack(alignment: .leading, spacing: 2) {
                        if !sinTitulo {
                            Text(titulo)
                                .tlsTexto(TLSTipo.interfazFuerte)
                                .foregroundStyle(TLSPaleta.texto.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if conAyuda, let a = pregunta.ayuda {
                            Text(a).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 230, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        ControlPregunta(modelo: modelo, pregunta: pregunta, estilo: estilo ?? .chips)
                        pie
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if pregunta.admiteNoLoSe { BotonNoLoSe(modelo: modelo, pregunta: pregunta) }
                }
            } else {
                VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                    HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e12) {
                        if !sinTitulo {
                            Text(titulo)
                                .tlsTexto(TLSTipo.tituloModulo)
                                .foregroundStyle(TLSPaleta.texto.color)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Spacer(minLength: 0)
                        if pregunta.admiteNoLoSe { BotonNoLoSe(modelo: modelo, pregunta: pregunta) }
                    }
                    if conAyuda, let a = pregunta.ayuda {
                        Text(a).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ref = pregunta.referencia {
                        Text(ref).tlsTexto(TLSTipo.interfaz.enItalica).foregroundStyle(TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ControlPregunta(modelo: modelo, pregunta: pregunta, estilo: estilo)
                    pie
                }
            }
        }
        .padding(falta ? TLSEspacio.e8 : 0)
        .background {
            if falta {
                RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
                    .strokeBorder(TLSPaleta.atencion.color, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(pregunta.texto)
        .accessibilityIdentifier("puesta.pregunta.\(pregunta.id.rawValue)")
    }

    @ViewBuilder
    private var pie: some View {
        OrigenEtiqueta(respuesta: modelo.respuesta(pregunta.id))
        if let rep = modelo.repreguntas[pregunta.id] {
            NotaPuesta(icono: "questionmark.bubble", texto: rep)
                .accessibilityIdentifier("puesta.repregunta.\(pregunta.id.rawValue)")
        }
        if falta {
            AvisoEnLinea(estado: .atencion, texto: "Contesta esta o pulsa «No lo sé».")
        }
    }
}

/// «No lo sé»: se guarda y se escribirá PENDIENTE.
struct BotonNoLoSe: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta

    var body: some View {
        let marcado = modelo.respuesta(pregunta.id)?.valor.esNoLoSe == true
        Button {
            modelo.noLoSeYGuardar(pregunta.id)
        } label: {
            Label("No lo sé", systemImage: marcado ? "checkmark.circle.fill" : "questionmark.circle")
        }
        .tlsBoton(.discreto)
        .accessibilityLabel("No lo sé: \(pregunta.texto)")
        .accessibilityAddTraits(marcado ? [.isSelected] : [])
        .accessibilityIdentifier("puesta.noLoSe.\(pregunta.id.rawValue)")
    }
}

/// El control de una pregunta según su tipo.
struct ControlPregunta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    var estilo: EstiloEleccion?

    var body: some View {
        switch pregunta.tipo {
        case .eleccion(let opciones):
            let e = estilo ?? (opciones.count > 7 ? .menu : (opciones.contains { $0.detalle != nil } || opciones.count <= 3 ? .filas : .chips))
            switch e {
            case .filas: OpcionesEnFilas(modelo: modelo, pregunta: pregunta, opciones: opciones)
            case .chips: OpcionesEnChips(modelo: modelo, pregunta: pregunta, opciones: opciones)
            case .menu: OpcionesEnMenu(modelo: modelo, pregunta: pregunta, opciones: opciones)
            }
        case .escala(let minimo, let maximo, let bajo, let alto):
            EscalaPuesta(modelo: modelo, pregunta: pregunta, minimo: minimo, maximo: maximo, bajo: bajo, alto: alto)
        case .siNo:
            SiNoPuesta(modelo: modelo, pregunta: pregunta)
        case .textoCorto(let ejemplo):
            TextoPregunta(modelo: modelo, pregunta: pregunta, ejemplo: ejemplo, varias: false)
        case .textoLibre(let ejemplo):
            TextoPregunta(modelo: modelo, pregunta: pregunta, ejemplo: ejemplo, varias: true)
        case .cifra(let unidad, let sinMeta):
            CifraPregunta(modelo: modelo, pregunta: pregunta, unidad: unidad, sinMeta: sinMeta)
        case .hora:
            HoraPregunta(modelo: modelo, pregunta: pregunta)
        case .rutas(let carpetas, _):
            RutasPregunta(modelo: modelo, pregunta: pregunta, carpetas: carpetas)
        }
    }
}

/// Lo elegido ahora en una pregunta de opción.
@MainActor
func elegida(_ modelo: ModeloPuesta, _ id: PreguntaID) -> String? { modelo.respuesta(id)?.valor.opcion }

/// Opciones en filas grandes: un círculo, el nombre y su detalle. La elegida, en azul noche.
struct OpcionesEnFilas: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let opciones: [OpcionPregunta]
    var icono: (OpcionPregunta) -> String? = { _ in nil }

    var body: some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            ForEach(opciones) { o in
                FilaOpcion(titulo: o.texto, detalle: o.detalle, icono: icono(o), elegida: elegida(modelo, pregunta.id) == o.id) {
                    Task { await modelo.contestar(pregunta.id, .opcion(o.id)) }
                }
                .accessibilityIdentifier("puesta.opcion.\(pregunta.id.rawValue).\(o.id)")
            }
        }
    }
}

/// Una opción en fila (también la usan las pantallas que eligen algo que no es una pregunta).
struct FilaOpcion: View {
    let titulo: String
    let detalle: String?
    var icono: String?
    let elegida: Bool
    var activa = true
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(alignment: .center, spacing: TLSEspacio.e12) {
                Image(systemName: elegida ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.bordeControl.color)
                    .accessibilityHidden(true)
                if let icono {
                    Image(systemName: icono)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .tlsTexto(TLSTipo.interfazFuerte.tamano(14, interlinea: 19))
                        .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detalle {
                        Text(detalle)
                            .tlsTexto(TLSTipo.interfaz)
                            .foregroundStyle(elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(EstiloOpcion(elegida: elegida))
        .disabled(!activa)
        .accessibilityLabel([titulo, detalle].compactMap { $0 }.joined(separator: ". "))
        .accessibilityAddTraits(elegida && activa ? [.isSelected] : [])
    }
}

/// Estilo de una opción grande: borde `separador`, `bandeja` al pasar, azul noche si está elegida y el anillo propio.
struct EstiloOpcion: ButtonStyle {
    let elegida: Bool
    var radio: CGFloat = TLSRadio.bloque

    func makeBody(configuration: Configuration) -> some View { Cuerpo(c: configuration, elegida: elegida, radio: radio) }

    private struct Cuerpo: View {
        let c: Configuration
        let elegida: Bool
        let radio: CGFloat
        @Environment(\.isFocused) private var enfocado
        @Environment(\.isEnabled) private var activo
        @State private var encima = false

        var body: some View {
            let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
            c.label
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: TLSAltura.filaLista)
                .background(forma.fill(relleno))
                .overlay(forma.strokeBorder(elegida ? Color.clear : TLSPaleta.separador.color, lineWidth: 1))
                .contentShape(forma)
                .opacity(activo ? 1 : 0.6)
                .tlsAnilloFoco(enfocado, radio: radio)
                .onHover { encima = $0 }
        }

        private var relleno: Color {
            if elegida { return TLSPaleta.principal.color }
            if c.isPressed { return TLSPaleta.principalSuave.color }
            return encima ? TLSPaleta.bandeja.color : TLSPaleta.superficie.color
        }
    }
}

/// Opciones en cápsulas (días, estados, montado / a medias / falta).
struct OpcionesEnChips: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let opciones: [OpcionPregunta]

    var body: some View {
        FlujoChipsPuesta(espacio: 8) {
            ForEach(opciones) { o in
                ChipOpcion(titulo: o.texto, elegida: elegida(modelo, pregunta.id) == o.id) {
                    Task { await modelo.contestar(pregunta.id, .opcion(o.id)) }
                }
                .help(o.detalle ?? o.texto)
                .accessibilityIdentifier("puesta.opcion.\(pregunta.id.rawValue).\(o.id)")
            }
        }
    }
}

/// Una cápsula elegible: `bandeja` con borde; elegida, azul noche con texto blanco y una marca.
struct ChipOpcion: View {
    let titulo: String
    let elegida: Bool
    var activa = true
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: 5) {
                // Desactivada no lleva marca: no lo has elegido tú (Mosaico §1.3).
                if elegida, activa {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).accessibilityHidden(true)
                }
                Text(titulo).lineLimit(1)
            }
        }
        .buttonStyle(EstiloChip(elegida: elegida && activa))
        .disabled(!activa)
        .accessibilityLabel(titulo)
        .accessibilityAddTraits(elegida && activa ? [.isSelected] : [])
    }
}

struct EstiloChip: ButtonStyle {
    let elegida: Bool

    func makeBody(configuration: Configuration) -> some View { Cuerpo(c: configuration, elegida: elegida) }

    private struct Cuerpo: View {
        let c: Configuration
        let elegida: Bool
        @Environment(\.isFocused) private var enfocado
        @Environment(\.isEnabled) private var activo
        @State private var encima = false

        var body: some View {
            // Desactivada: relleno y texto de botón desactivado (Mosaico §1.3; 4,5:1 también en oscuro), sin transparencia.
            c.label
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(!activo ? TLSPaleta.desactivadoTexto.color : (elegida ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color))
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(Capsule(style: .circular).fill(!activo ? TLSPaleta.desactivadoRelleno.color : (elegida ? TLSPaleta.principal.color
                    : (c.isPressed ? TLSPaleta.principalSuave.color : (encima ? TLSPaleta.bandeja.color : TLSPaleta.superficie.color)))))
                .overlay(Capsule(style: .circular).strokeBorder(elegida || !activo ? Color.clear : TLSPaleta.bordeControl.color, lineWidth: 1))
                .contentShape(Capsule(style: .circular))
                .tlsAnilloFoco(enfocado, radio: 999)
                .onHover { encima = $0 }
        }
    }
}

/// Muchas opciones: un menú (los procesos del alcance, los números clave).
struct OpcionesEnMenu: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let opciones: [OpcionPregunta]

    var body: some View {
        Picker(pregunta.texto, selection: Binding(
            get: { elegida(modelo, pregunta.id) ?? "" },
            set: { v in Task { await modelo.contestar(pregunta.id, .opcion(v)) } }
        )) {
            if elegida(modelo, pregunta.id) == nil { Text("Elige…").tag("") }
            ForEach(opciones) { o in Text(o.texto).tag(o.id) }
        }
        .labelsHidden()
        .frame(maxWidth: 460, alignment: .leading)
        .accessibilityLabel(pregunta.texto)
    }
}

/// Escala de 1 a 5 (o de 1 a 6) con botones redondos grandes y las palabras de los extremos.
struct EscalaPuesta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let minimo: Int
    let maximo: Int
    let bajo: String
    let alto: String

    var body: some View {
        let actual = modelo.respuesta(pregunta.id)?.valor.escala
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: TLSEspacio.e8) {
                ForEach(minimo...maximo, id: \.self) { n in
                    Button {
                        Task { await modelo.contestar(pregunta.id, .escala(n)) }
                    } label: {
                        Text("\(n)").tlsTexto(TLSEstiloTexto(.spaceGrotesk, peso: 600, tamano: 17, interlinea: 20, tabulares: true))
                    }
                    .buttonStyle(EstiloNumero(elegido: actual == n))
                    .accessibilityLabel("\(n) de \(maximo)" + (n == minimo ? ", \(bajo)" : n == maximo ? ", \(alto)" : ""))
                    .accessibilityAddTraits(actual == n ? [.isSelected] : [])
                    .accessibilityIdentifier("puesta.escala.\(pregunta.id.rawValue).\(n)")
                }
            }
            HStack {
                Text(bajo)
                Spacer()
                Text(alto)
            }
            .tlsTexto(TLSTipo.secundario)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .frame(width: CGFloat(maximo - minimo + 1) * 52 - 8)
            .accessibilityHidden(true)
        }
    }
}

/// Botón redondo de 44 pt de una escala.
struct EstiloNumero: ButtonStyle {
    let elegido: Bool

    func makeBody(configuration: Configuration) -> some View { Cuerpo(c: configuration, elegido: elegido) }

    private struct Cuerpo: View {
        let c: Configuration
        let elegido: Bool
        @Environment(\.isFocused) private var enfocado
        @State private var encima = false

        var body: some View {
            c.label
                .foregroundStyle(elegido ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(elegido ? TLSPaleta.principal.color
                    : (c.isPressed ? TLSPaleta.principalSuave.color : (encima ? TLSPaleta.bandeja.color : TLSPaleta.superficie.color))))
                .overlay(Circle().strokeBorder(elegido ? Color.clear : TLSPaleta.bordeControl.color, lineWidth: 1))
                .contentShape(Circle())
                .tlsAnilloFoco(enfocado, radio: 22)
                .onHover { encima = $0 }
        }
    }
}

/// Sí o no.
struct SiNoPuesta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    var si = "Sí"
    var no = "No"

    var body: some View {
        let actual = modelo.respuesta(pregunta.id)?.valor.siNo
        HStack(spacing: TLSEspacio.e8) {
            ChipOpcion(titulo: si, elegida: actual == true) { Task { await modelo.contestar(pregunta.id, .siNo(true)) } }
                .accessibilityIdentifier("puesta.si.\(pregunta.id.rawValue)")
            ChipOpcion(titulo: no, elegida: actual == false) { Task { await modelo.contestar(pregunta.id, .siNo(false)) } }
                .accessibilityIdentifier("puesta.no.\(pregunta.id.rawValue)")
        }
    }
}

/// Texto corto o libre. Se guarda al pulsar ↩, al salir del campo o al pulsar el botón de la pantalla.
struct TextoPregunta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let ejemplo: String?
    let varias: Bool

    var body: some View {
        CampoPuesta(titulo: pregunta.texto, ejemplo: ejemplo, texto: Binding(
            get: { modelo.borradores[pregunta.id] ?? modelo.respuesta(pregunta.id)?.valor.texto ?? "" },
            set: { modelo.borradores[pregunta.id] = $0 }
        ), varias: varias) {
            Task { await modelo.guardarBorrador(pregunta.id) }
        }
    }
}

/// Una cifra con su unidad y, si se puede, «Sin meta» (o «Sin alerta», en la alerta).
struct CifraPregunta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let unidad: String
    let sinMeta: Bool

    /// El texto de ejemplo del campo (el título no cabe en él y se cortaba: «¿Cuántas persona…»).
    static func ejemplo(_ unidad: String) -> String {
        switch unidad.lowercased() {
        case "€": "1200"
        case "%": "20"
        case "min": "30"
        case "h": "4"
        case "dias", "días", "d": "15"
        default: "3"
        }
    }

    var body: some View {
        let valor = modelo.respuesta(pregunta.id)?.valor
        let esSinMeta = valor?.opcion == "sin-meta"
        let esAlerta = pregunta.id.rawValue.hasSuffix(".alerta")
        HStack(spacing: TLSEspacio.e8) {
            CampoPuesta(titulo: pregunta.texto, ejemplo: Self.ejemplo(unidad), texto: Binding(
                get: { modelo.borradores[pregunta.id] ?? valor?.numero.map { FormatoBase.cifraParaEditar($0) } ?? "" },
                set: { modelo.borradores[pregunta.id] = $0 }
            ), ancho: 170) {
                Task { await modelo.guardarBorrador(pregunta.id) }
            }
            if !TextosUnidad.llana(unidad).isEmpty {
                Text(TextosUnidad.llana(unidad))
                    .tlsTexto(TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            if sinMeta {
                ChipOpcion(titulo: esAlerta ? "Sin alerta" : "Sin meta", elegida: esSinMeta) {
                    Task { await modelo.contestar(pregunta.id, .opcion("sin-meta")) }
                }
                .accessibilityIdentifier("puesta.sinMeta.\(pregunta.id.rawValue)")
            }
        }
    }
}

enum TextosUnidad {
    /// La unidad del catálogo en llano («%» y «€» se quedan; «dias» lleva tilde).
    static func llana(_ u: String) -> String {
        switch u.lowercased() {
        case "dias", "días", "d": "días"
        case "h": "horas"
        case "min": "minutos"
        case "n", "num", "numero", "número": ""
        default: u
        }
    }
}

/// Una hora (09:00).
struct HoraPregunta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta

    var body: some View {
        DatePicker(pregunta.texto, selection: Binding(
            get: { Self.fecha(modelo.respuesta(pregunta.id)?.valor.texto ?? "09:00") },
            set: { d in Task { await modelo.contestar(pregunta.id, .texto(Self.texto(d))) } }
        ), displayedComponents: .hourAndMinute)
        .datePickerStyle(.field)
        .labelsHidden()
        .frame(width: 110, alignment: .leading)
        .accessibilityLabel(pregunta.texto)
    }

    static func fecha(_ t: String) -> Date {
        let p = t.split(separator: ":").compactMap { Int($0) }
        var c = DateComponents()
        c.year = 2026; c.month = 1; c.day = 5
        c.hour = p.first ?? 9; c.minute = p.count > 1 ? p[1] : 0
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    static func texto(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
    }
}

/// Un fichero o una carpeta (el logo).
struct RutasPregunta: View {
    @Bindable var modelo: ModeloPuesta
    let pregunta: Pregunta
    let carpetas: Bool

    var body: some View {
        let rutas = modelo.respuesta(pregunta.id)?.valor.rutas ?? []
        HStack(spacing: TLSEspacio.e8) {
            ForEach(rutas, id: \.self) { r in
                Chip((r as NSString).lastPathComponent, icono: carpetas ? "folder" : "doc")
            }
            Button(rutas.isEmpty ? "Elegir…" : "Cambiar…") {
                let url: URL?
                if carpetas {
                    url = modelo.entorno.paneles.elegirCarpeta(mensaje: pregunta.texto)
                } else {
                    url = modelo.entorno.paneles.elegirFichero(mensaje: pregunta.ayuda ?? pregunta.texto,
                                                                tipos: ["svg", "pdf", "png", "jpg", "jpeg"])
                }
                if let url { Task { await modelo.contestar(pregunta.id, .rutas([url.path])) } }
            }
            .tlsBoton(.secundario)
            .accessibilityIdentifier("puesta.elegir.\(pregunta.id.rawValue)")
        }
    }
}

/// Las preguntas de una pantalla, una debajo de otra, con su separación.
struct ListaPreguntas: View {
    @Bindable var modelo: ModeloPuesta
    let preguntas: [Pregunta]
    var compacta = false

    var body: some View {
        VStack(alignment: .leading, spacing: compacta ? TLSEspacio.e12 : TLSEspacio.e20) {
            ForEach(preguntas) { q in
                FilaPregunta(modelo: modelo, pregunta: q, compacta: compacta)
                if compacta, q.id != preguntas.last?.id {
                    Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).accessibilityHidden(true)
                }
            }
        }
    }
}
