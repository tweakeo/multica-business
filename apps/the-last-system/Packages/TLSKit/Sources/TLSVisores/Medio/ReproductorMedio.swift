import AVFoundation
import AVKit
import SwiftUI
import TLSDesign

/// La vista de AVKit para SwiftUI. Se para al salir de la pantalla.
struct VistaAVPlayer: NSViewRepresentable {
    let url: URL
    let esVideo: Bool

    final class Coordinador {
        var url: URL?
    }

    func makeCoordinator() -> Coordinador { Coordinador() }

    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.controlsStyle = esVideo ? .floating : .inline
        v.showsFullScreenToggleButton = esVideo
        v.allowsPictureInPicturePlayback = false
        v.showsSharingServiceButton = false
        v.videoGravity = .resizeAspect
        v.setAccessibilityLabel(esVideo ? "Vídeo \(url.lastPathComponent)" : "Audio \(url.lastPathComponent)")
        poner(url, en: v, context: context)
        return v
    }

    func updateNSView(_ v: AVPlayerView, context: Context) {
        if context.coordinator.url != url { poner(url, en: v, context: context) }
    }

    static func dismantleNSView(_ v: AVPlayerView, coordinator: Coordinador) {
        v.player?.pause()
        v.player = nil
    }

    private func poner(_ url: URL, en v: AVPlayerView, context: Context) {
        v.player?.pause()
        v.player = AVPlayer(url: url)
        context.coordinator.url = url
    }
}

/// Reproductor de audio y vídeo con los controles del Mac (AVKit). Recibe una URL ya en el Mac.
public struct ReproductorMedio: View {
    let url: URL
    let tipo: TipoFichero
    let barra: Bool

    public init(url: URL, tipo: TipoFichero, barra: Bool = true) {
        self.url = url
        self.tipo = tipo
        self.barra = barra
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(spacing: 0) {
            if barra {
                HStack(spacing: TLSEspacio.e8) {
                    Spacer(minLength: TLSEspacio.e8)
                    MenuAbrirCon(url: url)
                    Button { AccionesFichero.mostrarEnFinder(url) } label: { Image(systemName: "folder") }
                        .tlsBoton(.discreto).help("Mostrar en Finder").accessibilityLabel("Mostrar en Finder")
                }
                .padding(.horizontal, TLSEspacio.e12)
                .padding(.vertical, TLSEspacio.e8)
            }
            if tipo == .video {
                VistaAVPlayer(url: url, esVideo: true)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
                    .padding(barra ? [.horizontal, .bottom] : [], TLSEspacio.e12)
            } else {
                VStack(spacing: TLSEspacio.e16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityHidden(true)
                    Text(url.deletingPathExtension().lastPathComponent)
                        .tlsTexto(TLSTipo.tituloModulo)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    VistaAVPlayer(url: url, esVideo: false)
                        .frame(maxWidth: 520, minHeight: 44, maxHeight: 60)
                }
                .padding(TLSEspacio.e24)
                .frame(maxWidth: .infinity, maxHeight: barra ? .infinity : nil)
                .background(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous).fill(TLSPaleta.bandeja.color))
                .padding(barra ? [.horizontal, .bottom] : [], TLSEspacio.e12)
            }
        }
        .background(forma.fill(barra ? TLSPaleta.superficie.color : .clear))
        .modifier(SombraSi(activa: barra, forma: forma))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tipo == .video ? "Reproductor de vídeo" : "Reproductor de audio")
    }
}
