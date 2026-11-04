import Darwin
import Foundation

/// Lanza Claude Code exactamente como dice el PLAN §5.3 («Lanzamiento»):
///
/// ```
/// /usr/bin/sandbox-exec -f <run>/agente.sb <claude> -p
///   --output-format stream-json --input-format stream-json --verbose
///   --session-id <uuid> | --resume <uuid>
///   --restricted --tools "" --disable-slash-commands
///   --mcp-config <run>/mcp.json --strict-mcp-config --allowedTools mcp__tls
///   --disallowedTools "Bash,Read,Edit,Write,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,AskUserQuestion"
///   --permission-mode dontAsk --permission-prompts none --settings <run>/settings.json
///   --append-system-prompt-file <agentes/slug/brief-<hash>.md>
///   --model <m> --effort <e> --max-budget-usd <min(ejecución, resto del mes)>
/// ```
///
/// Solo con los flags que confirma el preflight de `--help` (si falta uno imprescindible, no se lanza:
/// `fallida(.flagsAusentes)`). `cwd` = `<vault-id>/agentes/<slug>/` (estable); entorno mínimo sin
/// `ANTHROPIC_API_KEY`; grupo de procesos propio; `InitGuard` sobre el `init`. Cancelar la tarea que espera =
/// SIGTERM al grupo y SIGKILL a los `gracia` segundos (5).
public struct ClaudeCodeRuntime: AgentRuntime {
    public var claude: URL
    public var help: ClaudeHelp
    public var home: URL
    /// Bundle de la app (para que el sandbox deje ejecutar `tls-mcp`).
    public var appBundle: URL?
    public var initGuard: InitGuard
    /// SIGKILL a los N segundos de SIGTERM.
    public var gracia: TimeInterval
    /// Siempre `true` en la app. Solo las pruebas que no pueden usar `sandbox-exec` lo apagan.
    public var usarSandbox: Bool

    public let simulado = false

    public init(claude: URL, help: ClaudeHelp, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                appBundle: URL? = nil, initGuard: InitGuard = InitGuard(), gracia: TimeInterval = 5, usarSandbox: Bool = true) {
        self.claude = claude; self.help = help; self.home = home; self.appBundle = appBundle; self.initGuard = initGuard
        self.gracia = gracia; self.usarSandbox = usarSandbox
    }

    /// Perfil de sandbox de la ejecución.
    public func perfil(_ p: PeticionDeEjecucion) -> SandboxProfileBuilder {
        SandboxProfileBuilder(
            home: home, deniedRoots: p.carpetasNegadas, agentDirectory: p.paths.agentDirectory,
            runDirectory: p.paths.runDirectory, socket: p.credencial?.socket,
            readOnly: (appBundle.map { [$0] } ?? []) + SandboxProfileBuilder.claudeReadPaths(binary: claude, home: home))
    }

    /// Escribe `agente.sb`, `mcp.json` (solo `tls`), `settings.json` y `token`, y devuelve la orden completa.
    public func preparar(_ p: PeticionDeEjecucion) throws -> (ejecutable: String, argumentos: [String], avisos: [String]) {
        try p.paths.create()
        try perfil(p).write(to: p.paths.profile)
        let servidores = p.credencial.map { ["tls": $0.servidor] } ?? [:]
        try RunFiles.write(try RunFiles.mcpConfig(servidores), to: p.paths.mcpConfig)
        try RunFiles.write(try RunFiles.settings(), to: p.paths.settings)
        if let token = p.credencial?.token, !token.isEmpty {
            try RunFiles.write(Data(token.utf8), to: p.paths.runDirectory.appendingPathComponent("token"))
        }
        let cmd = try ClaudeCommandLine.build(ClaudeRunOptions(
            session: p.sesion, mcpConfig: p.paths.mcpConfig, settings: p.paths.settings, brief: p.brief,
            model: p.modelo, effort: p.esfuerzo, maxBudgetUSD: p.maxBudgetUSD), help: help)
        if usarSandbox {
            return (SandboxProfileBuilder.sandboxExec, ["-f", p.paths.profile.path, claude.path] + cmd.arguments, cmd.warnings)
        }
        return (claude.path, cmd.arguments, cmd.warnings)
    }

    public func ejecutar(_ p: PeticionDeEjecucion, alEvento: @escaping @Sendable (AgentEvent) -> Void,
                         alArrancar: @escaping @Sendable (Int32) -> Void) async -> ResultadoDeEjecucion {
        let orden: (ejecutable: String, argumentos: [String], avisos: [String])
        do { orden = try preparar(p) } catch let e as PreflightError {
            return ResultadoDeEjecucion(estado: .fallida(.flagsAusentes), avisos: [e.description])
        } catch {
            return ResultadoDeEjecucion(estado: .fallida(.error), avisos: ["\(error)"])
        }
        var reanudar: UUID?
        if case .resume(let id) = p.sesion { reanudar = id }
        let recolector = RecolectorDeStream(stream: p.paths.stream, guardia: initGuard, reanudar: reanudar, alEvento: alEvento)
        defer { recolector.cerrar() }
        let mensaje: Data
        do { mensaje = try RunFiles.userMessage(p.mensaje) } catch {
            return ResultadoDeEjecucion(estado: .fallida(.error), avisos: ["\(error)"])
        }
        let spec = ProcessSpec(
            executable: orden.ejecutable, arguments: orden.argumentos,
            environment: AgentEnvironment.minimal(home: home, tmp: p.paths.tmp),
            directory: p.paths.agentDirectory.path, stdin: mensaje, timeout: p.timeout, grace: gracia,
            alArrancar: { pid in alArrancar(pid) })
        let salida: ProcessOutput
        do {
            salida = try await ProcessRunner.run(spec) { recolector.linea($0) }
        } catch {
            return ResultadoDeEjecucion(estado: .fallida(.error), avisos: orden.avisos + ["\(error)"])
        }
        var estado = recolector.estadoFinal(cancelado: salida.cancelled, tiempoAgotado: salida.timedOut)
        var res = recolector.resultado(estado: estado, pid: salida.pid, simulado: false, avisos: orden.avisos)
        // `--resume` que no carga: el CLI sale sin `init` y lo dice por stderr.
        if reanudar != nil, res.initInfo == nil, !salida.cancelled {
            let texto = (salida.stderrText + salida.stdoutText).lowercased()
            if texto.contains("no conversation found") || texto.contains("session") && texto.contains("not found") {
                res.reanudacionRechazada = true
                estado = .fallida(.error)
                res.estado = estado
            }
        }
        // Sin `result` y con la sesión de Claude caducada (lo dice por stderr antes de empezar).
        if res.result == nil, case .fallida(.sinResultado) = estado {
            let err = salida.stderrText.lowercased()
            if err.contains("/login") || err.contains("not logged in") || err.contains("invalid api key") {
                res.estado = .fallida(.sinSesion)
            }
        }
        if !salida.stderrText.isEmpty, case .fallida = res.estado {
            res.avisos.append(String(salida.stderrText.suffix(600)))
        }
        return res
    }
}
