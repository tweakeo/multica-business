import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Apoyo de las pruebas de Finanzas, Marca y Equipo (F2 · rol areas-b): Ribera copiada a una carpeta temporal propia
/// (con lo que cada prueba quiera añadir antes de abrirla), la huella de todos sus ficheros para saber qué cambió y la
/// espera a que la sesión se entere de lo escrito. Nunca toca el ejemplo del repositorio.
@MainActor
struct ApoyoAreasB {
    let pruebas = SesionEscrituraTests()

    /// Abre una copia de Ribera. `preparar` escribe en la copia antes de abrirla (ruta relativa → texto; `nil` borra).
    func abrir(clase: VaultClass = .demo, escritura: WriteAccess = .permitida,
               preparar: [String: String?] = [:]) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: clase, escritura: escritura)
        for (ruta, texto) in preparar {
            let u = e.carpeta.appendingPathComponent(ruta)
            if let texto {
                try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(texto.utf8).write(to: u)
            } else {
                try? FileManager.default.removeItem(at: u)
            }
        }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        return (e, sesion)
    }

    /// Bytes de cada fichero de la carpeta (sin `.tls/escritor.json`, que es del escritor).
    func huella(_ carpeta: URL) -> [String: Data] {
        var out: [String: Data] = [:]
        let base = carpeta.standardizedFileURL.path
        let e = FileManager.default.enumerator(at: carpeta, includingPropertiesForKeys: [.isRegularFileKey])
        while let u = e?.nextObject() as? URL {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let rel = String(u.standardizedFileURL.path.dropFirst(base.count + 1))
            if rel == ".tls/escritor.json" { continue }
            out[rel.precomposedStringWithCanonicalMapping] = try? Data(contentsOf: u)
        }
        return out
    }

    /// Rutas que cambiaron (creadas, cambiadas o quitadas), en orden.
    func cambiados(_ a: [String: Data], _ b: [String: Data]) -> [String] {
        Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted()
    }

    func texto(_ e: SesionEscrituraTests.Entorno, _ ruta: String) -> String? {
        try? String(contentsOf: e.carpeta.appendingPathComponent(ruta), encoding: .utf8)
    }

    func esperar(_ condicion: @MainActor () -> Bool, segundos: Double = 10) async {
        await pruebas.esperar(condicion, segundos: segundos)
    }

    /// Espera a que la sesión se entere de lo escrito (sube la revisión).
    func esperarRevision(_ sesion: VaultSession, despuesDe r: Int) async {
        await esperar { sesion.revision > r }
    }

    /// Deshace con un `UndoManager` y espera a que la carpeta quede como `antes`.
    func deshacer(_ um: UndoManager, _ e: SesionEscrituraTests.Entorno, hasta antes: [String: Data]) async {
        um.undo()
        await esperar { self.huella(e.carpeta) == antes }
    }

    /// Un `UndoManager` que agrupa a mano (como en `AreaScaffoldTests`).
    static func undo() -> UndoManager {
        let um = UndoManager()
        um.groupsByEvent = false
        return um
    }

    static let corriente = "4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo"
    static let extracto = corriente + "/Extractos/2026-10-19 cuenta-corriente-2026-07-a-10.csv"
    static let pagos = "4 · Finanzas/Registros/pagos.csv"
    static let emitidas = "4 · Finanzas/Registros/emitidas.csv"
    static let recibidas = "4 · Finanzas/Registros/recibidas.csv"
}
