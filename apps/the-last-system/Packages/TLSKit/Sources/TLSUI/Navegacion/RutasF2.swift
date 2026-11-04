import Foundation
import TLSCore

// Rutas nuevas de F2 («Tareas y áreas»): nombres para migas, pestañas e historial. El enrutador está en
// `Shell/PantallaDestino.swift`; los huecos de cada pantalla, en `docs/F2-CONTRATOS.md` §2.

extension VaultSession {
    /// Nombre completo de las rutas de F2 (`nombre(de:)` lo pide para `.tarea`, `.decision` y `.banco`).
    func nombreF2(de destino: Destino) -> String {
        switch destino {
        case .tarea(let p):
            return titulo(de: p)
        case .decision:
            if let p = destino.rutaDeDecision { return titulo(de: p) }
            return "Decisión"
        case .banco(nil):
            return "Banco"
        case .banco(let p?):
            let cuenta = resumen(de: p.appending("Cuenta.md"))?.title ?? p.name
            return "Banco · \(cuenta)"
        default:
            return nombre(de: destino)
        }
    }
}
