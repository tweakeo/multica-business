import Foundation
import TLSAgents
import TLSCore

// F4 · integración. La puesta en marcha deja listos los asistentes de serie con lo que sabe TLSAgents (rol roles:
// `ConfigDeSerie` y `FichaDeRolDeAsistente`): la sección `agentes:` y lo que la acompaña en `.tls/config.yaml` y las
// fichas `6 · Equipo/Roles/asistente-<slug>.md` que falten. Nunca pisa nada.

/// Los asistentes de serie para la puesta en marcha (`OnboardingEngine.asistentes`).
public struct AsistentesDeLaPuesta: ProveedorAsistentesDeSerie {
    public var perfiles: [PerfilDeAsistente]

    public init(perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) { self.perfiles = perfiles }

    public func completarConfig(_ texto: String, estados: [AreaCode: AreaStatus]) -> String {
        ConfigDeSerie.completar(texto, estados: estados, mailConectado: false, perfiles: perfiles)
    }

    public func fichas(layout: VaultLayout, existe: (VaultPath) -> Bool, semilla: String) -> [(ruta: VaultPath, texto: String)] {
        let carpeta = FichaDeRolDeAsistente.carpeta(layout)
        return perfiles.compactMap { p in
            let ruta = FichaDeRolDeAsistente.ruta(p.slug, layout: layout)
            guard !existe(ruta) else { return nil }
            // Enlaza el rol de la persona del área si ya está (lo escribe Organizar en el mismo plan o venía de antes).
            let humano = p.area.flatMap(FichaDeRolDeAsistente.rolHumanoDeSerie).flatMap { existe(carpeta.appending($0 + ".md")) ? $0 : nil }
            return (ruta, FichaDeRolDeAsistente.texto(p, rolHumano: humano, semilla: semilla))
        }
    }
}
