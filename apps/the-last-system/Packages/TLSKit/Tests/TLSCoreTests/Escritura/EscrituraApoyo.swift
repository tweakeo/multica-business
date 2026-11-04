import Foundation
import Testing
@testable import TLSCore

/// Entorno de escritura: copia editable de la fixture, carpeta de estado y de cerrojos propias.
struct EntornoEscritura {
    let base: URL
    let root: URL
    let state: URL
    let appSupport: URL
    let entry: VaultEntry

    init(clase: VaultClass = .copia, escritura: WriteAccess = .permitida, exclusiones: [String] = []) {
        root = Apoyo.copiaDeFixture()
        base = root.deletingLastPathComponent()
        state = Apoyo.tempDir("estado")
        appSupport = Apoyo.tempDir("asup")
        entry = VaultEntry(nombre: "Estudio Ejemplo", ruta: root.path, bookmark: nil, clase: clase,
                           escritura: escritura, exclusionesCopia: exclusiones)
    }

    var options: VaultWriter.Options {
        VaultWriter.Options(stateDirectory: state, appSupport: appSupport, app: "The Last System pruebas")
    }

    func writer() async throws -> VaultWriter {
        try await VaultWriter.open(entry: entry, root: root, options: options)
    }

    func bus() async throws -> CommandBus {
        CommandBus(writer: try await writer())
    }

    func url(_ p: String) -> URL { VaultPath(p).url(in: root) }

    func datos(_ p: String) -> Data? { try? Data(contentsOf: url(p)) }

    func texto(_ p: String) -> String? { datos(p).flatMap { String(data: $0, encoding: .utf8) } }

    func escribir(_ p: String, _ texto: String) {
        let u = url(p)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(texto.utf8).write(to: u)
    }

    func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: url(p).path) }

    /// Huella (ruta → SHA-256) de todos los ficheros, también los ocultos.
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
                if isDir.boolValue { stack.append(u) } else { out[rel] = ContentHash.of((try? Data(contentsOf: u)) ?? Data()) }
            }
        }
        return out
    }

    /// Huella sin `.tls/escritor.json` (la ficha del escritor se crea al escribir la primera vez).
    func huellaSinEscritor() -> [String: String] {
        var h = huella()
        h.removeValue(forKey: ".tls/escritor.json")
        return h
    }

    func limpiar() { Apoyo.limpiar(base, state, appSupport) }
}

/// Generador pseudoaleatorio con semilla (las pruebas aleatorias se pueden repetir).
struct Semilla: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Array {
    func aleatorio(_ g: inout Semilla) -> Element { self[Int.random(in: 0..<count, using: &g)] }
}

/// Todos los ficheros de texto de la fixture (para las idas y vueltas).
func ficherosDeTexto(_ root: URL, extensiones: Set<String> = ["md", "csv"]) -> [URL] {
    var out: [URL] = []
    let fm = FileManager.default
    guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
    for case let u as URL in e where extensiones.contains(u.pathExtension.lowercased()) { out.append(u) }
    return out.sorted { $0.path < $1.path }
}

/// Comprueba que `body` falla con ese error de escritura.
func esperaError<T>(_ esperado: WriteError, sourceLocation: SourceLocation = #_sourceLocation, _ body: () throws -> T) {
    do {
        _ = try body()
        Issue.record("Debía fallar con \(esperado)", sourceLocation: sourceLocation)
    } catch let e as WriteError {
        #expect(e == esperado, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Error inesperado: \(error)", sourceLocation: sourceLocation)
    }
}

func esperaErrorAsync<T>(_ esperado: WriteError, sourceLocation: SourceLocation = #_sourceLocation,
                         _ body: () async throws -> T) async {
    do {
        _ = try await body()
        Issue.record("Debía fallar con \(esperado)", sourceLocation: sourceLocation)
    } catch let e as WriteError {
        #expect(e == esperado, sourceLocation: sourceLocation)
    } catch {
        Issue.record("Error inesperado: \(error)", sourceLocation: sourceLocation)
    }
}
