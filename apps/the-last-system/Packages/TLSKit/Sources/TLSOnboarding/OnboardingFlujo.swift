import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos. La ventana y el flujo de la puesta en marcha (PLAN §6.7) con Mosaico v2: una ventana limpia, sin
// barra lateral; arriba la cabecera azul noche con el paso, la explicación de 2–3 líneas, «Quedan ~N min» y «Seguir
// más tarde» (siempre visibles); debajo la barra de avance por pasos; en medio la pantalla del paso; abajo «Atrás»
// (⌘[), «Saber más» y el botón principal (↩). Con «Reducir movimiento», las pantallas cambian sin desplazamiento.
// Los `init` son contrato (los usan la escena, el arranque y Hoy por `PuertaPuestaEnMarcha.ventanaID`).

/// La escena de la puesta en marcha: una ventana por petición. La declara la app (`App/Sources`).
public struct OnboardingEscena: Scene {
    let entorno: EntornoPuesta

    public init() { entorno = .compartido }

    /// Con lo que la app le pasa (el modelo de la app, el ejemplo…). Ver «Cambios pedidos › pasos».
    public init(entorno: EntornoPuesta) { self.entorno = entorno }

    public var body: some Scene {
        WindowGroup("Puesta en marcha", id: PuertaPuestaEnMarcha.ventanaID, for: PeticionPuestaEnMarcha.self) { $peticion in
            VentanaConLaApp(entorno: entorno) {
                OnboardingVentana(peticion: peticion ?? PeticionPuestaEnMarcha(modo: .empezar), entorno: entorno)
            }
        }
        .defaultSize(width: 920, height: 720)
        .windowResizability(.contentMinSize)
        .commands { EnganchesPuesta() }
    }
}

/// Con el modelo de la app en el entorno (y su tamaño de texto), como las ventanas de `TLSScenes`.
struct VentanaConLaApp<Contenido: View>: View {
    let entorno: EntornoPuesta
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        if let app = entorno.app {
            contenido()
                .environment(app)
                .environment(\.tlsEscalaTexto, app.escalaTexto)
        } else {
            contenido()
        }
    }
}

/// Deja puesto «Repasar la puesta en marcha» del tutorial (abre esta ventana en modo repaso). Los menús se construyen
/// al arrancar la app, así que aquí ya hay un `openWindow` que sirve para cualquier momento.
struct EnganchesPuesta: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        let abrir = openWindow
        let _ = Self.poner(abrir)
        CommandGroup(after: .windowList) {}
    }

    @MainActor
    static func poner(_ abrir: OpenWindowAction) -> Bool {
        ControladorTutorial.repasarPuestaEnMarcha = { sesion in
            abrir(id: PuertaPuestaEnMarcha.ventanaID, value: PeticionPuestaEnMarcha(modo: .repasar, vaultID: sesion.entry.id))
        }
        return true
    }
}

/// La ventana: abre (o retoma) la puesta en marcha que se pide. El modelo se crea una vez, al aparecer (crearlo abre
/// o retoma `onboarding.json`).
public struct OnboardingVentana: View {
    @State private var modelo: ModeloPuesta?
    private let peticion: PeticionPuestaEnMarcha
    private let entorno: EntornoPuesta
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var appDelEntorno: AppModel?

    public init(peticion: PeticionPuestaEnMarcha) {
        self.init(peticion: peticion, entorno: .compartido)
    }

    public init(peticion: PeticionPuestaEnMarcha, entorno: EntornoPuesta) {
        self.peticion = peticion
        self.entorno = entorno
    }

    public var body: some View {
        Group {
            if let modelo {
                OnboardingFlujo(modelo: modelo)
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 760, minHeight: 600)
        .background(TLSPaleta.fondo.color)
        .onAppear {
            guard modelo == nil else { return }
            if entorno.app == nil, let a = appDelEntorno { entorno.app = a }
            let m = ModeloPuesta(peticion: peticion, persona: entorno.app?.personaEfectiva ?? AppModel.personaPorDefecto)
            m.entorno = entorno
            let abrir = openWindow
            let cerrar = dismiss
            m.ventana = AccionesVentana(abrirEmpresa: { abrir.abrirEmpresa($0) },
                                        abrirSelector: { abrir(id: SceneID.launcher) },
                                        cerrar: { [weak m] in
                                            // «Seguir más tarde» sin otra ventana abierta: vuelve el selector (con su
                                            // «Seguir con la puesta en marcha»), para que la app no se quede sin ventana.
                                            if m?.terminada != true, Self.esLaUnicaVentana() { abrir(id: SceneID.launcher) }
                                            cerrar()
                                        })
            modelo = m
            // «Empezar de cero…» del arranque llega con la respuesta elegida (si aún no se había contestado).
            if let como = peticion.como, m.motor.estado.respuesta(.como) == nil {
                Task { await m.contestar(.como, .opcion(como)) }
            }
        }
        .onDisappear {
            // El modelo del paso 2 vive mientras dura la ventana.
            if let id = modelo?.motor.estado.vaultID { ConexionOrdenar.olvidar(id) }
        }
    }
}

extension OnboardingVentana {
    /// La ventana con el foco es la única visible de la app (sin contar paneles ni menús).
    @MainActor
    static func esLaUnicaVentana() -> Bool {
        let otras = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain && !$0.isKeyWindow && $0.level == .normal }
        return otras.isEmpty
    }
}

/// El flujo: la cabecera, la barra de pasos, la pantalla del paso actual y el pie con los botones.
public struct OnboardingFlujo: View {
    @Bindable var modelo: ModeloPuesta
    @Environment(\.accessibilityReduceMotion) private var reducir
    @State private var haciaAtras = false

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        VStack(spacing: TLSEspacio.e16) {
            CabeceraPuesta(modelo: modelo)
            BarraPasos(modelo: modelo)
            ScrollViewReader { lector in
                ScrollView {
                    VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                        if let e = modelo.error {
                            AvisoEnLinea(estado: .mal, texto: e)
                                .accessibilityIdentifier("puesta.error")
                        }
                        paso
                            .id(modelo.pantalla?.id ?? "fin")
                            .transition(TLSMovimiento.transicionNivel(reducir: reducir, haciaAtras: haciaAtras))
                    }
                    .padding(.horizontal, TLSEspacio.e8)
                    .padding(.vertical, TLSEspacio.e4)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .id("arriba")
                }
                .scrollContentBackground(.hidden)
                .onChange(of: modelo.pantalla?.id) { _, _ in lector.scrollTo("arriba", anchor: .top) }
                .onChange(of: modelo.aplicado) { _, ahora in if ahora != nil { lector.scrollTo("arriba", anchor: .top) } }
                .onChange(of: modelo.error) { _, ahora in if ahora != nil { lector.scrollTo("arriba", anchor: .top) } }
            }
            .animation(TLSMovimiento.entrarNivel(reducir: reducir), value: modelo.pantalla?.id)
            PiePuesta(modelo: modelo, haciaAtras: $haciaAtras)
        }
        .padding(TLSEspacio.e24)
        .background(TLSPaleta.fondo.color)
        .task(id: modelo.pantalla?.id) {
            if let p = modelo.pantalla { modelo.alPintar(p) }
        }
        .tlsPantalla("Puesta en marcha")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("puesta.flujo")
    }

    @ViewBuilder
    private var paso: some View {
        switch modelo.pantalla?.paso ?? .bienvenida {
        case .bienvenida: PasoBienvenida(modelo: modelo)
        case .alcance: PasoAlcance(modelo: modelo)
        case .conocer: PasoConocer(modelo: modelo)
        case .ordenar: PasoOrdenar(modelo: modelo)
        case .organizar: PasoOrganizar(modelo: modelo)
        case .sinTi: PasoSinTi(modelo: modelo)
        case .diaADia: PasoDiaADia(modelo: modelo)
        case .numeros: PasoNumeros(modelo: modelo)
        case .conectar: PasoConectar(modelo: modelo)
        case .recorrido: PasoRecorrido(modelo: modelo)
        }
    }
}

/// La cabecera azul noche: «Paso 4 de 9 · Organizar», el título de la pantalla, su explicación, «Quedan ~N min» y
/// «Seguir más tarde».
struct CabeceraPuesta: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        let p = modelo.pantalla
        let progreso = modelo.progreso
        CabeceraAzulNoche(
            rotulo: modelo.repasando ? "Repasar la puesta en marcha · paso \(progreso.numero) de \(progreso.total)"
                : "Puesta en marcha · paso \(progreso.numero) de \(progreso.total) · \(p?.paso.titulo ?? "")",
            titulo: p?.titulo ?? "Puesta en marcha",
            subtitulo: p?.explicacion,
            altoMinimo: 120
        ) {
            AvatarCabecera(simbolo: p?.paso.icono ?? "hand.wave")
        } acciones: {
            VStack(alignment: .trailing, spacing: TLSEspacio.e8) {
                Button {
                    Task { await modelo.seguirMasTardeYCerrar() }
                } label: {
                    Label("Seguir más tarde", systemImage: "pause.circle")
                }
                .tlsBoton(.sobreCabecera)
                .help("Se guarda todo: al volver, sigues en esta misma pregunta")
                .accessibilityIdentifier("puesta.seguirMasTarde")
                // Al repasar el ejemplo no queda nada por hacer: solo se mira.
                if !modelo.repasando {
                    Label(progreso.textoMinutos, systemImage: "clock")
                        .tlsTexto(TLSTipo.interfazMedia)
                        .foregroundStyle(TLSPaleta.subtituloCabecera.color)
                        .accessibilityLabel(progreso.textoMinutos.replacingOccurrences(of: "~", with: "unos "))
                        .accessibilityIdentifier("puesta.quedan")
                } else {
                    Label("Solo se mira", systemImage: "eye")
                        .tlsTexto(TLSTipo.interfazMedia)
                        .foregroundStyle(TLSPaleta.subtituloCabecera.color)
                        .accessibilityIdentifier("puesta.soloSeMira")
                }
            }
        }
    }
}

/// La barra de avance: un tramo por paso; hechos y el actual en azul noche, los que faltan en gris, con su nombre.
struct BarraPasos: View {
    @Bindable var modelo: ModeloPuesta

    var body: some View {
        let grupos = modelo.motor.pasosIncluidos.filter { $0 != .alcance }
        let actual = modelo.pantalla.map { $0.paso == .alcance ? PasoPuesta.bienvenida : $0.paso } ?? .bienvenida
        let i = grupos.firstIndex(of: actual) ?? 0
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(grupos.enumerated()), id: \.element) { n, g in
                VStack(alignment: .leading, spacing: 5) {
                    Capsule(style: .circular)
                        .fill(n <= i || modelo.pasoHecho(g) ? TLSPaleta.principal.color : TLSPaleta.separador.color)
                        .frame(height: n == i ? 6 : 4)
                    HStack(spacing: 3) {
                        if modelo.pasoHecho(g), n != i {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        }
                        Text(Self.corto(g)).lineLimit(1)
                    }
                    .tlsTexto(n == i ? TLSTipo.secundario.peso(600) : TLSTipo.secundario)
                    .foregroundStyle(n == i ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, TLSEspacio.e4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Avance: paso \(i + 1) de \(grupos.count), \(actual.titulo)")
        .accessibilityValue(grupos.filter { modelo.pasoHecho($0) }.map(\.titulo).joined(separator: ", "))
        .accessibilityIdentifier("puesta.avance")
    }

    static func corto(_ p: PasoPuesta) -> String {
        switch p {
        case .bienvenida, .alcance: "Bienvenida"
        case .conocer: "Conocer"
        case .ordenar: "Ordenar"
        case .organizar: "Organizar"
        case .sinTi: "Sin ti"
        case .diaADia: "Día a día"
        case .numeros: "Números"
        case .conectar: "Conectar"
        case .recorrido: "Recorrido"
        }
    }
}

/// El pie: «Atrás» (⌘[), «Saber más», «Saltar este paso» y el botón principal (↩), con el motivo si no se puede.
struct PiePuesta: View {
    @Bindable var modelo: ModeloPuesta
    @Binding var haciaAtras: Bool

    var body: some View {
        let accion = modelo.accionPrincipal
        let p = modelo.pantalla
        HStack(spacing: TLSEspacio.e12) {
            Button {
                haciaAtras = true
                Task { await modelo.atras() }
            } label: {
                Label("Atrás", systemImage: "chevron.left")
            }
            .tlsBoton(.secundario)
            .keyboardShortcut("[", modifiers: .command)
            .disabled(modelo.motor.indiceActual == 0 || modelo.ocupado)
            .help("Atrás (⌘[)")
            .accessibilityIdentifier("puesta.atras")
            if let p { BotonSaberMas(seccion: "paso-\(p.paso.rawValue)") }
            Spacer(minLength: TLSEspacio.e8)
            if let p, p.paso.escribeEnLaCarpeta, p.paso != .bienvenida, !modelo.pasoHecho(p.paso), !modelo.repasando {
                Button("Saltar este paso") { haciaAtras = false; Task { await modelo.saltarPaso() } }
                    .tlsBoton(.enlace)
                    .help("No se escribe nada; puedes volver a él cuando quieras")
                    .accessibilityIdentifier("puesta.saltar")
            }
            if let motivo = modelo.motivoSinPrincipal {
                Text(motivo)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 260, alignment: .trailing)
            }
            Button {
                haciaAtras = false
                Task { await modelo.pulsarPrincipal() }
            } label: {
                HStack(spacing: 6) {
                    if modelo.ocupado || modelo.trabajando { ProgressView().controlSize(.small) }
                    Text(accion.titulo)
                }
            }
            .tlsBoton(.principal)
            .keyboardShortcut(.defaultAction)
            .disabled(modelo.motivoSinPrincipal != nil || modelo.ocupado)
            .help("\(accion.titulo) (↩)")
            .accessibilityIdentifier("puesta.siguiente")
        }
        .accessibilityElement(children: .contain)
    }
}

/// Lo común de cada paso: la pantalla del paso, su vista previa (mientras esté por aplicar) y el resumen al aplicar.
struct MarcoPaso<Contenido: View>: View {
    @Bindable var modelo: ModeloPuesta
    let paso: PasoPuesta
    @ViewBuilder var contenido: (Pantalla) -> Contenido

    var body: some View {
        if let p = modelo.pantalla, p.paso == paso {
            VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                // Lo ya aplicado (con «Deshacer») va arriba: es lo primero que se ve al aplicar o al volver.
                ResumenPaso(modelo: modelo, paso: paso)
                contenido(p)
                if p.conVistaPrevia, !modelo.pasoHecho(paso), let v = modelo.vista, v.paso == paso, paso != .ordenar {
                    PanelVistaPrevia(modelo: modelo, vista: v,
                                     titulo: v.nadaQueEscribir ? "Lo que va a pasar" : "Lo que se escribirá en tu carpeta")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
