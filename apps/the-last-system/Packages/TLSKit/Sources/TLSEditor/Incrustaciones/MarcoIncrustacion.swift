import AppKit
import SwiftUI
import TLSDesign

/// Alto de la franja de arriba de una incrustación (icono, nombre, Abrir y Ampliar).
let altoFranjaIncrustacion: CGFloat = 36

/// Marco de una incrustación dentro de la nota: franja con el nombre, «Abrir» y «Ampliar/Reducir», y el
/// contenido que da el proveedor (PDF, imagen, reproductor) a una altura fija.
struct VistaMarcoIncrustacion: View {
    let bloque: BloqueIncrustado
    let ampliado: Bool
    let alAmpliar: () -> Void

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: bloque.simbolo)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                Text(bloque.titulo)
                    .tlsTexto(TLSTipo.interfazMedia)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let abrir = bloque.abrir {
                    Button("Abrir") { abrir() }
                        .tlsBoton(.discreto, alto: TLSAltura.objetivoMinimo)
                        .accessibilityLabel("Abrir \(bloque.titulo)")
                }
                Button(action: alAmpliar) {
                    Image(systemName: ampliado ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .tlsBoton(.discreto, alto: TLSAltura.objetivoMinimo)
                .help(ampliado ? "Reducir" : "Ampliar")
                .accessibilityLabel(ampliado ? "Reducir \(bloque.titulo)" : "Ampliar \(bloque.titulo)")
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: altoFranjaIncrustacion)
            Rectangle().fill(TLSPaleta.separador.color).frame(height: 1)
            bloque.contenido
                .frame(maxWidth: .infinity)
                .frame(height: ampliado ? bloque.altoAmpliado : bloque.alto)
                .clipped()
        }
        .background(forma.fill(TLSPaleta.superficie.color))
        .clipShape(forma)
        .overlay(forma.strokeBorder(TLSPaleta.separador.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Incrustado: \(bloque.titulo)")
    }
}

/// Vista de AppKit que lleva el marco (vive dentro del `NSTextView`, encima del hueco que deja el párrafo).
@MainActor
final class MarcoIncrustacion: NSHostingView<VistaMarcoIncrustacion> {
    let clave: String
    var bloque: BloqueIncrustado
    var ampliado: Bool { didSet { rootView = VistaMarcoIncrustacion(bloque: bloque, ampliado: ampliado, alAmpliar: alAmpliar) } }
    private let alAmpliar: () -> Void

    init(clave: String, bloque: BloqueIncrustado, ampliado: Bool, alAmpliar: @escaping () -> Void) {
        self.clave = clave
        self.bloque = bloque
        self.ampliado = ampliado
        self.alAmpliar = alAmpliar
        super.init(rootView: VistaMarcoIncrustacion(bloque: bloque, ampliado: ampliado, alAmpliar: alAmpliar))
        sizingOptions = []
    }

    @available(*, unavailable)
    required init(rootView: VistaMarcoIncrustacion) { fatalError("init(rootView:) no se usa") }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) no se usa") }

    /// Alto total del marco (franja + contenido).
    var alto: CGFloat { altoFranjaIncrustacion + 1 + (ampliado ? bloque.altoAmpliado : bloque.alto) }
}
