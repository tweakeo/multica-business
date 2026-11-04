import AppKit
import SwiftUI
import TLSCore

/// Acceso a la `NSWindow` de una pestaña de empresa (§7.1): pestañas del Mac agrupadas por empresa,
/// pestaña nueva «detrás» con ⌘clic, ventana suelta con ⌥⌘clic, y la sesión sabe qué pestaña tiene el
/// foco (para `navegar(a:)` y para el ⌘Z de lo escrito).
struct AccesoVentana: NSViewRepresentable {
    let empresa: UUID?
    let ruta: VentanaRuta?
    let nav: Navegacion
    @Environment(AppModel.self) private var model

    func makeNSView(context: Context) -> VistaAcceso {
        let v = VistaAcceso()
        v.configurar = { ventana in configurar(ventana, coordinador: context.coordinator) }
        return v
    }

    func updateNSView(_ nsView: VistaAcceso, context: Context) {
        context.coordinator.nav = nav
        context.coordinator.empresa = empresa
        context.coordinator.model = model
        // La navegación puede crearse después de entrar en la ventana (al restaurar o al abrir con destino).
        if nav.numeroVentana == nil, let w = nsView.window { nav.numeroVentana = w.windowNumber }
    }

    func makeCoordinator() -> Coordinador { Coordinador(nav: nav, empresa: empresa, model: model) }

    @MainActor
    private func configurar(_ ventana: NSWindow, coordinador: Coordinador) {
        if let empresa { ventana.tabbingIdentifier = AppModel.identificadorPestanas(empresa) }
        if ruta?.nuevaVentana == true {
            ventana.tabbingMode = .disallowed
            // Después de aparecer suelta, vuelve a admitir pestañas (⌘T dentro de ella).
            DispatchQueue.main.async { ventana.tabbingMode = .preferred }
        } else {
            ventana.tabbingMode = .preferred
        }
        nav.numeroVentana = ventana.windowNumber
        coordinador.observar(ventana)
        // ⌘clic: la pestaña nueva queda detrás y la de origen sigue delante.
        if let ruta, !ruta.alFrente, let origen = ruta.origen, let otra = NSApp.window(withWindowNumber: origen) {
            DispatchQueue.main.async {
                otra.tabGroup?.selectedWindow = otra
                otra.makeKeyAndOrderFront(nil)
            }
        } else {
            coordinador.activar(ventana)
        }
    }

    @MainActor
    final class Coordinador: NSObject {
        var nav: Navegacion
        var empresa: UUID?
        var model: AppModel
        private weak var ventana: NSWindow?

        init(nav: Navegacion, empresa: UUID?, model: AppModel) {
            self.nav = nav; self.empresa = empresa; self.model = model
        }

        func observar(_ ventana: NSWindow) {
            if let anterior = self.ventana {
                NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: anterior)
            }
            self.ventana = ventana
            // Con selector: el centro de notificaciones lo suelta solo al desaparecer el coordinador.
            NotificationCenter.default.addObserver(self, selector: #selector(seActivo(_:)),
                                                   name: NSWindow.didBecomeKeyNotification, object: ventana)
        }

        @objc nonisolated private func seActivo(_ aviso: Notification) {
            MainActor.assumeIsolated {
                if let ventana { activar(ventana) }
            }
        }

        /// Esta pestaña pasa a ser la activa de su empresa.
        func activar(_ ventana: NSWindow) {
            guard let empresa, let sesion = model.sesionAbierta(empresa) else { return }
            model.ultimaEmpresa = empresa
            sesion.navegacionActiva = nav
            sesion.undoManagerActivo = ventana.undoManager
        }
    }
}

/// Vista vacía que avisa cuando entra en su ventana.
final class VistaAcceso: NSView {
    var configurar: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { configurar?(window) }
    }
}

// MARK: Ventanas de una empresa

extension AppModel {
    /// Identificador con el que se agrupan en pestañas del Mac todas las ventanas de una empresa.
    nonisolated static func identificadorPestanas(_ empresa: UUID) -> String { "empresa-\(empresa.uuidString)" }

    /// Ventanas (pestañas incluidas) abiertas de una empresa.
    func ventanas(de empresa: UUID) -> [NSWindow] {
        let clave = Self.identificadorPestanas(empresa)
        return NSApp.windows.filter { $0.tabbingIdentifier == clave }
    }

    /// Cierra todas las ventanas de una empresa y espera, como mucho `espera`, a que su sesión se suelte
    /// (p. ej. antes de reiniciar el ejemplo). Devuelve `true` si la sesión ya está cerrada.
    @discardableResult
    func cerrarVentanas(de empresa: UUID, espera: Duration = .seconds(6)) async -> Bool {
        for ventana in ventanas(de: empresa) { ventana.close() }
        let reloj = ContinuousClock()
        let fin = reloj.now.advanced(by: espera)
        while sesionAbierta(empresa) != nil, reloj.now < fin {
            do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
        }
        return sesionAbierta(empresa) == nil
    }
}
