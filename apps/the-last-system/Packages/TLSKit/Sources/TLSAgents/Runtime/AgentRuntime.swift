import Foundation
import TLSCore

// Lo que comparten `ClaudeCodeRuntime` (Claude Code de verdad, en su sandbox) y `SimulatedRuntime` (grabaciones):
// la petición de una ejecución, su resultado y el servidor de herramientas `tls` con el que hablan.

/// Para quién es un token del servidor de herramientas (`tls-mcp`): el servidor lo usa para autorizar cada llamada
/// (con el `Autorizador` de gobierno) y para escribir con `Autor.agente(slug)`.
public struct ContextoDeEjecucion: Sendable, Hashable, Codable {
    public var ejecucion: String
    public var agente: String
    /// Tarea que está trabajando (si la hay).
    public var tarea: VaultPath?
    public var disparo: TipoDeDisparo
    public var coordinador: Bool
    public var areas: [AreaCode]
    public var leeAreas: [AreaCode]
    public var maxTareasPorEjecucion: Int
    /// 0 = lo lanzó un disparador o la persona; 1 = delegado por el coordinador; 2 = delegado desde un delegado.
    public var profundidad: Int
    /// `chat:<mensaje>` (⌘J) o `pregunta:<id>` (respuesta a una pregunta): lo único que deja a
    /// `tls_registrar_decision` apuntar una decisión sin convertirla en propuesta.
    public var origen: String?
    public var simulado: Bool

    public init(ejecucion: String, agente: String, tarea: VaultPath? = nil, disparo: TipoDeDisparo, coordinador: Bool = false,
                areas: [AreaCode] = [], leeAreas: [AreaCode] = [], maxTareasPorEjecucion: Int = 10, profundidad: Int = 0,
                origen: String? = nil, simulado: Bool = false) {
        self.ejecucion = ejecucion; self.agente = agente; self.tarea = tarea; self.disparo = disparo
        self.coordinador = coordinador; self.areas = areas; self.leeAreas = leeAreas
        self.maxTareasPorEjecucion = maxTareasPorEjecucion; self.profundidad = profundidad; self.origen = origen
        self.simulado = simulado
    }
}

/// Lo que da el servidor para una ejecución: el token (32 bytes, válido solo mientras está en curso) y cómo lanzar
/// `tls-mcp` en el `mcp.json` de la ejecución (solo el servidor `tls`).
public struct CredencialDeEjecucion: Sendable, Hashable {
    public var ejecucion: String
    /// Token en hexadecimal. El motor lo escribe en `<run>/token` (0600) antes de lanzar.
    public var token: String
    /// Entrada `tls` del `mcp.json`.
    public var servidor: MCPServerConfig
    /// Socket de la carpeta (para la regla del sandbox).
    public var socket: URL?

    public init(ejecucion: String, token: String, servidor: MCPServerConfig, socket: URL?) {
        self.ejecucion = ejecucion; self.token = token; self.servidor = servidor; self.socket = socket
    }
}

/// Respuesta de una herramienta llamada directamente (simulación).
public struct ResultadoDeHerramienta: Sendable, Hashable {
    public var esError: Bool
    /// Normalmente JSON.
    public var texto: String
    public init(esError: Bool, texto: String) { self.esError = esError; self.texto = texto }
}

/// La puerta del motor al servidor de herramientas `tls` de una carpeta (lo implementa quien conecta `TLSMCPHost`:
/// `MCPHost` + `ServidorDeHerramientas`). El motor la arranca y la para con la carpeta, pide un token por ejecución
/// (con su `ContextoDeEjecucion`) y lo revoca al terminar o al cancelar (al momento).
public protocol PuertaDeHerramientas: Sendable {
    /// Arranca el socket (idempotente). Devuelve su ruta.
    func arrancar() async throws -> URL?
    /// Para el socket y revoca todos los tokens.
    func parar() async
    func abrir(_ contexto: ContextoDeEjecucion) async throws -> CredencialDeEjecucion
    func revocar(_ credencial: CredencialDeEjecucion) async
    /// Una llamada como si llegara por el socket con ese token (la usa `SimulatedRuntime`).
    func llamar(herramienta: String, argumentos: String, credencial: CredencialDeEjecucion) async -> ResultadoDeHerramienta
}

/// Una ejecución lista para lanzar.
public struct PeticionDeEjecucion: Sendable {
    public var contexto: ContextoDeEjecucion
    public var paths: AgentPaths
    public var sesion: ClaudeSession
    /// Brief del asistente (`agentes/<slug>/brief-<hash>.md`).
    public var brief: URL?
    public var modelo: String?
    public var esfuerzo: String?
    /// `min(tope de la ejecución, lo que queda del mes)`.
    public var maxBudgetUSD: Double
    /// Primer mensaje (lo variable: qué ha pasado, datos, contexto). Lo de fuera va marcado como dato.
    public var mensaje: String
    public var credencial: CredencialDeEjecucion?
    /// Carpetas que el asistente nunca lee (la de la empresa).
    public var carpetasNegadas: [URL]
    /// Grabaciones que valen para esta ejecución, de la más concreta a la más general (simulación).
    public var grabaciones: [String]
    /// Valores para las grabaciones: `{{tarea}}`, `{{hoy}}`, `{{agente}}`, `{{ejecucion}}`…
    public var variables: [String: String]
    public var timeout: TimeInterval

    public init(contexto: ContextoDeEjecucion, paths: AgentPaths, sesion: ClaudeSession, brief: URL? = nil,
                modelo: String? = nil, esfuerzo: String? = nil, maxBudgetUSD: Double, mensaje: String,
                credencial: CredencialDeEjecucion? = nil, carpetasNegadas: [URL] = [], grabaciones: [String] = [],
                variables: [String: String] = [:], timeout: TimeInterval = 1200) {
        self.contexto = contexto; self.paths = paths; self.sesion = sesion; self.brief = brief; self.modelo = modelo
        self.esfuerzo = esfuerzo; self.maxBudgetUSD = maxBudgetUSD; self.mensaje = mensaje; self.credencial = credencial
        self.carpetasNegadas = carpetasNegadas; self.grabaciones = grabaciones; self.variables = variables
        self.timeout = timeout
    }
}

/// Cómo acabó una ejecución.
public struct ResultadoDeEjecucion: Sendable {
    public var estado: RunState
    public var initInfo: InitInfo?
    public var result: ResultInfo?
    public var veredicto: InitGuard.Verdict?
    /// USD que informa el CLI (`total_cost_usd`); 0 si no llegó `result`.
    public var costeUSD: Double
    /// `true` si la sesión ya existe (llegó `init`): un reintento la reanuda en vez de crearla.
    public var sesionIniciada: Bool
    /// Se pidió `--resume` y no cargó (o el `session_id` es otro): hay que abrir una sesión nueva con el resumen.
    public var reanudacionRechazada: Bool
    /// Preguntas que dejó con `tls_preguntar` (ruta o id que devolvió la herramienta).
    public var preguntas: [String]
    /// Resumen de `tls_finalizar` (o el texto final si no lo llamó).
    public var resumen: String?
    public var finalizo: Bool
    /// Herramientas que usó (sin `mcp__tls__`), en orden y sin repetir.
    public var herramientas: [String]
    /// Límite de uso rechazado hasta esta hora (`rate_limit_event`).
    public var limiteHasta: Date?
    public var avisos: [String]
    public var pid: Int32?
    public var simulado: Bool
    /// F4 · corrector (R6): el modelo llegó a contestar (texto o una herramienta). Si además no llegó `result`, lo que
    /// gastó no se sabe: el motor le cuenta su tope entero.
    public var respondioElModelo: Bool

    public init(estado: RunState, initInfo: InitInfo? = nil, result: ResultInfo? = nil, veredicto: InitGuard.Verdict? = nil,
                costeUSD: Double = 0, sesionIniciada: Bool = false, reanudacionRechazada: Bool = false,
                preguntas: [String] = [], resumen: String? = nil, finalizo: Bool = false, herramientas: [String] = [],
                limiteHasta: Date? = nil, avisos: [String] = [], pid: Int32? = nil, simulado: Bool = false,
                respondioElModelo: Bool = false) {
        self.estado = estado; self.initInfo = initInfo; self.result = result; self.veredicto = veredicto
        self.costeUSD = costeUSD; self.sesionIniciada = sesionIniciada; self.reanudacionRechazada = reanudacionRechazada
        self.preguntas = preguntas; self.resumen = resumen; self.finalizo = finalizo; self.herramientas = herramientas
        self.limiteHasta = limiteHasta; self.avisos = avisos; self.pid = pid; self.simulado = simulado
        self.respondioElModelo = respondioElModelo
    }
}

/// Quien ejecuta: Claude Code o la simulación. Cancelar la tarea que espera = parar la ejecución (SIGTERM al grupo
/// y SIGKILL a los 5 s en Claude Code).
public protocol AgentRuntime: Sendable {
    /// `true` en la simulación: todo lo que produce lleva la marca «Simulado».
    var simulado: Bool { get }
    func ejecutar(_ peticion: PeticionDeEjecucion, alEvento: @escaping @Sendable (AgentEvent) -> Void,
                  alArrancar: @escaping @Sendable (Int32) -> Void) async -> ResultadoDeEjecucion
}

// MARK: - Recolector común

/// Lee el stream línea a línea (de Claude Code o de una grabación): guarda el crudo en `stream.jsonl`, traduce a
/// `AgentEvent`, aplica `InitGuard`, comprueba la reanudación y apunta preguntas, cierre, herramientas y límites.
final class RecolectorDeStream: @unchecked Sendable {
    private let lock = NSLock()
    private let stream: FileHandle?
    private let guardia: InitGuard
    private let esperada: String?
    private let alEvento: @Sendable (AgentEvent) -> Void
    private var initInfo: InitInfo?
    private var result: ResultInfo?
    private var veredicto: InitGuard.Verdict?
    private var rechazada = false
    private var preguntasPendientes: [String: Bool] = [:]
    private var preguntas: [String] = []
    private var resumen: String?
    private var finalizo = false
    private var ultimoTexto: String?
    private var herramientas: [String] = []
    private var limiteHasta: Date?
    private var respondio = false

    /// `reanudar`: la sesión que se pidió con `--resume` (para comprobar que el `init` trae la misma).
    init(stream: URL?, guardia: InitGuard, reanudar: UUID?, alEvento: @escaping @Sendable (AgentEvent) -> Void) {
        if let stream {
            FileManager.default.createFile(atPath: stream.path, contents: nil, attributes: [.posixPermissions: 0o600])
            self.stream = try? FileHandle(forWritingTo: stream)
            _ = try? self.stream?.seekToEnd()
        } else {
            self.stream = nil
        }
        self.guardia = guardia
        self.esperada = reanudar?.uuidString.lowercased()
        self.alEvento = alEvento
    }

    /// Una línea del stream. `.terminar` si hay que parar (guardia o reanudación rechazada).
    func linea(_ line: Data) -> LineDecision {
        let (eventos, decision) = lock.withLock { () -> ([AgentEvent], LineDecision) in
            try? stream?.write(contentsOf: line + Data([0x0A]))
            var decision = LineDecision.seguir
            let evs = StreamJSONParser.events(fromLine: line)
            for e in evs {
                switch e {
                case .inicio(let info) where initInfo == nil:
                    initInfo = info
                    let v = guardia.evaluate(info)
                    veredicto = v
                    if !v.isAllowed { decision = .terminar }
                    if let esperada, info.sessionID.lowercased() != esperada { rechazada = true; decision = .terminar }
                case .herramienta(let id, let nombre, let entrada):
                    respondio = true
                    let corto = nombre.replacingOccurrences(of: "mcp__tls__", with: "")
                    if !herramientas.contains(corto) { herramientas.append(corto) }
                    if corto == "tls_preguntar" { preguntasPendientes[id] = true }
                    if corto == "tls_finalizar" {
                        finalizo = true
                        resumen = Self.campo("resumen", en: entrada) ?? resumen
                    }
                case .resultadoHerramienta(let id, let esError, let texto):
                    if preguntasPendientes.removeValue(forKey: id) != nil, !esError {
                        preguntas.append(Self.referencia(texto) ?? id)
                    }
                case .texto(let t):
                    respondio = true
                    ultimoTexto = t
                case .limiteUso(let info) where info.status == "rejected":
                    limiteHasta = info.resetsAt ?? limiteHasta
                case .resultado(let r):
                    result = r
                default:
                    break
                }
            }
            return (evs, decision)
        }
        for e in eventos { alEvento(e) }
        return decision
    }

    func cerrar() { lock.withLock { try? stream?.close() } }

    var inicio: InitInfo? { lock.withLock { initInfo } }

    /// Resultado (sin el estado final, que decide cada runtime).
    func resultado(estado: RunState, pid: Int32?, simulado: Bool, avisos: [String]) -> ResultadoDeEjecucion {
        lock.withLock {
            ResultadoDeEjecucion(
                estado: estado, initInfo: initInfo, result: result, veredicto: veredicto,
                costeUSD: result?.totalCostUSD ?? 0, sesionIniciada: initInfo != nil && !rechazada,
                reanudacionRechazada: rechazada, preguntas: preguntas,
                resumen: resumen ?? result?.text ?? ultimoTexto, finalizo: finalizo, herramientas: herramientas,
                limiteHasta: limiteHasta, avisos: avisos, pid: pid, simulado: simulado, respondioElModelo: respondio)
        }
    }

    /// Estado final con las reglas comunes: guardia → reanudación rechazada → cancelada → tiempo → `result`.
    func estadoFinal(cancelado: Bool, tiempoAgotado: Bool) -> RunState {
        lock.withLock {
            if case .bloqueado? = veredicto { return .fallida(.guardia) }
            if rechazada { return .fallida(.error) }
            if cancelado { return .cancelada }
            if tiempoAgotado { return .fallida(.tiempoAgotado) }
            // Límite de uso rechazado sin `result`: es límite de uso, no «sin resultado».
            if result == nil, limiteHasta != nil { return .fallida(.limiteUso) }
            return RunState.from(result: result)
        }
    }

    /// `"ruta"`, `"pregunta"` o `"id"` del JSON que devuelve `tls_preguntar`.
    static func referencia(_ texto: String) -> String? {
        for clave in ["ruta", "pregunta", "id"] {
            if let v = campo(clave, en: texto), !v.isEmpty { return v }
        }
        return nil
    }

    static func campo(_ clave: String, en json: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        if let s = obj[clave] as? String { return s }
        if let n = obj[clave] as? NSNumber { return n.stringValue }
        return nil
    }
}
