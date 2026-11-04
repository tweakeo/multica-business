import Foundation
import MCP
import Testing
@testable import TLSMCPShared

/// Tramas y mensajes del protocolo entre `tls-mcp` y la app.
struct IPCTests {
    @Test func tramasPartidasYJuntas() throws {
        let a = try IPCCodec.encode(IPCRequest(id: 1, operacion: .listarHerramientas))
        let b = try IPCCodec.encode(IPCRequest(id: 2, operacion: .llamar(nombre: "tls_leer", argumentos: ["ruta": "x.md"])))
        var r = IPCFrame.Reader()
        let todo = a + b
        r.append(todo.prefix(3))
        #expect(try r.next() == nil)
        r.append(todo.dropFirst(3))
        let f1 = try #require(try r.next())
        let f2 = try #require(try r.next())
        #expect(try r.next() == nil)
        #expect(try IPCCodec.decode(IPCRequest.self, from: f1).id == 1)
        let req = try IPCCodec.decode(IPCRequest.self, from: f2)
        guard case .llamar(let n, let args) = req.operacion else { Issue.record("operación"); return }
        #expect(n == "tls_leer")
        #expect(args["ruta"]?.stringValue == "x.md")
    }

    @Test func tramaDemasiadoGrandeSeRechaza() {
        var r = IPCFrame.Reader()
        var len = UInt32(IPCFrame.maxLength + 1).bigEndian
        r.append(Data(bytes: &len, count: 4))
        #expect(throws: IPCFrame.FrameError.self) { try r.next() }
    }

    @Test func ajustesDelBinario() throws {
        let token = String(repeating: "ab", count: 32)
        let a = try TLSMCPHelper.ajustes(argumentos: ["tls-mcp", "--socket", "/tmp/s.sock"], entorno: ["TLS_MCP_TOKEN": token])
        #expect(a.socket == "/tmp/s.sock")
        #expect(a.token == token)
        #expect(throws: TLSMCPHelper.ErrorDeAjustes.self) {
            try TLSMCPHelper.ajustes(argumentos: ["tls-mcp", "--socket", "/tmp/s.sock"], entorno: [:])
        }
        // Desde el fichero de la ejecución.
        let fichero = FileManager.default.temporaryDirectory.appendingPathComponent("token-\(UUID().uuidString)")
        try (token + "\n").write(to: fichero, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fichero) }
        let f = try TLSMCPHelper.ajustes(argumentos: ["tls-mcp", "--socket", "/tmp/s.sock", "--token-file", fichero.path], entorno: [:])
        #expect(f.token == token)
        #expect(throws: TLSMCPHelper.ErrorDeAjustes.tokenNoValido) {
            try TLSMCPHelper.ajustes(argumentos: ["tls-mcp", "--socket", "/tmp/s.sock", "--token", "corto"], entorno: [:])
        }
    }
}
