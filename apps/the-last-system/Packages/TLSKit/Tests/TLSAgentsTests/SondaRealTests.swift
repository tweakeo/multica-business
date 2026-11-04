import Darwin
import Foundation
import Testing
@testable import TLSAgents

/// Prueba de riesgo con Claude Code de verdad (PLAN §9 F1, criterio 8). Usa la sesión de la suscripción,
/// así que solo corre con `TLS_SONDA_REAL=1` (lo pone `scripts/verificar-sandbox.sh`). Prompts mínimos,
/// sin herramientas, con `haiku` y tope de 0,05 USD por ejecución; las que solo miden `init` se paran antes
/// de que responda el modelo.
@Suite(.serialized, .enabled(if: Apoyo.real, "Prueba real: exporta TLS_SONDA_REAL=1"))
struct SondaRealTests {
    static let modelo = "haiku"
    static let tope = 0.05

    /// Claude Code localizado, su `--help` y el `tls-mcp` de F0.
    static func preparar() async throws -> (loc: ClaudeLocator, inst: ClaudeInstallation, probe: ClaudeProbe, mcp: URL) {
        let loc = ClaudeLocator()
        let inst = try await loc.locate()
        let help = try await loc.help(of: inst.binary)
        let mcp = try #require(Apoyo.tlsMCP, "Falta tls-mcp: compila la app (make build) o exporta TLS_SONDA_MCP")
        return (loc, inst, ClaudeProbe(claude: inst.binary, help: help), mcp)
    }

    /// Petición en el directorio estable del agente «sonda» (siempre el mismo `cwd`: `~/.claude.json` no crece).
    static func peticion(_ mcp: URL, vault: URL, sesion: ClaudeSession, servidores: [String]? = nil,
                         esquema: String? = nil, soloInicio: Bool = false, mensaje: String = "Responde solo con la palabra: listo")
        throws -> ClaudeProbe.Request {
        let paths = try AgentPaths(vaultState: Apoyo.estadoBase, slug: "sonda")
        var servers: [String: MCPServerConfig] = [:]
        for nombre in servidores ?? ["tls"] { servers[nombre] = MCPServerConfig(command: mcp.path) }
        let brief = paths.agentDirectory.appendingPathComponent("brief-sonda.md")
        try paths.create()
        try Data("Eres una sonda de prueba de The Last System. Responde con una sola palabra.\n".utf8).write(to: brief)
        return ClaudeProbe.Request(
            paths: paths, deniedRoots: [vault], socket: Apoyo.estadoBase.appendingPathComponent("s/sonda.sock"),
            appBundle: Apoyo.bundle(de: mcp), servers: servers, session: sesion, brief: brief, model: modelo,
            maxBudgetUSD: tope, jsonSchema: esquema, message: mensaje, stopAfterInit: soloInicio, timeout: 120)
    }

    @Test func localizaElBinarioReal() async throws {
        let (_, inst, _, _) = try await Self.preparar()
        #expect(inst.found.lastPathComponent == "claude")
        #expect(inst.isNative, "el binario real es Mach-O, no el alias ni un guion")
        let v = try #require(inst.version)
        #expect(v >= ClaudeVersion("2.1.306")!)
        if let aviso = ClaudeLocator.versionWarning(v) { print("AVISO: \(aviso)") }
        print("Claude Code \(v) en \(inst.binary.path) (encontrado como \(inst.found.path))")
    }

    @Test func preflightReal() async throws {
        let (loc, inst, _, _) = try await Self.preparar()
        let help = try await loc.help(of: inst.binary)
        #expect(!help.supports("--max-turns"))
        let cmd = try ClaudeCommandLine.build(ClaudeRunOptions(
            session: .ephemeral, mcpConfig: URL(fileURLWithPath: "/r/mcp.json"),
            settings: URL(fileURLWithPath: "/r/settings.json"), maxBudgetUSD: 0.01), help: help)
        #expect(cmd.warnings.isEmpty, "opciones que faltan: \(cmd.warnings)")
    }

    /// Dentro del perfil final, `auth status` sigue viendo la sesión iniciada.
    @Test func sesionIniciadaDentroDelPerfil() async throws {
        let (loc, inst, probe, mcp) = try await Self.preparar()
        let (vault, _) = Apoyo.vaultDePrueba()
        defer { Apoyo.limpiar(vault) }
        let r = try Self.peticion(mcp, vault: vault, sesion: .ephemeral)
        _ = try probe.prepare(r)
        let estado = try await loc.authStatus(binary: inst.binary, profile: r.paths.profile,
                                              environment: AgentEnvironment.minimal(home: Apoyo.home, tmp: r.paths.tmp),
                                              directory: r.paths.agentDirectory)
        #expect(estado.loggedIn)
        print("Sesión dentro del perfil: loggedIn=\(estado.loggedIn) método=\(estado.authMethod ?? "?")")
    }

    /// Mide la lista blanca con un `init` real y se para antes de que conteste el modelo.
    @Test func listaBlancaMedida() async throws {
        let (_, _, probe, mcp) = try await Self.preparar()
        let (vault, _) = Apoyo.vaultDePrueba()
        defer { Apoyo.limpiar(vault) }

        let sin = try await probe.run(try Self.peticion(mcp, vault: vault, sesion: .ephemeral, soloInicio: true))
        let infoSin = try #require(sin.initInfo, "sin init: \(sin.process.stderrText)")
        #expect(sin.state == .cancelada)
        #expect(infoSin.tools.isEmpty, "herramientas: \(infoSin.tools)")
        #expect(infoSin.mcpServers.map(\.name) == ["tls"])
        #expect(infoSin.mcpServers.first?.status == "connected")
        #expect(sin.verdict == .permitido)
        #expect(sin.groupGone, "no debe quedar ningún proceso (ni tls-mcp)")

        let esquema = #"{"type":"object","properties":{"ok":{"type":"boolean"}},"required":["ok"]}"#
        let con = try await probe.run(try Self.peticion(mcp, vault: vault, sesion: .ephemeral, esquema: esquema, soloInicio: true))
        let infoCon = try #require(con.initInfo)
        #expect(Set(infoCon.tools).isSubset(of: InitGuard.measuredWhitelist))
        #expect(infoCon.tools.contains("StructuredOutput"))
        #expect(con.verdict == .permitido)
        print("Lista blanca medida: sin esquema \(infoSin.tools), con esquema \(infoCon.tools); modo \(infoSin.permissionMode ?? "?"); complementos \(infoSin.plugins.map(\.source))")
    }

    /// Un segundo servidor en `mcp.json` → `InitGuard` lo para: `fallida(.guardia)`, sin resultado y sin procesos.
    @Test func segundoServidorLoPara() async throws {
        let (_, _, probe, mcp) = try await Self.preparar()
        let (vault, _) = Apoyo.vaultDePrueba()
        defer { Apoyo.limpiar(vault) }
        let out = try await probe.run(try Self.peticion(mcp, vault: vault, sesion: .ephemeral, servidores: ["tls", "otro"]))
        #expect(out.state == .fallida(.guardia))
        guard case .bloqueado(let motivos) = out.verdict else { Issue.record("la guardia no lo paró"); return }
        #expect(motivos.contains(.servidorAjeno("otro")))
        #expect(out.result == nil)
        #expect(out.process.stoppedByCaller)
        #expect(out.groupGone)
        let crudo = try String(contentsOf: out.paths.stream, encoding: .utf8)
        #expect(crudo.contains(#""subtype":"init""#))
        print("Guardia: \(motivos.map(\.description).joined(separator: "; "))")
    }

    /// `--session-id` y después `--resume` desde el mismo `cwd` estable → el mismo `session_id`.
    @Test func reanudarRecuperaLaSesion() async throws {
        let (_, _, probe, mcp) = try await Self.preparar()
        let (vault, _) = Apoyo.vaultDePrueba()
        defer { Apoyo.limpiar(vault) }
        let id = UUID()
        let uno = try await probe.run(try Self.peticion(mcp, vault: vault, sesion: .new(id)))
        #expect(uno.state == .completada, "\(uno.result?.text ?? "") \(uno.process.stderrText)")
        #expect(uno.initInfo?.sessionID == id.uuidString.lowercased())
        #expect(uno.initInfo?.cwd == SandboxProfileBuilder.realPath(
            try AgentPaths(vaultState: Apoyo.estadoBase, slug: "sonda").agentDirectory.path))

        let dos = try await probe.run(try Self.peticion(mcp, vault: vault, sesion: .resume(id)))
        #expect(dos.state == .completada, "\(dos.result?.text ?? "") \(dos.process.stderrText)")
        #expect(dos.initInfo?.sessionID == id.uuidString.lowercased())
        #expect(dos.result?.sessionID == id.uuidString.lowercased())
        let coste = (uno.result?.totalCostUSD ?? 0) + (dos.result?.totalCostUSD ?? 0)
        print("Reanudación: \(id.uuidString.lowercased()) → \(dos.initInfo?.sessionID ?? "?"); coste informado \(coste) USD")
    }

    /// Para `scripts/verificar-sandbox.sh`: deja el perfil final y las rutas en `ejecuciones/verificacion/`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TLS_SONDA_VAULT"] != nil))
    func perfilParaElGuion() async throws {
        let (_, inst, probe, mcp) = try await Self.preparar()
        let vault = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_SONDA_VAULT"]!, isDirectory: true)
        var r = try Self.peticion(mcp, vault: vault, sesion: .ephemeral)
        r.paths = try AgentPaths(vaultState: Apoyo.estadoBase, slug: "sonda", runID: "verificacion")
        _ = try probe.prepare(r)
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let env = [
            "PERFIL=\(q(r.paths.profile.path))", "CLAUDE=\(q(inst.binary.path))",
            "SOCKET=\(q(r.socket!.path))", "AGENTE=\(q(r.paths.agentDirectory.path))",
            "EJECUCION=\(q(r.paths.runDirectory.path))", "TMPDIR_AGENTE=\(q(r.paths.tmp.path))",
        ].joined(separator: "\n") + "\n"
        try Data(env.utf8).write(to: r.paths.runDirectory.appendingPathComponent("verificacion.env"))
    }
}
