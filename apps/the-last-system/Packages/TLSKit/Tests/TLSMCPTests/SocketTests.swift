import Darwin
import Foundation
import MCP
import System
import Testing
import TLSAgents
@testable import TLSCore
@testable import TLSMCPHost
@testable import TLSMCPShared

/// `tls-mcp` compilado de verdad hablando con la app por el socket (PLAN §5.4): handshake MCP real, `tools/list`,
/// `tools/call`, `PeerValidator` (usuario, firma y token) y revocación. Sin Claude.
@Suite(.serialized)
struct SocketTests {
    /// Host sobre la empresa de prueba con el validador dado.
    static func host(_ e: ApoyoMCP.Empresa, validador: PeerValidator, tokens: AlmacenDeTokens = AlmacenDeTokens()) throws -> MCPHost {
        let socket = try MCPHost.rutaDelSocket(vaultID: e.service.entry.id.uuidString, appSupport: e.appSupport)
        let h = MCPHost(socket: socket, tokens: tokens, validador: validador, manejador: e.servidor(), auditoria: e.auditoria)
        try h.iniciar()
        return h
    }

    /// Requisito que cumple exactamente el `tls-mcp-dev` compilado (su identificador y su huella).
    static func requisitoDelHelper(_ helper: URL) throws -> String {
        var sc: SecStaticCode?
        guard SecStaticCodeCreateWithPath(helper as CFURL, [], &sc) == errSecSuccess, let sc,
              let info = PeerValidator.informacion(sc), let id = info[kSecCodeInfoIdentifier as String] as? String else {
            throw ErrorDeArgumentos("sin firma")
        }
        return try #require(PeerValidator.requisito(equipo: nil, cdhash: PeerValidator.cdhash(de: helper), identificador: id))
    }

    /// Lanza el binario con su socket y su token, con tuberías para stdio.
    final class Binario: @unchecked Sendable {
        let proceso = Process()
        let entrada = Pipe()
        let salida = Pipe()
        let errores = Pipe()

        init(_ helper: URL, socket: URL, token: String) throws {
            proceso.executableURL = helper
            proceso.arguments = ["--socket", socket.path]
            proceso.environment = ["TLS_MCP_TOKEN": token, "PATH": "/usr/bin:/bin"]
            proceso.standardInput = entrada
            proceso.standardOutput = salida
            proceso.standardError = errores
            try proceso.run()
        }

        var transporte: StdioTransport {
            StdioTransport(input: FileDescriptor(rawValue: salida.fileHandleForReading.fileDescriptor),
                           output: FileDescriptor(rawValue: entrada.fileHandleForWriting.fileDescriptor))
        }

        /// Espera a que termine (como mucho `segundos`) y si no, lo mata.
        func terminar(_ segundos: Double = 5) -> Int32 {
            try? entrada.fileHandleForWriting.close()
            let fin = Date().addingTimeInterval(segundos)
            while proceso.isRunning && Date() < fin { usleep(20_000) }
            if proceso.isRunning { proceso.terminate(); usleep(200_000) }
            if proceso.isRunning { kill(proceso.processIdentifier, SIGKILL) }
            proceso.waitUntilExit()
            return proceso.terminationStatus
        }

        var stderr: String {
            String(decoding: errores.fileHandleForReading.availableData, as: UTF8.self)
        }
    }

    @Test func handshakeMCPRealListarYLlamar() async throws {
        let helper = try #require(ApoyoMCP.helper, "Falta tls-mcp-dev junto a las pruebas")
        try await ApoyoMCP.conEmpresa { e in
            let h = try Self.host(e, validador: PeerValidator(firma: .requisito(try Self.requisitoDelHelper(helper))))
            defer { h.detener() }
            let token = h.tokens.emitir(ApoyoMCP.contexto(ejecucion: "r-socket"))
            let b = try Binario(helper, socket: h.socket, token: token)
            let cliente = Client(name: "prueba", version: "1")
            do {
                let ini = try await cliente.connect(transport: b.transporte)
                #expect(ini.serverInfo.name == "tls")
                let (tools, _) = try await cliente.listTools()
                let nombres = Set(tools.map(\.name))
                #expect(nombres.contains("tls_estado") && nombres.contains("tls_solicitar_accion") && nombres.contains("tls_delegar"))
                #expect(!nombres.contains("tls_movimientos"))
                #expect(tools.allSatisfy { $0.description?.isEmpty == false })
                let (leido, err) = try await cliente.callTool(name: "tls_leer", arguments: ["ruta": "Empresa.md"])
                #expect(err != true)
                guard case .text(let t, _, _) = leido.first else { Issue.record("sin texto"); return }
                #expect(t.contains("Contenido de «Empresa.md»"))
                let (privado, errPrivado) = try await cliente.callTool(name: "tls_leer", arguments: ["ruta": .string(ApoyoMCP.notaPrivada)])
                #expect(errPrivado == true)
                if case .text(let tp, _, _) = privado.first { #expect(tp == "No encontrado.") }
                let (creada, errCreada) = try await cliente.callTool(name: "tls_crear_tarea",
                                                                     arguments: ["titulo": "Tarea desde el socket", "area": "Dirección"])
                #expect(errCreada != true, "\(creada)")
                let (solicitud, _) = try await cliente.callTool(name: "tls_solicitar_accion",
                                                                arguments: ["accion": "enviar_correo", "borrador_id": "x"])
                if case .text(let ts, _, _) = solicitud.first { #expect(ts.contains("Aprobación requerida")) }
            } catch {
                Issue.record("MCP: \(error) · \(b.stderr)")
            }
            await cliente.disconnect()
            _ = b.terminar()
            #expect(!b.proceso.isRunning)
            let tareas = try FileManager.default.contentsOfDirectory(atPath: e.url("1 · Dirección/Tareas").path)
            #expect(tareas.contains { $0.contains("tarea-desde-el-socket") })
        }
    }

    /// Sin socket (la sonda de F1): servidor MCP sin ninguna herramienta. Con socket pero sin token: no arranca.
    @Test func sinSocketNoHayHerramientas() async throws {
        let helper = try #require(ApoyoMCP.helper, "Falta tls-mcp-dev junto a las pruebas")
        let p = Process()
        let entrada = Pipe(), salida = Pipe()
        p.executableURL = helper
        p.environment = ["PATH": "/usr/bin:/bin"]
        p.standardInput = entrada
        p.standardOutput = salida
        p.standardError = FileHandle.nullDevice
        try p.run()
        let cliente = Client(name: "prueba", version: "1")
        do {
            let t = StdioTransport(input: FileDescriptor(rawValue: salida.fileHandleForReading.fileDescriptor),
                                   output: FileDescriptor(rawValue: entrada.fileHandleForWriting.fileDescriptor))
            _ = try await cliente.connect(transport: t)
            let (tools, _) = try await cliente.listTools()
            #expect(tools.isEmpty)
        } catch {
            Issue.record("MCP: \(error)")
        }
        await cliente.disconnect()
        try? entrada.fileHandleForWriting.close()
        let fin = Date().addingTimeInterval(5)
        while p.isRunning && Date() < fin { usleep(20_000) }
        if p.isRunning { p.terminate() }
        p.waitUntilExit()
        // Con socket y sin token: sale con error sin servir nada.
        let q = Process()
        q.executableURL = helper
        q.arguments = ["--socket", "/tmp/no-existe.sock"]
        q.environment = ["PATH": "/usr/bin:/bin"]
        q.standardInput = Pipe()
        q.standardOutput = Pipe()
        q.standardError = FileHandle.nullDevice
        try q.run()
        q.waitUntilExit()
        #expect(q.terminationStatus == 64)
    }

    @Test func sinSaludoOConTokenMaloSeRechaza() async throws {
        try await ApoyoMCP.conEmpresa { e in
            // En el mismo proceso (sin firma que comprobar): usuario y token.
            let h = try Self.host(e, validador: PeerValidator(firma: .sinComprobarFirma))
            defer { h.detener() }
            // Sin saludo.
            let fd = try UnixSocket.connect(path: h.socket.path)
            UnixSocket.configure(fd, readTimeout: 5, writeTimeout: 5)
            try UnixSocket.writeAll(fd, try IPCCodec.encode(IPCRequest(id: 1, operacion: .listarHerramientas)))
            var reader = IPCFrame.Reader()
            let r = try IPCCodec.decode(IPCResponse.self, from: try UnixSocket.readFrame(fd, reader: &reader))
            guard case .error(let err) = r.resultado else { Issue.record("debía rechazar"); return }
            #expect(err.codigo == .noAutorizado)
            #expect(throws: (any Error).self) { _ = try UnixSocket.readFrame(fd, reader: &reader) }  // cerrada
            close(fd)
            // Con un token que no existe.
            #expect {
                _ = try IPCCliente.conectar(socket: h.socket.path, token: String(repeating: "0", count: 64), timeout: 5)
            } throws: { ($0 as? IPCError)?.codigo == .tokenNoValido }
            #expect(e.auditoria.eventos.filter { $0.accion == "saludo" && $0.veredicto == "rechazado" }.count == 2)
        }
    }

    @Test func tokenRevocadoOCaducadoSeRechaza() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let reloj = RelojDePrueba()
            let tokens = AlmacenDeTokens(duracionMaxima: 60, ahora: { reloj.ahora })
            let h = try Self.host(e, validador: PeerValidator(firma: .sinComprobarFirma), tokens: tokens)
            defer { h.detener() }
            // Revocado en mitad de la ejecución: la siguiente llamada ya no pasa.
            let t1 = tokens.emitir(ApoyoMCP.contexto(ejecucion: "r-1"))
            let c1 = try IPCCliente.conectar(socket: h.socket.path, token: t1, timeout: 5)
            guard case .herramientas(let specs) = try c1.enviarSincrono(.listarHerramientas) else { Issue.record("lista"); return }
            #expect(!specs.isEmpty)
            h.revocar(ejecucion: "r-1")
            #expect(throws: (any Error).self) { _ = try c1.enviarSincrono(.listarHerramientas) }
            c1.cerrar()
            #expect(throws: IPCError.self) { _ = try IPCCliente.conectar(socket: h.socket.path, token: t1, timeout: 5) }
            // Caducado: pasada la duración máxima, el mismo token ya no vale.
            let t2 = tokens.emitir(ApoyoMCP.contexto(ejecucion: "r-2"))
            let c2 = try IPCCliente.conectar(socket: h.socket.path, token: t2, timeout: 5)
            reloj.adelantar(61)
            let r = try c2.enviarSincrono(.listarHerramientas)
            guard case .error(let err) = r else { Issue.record("debía caducar"); return }
            #expect(err.codigo == .tokenNoValido)
            c2.cerrar()
            #expect(tokens.contexto(de: t2) == nil)
        }
    }

    @Test func firmaQueNoCoincideSeRechazaAlAceptar() async throws {
        let helper = try #require(ApoyoMCP.helper, "Falta tls-mcp-dev junto a las pruebas")
        try await ApoyoMCP.conEmpresa { e in
            // El requisito de la app (otro identificador y un equipo): el binario de pruebas no lo cumple.
            let requisito = try #require(PeerValidator.requisito(equipo: "ABCDE12345", cdhash: nil))
            let h = try Self.host(e, validador: PeerValidator(firma: .requisito(requisito)))
            defer { h.detener() }
            let token = h.tokens.emitir(ApoyoMCP.contexto(ejecucion: "r-firma"))
            let b = try Binario(helper, socket: h.socket, token: token)
            let status = b.terminar(5)
            #expect(status != 0)
            #expect(e.auditoria.eventos.contains { $0.accion == "conexion" && $0.veredicto == "rechazado" })
            // Y desde este proceso (que tampoco es tls-mcp), igual.
            #expect(throws: (any Error).self) { _ = try IPCCliente.conectar(socket: h.socket.path, token: token, timeout: 5) }
            // Sin equipo ni huella no hay requisito: la app no aceptaría a nadie.
            #expect(PeerValidator.requisito(equipo: nil, cdhash: nil) == nil)
        }
    }

    @Test func socketConPermisosYUnoPorEmpresa() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let h = try Self.host(e, validador: PeerValidator(firma: .sinComprobarFirma))
            #expect(h.socket.path.utf8.count < 104)
            #expect(h.socket.lastPathComponent.count == "xxxxxxxx.sock".count)
            var st = stat()
            #expect(lstat(h.socket.path, &st) == 0)
            #expect(st.st_mode & S_IFMT == S_IFSOCK)
            #expect(st.st_mode & 0o777 == 0o600)
            #expect(lstat(h.socket.deletingLastPathComponent().path, &st) == 0)
            #expect(st.st_mode & 0o777 == 0o700)
            // Otra instancia sobre la misma empresa: no.
            let otra = MCPHost(socket: h.socket, validador: PeerValidator(firma: .sinComprobarFirma), manejador: e.servidor())
            #expect(throws: MCPHostError.self) { try otra.iniciar() }
            h.detener()
            #expect(!FileManager.default.fileExists(atPath: h.socket.path))
            // Ruta demasiado larga: error claro, sin crear nada.
            let larga = URL(fileURLWithPath: "/tmp/" + String(repeating: "x", count: 120))
            #expect(throws: MCPHostError.self) { try MCPHost.rutaDelSocket(vaultID: "abc", appSupport: larga) }
        }
    }

    @Test func mcpJsonConSoloEsteServidor() throws {
        let base = ApoyoMCP.baseCorta()
        defer { try? FileManager.default.removeItem(at: base) }
        let paths = try AgentPaths(vaultState: base, slug: "mika", runID: "r-json")
        let token = String(repeating: "a", count: 64)
        try ConfiguracionMCP.escribir(en: paths, helper: URL(fileURLWithPath: "/App.app/Contents/Helpers/tls-mcp"),
                                      socket: base.appendingPathComponent("s/x.sock"), token: token)
        let data = try Data(contentsOf: paths.mcpConfig)
        let json = try JSONSerialization.jsonObject(with: data)
        let obj = try #require(json as? [String: Any])
        let servers = try #require(obj["mcpServers"] as? [String: Any])
        #expect(Array(servers.keys) == ["tls"])
        let tls = try #require(servers["tls"] as? [String: Any])
        #expect(tls["command"] as? String == "/App.app/Contents/Helpers/tls-mcp")
        #expect((tls["args"] as? [String])?.contains(token) == false, "el token nunca va en los argumentos")
        #expect((tls["env"] as? [String: String])?["TLS_MCP_TOKEN"] == token)
        let attrs = try FileManager.default.attributesOfItem(atPath: paths.mcpConfig.path)
        #expect((attrs[FileAttributeKey.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
}
