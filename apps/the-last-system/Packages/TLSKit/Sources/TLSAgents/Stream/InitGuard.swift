import Foundation

/// Revisa el evento `system/init` antes de dejar trabajar a un asistente (PLAN §5.3).
///
/// Se para la ejecución (SIGTERM al grupo → `fallida(.guardia)`) si la sesión trae:
/// - una herramienta que no es `mcp__tls__*` ni de la lista blanca medida;
/// - un servidor MCP distinto del de la app;
/// - un modo de permisos distinto de `dontAsk`;
/// - un complemento que no venga de serie (`…@builtin`);
/// - una clave de API (el uso va con la suscripción; una clave cobraría aparte).
public struct InitGuard: Sendable {
    /// Medida en F1 con Claude Code 2.1.307, `--restricted --tools ""` y un `tls-mcp` sin herramientas:
    /// `tools` llega vacío; con `--json-schema` aparece `StructuredOutput`. Las dos de recursos MCP
    /// (del PLAN) aparecen solo si el servidor ofrece recursos; se admiten porque solo leen de `tls`.
    public static let measuredWhitelist: Set<String> = ["StructuredOutput", "ListMcpResourcesTool", "ReadMcpResourceTool"]

    public enum Reason: Sendable, Equatable, CustomStringConvertible {
        case herramientaAjena(String)
        case servidorAjeno(String)
        case modoDistinto(String?)
        case complementoAjeno(String)
        case claveAPI(String)

        public var description: String {
            switch self {
            case .herramientaAjena(let t): "herramienta no permitida: \(t)"
            case .servidorAjeno(let s): "servidor no permitido: \(s)"
            case .modoDistinto(let m): "modo de permisos distinto de dontAsk: \(m ?? "ninguno")"
            case .complementoAjeno(let p): "complemento no permitido: \(p)"
            case .claveAPI(let s): "usa una clave de API (\(s)) en vez de la suscripción"
            }
        }
    }

    public enum Verdict: Sendable, Equatable {
        case permitido
        case bloqueado([Reason])

        public var isAllowed: Bool { self == .permitido }
    }

    public var server: String
    public var whitelist: Set<String>
    public var mode: String

    public init(server: String = "tls", whitelist: Set<String> = InitGuard.measuredWhitelist, mode: String = "dontAsk") {
        self.server = server; self.whitelist = whitelist; self.mode = mode
    }

    public func evaluate(_ info: InitInfo) -> Verdict {
        var reasons: [Reason] = []
        let prefix = "mcp__\(server)__"
        for tool in info.tools where !(tool.hasPrefix(prefix) || whitelist.contains(tool)) {
            reasons.append(.herramientaAjena(tool))
        }
        for s in info.mcpServers where s.name != server {
            reasons.append(.servidorAjeno(s.name))
        }
        if info.permissionMode != mode { reasons.append(.modoDistinto(info.permissionMode)) }
        for p in info.plugins where !p.source.hasSuffix("@builtin") && p.source != "builtin" {
            reasons.append(.complementoAjeno(p.name))
        }
        if let key = info.apiKeySource, key != "none" { reasons.append(.claveAPI(key)) }
        return reasons.isEmpty ? .permitido : .bloqueado(reasons)
    }
}
