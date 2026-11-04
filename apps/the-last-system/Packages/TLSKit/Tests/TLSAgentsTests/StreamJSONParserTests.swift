import Foundation
import Testing
@testable import TLSAgents

/// Contrato del `stream-json` con streams grabados de Claude Code 2.1.307 (saneados: sin rutas ni datos reales).
@Suite struct StreamJSONParserTests {
    static func eventos(_ data: Data) -> [AgentEvent] {
        var p = StreamJSONParser()
        return p.consume(data) + p.finish()
    }

    @Test func sesionNuevaGrabada() throws {
        let ev = Self.eventos(Apoyo.grabacion("sesion-nueva-2.1.307.jsonl"))
        #expect(ev.count == 4)
        guard case .inicio(let info) = ev[0] else { Issue.record("falta init"); return }
        #expect(info.sessionID == "62aebe90-174e-4be0-91d9-ac42f0c6591f")
        #expect(info.tools.isEmpty)
        #expect(info.mcpServers == [MCPServerStatus(name: "tls", status: "connected")])
        #expect(info.permissionMode == "dontAsk")
        #expect(info.apiKeySource == "none")
        #expect(info.claudeCodeVersion == "2.1.307")
        #expect(info.plugins.allSatisfy { $0.source.hasSuffix("@builtin") })
        #expect(info.cwd?.hasSuffix("/agentes/sonda") == true)
        #expect(ev[1] == .texto("listo"))
        guard case .limiteUso(let rl) = ev[2] else { Issue.record("falta rate_limit_event"); return }
        #expect(rl.status == "allowed")
        #expect(rl.limitType == "five_hour")
        guard case .resultado(let r) = ev[3] else { Issue.record("falta result"); return }
        #expect(r.subtype == "success" && !r.isError)
        #expect(r.text == "listo")
        #expect(r.sessionID == info.sessionID)
        #expect((r.totalCostUSD ?? 0) > 0)
        #expect(r.terminalReason == "completed")
        #expect(RunState.from(result: r) == .completada)
    }

    @Test func reanudarConservaLaSesion() {
        let ev = Self.eventos(Apoyo.grabacion("reanudar-2.1.307.jsonl"))
        guard case .inicio(let info) = ev.first, case .resultado(let r) = ev.last else {
            Issue.record("faltan init o result"); return
        }
        #expect(info.sessionID == "62aebe90-174e-4be0-91d9-ac42f0c6591f")
        #expect(r.sessionID == info.sessionID)
    }

    /// Primera prueba real de F1: sin el socket de DNS en el perfil no hay red; el CLI reintenta 10 veces
    /// y cierra con `success` pero `is_error` (manda `is_error`).
    @Test func sinRedGrabado() {
        let ev = Self.eventos(Apoyo.grabacion("sin-red-2.1.307.jsonl"))
        let reintentos = ev.filter { if case .reintento = $0 { true } else { false } }
        #expect(reintentos.count == 10)
        #expect(ev.contains { if case .errorAPI(let tipo, let t) = $0 { tipo == "server_error" && t.contains("ENOTFOUND") } else { false } })
        guard case .resultado(let r) = ev.last else { Issue.record("falta result"); return }
        #expect(r.subtype == "success" && r.isError)
        #expect(r.terminalReason == "api_error")
        #expect(RunState.from(result: r) == .fallida(.red))
        #expect(FailureReason.red.retriable)
    }

    /// Las líneas pueden llegar partidas por cualquier byte (también a mitad de un carácter UTF-8).
    @Test func trozosArbitrarios() {
        let data = Apoyo.grabacion("sin-red-2.1.307.jsonl") + Apoyo.grabacion("sesion-nueva-2.1.307.jsonl")
        let entero = Self.eventos(data)
        for tam in [1, 2, 3, 7, 64, 1000] {
            var p = StreamJSONParser()
            var ev: [AgentEvent] = []
            var i = data.startIndex
            while i < data.endIndex {
                let j = min(i + tam, data.endIndex)
                ev += p.consume(data[i..<j])
                i = j
            }
            ev += p.finish()
            #expect(ev == entero, "trozos de \(tam) bytes")
        }
    }

    @Test func herramientasYResultados() {
        let lineas = """
        {"type":"assistant","message":{"content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"Busco"},{"type":"tool_use","id":"t1","name":"mcp__tls__tls_buscar","input":{"q":"caja","limite":3}}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":[{"type":"text","text":"2 resultados"}]}]}}
        {"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","is_error":true,"content":"no encontrado"}]}}
        {"type":"result","subtype":"error_max_budget_usd","is_error":true,"total_cost_usd":0.5,"num_turns":3,"permission_denials":[{"tool_name":"Bash"}]}
        """
        let ev = Self.eventos(Data(lineas.utf8))
        #expect(ev == [
            .razonamiento,
            .texto("Busco"),
            .herramienta(id: "t1", nombre: "mcp__tls__tls_buscar", entrada: #"{"limite":3,"q":"caja"}"#),
            .resultadoHerramienta(id: "t1", esError: false, texto: "2 resultados"),
            .resultadoHerramienta(id: "t2", esError: true, texto: "no encontrado"),
            .resultado(ResultInfo(subtype: "error_max_budget_usd", isError: true, totalCostUSD: 0.5, numTurns: 3,
                                  permissionDenials: 1)),
        ])
        if case .resultado(let r) = ev.last { #expect(RunState.from(result: r) == .fallida(.presupuesto)) }
        #expect(ev[2].resumen == "Usando tls_buscar…")
    }

    @Test func loDesconocidoNoRompe() {
        let lineas = "esto no es json\n{\"type\":\"stream_event\",\"x\":1}\n{\"type\":\"system\",\"subtype\":\"compact_boundary\"}\n\n   \n{\"sin_tipo\":true}\n"
        #expect(Self.eventos(Data(lineas.utf8)) == [
            .lineaInvalida("esto no es json"), .otro("stream_event"), .sistema("compact_boundary"),
            .lineaInvalida(#"{"sin_tipo":true}"#),
        ])
    }

    @Test func estadoSegunResultado() {
        #expect(RunState.from(result: nil) == .fallida(.sinResultado))
        #expect(RunState.from(result: ResultInfo(subtype: "success", isError: true, apiErrorStatus: 429)) == .fallida(.limiteUso))
        #expect(RunState.from(result: ResultInfo(subtype: "success", isError: true, apiErrorStatus: 529)) == .fallida(.sobrecarga))
        #expect(RunState.from(result: ResultInfo(subtype: "success", isError: true, text: "Not logged in · Please run /login"))
                == .fallida(.sinSesion))
        #expect(RunState.from(result: ResultInfo(subtype: "error_during_execution", isError: true)) == .fallida(.error))
        // Nunca se reintenta ante sesión, presupuesto, guardia o interruptor.
        for m in [FailureReason.sinSesion, .presupuesto, .guardia, .flagsAusentes] { #expect(!m.retriable) }
    }
}
