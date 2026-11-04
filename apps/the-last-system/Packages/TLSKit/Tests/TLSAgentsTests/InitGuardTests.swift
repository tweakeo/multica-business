import Foundation
import Testing
@testable import TLSAgents

@Suite struct InitGuardTests {
    static let deSerie = [PluginInfo(name: "cc-plugin-agents-md", source: "cc-plugin-agents-md@builtin")]
    static let tls = MCPServerStatus(name: "tls", status: "connected")

    @Test func loMedidoPasa() {
        let g = InitGuard()
        // Medido en F1 (2.1.307): sin herramientas; con --json-schema, StructuredOutput.
        #expect(g.evaluate(InitInfo(sessionID: "s", tools: [], mcpServers: [Self.tls], plugins: Self.deSerie)) == .permitido)
        #expect(g.evaluate(InitInfo(sessionID: "s", tools: ["StructuredOutput"], mcpServers: [Self.tls])) == .permitido)
        #expect(g.evaluate(InitInfo(sessionID: "s", tools: ["mcp__tls__tls_buscar", "mcp__tls__tls_finalizar",
                                                            "ListMcpResourcesTool", "ReadMcpResourceTool"],
                                    mcpServers: [Self.tls])) == .permitido)
    }

    @Test func herramientaIntegradaSePara() {
        let v = InitGuard().evaluate(InitInfo(sessionID: "s", tools: ["Bash", "mcp__tls__tls_leer", "Read"], mcpServers: [Self.tls]))
        #expect(v == .bloqueado([.herramientaAjena("Bash"), .herramientaAjena("Read")]))
    }

    /// Un segundo servidor en `mcp.json` (y sus herramientas) termina en `fallida(.guardia)`.
    @Test func segundoServidorSePara() {
        let info = InitInfo(sessionID: "s", tools: ["mcp__otro__enviar", "mcp__tlsx__a"],
                            mcpServers: [Self.tls, MCPServerStatus(name: "otro", status: "connected")])
        let v = InitGuard().evaluate(info)
        #expect(v == .bloqueado([.herramientaAjena("mcp__otro__enviar"), .herramientaAjena("mcp__tlsx__a"),
                                 .servidorAjeno("otro")]))
        #expect(!v.isAllowed)
    }

    @Test func otroModoSePara() {
        for modo in ["default", "acceptEdits", "bypassPermissions", "auto", "plan"] {
            #expect(InitGuard().evaluate(InitInfo(sessionID: "s", mcpServers: [Self.tls], permissionMode: modo))
                    == .bloqueado([.modoDistinto(modo)]))
        }
        #expect(InitGuard().evaluate(InitInfo(sessionID: "s", permissionMode: nil)) == .bloqueado([.modoDistinto(nil)]))
    }

    @Test func complementoAjenoYClaveDeAPI() {
        let info = InitInfo(sessionID: "s", mcpServers: [Self.tls], apiKeySource: "ANTHROPIC_API_KEY",
                            plugins: Self.deSerie + [PluginInfo(name: "mio", source: "mio@marketplace")])
        #expect(InitGuard().evaluate(info) == .bloqueado([.complementoAjeno("mio"), .claveAPI("ANTHROPIC_API_KEY")]))
    }

    /// `init` reales grabados en F1: el de un `mcp.json` con dos servidores se para; el de `--json-schema` pasa.
    @Test func initsGrabados() {
        func info(_ nombre: String) -> InitInfo? {
            var p = StreamJSONParser()
            for e in p.consume(Apoyo.grabacion(nombre)) + p.finish() { if case .inicio(let i) = e { return i } }
            return nil
        }
        #expect(InitGuard().evaluate(info("dos-servidores-2.1.307.jsonl")!) == .bloqueado([.servidorAjeno("otro")]))
        let esquema = info("init-esquema-2.1.307.jsonl")!
        #expect(esquema.tools == ["StructuredOutput"])
        #expect(InitGuard().evaluate(esquema) == .permitido)
        #expect(InitGuard().evaluate(info("sesion-nueva-2.1.307.jsonl")!) == .permitido)
    }

    @Test func listaBlancaNoAdmiteComodines() {
        let g = InitGuard(whitelist: [])
        #expect(g.evaluate(InitInfo(sessionID: "s", tools: ["StructuredOutput"])) == .bloqueado([.herramientaAjena("StructuredOutput")]))
        #expect(g.evaluate(InitInfo(sessionID: "s", tools: ["mcp__tls"])) == .bloqueado([.herramientaAjena("mcp__tls")]))
    }
}
