import Foundation

/// Directorios de un agente y de una ejecución (PLAN §3.4):
/// `<vault-id>/agentes/<slug>/` (estable: `cwd` del proceso, para `--resume`) y
/// `<vault-id>/ejecuciones/<run>/` (`agente.sb`, `mcp.json`, `settings.json`, `stream.jsonl`, `tmp/`).
public struct AgentPaths: Sendable, Equatable {
    /// Estado de la carpeta fuera de ella: `AppLocations.vaultState(id)`.
    public var vaultState: URL
    public var slug: String
    public var runID: String

    public init(vaultState: URL, slug: String, runID: String = AgentPaths.newRunID()) throws {
        guard Self.isSafeName(slug) else { throw SandboxProfileError.rutaNoValida(slug) }
        guard Self.isSafeName(runID) else { throw SandboxProfileError.rutaNoValida(runID) }
        self.vaultState = vaultState; self.slug = slug; self.runID = runID
    }

    /// `AAAAMMDD-HHmmss-xxxxxx` (ordenable y sin colisiones prácticas).
    public static func newRunID(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: now) + "-" + UUID().uuidString.prefix(6).lowercased()
    }

    /// Solo minúsculas, cifras, guiones y guiones bajos.
    static func isSafeName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 64 && s.unicodeScalars.allSatisfy {
            ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" || $0 == "_"
        }
    }

    public var agentDirectory: URL {
        vaultState.appendingPathComponent("agentes", isDirectory: true).appendingPathComponent(slug, isDirectory: true)
    }
    public var runDirectory: URL {
        vaultState.appendingPathComponent("ejecuciones", isDirectory: true).appendingPathComponent(runID, isDirectory: true)
    }
    public var profile: URL { runDirectory.appendingPathComponent("agente.sb") }
    public var mcpConfig: URL { runDirectory.appendingPathComponent("mcp.json") }
    public var settings: URL { runDirectory.appendingPathComponent("settings.json") }
    public var stream: URL { runDirectory.appendingPathComponent("stream.jsonl") }
    public var tmp: URL { runDirectory.appendingPathComponent("tmp", isDirectory: true) }

    /// Crea los directorios (0700).
    public func create() throws {
        let fm = FileManager.default
        for dir in [agentDirectory, runDirectory, tmp] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}

/// Un servidor MCP por stdio para `mcp.json`.
public struct MCPServerConfig: Sendable, Hashable {
    public var command: String
    public var args: [String]
    public var env: [String: String]

    public init(command: String, args: [String] = [], env: [String: String] = [:]) {
        self.command = command; self.args = args; self.env = env
    }
}

/// Ficheros de configuración de cada ejecución.
public enum RunFiles {
    /// `{"mcpServers": {...}}` con `type: stdio`.
    public static func mcpConfig(_ servers: [String: MCPServerConfig]) throws -> Data {
        var dict: [String: Any] = [:]
        for (name, s) in servers {
            dict[name] = ["type": "stdio", "command": s.command, "args": s.args, "env": s.env] as [String: Any]
        }
        return try JSONSerialization.data(withJSONObject: ["mcpServers": dict],
                                          options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
    }

    /// `settings.json` de la ejecución (PLAN §5.3). `--restricted` ignora los ajustes del usuario:
    /// la app nunca toca `~/.claude/settings.json`.
    public static func settings(allow: [String] = ["mcp__tls"]) throws -> Data {
        let obj: [String: Any] = [
            "disableAllHooks": true,
            "permissions": ["defaultMode": "dontAsk", "allow": allow] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted])
    }

    /// Mensaje de usuario para `--input-format stream-json` (una línea).
    public static func userMessage(_ text: String) throws -> Data {
        let obj: [String: Any] = ["type": "user", "message": ["role": "user", "content": text] as [String: Any]]
        var data = try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    /// Escribe con permisos 0600.
    static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
