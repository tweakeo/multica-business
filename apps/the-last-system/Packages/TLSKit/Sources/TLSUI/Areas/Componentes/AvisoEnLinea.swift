import SwiftUI
import TLSDesign

/// Un aviso de una línea: el icono en el color del estado y la frase en `texto` (el color nunca va solo).
struct AvisoEnLinea: View {
    let texto: String
    let estado: TLSEstado

    init(_ texto: String, estado: TLSEstado) {
        self.texto = texto
        self.estado = estado
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TLSEspacio.e8) {
            Image(systemName: estado.simbolo)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(estado.color.color)
                .accessibilityHidden(true)
            Text(texto)
                .tlsTexto(TLSTipo.interfaz)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(estado.palabra): \(texto)")
    }
}
