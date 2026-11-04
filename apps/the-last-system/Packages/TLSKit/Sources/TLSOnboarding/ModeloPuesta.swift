import Foundation
import Observation
import TLSCore

// F3 · andamio del rol motor. El modelo de la ventana de la puesta en marcha: envuelve `OnboardingEngine` (TLSCore),
// que guarda `onboarding.json` tras cada respuesta. Las vistas de los pasos (fase de pantallas) leen y escriben por
// aquí; nunca escriben en la carpeta salvo con `aplicar(...)`, que es el «Aplicar» de la persona.

@MainActor
@Observable
public final class ModeloPuesta {
    public private(set) var motor: OnboardingEngine
    /// La vista previa del paso actual (se prepara al llegar a la pantalla con «Aplicar»).
    public private(set) var vista: VistaPreviaPaso?
    /// La repregunta del entrevistador para una pregunta (una vez).
    public private(set) var repreguntas: [PreguntaID: String] = [:]
    /// Lo último que salió mal, en español llano.
    public var error: String?
    public private(set) var trabajando = false
    /// Faltan respuestas en la pantalla actual (tras pulsar «Siguiente»).
    public private(set) var faltan: [PreguntaID] = []

    public init(motor: OnboardingEngine) {
        var m = motor
        // F4: el paso 4 (o el 3) deja listos los asistentes de serie en el mismo plan.
        if m.asistentes == nil { m.asistentes = AsistentesDeLaPuesta() }
        self.motor = m
    }

    // MARK: Ampliado por el rol pasos (fase de pantallas)

    /// Cómo se abrió la ventana (empezar, retomar o repasar). `nil`: desde el motor directamente (pruebas).
    public var peticion: PeticionPuestaEnMarcha?
    /// Dónde viven el registro de carpetas, el estado de la app y las copias (en pruebas, temporales).
    public var registro = VaultRegistry()
    public var appSupport = AppLocations.appSupport
    public var empresas = AppLocations.empresas
    /// Lo que la app le pasa a la puesta en marcha (sesiones abiertas, el ejemplo, los paneles, Claude Code…).
    @ObservationIgnored public var entorno: EntornoPuesta = .compartido
    /// Lo que puede hacer la ventana (abrir la empresa, el selector, cerrarse).
    @ObservationIgnored public var ventana = AccionesVentana()
    /// Texto escrito en un campo que aún no se ha guardado (se guarda al salir del campo o al pulsar el botón).
    public var borradores: [PreguntaID: String] = [:]
    /// La copia de la bienvenida mientras se hace y al acabar.
    public internal(set) var copia: EstadoCopia?
    /// Claude Code en este Mac (alcance y paso 7).
    public internal(set) var claude: EstadoClaude = .sinMirar
    /// Lo que se acaba de aplicar en esta pantalla (el resumen, con «Deshacer»).
    public internal(set) var aplicado: ResumenAplicado?
    /// Pantallas que se han pintado, en orden (las pruebas cuentan pantallas recorriendo las vistas).
    public internal(set) var pintadas: [String] = []
    /// La carpeta que se abre al terminar si no es la de la puesta en marcha («Ver sin tocar»).
    public internal(set) var empresaAlTerminar: UUID?
    /// Ya se pulsó el último botón.
    public internal(set) var terminada = false
    /// Se cambió la carpeta de origen: hay que volver a decir si tiene carpetas privadas.
    public internal(set) var privadasPorConfirmar = false
    /// Copiar también `Archivo/` (lo retirado; más lento), como en «Crear copia de mi carpeta».
    public var incluirArchivo = false
    /// Un botón está trabajando (no se vuelve a pulsar hasta que acabe).
    public internal(set) var ocupado = false
    @ObservationIgnored var tareaVista: Task<Void, Never>?
    @ObservationIgnored var tareaCopia: Task<Void, Never>?

    /// Abre (o retoma) la puesta en marcha que pide la interfaz.
    public convenience init(peticion: PeticionPuestaEnMarcha, registro: VaultRegistry = VaultRegistry(),
                            appSupport: URL = AppLocations.appSupport, persona: String = "Manu") {
        let id = peticion.vaultID ?? UUID()
        let entrada = registro.load().first { $0.id == id }
        let contexto: ContextoCarpeta
        if let entrada, let url = registro.resolveURL(entrada) {
            contexto = ContextoCarpeta.leer(url, entrada: entrada)
        } else {
            contexto = .vacio()
        }
        let motor = OnboardingEngine.abrir(vaultID: id, contexto: contexto, almacen: AlmacenPuesta(vaultID: id, appSupport: appSupport),
                                           persona: persona)
        self.init(motor: motor)
        self.peticion = peticion
        self.registro = registro
        self.appSupport = appSupport
    }

    // MARK: Lo que se ve

    public var pantalla: Pantalla? { motor.pantallaActual }
    public var preguntas: [Pregunta] { motor.preguntasActuales }
    public var progreso: ProgresoPuestaEnMarcha { motor.progreso }
    public var ruta: RutaPuesta { motor.ruta }
    public var pantallas: [Pantalla] { motor.pantallas }

    // MARK: Contestar

    public func responder(_ id: PreguntaID, _ valor: ValorRespuesta) async {
        var m = motor
        let r = await m.responder(id, valor)
        motor = m
        if case .repreguntar(let t) = r { repreguntas[id] = t } else { repreguntas[id] = nil }
        faltan.removeAll { $0 == id }
    }

    public func noLoSe(_ id: PreguntaID) {
        motor.noLoSe(id)
        repreguntas[id] = nil
        faltan.removeAll { $0 == id }
    }

    /// Tras contestar varias de golpe («Lo contesto luego»): ya no faltan.
    func faltanDespuesDeContestar(_ ids: [PreguntaID]) {
        for id in ids { repreguntas[id] = nil }
        faltan.removeAll { ids.contains($0) }
    }

    /// «Siguiente».
    @discardableResult
    public func siguiente() -> ResultadoAvance {
        let r = motor.siguiente()
        if case .faltan(let f) = r { faltan = f } else { faltan = [] }
        vista = nil
        return r
    }

    public func anterior() {
        motor.anterior()
        vista = nil
    }

    /// «Seguir más tarde»: queda guardado; al volver se retoma en la misma pregunta.
    public func seguirMasTarde() { motor.seguirMasTarde() }

    // MARK: Vista previa y aplicar

    /// Prepara la vista previa del paso de la pantalla actual (solo lee la carpeta).
    public func prepararVistaPrevia() {
        guard let p = pantalla else { return }
        do {
            vista = try motor.vistaPrevia(p.paso)
            error = nil
        } catch {
            vista = nil
            self.error = error.localizedDescription
        }
    }

    /// «Aplicar» en una carpeta abierta con escritor (`sesion.escritor` → `CommandBus`).
    public func aplicar(bus: CommandBus) async {
        guard let v = vista else { return }
        trabajando = true
        defer { trabajando = false }
        do {
            var m = motor
            try await m.aplicar(v, bus: bus)
            motor = m
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// «Aplicar» del paso 0 en «Empiezo de cero»: crea la carpeta, la registra y escribe.
    public func aplicarEmpezarDeCero(empresas: URL = AppLocations.empresas, registro: VaultRegistry = VaultRegistry(),
                                     appSupport: URL = AppLocations.appSupport) async -> VaultEntry? {
        guard let v = vista else { return nil }
        trabajando = true
        defer { trabajando = false }
        do {
            var m = motor
            let e = try await m.aplicarEmpezarDeCero(v, empresas: empresas, registro: registro, appSupport: appSupport)
            motor = m
            error = nil
            return e
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// «Deshacer» del paso (si es lo último que se escribió).
    public func deshacer(_ paso: PasoPuesta, bus: CommandBus) async {
        do {
            var m = motor
            try await m.deshacer(paso, bus: bus)
            motor = m
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Para el importador (paso 2) y la bienvenida con carpeta: cambiar el motor (registrar la copia, lo ordenado…).
    public func actualizar(_ cambio: (inout OnboardingEngine) -> Void) {
        var m = motor
        cambio(&m)
        motor = m
    }
}
