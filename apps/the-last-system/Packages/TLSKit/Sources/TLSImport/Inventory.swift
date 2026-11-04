import CryptoKit
import Foundation
import TLSCore

/// Una entrada del inventario de una carpeta.
public struct InventoryEntry: Sendable, Codable, Hashable {
    public enum Tipo: String, Sendable, Codable, Hashable {
        case fichero, carpeta, enlace
    }

    /// Ruta relativa en NFC.
    public let ruta: String
    public let tipo: Tipo
    /// Tamaño en bytes (solo ficheros; también los que están solo en iCloud).
    public let tamano: Int64?
    /// SHA-256 en hexadecimal; `nil` si no se calculó o si el fichero está solo en iCloud.
    public let sha256: String?
    /// Solo en iCloud: no se ha leído (ni, si es carpeta, listado).
    public let dataless: Bool

    public init(ruta: String, tipo: Tipo, tamano: Int64?, sha256: String?, dataless: Bool) {
        self.ruta = ruta; self.tipo = tipo; self.tamano = tamano; self.sha256 = sha256; self.dataless = dataless
    }

    /// Línea canónica para el hash del árbol.
    var canonicalLine: String {
        "\(tipo.rawValue)\t\(ruta)\t\(tamano.map(String.init) ?? "")\t\(sha256 ?? "")\t\(dataless ? 1 : 0)\n"
    }
}

/// Inventario de una carpeta con el mismo recorrido y la misma poda que la copia.
///
/// Sirve para el criterio de F0 «el inventario del origen es idéntico antes y después»:
/// mismo `hashArbol` antes y después = mismas rutas, tamaños, contenidos y ficheros solo en iCloud.
public struct Inventory: Sendable, Codable {
    public let raiz: String
    /// Ordenadas por ruta (orden de bytes en NFC).
    public let entradas: [InventoryEntry]
    public let ficheros: Int
    public let carpetas: Int
    public let enlaces: Int
    /// Suma de tamaños de los ficheros (incluidos los que están solo en iCloud).
    public let bytes: Int64
    /// Ficheros y carpetas solo en iCloud.
    public let dataless: Int
    /// Rutas podadas (excluidas); no se listaron.
    public let excluidas: Int
    public let conHashes: Bool
    /// SHA-256 de las líneas canónicas de todas las entradas.
    public let hashArbol: String

    public init(raiz: String, entradas: [InventoryEntry], excluidas: Int, conHashes: Bool) {
        let sorted = entradas.sorted { $0.ruta < $1.ruta }
        self.raiz = raiz
        self.entradas = sorted
        self.ficheros = sorted.filter { $0.tipo == .fichero }.count
        self.carpetas = sorted.filter { $0.tipo == .carpeta }.count
        self.enlaces = sorted.filter { $0.tipo == .enlace }.count
        self.bytes = sorted.reduce(0) { $0 + ($1.tipo == .fichero ? ($1.tamano ?? 0) : 0) }
        self.dataless = sorted.filter(\.dataless).count
        self.excluidas = excluidas
        self.conHashes = conHashes
        var hasher = SHA256()
        for e in sorted { hasher.update(data: Data(e.canonicalLine.utf8)) }
        self.hashArbol = LocalFileSystem.hex(hasher.finalize())
    }

    /// Rutas que aparecen, desaparecen o cambian entre dos inventarios.
    public func diferencias(con otro: Inventory) -> [String] {
        let a = Dictionary(entradas.map { ($0.ruta, $0) }, uniquingKeysWith: { x, _ in x })
        let b = Dictionary(otro.entradas.map { ($0.ruta, $0) }, uniquingKeysWith: { x, _ in x })
        return Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted()
    }

    /// Hace el inventario de `root` sin descargar nada de iCloud.
    ///
    /// Aplica las mismas exclusiones que la copia: las indicadas, `privado` de `.tls/`,
    /// `CopyOptions.siempre` y `Archivo/` salvo `incluirArchivo`.
    public static func make(of root: URL, exclusiones: [VaultPath] = [], incluirArchivo: Bool = false,
                            conHashes: Bool = true, fileSystem: any FileSystemAccess = LocalFileSystem(),
                            progress: (@Sendable (Int) -> Void)? = nil) async throws -> Inventory {
        try await make(of: root, exclusiones: exclusiones, incluirArchivo: incluirArchivo, conHashes: conHashes,
                       completo: false, fileSystem: fileSystem, progress: progress)
    }

    /// Igual, y con `completo` mira también lo oculto (`.tls/`, `.obsidian/`, `.DS_Store`) y `Archivo/`:
    /// sirve para comprobar que nada ha escrito en una copia. Lo privado y lo indicado siguen sin mirarse.
    public static func make(of root: URL, exclusiones: [VaultPath] = [], incluirArchivo: Bool = false,
                            conHashes: Bool = true, completo: Bool, fileSystem: any FileSystemAccess = LocalFileSystem(),
                            progress: (@Sendable (Int) -> Void)? = nil) async throws -> Inventory {
        try await DatalessGuard.run("TLSImport.inventario") { cancel in
            let base = root.standardizedFileURL.resolvingSymlinksInPath()
            guard fileSystem.isDirectory(base) else { throw CopyError.origenNoAccesible(root.path) }
            let plan = try CopyExclusions.make(origen: base, personales: exclusiones, incluirArchivo: incluirArchivo,
                                               completo: completo, fs: fileSystem)
            return try make(root: base, rules: plan.rules, plan: plan, conHashes: conHashes,
                            fs: fileSystem, cancel: cancel, progress: progress)
        }
    }

    /// Versión síncrona; debe llamarse desde un hilo protegido (`DatalessGuard`).
    static func make(root: URL, rules: ExclusionRules, plan: CopyExclusions? = nil, conHashes: Bool,
                     fs: any FileSystemAccess, cancel: CancelFlag?,
                     progress: (@Sendable (Int) -> Void)?) throws -> Inventory {
        var entries: [InventoryEntry] = []
        var skipped: [WalkItem] = []
        let walker = TreeWalker(fs: fs, rules: rules)
        let pruned: [VaultPath]
        do {
            pruned = try walker.walk(root: root, cancel: cancel) { item in
                switch item.kind {
                case .dataless, .symlink: skipped.append(item)
                case .directory, .file: break
                }
                let entry: InventoryEntry
                switch item.kind {
                case .directory:
                    entry = InventoryEntry(ruta: item.path.raw, tipo: .carpeta, tamano: nil, sha256: nil, dataless: false)
                case .symlink:
                    entry = InventoryEntry(ruta: item.path.raw, tipo: .enlace, tamano: nil, sha256: nil, dataless: false)
                case .dataless(let isDir):
                    entry = InventoryEntry(ruta: item.path.raw, tipo: isDir ? .carpeta : .fichero,
                                           tamano: isDir ? nil : fs.fileSize(item.url), sha256: nil, dataless: true)
                case .file:
                    entry = InventoryEntry(ruta: item.path.raw, tipo: .fichero, tamano: fs.fileSize(item.url),
                                           sha256: conHashes ? try fs.sha256(of: item.url) : nil, dataless: false)
                }
                entries.append(entry)
                if entries.count % 200 == 0 { progress?(entries.count) }
            }
        } catch let error as CancellationError {
            throw error
        } catch where entries.isEmpty {
            throw CopyError.origenNoAccesible(root.path)
        }
        progress?(entries.count)
        // Igual que la copia: una ruta declarada que no coincide con nada suele ser una errata.
        try plan?.checkUnmatched(pruned: pruned, items: skipped)
        return Inventory(raiz: root.path, entradas: entries, excluidas: pruned.count, conHashes: conHashes)
    }
}
