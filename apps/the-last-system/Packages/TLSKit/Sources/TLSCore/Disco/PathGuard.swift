import Darwin
import Foundation

/// Decide si una ruta de la carpeta se puede mirar (leer, listar, enlazar o pedir a iCloud).
///
/// La ruta escrita no basta: APFS no distingue mayúsculas («privado/x.md» abre «Privado/x.md») y un
/// enlace simbólico a mitad de ruta («Atajo → Privado») lleva a otro sitio. Por eso se compara con la
/// ruta real (`realpath`, que en APFS devuelve los nombres tal como están en disco):
/// - tiene que quedar dentro de la raíz real;
/// - escrita y real deben coincidir sin distinguir mayúsculas (si no, algún componente es un enlace);
/// - ni la escrita ni la real pueden estar excluidas ni tener componentes ocultos (`.tls`, `..`).
///
/// No lee contenidos ni descarga nada: `realpath` solo mira nombres. Debe llamarse con la
/// materialización de iCloud desactivada en el hilo (`UbiquityInspector.withoutMaterializing`).
struct PathGuard: Sendable {
    enum Verdict: Equatable, Sendable {
        case ok
        /// No existe (o no se puede resolver sin descargar).
        case missing
        /// Existe pero no se muestra: fuera de la carpeta, por un enlace, oculto o excluido.
        case denied
    }

    let root: URL
    /// `realpath` de la raíz, en NFC.
    let realRootPath: String
    let rules: ExclusionRules

    init(root: URL, rules: ExclusionRules) {
        self.root = root.standardizedFileURL
        self.realRootPath = Self.realPath(self.root) ?? self.root.path.precomposedStringWithCanonicalMapping
        self.rules = rules
    }

    /// Sin `..` ni componentes ocultos: nunca se sale de la carpeta ni se entra en `.tls`.
    static func isSafe(_ path: VaultPath) -> Bool {
        !path.components.contains { $0 == ".." || $0.hasPrefix(".") }
    }

    /// `true` si la ruta escrita (sin mirar el disco) está permitida.
    func allowsByName(_ path: VaultPath) -> Bool {
        Self.isSafe(path) && !rules.excludes(path)
    }

    func check(_ path: VaultPath) -> Verdict {
        guard allowsByName(path) else { return .denied }
        if path.isRoot { return .ok }
        guard let real = Self.realPath(path.url(in: root)) else { return .missing }
        guard let rel = relative(real) else { return .denied }
        guard TextFolding.pathKey(rel.raw) == TextFolding.pathKey(path.raw), allowsByName(rel) else { return .denied }
        return .ok
    }

    func exists(_ path: VaultPath) -> Bool { check(path) == .ok }

    /// Ruta relativa de una ruta real respecto a la raíz real, o `nil` si queda fuera.
    func relative(_ real: String) -> VaultPath? {
        let rootKey = TextFolding.pathKey(realRootPath)
        let key = TextFolding.pathKey(real)
        if key == rootKey { return .root }
        guard key.hasPrefix(rootKey.hasSuffix("/") ? rootKey : rootKey + "/") else { return nil }
        let rootComponents = URL(fileURLWithPath: realRootPath).standardizedFileURL.pathComponents
        let comps = URL(fileURLWithPath: real).standardizedFileURL.pathComponents
        guard comps.count > rootComponents.count else { return nil }
        return VaultPath(components: Array(comps.dropFirst(rootComponents.count)))
    }

    /// `realpath` en NFC, o `nil` si la ruta no existe.
    static func realPath(_ url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { p -> String? in
            guard let p, let r = realpath(p, nil) else { return nil }
            defer { free(r) }
            return String(cString: r).precomposedStringWithCanonicalMapping
        }
    }

    /// Ruta real aunque aún no exista: `realpath` del antepasado existente más cercano más el resto.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while true {
            if var base = realPath(existing) {
                for c in rest.reversed() { base += (base.hasSuffix("/") ? "" : "/") + c }
                return base
            }
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { return url.standardizedFileURL.path }
            rest.append(existing.lastPathComponent)
            existing = parent
        }
    }
}
