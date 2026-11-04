import CryptoKit
import Foundation
@testable import TLSCore

/// Utilidades comunes de los tests de TLSCore.
enum Apoyo {
    /// Fixture sintética dentro del bundle de tests (solo lectura).
    static var empresaMinima: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
            .appendingPathComponent("EmpresaMinima", isDirectory: true)
    }

    /// Carpeta temporal nueva (se borra con `limpiar`).
    static func tempDir(_ name: String = "tls") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func limpiar(_ urls: URL...) {
        for u in urls { try? FileManager.default.removeItem(at: u) }
    }

    /// Copia editable de la fixture (para vigilancia e incremental).
    static func copiaDeFixture() -> URL {
        let dir = tempDir("empresa")
        let dst = dir.appendingPathComponent("EmpresaMinima", isDirectory: true)
        try! FileManager.default.copyItem(at: empresaMinima, to: dst)
        return dst
    }

    static func entrada(_ root: URL) -> VaultEntry {
        VaultEntry(nombre: "Estudio Ejemplo", ruta: root.path, bookmark: nil, clase: .demo, escritura: .bloqueada)
    }

    /// Servicio sobre `root` con el índice en una carpeta temporal y «Privado» marcado como privado.
    static func servicio(_ root: URL, state: URL, vigilar: Bool = false) throws -> VaultService {
        try VaultService(entry: entrada(root), root: root,
                         options: .init(privado: [VaultPath("Privado")], stateDirectory: state, vigilar: vigilar))
    }

    /// Huella del árbol: rutas (también ocultas), tamaño, fecha de modificación y SHA-256.
    static func huellaDeArbol(_ root: URL) -> [String] {
        var out: [String] = []
        let fm = FileManager.default
        var stack = [root]
        while let dir = stack.popLast() {
            let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            for n in names.sorted() {
                let u = dir.appendingPathComponent(n)
                let rel = String(u.path.dropFirst(root.path.count))
                let info = UbiquityInspector.info(u)!
                if info.isDirectory {
                    out.append("D \(rel) \(info.mtimeNanos)")
                    stack.append(u)
                } else {
                    let data = (try? Data(contentsOf: u)) ?? Data()
                    let h = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    out.append("F \(rel) \(info.size) \(info.mtimeNanos) \(h)")
                }
            }
        }
        return out.sorted()
    }

    /// Espera hasta `timeout` segundos a que `condition` sea cierta.
    static func esperar(_ timeout: TimeInterval, _ condition: @Sendable () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }
}

/// Caja con cerrojo para recoger resultados de callbacks.
final class Caja<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
    func update(_ f: (inout T) -> Void) { lock.withLock { f(&_value) } }
}
