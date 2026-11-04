import AppKit
import QuickLookUI
import SwiftUI
import TLSDesign

/// La vista previa de Quick Look para SwiftUI.
struct VistaQLPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        v.autostarts = false
        v.shouldCloseWithWindow = true
        v.previewItem = url as NSURL
        v.setAccessibilityLabel("Vista previa de \(url.lastPathComponent)")
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != url { v.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) {
        v.close()
    }
}

/// Resto de ficheros (Word, Excel, Keynote, zip…): vista previa de Quick Look en un panel, con «Abrir con…».
public struct VistaQuickLook: View {
    let url: URL
    let barra: Bool

    public init(url: URL, barra: Bool = true) {
        self.url = url
        self.barra = barra
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(spacing: 0) {
            if barra {
                HStack(spacing: TLSEspacio.e8) {
                    Text("Vista previa del Mac. Para cambiarlo, ábrelo con su app.")
                        .tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(2)
                    Spacer(minLength: TLSEspacio.e8)
                    MenuAbrirCon(url: url)
                    Button { AccionesFichero.mostrarEnFinder(url) } label: { Image(systemName: "folder") }
                        .tlsBoton(.discreto).help("Mostrar en Finder").accessibilityLabel("Mostrar en Finder")
                }
                .padding(.horizontal, TLSEspacio.e12)
                .padding(.vertical, TLSEspacio.e8)
            }
            VistaQLPreview(url: url)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
                .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
                .padding(barra ? [.horizontal, .bottom] : [], TLSEspacio.e12)
        }
        .background(forma.fill(barra ? TLSPaleta.superficie.color : .clear))
        .modifier(SombraSi(activa: barra, forma: forma))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vista previa de \(url.lastPathComponent)")
    }
}
