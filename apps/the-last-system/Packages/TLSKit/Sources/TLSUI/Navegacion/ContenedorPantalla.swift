import SwiftUI
import TLSCore
import TLSDesign

/// Contenedor de una pantalla con desplazamiento: ancho máximo de 1.240 pt centrado, márgenes de 24 pt
/// (16 por debajo de 900) y el desplazamiento recordado al volver con Atrás o con su miga (§11.1).
struct ContenedorPantalla<Contenido: View>: View {
    let destino: Destino
    let espacio: CGFloat
    let contenido: Contenido

    init(destino: Destino, espacio: CGFloat = TLSEspacio.e20, @ViewBuilder contenido: () -> Contenido) {
        self.destino = destino
        self.espacio = espacio
        self.contenido = contenido()
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: espacio) {
                    contenido
                }
                .padding(.horizontal, TLSEspacio.margenPantalla(ancho: geo.size.width))
                .padding(.top, TLSEspacio.e24)
                .padding(.bottom, TLSEspacio.e48)
                .frame(maxWidth: TLSAncho.contenidoMaximo, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .tlsRecordarDesplazamiento(destino)
        }
    }
}

/// Guarda el desplazamiento de un `ScrollView` en el recuerdo de su pantalla y lo restaura al volver.
struct RecordarDesplazamientoModifier: ViewModifier {
    let destino: Destino
    @Environment(\.navegacion) private var nav
    @State private var posicion = ScrollPosition(edge: .top)
    @State private var ultimo: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scrollPosition($posicion)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in ultimo = y }
            .task(id: destino.identidad) {
                guard let y = nav?.recuerdo(de: destino).desplazamiento, y > 0 else { return }
                // Deja que se pinte el contenido antes de desplazar.
                try? await Task.sleep(for: .milliseconds(30))
                posicion.scrollTo(y: y)
            }
            .onDisappear {
                nav?.actualizarRecuerdo(de: destino) { $0.desplazamiento = ultimo > 0 ? ultimo : nil }
            }
    }
}

extension View {
    /// Recuerda el desplazamiento de esta vista de desplazamiento para `destino` en la pestaña de ventana.
    func tlsRecordarDesplazamiento(_ destino: Destino) -> some View {
        modifier(RecordarDesplazamientoModifier(destino: destino))
    }
}
