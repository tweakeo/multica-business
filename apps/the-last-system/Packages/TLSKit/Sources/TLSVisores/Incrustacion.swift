import AppKit
import PDFKit
import SwiftUI
import TLSDesign

/// Un fichero incrustado en una nota (`![[factura.pdf#page=3]]`, `![](Materiales/acta.pdf)`, `![[logo.png|300]]`),
/// como en Obsidian (R1): un bloque de altura fija que se puede ampliar, con su nombre, «Abrir» y el menú del
/// fichero. Lo usa el editor (TLSEditor/TLSUI) para pintar las incrustaciones; el texto de la nota no cambia.
///
/// - PDF: visor compacto (sin panel) en la página de `#page=N`, con ‹ › y el número de página.
/// - Imagen: ajustada al ancho del bloque (o al de `|300`), sin pasar de su alto.
/// - Audio y vídeo: el reproductor del Mac.
/// - Otros: una tarjeta con el nombre y «Abrir».
/// - Solo en iCloud: no descarga al pintar; ofrece «Descargar y abrir» (acción explícita).
public struct IncrustacionFichero: View {
    let url: URL
    let tipo: TipoFichero
    let pagina: Int?
    let alto: CGFloat?
    let ancho: CGFloat?
    let titulo: String?
    let acceso: any AccesoICloud
    let alAbrir: (() -> Void)?
    @State private var ampliada = false
    @Environment(\.accessibilityReduceMotion) private var reducirMovimiento

    /// Desde una referencia ya leída (`ReferenciaIncrustada.leer`) y la URL que TLSUI resolvió.
    public init(url: URL, referencia: ReferenciaIncrustada, titulo: String? = nil,
                acceso: any AccesoICloud = AccesoICloudSistema(), alAbrir: (() -> Void)? = nil) {
        self.init(url: url, tipo: TipoFichero.de(extension: url.pathExtension), pagina: referencia.pagina,
                  alto: referencia.alto, ancho: referencia.ancho, titulo: titulo, acceso: acceso, alAbrir: alAbrir)
    }

    public init(url: URL, tipo: TipoFichero, pagina: Int? = nil, alto: CGFloat? = nil, ancho: CGFloat? = nil,
                titulo: String? = nil, acceso: any AccesoICloud = AccesoICloudSistema(), alAbrir: (() -> Void)? = nil) {
        self.url = url
        self.tipo = tipo
        self.pagina = pagina
        self.alto = alto
        self.ancho = ancho
        self.titulo = titulo
        self.acceso = acceso
        self.alAbrir = alAbrir
    }

    /// Alto del bloque si la nota no dice otro (`#height=`).
    nonisolated public static func altoPorDefecto(_ tipo: TipoFichero) -> CGFloat {
        switch tipo {
        case .pdf: 420
        case .imagen: 360
        case .video: 320
        case .audio: 52
        case .texto, .otro: 0
        }
    }

    /// Alto con «Ampliar».
    nonisolated public static func altoAmpliado(_ tipo: TipoFichero, base: CGFloat) -> CGFloat {
        tipo == .audio ? base : min(base * 2, 960)
    }

    private var altoActual: CGFloat {
        let base = alto ?? Self.altoPorDefecto(tipo)
        return ampliada ? Self.altoAmpliado(tipo, base: base) : base
    }

    private var nombreVisible: String { titulo ?? url.deletingPathExtension().lastPathComponent }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            cabecera
                .padding(.horizontal, TLSEspacio.e12)
                .frame(minHeight: TLSAltura.filaLista)
            if tipo.seIncrusta {
                ContenidoIncrustado(url: url, tipo: tipo, pagina: pagina, ancho: ancho, acceso: acceso, alAbrir: alAbrir)
                    .frame(height: altoActual)
                    .padding([.horizontal, .bottom], TLSEspacio.e8)
            }
        }
        .frame(maxWidth: ancho.map { max($0, 240) + 2 * TLSEspacio.e8 }, alignment: .leading)
        .background(forma.fill(TLSPaleta.superficie.color))
        .overlay(forma.strokeBorder(TLSPaleta.separador.color, lineWidth: 1))
        .animation(reducirMovimiento ? nil : TLSMovimiento.muelle, value: ampliada)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(tipo.nombre) incrustado: \(nombreVisible)")
    }

    private var cabecera: some View {
        HStack(spacing: TLSEspacio.e8) {
            Image(systemName: tipo.simbolo)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(nombreVisible)
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(tipo.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Spacer(minLength: TLSEspacio.e8)
            if tipo.seIncrusta, tipo != .audio {
                Button { ampliada.toggle() } label: {
                    Image(systemName: ampliada ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .tlsBoton(.discreto)
                .help(ampliada ? "Reducir" : "Ampliar")
                .accessibilityLabel(ampliada ? "Reducir" : "Ampliar")
            }
            if let alAbrir {
                Button("Abrir", action: alAbrir).tlsBoton(.secundario)
            }
            Menu {
                if tipo == .pdf || tipo == .imagen {
                    Button("Abrir en Vista Previa") { AccionesFichero.abrirEnVistaPrevia(url) }
                } else {
                    Button("Abrir con la app de siempre") { AccionesFichero.abrirConLaDeSiempre(url) }
                }
                Button("Mostrar en Finder") { AccionesFichero.mostrarEnFinder(url) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .tlsBoton(.discreto)
            .fixedSize()
            .help("Más")
            .accessibilityLabel("Más acciones de \(nombreVisible)")
        }
    }
}

/// Solo el contenido de una incrustación, sin franja de título: lo que el editor mete en su marco
/// (`TLSEditor.BloqueIncrustado`, con `IncrustacionFichero.altoPorDefecto` y `altoAmpliado`). Ocupa el alto que le
/// den. PDF compacto en la página de `#page=N` con ‹ › y el número de página; imagen ajustada (a `|ancho` si lo
/// hay); reproductor para audio y vídeo; para otros ficheros, su icono, nombre y «Abrir». Lo que está solo en
/// iCloud no se descarga al pintar: ofrece «Descargar y abrir».
public struct ContenidoIncrustado: View {
    let url: URL
    let tipo: TipoFichero
    let pagina: Int?
    let ancho: CGFloat?
    let acceso: any AccesoICloud
    let alAbrir: (() -> Void)?
    @State private var descarga: DescargaICloud?
    @State private var pdf: ControladorPDF?

    public init(url: URL, tipo: TipoFichero? = nil, pagina: Int? = nil, ancho: CGFloat? = nil,
                acceso: any AccesoICloud = AccesoICloudSistema(), alAbrir: (() -> Void)? = nil) {
        self.url = url
        self.tipo = tipo ?? TipoFichero.de(extension: url.pathExtension)
        self.pagina = pagina
        self.ancho = ancho
        self.acceso = acceso
        self.alAbrir = alAbrir
    }

    public var body: some View {
        Group {
            if let descarga {
                switch descarga.fase {
                case .lista:
                    cuerpo
                case .comprobando:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    EstadoDescargaVista(descarga: descarga, tipo: tipo, nombre: url.lastPathComponent, compacto: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
                }
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            let d = DescargaICloud(url: url, acceso: acceso)
            d.comprobar()
            descarga = d
        }
        .onDisappear { descarga?.cancelar() }
    }

    @ViewBuilder
    private var cuerpo: some View {
        switch tipo {
        case .pdf:
            if let pdf {
                VistaPDFKit(controlador: pdf)
                    .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if pdf.totalPaginas > 1 { paginador(pdf) }
                    }
                    .accessibilityLabel("PDF \(url.deletingPathExtension().lastPathComponent), \(pdf.textoPagina)")
            } else {
                Color.clear.onAppear {
                    let c = ControladorPDF()
                    c.cargar(url: url, pagina: pagina)
                    pdf = c
                }
            }
        case .imagen:
            Button { alAbrir?() } label: {
                MiniaturaFicheroVista(url: url, tipo: .imagen, lado: max(ancho ?? 0, 900), acceso: acceso)
                    .frame(maxWidth: ancho ?? .infinity, maxHeight: .infinity)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(alAbrir == nil)
            .accessibilityLabel("Imagen \(url.lastPathComponent)")
        case .video:
            VistaAVPlayer(url: url, esVideo: true)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
        case .audio:
            VistaAVPlayer(url: url, esVideo: false)
        case .texto, .otro:
            HStack(spacing: TLSEspacio.e12) {
                Image(systemName: tipo.simbolo)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                Text(url.lastPathComponent).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                Spacer(minLength: TLSEspacio.e8)
                if let alAbrir { Button("Abrir", action: alAbrir).tlsBoton(.secundario) }
            }
            .padding(TLSEspacio.e12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func paginador(_ pdf: ControladorPDF) -> some View {
        HStack(spacing: 2) {
            Button { pdf.paginaAnterior() } label: { Image(systemName: "chevron.left") }
                .tlsBoton(.discreto).disabled(!pdf.puedeIrAtras).accessibilityLabel("Página anterior")
            Text("\(pdf.numeroPagina) / \(pdf.totalPaginas)")
                .tlsTexto(TLSTipo.cifraFila)
                .foregroundStyle(TLSPaleta.texto.color)
                .accessibilityLabel(pdf.textoPagina)
            Button { pdf.paginaSiguiente() } label: { Image(systemName: "chevron.right") }
                .tlsBoton(.discreto).disabled(!pdf.puedeIrAdelante).accessibilityLabel("Página siguiente")
        }
        .padding(.horizontal, 4)
        .background(Capsule(style: .circular).fill(TLSPaleta.superficieElevada.color))
        .tlsSombra(.dos, forma: Capsule(style: .circular))
        .padding(TLSEspacio.e8)
    }
}
