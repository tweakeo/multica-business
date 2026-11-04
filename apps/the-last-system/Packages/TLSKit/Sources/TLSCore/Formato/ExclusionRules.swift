import Darwin
import Foundation

/// Qué no se lista ni se recorre (lo excluido y lo privado).
///
/// Se compara en NFC y sin distinguir mayúsculas, como APFS: «privado/x.md» es la misma ruta que
/// «Privado/x.md». Ante la duda, se excluye de más. Vive en TLSCore para que la copia, el índice y
/// la lectura usen exactamente la misma regla.
public struct ExclusionRules: Sendable, Hashable {
    /// Rutas desde la raíz: se poda la ruta y todo lo que cuelga de ella.
    public private(set) var paths: [VaultPath] = []
    /// Nombres que se omiten a cualquier profundidad (`.DS_Store`).
    public private(set) var names: Set<String> = []
    /// Patrones `fnmatch` sobre la ruta relativa (`*`, `?`, `[…]`). Solo para reglas escritas en el código.
    public private(set) var patterns: [String] = []

    private var pathKeys: [String] = []
    private var nameKeys: Set<String> = []
    private var patternKeys: [String] = []

    public init(paths: [VaultPath] = [], names: Set<String> = [], patterns: [String] = []) {
        for p in paths { add(p) }
        for n in names { addName(n) }
        for p in patterns { addPattern(p) }
    }

    public var isEmpty: Bool { pathKeys.isEmpty && nameKeys.isEmpty && patternKeys.isEmpty }

    /// Añade una ruta desde la raíz, tal cual (sin comodines). La raíz misma se ignora (excluiría todo).
    public mutating func add(_ path: VaultPath) {
        guard !path.isRoot else { return }
        let k = TextFolding.pathKey(path.raw)
        guard !pathKeys.contains(k) else { return }
        paths.append(path); pathKeys.append(k)
    }

    public mutating func addName(_ name: String) {
        let k = TextFolding.pathKey(name)
        guard !k.isEmpty, !nameKeys.contains(k) else { return }
        names.insert(name); nameKeys.insert(k)
    }

    public mutating func addPattern(_ pattern: String) {
        let k = TextFolding.pathKey(VaultPath(pattern).raw)
        guard !k.isEmpty, !patternKeys.contains(k) else { return }
        patterns.append(pattern); patternKeys.append(k)
    }

    /// Añade una regla escrita en el código (`CopyOptions.siempre`): con comodines es patrón;
    /// sin «/» y empezando por «.», nombre a cualquier profundidad; si no, ruta desde la raíz.
    /// Lo que escribe la persona o declara la carpeta (`privado`) va con `add(_:)`: es una ruta literal.
    public mutating func addEntry(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if t.contains(where: { "*?[".contains($0) }) {
            addPattern(t)
        } else if !t.contains("/"), t.hasPrefix(".") {
            addName(t)
        } else {
            add(VaultPath(t))
        }
    }

    /// `true` si la ruta o alguna carpeta que la contiene está excluida.
    public func excludes(_ path: VaultPath) -> Bool {
        guard !path.isRoot else { return false }
        let k = TextFolding.pathKey(path.raw)
        for p in pathKeys where k == p || k.hasPrefix(p + "/") { return true }
        if nameKeys.isEmpty && patternKeys.isEmpty { return false }
        let comps = k.split(separator: "/").map(String.init)
        if comps.contains(where: nameKeys.contains) { return true }
        if !patternKeys.isEmpty {
            // Sin «/», el patrón se aplica a cada nombre (`*.env`); con «/», a cada ruta parcial.
            var prefix = ""
            for c in comps {
                prefix = prefix.isEmpty ? c : prefix + "/" + c
                for p in patternKeys where Self.fnmatches(p, p.contains("/") ? prefix : c) { return true }
            }
        }
        return false
    }

    /// Huella estable (sin distinguir mayúsculas) para saber si el conjunto cambió.
    public var fingerprint: String {
        (pathKeys.sorted() + nameKeys.sorted().map { "name:" + $0 } + patternKeys.sorted().map { "pattern:" + $0 })
            .joined(separator: ",")
    }

    static func fnmatches(_ pattern: String, _ path: String) -> Bool {
        fnmatch(pattern, path, FNM_PATHNAME) == 0
    }
}
