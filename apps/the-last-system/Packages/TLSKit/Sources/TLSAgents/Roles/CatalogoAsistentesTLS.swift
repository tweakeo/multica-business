import Foundation
import TLSCore

// F4 · rol «roles». El catálogo de serie que consume el motor (`CatalogoDeAsistentes`): los ocho perfiles con sus
// instrucciones de rol, que viven en la app (`App/Recursos/Asistentes/<slug>.md`, en el paquete de la app
// `Contents/Resources/Recursos/Asistentes/`). Las instrucciones son de la app, no de la carpeta: ningún asistente
// las puede cambiar y no dependen de lo que haya en la empresa.

/// Catálogo de los asistentes de serie.
public struct CatalogoAsistentesTLS: CatalogoDeAsistentes {
    /// Perfiles completos, en orden.
    public let perfiles: [PerfilDeAsistente]
    /// Instrucciones de rol por slug, tal como están en su fichero.
    public let instrucciones: [String: String]
    /// Lo que no se pudo leer (el motor sigue con las instrucciones de reserva).
    public let avisos: [String]

    /// Lo que consume el motor.
    public var roles: [RolDeAsistente] {
        perfiles.map { $0.rol(instrucciones: instrucciones[$0.slug] ?? Self.instruccionesDeReserva($0)) }
    }

    /// Carga las instrucciones de `<carpeta>/<slug>.md`. Sin carpeta o sin fichero, el perfil se queda con las de
    /// reserva (hechas con sus datos) y queda un aviso.
    public init(carpetaInstrucciones carpeta: URL?, perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) {
        self.perfiles = perfiles
        var leidas: [String: String] = [:]
        var avisos: [String] = []
        for p in perfiles {
            guard let carpeta else { avisos.append("Sin instrucciones de rol para \(p.slug)"); continue }
            let url = carpeta.appendingPathComponent(p.slug + ".md")
            if let texto = try? String(contentsOf: url, encoding: .utf8), !texto.isEmpty {
                leidas[p.slug] = texto
            } else {
                avisos.append("No encuentro \(url.lastPathComponent)")
            }
        }
        self.instrucciones = leidas
        self.avisos = avisos
    }

    /// Las de la app instalada: `Contents/Resources/Recursos/Asistentes/`.
    public static func deLaApp(bundle: Bundle = .main) -> CatalogoAsistentesTLS {
        CatalogoAsistentesTLS(carpetaInstrucciones: carpetaDeLaApp(bundle: bundle))
    }

    /// `Contents/Resources/Recursos/Asistentes/` si existe.
    public static func carpetaDeLaApp(bundle: Bundle = .main) -> URL? {
        guard let r = bundle.resourceURL?.appendingPathComponent("Recursos/Asistentes", isDirectory: true),
              FileManager.default.fileExists(atPath: r.path) else { return nil }
        return r
    }

    /// `App/Recursos/Asistentes/` dentro del repositorio (pruebas y herramientas de desarrollo).
    public static func carpetaDelRepositorio(_ repo: URL) -> URL {
        repo.appendingPathComponent("App/Recursos/Asistentes", isDirectory: true)
    }

    public func perfil(_ slug: String) -> PerfilDeAsistente? {
        let s = ConfigAgentes.slug(slug)
        return perfiles.first { $0.slug == s }
    }

    /// Los que trabajan en un área (los del sistema no tienen).
    public func perfiles(de area: AreaCode) -> [PerfilDeAsistente] { perfiles.filter { $0.area == area } }

    /// Secciones obligatorias de unas instrucciones de rol (PLAN §5.1).
    public static let secciones = ["Qué haces", "Qué no haces nunca", "Escalado", "Entrega"]

    /// Instrucciones mínimas, hechas con los datos del perfil, si falta el fichero (nunca debería pasar en la app).
    public static func instruccionesDeReserva(_ p: PerfilDeAsistente) -> String {
        var l: [String] = ["# \(p.nombre)", "", "> \(p.pregunta)", "", "## Qué haces", p.mision]
        l += p.puedeSolo.map { "- \($0)" }
        l += ["", "## Qué no haces nunca"] + p.nunca.map { "- \($0)" }
        l += ["", "## Escalado", p.escalado, "", "## Entrega", p.entrega, ""]
        return l.joined(separator: "\n")
    }
}

extension CatalogoAsistentesTLS {
    /// El catálogo sin instrucciones de fichero (pruebas del motor y vistas que solo necesitan los datos).
    public static let soloPerfiles = CatalogoAsistentesTLS(carpetaInstrucciones: nil)
}
