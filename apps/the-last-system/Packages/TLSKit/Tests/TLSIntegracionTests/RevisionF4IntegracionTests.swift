import Foundation
import Testing
import TLSCore
@testable import TLSIntegracion
@testable import TLSMCPHost

/// Revisión adversarial de F4 (rol revisión-seguridad): lo que la integración hace con los avisos de `tls_avisar`.
/// Los fallos se corrigieron en el corrector final de F4: las pruebas quedan como regresión.
@Suite("Revisión F4 · integración", .serialized)
struct RevisionF4IntegracionTests {
    final class Contador: @unchecked Sendable {
        private let lock = NSLock()
        private var _n = 0
        var n: Int { lock.withLock { _n } }
        func sumar() { lock.withLock { _n += 1 } }
    }

    /// R12: el nivel «rojo» lo elige el asistente (`tls_avisar {"nivel":"rojo"}`) y lo rojo sale siempre, también como
    /// aviso del Mac (`alMac: nivel == .rojo`), sin tope: basta cambiar el texto. El presupuesto de interrupciones
    /// (≤ 3 no rojos al día) no frena a un asistente (ni a un texto inyectado que se lo pida).
    @Test("R12 · Diez avisos «rojos» de un asistente en un día salen los diez")
    func avisosRojosSinTope() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rev-avisos-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let estado = try EstadoGobierno(directory: dir)
        let salidos = Contador()
        let servicios = ServiciosDelMotor(estado: estado, tope: { 3 }, hoy: { LocalDate(parsing: "2026-10-19")! },
                                          alAvisar: { _ in salidos.sumar() })
        for i in 1...10 {
            _ = await servicios.avisar(AvisoDeAsistente(ejecucion: "r-1", asistente: "comercial",
                                                        texto: "Urgente \(i): revisa el correo de pago.", nivel: .rojo, ruta: nil))
        }
        // Corregido (corrector final F4): R12: lo «rojo» de un asistente no tiene tope ni lo comprueba la app
        do {
            #expect(salidos.n <= 3, "salieron \(salidos.n) avisos rojos")
        }
    }
}
