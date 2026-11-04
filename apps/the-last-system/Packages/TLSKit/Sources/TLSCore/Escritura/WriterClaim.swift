// Procedencia: el patrón de escritor único (`.tls/escritor.json` + `flock` en `locks/`) sigue la
// lógica de FORK/server/internal/biz/writer.go (autor: Manuel Trigo), portada a Swift.

import Darwin
import Foundation

/// Escritor único de una carpeta (PLAN §4.5).
///
/// - `.tls/escritor.json` (0600) dice qué instalación escribe la carpeta. Viaja con ella: otro
///   Mac que la vea solo lee. Si lleva `workspace_id`, la carpeta es del fork: solo lectura.
/// - `AppLocations.appSupport/locks/<sha8>.lock` con `flock` mientras dure el proceso: dos
///   ventanas o procesos de este Mac nunca escriben a la vez.
///
/// Se toma la primera vez que hay que escribir (abrir y leer no deja rastro en la carpeta).
public final class WriterClaim: @unchecked Sendable {
    /// Contenido de `.tls/escritor.json`.
    public struct Info: Sendable, Hashable, Codable {
        public var instalacion: String
        public var equipo: String
        public var vault_id: String
        public var empresa: String
        public var app: String
        public var desde: String
        /// Solo lo escribe el fork (Multica): si está, esta app solo lee.
        public var workspace_id: String?

        public init(instalacion: String, equipo: String, vault_id: String, empresa: String, app: String,
                    desde: String, workspace_id: String? = nil) {
            self.instalacion = instalacion; self.equipo = equipo; self.vault_id = vault_id
            self.empresa = empresa; self.app = app; self.desde = desde; self.workspace_id = workspace_id
        }
    }

    public static let file = ".tls/escritor.json"

    public let info: Info
    public let lockURL: URL
    private let lock = NSLock()
    private var fd: Int32

    private init(info: Info, lockURL: URL, fd: Int32) {
        self.info = info; self.lockURL = lockURL; self.fd = fd
    }

    deinit { release() }

    /// Suelta el cerrojo (también se suelta al cerrar el proceso).
    public func release() {
        lock.withLock {
            guard fd >= 0 else { return }
            flock(fd, LOCK_UN)
            close(fd)
            fd = -1
        }
    }

    /// Lee `.tls/escritor.json`. `nil` si no existe; lanza si existe y no se entiende.
    public static func read(root: URL) throws -> Info? {
        let url = VaultPath(file).url(in: root)
        guard let st = UbiquityInspector.info(url) else { return nil }
        guard !st.isSymlink, !st.isDirectory, !st.dataless,
              let data = UbiquityInspector.withoutMaterializing({ FileManager.default.contents(atPath: url.path) }) else {
            throw WriteError.escritorIlegible
        }
        // El del fork no trae todos los campos: se mira primero si es suyo.
        if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ws = any["workspace_id"] as? String, !ws.isEmpty {
            throw WriteError.carpetaDelFork(any["empresa"] as? String ?? "")
        }
        guard let info = try? JSONDecoder().decode(Info.self, from: data), !info.instalacion.isEmpty else {
            throw WriteError.escritorIlegible
        }
        return info
    }

    /// Cerrojo de esta carpeta: `locks/<sha8>.lock` (8 bytes del SHA-256 de su ruta real).
    public static func lockURL(root: URL, appSupport: URL) -> URL {
        let real = PathGuard.realPath(root) ?? root.standardizedFileURL.path
        let hex = ContentHash.of(Data(real.utf8)).prefix(16)
        return appSupport.appendingPathComponent("locks", isDirectory: true).appendingPathComponent("\(hex).lock")
    }

    /// Toma la carpeta para escribir: cerrojo y, si nadie la tiene, `.tls/escritor.json`.
    public static func acquire(root: URL, entry: VaultEntry, installation: UUID, appSupport: URL,
                               app: String, now: Date = Date()) throws -> WriterClaim {
        let lockURL = lockURL(root: root, appSupport: appSupport)
        try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw WriteError.otroProceso
        }
        do {
            _ = ftruncate(fd, 0)
            let note = "\(getpid()) \(root.standardizedFileURL.path)\n"
            _ = note.withCString { Darwin.write(fd, $0, strlen($0)) }
            let instalacion = installation.uuidString.lowercased()
            let vaultID = entry.id.uuidString.lowercased()
            if let current = try read(root: root) {
                guard current.instalacion == instalacion else {
                    throw WriteError.otroEscritor(equipo: current.equipo, desde: current.desde)
                }
                guard current.vault_id.lowercased() == vaultID else {
                    throw WriteError.otroEscritor(equipo: current.equipo + " · " + current.empresa, desde: current.desde)
                }
                return WriterClaim(info: current, lockURL: lockURL, fd: fd)
            }
            let info = Info(instalacion: instalacion, equipo: hostName(),
                            vault_id: vaultID, empresa: entry.nombre, app: app,
                            desde: ISO8601DateFormatter().string(from: now))
            try write(info, root: root)
            return WriterClaim(info: info, lockURL: lockURL, fd: fd)
        } catch {
            flock(fd, LOCK_UN)
            close(fd)
            throw error
        }
    }

    /// Nombre del equipo (`gethostname`, sin consultar la red).
    static func hostName() -> String {
        var buf = [CChar](repeating: 0, count: 256)
        guard gethostname(&buf, buf.count) == 0 else { return "este Mac" }
        let name = String(decoding: buf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return name.isEmpty ? "este Mac" : name
    }

    /// `.tls/escritor.json` con permisos 0600, escrito de forma atómica (nunca pisa otro).
    static func write(_ info: Info, root: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try enc.encode(info)
        data.append(0x0A)
        let url = VaultPath(file).url(in: root)
        let dir = url.deletingLastPathComponent()
        if let i = UbiquityInspector.info(dir), i.isSymlink || !i.isDirectory { throw WriteError.rutaNoPermitida(".tls") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try UbiquityInspector.withoutMaterializing {
            try AtomicFiles.create(url, with: data, display: file, mode: 0o600, afterTemporary: {})
        }
    }
}
