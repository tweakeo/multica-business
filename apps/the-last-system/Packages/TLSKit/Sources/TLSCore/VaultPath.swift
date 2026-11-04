import Foundation

/// Ruta relativa dentro de la carpeta de una empresa.
///
/// Siempre en NFC (las tildes en NFD rompen las comparaciones con iCloud),
/// separada por `/`, sin barra inicial ni final. La raíz es la ruta vacía.
public struct VaultPath: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let raw: String

    public init(_ string: String) {
        let nfc = string.precomposedStringWithCanonicalMapping
        let parts = nfc.split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
        self.raw = parts.joined(separator: "/")
    }

    public init(components: [String]) {
        self.init(components.joined(separator: "/"))
    }

    public static let root = VaultPath("")

    public var isRoot: Bool { raw.isEmpty }

    public var components: [String] {
        raw.isEmpty ? [] : raw.split(separator: "/").map(String.init)
    }

    /// Último componente, con extensión.
    public var name: String { components.last ?? "" }

    /// Último componente sin extensión.
    public var stem: String {
        let n = name
        guard let dot = n.lastIndex(of: "."), dot != n.startIndex else { return n }
        return String(n[..<dot])
    }

    /// Extensión en minúsculas, sin punto. Vacía si no hay.
    public var ext: String {
        let n = name
        guard let dot = n.lastIndex(of: "."), dot != n.startIndex else { return "" }
        return String(n[n.index(after: dot)...]).lowercased()
    }

    public var parent: VaultPath? {
        guard !isRoot else { return nil }
        return VaultPath(components: Array(components.dropLast()))
    }

    public func appending(_ component: String) -> VaultPath {
        isRoot ? VaultPath(component) : VaultPath(raw + "/" + component)
    }

    /// `true` si es igual a `other` o cuelga de ella.
    public func isDescendant(of other: VaultPath) -> Bool {
        if other.isRoot { return true }
        return raw == other.raw || raw.hasPrefix(other.raw + "/")
    }

    public func url(in root: URL) -> URL {
        components.reduce(root) { $0.appendingPathComponent($1, isDirectory: false) }
    }

    /// Ruta relativa de `url` respecto a `root`, o `nil` si está fuera.
    public init?(url: URL, root: URL) {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().path
        let full = url.standardizedFileURL.resolvingSymlinksInPath().path
        let b = base.precomposedStringWithCanonicalMapping
        let f = full.precomposedStringWithCanonicalMapping
        if f == b { self = .root; return }
        guard f.hasPrefix(b + "/") else { return nil }
        self.init(String(f.dropFirst(b.count + 1)))
    }

    /// Resuelve un destino relativo (`../Empresas/x.md`, con `%20`) desde la carpeta de esta ruta.
    public func resolvingRelative(_ target: String) -> VaultPath? {
        let decoded = target.removingPercentEncoding ?? target
        var stack = parent?.components ?? []
        for part in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..":
                guard !stack.isEmpty else { return nil }
                stack.removeLast()
            default: stack.append(String(part))
            }
        }
        return VaultPath(components: stack)
    }

    public var description: String { raw }

    public static func < (lhs: VaultPath, rhs: VaultPath) -> Bool {
        lhs.raw.localizedStandardCompare(rhs.raw) == .orderedAscending
    }

    public init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(raw)
    }
}
