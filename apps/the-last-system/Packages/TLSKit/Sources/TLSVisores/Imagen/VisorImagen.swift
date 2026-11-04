import AppKit
import Observation
import SwiftUI
import TLSDesign

/// Estado del visor de imágenes: zoom con «Ajustar», «Tamaño real», acercar y alejar (también con el
/// gesto de pellizcar). Nunca escribe el fichero.
@Observable @MainActor
public final class ControladorImagen {
    public private(set) var url: URL?
    public private(set) var imagen: NSImage?
    /// Tamaño en píxeles (o en puntos, si es vectorial).
    public private(set) var tamano: CGSize = .zero
    public private(set) var escala: CGFloat = 1
    /// `true` mientras se ajusta sola al tamaño del visor.
    public private(set) var ajustada = true
    public private(set) var error: String?

    @ObservationIgnored public let lienzo = LienzoImagen()

    public static let escalaMinima: CGFloat = 0.05
    public static let escalaMaxima: CGFloat = 16

    public init() {
        lienzo.controlador = self
    }

    /// Abre una imagen que ya está en el Mac.
    @discardableResult
    public func cargar(url: URL) -> Bool {
        self.url = url
        guard let img = AccesoICloudSistema.sinDescargar({ NSImage(contentsOf: url) }), img.isValid else {
            imagen = nil
            lienzo.ponerImagen(nil, tamano: .zero)
            error = "No he podido abrir esta imagen. Puede que esté dañada o que el Mac no conozca su formato."
            return false
        }
        cargar(imagen: img)
        return true
    }

    public func cargar(imagen img: NSImage) {
        error = nil
        imagen = img
        tamano = Self.tamanoReal(de: img)
        img.size = tamano
        lienzo.ponerImagen(img, tamano: tamano)
        ajustar()
    }

    /// «1.200 × 800».
    public var textoTamano: String? {
        guard tamano.width > 0 else { return nil }
        return "\(Int(tamano.width)) × \(Int(tamano.height))"
    }

    public var textoEscala: String { "\(Int((escala * 100).rounded())) %" }

    /// Cabe entera en el visor (sin agrandar más de 4 veces).
    public func ajustar() {
        ajustada = true
        let visible = lienzo.contentSize
        guard tamano.width > 0, tamano.height > 0, visible.width > 0, visible.height > 0 else { return }
        let e = min(visible.width / tamano.width, visible.height / tamano.height, 4)
        ponerEscala(e, manteniendoAjuste: true)
    }

    public func tamanoReal() { ajustada = false; ponerEscala(1, manteniendoAjuste: false) }
    public func acercar() { ajustada = false; ponerEscala(escala * 1.25, manteniendoAjuste: false) }
    public func alejar() { ajustada = false; ponerEscala(escala / 1.25, manteniendoAjuste: false) }

    private func ponerEscala(_ e: CGFloat, manteniendoAjuste: Bool) {
        let limitada = min(max(e, Self.escalaMinima), Self.escalaMaxima)
        lienzo.magnification = limitada
        escala = limitada
        ajustada = manteniendoAjuste
    }

    /// Lo llama el lienzo al cambiar de tamaño o tras pellizcar.
    func lienzoCambio(pellizco: Bool) {
        if pellizco {
            ajustada = false
            escala = lienzo.magnification
        } else if ajustada {
            ajustar()
        }
    }

    static func tamanoReal(de img: NSImage) -> CGSize {
        if let bitmap = img.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
           bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }
        if let rep = img.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return img.size
    }
}

/// `NSScrollView` con la imagen centrada y zoom (pellizcar, ⌘+ ⌘−).
public final class LienzoImagen: NSScrollView {
    weak var controlador: ControladorImagen?
    let vistaImagen = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = ClipCentrado()
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        minMagnification = ControladorImagen.escalaMinima
        maxMagnification = ControladorImagen.escalaMaxima
        drawsBackground = false
        vistaImagen.imageScaling = .scaleAxesIndependently
        vistaImagen.imageFrameStyle = .none
        vistaImagen.setAccessibilityElement(true)
        vistaImagen.setAccessibilityRole(.image)
        documentView = vistaImagen
        NotificationCenter.default.addObserver(self, selector: #selector(finPellizco),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    func ponerImagen(_ img: NSImage?, tamano: CGSize) {
        vistaImagen.image = img
        vistaImagen.frame = NSRect(origin: .zero, size: tamano)
    }

    @objc private func finPellizco() {
        controlador?.lienzoCambio(pellizco: true)
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        controlador?.lienzoCambio(pellizco: false)
    }
}

/// Mantiene la imagen centrada cuando es más pequeña que el visor.
final class ClipCentrado: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return r }
        if r.width > doc.frame.width { r.origin.x = (doc.frame.width - r.width) / 2 }
        if r.height > doc.frame.height { r.origin.y = (doc.frame.height - r.height) / 2 }
        return r
    }
}

struct VistaLienzoImagen: NSViewRepresentable {
    let controlador: ControladorImagen
    let descripcion: String

    func makeNSView(context: Context) -> LienzoImagen {
        controlador.lienzo.vistaImagen.setAccessibilityLabel(descripcion)
        return controlador.lienzo
    }

    func updateNSView(_ v: LienzoImagen, context: Context) {
        v.vistaImagen.setAccessibilityLabel(descripcion)
    }
}

/// Visor de imágenes (png, jpg, heic, gif, webp, tiff, svg…) con zoom. Recibe una URL ya en el Mac.
public struct VisorImagen: View {
    let url: URL
    let barra: Bool
    @State private var controlador: ControladorImagen?

    public init(url: URL, barra: Bool = true) {
        self.url = url
        self.barra = barra
    }

    public var body: some View {
        Group {
            if let controlador {
                PanelVisorImagen(controlador: controlador, url: url, barra: barra)
                    .onChange(of: url) { _, nueva in controlador.cargar(url: nueva) }
            } else {
                Color.clear.onAppear {
                    let c = ControladorImagen()
                    c.cargar(url: url)
                    controlador = c
                }
            }
        }
    }
}

/// El visor de imágenes sobre un controlador ya cargado.
public struct PanelVisorImagen: View {
    @Bindable var controlador: ControladorImagen
    let url: URL
    let barra: Bool

    public init(controlador: ControladorImagen, url: URL, barra: Bool = true) {
        self.controlador = controlador
        self.url = url
        self.barra = barra
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(spacing: 0) {
            if barra {
                HStack(spacing: TLSEspacio.e8) {
                    if let t = controlador.textoTamano {
                        Text(t).tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    Spacer(minLength: TLSEspacio.e8)
                    Button { controlador.alejar() } label: { Image(systemName: "minus.magnifyingglass") }
                        .tlsBoton(.discreto).help("Alejar (⌘−)").accessibilityLabel("Alejar")
                    Text(controlador.textoEscala)
                        .tlsTexto(TLSTipo.cifraFila)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .frame(minWidth: 44)
                        .accessibilityLabel("Zoom \(controlador.textoEscala)")
                    Button { controlador.acercar() } label: { Image(systemName: "plus.magnifyingglass") }
                        .tlsBoton(.discreto).help("Acercar (⌘+)").accessibilityLabel("Acercar")
                    BotonAlternar(titulo: "Ajustar", icono: "arrow.up.left.and.arrow.down.right",
                                  activo: controlador.ajustada, etiqueta: "Ajustar al visor") { controlador.ajustar() }
                    BotonAlternar(titulo: "Tamaño real", icono: "1.magnifyingglass",
                                  activo: !controlador.ajustada && abs(controlador.escala - 1) < 0.001,
                                  etiqueta: "Tamaño real") { controlador.tamanoReal() }
                    Button { AccionesFichero.abrirEnVistaPrevia(url) } label: { Text("Abrir en Vista Previa") }
                        .tlsBoton(.secundario)
                    Button { AccionesFichero.mostrarEnFinder(url) } label: { Image(systemName: "folder") }
                        .tlsBoton(.discreto).help("Mostrar en Finder").accessibilityLabel("Mostrar en Finder")
                }
                .padding(.horizontal, TLSEspacio.e12)
                .padding(.vertical, TLSEspacio.e8)
            }
            Group {
                if let error = controlador.error {
                    VacioExplicado(icono: "photo.badge.exclamationmark", titulo: "No se puede enseñar esta imagen",
                                   porQue: error, accion: "Abrir con la app de siempre",
                                   alPulsar: { AccionesFichero.abrirConLaDeSiempre(url) })
                } else {
                    VistaLienzoImagen(controlador: controlador,
                                      descripcion: "Imagen \(url.lastPathComponent)" + (controlador.textoTamano.map { ", \($0)" } ?? ""))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
            .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
            .padding(barra ? [.horizontal, .bottom] : [], TLSEspacio.e12)
        }
        .background(forma.fill(barra ? TLSPaleta.superficie.color : .clear))
        .modifier(SombraSi(activa: barra, forma: forma))
        .background {
            Group {
                Button("") { controlador.acercar() }.keyboardShortcut("+", modifiers: .command)
                Button("") { controlador.acercar() }.keyboardShortcut("=", modifiers: .command)
                Button("") { controlador.alejar() }.keyboardShortcut("-", modifiers: .command)
                Button("") { controlador.tamanoReal() }.keyboardShortcut("0", modifiers: .command)
            }
            .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visor de imagen")
    }
}

/// Sombra de nivel 1 solo cuando el visor va en su tarjeta.
struct SombraSi<S: InsettableShape>: ViewModifier {
    let activa: Bool
    let forma: S
    func body(content: Content) -> some View {
        if activa { content.tlsSombra(.uno, forma: forma) } else { content }
    }
}
