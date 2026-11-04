import Darwin
import Foundation

/// Prueba de riesgo de F1 (PLAN §5.3 y §9 F1): lanza `claude -p` dentro del perfil de sandbox, con el
/// entorno mínimo, el `cwd` estable del agente y solo los flags que da el preflight; traduce el stream,
/// aplica `InitGuard` y devuelve el estado final. Es el núcleo que `ClaudeCodeRuntime` ampliará en F4
/// (cola, reintentos, coste, token del socket).
public struct ClaudeProbe: Sendable {
    public var claude: URL
    public var help: ClaudeHelp
    public var home: URL

    public init(claude: URL, help: ClaudeHelp, home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.claude = claude; self.help = help; self.home = home
    }

    public struct Request: Sendable {
        public var paths: AgentPaths
        /// Carpetas de empresa que el asistente nunca puede leer.
        public var deniedRoots: [URL]
        public var socket: URL?
        /// Bundle de la app (para que el sandbox deje ejecutar `tls-mcp`).
        public var appBundle: URL?
        public var servers: [String: MCPServerConfig]
        public var session: ClaudeSession
        public var brief: URL?
        public var model: String?
        public var effort: String?
        public var maxBudgetUSD: Double
        public var jsonSchema: String?
        public var message: String
        public var initGuard: InitGuard
        /// Para tras `system/init` (medir la lista blanca sin gastar).
        public var stopAfterInit: Bool
        public var timeout: TimeInterval

        public init(paths: AgentPaths, deniedRoots: [URL], socket: URL? = nil, appBundle: URL? = nil,
                    servers: [String: MCPServerConfig], session: ClaudeSession, brief: URL? = nil,
                    model: String? = nil, effort: String? = nil, maxBudgetUSD: Double, jsonSchema: String? = nil,
                    message: String, initGuard: InitGuard = InitGuard(), stopAfterInit: Bool = false,
                    timeout: TimeInterval = 180) {
            self.paths = paths; self.deniedRoots = deniedRoots; self.socket = socket; self.appBundle = appBundle
            self.servers = servers; self.session = session; self.brief = brief; self.model = model
            self.effort = effort; self.maxBudgetUSD = maxBudgetUSD; self.jsonSchema = jsonSchema
            self.message = message; self.initGuard = initGuard; self.stopAfterInit = stopAfterInit
            self.timeout = timeout
        }
    }

    public struct Outcome: Sendable {
        public var paths: AgentPaths
        public var state: RunState
        public var events: [AgentEvent]
        public var initInfo: InitInfo?
        public var result: ResultInfo?
        public var verdict: InitGuard.Verdict?
        public var warnings: [String]
        public var process: ProcessOutput
        /// `true` si al terminar no queda ningún proceso del grupo (ni `tls-mcp`).
        public var groupGone: Bool
    }

    /// Perfil de sandbox de la petición.
    public func profileBuilder(_ r: Request) -> SandboxProfileBuilder {
        SandboxProfileBuilder(
            home: home, deniedRoots: r.deniedRoots, agentDirectory: r.paths.agentDirectory,
            runDirectory: r.paths.runDirectory, socket: r.socket,
            readOnly: (r.appBundle.map { [$0] } ?? []) + SandboxProfileBuilder.claudeReadPaths(binary: claude, home: home))
    }

    /// Escribe `agente.sb`, `mcp.json` y `settings.json` y devuelve la línea de órdenes.
    public func prepare(_ r: Request) throws -> ClaudeCommandLine {
        try r.paths.create()
        try profileBuilder(r).write(to: r.paths.profile)
        try RunFiles.write(try RunFiles.mcpConfig(r.servers), to: r.paths.mcpConfig)
        try RunFiles.write(try RunFiles.settings(), to: r.paths.settings)
        return try ClaudeCommandLine.build(ClaudeRunOptions(
            session: r.session, mcpConfig: r.paths.mcpConfig, settings: r.paths.settings, brief: r.brief,
            model: r.model, effort: r.effort, maxBudgetUSD: r.maxBudgetUSD, jsonSchema: r.jsonSchema), help: help)
    }

    public func run(_ r: Request) async throws -> Outcome {
        let cmd = try prepare(r)
        FileManager.default.createFile(atPath: r.paths.stream.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let collector = Collector(stream: try FileHandle(forWritingTo: r.paths.stream), guard: r.initGuard,
                                  stopAfterInit: r.stopAfterInit)
        defer { collector.close() }

        let spec = ProcessSpec(
            executable: SandboxProfileBuilder.sandboxExec,
            arguments: ["-f", r.paths.profile.path, claude.path] + cmd.arguments,
            environment: AgentEnvironment.minimal(home: home, tmp: r.paths.tmp),
            directory: r.paths.agentDirectory.path,
            stdin: try RunFiles.userMessage(r.message),
            timeout: r.timeout)
        let out = try await ProcessRunner.run(spec) { line in collector.handle(line) }

        // El lanzador ya paró lo que quedara del grupo antes de recoger el proceso; aquí solo se comprueba.
        let gone = !ProcessRunner.groupAlive(out.pid)

        let snap = collector.snapshot()
        let state: RunState
        if case .bloqueado = snap.verdict {
            state = .fallida(.guardia)
        } else if out.cancelled || (r.stopAfterInit && snap.initInfo != nil) {
            state = .cancelada
        } else if out.timedOut {
            state = .fallida(.tiempoAgotado)
        } else {
            state = RunState.from(result: snap.result)
        }
        return Outcome(paths: r.paths, state: state, events: snap.events, initInfo: snap.initInfo, result: snap.result,
                       verdict: snap.verdict, warnings: cmd.warnings, process: out, groupGone: gone)
    }

    /// Recoge eventos desde el hilo lector y guarda el crudo en `stream.jsonl`.
    final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private let stream: FileHandle
        private let initGuard: InitGuard
        private let stopAfterInit: Bool
        private var events: [AgentEvent] = []
        private var initInfo: InitInfo?
        private var result: ResultInfo?
        private var verdict: InitGuard.Verdict?

        init(stream: FileHandle, guard g: InitGuard, stopAfterInit: Bool) {
            self.stream = stream; self.initGuard = g; self.stopAfterInit = stopAfterInit
        }

        func handle(_ line: Data) -> LineDecision {
            lock.withLock {
                try? stream.write(contentsOf: line + Data([0x0A]))
                var decision = LineDecision.seguir
                for e in StreamJSONParser.events(fromLine: line) {
                    events.append(e)
                    switch e {
                    case .inicio(let info) where initInfo == nil:
                        initInfo = info
                        let v = initGuard.evaluate(info)
                        verdict = v
                        if !v.isAllowed || stopAfterInit { decision = .terminar }
                    case .resultado(let r):
                        result = r
                    default:
                        break
                    }
                }
                return decision
            }
        }

        func close() { lock.withLock { try? stream.close() } }

        func snapshot() -> (events: [AgentEvent], initInfo: InitInfo?, result: ResultInfo?, verdict: InitGuard.Verdict?) {
            lock.withLock { (events, initInfo, result, verdict) }
        }
    }
}
