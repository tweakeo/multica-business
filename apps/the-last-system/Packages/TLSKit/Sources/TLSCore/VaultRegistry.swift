import Foundation

/// Registro de carpetas de esta instalación (`vaults.json` en AppLocations.appSupport).
///
/// Escritura atómica: fichero temporal en `itemReplacementDirectory` + `replaceItemAt`.
/// Si `vaults.json` está dañado se aparta (`vaults.json.dañado-<fecha>`) y se empieza de cero.
public final class VaultRegistry: Sendable {
    public init(directory: URL = AppLocations.appSupport) {
        self.directory = directory
    }

    public let directory: URL
    private let lock = NSLock()

    static let fileName = "vaults.json"
    static let installationFile = "instalacion.json"

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    /// Carpetas registradas, las más recientes primero.
    public func load() -> [VaultEntry] {
        lock.withLock { (try? readEntries()) ?? [] }
            .sorted { $0.creada > $1.creada }
    }

    /// Inserta o sustituye por `id`.
    public func upsert(_ entry: VaultEntry) throws {
        try lock.withLock {
            var entries = try readEntriesOrQuarantine()
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[i] = entry
            } else {
                entries.append(entry)
            }
            try write(entries)
        }
    }

    public func remove(id: UUID) throws {
        try lock.withLock {
            var entries = try readEntriesOrQuarantine()
            entries.removeAll { $0.id == id }
            try write(entries)
        }
    }

    /// Crea un bookmark para guardar en `VaultEntry.bookmark` (app sin sandbox: bookmark normal).
    public static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resuelve la carpeta de una entrada (bookmark primero, ruta después). `nil` si no existe.
    /// Si el bookmark estaba caducado o la carpeta se movió, actualiza la entrada.
    public func resolveURL(_ entry: VaultEntry) -> URL? {
        if let data = entry.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting],
                                  relativeTo: nil, bookmarkDataIsStale: &stale),
               Self.isDirectory(url) {
                if stale || url.path != entry.ruta {
                    var updated = entry
                    updated.ruta = url.path
                    if stale, let fresh = try? Self.makeBookmark(for: url) { updated.bookmark = fresh }
                    try? upsert(updated)
                }
                return url
            }
        }
        let url = URL(fileURLWithPath: entry.ruta, isDirectory: true)
        return Self.isDirectory(url) ? url : nil
    }

    /// Identidad de esta instalación (`instalacion.json`); se crea la primera vez.
    public func installationID() -> UUID {
        lock.withLock {
            let url = directory.appendingPathComponent(Self.installationFile)
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let s = obj["id"] as? String, let id = UUID(uuidString: s) {
                return id
            }
            let id = UUID()
            let obj: [String: Any] = ["id": id.uuidString.lowercased(),
                                      "creada": ISO8601DateFormatter().string(from: Date())]
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                try? Self.atomicWrite(data, to: url)
            }
            return id
        }
    }

    // MARK: Fichero

    struct File: Codable {
        var version: Int
        var vaults: [VaultEntry]
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Lee las entradas; `[]` si no hay fichero. Lanza si está dañado.
    func readEntries() throws -> [VaultEntry] {
        guard let data = FileManager.default.contents(atPath: fileURL.path) else { return [] }
        if let f = try? Self.decoder.decode(File.self, from: data) { return f.vaults }
        return try Self.decoder.decode([VaultEntry].self, from: data)
    }

    private func readEntriesOrQuarantine() throws -> [VaultEntry] {
        do {
            return try readEntries()
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = directory.appendingPathComponent("\(Self.fileName).dañado-\(stamp)")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return []
        }
    }

    private func write(_ entries: [VaultEntry]) throws {
        let data = try Self.encoder.encode(File(version: 1, vaults: entries))
        try Self.atomicWrite(data, to: fileURL)
    }

    /// Temporal + `fsync` + `replaceItemAt` (o `moveItem` si aún no existe).
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmpDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fm.removeItem(at: tmpDir) }
        let tmp = tmpDir.appendingPathComponent(url.lastPathComponent)
        guard fm.createFile(atPath: tmp.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        let handle = try FileHandle(forWritingTo: tmp)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
