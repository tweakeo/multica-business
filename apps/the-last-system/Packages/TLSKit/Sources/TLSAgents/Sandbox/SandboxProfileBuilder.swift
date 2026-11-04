import Darwin
import Foundation

public enum SandboxProfileError: Error, Equatable, CustomStringConvertible {
    /// Ruta relativa, con comillas o con saltos de línea: no se puede escribir en el perfil sin riesgo.
    case rutaNoValida(String)

    public var description: String {
        switch self {
        case .rutaNoValida(let p): "Ruta no válida para el perfil de sandbox: \(p)"
        }
    }
}

/// Perfil de `sandbox-exec` de una ejecución de asistente (PLAN §5.3, con las correcciones de F1).
///
/// - Niega la carpeta personal, `/Volumes` y la carpeta de la empresa.
/// - Deja leer la carpeta personal en sí, Claude Code y la app (para `tls-mcp`).
/// - Deja leer y escribir la sesión de Claude (`~/.claude`, `~/.claude.json*`), el Llavero
///   (renovación del OAuth; `/usr/bin/security` se permite), el directorio estable del agente y el
///   de la ejecución; pero no escribir lo de `~/.claude` que se ejecuta fuera de la caja (ajustes, órdenes, subagentes,
///   ganchos, complementos: `protegidasDeClaude`).
/// - Sockets: solo el del MCP de la carpeta y el de DNS (`mDNSResponder`; sin él no hay red,
///   comprobado en F1: «ENOTFOUND»).
/// - Sin `osascript` ni Apple Events.
/// - La carpeta de la empresa se vuelve a negar al final, para que ninguna regla anterior la abra.
///
/// Las reglas comparan rutas reales (`/tmp` es `/private/tmp`), así que todo se resuelve con `realpath`.
public struct SandboxProfileBuilder: Sendable {
    public static let sandboxExec = "/usr/bin/sandbox-exec"
    public static let dnsSocket = "/private/var/run/mDNSResponder"

    public var home: URL
    /// Carpetas de empresa (y cualquier otra) que nunca se leen ni se escriben.
    public var deniedRoots: [URL]
    /// Directorio estable del agente (`<vault-id>/agentes/<slug>`), `cwd` del proceso.
    public var agentDirectory: URL
    /// Directorio de la ejecución (`<vault-id>/ejecuciones/<run>`).
    public var runDirectory: URL
    /// Socket del MCP de la carpeta (puede no existir todavía).
    public var socket: URL?
    /// Lectura adicional: el bundle de la app (`tls-mcp`) y, si está fuera de `~/.local`, Claude Code.
    public var readOnly: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, deniedRoots: [URL],
                agentDirectory: URL, runDirectory: URL, socket: URL? = nil, readOnly: [URL] = []) {
        self.home = home; self.deniedRoots = deniedRoots; self.agentDirectory = agentDirectory
        self.runDirectory = runDirectory; self.socket = socket; self.readOnly = readOnly
    }

    /// Lo que hay que dejar leer para ejecutar `binary` si no está en `~/.local/share/claude`
    /// (por ejemplo, una instalación con npm: se abre el paquete entero).
    public static func claudeReadPaths(binary: URL, home: URL) -> [URL] {
        let real = URL(fileURLWithPath: realPath(binary.path))
        let local = realPath(home.appendingPathComponent(".local/share/claude").path)
        if real.path.hasPrefix(local + "/") { return [] }
        var dir = real.deletingLastPathComponent()
        if dir.lastPathComponent == "bin" { dir = dir.deletingLastPathComponent() }
        return [dir]
    }

    public func build() throws -> String {
        let h = try Self.checked(Self.realPath(home.path))
        let denied = try (deniedRoots.map { Self.realPath($0.path) } + ["/Volumes"]).map(Self.checked)
        let agent = try Self.checked(Self.realPath(agentDirectory.path))
        let run = try Self.checked(Self.realPath(runDirectory.path))
        let extra = try readOnly.map { try Self.checked(Self.realPath($0.path)) }
        let sock = try socket.map { try Self.checked(Self.realPath($0.path)) }
        let vaults = try deniedRoots.map { try Self.checked(Self.realPath($0.path)) }

        func sub(_ p: String) -> String { "(subpath \(Self.quote(p)))" }
        func lit(_ p: String) -> String { "(literal \(Self.quote(p)))" }

        var lines: [String] = [
            ";; The Last System · perfil de una ejecución de asistente (PLAN §5.3). Generado: no editar.",
            "(version 1)",
            "(allow default)",
            ";; Nada de la carpeta personal, discos externos ni la carpeta de la empresa.",
            "(deny file-read* file-write* \(([sub(h)] + denied.map(sub)).joined(separator: " ")))",
            "(allow file-read-metadata)",
            ";; Lectura: la carpeta personal en sí, Claude Code y la app (tls-mcp).",
            "(allow file-read* \(([lit(h), sub(h + "/.local/share/claude"), sub(h + "/.local/bin")] + extra.map(sub)).joined(separator: " ")))",
            ";; Lectura y escritura: sesión de Claude, Llavero (renovación del OAuth), agente y ejecución.",
            "(allow file-read* file-write* \(sub(h + "/.claude")) (regex #\"^\(Self.regexEscape(h))/\\.claude\\.json\") "
                + "\(sub(h + "/Library/Keychains")) \(sub(agent)) \(sub(run)))",
            ";; Pero no lo que Claude Code usa FUERA de la caja en las sesiones de la persona (ajustes con ganchos, órdenes,",
            ";; subagentes, complementos, instrucciones): un proceso de dentro no puede dejar nada que se ejecute sin caja.",
            "(deny file-write* \(Self.protegidasDeClaude(h).joined(separator: " ")))",
            ";; Sockets locales: solo el del MCP de esta carpeta y el de DNS.",
            "(deny network-outbound (remote unix-socket))",
            "(allow network-outbound (remote unix-socket (path-literal \(Self.quote(Self.dnsSocket)))))",
        ]
        if let sock {
            lines.append("(allow network-outbound (remote unix-socket (path-literal \(Self.quote(sock)))))")
        }
        lines += [
            ";; Sin automatización: ni osascript ni Apple Events (/usr/bin/security sí se permite).",
            "(deny process-exec (literal \"/usr/bin/osascript\"))",
            "(deny appleevent-send)",
        ]
        if !vaults.isEmpty {
            lines.append(";; La carpeta de la empresa, otra vez al final: gana a cualquier permiso anterior.")
            lines.append("(deny file-read* file-write* \(vaults.map(sub).joined(separator: " ")))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// F4 · corrector (R7): lo de `~/.claude` que Claude Code lee fuera de la caja y que puede ejecutar algo
    /// (`settings.json` con sus ganchos, `commands/`, `agents/`, `hooks/`, `skills/`, `plugins/`, `output-styles/`,
    /// `CLAUDE.md`). Las sesiones, el estado y las credenciales siguen abiertos.
    static func protegidasDeClaude(_ h: String) -> [String] {
        let base = h + "/.claude"
        let ficheros = ["settings.json", "settings.local.json", "CLAUDE.md", "keybindings.json"].map { "(literal \(quote(base + "/" + $0)))" }
        let carpetas = ["commands", "agents", "hooks", "skills", "plugins", "output-styles"].map { "(subpath \(quote(base + "/" + $0)))" }
        return ficheros + carpetas
    }

    /// Escribe el perfil (0600) y devuelve su ruta.
    @discardableResult
    public func write(to url: URL) throws -> URL {
        try Data(try build().utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Rutas y escapes

    /// `realpath`; si no existe, el de la carpeta que la contiene más el nombre.
    public static func realPath(_ path: String) -> String {
        if let p = Darwin.realpath(path, nil) { defer { free(p) }; return String(cString: p) }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        guard parent != path, !parent.isEmpty else { return url.standardizedFileURL.path }
        return (realPath(parent) as NSString).appendingPathComponent(url.lastPathComponent)
    }

    static func checked(_ p: String) throws -> String {
        guard p.hasPrefix("/"), !p.contains("\""), !p.contains("\n"), !p.contains("\r"), !p.contains("\0")
        else { throw SandboxProfileError.rutaNoValida(p) }
        return p
    }

    /// Cadena del perfil entre comillas (SBPL admite `\\` y `\"`).
    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Escapa una ruta para usarla literal dentro de una expresión regular.
    static func regexEscape(_ s: String) -> String {
        var out = ""
        for c in s {
            if "\\^$.|?*+()[]{}".contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }
}
