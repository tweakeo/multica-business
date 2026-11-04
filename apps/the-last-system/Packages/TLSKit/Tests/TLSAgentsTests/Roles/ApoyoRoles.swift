import Foundation
import TLSCore
@testable import TLSAgents

/// Utilidades de las pruebas del rol «roles» (catálogo, instrucciones, configuración de serie y Ribera).
enum ApoyoRoles {
    /// Raíz del repositorio (este fichero está en `Packages/TLSKit/Tests/TLSAgentsTests/Roles/`).
    static var repo: URL {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { u.deleteLastPathComponent() }
        return u
    }

    static var ribera: URL { repo.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera", isDirectory: true) }
    static var instrucciones: URL { CatalogoAsistentesTLS.carpetaDelRepositorio(repo) }
    static var grabaciones: URL {
        repo.appendingPathComponent("Packages/TLSKit/Sources/TLSAgents/Simulado/Grabaciones", isDirectory: true)
    }

    /// `TLS_ACTUALIZAR_GOLDEN=1`: regenera en su sitio lo que sale del generador (config y fichas de Ribera).
    static var actualizar: Bool { ProcessInfo.processInfo.environment["TLS_ACTUALIZAR_GOLDEN"] == "1" }

    /// Palabras que no pueden llegar a la pantalla (PLAN §6.9 y el glosario de F4: «asistente», no agente; uso como
    /// porcentaje del tope, no USD).
    static let jerga = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash",
                        "agente", "agentes", "usd", "prompt", "token", "tokens"]

    static func palabrasDeJerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        return jerga.filter { palabras.contains($0) }
    }

    /// Copia temporal de Ribera (nunca se toca la del repositorio).
    static func copiaDeRibera(_ nombre: String = "ribera") throws -> URL {
        let destino = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nombre)-\(UUID().uuidString.prefix(8))", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.copyItem(at: ribera, to: destino)
        return destino
    }

    static func temporal(_ nombre: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nombre)-\(UUID().uuidString.prefix(8))", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func texto(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    /// Estados de Ribera, como los dicen sus `Área.md`.
    static let estadosRibera: [AreaCode: AreaStatus] = [
        .direccion: .activa, .ventas: .activa, .entrega: .activa, .finanzas: .activa, .marca: .preparada, .equipo: .reposo,
    ]
}
