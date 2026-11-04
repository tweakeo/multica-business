import Darwin
import Foundation
import MCP

/// El binario `tls-mcp` (PLAN §5.4): un servidor MCP por stdio que **no lee la carpeta** ni nada del disco. Cada
/// `tools/list` y `tools/call` se reenvía a la app por el socket; la app decide y escribe. Hereda el sandbox del
/// asistente (solo puede conectarse a su socket).
///
/// Ajustes (de `mcp.json`): `--socket <ruta>` o `TLS_MCP_SOCKET`; el token, por `TLS_MCP_TOKEN` o en el fichero de la
/// ejecución (`--token-file`), nunca en los argumentos de la app (`--token`, solo pruebas). Nunca escribe en stdout salvo
/// el protocolo MCP: los avisos van a stderr.
public enum TLSMCPHelper {
    public struct Ajustes: Sendable, Equatable {
        public var socket: String
        public var token: String
    }

    public enum ErrorDeAjustes: Error, Equatable, CustomStringConvertible {
        case falta(String)
        case tokenNoValido

        public var description: String {
            switch self {
            case .falta(let que): "Falta \(que). Este programa lo lanza The Last System para sus asistentes."
            case .tokenNoValido: "El token de la ejecución no es válido."
            }
        }
    }

    /// Lee los ajustes de los argumentos y del entorno (los argumentos ganan).
    public static func ajustes(argumentos: [String], entorno: [String: String]) throws -> Ajustes {
        func valor(_ flag: String) -> String? {
            guard let i = argumentos.firstIndex(of: flag), i + 1 < argumentos.count else { return nil }
            return argumentos[i + 1]
        }
        guard let socket = valor("--socket") ?? entorno[TLSMCPInfo.socketEnvironmentKey], !socket.isEmpty else {
            throw ErrorDeAjustes.falta("la ruta del socket")
        }
        // El token: por el entorno (`mcp.json`), por `--token` (pruebas) o en un fichero de la ejecución (`<run>/token`,
        // 0600; `--token-file` o `TLS_MCP_TOKEN_FILE`). Nunca se lee nada de la carpeta de la empresa.
        var token = valor("--token") ?? entorno[TLSMCPInfo.tokenEnvironmentKey]
        if token?.isEmpty ?? true, let fichero = valor("--token-file") ?? entorno[TLSMCPInfo.tokenFileEnvironmentKey], !fichero.isEmpty,
           let data = FileManager.default.contents(atPath: fichero), data.count <= 256 {
            token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let token, !token.isEmpty else {
            throw ErrorDeAjustes.falta("el token de la ejecución")
        }
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else { throw ErrorDeAjustes.tokenNoValido }
        return Ajustes(socket: socket, token: token)
    }

    /// Punto de entrada del binario. Devuelve el código de salida.
    public static func main(argumentos: [String] = CommandLine.arguments,
                            entorno: [String: String] = ProcessInfo.processInfo.environment) async -> Int32 {
        if argumentos.contains("--version") {
            print("tls-mcp \(TLSMCPInfo.version)")
            return 0
        }
        // Sin socket (la sonda de F1, `make sandbox`): servidor sin ninguna herramienta, como el de F0. No puede hacer
        // nada: no hay con quién hablar. Con socket, todo tiene que cuadrar o no se arranca.
        let sinSocket = (valorDe("--socket", argumentos) ?? entorno[TLSMCPInfo.socketEnvironmentKey] ?? "").isEmpty
        if sinSocket {
            aviso("sin conexión con la app: no hay herramientas.")
            return await servirSinHerramientas()
        }
        let ajustes: Ajustes
        do {
            ajustes = try Self.ajustes(argumentos: argumentos, entorno: entorno)
        } catch {
            aviso("\(error)")
            return 64
        }
        let cliente: IPCCliente
        do {
            cliente = try IPCCliente.conectar(socket: ajustes.socket, token: ajustes.token)
        } catch let e as IPCError {
            aviso("La app no acepta esta conexión: \(e.mensaje)")
            return 77
        } catch {
            aviso("No puedo conectar con The Last System: \(error)")
            return 69
        }
        defer { cliente.cerrar() }
        let server = TLSMCPInfo.makeServer()
        await registrar(en: server, cliente: cliente)
        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            aviso("El servidor de herramientas se paró: \(error)")
            return 70
        }
        return 0
    }

    static func valorDe(_ flag: String, _ argumentos: [String]) -> String? {
        guard let i = argumentos.firstIndex(of: flag), i + 1 < argumentos.count else { return nil }
        return argumentos[i + 1]
    }

    /// Servidor MCP sin herramientas (sin socket).
    static func servirSinHerramientas() async -> Int32 {
        let server = TLSMCPInfo.makeServer()
        await server.withMethodHandler(ListTools.self) { _ in ListTools.Result(tools: []) }
        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            return 70
        }
        return 0
    }

    /// Manejadores que reenvían a la app.
    public static func registrar(en server: Server, cliente: IPCCliente) async {
        await server.withMethodHandler(ListTools.self) { _ in
            switch try await cliente.enviar(.listarHerramientas) {
            case .herramientas(let specs): return ListTools.Result(tools: specs.map(\.tool))
            case .error(let e): throw MCPError.internalError(e.mensaje)
            default: throw MCPError.internalError("La app respondió algo inesperado.")
            }
        }
        await server.withMethodHandler(CallTool.self) { params in
            do {
                switch try await cliente.enviar(.llamar(nombre: params.name, argumentos: params.arguments ?? [:])) {
                case .llamada(let r): return r.callResult
                case .error(let e): return ToolResult(texto: e.mensaje, esError: true).callResult
                default: return ToolResult(texto: "La app respondió algo inesperado.", esError: true).callResult
                }
            } catch {
                return ToolResult(texto: "No hay conexión con la app: \(error)", esError: true).callResult
            }
        }
    }

    static func aviso(_ texto: String) {
        FileHandle.standardError.write(Data(("tls-mcp: " + texto + "\n").utf8))
    }
}
