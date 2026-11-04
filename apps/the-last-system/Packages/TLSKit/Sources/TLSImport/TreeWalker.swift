import Darwin
import Foundation
import TLSCore

/// Reglas de exclusión de la copia. `ExclusionRules` vive en TLSCore (misma regla para copia,
/// índice y lectura); aquí solo lo propio de la copia y del recorrido.
extension ExclusionRules {
    /// Exclusiones de una copia: las de la persona, `privado`, `CopyOptions.siempre` y `Archivo/`.
    /// `privado` son rutas literales (ya expandidas por `VaultLayout`): nunca patrones.
    public static func forCopy(personales: [VaultPath], privado: [VaultPath] = [],
                               incluirArchivo: Bool) -> ExclusionRules {
        var rules = ExclusionRules()
        for p in personales { rules.add(p) }
        for p in privado { rules.add(p) }
        for s in CopyOptions.siempre { rules.addEntry(s) }
        if !incluirArchivo { rules.add(VaultPath("Archivo")) }
        return rules
    }

    /// Exclusiones escritas como ruta absoluta dentro del origen pasan a relativas
    /// (`VaultPath` quita la barra inicial y, si no, no coincidirían con nada).
    static func relativized(_ exclusions: [VaultPath], origen: URL) -> [VaultPath] {
        let base = ExclusionRules.key(CopyJob.canonicalPath(origen))
        return exclusions.map { e in
            let abs = ExclusionRules.key(CopyJob.canonicalPath(URL(fileURLWithPath: "/" + e.raw)))
            guard abs.hasPrefix(base + "/") else { return e }
            let rel = String(CopyJob.canonicalPath(URL(fileURLWithPath: "/" + e.raw)).dropFirst(base.count + 1))
            return VaultPath(rel)
        }
    }

    /// Antes de recorrer, sin listar nada: la primera exclusión de la persona que no existe (`lstat`)
    /// ni cuelga de algo que no se recorre (otra exclusión, solo en iCloud o enlace).
    static func missingBeforeWalk(_ exclusions: [VaultPath], origen: URL, others: ExclusionRules,
                                  fs: any FileSystemAccess) -> VaultPath? {
        exclusions.first { e in
            guard !e.isRoot, !fs.fileExists(e.url(in: origen)) else { return false }
            var ancestor = e.parent
            while let a = ancestor, !a.isRoot {
                let u = a.url(in: origen)
                if others.excludes(a) || fs.isDataless(u) || fs.isSymbolicLink(u) { return false }
                ancestor = a.parent
            }
            return true
        }
    }

    /// Exclusiones de la persona que no coinciden con nada del recorrido (ni podadas, ni dentro de una
    /// carpeta podada, solo en iCloud o enlazada). Suele ser una errata: mejor parar que copiar lo privado.
    static func unmatched(_ exclusions: [VaultPath], pruned: [VaultPath], items: [WalkItem]) -> [VaultPath] {
        var covered = pruned.map { key($0.raw) }
        for item in items {
            switch item.kind {
            case .dataless, .symlink: covered.append(key(item.path.raw))
            case .directory, .file: break
            }
        }
        return exclusions.filter { e in
            guard !e.isRoot else { return false }
            let k = key(e.raw)
            return !covered.contains { k == $0 || k.hasPrefix($0 + "/") }
        }
    }

    static func key(_ s: String) -> String { TextFolding.pathKey(s) }
}

/// Una entrada encontrada al recorrer el origen.
struct WalkItem: Sendable {
    enum Kind: Sendable, Equatable {
        case directory, file, symlink
        /// Solo en iCloud: ni se copia ni se lee. Si es carpeta, tampoco se lista.
        case dataless(isDirectory: Bool)
    }

    /// Ruta relativa en NFC (para comparar e informar).
    let path: VaultPath
    /// Componentes tal como están en disco (para reproducir los nombres en el destino).
    let names: [String]
    let url: URL
    let kind: Kind

    func url(in root: URL) -> URL {
        names.enumerated().reduce(root) { url, item in
            url.appendingPathComponent(item.element, isDirectory: item.offset < names.count - 1 || kind == .directory)
        }
    }
}

/// Recorrido propio con poda: cada carpeta se lista solo si no está excluida, y la decisión se toma
/// ANTES de descender. Una ruta excluida nunca llega a `contentsOfDirectory`.
struct TreeWalker {
    let fs: any FileSystemAccess
    let rules: ExclusionRules

    /// Recorre `root` en preorden (la carpeta antes que su contenido), con orden estable por nombre.
    /// Devuelve las rutas podadas (solo para recuento: no se listaron).
    @discardableResult
    func walk(root: URL, cancel: CancelFlag? = nil, visit: (WalkItem) throws -> Void) throws -> [VaultPath] {
        try walk(root: root, cancel: cancel, podar: nil, opaca: nil, visit: visit)
    }

    /// Igual, con dos ampliaciones de F3 (importar):
    /// - `podar`: además de `rules`, lo que devuelva `true` (por la ruta, sin mirar el disco) no se mira más y cuenta
    ///   como podado (lo oculto: `.obsidian/`, `.git/`…).
    /// - `opaca`: carpetas que se visitan pero no se recorren por dentro (paquetes como `.numbers` o `.app`).
    @discardableResult
    func walk(root: URL, cancel: CancelFlag? = nil, podar: ((VaultPath) -> Bool)?, opaca: ((VaultPath) -> Bool)?,
              visit: (WalkItem) throws -> Void) throws -> [VaultPath] {
        var pruned: [VaultPath] = []
        try walkDirectory(root, path: .root, names: [], cancel: cancel, podar: podar, opaca: opaca,
                          pruned: &pruned, visit: visit)
        return pruned
    }

    private func walkDirectory(_ dir: URL, path: VaultPath, names: [String], cancel: CancelFlag?,
                               podar: ((VaultPath) -> Bool)?, opaca: ((VaultPath) -> Bool)?,
                               pruned: inout [VaultPath], visit: (WalkItem) throws -> Void) throws {
        try cancel?.check()
        let children = try fs.contentsOfDirectory(at: dir)
            .map { (url: $0, name: $0.lastPathComponent) }
            .sorted { $0.name.precomposedStringWithCanonicalMapping < $1.name.precomposedStringWithCanonicalMapping }
        for child in children {
            let childPath = path.appending(child.name)
            // Poda: lo excluido no se mira más (ni lstat, ni listado).
            if rules.excludes(childPath) || podar?(childPath) == true {
                pruned.append(childPath)
                continue
            }
            let childNames = names + [child.name]
            if fs.isSymbolicLink(child.url) {
                try visit(WalkItem(path: childPath, names: childNames, url: child.url, kind: .symlink))
                continue
            }
            let isDir = fs.isDirectory(child.url)
            if fs.isDataless(child.url) {
                try visit(WalkItem(path: childPath, names: childNames, url: child.url,
                                   kind: .dataless(isDirectory: isDir)))
                continue
            }
            if isDir {
                try visit(WalkItem(path: childPath, names: childNames, url: child.url, kind: .directory))
                if opaca?(childPath) == true { continue }
                try walkDirectory(child.url, path: childPath, names: childNames, cancel: cancel,
                                  podar: podar, opaca: opaca, pruned: &pruned, visit: visit)
            } else {
                try visit(WalkItem(path: childPath, names: childNames, url: child.url, kind: .file))
            }
        }
    }
}
