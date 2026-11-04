import Foundation

/// Resuelve enlaces a rutas de la carpeta: primero por ruta, luego por nombre (NFC, sin distinguir
/// mayúsculas). Si el nombre se repite, decide como Obsidian (ver `byName`), para que la app y Obsidian
/// lleven cada enlace al mismo sitio.
public struct LinkResolver: Sendable {
    let paths: Set<VaultPath>
    /// Ruta en minúsculas → ruta real.
    let lowerPaths: [String: VaultPath]
    /// Nombre (con extensión y, en Markdown, también sin ella) → rutas.
    let names: [String: [VaultPath]]
    let existsOnDisk: @Sendable (VaultPath) -> Bool

    public init(paths: some Sequence<VaultPath>, existsOnDisk: @escaping @Sendable (VaultPath) -> Bool = { _ in false }) {
        var set = Set<VaultPath>()
        var lower: [String: VaultPath] = [:]
        var names: [String: [VaultPath]] = [:]
        for p in paths {
            set.insert(p)
            lower[TextFolding.nameKey(p.raw)] = p
            names[TextFolding.nameKey(p.name), default: []].append(p)
            if p.ext == "md" || p.ext == "markdown" {
                names[TextFolding.nameKey(p.stem), default: []].append(p)
            }
        }
        self.paths = set; self.lowerPaths = lower; self.names = names; self.existsOnDisk = existsOnDisk
    }

    public static let empty = LinkResolver(paths: [])

    /// `target`: destino Markdown (`../Empresa.md`, `Sistemas/A%20B.md`, `<A B.md>`) o wikilink (`[[Nota|alias]]`).
    public func resolve(_ target: String, from: VaultPath) -> VaultPath? {
        let t = target.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("[[") || t.hasPrefix("![[") {
            guard let link = LinkParser.links(in: t).first, link.style == .wiki else { return nil }
            return resolveWiki(link.target, from: from)
        }
        var dest = t
        if dest.hasPrefix("<"), dest.hasSuffix(">") { dest = String(dest.dropFirst().dropLast()) }
        if LinkParser.isExternal(dest) { return nil }
        if let hash = dest.firstIndex(of: "#") { dest = String(dest[..<hash]) }
        guard !dest.isEmpty else { return nil }
        return resolveMarkdown(dest, from: from)
    }

    func resolveMarkdown(_ dest: String, from: VaultPath) -> VaultPath? {
        let decoded = dest.removingPercentEncoding ?? dest
        if decoded.hasPrefix("/") {
            if let p = existing(VaultPath(decoded)) { return p }
        } else if let rel = from.resolvingRelative(dest) {
            if let p = existing(rel) { return p }
            if rel.ext.isEmpty, let p = existing(VaultPath(rel.raw + ".md")) { return p }
        }
        return byName(VaultPath(decoded).name, suffix: decoded, from: from)
    }

    func resolveWiki(_ note: String, from: VaultPath) -> VaultPath? {
        let n = note.precomposedStringWithCanonicalMapping
        guard !n.isEmpty else { return nil }
        let candidates = VaultPath(n).ext.isEmpty ? [n + ".md", n] : [n, n + ".md"]
        for c in candidates {
            // Ruta desde la raíz (como Obsidian, también `[[Nota]]`: gana `Nota.md` de la raíz).
            if let p = existing(VaultPath(c)) { return p }
            // Junto a la nota que enlaza.
            if let p = existing(VaultPath(components: (from.parent?.components ?? []) + [c])) { return p }
        }
        let name = VaultPath(n).name
        return byName(name, suffix: n, from: from, exigirRuta: true)
            ?? (VaultPath(n).ext.isEmpty ? nil : byName(name + ".md", suffix: n, from: from, exigirRuta: true))
    }

    func existing(_ p: VaultPath) -> VaultPath? {
        if p.isRoot || p.components.contains("..") { return nil }
        if paths.contains(p) { return p }
        if let real = lowerPaths[TextFolding.nameKey(p.raw)] { return real }
        return existsOnDisk(p) ? p : nil
    }

    /// Por nombre, con la regla de Obsidian (`MetadataCache.getLinkpathDest`, 1.7): si es único, ese; si se
    /// escribió una ruta, solo los que terminan en ella (en un wikilink es obligatorio: si no hay ninguno, el
    /// enlace está roto); después, primero los que cuelgan de la carpeta de la nota que enlaza y, en cada grupo,
    /// el de ruta más corta. Si los dos primeros empatan, Obsidian depende del orden de carga: ambiguo (`nil`).
    func byName(_ name: String, suffix: String, from: VaultPath, exigirRuta: Bool = false) -> VaultPath? {
        guard var found = names[TextFolding.nameKey(name)], !found.isEmpty else { return nil }
        found = Array(Set(found)).sorted()
        let sfx = TextFolding.nameKey(suffix)
        if sfx.contains("/") {
            let matching = found.filter {
                let k = TextFolding.nameKey($0.raw)
                return k.hasSuffix(sfx) || k.hasSuffix(sfx + ".md")
            }
            if exigirRuta || !matching.isEmpty { found = matching }
        }
        if found.count <= 1 { return found.first }
        let dir = TextFolding.nameKey(from.parent?.raw ?? "")
        func rank(_ p: VaultPath) -> (Int, Int) {
            (TextFolding.nameKey(p.raw).hasPrefix(dir) ? 0 : 1, p.raw.utf16.count)
        }
        let sorted = found.sorted { rank($0) < rank($1) }
        return rank(sorted[0]) == rank(sorted[1]) ? nil : sorted[0]
    }
}
