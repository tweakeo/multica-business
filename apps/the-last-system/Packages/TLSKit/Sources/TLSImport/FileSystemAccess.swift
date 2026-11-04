import CryptoKit
import Darwin
import Foundation

/// Acceso al disco, sustituible en tests para demostrar qué rutas se listaron.
///
/// Ninguna operación sigue enlaces simbólicos: `isDirectory`, `isDataless`, `fileSize`
/// y `fileExists` miran la entrada misma (`lstat`).
public protocol FileSystemAccess: Sendable {
    func contentsOfDirectory(at url: URL) throws -> [URL]
    func isDirectory(_ url: URL) -> Bool
    func isDataless(_ url: URL) -> Bool
    func fileSize(_ url: URL) -> Int64?
    func sha256(of url: URL) throws -> String
    func copyItem(at src: URL, to dst: URL) throws
    func createDirectory(at url: URL) throws
    func write(_ data: Data, to url: URL) throws
    func fileExists(_ url: URL) -> Bool

    // Ampliación F0 (con implementación por defecto, no rompe a quien ya conforma).

    /// `true` si la entrada es un enlace simbólico. Los enlaces no se siguen ni se copian.
    func isSymbolicLink(_ url: URL) -> Bool
    /// Lee un fichero pequeño (`.tls/layout.json`, `.tls/config.yaml`).
    func contents(of url: URL) throws -> Data
    func modificationDate(_ url: URL) -> Date?
    func setModificationDate(_ date: Date, for url: URL) throws
    /// Manda a la Papelera una copia a medias (cancelada o con la verificación fallida). Recuperable.
    func trashItem(_ url: URL) throws
}

public extension FileSystemAccess {
    func isSymbolicLink(_ url: URL) -> Bool { false }
    func contents(of url: URL) throws -> Data { try Data(contentsOf: url) }
    func modificationDate(_ url: URL) -> Date? { nil }
    func setModificationDate(_ date: Date, for url: URL) throws {}
    func trashItem(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

/// Disco real. Pensado para usarse desde un hilo con la protección de iCloud activa
/// (`DatalessGuard`): así, tocar por error un fichero que solo está en iCloud da error y no lo descarga.
public struct LocalFileSystem: FileSystemAccess {
    public init() {}

    /// `SF_DATALESS` de `<sys/stat.h>`: el contenido solo está en iCloud.
    static let datalessFlag: UInt32 = 0x4000_0000
    /// Bloques de lectura para el SHA-256.
    static let hashChunk = 1 << 20

    /// Hijos inmediatos con el nombre tal como está en disco (`readdir`, sin pedir atributos).
    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        let dir: UnsafeMutablePointer<DIR>? = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return nil }
            return opendir(path)
        }
        guard let dir else { throw Self.posixError(errno, url) }
        defer { closedir(dir) }
        var urls: [URL] = []
        while true {
            errno = 0
            guard let entry = readdir(dir) else {
                if errno != 0 { throw Self.posixError(errno, url) }
                break
            }
            var nameBuffer = entry.pointee.d_name
            let name = withUnsafeBytes(of: &nameBuffer) { raw -> String in
                let bytes = raw.prefix(Int(entry.pointee.d_namlen))
                return String(decoding: bytes, as: UTF8.self)
            }
            if name == "." || name == ".." { continue }
            let isDir = entry.pointee.d_type == UInt8(DT_DIR)
            urls.append(url.appendingPathComponent(name, isDirectory: isDir))
        }
        return urls
    }

    public func isDirectory(_ url: URL) -> Bool {
        guard let st = Self.lstatInfo(url) else { return false }
        return (st.st_mode & S_IFMT) == S_IFDIR
    }

    public func isSymbolicLink(_ url: URL) -> Bool {
        guard let st = Self.lstatInfo(url) else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    public func isDataless(_ url: URL) -> Bool {
        guard let st = Self.lstatInfo(url) else { return false }
        return (st.st_flags & Self.datalessFlag) != 0
    }

    public func fileSize(_ url: URL) -> Int64? {
        Self.lstatInfo(url).map { Int64($0.st_size) }
    }

    /// SHA-256 en hexadecimal, leyendo por bloques de 1 MB. No sigue enlaces.
    public func sha256(of url: URL) throws -> String {
        let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else { throw Self.posixError(errno, url) }
        defer { close(fd) }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: Self.hashChunk)
        while true {
            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, Self.hashChunk) }
            if n < 0 {
                if errno == EINTR { continue }
                throw Self.posixError(errno, url)
            }
            if n == 0 { break }
            buffer.withUnsafeBytes { hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
        }
        return Self.hex(hasher.finalize())
    }

    /// Copia un fichero (en APFS, un clon). Nunca sobrescribe, nunca copia carpetas enteras ni enlaces.
    public func copyItem(at src: URL, to dst: URL) throws {
        guard let st = Self.lstatInfo(src), (st.st_mode & S_IFMT) == S_IFREG else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: src.path])
        }
        try FileManager.default.copyItem(at: src, to: dst)
        // copyfile conserva la fecha; si el volumen no lo hace, se fija a mano.
        if let original = modificationDate(src), modificationDate(dst) != original {
            try setModificationDate(original, for: dst)
        }
    }

    /// Crea la carpeta (y las intermedias). Falla si ya existe: así nunca se reutiliza un destino.
    public func createDirectory(at url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if Self.lstatInfo(parent) == nil {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        let r = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return mkdir(path, 0o755)
        }
        if r != 0 { throw Self.posixError(errno, url) }
    }

    /// Escribe un fichero nuevo. Falla si ya existe.
    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.withoutOverwriting])
    }

    public func fileExists(_ url: URL) -> Bool {
        Self.lstatInfo(url) != nil
    }

    public func contents(of url: URL) throws -> Data {
        guard !isSymbolicLink(url) else {
            throw CocoaError(.fileReadUnsupportedScheme, userInfo: [NSFilePathErrorKey: url.path])
        }
        return try Data(contentsOf: url)
    }

    public func modificationDate(_ url: URL) -> Date? {
        guard let st = Self.lstatInfo(url) else { return nil }
        let t = st.st_mtimespec
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1_000_000_000)
    }

    public func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    // MARK: - Utilidades

    static func lstatInfo(_ url: URL) -> stat? {
        var st = stat()
        let r = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &st)
        }
        return r == 0 ? st : nil
    }

    static func posixError(_ code: Int32, _ url: URL) -> Error {
        let posix = POSIXErrorCode(rawValue: code) ?? .EIO
        return NSError(domain: NSPOSIXErrorDomain, code: Int(posix.rawValue),
                       userInfo: [NSFilePathErrorKey: url.path])
    }

    static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var out = [UInt8]()
        out.reserveCapacity(64)
        for b in digest {
            out.append(digits[Int(b >> 4)])
            out.append(digits[Int(b & 0x0f)])
        }
        return String(decoding: out, as: UTF8.self)
    }
}
