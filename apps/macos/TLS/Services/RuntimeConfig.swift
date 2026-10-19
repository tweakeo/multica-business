import Foundation

/// Endpoints the renderer talks to. Mirrors apps/desktop/src/shared/runtime-config.ts.
struct RuntimeConfig: Codable, Equatable {
    var schemaVersion = 1
    var apiUrl: String
    var wsUrl: String
    var appUrl: String
    /// "embedded" runs PostgreSQL and the API inside the app (LocalStack);
    /// "external" (or absent, for configs written before 0.1) uses the URLs.
    var mode: String?

    static let embeddedDefault = RuntimeConfig(
        apiUrl: LocalStack.apiURL,
        wsUrl: "ws://127.0.0.1:\(LocalStack.apiPort)/ws",
        appUrl: LocalStack.apiURL,
        mode: "embedded"
    )
}

enum AppPaths {
    /// Per-user host state (config, logs). Never inside a synced company folder.
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TLS", isDirectory: true)
    }

    static var runtimeConfig: URL { support.appendingPathComponent("runtime-config.json") }
}

struct ConfigError: Error {
    let message: String
}

enum RuntimeConfigStore {
    /// Loads `runtime-config.json`. A new install gets embedded mode; an
    /// external server is configured explicitly; nothing is discovered.
    static func load() -> Result<RuntimeConfig, ConfigError> {
        let url = AppPaths.runtimeConfig
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
                let data = try JSONEncoder.pretty.encode(RuntimeConfig.embeddedDefault)
                try data.write(to: url, options: .atomic)
            }
            let config = try JSONDecoder().decode(RuntimeConfig.self, from: Data(contentsOf: url))
            if config.mode == "embedded" { return .success(.embeddedDefault) }
            if let problem = validate(config) { return .failure(ConfigError(message: "\(url.path): \(problem)")) }
            return .success(config)
        } catch {
            return .failure(ConfigError(message: "\(url.path): \(error.localizedDescription)"))
        }
    }

    static var isEmbedded: Bool {
        if case let .success(config) = load() { return config.mode == "embedded" }
        return false
    }

    private static func validate(_ config: RuntimeConfig) -> String? {
        guard config.schemaVersion == 1 else { return "unsupported schemaVersion \(config.schemaVersion)" }
        let checks: [(String, String, Set<String>)] = [
            ("apiUrl", config.apiUrl, ["http", "https"]),
            ("wsUrl", config.wsUrl, ["ws", "wss"]),
            ("appUrl", config.appUrl, ["http", "https"]),
        ]
        for (name, value, schemes) in checks {
            guard let scheme = URL(string: value)?.scheme?.lowercased(), schemes.contains(scheme) else {
                return "\(name) must be a \(schemes.sorted().joined(separator: "/")) URL"
            }
        }
        return nil
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
