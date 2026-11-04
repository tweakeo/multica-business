import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// Identificadores de escena.
public enum SceneID {
    public static let launcher = "launcher"
    public static let vault = "vault"
}

extension FocusedValues {
    /// Sesión de la ventana de empresa con el foco (para los menús y atajos).
    @Entry var vaultSession: VaultSession?
}

/// Escenas de la app. El target de Xcode instancia esto y, al lado, la puesta en marcha (`OnboardingEscena` de
/// TLSOnboarding) con el mismo `AppModel`.
///
/// - `Window("launcher")`: selector de empresa (y, la primera vez, la puesta en marcha en su lugar).
/// - `WindowGroup(id: "vault", for: VentanaRuta.self)`: ventanas de empresa con pestañas del Mac (§7.1).
/// - `Window("manual")`: el manual y «De dónde salen las ideas» (menú Ayuda, «Saber más»).
/// - `Settings`: Ajustes.
public struct TLSScenes: Scene {
    @State private var model: AppModel

    public init() {
        self.init(model: .deLaApp())
    }

    /// Con el modelo de la app (`AppModel.deLaApp()`), el mismo que usa la puesta en marcha.
    public init(model: AppModel) {
        TLSFuentes.registrar()
        _model = State(initialValue: model)
    }

    public var body: some Scene {
        Window("The Last System", id: SceneID.launcher) {
            LauncherView()
                .environment(model)
                .environment(\.tlsEscalaTexto, model.escalaTexto)
        }
        .defaultSize(width: 720, height: 520)
        .windowResizability(.contentMinSize)
        .commands {
            ComandosEmpresa(model: model)
            ComandosAyuda(model: model)
            // F4 · rol mika: ⌘J (Shell/BarraMenuMika).
            ComandosMika()
        }

        EscenaManual()

        WindowGroup("Empresa", id: SceneID.vault, for: VentanaRuta.self) { $ruta in
            VentanaEmpresa(ruta: $ruta)
                .environment(model)
                .environment(\.tlsEscalaTexto, model.escalaTexto)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified(showsTitle: false))

        Settings {
            AjustesPantalla(sesion: nil)
                .environment(model)
                .environment(\.tlsEscalaTexto, model.escalaTexto)
                .frame(width: 560, height: 520)
        }

        // F4 · rol mika: los asistentes en la barra de menús (opcional, apagado de serie; Shell/BarraMenuExtra).
        EscenaBarraDeMenus(model: model)
    }
}

public extension OpenWindowAction {
    /// Abre una empresa: si ya tiene ventana, la trae delante (una ventana por empresa, PLAN §6.1); si no,
    /// abre una en Hoy (o en `destino`). Para una pestaña más de la misma empresa, `pestanaNueva`.
    @MainActor
    func abrirEmpresa(_ id: UUID, destino: Destino? = nil) {
        if destino == nil, let ventana = NSApp.windows.first(where: { $0.tabbingIdentifier == AppModel.identificadorPestanas(id) && $0.isVisible }) {
            ventana.makeKeyAndOrderFront(nil)
            return
        }
        callAsFunction(id: SceneID.vault, value: VentanaRuta(empresa: id, destino: destino))
    }

    /// Pestaña nueva de la ventana de una empresa (⌘T), en Hoy.
    @MainActor
    func pestanaNueva(_ id: UUID, destino: Destino? = nil) {
        callAsFunction(id: SceneID.vault, value: VentanaRuta(empresa: id, destino: destino ?? .hoy))
    }
}

/// Menús y atajos (§2.1, §7.2). Actúan sobre la pestaña de ventana con el foco.
struct ComandosEmpresa: Commands {
    let model: AppModel
    @FocusedValue(\.vaultSession) private var session
    @FocusedValue(\.navegacion) private var nav
    @Environment(\.openWindow) private var openWindow

    private var lista: Bool { session?.isReady ?? false }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Pestaña nueva") {
                guard let id = session?.entry.id ?? model.ultimaEmpresa else { openWindow(id: SceneID.launcher); return }
                openWindow.pestanaNueva(id)
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("Elegir empresa…") { openWindow(id: SceneID.launcher) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            // F2: ⌘N crea una tarea con el contexto de la pantalla (en una base, su propio ⌘N crea una ficha de esa base).
            Button("Nueva tarea…") { nav?.hoja = .nuevaTarea }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!lista || nav == nil || !(session?.puedeEscribir ?? false))
            // PLAN §6.1: ⇧⌘N, una nota nueva (o de una plantilla) en la carpeta de la pantalla actual.
            Button("Nueva nota…") { nav?.hoja = .nuevaNota }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!lista || nav == nil || !(session?.puedeEscribir ?? false))
            Divider()
            Button("Buscar o hacer…") { nav?.hoja = .paleta }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!lista || nav == nil)
            Button("Abrir rápido…") { nav?.hoja = .abrirRapido }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!lista || nav == nil)
            Divider()
            Button("Mostrar en Finder") { session?.revealInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(session?.root == nil)
            Divider()
            // F3: la puesta en marcha (seguir, empezar o repasar), traer lo nuevo de la carpeta real y las tareas de Multica.
            Button(PuestaDeLaEmpresa.tituloMenu(session)) {
                guard let s = session else { return }
                openWindow(id: PuertaPuestaEnMarcha.ventanaID, value: PuestaDeLaEmpresa.peticion(s))
            }
            .disabled(session == nil || !(session?.isReady ?? false))
            Button("Actualizar la copia desde la real…") { nav?.hoja = .actualizarCopia }
                .disabled(!lista || nav == nil || !(session.map(PuestaDeLaEmpresa.sePuedeActualizarCopia) ?? false))
            Button("Importar tareas de Multica…") { nav?.hoja = .importarMultica }
                .disabled(!lista || nav == nil || !(session?.puedeEscribir ?? false))
        }

        CommandGroup(after: .sidebar) {
            Button("Mostrar u ocultar las propiedades") { session?.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(session == nil)
        }

        CommandMenu("Ir") {
            Button("Atrás") { nav?.irAtras() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(nav?.puedeIrAtras ?? false))
            Button("Adelante") { nav?.irAdelante() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(nav?.puedeIrAdelante ?? false))
            Divider()
            raiz("Hoy", .hoy, tecla: "1")
            raiz("Decisiones", .decisiones, tecla: "2")
            raiz("Tareas", .tareas, tecla: "3")
            ForEach(AreaCode.allCases, id: \.self) { code in
                raiz(session?.area(code)?.etiquetaNumerada ?? code.etiquetaNumerada, .area(code),
                     tecla: KeyEquivalent(Character(String(code.numero + 3))))
            }
            Divider()
            Button("Todas las bases") { nav?.nuevaRaiz(.todasLasBases) }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                .disabled(!lista || nav == nil)
            Button("Carpeta") { nav?.nuevaRaiz(.carpeta(nil)) }
                .disabled(!lista || nav == nil)
            Button("Revisar") { nav?.nuevaRaiz(.revisar) }
                .disabled(!lista || nav == nil)
            Button("Buscar en la carpeta") { nav?.nuevaRaiz(.busqueda("")) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(!lista || nav == nil)
        }
    }

    private func raiz(_ titulo: String, _ destino: Destino, tecla: KeyEquivalent) -> some View {
        Button(titulo) { nav?.nuevaRaiz(destino) }
            .keyboardShortcut(tecla, modifiers: .command)
            .disabled(!lista || nav == nil)
    }
}

/// Delegado mínimo: la app sigue abierta al cerrar la última ventana.
@MainActor
public final class TLSAppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        TLSFuentes.registrar()
        // Las pestañas del Mac (§2.4): las ventanas de una empresa se agrupan.
        NSWindow.allowsAutomaticWindowTabbing = true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ⌘Q: antes de salir, los editores guardan lo que aún esperaba (los 800 ms tras la última tecla) y, en F4, se
    /// paran los asistentes de todas las empresas (`alSalir`: cola, servidor de herramientas y chat; ningún `tls-mcp`
    /// queda vivo). Como mucho se espera `esperaAlSalir` (o `esperaAlSalirConAsistentes`); después la app sale igual.
    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let registro = GuardadosPendientes.compartido
        let pendientes = registro.hayPendientes()
        let parar = Self.alSalir
        guard pendientes || parar != nil else { return .terminateNow }
        let respuesta = RespuestaSalida(sender)
        Task { @MainActor in
            try? await Task.sleep(for: parar == nil ? Self.esperaAlSalir : Self.esperaAlSalirConAsistentes)
            respuesta.responder()
        }
        Task { @MainActor in
            if pendientes { await registro.guardarTodo() }
            if let parar { await parar() }
            respuesta.responder()
        }
        return .terminateLater
    }

    static let esperaAlSalir: Duration = .seconds(5)
    /// Parar un trabajo en curso: SIGTERM al grupo y SIGKILL a los 5 s; con margen.
    static let esperaAlSalirConAsistentes: Duration = .seconds(9)

    /// F4 · integración: lo que hay que parar antes de salir (lo pone la app al arrancar).
    public static var alSalir: (@MainActor () async -> Void)?
}

/// Responde una sola vez a `applicationShouldTerminate` (lo que llegue antes: el guardado o el tope).
@MainActor
private final class RespuestaSalida {
    private weak var app: NSApplication?
    private var hecha = false
    init(_ app: NSApplication) { self.app = app }
    func responder() {
        guard !hecha else { return }
        hecha = true
        app?.reply(toApplicationShouldTerminate: true)
    }
}
