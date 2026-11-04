import SwiftUI
import TLSIntegracion
import TLSOnboarding
import TLSUI

@main
struct TheLastSystemApp: App {
    @NSApplicationDelegateAdaptor(TLSAppDelegate.self) private var appDelegate
    /// Un solo modelo para toda la app: el selector, las ventanas de empresa, el manual y la puesta en marcha.
    private let model: AppModel
    private let puesta: EntornoPuesta

    init() {
        let model = AppModel.deLaApp()
        // F4: los asistentes de cada empresa abierta (motor, `tls-mcp` y chat de Mika) se montan al abrirla con escritor
        // y se paran al cerrarla o al salir (antes de soltar el escritor).
        // F5: con cada empresa que escribe se montan también sus conexiones (Mail con el Cartero, Calendario y otros
        // programas) con lo del Mac de verdad; en el ejemplo, Mail y Calendario no se conectan y el programa es simulado.
        AsistentesDeLaApp.compartido.opciones.conexiones = .delMac
        AsistentesDeLaApp.compartido.instalar(en: model)
        self.model = model
        puesta = EntornoPuesta.deLaApp(model)
    }

    var body: some Scene {
        TLSScenes(model: model)
        // F3 · puesta en marcha (PLAN §6.7): la abre el arranque, Hoy, Ajustes y el tutorial por su identificador.
        OnboardingEscena(entorno: puesta)
    }
}
