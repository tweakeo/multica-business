import Foundation
import MCP

/// Piezas compartidas entre la app y el binario auxiliar `tls-mcp`.
public enum TLSMCPInfo {
    /// Nombre del servidor en `mcp.json`: las herramientas se ven como `mcp__tls__<herramienta>`.
    public static let serverName = "tls"
    public static let version = "0.5.0"
    /// Identificador de firma del binario auxiliar (`PeerValidator` lo exige al otro lado del socket).
    public static let helperIdentifier = "es.thelast.system.tls-mcp"
    /// Variables de entorno que pone `mcp.json` (el token nunca va en los argumentos: se vería en `ps`).
    public static let socketEnvironmentKey = "TLS_MCP_SOCKET"
    public static let tokenEnvironmentKey = "TLS_MCP_TOKEN"
    /// Alternativa: ruta del fichero `<run>/token` (0600) que escribe el motor.
    public static let tokenFileEnvironmentKey = "TLS_MCP_TOKEN_FILE"
    /// Versión del protocolo entre `tls-mcp` y la app (sube si cambia `IPCRequest`/`IPCResponse`).
    public static let ipcProtocol = 1

    /// Servidor MCP vacío (solo declara herramientas). El binario le añade los manejadores que reenvían a la app.
    public static func makeServer() -> Server {
        Server(name: serverName, version: version, capabilities: .init(tools: .init(listChanged: false)))
    }
}
