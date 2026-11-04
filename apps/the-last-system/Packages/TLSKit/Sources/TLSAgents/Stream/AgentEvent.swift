import Foundation

/// Servidor MCP tal como lo anuncia `system/init`.
public struct MCPServerStatus: Sendable, Equatable, Codable {
    public var name: String
    public var status: String

    public init(name: String, status: String) { self.name = name; self.status = status }
}

/// Complemento cargado, tal como lo anuncia `system/init` (`source` acaba en `@builtin` si viene de serie).
public struct PluginInfo: Sendable, Equatable, Codable {
    public var name: String
    public var source: String

    public init(name: String, source: String) { self.name = name; self.source = source }
}

/// Evento `system/init`: lo que la sesión tiene de verdad a mano. `InitGuard` lo revisa.
public struct InitInfo: Sendable, Equatable {
    public var sessionID: String
    public var tools: [String]
    public var mcpServers: [MCPServerStatus]
    public var permissionMode: String?
    public var model: String?
    public var cwd: String?
    public var claudeCodeVersion: String?
    public var apiKeySource: String?
    public var plugins: [PluginInfo]
    public var skills: [String]
    public var slashCommands: [String]

    public init(sessionID: String, tools: [String] = [], mcpServers: [MCPServerStatus] = [],
                permissionMode: String? = "dontAsk", model: String? = nil, cwd: String? = nil,
                claudeCodeVersion: String? = nil, apiKeySource: String? = "none", plugins: [PluginInfo] = [],
                skills: [String] = [], slashCommands: [String] = []) {
        self.sessionID = sessionID; self.tools = tools; self.mcpServers = mcpServers
        self.permissionMode = permissionMode; self.model = model; self.cwd = cwd
        self.claudeCodeVersion = claudeCodeVersion; self.apiKeySource = apiKeySource; self.plugins = plugins
        self.skills = skills; self.slashCommands = slashCommands
    }
}

/// Evento `result`: cierre de la ejecución, con el coste que informa el CLI.
public struct ResultInfo: Sendable, Equatable {
    /// `success` o `error_*` (por ejemplo `error_max_budget_usd`).
    public var subtype: String
    public var isError: Bool
    public var text: String?
    public var totalCostUSD: Double?
    public var numTurns: Int?
    public var durationMS: Int?
    public var sessionID: String?
    /// `completed`, `api_error`… (el CLI marca `success` aunque haya error de API: manda `isError`).
    public var terminalReason: String?
    public var apiErrorStatus: Int?
    public var permissionDenials: Int

    public init(subtype: String, isError: Bool, text: String? = nil, totalCostUSD: Double? = nil,
                numTurns: Int? = nil, durationMS: Int? = nil, sessionID: String? = nil,
                terminalReason: String? = nil, apiErrorStatus: Int? = nil, permissionDenials: Int = 0) {
        self.subtype = subtype; self.isError = isError; self.text = text; self.totalCostUSD = totalCostUSD
        self.numTurns = numTurns; self.durationMS = durationMS; self.sessionID = sessionID
        self.terminalReason = terminalReason; self.apiErrorStatus = apiErrorStatus
        self.permissionDenials = permissionDenials
    }
}

/// `rate_limit_event`: estado del límite de uso de la suscripción.
public struct RateLimitInfo: Sendable, Equatable {
    /// `allowed`, `allowed_warning`, `rejected`…
    public var status: String?
    public var limitType: String?
    public var resetsAt: Date?

    public init(status: String?, limitType: String? = nil, resetsAt: Date? = nil) {
        self.status = status; self.limitType = limitType; self.resetsAt = resetsAt
    }
}

/// Lo que pasa en una ejecución, ya traducido del `stream-json` del CLI.
public enum AgentEvent: Sendable, Equatable {
    case inicio(InitInfo)
    /// Texto del asistente.
    case texto(String)
    /// Bloque de razonamiento (no se muestra su contenido).
    case razonamiento
    /// Llamada a una herramienta; `entrada` en JSON compacto.
    case herramienta(id: String, nombre: String, entrada: String)
    case resultadoHerramienta(id: String, esError: Bool, texto: String)
    /// Mensaje sintético de error de la API (sin red, sesión caducada…).
    case errorAPI(tipo: String, texto: String)
    /// `system/api_retry`: el CLI reintenta por su cuenta.
    case reintento(intento: Int, maximo: Int?, esperaMS: Int?, estadoHTTP: Int?)
    case limiteUso(RateLimitInfo)
    case resultado(ResultInfo)
    /// Otro subtipo de `system` (por ejemplo `compact_boundary`).
    case sistema(String)
    /// Tipo que esta versión no conoce: se conserva en el crudo, aquí solo el nombre.
    case otro(String)
    /// Línea que no es JSON (se guarda recortada).
    case lineaInvalida(String)
}

extension AgentEvent {
    /// Texto breve y sin jerga para la ficha en directo («Leyendo…», «Creando tarea…»).
    public var resumen: String? {
        switch self {
        case .inicio: "Empezando…"
        case .texto: "Escribiendo…"
        case .razonamiento: "Pensando…"
        case .herramienta(_, let nombre, _): "Usando \(nombre.replacingOccurrences(of: "mcp__tls__", with: ""))…"
        case .reintento: "Esperando a que responda el servicio…"
        case .limiteUso(let r) where r.status == "rejected": "Límite de uso alcanzado"
        case .errorAPI: "Error al hablar con el servicio"
        default: nil
        }
    }
}
