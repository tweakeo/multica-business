import Foundation

/// Foto de la carpeta para preparar cambios en bloque: qué ficheros hay y el texto de los que
/// se pueden editar. Nunca escribe.
///
/// - No entra en lo oculto (salvo los ajustes de `.tls/` que importan para renombrar), ni en lo
///   excluido, ni sigue enlaces simbólicos.
/// - No descarga nada de iCloud: lo que está solo en la nube se apunta en `dataless` (se sabe que
///   existe, pero no qué dice).
/// - Solo guarda texto UTF-8 válido (lo que el escritor sabe cambiar byte a byte).
public struct VaultSnapshot: Sendable {
    public let root: URL
    public let layout: VaultLayout
    /// Todos los ficheros visibles (cualquier extensión), ordenados.
    public let files: [VaultPath]
    public let directories: [VaultPath]
    /// Ficheros o carpetas que están solo en iCloud.
    public let dataless: Set<VaultPath>
    /// Ficheros de texto que existen pero no son UTF-8 (no se pueden editar).
    public let noEditables: Set<VaultPath>
    let texts: [VaultPath: Texto]
    let lowerIndex: [String: VaultPath]

    struct Texto: Sendable {
        var data: Data
        var text: String
    }

    /// Extensiones cuyo contenido se lee.
    public static let textExtensions: Set<String> = ["md", "markdown", "csv", "canvas"]
    /// Ajustes de `.tls/` que pueden llevar rutas de la carpeta.
    public static let settingsFiles: [VaultPath] = [
        VaultPath(".tls/layout.json"), VaultPath(".tls/config.yaml"), VaultPath(".tls/plantillas.yaml"),
        VaultPath(".tls/secuencias.json"),
    ]

    /// Lee la carpeta (sin descargar nada de iCloud).
    public static func read(root: URL, layout: VaultLayout? = nil, excluded: [VaultPath] = []) -> VaultSnapshot {
        UbiquityInspector.withoutMaterializing {
            let layout = layout ?? VaultLayout.load(root: root).layout
            let rules = ExclusionRules(paths: excluded)
            var files: [VaultPath] = []
            var dirs: [VaultPath] = []
            var dataless = Set<VaultPath>()
            var noEditables = Set<VaultPath>()
            var texts: [VaultPath: Texto] = [:]
            let fm = FileManager.default
            var stack: [VaultPath] = [.root]
            while let dir = stack.popLast() {
                let url = dir.url(in: root)
                guard let names = try? fm.contentsOfDirectory(atPath: url.path) else { continue }
                for name in names {
                    if name.hasPrefix(".") { continue }
                    let path = dir.appending(name)
                    if rules.excludes(path) { continue }
                    guard let info = UbiquityInspector.info(path: url.appendingPathComponent(name).path),
                          !info.isSymlink else { continue }
                    if info.isDirectory {
                        dirs.append(path)
                        // Una carpeta solo en iCloud no se abre: listarla la descargaría.
                        if info.dataless { dataless.insert(path) } else { stack.append(path) }
                        continue
                    }
                    files.append(path)
                    if info.dataless { dataless.insert(path); continue }
                    guard textExtensions.contains(path.ext) else { continue }
                    if let t = readText(path, root: root) { texts[path] = t } else { noEditables.insert(path) }
                }
            }
            // Ajustes de `.tls/` (no son ficheros de la carpeta para enlazar, pero llevan rutas).
            for s in settingsFiles {
                let url = s.url(in: root)
                guard let info = UbiquityInspector.info(url), !info.isSymlink, !info.isDirectory, !info.dataless else { continue }
                if let t = readText(s, root: root) { texts[s] = t }
            }
            files.sort()
            dirs.sort()
            var lower: [String: VaultPath] = [:]
            for p in files + dirs { lower[TextFolding.pathKey(p.raw)] = p }
            return VaultSnapshot(root: root, layout: layout, files: files, directories: dirs, dataless: dataless,
                                 noEditables: noEditables, texts: texts, lowerIndex: lower)
        }
    }

    /// Foto de una carpeta registrada: sin lo que la persona dejó fuera (`exclusionesCopia`).
    public static func read(entry: VaultEntry, root: URL) -> VaultSnapshot {
        read(root: root, excluded: entry.exclusionesCopia.map { VaultPath($0) })
    }

    private static func readText(_ p: VaultPath, root: URL) -> Texto? {
        guard let data = try? Data(contentsOf: p.url(in: root), options: [.uncached]),
              let e = EditableText(data: data) else { return nil }
        return Texto(data: data, text: e.text)
    }

    /// Texto (sin BOM) de un fichero leído.
    public func text(_ p: VaultPath) -> String? { texts[p]?.text }

    /// Bytes exactos de un fichero leído (con BOM si lo tenía).
    public func data(_ p: VaultPath) -> Data? { texts[p]?.data }

    /// Ficheros con texto (notas y CSV), sin los ajustes de `.tls/`.
    public var textPaths: [VaultPath] {
        texts.keys.filter { !$0.raw.hasPrefix(".tls/") }.sorted()
    }

    /// Ruta real (como está en la foto) de `p`, sin distinguir mayúsculas. `nil` si no existe.
    public func existing(_ p: VaultPath) -> VaultPath? {
        lowerIndex[TextFolding.pathKey(p.raw)]
    }

    public func isDirectory(_ p: VaultPath) -> Bool {
        guard let real = existing(p) else { return false }
        return directories.contains(real)
    }

    /// Resolutor de enlaces sobre todos los ficheros de la foto.
    public var resolver: LinkResolver { LinkResolver(paths: files) }

    /// Notas Markdown (con texto leído).
    public var notes: [VaultPath] {
        textPaths.filter { $0.ext == "md" || $0.ext == "markdown" }
    }

    /// Propiedades de una nota leída.
    public func frontmatter(_ p: VaultPath) -> Frontmatter {
        guard let t = text(p) else { return .empty }
        return NoteDocument(text: t).frontmatter
    }

    /// `true` si la ruta está dentro de una carpeta de plantillas (`…/Sistemas/Plantillas/…`):
    /// esas notas no son fichas aunque lleven `tls_type`.
    public static func isTemplatePath(_ p: VaultPath) -> Bool {
        let c = p.components.map(TextFolding.nameKey)
        guard c.count >= 3 else { return false }
        for i in 0..<(c.count - 1) where c[i] == "sistemas" && c[i + 1] == "plantillas" { return true }
        return false
    }

    /// Índice `id` → ruta de las notas que lo declaran (para las relaciones `*_id` heredadas).
    public func idIndex() -> [String: VaultPath] {
        var out: [String: VaultPath] = [:]
        for p in notes where !Self.isTemplatePath(p) {
            guard let id = frontmatter(p).text("id")?.lowercased(), !id.contains("{{") else { continue }
            if out[id] == nil { out[id] = p }
        }
        return out
    }
}
