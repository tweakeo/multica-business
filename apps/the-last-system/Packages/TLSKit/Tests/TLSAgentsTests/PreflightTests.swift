import Foundation
import Testing
@testable import TLSAgents

/// Preflight de flags con el `--help` grabado de Claude Code 2.1.307.
@Suite struct PreflightTests {
    static let help = ClaudeHelp(text: String(decoding: Apoyo.grabacion("help-2.1.307.txt"), as: UTF8.self))

    static func opciones(_ sesion: ClaudeSession = .new(UUID(uuidString: "62AEBE90-174E-4BE0-91D9-AC42F0C6591F")!),
                         brief: URL? = nil, effort: String? = nil) -> ClaudeRunOptions {
        ClaudeRunOptions(session: sesion, mcpConfig: URL(fileURLWithPath: "/r/mcp.json"),
                         settings: URL(fileURLWithPath: "/r/settings.json"), brief: brief, model: "haiku",
                         effort: effort, maxBudgetUSD: 0.05)
    }

    @Test func flagsDeLa2_1_307() {
        let h = Self.help
        for f in ["-p", "--print", "--output-format", "--input-format", "--verbose", "--session-id", "--resume", "-r",
                  "--restricted", "--tools", "--disable-slash-commands", "--mcp-config", "--strict-mcp-config",
                  "--allowedTools", "--allowed-tools", "--disallowedTools", "--permission-mode", "--permission-prompts",
                  "--settings", "--append-system-prompt", "--model", "--effort", "--max-budget-usd", "--json-schema",
                  "--no-session-persistence", "--fork-session"] {
            #expect(h.supports(f), "debería existir \(f)")
        }
        // No existen en la 2.1.307: --max-turns (PLAN) ni --append-system-prompt-file.
        #expect(!h.supports("--max-turns"))
        #expect(!h.supports("--append-system-prompt-file"))
        #expect(h.commands.isSuperset(of: ["auth", "mcp", "plugin", "plugins", "doctor", "stop", "kill"]))
    }

    /// Una mención dentro de una descripción no declara la opción.
    @Test func mencionesNoCuentan() {
        let texto = """
        Usage: claude [options]

        Options:
          --verbose                 Override verbose mode (see --max-turns and
                                    --append-system-prompt-file for details)
          -c, --continue            Continue
          --allowedTools, --allowed-tools <tools...>
              Comma or space-separated list; --print only

        Commands:
          auth                      Manage authentication
          plugin|plugins            Manage plugins
        """
        let h = ClaudeHelp(text: texto)
        #expect(h.options == ["--verbose", "-c", "--continue", "--allowedTools", "--allowed-tools"])
        #expect(h.commands == ["auth", "plugin", "plugins"])
    }

    @Test func lineaDeOrdenesSegura() throws {
        let dir = Apoyo.tempDir("brief")
        defer { Apoyo.limpiar(dir) }
        let brief = dir.appendingPathComponent("brief-abc.md")
        Apoyo.escribir("Eres una sonda.\nNunca uses nada fuera de tls.", en: brief)
        let cmd = try ClaudeCommandLine.build(Self.opciones(brief: brief, effort: "low"), help: Self.help)
        let a = cmd.arguments
        #expect(a.first == "-p")
        #expect(cmd.warnings.isEmpty)
        func valor(_ f: String) -> String? { a.firstIndex(of: f).map { a[$0 + 1] } }
        #expect(valor("--output-format") == "stream-json")
        #expect(valor("--input-format") == "stream-json")
        #expect(valor("--session-id") == "62aebe90-174e-4be0-91d9-ac42f0c6591f")
        #expect(valor("--tools") == "")
        #expect(valor("--allowedTools") == "mcp__tls")
        #expect(valor("--disallowedTools") == ClaudeCommandLine.deniedBuiltins)
        #expect(valor("--permission-mode") == "dontAsk")
        #expect(valor("--permission-prompts") == "none")
        #expect(valor("--mcp-config") == "/r/mcp.json")
        #expect(valor("--settings") == "/r/settings.json")
        #expect(valor("--max-budget-usd") == "0.0500")
        #expect(valor("--effort") == "low")
        // Sin --append-system-prompt-file en esta versión: va el texto del brief.
        #expect(valor("--append-system-prompt") == "Eres una sonda.\nNunca uses nada fuera de tls.")
        for f in ["--restricted", "--strict-mcp-config", "--verbose", "--disable-slash-commands"] { #expect(a.contains(f)) }
        for f in ClaudeCommandLine.neverUsed { #expect(!a.contains(f)) }
        #expect(!a.contains { $0.contains("bypassPermissions") })
    }

    @Test func reanudarYEfimera() throws {
        let id = UUID()
        let r = try ClaudeCommandLine.build(Self.opciones(.resume(id)), help: Self.help).arguments
        #expect(r.contains("--resume") && !r.contains("--session-id"))
        #expect(r[r.firstIndex(of: "--resume")! + 1] == id.uuidString.lowercased())
        let e = try ClaudeCommandLine.build(Self.opciones(.ephemeral), help: Self.help).arguments
        #expect(e.contains("--no-session-persistence") && !e.contains("--resume") && !e.contains("--session-id"))
    }

    @Test func sinFlagsImprescindiblesNoSeLanza() {
        var h = Self.help
        h.options.remove("--restricted")
        h.options.remove("--permission-prompts")
        #expect(throws: PreflightError.flagsAusentes(["--restricted", "--permission-prompts"])) {
            try ClaudeCommandLine.build(Self.opciones(), help: h)
        }
    }

    @Test func prescindiblesSeOmitenConAviso() throws {
        var h = Self.help
        h.options.subtract(["--effort", "--disable-slash-commands"])
        let cmd = try ClaudeCommandLine.build(Self.opciones(effort: "low"), help: h)
        #expect(!cmd.arguments.contains("--effort") && !cmd.arguments.contains("--disable-slash-commands"))
        #expect(cmd.warnings == ["--disable-slash-commands", "--effort"])
    }
}
