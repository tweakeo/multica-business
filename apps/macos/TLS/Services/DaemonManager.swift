import AppKit
import Foundation

/// Supervises the bundled `multica` daemon for a host-owned CLI profile.
/// A reduced port of apps/desktop/src/main/daemon-manager.ts: it starts and
/// stops the daemon, keeps the profile token in sync and reports status. Not
/// ported yet: crash-recovery budget, CLI download fallback, WSL detection.
@MainActor
final class DaemonManager {
    static let shared = DaemonManager()

    struct Status: Equatable {
        var state: String
        var pid: Int?
        var uptime: String?
        var daemonId: String?
        var deviceName: String?
        var agents: [String]?
        var serverUrl: String?

        var json: [String: Any] {
            var out: [String: Any] = ["state": state, "profile": DaemonManager.profile]
            if let pid { out["pid"] = pid }
            if let uptime { out["uptime"] = uptime }
            if let daemonId { out["daemonId"] = daemonId }
            if let deviceName { out["deviceName"] = deviceName }
            if let agents { out["agents"] = agents }
            if let serverUrl { out["serverUrl"] = serverUrl }
            return out
        }
    }

    struct Prefs: Codable {
        var autoStart = true
        var autoStop = false
        var json: [String: Any] { ["autoStart": autoStart, "autoStop": autoStop] }
    }

    /// Host-owned profile; never the user's default `~/.multica` profile.
    static let profile = "tls-local"

    var onStatusChange: ((Any) -> Void)?
    var onLogLine: ((String) -> Void)?
    private(set) var prefs: Prefs
    private var targetApiUrl: String?
    private var transitional: String?
    private var lastStatus: Status?
    private var pollTimer: Timer?
    private var logTimer: Timer?
    private var logOffset: UInt64 = 0
    private lazy var spawnPath: String = Self.loginShellPath()

    private init() {
        if let data = UserDefaults.standard.data(forKey: "daemonPrefs"),
           let saved = try? JSONDecoder().decode(Prefs.self, from: data) {
            prefs = saved
        } else {
            prefs = Prefs()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in _ = await self?.status() }
        }
    }

    // MARK: Paths

    private var profileDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".multica/profiles/\(Self.profile)", isDirectory: true)
    }

    private var configURL: URL { profileDir.appendingPathComponent("config.json") }
    private var userIdURL: URL { profileDir.appendingPathComponent("tls_user_id") }
    private var logURL: URL { profileDir.appendingPathComponent("daemon.log") }

    private var cliURL: URL? { Bundle.main.resourceURL?.appendingPathComponent("bin/multica") }

    var isCliInstalled: Bool {
        guard let cliURL else { return false }
        return FileManager.default.isExecutableFile(atPath: cliURL.path)
    }

    /// Same derivation as healthPortForProfile in server/cmd/multica/cmd_daemon.go.
    private var healthPort: Int {
        19514 + 1 + Self.profile.utf8.reduce(0) { $0 + Int($1) } % 1000
    }

    // MARK: Status

    @discardableResult
    func status() async -> Status {
        let next: Status
        if !isCliInstalled {
            next = Status(state: "cli_not_found")
        } else if let health = await fetchHealth() {
            next = Status(
                state: "running",
                pid: health["pid"] as? Int,
                uptime: health["uptime"] as? String,
                daemonId: health["daemon_id"] as? String,
                deviceName: health["device_name"] as? String,
                agents: health["agents"] as? [String],
                serverUrl: health["server_url"] as? String
            )
        } else {
            next = Status(state: transitional ?? "stopped")
        }
        if next != lastStatus {
            lastStatus = next
            onStatusChange?(next.json)
        }
        return next
    }

    private func fetchHealth() async -> [String: Any]? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(healthPort)/health")!)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let target = targetApiUrl, let server = json["server_url"] as? String,
           Self.normalize(server) != Self.normalize(target) {
            return nil
        }
        return json
    }

    func probeRuntimes() async -> [String: Any] {
        let current = await status()
        if current.state == "running" {
            return Self.runtimeProbe(current.agents ?? [], running: true)
        }
        guard let result = try? await runCLI(["daemon", "probe-runtimes", "--profile", Self.profile], timeout: 15),
              result.status == 0,
              let json = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              json["probe_result"] as? String == "success",
              let summary = json["provider_summary"] as? [String: Int]
        else { return ["probeResult": "error"] }
        return Self.runtimeProbe(summary.flatMap { Array(repeating: $0.key, count: min(max($0.value, 0), 1000)) }, running: false)
    }

    private static func runtimeProbe(_ providers: [String], running: Bool) -> [String: Any] {
        var summary: [String: Int] = [:]
        for provider in providers.map({ $0.lowercased() }) where provider.range(of: "^[a-z0-9][a-z0-9_-]{0,63}$", options: .regularExpression) != nil {
            summary[provider, default: 0] += 1
        }
        let count = summary.values.reduce(0, +)
        return [
            "probeResult": "success", "runtimeCount": count, "providerSummary": summary,
            "onlineCount": running ? count : 0, "offlineCount": running ? 0 : count,
        ]
    }

    // MARK: Lifecycle

    func setTargetApiUrl(_ url: String) {
        targetApiUrl = url
        var config = readConfig()
        if config["server_url"] as? String != url {
            config["server_url"] = url
            writeConfig(config)
        }
    }

    func start() async -> [String: Any] {
        guard isCliInstalled else { return ["success": false, "error": "CLI not bundled"] }
        guard readConfig()["token"] as? String != nil else { return ["success": false, "error": "Not signed in"] }
        if await status().state == "running" { return ["success": true] }
        transitional = "starting"
        await status()
        defer { transitional = nil }
        do {
            let result = try await runCLI(["daemon", "start", "--profile", Self.profile], timeout: 60)
            guard result.status == 0 else {
                return ["success": false, "error": result.stderr.isEmpty ? "daemon start exited \(result.status)" : result.stderr]
            }
            for _ in 0..<40 {
                if await fetchHealth() != nil { break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            transitional = nil
            let state = await status().state
            return state == "running" ? ["success": true] : ["success": false, "error": "daemon did not report healthy"]
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }

    func stop() async -> [String: Any] {
        guard isCliInstalled else { return ["success": true] }
        transitional = "stopping"
        await status()
        defer { transitional = nil }
        let result = try? await runCLI(["daemon", "stop", "--profile", Self.profile], timeout: 30)
        transitional = nil
        await status()
        if let result, result.status != 0 { return ["success": false, "error": result.stderr] }
        return ["success": true]
    }

    func restart() async -> [String: Any] {
        _ = await stop()
        return await start()
    }

    func stopForQuit() async {
        if await status().state == "running" { _ = await stop() }
    }

    func autoStart() async {
        guard prefs.autoStart else { await status(); return }
        _ = await start()
    }

    func updatePrefs(_ patch: [String: Any]) -> Prefs {
        if let value = patch["autoStart"] as? Bool { prefs.autoStart = value }
        if let value = patch["autoStop"] as? Bool { prefs.autoStop = value }
        if let data = try? JSONEncoder().encode(prefs) { UserDefaults.standard.set(data, forKey: "daemonPrefs") }
        return prefs
    }

    // MARK: Token

    /// Exchanges the session JWT for a long-lived PAT the daemon can use, once
    /// per signed-in user. The PAT lives in the CLI profile, as with Electron.
    func syncToken(jwt: String, userId: String) async throws {
        let config = readConfig()
        let storedUser = try? String(contentsOf: userIdURL, encoding: .utf8)
        if let token = config["token"] as? String, token.hasPrefix("mul_"), storedUser == userId { return }
        let pat = try await mintPat(jwt: jwt)
        var next = config
        next["token"] = pat
        if let targetApiUrl { next["server_url"] = targetApiUrl }
        writeConfig(next)
        try? userId.write(to: userIdURL, atomically: true, encoding: .utf8)
        if lastStatus?.state == "running" { _ = await restart() }
    }

    func reauthenticate(jwt: String, userId: String) async -> [String: Any] {
        do {
            var config = readConfig()
            config.removeValue(forKey: "token")
            writeConfig(config)
            try await syncToken(jwt: jwt, userId: userId)
            return ["ok": true]
        } catch let error as PatError where error.status == 401 {
            return ["ok": false, "reason": "session_invalid"]
        } catch {
            return ["ok": false, "reason": "transient", "message": error.localizedDescription]
        }
    }

    func clearToken() async {
        _ = await stop()
        var config = readConfig()
        config.removeValue(forKey: "token")
        writeConfig(config)
        try? FileManager.default.removeItem(at: userIdURL)
    }

    private struct PatError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { message }
    }

    private func mintPat(jwt: String) async throws -> String {
        guard let base = targetApiUrl, let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/tokens") else {
            throw PatError(status: 0, message: "mint PAT: target API URL not set")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": "TLS Desktop"])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw PatError(status: status, message: "mint PAT failed: \(status) \(String(decoding: data, as: UTF8.self))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String, token.hasPrefix("mul_")
        else { throw PatError(status: status, message: "mint PAT: response missing token") }
        return token
    }

    // MARK: Logs

    func startLogStream() {
        logOffset = (try? FileManager.default.attributesOfItem(atPath: logURL.path)[.size] as? UInt64) ?? 0
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.drainLog() }
        }
    }

    func stopLogStream() {
        logTimer?.invalidate()
        logTimer = nil
    }

    private func drainLog() {
        guard let handle = try? FileHandle(forReadingFrom: logURL) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < logOffset { logOffset = 0 }
        guard size > logOffset else { return }
        try? handle.seek(toOffset: logOffset)
        let data = handle.readData(ofLength: Int(min(size - logOffset, 256 * 1024)))
        logOffset += UInt64(data.count)
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).forEach { onLogLine?(String($0)) }
    }

    func openLogFile() -> [String: Any] {
        guard FileManager.default.fileExists(atPath: logURL.path) else { return ["success": false, "error": "No log file yet"] }
        NSWorkspace.shared.open(logURL)
        return ["success": true]
    }

    // MARK: Helpers

    private func readConfig() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private func writeConfig(_ config: [String: Any]) {
        do {
            try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        } catch {
            NSLog("[daemon] failed to write profile config: \(error)")
        }
    }

    private struct CLIResult { let status: Int32; let stdout: String; let stderr: String }

    private func runCLI(_ args: [String], timeout: TimeInterval) async throws -> CLIResult {
        guard let cliURL else { throw CocoaError(.fileNoSuchFile) }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = spawnPath
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = cliURL
            process.arguments = args
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { proc in
                let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: CLIResult(status: proc.terminationStatus, stdout: stdout, stderr: stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning { process.terminate() }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Apps launched from Finder get a minimal PATH; agent CLIs installed via
    /// Homebrew, npm or ~/.local would not be found without the login shell's.
    private static func loginShellPath() -> String {
        let fallback = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-ilc", "printf '__TLS_PATH__%s' \"$PATH\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return fallback.joined(separator: ":") }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return fallback.joined(separator: ":") }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard let range = text.range(of: "__TLS_PATH__") else { return fallback.joined(separator: ":") }
        let path = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var parts = path.split(separator: ":").map(String.init)
        for dir in fallback where !parts.contains(dir) { parts.append(dir) }
        return parts.joined(separator: ":")
    }

    private static func normalize(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
