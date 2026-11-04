import AppKit
import SwiftUI
import TLSCore

/// Menú Ayuda (PLAN §6.8): el manual, «De dónde salen las ideas», «Conoce la app con un ejemplo» y «Recorrido con
/// tu empresa». Se añade en `TLSScenes` con `.commands { ComandosAyuda(model: model) }`.
public struct ComandosAyuda: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.vaultSession) private var session

    public init(model: AppModel) { self.model = model }

    public var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Manual de The Last System") { abrirManual("") }
                .keyboardShortcut("?", modifiers: .command)
            Button("De dónde salen las ideas") { abrirManual(ManualNavegacion.seccionIdeas) }
            Divider()
            Button("Conoce la app con un ejemplo") { Task { await conocerConEjemplo() } }
            Button("Recorrido con tu empresa") {
                guard let id = session?.entry.id else { return }
                Task { await TutorialEventos.empezar(.tuEmpresa, empresa: id) }
            }
            .disabled(session == nil || session?.entry.clase == .demo || session?.puedeEscribir != true)
        }
    }

    private func abrirManual(_ seccion: String) {
        ManualNavegacion.compartida.abrir(seccion)
        openWindow(id: ManualNavegacion.idVentana)
    }

    /// Instala el ejemplo si no está, lo abre y empieza su recorrido (si ya se hizo, desde el principio).
    @MainActor
    private func conocerConEjemplo() async {
        do {
            let r = try await InstaladorEjemplo().instalarOAbrir(en: model)
            await TutorialEventos.empezar(.ejemplo, empresa: r.entrada.id)
            openWindow.abrirEmpresa(r.entrada.id)
        } catch {
            NSApp?.presentError(error)
        }
    }
}
