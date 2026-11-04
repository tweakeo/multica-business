import Foundation

/// Flags y órdenes que declara `claude --help`. Solo cuenta lo que aparece como opción
/// (una línea con dos espacios y un guion); las menciones dentro de una descripción no cuentan.
public struct ClaudeHelp: Sendable, Equatable {
    public var options: Set<String>
    public var commands: Set<String>

    public init(options: Set<String>, commands: Set<String> = []) {
        self.options = options; self.commands = commands
    }

    public init(text: String) {
        var options = Set<String>(), commands = Set<String>()
        var section = ""
        for raw in text.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            if !line.hasPrefix(" "), line.hasSuffix(":") { section = line.lowercased(); continue }
            // Exactamente dos espacios: las continuaciones de una descripción van más sangradas.
            guard line.hasPrefix("  "), !line.hasPrefix("   ") else { continue }
            let body = line.dropFirst(2)
            if section.hasPrefix("options"), body.hasPrefix("-") {
                for token in body.split(separator: " ", omittingEmptySubsequences: true) {
                    let t = token.trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    if t.hasPrefix("-") {
                        options.insert(String(t.split(separator: "=").first ?? Substring(t)))
                    } else if t.hasPrefix("<") || t.hasPrefix("[") {
                        continue
                    } else {
                        break
                    }
                }
            } else if section.hasPrefix("commands"), let first = body.split(separator: " ").first {
                for name in first.split(separator: "|") { commands.insert(String(name)) }
            }
        }
        self.options = options; self.commands = commands
    }

    public func supports(_ flag: String) -> Bool { options.contains(flag) }
}

/// Cómo arranca la sesión de una ejecución.
public enum ClaudeSession: Sendable, Equatable {
    /// Sesión nueva con este identificador.
    case new(UUID)
    /// Reanuda la sesión (desde el mismo directorio estable).
    case resume(UUID)
    /// Sin guardar nada (clasificador, entrevistador, pruebas).
    case ephemeral
}

/// Opciones de una ejecución de `claude -p` (PLAN §5.3, «Lanzamiento»).
public struct ClaudeRunOptions: Sendable {
    public var session: ClaudeSession
    public var mcpConfig: URL
    public var settings: URL
    /// Instrucciones del rol (brief). Con `--append-system-prompt-file` si existe; si no, su texto.
    public var brief: URL?
    public var model: String?
    public var effort: String?
    public var maxBudgetUSD: Double
    public var jsonSchema: String?
    /// Herramientas permitidas: solo las del servidor de la app.
    public var allowedTools: String

    public init(session: ClaudeSession, mcpConfig: URL, settings: URL, brief: URL? = nil, model: String? = nil,
                effort: String? = nil, maxBudgetUSD: Double, jsonSchema: String? = nil,
                allowedTools: String = "mcp__tls") {
        self.session = session; self.mcpConfig = mcpConfig; self.settings = settings; self.brief = brief
        self.model = model; self.effort = effort; self.maxBudgetUSD = maxBudgetUSD
        self.jsonSchema = jsonSchema; self.allowedTools = allowedTools
    }
}

public enum PreflightError: Error, Equatable, CustomStringConvertible {
    /// Faltan flags imprescindibles para lanzar con seguridad: no se lanza.
    case flagsAusentes([String])
    case briefIlegible(String)

    public var description: String {
        switch self {
        case .flagsAusentes(let f):
            "Esta versión de Claude Code no tiene opciones que la app necesita para trabajar con seguridad (\(f.joined(separator: ", "))). Los asistentes quedan parados."
        case .briefIlegible(let p): "No se pudieron leer las instrucciones del asistente (\(p))."
        }
    }
}

/// Línea de órdenes de `claude` tras el preflight: solo lleva flags presentes en `--help`.
public struct ClaudeCommandLine: Sendable, Equatable {
    public var arguments: [String]
    /// Opciones prescindibles que esta versión no tiene (se lanzan sin ellas).
    public var warnings: [String]

    /// Herramientas integradas que se niegan aunque `--tools ""` ya las quite.
    public static let deniedBuiltins = "Bash,Read,Edit,Write,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,AskUserQuestion"

    /// Nunca se usa (no existe en 2.1.306/2.1.307); el tope va con `--max-budget-usd`.
    public static let neverUsed: Set<String> = ["--max-turns", "--dangerously-skip-permissions",
                                                "--allow-dangerously-skip-permissions"]

    public static func build(_ o: ClaudeRunOptions, help: ClaudeHelp) throws -> ClaudeCommandLine {
        var args: [String] = []
        var missing: [String] = []
        var warnings: [String] = []

        func required(_ flag: String, _ values: String...) {
            if help.supports(flag) { args.append(flag); args.append(contentsOf: values) } else { missing.append(flag) }
        }
        func optional(_ flag: String, _ values: String...) {
            if help.supports(flag) { args.append(flag); args.append(contentsOf: values) } else { warnings.append(flag) }
        }

        if help.supports("-p") { args.append("-p") } else { required("--print") }
        required("--output-format", "stream-json")
        required("--input-format", "stream-json")
        required("--verbose")
        switch o.session {
        case .new(let id): required("--session-id", id.uuidString.lowercased())
        case .resume(let id): required("--resume", id.uuidString.lowercased())
        case .ephemeral: required("--no-session-persistence")
        }
        required("--restricted")
        required("--tools", "")
        optional("--disable-slash-commands")
        required("--mcp-config", o.mcpConfig.path)
        required("--strict-mcp-config")
        required("--allowedTools", o.allowedTools)
        required("--disallowedTools", deniedBuiltins)
        required("--permission-mode", "dontAsk")
        required("--permission-prompts", "none")
        required("--settings", o.settings.path)
        if let brief = o.brief {
            if help.supports("--append-system-prompt-file") {
                args += ["--append-system-prompt-file", brief.path]
            } else if help.supports("--append-system-prompt") {
                guard let text = try? String(contentsOf: brief, encoding: .utf8) else {
                    throw PreflightError.briefIlegible(brief.lastPathComponent)
                }
                args += ["--append-system-prompt", text]
            } else {
                missing.append("--append-system-prompt")
            }
        }
        if let model = o.model { optional("--model", model) }
        if let effort = o.effort { optional("--effort", effort) }
        if let schema = o.jsonSchema { required("--json-schema", schema) }
        required("--max-budget-usd", String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), o.maxBudgetUSD))

        guard missing.isEmpty else { throw PreflightError.flagsAusentes(missing) }
        assert(!args.contains { neverUsed.contains($0) })
        return ClaudeCommandLine(arguments: args, warnings: warnings)
    }
}
