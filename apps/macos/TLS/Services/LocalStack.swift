import Foundation

/// Embedded mode: everything TLS needs runs inside the app, so the .app works
/// on a Mac without Node, Go, Homebrew or Docker.
///
///   PostgreSQL (bundled, Unix socket only, inside Application Support)
///   → migrations → API server bound to 127.0.0.1 → automatic local login.
///
/// Secrets (JWT key, local login code) live in a 0600 file the agent sandbox
/// denies; only its path reaches the server process. On first launch the
/// bundled demo company is restored (database snapshot + company folder).
@MainActor
final class LocalStack {
    static let shared = LocalStack()

    nonisolated static let apiPort = 18080
    nonisolated static let localUserEmail = "demo@tls.local"
    nonisolated static var apiURL: String { "http://127.0.0.1:\(apiPort)" }

    private var serverProcess: Process?
    private(set) var running = false

    // MARK: Paths

    private var runtimeDir: URL { AppPaths.support.appendingPathComponent("runtime", isDirectory: true) }
    private var clusterDir: URL { runtimeDir.appendingPathComponent("pgdata", isDirectory: true) }
    private var dataDir: URL { clusterDir.appendingPathComponent("data", isDirectory: true) }
    private var socketDir: URL { runtimeDir.appendingPathComponent("pg", isDirectory: true) }
    private var uploadsDir: URL { runtimeDir.appendingPathComponent("uploads", isDirectory: true) }
    private var secretsURL: URL { runtimeDir.appendingPathComponent("secrets.env") }
    static var logsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/TLS", isDirectory: true)
    }

    private var resources: URL { Bundle.main.resourceURL! }
    private func pgBin(_ name: String) -> URL { resources.appendingPathComponent("postgres/bin/\(name)") }
    private func bin(_ name: String) -> URL { resources.appendingPathComponent("bin/\(name)") }

    private var databaseURL: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "/&=+ ")
        let host = socketDir.path.addingPercentEncoding(withAllowedCharacters: allowed) ?? socketDir.path
        return "postgres://multica@/multica?host=\(host)&sslmode=disable"
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Lifecycle

    /// Starts the stack and returns a session token for the local user.
    func start(progress: @escaping (String) -> Void) async throws -> String? {
        let fm = FileManager.default
        for dir in [runtimeDir, socketDir, uploadsDir, Self.logsDir] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let secrets = try ensureSecrets()

        if !fm.fileExists(atPath: dataDir.appendingPathComponent("PG_VERSION").path) {
            progress("Preparando la base de datos (primer arranque)…")
            try await prepareCluster()
        }
        try await restoreDemoFolderIfNeeded()

        progress("Arrancando la base de datos…")
        try await startPostgres()

        progress("Aplicando migraciones…")
        let migrate = try await run(bin("multica-migrate"), ["up"], env: serverEnv(), log: "migrate.log", timeout: 300)
        guard migrate.status == 0 else { throw Failure(message: "Las migraciones fallaron. Revisa \(Self.logsDir.path)/migrate.log") }

        progress("Arrancando el servidor de TLS…")
        try await startServer()
        running = true

        progress("Iniciando sesión…")
        return await login(code: secrets["MULTICA_DEV_VERIFICATION_CODE"] ?? "")
    }

    /// Stops the server and PostgreSQL. Called on quit.
    func stop() {
        if let p = serverProcess, p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(5)
            while p.isRunning && Date() < deadline { usleep(50_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        serverProcess = nil
        let stop = Process()
        stop.executableURL = pgBin("pg_ctl")
        stop.arguments = ["-D", dataDir.path, "stop", "-m", "fast", "-w"]
        stop.standardOutput = FileHandle.nullDevice
        stop.standardError = FileHandle.nullDevice
        try? stop.run()
        stop.waitUntilExit()
        running = false
    }

    // MARK: Steps

    private func ensureSecrets() throws -> [String: String] {
        if let text = try? String(contentsOf: secretsURL, encoding: .utf8) {
            var out: [String: String] = [:]
            for line in text.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { out[parts[0]] = parts[1] }
            }
            if out["JWT_SECRET"] != nil, out["MULTICA_DEV_VERIFICATION_CODE"] != nil { return out }
        }
        func random(_ bytes: Int) -> String {
            var data = Data(count: bytes)
            _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
            return data.map { String(format: "%02x", $0) }.joined()
        }
        let code = String(format: "%06d", Int.random(in: 0..<1_000_000))
        let secrets = ["JWT_SECRET": random(32), "MULTICA_DEV_VERIFICATION_CODE": code]
        let body = secrets.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n") + "\n"
        try body.write(to: secretsURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretsURL.path)
        return secrets
    }

    private func prepareCluster() async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: clusterDir)
        try fm.createDirectory(at: clusterDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let snapshot = resources.appendingPathComponent("demo/pgdata.tar.gz")
        if fm.fileExists(atPath: snapshot.path) {
            let r = try await run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", snapshot.path, "-C", clusterDir.path], log: "setup.log", timeout: 300)
            guard r.status == 0 else { throw Failure(message: "No se pudo restaurar la demo (setup.log)") }
        } else {
            let r = try await run(pgBin("initdb"), ["-D", dataDir.path, "-U", "multica", "-A", "trust", "-E", "UTF8", "--locale=C"], log: "setup.log", timeout: 300)
            guard r.status == 0 else { throw Failure(message: "initdb falló (setup.log)") }
            // Single-user mode creates the database without any client tool.
            let single = Process()
            single.executableURL = pgBin("postgres")
            single.arguments = ["--single", "-D", dataDir.path, "postgres"]
            let input = Pipe()
            single.standardInput = input
            single.standardOutput = FileHandle.nullDevice
            single.standardError = FileHandle.nullDevice
            try single.run()
            input.fileHandleForWriting.write(Data("CREATE DATABASE multica;\n".utf8))
            try input.fileHandleForWriting.close()
            single.waitUntilExit()
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataDir.path)
    }

    private func restoreDemoFolderIfNeeded() async throws {
        let archive = resources.appendingPathComponent("demo/folder.tar.gz")
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("TLS Empresas", isDirectory: true)
        let target = base.appendingPathComponent("DEMO - Asesoría Ribera", isDirectory: true)
        guard FileManager.default.fileExists(atPath: archive.path), !FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        _ = try await run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", archive.path, "-C", base.path], log: "setup.log", timeout: 120)
    }

    private func startPostgres() async throws {
        let status = try await run(pgBin("pg_ctl"), ["-D", dataDir.path, "status"], log: nil, timeout: 10)
        if status.status == 0 { return }
        let options = "-c listen_addresses='' -k \"\(socketDir.path)\" -c unix_socket_permissions=0700"
        let r = try await run(pgBin("pg_ctl"), ["-D", dataDir.path, "-o", options, "-l", Self.logsDir.appendingPathComponent("postgres.log").path, "-w", "-t", "60", "start"], log: "setup.log", timeout: 90)
        guard r.status == 0 else { throw Failure(message: "PostgreSQL no arrancó. Revisa \(Self.logsDir.path)/postgres.log") }
    }

    private func serverEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let secretKeys = ["JWT_SECRET", "MULTICA_DEV_VERIFICATION_CODE"]
        secretKeys.forEach { env.removeValue(forKey: $0) }
        let values: [String: String] = [
            "DATABASE_URL": databaseURL,
            "MULTICA_SECRETS_FILE": secretsURL.path,
            "APP_ENV": "development",
            "PORT": "\(Self.apiPort)",
            "BIND_HOST": "127.0.0.1",
            "CORS_ALLOWED_ORIGINS": AppSchemeHandler.origin,
            "MULTICA_PUBLIC_URL": Self.apiURL,
            "MULTICA_APP_URL": Self.apiURL,
            "LOCAL_UPLOAD_DIR": uploadsDir.path,
            "LOCAL_UPLOAD_BASE_URL": Self.apiURL,
            "FF_PROJECT_WORKFLOWS_V1": "true",
            "TLS_REBIND_AGENTS": "1",
            "DO_NOT_TRACK": "1",
        ]
        values.forEach { env[$0.key] = $0.value }
        return env
    }

    private func startServer() async throws {
        if await healthy() { return }
        let p = Process()
        p.executableURL = bin("multica-server")
        p.environment = serverEnv()
        p.currentDirectoryURL = runtimeDir
        let logURL = Self.logsDir.appendingPathComponent("server.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        p.standardOutput = log
        p.standardError = log
        try p.run()
        serverProcess = p
        for _ in 0..<120 {
            if await healthy() { return }
            if !p.isRunning { break }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw Failure(message: "El servidor de TLS no respondió. ¿Está ocupado el puerto \(Self.apiPort)? Revisa \(logURL.path)")
    }

    private func healthy() async -> Bool {
        var request = URLRequest(url: URL(string: "\(Self.apiURL)/health")!)
        request.timeoutInterval = 1
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Local single-user login with the per-install code. The server only
    /// listens on 127.0.0.1 and the code never leaves the secrets file.
    private func login(code: String) async -> String? {
        func post(_ path: String, _ body: [String: String]) async -> [String: Any]? {
            var request = URLRequest(url: URL(string: "\(Self.apiURL)\(path)")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        _ = await post("/auth/send-code", ["email": Self.localUserEmail])
        let res = await post("/auth/verify-code", ["email": Self.localUserEmail, "code": code])
        return res?["token"] as? String
    }

    // MARK: Process helper

    private struct RunResult { let status: Int32 }

    private func run(_ exe: URL, _ args: [String], env: [String: String]? = nil, log: String?, timeout: TimeInterval) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            let p = Process()
            p.executableURL = exe
            p.arguments = args
            if let env { p.environment = env }
            if let log {
                let url = Self.logsDir.appendingPathComponent(log)
                if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
                if let h = try? FileHandle(forWritingTo: url) {
                    h.seekToEndOfFile()
                    p.standardOutput = h
                    p.standardError = h
                }
            } else {
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
            }
            p.terminationHandler = { proc in continuation.resume(returning: RunResult(status: proc.terminationStatus)) }
            do {
                try p.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if p.isRunning { p.terminate() } }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
