import Foundation

/// Duplicados «X 2.md» (los que dejan iCloud o Finder al chocar dos copias): mismo `id` que
/// «X.md» o bytes idénticos. Solo lee; cada duplicado se apunta como tarjeta.
public struct DuplicateDetector: Sendable {
    public struct Duplicate: Sendable, Hashable {
        public let original: VaultPath
        public let duplicado: VaultPath
        /// `id` común (si lo tienen).
        public let id: String?
        /// Los dos ficheros son idénticos byte a byte.
        public let identicos: Bool
    }

    public let root: URL
    public let rules: ExclusionRules
    public let layout: VaultLayout

    public init(root: URL, excluidas: [VaultPath] = [], layout: VaultLayout? = nil) {
        self.root = root.standardizedFileURL
        self.rules = ExclusionRules(paths: excluidas)
        self.layout = layout ?? VaultLayout.load(root: root).layout
    }

    /// «Nombre 2» → («Nombre», 2). Solo números del 2 al 99 tras un espacio.
    static func duplicateBase(_ stem: String) -> String? {
        guard let space = stem.lastIndex(of: " ") else { return nil }
        let suffix = stem[stem.index(after: space)...]
        guard let n = Int(suffix), (2...99).contains(n), String(n) == suffix else { return nil }
        let base = String(stem[..<space])
        return base.isEmpty ? nil : base
    }

    /// Recorre toda la carpeta (sin lo oculto, lo excluido, el Archivo ni lo que está solo en iCloud).
    public func scan() -> [Duplicate] {
        UbiquityInspector.withoutMaterializing {
            var out: [Duplicate] = []
            var stack: [VaultPath] = [.root]
            let fm = FileManager.default
            while let dir = stack.popLast() {
                guard let names = try? fm.contentsOfDirectory(atPath: dir.url(in: root).path) else { continue }
                let nfc = names.map { $0.precomposedStringWithCanonicalMapping }
                for name in nfc where !name.hasPrefix(".") {
                    let path = dir.appending(name)
                    if rules.excludes(path) || layout.isArchived(path) { continue }
                    guard let info = UbiquityInspector.info(path.url(in: root)), !info.isSymlink else { continue }
                    if info.isDirectory {
                        if !info.dataless { stack.append(path) }
                        continue
                    }
                    if let d = check(path, siblings: Set(nfc)) { out.append(d) }
                }
            }
            return out.sorted { $0.duplicado < $1.duplicado }
        }
    }

    /// Solo las rutas dadas (lo que acaba de cambiar).
    public func scan(paths: [VaultPath]) -> [Duplicate] {
        UbiquityInspector.withoutMaterializing {
            paths.compactMap { p in
                guard !p.isRoot, !p.components.contains(where: { $0.hasPrefix(".") }), !rules.excludes(p), !layout.isArchived(p),
                      let names = try? FileManager.default.contentsOfDirectory(atPath: (p.parent ?? .root).url(in: root).path) else { return nil }
                return check(p, siblings: Set(names.map { $0.precomposedStringWithCanonicalMapping }))
            }
        }
    }

    private func check(_ path: VaultPath, siblings: Set<String>) -> Duplicate? {
        guard let base = Self.duplicateBase(path.stem) else { return nil }
        let ext = path.ext.isEmpty ? "" : "." + (path.name.split(separator: ".").last.map(String.init) ?? "")
        let originalName = base + ext
        guard siblings.contains(originalName) else { return nil }
        let original = (path.parent ?? .root).appending(originalName)
        guard let a = read(original), let b = read(path) else { return nil }
        if a == b { return Duplicate(original: original, duplicado: path, id: Self.noteID(a, ext: path.ext), identicos: true) }
        guard path.ext == "md" || path.ext == "markdown",
              let idA = Self.noteID(a, ext: path.ext), let idB = Self.noteID(b, ext: path.ext), idA == idB else { return nil }
        return Duplicate(original: original, duplicado: path, id: idA, identicos: false)
    }

    private func read(_ p: VaultPath) -> Data? {
        let url = p.url(in: root)
        guard let info = UbiquityInspector.info(url), !info.isSymlink, !info.isDirectory, !info.dataless else { return nil }
        return try? Data(contentsOf: url, options: [.uncached])
    }

    static func noteID(_ data: Data, ext: String) -> String? {
        guard ext == "md" || ext == "markdown" else { return nil }
        return NoteDocument(data: data).frontmatter.text("id")
    }

    /// Apunta cada duplicado como tarjeta (sin repetir las que ya están pendientes).
    @discardableResult
    public func registrar(_ duplicates: [Duplicate], en registry: ConflictRegistry) throws -> [ConflictRecord] {
        try duplicates.map { d in
            let detalle = d.identicos
                ? "«\(d.duplicado.name)» es una copia exacta de «\(d.original.name)». Puedes apartarla al Archivo."
                : "«\(d.original.name)» y «\(d.duplicado.name)» son la misma ficha con contenidos distintos. Elige cuál se queda; la otra irá al Archivo."
            return try registry.registrar(ConflictRecord(
                tipo: .duplicado, ruta: d.original, otraRuta: d.duplicado,
                titulo: "«\(d.original.stem)» está repetida", detalle: detalle,
                versiones: [ConflictVersion(etiqueta: "La original", ubicacion: .carpeta(d.original), hash: nil),
                            ConflictVersion(etiqueta: "La repetida", ubicacion: .carpeta(d.duplicado), hash: nil)]))
        }
    }
}

// MARK: Conflictos de iCloud

/// Una versión en conflicto de un fichero de iCloud.
public struct ConflictVersionInfo: Sendable {
    public var data: Data?
    /// Nombre del Mac que la guardó.
    public var equipo: String?
    public var fecha: Date?

    public init(data: Data?, equipo: String?, fecha: Date?) {
        self.data = data; self.equipo = equipo; self.fecha = fecha
    }
}

/// De dónde salen las versiones en conflicto (en las pruebas, una falsa).
public protocol ConflictVersionProvider: Sendable {
    func unresolvedVersions(of url: URL) -> [ConflictVersionInfo]
    func markResolved(_ url: URL) throws
}

/// Las de verdad: `NSFileVersion`.
public struct SystemFileVersions: ConflictVersionProvider {
    public init() {}

    public func unresolvedVersions(of url: URL) -> [ConflictVersionInfo] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { v in
            ConflictVersionInfo(data: try? Data(contentsOf: v.url), equipo: v.localizedNameOfSavingComputer,
                                fecha: v.modificationDate)
        }
    }

    /// Las marca como resueltas (no las borra: la perdedora ya está copiada en `Archivo/Conflictos/`).
    public func markResolved(_ url: URL) throws {
        for v in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] { v.isResolved = true }
    }
}

public enum ICloudConflicts {
    /// Mira las rutas dadas y apunta una tarjeta por cada fichero con versiones en conflicto.
    /// Cada versión se copia fuera de la carpeta para poder recuperarla.
    @discardableResult
    public static func scan(_ paths: [VaultPath], root: URL, registry: ConflictRegistry,
                            provider: any ConflictVersionProvider = SystemFileVersions()) throws -> [ConflictRecord] {
        var out: [ConflictRecord] = []
        for p in paths where !p.isRoot && !p.components.contains(where: { $0.hasPrefix(".") }) {
            let url = p.url(in: root)
            let versions = provider.unresolvedVersions(of: url)
            guard !versions.isEmpty else { continue }
            if let pending = registry.pendientes().first(where: { $0.tipo == .icloud && $0.ruta == p }) {
                out.append(pending)
                continue
            }
            let id = UUID()
            var list = [ConflictVersion(etiqueta: "La de ahora", ubicacion: .carpeta(p), hash: nil)]
            for (i, v) in versions.enumerated() {
                guard let data = v.data else { continue }
                let loc = try registry.guardarVersion(data, conflicto: id, nombre: "version-\(i + 1)" + (p.ext.isEmpty ? "" : "." + p.ext))
                list.append(ConflictVersion(etiqueta: "Versión de \(v.equipo ?? "otro equipo")", ubicacion: loc,
                                            hash: ContentHash.of(data)))
            }
            out.append(try registry.registrar(ConflictRecord(
                id: id, tipo: .icloud, ruta: p,
                titulo: "«\(p.stem)» tiene dos versiones en iCloud",
                detalle: "Se guardó a la vez en dos sitios. Elige cuál se queda; la otra irá a Archivo/Conflictos.",
                versiones: list)))
        }
        return out
    }
}
