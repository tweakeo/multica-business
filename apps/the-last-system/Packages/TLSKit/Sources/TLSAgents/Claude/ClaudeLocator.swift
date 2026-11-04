import Darwin
import Foundation

/// Versión de Claude Code («2.1.307 (Claude Code)» → 2.1.307).
public struct ClaudeVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ text: String) {
        let token = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).first.map(String.init) ?? ""
        let parts = token.split(separator: ".").map { Int($0) }
        guard parts.count >= 2, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.map { $0! }
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (a: ClaudeVersion, b: ClaudeVersion) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

/// Resultado de `claude auth status --json`. Solo se guarda lo que la app necesita:
/// ni correo, ni organización, ni rutas.
public struct ClaudeAuthStatus: Sendable, Equatable {
    public var loggedIn: Bool
    public var authMethod: String?
    public var apiProvider: String?
    public var subscriptionType: String?

    public init(loggedIn: Bool, authMethod: String? = nil, apiProvider: String? = nil, subscriptionType: String? = nil) {
        self.loggedIn = loggedIn; self.authMethod = authMethod
        self.apiProvider = apiProvider; self.subscriptionType = subscriptionType
    }

    /// Lee la salida JSON (puede venir con texto alrededor).
    public static func parse(_ data: Data) throws -> ClaudeAuthStatus {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let obj = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let logged = obj["loggedIn"] as? Bool
        else { throw ClaudeLocatorError.authIlegible(String(text.prefix(300))) }
        return ClaudeAuthStatus(loggedIn: logged, authMethod: obj["authMethod"] as? String,
                                apiProvider: obj["apiProvider"] as? String,
                                subscriptionType: obj["subscriptionType"] as? String)
    }
}

/// Dónde está Claude Code en este Mac.
public struct ClaudeInstallation: Sendable, Equatable {
    /// Ruta tal como aparece en el PATH (p. ej. `~/.local/bin/claude`, que es un enlace).
    public var found: URL
    /// Binario real, con los enlaces resueltos: es lo que se ejecuta.
    public var binary: URL
    /// `true` si es un ejecutable Mach-O (no un guion que delega en otro programa).
    public var isNative: Bool
    public var version: ClaudeVersion?
}

public enum ClaudeLocatorError: Error, Equatable, CustomStringConvertible {
    case noEncontrado([String])
    case versionIlegible(String)
    case authIlegible(String)
    case ordenFallida(String, Int32, String)

    public var description: String {
        switch self {
        case .noEncontrado: "No encuentro Claude Code en este Mac. Lo demás sigue funcionando sin asistentes."
        case .versionIlegible(let s): "Claude Code no ha dicho su versión de forma reconocible: \(s)"
        case .authIlegible(let s): "No entiendo el estado de la sesión de Claude: \(s)"
        case .ordenFallida(let o, let c, let e): "«claude \(o)» ha fallado (código \(c)): \(e)"
        }
    }
}

/// Entorno mínimo de los procesos de Claude (PLAN §5.3). Se construye desde cero: nunca lleva
/// `ANTHROPIC_API_KEY` ni nada del entorno de la app.
public enum AgentEnvironment {
    public static let path = "/usr/bin:/bin:/usr/sbin:/sbin"

    public static func minimal(home: URL, tmp: URL? = nil, user: String = NSUserName(),
                               lang: String? = nil) -> [String: String] {
        var env = [
            "PATH": path,
            "HOME": home.path,
            "USER": user,
            "LOGNAME": user,
            "LANG": lang ?? ProcessInfo.processInfo.environment["LANG"].flatMap { $0.isEmpty ? nil : $0 } ?? "es_ES.UTF-8",
            "DISABLE_AUTOUPDATER": "1",
            "CLAUDE_CODE_DISABLE_CLAUDE_MDS": "1",
            "CLAUDE_CODE_DISABLE_AUTO_MEMORY": "1",
            "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        ]
        if let tmp { env["TMPDIR"] = tmp.path }
        return env
    }
}

/// Encuentra el binario real de Claude Code (PLAN §5.3, `ClaudeLocator`).
///
/// No se pregunta a la shell por `claude` (puede ser un alias, como `claude --remote-control`):
/// se toma el PATH de la shell de login interactiva y se busca el fichero en cada carpeta,
/// después en las de reserva. Los enlaces se resuelven para ejecutar siempre el binario real.
public struct ClaudeLocator: Sendable {
    /// Versión con la que se verificaron los flags y el sandbox. Otra versión avisa, no bloquea.
    public static let verifiedVersion = ClaudeVersion("2.1.307")!

    public var home: URL
    public var shell: String
    public var fallbackDirectories: [URL]

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, shell: String? = nil,
                fallbackDirectories: [URL]? = nil) {
        self.home = home
        self.shell = shell ?? Self.loginShell()
        self.fallbackDirectories = fallbackDirectories ?? [
            home.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
        ]
    }

    /// Shell de login de la cuenta (no `$SHELL`, que una app abierta desde el Finder puede no tener).
    public static func loginShell() -> String {
        if let pw = getpwuid(getuid()), let sh = pw.pointee.pw_shell {
            let s = String(cString: sh)
            if !s.isEmpty, FileManager.default.isExecutableFile(atPath: s) { return s }
        }
        return "/bin/zsh"
    }

    static let marker = "__TLS_PATH__"

    /// PATH de la shell de login interactiva (`-ilc`: lee también `.zshrc`, donde suele estar
    /// `~/.local/bin`). Si falla o tarda más de `timeout`, lista vacía.
    public func loginShellPATH(timeout: TimeInterval = 5) async -> [String] {
        let spec = ProcessSpec(
            executable: shell,
            arguments: ["-ilc", "printf '\\n\(Self.marker)%s\(Self.marker)\\n' \"$PATH\""],
            environment: ["HOME": home.path, "USER": NSUserName(), "LOGNAME": NSUserName(), "SHELL": shell,
                          "TERM": "dumb", "PATH": AgentEnvironment.path],
            directory: home.path, timeout: timeout, grace: 1, maxCapture: 256 * 1024)
        guard let out = try? await ProcessRunner.run(spec), !out.timedOut else { return [] }
        return Self.parsePATH(out.stdoutText) ?? []
    }

    /// Extrae el PATH entre las marcas (lo que impriman los ficheros de la shell se ignora).
    public static func parsePATH(_ output: String) -> [String]? {
        let parts = output.components(separatedBy: marker)
        guard parts.count >= 3 else { return nil }
        let dirs = parts[1].split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return dirs.isEmpty ? nil : dirs
    }

    /// Candidatos `<carpeta>/claude`: primero el PATH, después las de reserva, sin repetir.
    public func candidates(path: [String]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for dir in path.map({ URL(fileURLWithPath: $0, isDirectory: true) }) + fallbackDirectories {
            let url = dir.appendingPathComponent("claude").standardizedFileURL
            if seen.insert(url.path).inserted { result.append(url) }
        }
        return result
    }

    /// Primer candidato que sea un fichero ejecutable, con su binario real.
    public static func firstExecutable(in candidates: [URL]) -> (found: URL, binary: URL)? {
        for c in candidates {
            guard let real = realPath(c) else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: real, isDirectory: &isDir), !isDir.boolValue,
                  FileManager.default.isExecutableFile(atPath: real) else { continue }
            return (c, URL(fileURLWithPath: real))
        }
        return nil
    }

    public static func realPath(_ url: URL) -> String? {
        guard let p = Darwin.realpath(url.path, nil) else { return nil }
        defer { free(p) }
        return String(cString: p)
    }

    /// `true` si el fichero empieza por una cabecera Mach-O (fina o universal).
    public static func isMachO(_ url: URL) -> Bool {
        guard let h = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 4), d.count == 4 else { return false }
        let magic = d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xFEEDFACF, 0xCFFAEDFE, 0xFEEDFACE, 0xCEFAEDFE, 0xCAFEBABE, 0xBEBAFECA].contains(magic)
    }

    /// Busca Claude Code y pide su versión.
    public func locate() async throws -> ClaudeInstallation {
        let list = candidates(path: await loginShellPATH())
        guard let hit = Self.firstExecutable(in: list) else {
            throw ClaudeLocatorError.noEncontrado(list.map(\.path))
        }
        let version = try? await version(of: hit.binary)
        return ClaudeInstallation(found: hit.found, binary: hit.binary, isNative: Self.isMachO(hit.binary),
                                  version: version)
    }

    /// Aviso (sin bloquear) si la versión no es la verificada.
    public static func versionWarning(_ v: ClaudeVersion?) -> String? {
        guard let v else { return "No he podido leer la versión de Claude Code. Sigo, pero conviene repetir la prueba del sandbox." }
        guard v != verifiedVersion else { return nil }
        return "Claude Code \(v) no es la versión comprobada (\(verifiedVersion)). Sigo, pero conviene repetir la prueba del sandbox."
    }

    func plain(_ binary: URL, _ args: [String], timeout: TimeInterval = 20) async throws -> ProcessOutput {
        let tmp = FileManager.default.temporaryDirectory
        return try await ProcessRunner.run(ProcessSpec(
            executable: binary.path, arguments: args,
            environment: AgentEnvironment.minimal(home: home), directory: tmp.path, timeout: timeout))
    }

    public func version(of binary: URL) async throws -> ClaudeVersion {
        let out = try await plain(binary, ["--version"])
        guard out.status == 0, let v = ClaudeVersion(out.stdoutText) else {
            throw ClaudeLocatorError.versionIlegible(String((out.stdoutText + out.stderrText).prefix(200)))
        }
        return v
    }

    /// `claude --help` para el preflight de flags.
    public func help(of binary: URL) async throws -> ClaudeHelp {
        let out = try await plain(binary, ["--help"])
        guard out.status == 0 else {
            throw ClaudeLocatorError.ordenFallida("--help", out.status, String(out.stderrText.prefix(300)))
        }
        return ClaudeHelp(text: out.stdoutText)
    }

    /// `claude auth status --json`; con `profile`, dentro de ese perfil de sandbox (PLAN: «dentro del perfil final»).
    public func authStatus(binary: URL, profile: URL? = nil, environment: [String: String]? = nil,
                           directory: URL? = nil, timeout: TimeInterval = 30) async throws -> ClaudeAuthStatus {
        var exe = binary.path
        var args = ["auth", "status", "--json"]
        if let profile {
            exe = SandboxProfileBuilder.sandboxExec
            args = ["-f", profile.path, binary.path] + args
        }
        let out = try await ProcessRunner.run(ProcessSpec(
            executable: exe, arguments: args,
            environment: environment ?? AgentEnvironment.minimal(home: home),
            directory: (directory ?? FileManager.default.temporaryDirectory).path, timeout: timeout))
        // Sin sesión, el CLI responde también en JSON (con otro código de salida).
        do { return try ClaudeAuthStatus.parse(out.stdout) } catch {
            throw ClaudeLocatorError.ordenFallida("auth status", out.status, String(out.stderrText.prefix(300)))
        }
    }
}
