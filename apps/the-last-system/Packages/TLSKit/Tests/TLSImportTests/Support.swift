import Foundation
import Synchronization
import TLSCore
@testable import TLSImport

/// Carpeta temporal con un árbol sintético. Nada de datos reales.
struct TempTree {
    let base: URL

    init() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        base = tmp.appendingPathComponent("tls-import-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    func dir(_ rel: String) -> URL { base.appendingPathComponent(rel, isDirectory: true) }

    @discardableResult
    func write(_ rel: String, _ text: String, in root: String) throws -> URL {
        let url = base.appendingPathComponent(root).appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    func remove() { try? FileManager.default.removeItem(at: base) }

    /// Origen sintético con forma de carpeta de empresa G3.
    func makeOrigin(_ name: String = "Empresa Prueba") throws -> URL {
        let o = name
        try write("Empresa.md", "# Empresa de prueba\n", in: o)
        try write("AGENTS.md", "Instrucciones de prueba.\n", in: o)
        try write(".tls/layout.json", "{\"preset\": \"humana\"}", in: o)
        try write(".tls/escritor.json", "{\"vault_id\": \"x\"}", in: o)
        try write(".obsidian/app.json", "{}", in: o)
        try write(".obsidian/workspace.json", "{\"abierto\": true}", in: o)
        try write("1 · Dirección/Área.md", "# Dirección\n\n**Estado:** activa · **La lleva:** Ana\n", in: o)
        try write("2 · Ventas/Área.md", "# Ventas\n\n**Estado:** preparada\n", in: o)
        try write("2 · Ventas/.DS_Store", "basura de Finder", in: o)
        // «Trámites» escrito en NFD a propósito: la exclusión llega en NFC.
        let tramites = "4 · Finanzas/Tra\u{301}mites"
        try write("\(tramites)/Privada X/secreto.md", "contenido privado de prueba\n", in: o)
        try write("\(tramites)/Privada X/Sub/otro.md", "más privado\n", in: o)
        try write("\(tramites)/Público/nota.md", "nota pública\n", in: o)
        try write("4 · Finanzas/Registros/emitidas.csv", "id,fecha,total\nF-1,2026-10-01,100\n", in: o)
        try write("Archivo/viejo.md", "retirado\n", in: o)
        try write("Archivo/Importación 2026-09-01/a.md", "retirado\n", in: o)
        // Un fichero de 3 MB para cruzar varios bloques de 1 MB al resumir.
        let big = base.appendingPathComponent(o).appendingPathComponent("5 · Marca/Recursos/grande.bin")
        try FileManager.default.createDirectory(at: big.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<(3 * 1024 * 1024 + 17)).map { UInt8(truncatingIfNeeded: $0 &* 31) }).write(to: big)
        try FileManager.default.createDirectory(at: dir("\(o)/6 · Equipo/Vacía"), withIntermediateDirectories: true)
        return dir(o)
    }
}

/// Envuelve el disco real y registra cada operación, para demostrar qué se listó, leyó y copió.
final class RecordingFileSystem: FileSystemAccess, Sendable {
    struct Log: Sendable {
        var listed: [String] = []
        var hashed: [String] = []
        var copied: [String] = []
        var trashed: [String] = []
        var unprotectedCalls: [String] = []
    }

    let inner = LocalFileSystem()
    let log = Mutex(Log())
    /// Rutas absolutas (NFC) que este disco simula como «solo en iCloud».
    let datalessPaths: Set<String>
    /// Si no es nil, el SHA-256 de lo que cuelgue de aquí se falsea (para probar la verificación).
    let corruptUnder: String?

    init(datalessPaths: Set<String> = [], corruptUnder: String? = nil) {
        self.datalessPaths = Set(datalessPaths.map(Self.nfc))
        self.corruptUnder = corruptUnder.map(Self.nfc)
    }

    static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
    static func key(_ url: URL) -> String { nfc(url.standardizedFileURL.path) }

    private func note(_ op: String, _ url: URL) {
        let protected = DatalessGuard.currentThreadIsProtected
        log.withLock { l in
            if !protected { l.unprotectedCalls.append("\(op) \(Self.key(url))") }
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        note("listar", url)
        log.withLock { $0.listed.append(Self.key(url)) }
        return try inner.contentsOfDirectory(at: url)
    }

    func isDirectory(_ url: URL) -> Bool { inner.isDirectory(url) }
    func isSymbolicLink(_ url: URL) -> Bool { inner.isSymbolicLink(url) }
    func isDataless(_ url: URL) -> Bool { datalessPaths.contains(Self.key(url)) || inner.isDataless(url) }
    func fileSize(_ url: URL) -> Int64? { inner.fileSize(url) }

    func sha256(of url: URL) throws -> String {
        note("resumir", url)
        log.withLock { $0.hashed.append(Self.key(url)) }
        if let c = corruptUnder, Self.key(url).hasPrefix(c + "/") { return String(repeating: "0", count: 64) }
        return try inner.sha256(of: url)
    }

    func copyItem(at src: URL, to dst: URL) throws {
        if let hook = onCopy.withLock({ $0 }) { hook() }
        note("copiar", src)
        log.withLock { $0.copied.append(Self.key(src)) }
        try inner.copyItem(at: src, to: dst)
    }

    func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
    func write(_ data: Data, to url: URL) throws { try inner.write(data, to: url) }
    func fileExists(_ url: URL) -> Bool { inner.fileExists(url) }
    func contents(of url: URL) throws -> Data {
        note("leer", url)
        return try inner.contents(of: url)
    }
    func modificationDate(_ url: URL) -> Date? { inner.modificationDate(url) }
    func setModificationDate(_ date: Date, for url: URL) throws { try inner.setModificationDate(date, for: url) }
    /// En pruebas no se usa la Papelera de verdad: se borra (es una carpeta temporal) y se apunta.
    func trashItem(_ url: URL) throws {
        log.withLock { $0.trashed.append(Self.key(url)) }
        try FileManager.default.removeItem(at: url)
    }

    /// Se llama (en el hilo de copia) antes de copiar cada fichero: para probar «Cancelar».
    let onCopy: Mutex<(@Sendable () -> Void)?> = Mutex(nil)
}

/// Todos los ficheros (no carpetas) bajo `root`, como rutas relativas en NFC.
func relativeFiles(under root: URL) -> [String] {
    let fm = FileManager.default
    guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
    var out: [String] = []
    for case let url as URL in e {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if !isDir, let rel = VaultPath(url: url, root: root) { out.append(rel.raw) }
    }
    return out.sorted()
}

func sha(_ url: URL) throws -> String { try LocalFileSystem().sha256(of: url) }
