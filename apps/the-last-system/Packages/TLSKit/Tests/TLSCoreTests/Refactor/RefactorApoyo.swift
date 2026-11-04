import Foundation
import Testing
@testable import TLSCore

/// Rutas del repositorio que usan las pruebas de funciones (casos de conformidad y la Ribera convertida).
enum RutasRepo {
    /// Raíz del repositorio (`tls-app`), subiendo desde este fichero.
    static var raiz: URL {
        var u = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while u.path != "/" {
            if FileManager.default.fileExists(atPath: u.appendingPathComponent("Packages/TLSKit/Package.swift").path) { return u }
            u = u.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
    }

    static var ribera: URL { raiz.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera", isDirectory: true) }

    static var casos: URL { raiz.appendingPathComponent("Packages/TLSKit/Tests/Conformidad/Casos", isDirectory: true) }

    static var plantillasPropuesta: URL { raiz.appendingPathComponent("docs/propuesta/plantillas", isDirectory: true) }
}

/// Entorno de escritura sobre una carpeta cualquiera (copia temporal).
struct EntornoCarpeta {
    let base: URL
    let root: URL
    let state: URL
    let appSupport: URL
    let entry: VaultEntry

    init(copiando origen: URL, nombre: String = "Empresa", clase: VaultClass = .copia) {
        base = Apoyo.tempDir("funciones")
        root = base.appendingPathComponent(nombre, isDirectory: true)
        try! FileManager.default.copyItem(at: origen, to: root)
        state = Apoyo.tempDir("estado")
        appSupport = Apoyo.tempDir("asup")
        entry = VaultEntry(nombre: nombre, ruta: root.path, bookmark: nil, clase: clase, escritura: .permitida)
    }

    /// Carpeta vacía (con las seis áreas si se pide).
    init(vacia areas: Bool) {
        base = Apoyo.tempDir("funciones")
        root = base.appendingPathComponent("Empresa", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if areas {
            for a in AreaCode.allCases {
                try! FileManager.default.createDirectory(at: root.appendingPathComponent("\(a.numero) · \(a.nombre)"),
                                                         withIntermediateDirectories: true)
            }
        }
        state = Apoyo.tempDir("estado")
        appSupport = Apoyo.tempDir("asup")
        entry = VaultEntry(nombre: "Empresa", ruta: root.path, bookmark: nil, clase: .copia, escritura: .permitida)
    }

    func writer() async throws -> VaultWriter {
        try await VaultWriter.open(entry: entry, root: root,
                                   options: .init(stateDirectory: state, appSupport: appSupport, app: "The Last System pruebas"))
    }

    func bus() async throws -> CommandBus {
        CommandBus(writer: try await writer())
    }

    func url(_ p: String) -> URL { VaultPath(p).url(in: root) }
    func texto(_ p: String) -> String? { (try? Data(contentsOf: url(p))).flatMap { String(data: $0, encoding: .utf8) } }
    func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: url(p).path) }

    func escribir(_ p: String, _ texto: String) {
        let u = url(p)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(texto.utf8).write(to: u)
    }

    /// Ruta → SHA-256 de todos los ficheros (también ocultos), sin `.tls/escritor.json`.
    func huella() -> [String: String] {
        var out: [String: String] = [:]
        let fm = FileManager.default
        var stack = [root]
        while let dir = stack.popLast() {
            for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                let u = dir.appendingPathComponent(n)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: u.path, isDirectory: &isDir)
                let rel = String(u.path.dropFirst(root.path.count + 1)).precomposedStringWithCanonicalMapping
                if isDir.boolValue { stack.append(u) } else if rel != ".tls/escritor.json" {
                    out[rel] = ContentHash.of((try? Data(contentsOf: u)) ?? Data())
                }
            }
        }
        return out
    }

    /// Huella del árbol en un solo valor.
    func hashArbol() -> String {
        ContentHash.of(huella().sorted { $0.key < $1.key }.map { "\($0.key)\t\($0.value)" }.joined(separator: "\n"))
    }

    func foto() -> VaultSnapshot { VaultSnapshot.read(root: root) }

    func limpiar() { Apoyo.limpiar(base, state, appSupport) }
}

/// Comprueba que cada enlace que resolvía antes sigue resolviendo, después, al destino que le toca
/// (el movido si se movió; el mismo si no). Los enlaces Markdown que resolvían por ruta siguen
/// resolviendo por ruta. Devuelve los fallos en texto.
func comprobarEnlaces(antes: VaultSnapshot, despues: VaultSnapshot, mapa: (VaultPath) -> VaultPath) -> [String] {
    var fallos: [String] = []
    let ra = antes.resolver
    let rd = despues.resolver
    for p in antes.textPaths where p.ext == "md" {
        let q = mapa(p)
        guard let ta = antes.text(p) else { continue }
        guard let td = despues.text(q) else { fallos.append("No está \(q.raw)"); continue }
        let la = LinkScanner.scan(ta)
        let ld = LinkScanner.scan(td)
        guard la.count == ld.count else { fallos.append("\(q.raw): \(la.count) enlaces antes y \(ld.count) después"); continue }
        for (a, d) in zip(la, ld) where !a.link.isExternal && !a.link.target.isEmpty {
            guard let x = ra.resolve(a.link.resolvable, from: p) else { continue }
            let y = rd.resolve(d.link.resolvable, from: q)
            if y?.raw != mapa(x).raw {
                fallos.append("\(q.raw) línea \(d.line): \(d.link.raw) → \(y?.raw ?? "nada") (debía ser \(mapa(x).raw))")
                continue
            }
            if a.link.style == .markdown,
               MarkdownDestination.strictTarget(a.link.target, from: p, exists: { antes.existing($0) })?.raw == x.raw,
               MarkdownDestination.strictTarget(d.link.target, from: q, exists: { despues.existing($0) })?.raw != mapa(x).raw {
                fallos.append("\(q.raw) línea \(d.line): \(d.link.raw) ya no resuelve por ruta")
            }
            if a.link.label != d.link.label || a.link.anchor != d.link.anchor || a.link.isEmbed != d.link.isEmbed {
                fallos.append("\(q.raw) línea \(d.line): cambió el texto visible o la sección de \(a.link.raw)")
            }
        }
    }
    return fallos
}
