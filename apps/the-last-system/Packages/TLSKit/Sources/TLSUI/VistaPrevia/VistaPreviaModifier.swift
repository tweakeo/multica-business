import AppKit
import SwiftUI
import TLSCore
import TLSDesign

extension EnvironmentValues {
    /// La empresa abierta en esta parte de la ventana (la pone la ficha; las demás pantallas pueden pasar la
    /// sesión a `.vistaPrevia(ruta:sesion:)`).
    @Entry var tlsSesionEmpresa: VaultSession? = nil
}

/// Vista previa al dejar el puntero 0,6 s (o con ⌘ pulsado, según Ajustes), con la barra espaciadora cuando la
/// vista tiene el foco y con la acción «Vista previa» de VoiceOver (§2.5, §7.7). Desaparece al salir con el
/// puntero, con 0,2 s de margen para poder entrar en ella. Nunca escribe; lo privado no se enseña.
struct VistaPreviaModifier: ViewModifier {
    let ruta: VaultPath
    let sesionDada: VaultSession?
    @Environment(\.tlsSesionEmpresa) private var sesionEntorno
    @Environment(\.navegacion) private var nav
    @Environment(\.navegar) private var navegar
    @Environment(AppModel.self) private var model: AppModel?
    @State private var visible = false
    @State private var dentroOrigen = false
    @State private var dentroTarjeta = false
    @State private var espera: Task<Void, Never>?

    private var sesion: VaultSession? {
        sesionDada ?? sesionEntorno ?? navegar.empresa.flatMap { model?.sesionAbierta($0) }
    }

    private var modo: ModoVistaPrevia { model?.modoVistaPrevia ?? .alPasar }

    func body(content: Content) -> some View {
        if let sesion, !sesion.esPrivado(ruta) {
            content
                .onHover { dentro in
                    dentroOrigen = dentro
                    dentro ? programarApertura() : programarCierre()
                }
                .popover(isPresented: $visible, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
                    VistaPreviaPopover(ruta: ruta, sesion: sesion, cerrar: { visible = false })
                        .environment(\.navegar, navegar)
                        .environment(\.navegacion, nav)
                        .onHover { dentro in
                            dentroTarjeta = dentro
                            if !dentro { programarCierre() }
                        }
                }
                .onKeyPress(.space) {
                    nav?.vistaPrevia = (nav?.vistaPrevia == ruta) ? nil : ruta
                    return nav == nil ? .ignored : .handled
                }
                .accessibilityAction(named: "Vista previa") {
                    if let nav { nav.vistaPrevia = ruta } else { visible = true }
                }
                .onDisappear { espera?.cancel() }
        } else {
            content
        }
    }

    private func programarApertura() {
        espera?.cancel()
        guard modo != .soloEspacio else { return }
        espera = Task { @MainActor in
            try? await Task.sleep(for: TLSMovimiento.esperaVistaPrevia)
            guard !Task.isCancelled, dentroOrigen else { return }
            if modo == .conComando, !NSEvent.modifierFlags.contains(.command) { return }
            visible = true
        }
    }

    private func programarCierre() {
        espera?.cancel()
        espera = Task { @MainActor in
            try? await Task.sleep(for: TLSMovimiento.margenSalidaVistaPrevia)
            guard !Task.isCancelled, !dentroOrigen, !dentroTarjeta else { return }
            visible = false
        }
    }
}

extension View {
    /// Vista previa de la ficha de `ruta` al pasar el puntero o con la barra espaciadora (§2.5). La sesión sale
    /// de la ficha que la contiene o de la empresa de la pestaña de ventana.
    func vistaPrevia(ruta: VaultPath?) -> some View {
        modifier(VistaPreviaOpcional(ruta: ruta, sesion: nil))
    }

    /// Igual, con la sesión dada (para pantallas fuera de una ficha: bases, búsqueda…).
    func vistaPrevia(ruta: VaultPath?, sesion: VaultSession) -> some View {
        modifier(VistaPreviaOpcional(ruta: ruta, sesion: sesion))
    }
}

/// `.vistaPrevia` sin ruta no hace nada.
struct VistaPreviaOpcional: ViewModifier {
    let ruta: VaultPath?
    let sesion: VaultSession?
    func body(content: Content) -> some View {
        if let ruta { content.modifier(VistaPreviaModifier(ruta: ruta, sesionDada: sesion)) } else { content }
    }
}
