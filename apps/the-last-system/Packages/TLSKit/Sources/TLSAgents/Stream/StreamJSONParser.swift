import Foundation

/// Traduce `--output-format stream-json` (una línea JSON por evento) a `AgentEvent`.
///
/// Admite trozos de cualquier tamaño (una línea puede llegar partida, incluso a mitad de un carácter).
/// Lo desconocido no rompe nada: queda como `.otro` o `.sistema` y el crudo se guarda aparte (`stream.jsonl`).
public struct StreamJSONParser: Sendable {
    private var buffer = Data()

    public init() {}

    /// Añade un trozo y devuelve los eventos de las líneas completas.
    public mutating func consume(_ chunk: Data) -> [AgentEvent] {
        buffer.append(chunk)
        var events: [AgentEvent] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            events += Self.events(fromLine: Data(line))
        }
        return events
    }

    /// Procesa lo que quede sin salto de línea final.
    public mutating func finish() -> [AgentEvent] {
        defer { buffer.removeAll() }
        return Self.events(fromLine: buffer)
    }

    /// Eventos de una línea (un mensaje del asistente con varios bloques da varios eventos).
    public static func events(fromLine line: Data) -> [AgentEvent] {
        let trimmed = line.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
        guard !trimmed.isEmpty, !(trimmed.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) else { return [] }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(trimmed)) as? [String: Any],
              let type = obj["type"] as? String
        else { return [.lineaInvalida(String(String(decoding: trimmed, as: UTF8.self).prefix(200)))] }

        switch type {
        case "system":
            let subtype = obj["subtype"] as? String ?? ""
            switch subtype {
            case "init": return [.inicio(initInfo(obj))]
            case "api_retry":
                return [.reintento(intento: int(obj["attempt"]) ?? 0, maximo: int(obj["max_retries"]),
                                   esperaMS: int(obj["retry_delay_ms"]), estadoHTTP: int(obj["error_status"]))]
            default: return [.sistema(subtype)]
            }
        case "assistant":
            let message = obj["message"] as? [String: Any] ?? [:]
            let blocks = message["content"] as? [[String: Any]] ?? []
            if obj["is_api_error_message"] as? Bool == true || (obj["error"] as? String) != nil {
                let text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
                return [.errorAPI(tipo: obj["error"] as? String ?? "desconocido", texto: text)]
            }
            return blocks.compactMap { block -> AgentEvent? in
                switch block["type"] as? String {
                case "text": return (block["text"] as? String).map(AgentEvent.texto)
                case "thinking", "redacted_thinking": return .razonamiento
                case "tool_use":
                    return .herramienta(id: block["id"] as? String ?? "", nombre: block["name"] as? String ?? "",
                                        entrada: compactJSON(block["input"]))
                default: return nil
                }
            }
        case "user":
            let message = obj["message"] as? [String: Any] ?? [:]
            guard let blocks = message["content"] as? [[String: Any]] else { return [] }
            return blocks.compactMap { block -> AgentEvent? in
                guard block["type"] as? String == "tool_result" else { return nil }
                return .resultadoHerramienta(id: block["tool_use_id"] as? String ?? "",
                                             esError: block["is_error"] as? Bool ?? false,
                                             texto: toolResultText(block["content"]))
            }
        case "rate_limit_event":
            let info = obj["rate_limit_info"] as? [String: Any] ?? [:]
            let resets = (info["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return [.limiteUso(RateLimitInfo(status: info["status"] as? String,
                                             limitType: info["rateLimitType"] as? String, resetsAt: resets))]
        case "result":
            return [.resultado(ResultInfo(
                subtype: obj["subtype"] as? String ?? "",
                isError: obj["is_error"] as? Bool ?? false,
                text: obj["result"] as? String,
                totalCostUSD: (obj["total_cost_usd"] as? NSNumber)?.doubleValue,
                numTurns: int(obj["num_turns"]),
                durationMS: int(obj["duration_ms"]),
                sessionID: obj["session_id"] as? String,
                terminalReason: obj["terminal_reason"] as? String,
                apiErrorStatus: int(obj["api_error_status"]),
                permissionDenials: (obj["permission_denials"] as? [Any])?.count ?? 0))]
        default:
            return [.otro(type)]
        }
    }

    static func initInfo(_ obj: [String: Any]) -> InitInfo {
        let servers = (obj["mcp_servers"] as? [[String: Any]] ?? []).map {
            MCPServerStatus(name: $0["name"] as? String ?? "", status: $0["status"] as? String ?? "")
        }
        let plugins = (obj["plugins"] as? [Any] ?? []).map { item -> PluginInfo in
            if let d = item as? [String: Any] {
                return PluginInfo(name: d["name"] as? String ?? "", source: d["source"] as? String ?? (d["path"] as? String ?? ""))
            }
            return PluginInfo(name: "\(item)", source: "")
        }
        return InitInfo(
            sessionID: obj["session_id"] as? String ?? "",
            tools: strings(obj["tools"]),
            mcpServers: servers,
            permissionMode: obj["permissionMode"] as? String,
            model: obj["model"] as? String,
            cwd: obj["cwd"] as? String,
            claudeCodeVersion: obj["claude_code_version"] as? String,
            apiKeySource: obj["apiKeySource"] as? String,
            plugins: plugins,
            skills: strings(obj["skills"]),
            slashCommands: strings(obj["slash_commands"]))
    }

    /// Lista de nombres; admite cadenas u objetos con `name`.
    static func strings(_ v: Any?) -> [String] {
        (v as? [Any] ?? []).compactMap { ($0 as? String) ?? (($0 as? [String: Any])?["name"] as? String) }
    }

    static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

    static func compactJSON(_ v: Any?) -> String {
        guard let v, JSONSerialization.isValidJSONObject(v),
              let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return v.map { "\($0)" } ?? "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    static func toolResultText(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let blocks = v as? [[String: Any]] {
            return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        return ""
    }
}
