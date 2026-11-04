import Foundation

/// Escrituras recientes de la app (ruta y huella), para que la vigilancia no tome por
/// externos los cambios que acaba de hacer la propia app.
///
/// Una ruta cuenta como propia si lo que hay ahora en disco es lo que dejó la app (misma
/// huella, o ausente si la app la movió) y no han pasado más de `ttl` segundos.
public final class RecentWrites: @unchecked Sendable {
    private struct Mark { var hash: String?; var at: Date }

    private let lock = NSLock()
    private var marks: [String: Mark] = [:]
    public let ttl: TimeInterval

    public init(ttl: TimeInterval = 120) {
        self.ttl = ttl
    }

    /// Apunta que la app deja `path` con esa huella (`nil` = ya no está: se movió).
    public func register(_ path: VaultPath, hash: String?, now: Date = Date()) {
        lock.withLock {
            marks[TextFolding.pathKey(path.raw)] = Mark(hash: hash, at: now)
            if marks.count > 4096 { purge(now) }
        }
    }

    private func purge(_ now: Date) {
        marks = marks.filter { now.timeIntervalSince($0.value.at) <= ttl }
    }

    /// `true` si lo que hay ahora en `path` es lo que escribió la app hace poco.
    public func isOwn(_ path: VaultPath, root: URL, now: Date = Date()) -> Bool {
        guard let mark = lock.withLock({ marks[TextFolding.pathKey(path.raw)] }),
              now.timeIntervalSince(mark.at) <= ttl else { return false }
        return UbiquityInspector.withoutMaterializing {
            let url = path.url(in: root)
            guard let info = UbiquityInspector.info(url) else { return mark.hash == nil }
            if info.isDirectory { return mark.hash == "carpeta" }
            guard let hash = mark.hash, !info.dataless, !info.isSymlink,
                  let data = try? Data(contentsOf: url, options: [.uncached]) else { return false }
            return ContentHash.of(data) == hash
        }
    }

    /// Quita de una lista de cambios vistos por la vigilancia los que hizo la propia app.
    /// Una lista vacía («revisar todo») se devuelve tal cual.
    public func filterExternal(_ paths: [VaultPath], root: URL, now: Date = Date()) -> [VaultPath] {
        paths.filter { !isOwn($0, root: root, now: now) }
    }
}
