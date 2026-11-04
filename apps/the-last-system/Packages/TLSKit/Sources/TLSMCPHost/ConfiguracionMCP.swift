import Foundation
import TLSAgents
import TLSMCPShared

/// `mcp.json` de cada ejecución, con **solo** el servidor `tls` (PLAN §5.3–§5.4): el binario `tls-mcp`, la ruta del
/// socket como argumento y el token de la ejecución por el entorno (no se ve en `ps`).
public enum ConfiguracionMCP {
    /// `{"tls": {command: <tls-mcp>, args: ["--socket", <socket>], env: {TLS_MCP_TOKEN: <token>}}}`.
    public static func servidores(helper: URL, socket: URL, token: String) -> [String: MCPServerConfig] {
        [TLSMCPInfo.serverName: MCPServerConfig(command: helper.path, args: ["--socket", socket.path],
                                                env: [TLSMCPInfo.tokenEnvironmentKey: token])]
    }

    /// Contenido de `mcp.json`.
    public static func json(helper: URL, socket: URL, token: String) throws -> Data {
        try RunFiles.mcpConfig(servidores(helper: helper, socket: socket, token: token))
    }

    /// Escribe `mcp.json` en la carpeta de la ejecución con permisos 0600 (lleva el token).
    public static func escribir(en paths: AgentPaths, helper: URL, socket: URL, token: String) throws {
        try paths.create()
        let data = try json(helper: helper, socket: socket, token: token)
        try data.write(to: paths.mcpConfig, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.mcpConfig.path)
    }

    /// `Contents/Helpers/tls-mcp` del bundle de la app (si existe y es ejecutable).
    public static func helperDelBundle(_ bundle: URL = Bundle.main.bundleURL) -> URL? {
        let url = bundle.appendingPathComponent("Contents/Helpers/tls-mcp")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// Dónde está `tls-mcp`: `TLS_MCP_HELPER` (pruebas), el bundle de la app o, en desarrollo, la app compilada en
    /// `build/DerivedData` del repositorio.
    public static func localizarHelper(bundle: URL = Bundle.main.bundleURL,
                                       entorno: [String: String] = ProcessInfo.processInfo.environment,
                                       repositorio: URL? = nil) -> URL? {
        let fm = FileManager.default
        if let e = entorno["TLS_MCP_HELPER"], !e.isEmpty, fm.isExecutableFile(atPath: e) { return URL(fileURLWithPath: e) }
        if let b = helperDelBundle(bundle) { return b }
        guard let repo = repositorio else { return nil }
        for conf in ["Debug", "Release"] {
            let url = repo.appendingPathComponent("build/DerivedData/Build/Products/\(conf)/The Last System.app/Contents/Helpers/tls-mcp")
            if fm.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }
}
