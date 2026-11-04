import SwiftUI
import TLSCore

// PLAN §6.1 (⇧⌘N «Nueva nota»): la misma hoja «Nueva…» de la Carpeta, abierta desde cualquier pantalla y en la carpeta
// que le toca: la del área si estás en un área, la carpeta que estás viendo o, si no, la carpeta de tu empresa. No escribe
// nada hasta que confirmas, y lo creado se abre al momento (se deshace con ⌘Z, como todo).

struct NuevaNotaHoja: View {
    let contexto: Destino
    let sesion: VaultSession
    @State private var modelo: CarpetaModelo?
    @Environment(\.navegar) private var navegar

    var body: some View {
        Group {
            if let modelo {
                HojaNueva(modelo: modelo, seleccion: nil) { destino in navegar(destino, modo: .entrar) }
            } else {
                ProgressView().controlSize(.small).frame(width: 600, height: 420)
            }
        }
        .task {
            let m = CarpetaModelo(carpeta: Self.carpeta(de: contexto, sesion: sesion), sesion: sesion)
            await m.cargar()
            modelo = m
        }
        .accessibilityIdentifier("nuevaNota.hoja")
    }

    /// La carpeta de la pantalla: un área, la carpeta que se ve o la raíz.
    static func carpeta(de d: Destino, sesion: VaultSession) -> VaultPath? {
        switch d {
        case .area(let a, _): return sesion.estructura?.areaFolder(a)
        case .carpeta(let p): return p
        default: return nil
        }
    }
}
