import SwiftUI

/// Un aviso breve con, si se puede, «Deshacer» («Enlacé la reunión del 14 oct a Arquitectura Nexo ·
/// Deshacer»). Dura 6 s a la vista (§5.4).
public struct Aviso: Identifiable, Equatable {
    public let id: UUID
    public let texto: String
    public let estado: TLSEstado?
    public let tituloAccion: String
    public let accion: (@MainActor () -> Void)?

    public init(_ texto: String, estado: TLSEstado? = nil, tituloAccion: String = "Deshacer",
                accion: (@MainActor () -> Void)? = nil) {
        self.id = UUID(); self.texto = texto; self.estado = estado; self.tituloAccion = tituloAccion
        self.accion = accion
    }

    public static func == (a: Aviso, b: Aviso) -> Bool { a.id == b.id }
}

/// Tarjeta del aviso: `superficieElevada`, sombra 2, radio 14 y el botón como enlace.
public struct AvisoDeshacer: View {
    let aviso: Aviso
    let cerrar: () -> Void

    public init(_ aviso: Aviso, cerrar: @escaping () -> Void) { self.aviso = aviso; self.cerrar = cerrar }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous)
        HStack(spacing: TLSEspacio.e8) {
            if let estado = aviso.estado {
                Image(systemName: estado.simbolo)
                    .foregroundStyle(estado.color.color)
                    .accessibilityLabel(estado.palabra)
            }
            Text(aviso.texto)
                .tlsTexto(TLSTipo.interfazMedia)
                .foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420, alignment: .leading)
            if let accion = aviso.accion {
                Button(aviso.tituloAccion) {
                    accion()
                    cerrar()
                }
                .tlsBoton(.enlace, alto: 44)
            }
            Button(action: cerrar) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .tlsBoton(.discreto)
            .accessibilityLabel("Cerrar el aviso")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(forma.fill(TLSPaleta.superficieElevada.color))
        .tlsSombra(.dos, forma: forma)
        .accessibilityElement(children: .contain)
    }
}

struct AvisoModifier: ViewModifier {
    @Binding var aviso: Aviso?
    @Environment(\.accessibilityReduceMotion) private var reducir

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let actual = aviso {
                AvisoDeshacer(actual) { if aviso == actual { aviso = nil } }
                    .padding(TLSEspacio.e16)
                    .transition(reducir ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: actual.id) {
                        AccessibilityNotification.Announcement(actual.texto).post()
                        try? await Task.sleep(for: TLSMovimiento.duracionAviso)
                        if aviso == actual { aviso = nil }
                    }
            }
        }
        .animation(TLSMovimiento.si(TLSMovimiento.muelle, reducir: reducir), value: aviso?.id)
    }
}

public extension View {
    /// Enseña el aviso abajo, lo anuncia a VoiceOver y lo quita a los 6 s.
    func tlsAviso(_ aviso: Binding<Aviso?>) -> some View {
        modifier(AvisoModifier(aviso: aviso))
    }
}
