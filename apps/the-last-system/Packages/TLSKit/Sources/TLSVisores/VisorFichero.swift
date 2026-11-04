import AppKit
import SwiftUI
import TLSDesign

/// Visor de un fichero de la carpeta (R1): elige el de su tipo (PDF, imagen, audio, vídeo o Quick Look) y se
/// ocupa de lo que está solo en iCloud.
///
/// - Recibe una URL ya comprobada por TLSUI (dentro de la carpeta). Nunca escribe en el fichero.
/// - **iCloud:** abrir es una acción explícita, así que con `descargaAutomatica` (el visor de pantalla
///   completa) pide la descarga al aparecer y enseña el progreso con «Volver a intentarlo». Sin ella (una
///   incrustación o una miniatura), espera a que la persona pulse «Descargar». Nunca descarga al recorrer.
/// - `pagina` (PDF) empieza en 1; `alCambiarPagina` avisa para recordarla.
public struct VisorFichero: View {
    let url: URL
    let tipo: TipoFichero
    let pagina: Int?
    let descargaAutomatica: Bool
    let acceso: any AccesoICloud
    let alCambiarPagina: ((Int) -> Void)?
    @State private var descarga: DescargaICloud?

    public init(url: URL, tipo: TipoFichero, pagina: Int? = nil, descargaAutomatica: Bool = true,
                acceso: any AccesoICloud = AccesoICloudSistema(), alCambiarPagina: ((Int) -> Void)? = nil) {
        self.url = url
        self.tipo = tipo
        self.pagina = pagina
        self.descargaAutomatica = descargaAutomatica
        self.acceso = acceso
        self.alCambiarPagina = alCambiarPagina
    }

    public var body: some View {
        Group {
            if let descarga {
                switch descarga.fase {
                case .lista:
                    visor
                case .comprobando:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                default:
                    EstadoDescargaVista(descarga: descarga, tipo: tipo, nombre: url.lastPathComponent)
                }
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            descarga?.cancelar()
            let d = DescargaICloud(url: url, acceso: acceso)
            d.comprobar()
            descarga = d
            if descargaAutomatica, d.fase == .soloEnICloud { d.descargar() }
        }
        .onDisappear { descarga?.cancelar() }
    }

    @ViewBuilder
    private var visor: some View {
        switch tipo {
        case .pdf:
            VisorPDF(url: url, pagina: pagina, alCambiarPagina: alCambiarPagina)
        case .imagen:
            VisorImagen(url: url)
        case .audio, .video:
            ReproductorMedio(url: url, tipo: tipo)
        case .texto, .otro:
            VistaQuickLook(url: url)
        }
    }
}

/// Lo que se ve mientras un fichero está solo en iCloud o bajando: el porqué, el progreso y qué hacer.
public struct EstadoDescargaVista: View {
    @Bindable var descarga: DescargaICloud
    let tipo: TipoFichero
    let nombre: String
    let compacto: Bool

    public init(descarga: DescargaICloud, tipo: TipoFichero, nombre: String, compacto: Bool = false) {
        self.descarga = descarga
        self.tipo = tipo
        self.nombre = nombre
        self.compacto = compacto
    }

    public var body: some View {
        VStack(alignment: compacto ? .leading : .center, spacing: TLSEspacio.e12) {
            Image(systemName: icono)
                .font(.system(size: compacto ? 20 : 32, weight: .regular))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            Text(titulo)
                .tlsTexto(compacto ? TLSTipo.tituloModulo : TLSTipo.tituloSeccion)
                .foregroundStyle(TLSPaleta.texto.color)
                .multilineTextAlignment(compacto ? .leading : .center)
                .accessibilityAddTraits(.isHeader)
            Text(descarga.texto)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .multilineTextAlignment(compacto ? .leading : .center)
                .frame(maxWidth: 460, alignment: compacto ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            if descarga.fase == .descargando || descarga.fase == .tardando {
                ProgressView(value: descarga.fraccion)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 280)
                    .accessibilityLabel("Descargando de iCloud")
            }
            HStack(spacing: TLSEspacio.e8) {
                switch descarga.fase {
                case .soloEnICloud:
                    Button("Descargar y abrir") { descarga.descargar() }.tlsBoton(.principal)
                case .tardando, .fallo:
                    Button("Volver a intentarlo") { descarga.reintentar() }.tlsBoton(.principal)
                default:
                    EmptyView()
                }
            }
        }
        .padding(compacto ? TLSEspacio.e16 : TLSEspacio.e32)
        .frame(maxWidth: .infinity, maxHeight: compacto ? nil : .infinity, alignment: compacto ? .leading : .center)
        .accessibilityElement(children: .contain)
    }

    private var icono: String {
        switch descarga.fase {
        case .fallo: "exclamationmark.icloud"
        case .noExiste: "questionmark.folder"
        default: "icloud.and.arrow.down"
        }
    }

    private var titulo: String {
        switch descarga.fase {
        case .noExiste: "No encuentro «\(nombre)»"
        case .fallo: "No se ha podido descargar"
        case .descargando, .tardando: "Bajando \(tipo.conEste) de iCloud"
        default: "\(tipo.conEste.prefix(1).uppercased() + tipo.conEste.dropFirst()) está en iCloud"
        }
    }
}
