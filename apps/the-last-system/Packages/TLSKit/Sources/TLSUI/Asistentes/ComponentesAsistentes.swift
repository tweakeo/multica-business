import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. Piezas pequeñas que comparten Asistentes, la ficha de cada asistente, Equipo y la ficha de
// tarea: la pastilla de estado (icono y palabra; el color solo refuerza), la marca «Simulado», el icono de cada
// asistente, la barra de uso y la tarjeta de filas de Mosaico v2 («filas, no tarjetas»).

/// Estado de un asistente en una cápsula: icono propio y palabra (nunca solo color).
struct PastillaAsistente: View {
    let palabra: String
    let simbolo: String
    let estado: TLSEstado
    var sobreColor = false

    init(_ e: EstadoDeAsistente, sobreColor: Bool = false) {
        palabra = e.palabra; simbolo = e.simbolo; estado = e.tlsEstado; self.sobreColor = sobreColor
    }

    init(palabra: String, simbolo: String, estado: TLSEstado, sobreColor: Bool = false) {
        self.palabra = palabra; self.simbolo = simbolo; self.estado = estado; self.sobreColor = sobreColor
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: simbolo)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(sobreColor ? Self.enClaro(estado.color) : estado.color.color)
                .accessibilityHidden(true)
            Text(palabra)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(sobreColor ? Color(red: 15 / 255, green: 20 / 255, blue: 48 / 255) : TLSPaleta.texto.color)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 24)
        .background(Capsule(style: .circular).fill(sobreColor ? TLSPaleta.sobreColor.color : estado.tinte.color))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(palabra)
    }

    /// Sobre el blanco de la pastilla, el color de claro también en oscuro (el contraste es el de claro).
    static func enClaro(_ c: TLSColor) -> Color {
        TLSColor(c.id + ".claro", claro: c.claro, oscuro: c.claro, claroContraste: c.claroContraste, oscuroContraste: c.claroContraste).color
    }
}

/// «Simulado»: lo hizo la simulación del ejemplo, no un asistente de verdad. Nada salió de la empresa.
struct MarcaSimulado: View {
    var sobreColor = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "theatermasks")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
            Text("Simulado").tlsTexto(TLSTipo.secundario.peso(600))
        }
        .foregroundStyle(sobreColor ? TLSPaleta.sobreColor.color : TLSPaleta.textoSecundario.color)
        .padding(.horizontal, 7)
        .frame(minHeight: 20)
        .overlay(Capsule(style: .circular)
            .strokeBorder(sobreColor ? TLSPaleta.sobreColor.color.opacity(0.7) : TLSPaleta.bordeControl.color, lineWidth: 1))
        .fixedSize()
        .help("Lo hizo la simulación del ejemplo: nada salió de la empresa")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Simulado")
    }
}

/// El icono de un asistente: el icono de app de su área con el destello (`sparkle`); los del sistema, el Buzón.
struct IconoAsistente: View {
    let area: AreaCode?
    let simbolo: String
    var tamano: CGFloat = 28
    var atenuado = false

    init(_ a: AsistenteEnLista, tamano: CGFloat = 28) {
        area = a.esDelSistema ? nil : a.area
        simbolo = a.simbolo
        self.tamano = tamano
        atenuado = !a.activo
    }

    var body: some View {
        if let area {
            IconoArea(area.tlsArea, tamano: tamano, simbolo: simbolo, atenuado: atenuado)
        } else {
            let forma = RoundedRectangle(cornerRadius: tamano * TLSRadio.iconoArea24 / 24, style: .continuous)
            Image(systemName: simbolo)
                .font(.system(size: tamano * 0.5, weight: .semibold))
                .foregroundStyle(TLSPaleta.texto.color)
                .frame(width: tamano, height: tamano)
                .background(forma.fill(TLSPaleta.bandeja.color))
                .overlay(forma.strokeBorder(TLSPaleta.bordeControl.color, lineWidth: 1))
                .opacity(atenuado ? 0.6 : 1)
                .accessibilityHidden(true)
        }
    }
}

/// Barra del uso del mes frente al tope (azul noche; en ámbar desde el 80 %). La cifra va al lado, en texto.
struct BarraUso: View {
    let uso: UsoDelMes

    var body: some View {
        let alto: CGFloat = 8
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .circular).fill(TLSPaleta.bandeja.color)
                Capsule(style: .circular)
                    .fill(uso.fraccion >= 0.8 ? TLSPaleta.atencion.color : TLSPaleta.principal.color)
                    .frame(width: max(uso.usadoUSD > 0 ? alto : 0, geo.size.width * uso.fraccion))
            }
        }
        .frame(height: alto)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(uso.frase)
    }
}

/// Una tarjeta de filas (`superficie`, radio 22, sombra 1) con separadores entre filas.
struct TarjetaFilas<Contenido: View>: View {
    let contenido: Contenido

    init(@ViewBuilder _ contenido: () -> Contenido) { self.contenido = contenido() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { contenido }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous).fill(TLSPaleta.superficie.color))
            .tlsSombra(.uno, radio: TLSRadio.mosaico)
    }
}

/// Mosaicos en fila (con la misma altura) si hay ancho; si no, uno debajo de otro.
struct FilaOColumna<Contenido: View>: View {
    let umbral: CGFloat
    let contenido: Contenido
    @State private var ancho: CGFloat = 1100

    init(umbral: CGFloat = 860, @ViewBuilder _ contenido: () -> Contenido) {
        self.umbral = umbral
        self.contenido = contenido()
    }

    var body: some View {
        Group {
            if ancho >= umbral {
                HStack(alignment: .top, spacing: TLSEspacio.entreMosaicos) { contenido }
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: TLSEspacio.entreMosaicos) { contenido }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
    }
}

/// Separador entre filas de una tarjeta.
struct SeparadorFila: View {
    var sangria: CGFloat = 56

    var body: some View {
        Rectangle().fill(TLSPaleta.separador.color).frame(height: 1).padding(.leading, sangria)
            .accessibilityHidden(true)
    }
}

/// Título de una sección dentro de una pantalla de asistentes, con una línea que explica.
struct TituloSeccionAsistentes: View {
    let titulo: String
    var explicacion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .accessibilityAddTraits(.isHeader)
            if let explicacion {
                Text(explicacion).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }
}

/// Lista con viñetas de frases cortas.
struct ListaFrases: View {
    let frases: [String]
    var simbolo = "circle.fill"
    var tamanoSimbolo: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(frases.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: simbolo)
                        .font(.system(size: tamanoSimbolo, weight: .bold))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityHidden(true)
                    Text(f).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

extension VaultSession {
    /// Nombre de un asistente para las migas y las pestañas («Contable»).
    func nombreDeAsistente(_ slug: String) -> String {
        PerfilDeAsistente.deSerie.first { $0.slug == ConfigAgentes.slug(slug) }?.nombre ?? AsistenteConfigurado.nombre(de: slug)
    }
}
