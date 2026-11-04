import AppKit
import Foundation
import TLSCore

/// Ganchos de arranque para las pruebas de interfaz (XCUITest `launchEnvironment`) y las capturas.
/// Solo navegan: nunca escriben nada.
///
/// - `TLS_UI_ABRIR=<uuid>`: abre esa empresa al arrancar.
/// - `TLS_UI_LATERAL=carpeta|buscar|bases|revisar|DIR|VEN|ENT|FIN|MAR|EQU`: raíz de la primera pestaña.
/// - `TLS_UI_NOTA=<ruta relativa>`: ficha, nota o fichero que se abre (un nivel).
/// - `TLS_UI_BUSCAR=<texto>`: búsqueda inicial en la carpeta.
/// - `TLS_UI_DESPLEGAR=<ruta>[,<ruta>…]`: carpetas desplegadas en el árbol.
/// - `TLS_UI_HOJA=abrirRapido|paleta`: hoja abierta al terminar.
/// - `TLS_UI_SELECTOR=crearCopia|verSinTocar`: hoja abierta en el selector de empresa.
enum UITestHooks {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }

    static var vaultToOpen: UUID? {
        env["TLS_UI_ABRIR"].flatMap(UUID.init(uuidString:))
    }

    static var launcherSheet: String? { env["TLS_UI_SELECTOR"] }

    /// Solo la primera vez: abrir el selector de nuevo no repite la navegación.
    @MainActor static var consumed = false

    @MainActor
    static func apply(to session: VaultSession, nav: Navegacion) {
        guard vaultToOpen == session.entry.id, !navegacionAplicada else { return }
        navegacionAplicada = true
        NSApplication.shared.activate()
        if let folders = env["TLS_UI_DESPLEGAR"] {
            for raw in folders.split(separator: ",") { session.expand(VaultPath(String(raw))) }
        }
        switch env["TLS_UI_LATERAL"] {
        case "carpeta"?: nav.nuevaRaiz(.carpeta(nil))
        case "buscar"?: nav.nuevaRaiz(.busqueda(""))
        case "bases"?: nav.nuevaRaiz(.todasLasBases)
        case "revisar"?: nav.nuevaRaiz(.revisar)
        case let code? where AreaCode(rawValue: code) != nil: nav.nuevaRaiz(.area(AreaCode(rawValue: code)!))
        default: break
        }
        if let query = env["TLS_UI_BUSCAR"] {
            nav.nuevaRaiz(.busqueda(query))
            session.updateSearch(query)
        }
        if let note = env["TLS_UI_NOTA"] {
            nav.entrar(session.destino(para: VaultPath(note)))
        }
        switch env["TLS_UI_HOJA"] {
        case "abrirRapido"?: nav.hoja = .abrirRapido
        case "paleta"?: nav.hoja = .paleta
        default: break
        }
    }

    /// La navegación de prueba se aplica una sola vez (a la primera pestaña).
    @MainActor static var navegacionAplicada = false
}
