import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import SwiftUI
import TLSDesign

/// Una miniatura ya pintada (CoreGraphics la deja inmutable: se puede pasar entre hilos).
public struct ImagenMiniatura: @unchecked Sendable {
    public let cg: CGImage
    public var tamano: CGSize { CGSize(width: cg.width, height: cg.height) }
}

/// Miniaturas de ficheros para las fichas, la Galería de las bases (F2) y las incrustaciones: la página de un
/// PDF, la imagen reducida o un fotograma del vídeo. **Nunca descarga de iCloud**: si el fichero no está en el
/// Mac devuelve `nil` (y quien la pinta enseña «Está en iCloud»).
public enum MiniaturaFichero {
    /// Pinta la miniatura fuera del hilo principal. `pagina` empieza en 1; `lado` es el lado mayor en píxeles.
    public static func generar(url: URL, tipo: TipoFichero? = nil, pagina: Int = 1, lado: CGFloat = 480,
                               acceso: any AccesoICloud = AccesoICloudSistema()) async -> ImagenMiniatura? {
        let tipo = tipo ?? TipoFichero.de(extension: url.pathExtension)
        guard acceso.estado(de: url) == .local else { return nil }
        switch tipo {
        case .pdf:
            return await Task.detached(priority: .utility) {
                AccesoICloudSistema.sinDescargar { paginaPDF(url: url, pagina: pagina, lado: lado) }
            }.value
        case .imagen:
            return await Task.detached(priority: .utility) {
                AccesoICloudSistema.sinDescargar { imagenReducida(url: url, lado: lado) }
            }.value
        case .video:
            return await fotograma(url: url, lado: lado)
        case .texto, .audio, .otro:
            return nil
        }
    }

    /// Número de páginas de un PDF que ya está en el Mac (sin descargarlo si no lo está).
    public static func paginas(dePDF url: URL, acceso: any AccesoICloud = AccesoICloudSistema()) -> Int? {
        guard acceso.estado(de: url) == .local else { return nil }
        return AccesoICloudSistema.sinDescargar { CGPDFDocument(url as CFURL)?.numberOfPages }
    }

    // MARK: Pintar

    static func paginaPDF(url: URL, pagina: Int, lado: CGFloat) -> ImagenMiniatura? {
        guard let doc = CGPDFDocument(url as CFURL), doc.numberOfPages > 0, !doc.isEncrypted || doc.isUnlocked else { return nil }
        let n = min(max(pagina, 1), doc.numberOfPages)
        guard let page = doc.page(at: n) else { return nil }
        let caja = page.getBoxRect(.cropBox)
        let giro = ((page.rotationAngle % 360) + 360) % 360
        let ancho = giro == 90 || giro == 270 ? caja.height : caja.width
        let alto = giro == 90 || giro == 270 ? caja.width : caja.height
        guard ancho > 0, alto > 0 else { return nil }
        let escala = lado / max(ancho, alto)
        let w = max(Int((ancho * escala).rounded()), 1)
        let h = max(Int((alto * escala).rounded()), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .high
        let destino = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: destino, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        return ctx.makeImage().map(ImagenMiniatura.init(cg:))
    }

    static func imagenReducida(url: URL, lado: CGFloat) -> ImagenMiniatura? {
        if url.pathExtension.lowercased() == "svg" {
            guard let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else { return nil }
            let escala = lado / max(img.size.width, img.size.height)
            var r = CGRect(x: 0, y: 0, width: img.size.width * escala, height: img.size.height * escala)
            return img.cgImage(forProposedRect: &r, context: nil, hints: nil).map(ImagenMiniatura.init(cg:))
        }
        guard let fuente = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opciones: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(lado),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(fuente, 0, opciones as CFDictionary).map(ImagenMiniatura.init(cg:))
    }

    static func fotograma(url: URL, lado: CGFloat) async -> ImagenMiniatura? {
        let generador = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generador.appliesPreferredTrackTransform = true
        generador.maximumSize = CGSize(width: lado, height: lado)
        guard let (cg, _) = try? await generador.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else { return nil }
        return ImagenMiniatura(cg: cg)
    }
}

/// Miniatura de un fichero para SwiftUI: la pinta en segundo plano y, mientras, o si está solo en iCloud, enseña
/// el icono del tipo. Nunca descarga.
public struct MiniaturaFicheroVista: View {
    let url: URL
    let tipo: TipoFichero
    let pagina: Int
    let lado: CGFloat
    let acceso: any AccesoICloud
    @State private var imagen: ImagenMiniatura?
    @State private var leida = false
    @State private var enICloud = false

    public init(url: URL, tipo: TipoFichero? = nil, pagina: Int = 1, lado: CGFloat = 480,
                acceso: any AccesoICloud = AccesoICloudSistema()) {
        self.url = url
        self.tipo = tipo ?? TipoFichero.de(extension: url.pathExtension)
        self.pagina = pagina
        self.lado = lado
        self.acceso = acceso
    }

    public var body: some View {
        ZStack {
            if let imagen {
                Image(decorative: imagen.cg, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: TLSEspacio.e8) {
                    Image(systemName: enICloud ? "icloud.and.arrow.down" : tipo.simbolo)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                    if enICloud {
                        Text("Está en iCloud").tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    } else if leida {
                        Text(tipo.nombre).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(url.path)#\(pagina)") {
            enICloud = { if case .soloEnICloud = acceso.estado(de: url) { return true }; return false }()
            imagen = enICloud ? nil : await MiniaturaFichero.generar(url: url, tipo: tipo, pagina: pagina, lado: lado, acceso: acceso)
            leida = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(enICloud ? "\(tipo.nombre) \(url.lastPathComponent), está en iCloud"
                                     : "\(tipo.nombre) \(url.lastPathComponent)" + (tipo == .pdf ? ", página \(pagina)" : ""))
    }
}

/// Vista previa compacta de un PDF para las fichas (factura, justificante, contrato, materiales): la primera
/// página (o la indicada) como papel, con su nombre, el número de páginas y «Abrir». No descarga de iCloud.
public struct VistaPreviaPDF: View {
    let url: URL
    let pagina: Int
    let titulo: String?
    let alto: CGFloat
    let alAbrir: (() -> Void)?
    let acceso: any AccesoICloud
    @State private var paginas: Int?

    public init(url: URL, pagina: Int = 1, titulo: String? = nil, alto: CGFloat = 320,
                acceso: any AccesoICloud = AccesoICloudSistema(), alAbrir: (() -> Void)? = nil) {
        self.url = url
        self.pagina = pagina
        self.titulo = titulo
        self.alto = alto
        self.acceso = acceso
        self.alAbrir = alAbrir
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.tarjeta, style: .continuous)
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            Button { alAbrir?() } label: {
                MiniaturaFicheroVista(url: url, tipo: .pdf, pagina: pagina, lado: alto * 2, acceso: acceso)
                    .frame(maxWidth: .infinity, minHeight: 80, maxHeight: alto)
                    .padding(TLSEspacio.e12)
                    .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(alAbrir == nil)
            .accessibilityLabel("Abrir el PDF \(titulo ?? url.lastPathComponent)")
            HStack(spacing: TLSEspacio.e8) {
                Image(systemName: TipoFichero.pdf.simbolo)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(titulo ?? url.deletingPathExtension().lastPathComponent)
                        .tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let paginas {
                        Text(paginas == 1 ? "1 página" : (pagina > 1 ? "Página \(pagina) de \(paginas)" : "\(paginas) páginas"))
                            .tlsTexto(TLSTipo.secundario)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                }
                Spacer(minLength: TLSEspacio.e8)
                if let alAbrir {
                    Button("Abrir", action: alAbrir).tlsBoton(.secundario)
                }
            }
        }
        .padding(TLSEspacio.e12)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .task(id: url) { paginas = MiniaturaFichero.paginas(dePDF: url, acceso: acceso) }
        .accessibilityElement(children: .contain)
    }
}
