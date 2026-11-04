import Foundation
import OSLog
import TLSAgents
import TLSCore
import TLSMCPHost
import TLSMCPShared
import TLSUI

// F4 · integración (PLAN §5.3–§5.4, «Cambios pedidos» de docs/F4-CONTRATOS.md). Los asistentes de **una** empresa
// abierta con escritor: su motor (`AgentHost`: cola, planificador de rutinas y disparos), su servidor de herramientas
// (`ServidorDeHerramientas` detrás de `PuertaMCP`: el socket de `tls-mcp`) y el chat de Mika. Todo con las piezas de la
// sesión: el mismo índice, el mismo `CommandBus` y **el mismo** `Autorizador`, con sus `Aprobaciones` y su
// `EscrituraDeAsistente`.
//
// - Ribera (el ejemplo): `SimulatedRuntime` con las grabaciones y el reloj del ejemplo (19 de octubre). Nada sale.
// - Una copia: Claude Code si está (con sesión y con los flags del lanzamiento); si no, no hay motor y Asistentes
//   explica cómo conectarlo («Buscar otra vez» lo vuelve a intentar).
// - Parar (al cerrar la empresa, al pasarla a solo lectura o al salir): cancela lo que esté en marcha (SIGTERM al
//   grupo, SIGKILL a los 5 s, token revocado antes), cierra los chats, revoca todos los tokens y borra el socket: no
//   queda ningún `tls-mcp` vivo.

@MainActor
public final class MotorDeEmpresa {
    public struct Opciones: Sendable {
        public var localizador: any LocalizadorDeClaude
        /// `tls-mcp` (en el bundle de la app). `nil`: lo busca `ConfiguracionMCP.localizarHelper()`.
        public var helper: URL?
        /// `nil`: el de la app (`PeerValidator.deLaApp()`). En pruebas, `.sinComprobarFirma`.
        public var validador: PeerValidator?
        /// Dónde va el socket (`<appSupport>/s/<vault8>.sock`).
        public var appSupport: URL
        public var appBundle: URL?
        public var catalogo: CatalogoAsistentesTLS
        /// Grabaciones de la demo (`GrabacionesDeEjemplo.carpeta`).
        public var grabaciones: URL?
        /// Pausa entre líneas de una grabación (la demo enseña «Leyendo…» un momento).
        public var pausaSimulacion: TimeInterval
        /// Cada cuánto vuelve a mirar el motor aunque no pase nada.
        public var intervalo: TimeInterval
        /// `home` de Claude (sandbox y entorno mínimo).
        public var home: URL
        /// Solo pruebas que no pueden usar `sandbox-exec`.
        public var usarSandbox: Bool
        /// SIGKILL a los N segundos de SIGTERM.
        public var gracia: TimeInterval
        /// Reloj fijo (pruebas). `nil`: el del ejemplo en la demo y el del Mac en una copia.
        public var reloj: (any RelojDelMotor)?
        /// **Solo pruebas:** el runtime que se usa, con la puerta de la empresa (un `claude` falso o una simulación
        /// propia). `nil`: simulación en el ejemplo y Claude Code en una copia.
        public var fabricaDeRuntime: (@Sendable (PuertaMCP) -> any AgentRuntime)?
        /// F5 · integración: Mail, Calendario, permisos y Llavero de cada empresa (`SistemaDeConexiones.delMac` en la
        /// app; dobles en pruebas). `nil`: sin conexiones (Conexiones enseña «Ahora no»).
        public var conexiones: SistemaDeConexiones?

        public init(localizador: any LocalizadorDeClaude = LocalizadorClaudeCode(), helper: URL? = nil,
                    validador: PeerValidator? = nil, appSupport: URL = AppLocations.appSupport,
                    appBundle: URL? = Bundle.main.bundleURL, catalogo: CatalogoAsistentesTLS = .deLaApp(),
                    grabaciones: URL? = GrabacionesDeEjemplo.carpeta, pausaSimulacion: TimeInterval = 0.4,
                    intervalo: TimeInterval = 60, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                    usarSandbox: Bool = true, gracia: TimeInterval = 5, reloj: (any RelojDelMotor)? = nil,
                    fabricaDeRuntime: (@Sendable (PuertaMCP) -> any AgentRuntime)? = nil,
                    conexiones: SistemaDeConexiones? = nil) {
            self.localizador = localizador; self.helper = helper; self.validador = validador; self.appSupport = appSupport
            self.appBundle = appBundle; self.catalogo = catalogo; self.grabaciones = grabaciones
            self.pausaSimulacion = pausaSimulacion; self.intervalo = intervalo; self.home = home
            self.usarSandbox = usarSandbox; self.gracia = gracia; self.reloj = reloj
            self.fabricaDeRuntime = fabricaDeRuntime
            self.conexiones = conexiones
        }
    }

    public let piezas: PiezasDeLaEmpresa
    public let opciones: Opciones
    public let enVivo = EstadoEnVivo()
    public private(set) weak var sesion: VaultSession?
    /// El motor de la carpeta (`nil` sin Claude en una copia, o antes de arrancar).
    public private(set) var host: AgentHost?
    public private(set) var puerta: PuertaMCP?
    public private(set) var servidor: ServidorDeHerramientas?
    /// Lo último que se supo de Claude Code (en el ejemplo, `nil`: no hace falta).
    public private(set) var claude: ClaudeDisponible?
    public let auditoria = AuditoriaDeLaApp()
    public private(set) var arrancado = false
    /// Ya está todo montado y conectado a las pantallas (o se sabe por qué no hay motor).
    public private(set) var listo = false
    /// Lo que ven las pantallas (una nueva cada vez que cambia el motor: así se enteran solas).
    public private(set) var conexion: ConexionAsistentes
    let servicios: ServiciosDelMotor
    /// F5 · integración: las conexiones de la empresa (Mail, Calendario y otros programas), si las hay.
    public let conexiones: ConexionesDeEmpresa?
    private var vista: AgentView?
    private var chats: [WeakChat] = []
    private static let log = Logger(subsystem: "es.thelast.system", category: "Asistentes")

    private final class WeakChat { weak var valor: SesionDeChat?; init(_ v: SesionDeChat) { valor = v } }

    public init(sesion: VaultSession, piezas: PiezasDeLaEmpresa, opciones: Opciones = Opciones(),
                conexiones: ConexionesDeEmpresa? = nil) {
        self.sesion = sesion
        self.piezas = piezas
        self.opciones = opciones
        self.conexiones = conexiones
        let gobierno = piezas.autorizador
        let hoyCarpeta = piezas.hoyCarpeta
        servicios = ServiciosDelMotor(
            estado: gobierno.estado,
            tope: { gobierno.estadoDeConfig().efectiva.avisos.topeNotificacionesNoRojasDia },
            hoy: { hoyCarpeta ?? .today() },
            alAvisar: { [weak sesion] a in
                Task { @MainActor in
                    sesion?.avisoDeLosAsistentes("\(AsistenteConfigurado.nombre(de: a.asistente)): \(a.texto)",
                                                 estado: a.nivel == .rojo ? .mal : .atencion, alMac: a.nivel == .rojo,
                                                 id: "aviso:\(a.ejecucion)")
                }
            })
        conexion = ConexionAsistentes(host: nil, enVivo: enVivo)
    }

    /// El ejemplo va simulado; una copia, con Claude Code.
    public var simulado: Bool { piezas.esEjemplo }

    // MARK: Arrancar y parar

    /// Monta y arranca todo. En una copia sin Claude, deja la conexión con el motivo (y «Buscar otra vez»).
    public func arrancar() async {
        guard !arrancado, let sesion else { return }
        arrancado = true
        _ = try? await piezas.aprobaciones.caducar()
        if simulado || opciones.fabricaDeRuntime != nil {
            claude = nil
        } else {
            let c = await opciones.localizador.buscar()
            claude = c
        }
        guard arrancado else { return }
        var motivo: String?
        if simulado || opciones.fabricaDeRuntime != nil || claude?.listo == true {
            do {
                try await montar()
            } catch {
                Self.log.error("No se pudo montar el motor de los asistentes: \(String(describing: error), privacy: .public)")
                await desmontar()
                motivo = "No he podido poner en marcha los asistentes de esta empresa. Pulsa «Buscar otra vez»."
            }
        } else {
            motivo = claude?.explicacion
        }
        conectar(sesion, sinMotor: motivo)
        listo = true
    }

    /// Las pantallas (asistentes, ⌘J, Decisiones) ven este motor: una conexión nueva cada vez.
    private func conectar(_ sesion: VaultSession, sinMotor: String?) {
        conexion = ConexionAsistentes(host: host, enVivo: enVivo,
                                      alCambiarAjustes: { [weak self] apagado in await self?.ajustesCambiaron(apagado: apagado) },
                                      sinMotor: sinMotor, reintentar: { [weak self] in await self?.reintentar() })
        RegistroDeAsistentes.compartido.conectar(conexion, a: sesion)
        conectarChat()
    }

    /// Para todo lo de esta empresa (cola, chats, servidor) y la desconecta de las pantallas.
    public func parar() async {
        guard arrancado else { return }
        arrancado = false
        listo = false
        await desmontar()
        if let sesion {
            RegistroDeAsistentes.compartido.desconectar(sesion)
            sesion.conectarChatDeMika(nil)
        }
    }

    /// «Buscar otra vez»: si ahora hay Claude Code, monta el motor.
    public func reintentar() async {
        guard arrancado, host == nil, !simulado, let sesion else { return }
        let c = await opciones.localizador.buscar()
        claude = c
        guard c.listo else {
            conectar(sesion, sinMotor: c.explicacion)
            sesion.avisoDeLosAsistentes(c.explicacion ?? "Aún no.", estado: .atencion)
            return
        }
        do {
            try await montar()
            conectar(sesion, sinMotor: nil)
            sesion.avisoDeLosAsistentes("Claude Code está listo: los asistentes ya pueden trabajar.", estado: .bien)
        } catch {
            await desmontar()
            conectar(sesion, sinMotor: "No he podido poner en marcha los asistentes de esta empresa. Pulsa «Buscar otra vez».")
        }
    }

    /// La carpeta cambió (de fuera o por la app).
    public func carpetaCambio() async {
        await host?.carpetaCambio()
    }

    /// El Mac despertó: se recalculan las rutinas.
    public func despertoElMac() async {
        await host?.despertoElMac()
    }

    /// Tras el interruptor o la ficha de un asistente. Al apagar, además de no lanzar nada, se revocan todos los
    /// permisos de `tls-mcp` al momento (lo que esté en marcha pierde sus herramientas antes de pararse).
    func ajustesCambiaron(apagado: Bool) async {
        // `ConexionAsistentes` ya avisó al motor (`host.ajustesCambiaron()`): aquí, lo de `tls-mcp` y el chat.
        guard apagado else { return }
        puerta?.host.tokens.revocarTodos()
        await cerrarChats()
    }

    // MARK: Montar

    private func montar() async throws {
        let p = piezas
        let ajustesFuente = AjustesDeGobierno(autorizador: p.autorizador)
        let zona = await ajustesFuente.ajustes().zona
        let reloj: any RelojDelMotor = opciones.reloj
            ?? (simulado ? RelojDeDemo(hoy: p.hoyCarpeta ?? .today(), zona: zona) : RelojDelSistema())

        // Servidor de herramientas (traduce cada herramienta a lecturas por `AgentView` y a planes por el gobierno).
        var deps = ServidorDeHerramientas.Dependencias.de(
            service: p.service, bus: p.bus, motor: p.motorDominio, autorizador: AutorizadorDelGobierno(p.autorizador),
            dominio: DominioDelGobierno(p.escritura), servicios: servicios,
            aprobaciones: AprobacionesDelGobierno(p.aprobaciones),
            propuestas: PropuestasDelGobierno(AlmacenPropuestas(estado: p.autorizador.estado)),
            auditoria: auditoria, persona: p.persona)
        vista = deps.vista
        if simulado, let hoy = p.hoyCarpeta {
            // El ejemplo vive el día que fija su carpeta (también para las herramientas).
            deps.reloj = { _ in Reloj(hoy: hoy, ahora: reloj.ahora(), zona: zona) }
        }
        // F5 · integración: `tls_correo_pendiente`, `tls_agenda` con lo ocupado del Calendario y `ext_*`.
        conexiones?.completar(&deps)
        let servidor = ServidorDeHerramientas(deps)
        self.servidor = servidor

        let socket = try MCPHost.rutaDelSocket(vaultID: p.entry.id.uuidString, appSupport: opciones.appSupport)
        let mcp = MCPHost(socket: socket, validador: opciones.validador ?? .deLaApp(bundle: opciones.appBundle ?? Bundle.main.bundleURL),
                          manejador: servidor, auditoria: auditoria)
        let autorizador = p.autorizador
        let puerta = PuertaMCP(host: mcp, servidor: servidor, helper: opciones.helper ?? ConfiguracionMCP.localizarHelper(),
                               buzon: { slug in
                                   autorizador.config.efectiva().asistente(slug)?.buzon ?? ["cartero", "ordenador"].contains(slug)
                               })
        self.puerta = puerta

        let runtime: any AgentRuntime
        if let fabrica = opciones.fabricaDeRuntime {
            runtime = fabrica(puerta)
        } else if simulado {
            guard let g = opciones.grabaciones else { throw FalloDeMotor.sinGrabaciones }
            runtime = SimulatedRuntime(grabaciones: g, servidor: puerta, pausa: opciones.pausaSimulacion)
        } else {
            guard case .listo(let binario, let ayuda, _) = claude else { throw FalloDeMotor.sinClaude }
            runtime = ClaudeCodeRuntime(claude: binario, help: ayuda, home: opciones.home, appBundle: opciones.appBundle,
                                        gracia: opciones.gracia, usarSandbox: opciones.usarSandbox)
        }

        let sesion = self.sesion
        let empresa = p.entry.nombre
        var antesDeLanzar: (@Sendable (Ejecucion) async -> Void)?
        if let c = conexiones {
            antesDeLanzar = { e in await c.antesDeLanzar(e) }
        }
        let host = try AgentHost(.init(
            raiz: p.root, estadoDeCarpeta: p.estadoDeCarpeta, runtime: runtime, puerta: puerta,
            registro: ActivityWriter(bus: p.bus, foto: p.foto, zona: zona), ajustes: ajustesFuente,
            catalogo: opciones.catalogo, reloj: reloj, foto: p.foto, enVivo: enVivo,
            alAvisar: { aviso in
                Task { @MainActor in
                    let grave: Bool = { if case .guardia = aviso { return true }; if case .sinSesion = aviso { return true }; return false }()
                    sesion?.avisoDeLosAsistentes(aviso.texto, estado: grave ? .mal : .atencion, alMac: grave)
                }
            },
            empresa: empresa, intervalo: opciones.intervalo,
            permisoDeLanzamiento: { autorizador.permisoDeLanzamiento($0) },
            antesDeLanzar: antesDeLanzar))
        servicios.host = host
        self.host = host
        try await host.arrancar()
    }

    private func desmontar() async {
        await cerrarChats()
        if let host { await host.parar() }
        // Por si el host no llegó a arrancar la puerta (o falló al montar): el socket, fuera.
        await puerta?.parar()
        servicios.host = nil
        vista?.cerrar()
        vista = nil
        host = nil
        puerta = nil
        servidor = nil
    }

    // MARK: Chat de Mika (⌘J)

    /// Cómo se habla con Mika en esta empresa: con Claude Code (un proceso vivo), simulado en el ejemplo o, sin motor,
    /// el enrutador de la app (sin conectar nada).
    private func conectarChat() {
        guard let sesion else { return }
        guard let host, let puerta else {
            sesion.conectarChatDeMika(nil)
            return
        }
        let p = piezas
        let opciones = self.opciones
        let claude: ClaudeCodeRuntime? = {
            guard case .listo(let binario, let ayuda, _) = self.claude else { return nil }
            return ClaudeCodeRuntime(claude: binario, help: ayuda, home: opciones.home, appBundle: opciones.appBundle,
                                     gracia: opciones.gracia, usarSandbox: opciones.usarSandbox)
        }()
        let simulacion: SimulatedRuntime? = simulado ? opciones.grabaciones.map {
            SimulatedRuntime(grabaciones: $0, servidor: puerta, pausa: 0)
        } : nil
        let reloj = host.configuracion.reloj
        sesion.conectarChatDeMika { [weak self] in
            let chat = SesionDeChat(.init(
                agente: "mika", estadoDeCarpeta: p.estadoDeCarpeta, raiz: p.root, claude: claude, puerta: puerta,
                ajustes: AjustesDeGobierno(autorizador: p.autorizador), catalogo: opciones.catalogo, reloj: reloj,
                foto: p.foto, estado: host.estado, empresa: p.entry.nombre, simulacion: simulacion))
            self?.chats.append(WeakChat(chat))
            return chat
        }
    }

    private func cerrarChats() async {
        let vivos = chats.compactMap(\.valor)
        chats = []
        for c in vivos { await c.cerrar() }
    }
}

enum FalloDeMotor: Error {
    case sinGrabaciones
    case sinClaude
}
