import Foundation
import TLSCore

// F4 · rol «roles». Lo que hay que escribir en una carpeta para dejarle los asistentes de serie: la configuración
// completada (`.tls/config.yaml`, PLAN §4.5) y las fichas de rol que falten (`6 · Equipo/Roles/asistente-<slug>.md`).
// Es lo que usa la puesta en marcha al aplicar (F3, paso 4) en una empresa nueva o en la copia, como la persona y
// en el mismo plan (un solo Deshacer). **Nunca cambia nada que ya esté**: una clave de la configuración que ya
// existe se respeta aunque esté vacía, y una ficha que ya existe no se toca.

/// Un cambio previsto (para la vista previa y para las pruebas).
public struct CambioDeAsistentes: Sendable, Hashable {
    public let ruta: VaultPath
    /// `nil` si el fichero es nuevo.
    public let antes: String?
    public let despues: String
}

/// Los asistentes de serie de una carpeta.
public enum AsistentesDeSerie {
    /// Qué cambiaría en `root` (solo lee).
    /// - Parameters:
    ///   - estados: estados de las áreas (los de la puesta en marcha, si aún no están escritos); sin ellos, los de
    ///     los `Área.md` de la carpeta.
    ///   - semilla: para los `id` de las fichas (el id de la empresa).
    public static func cambios(root: URL, estados: [AreaCode: AreaStatus]? = nil, mailConectado: Bool = false,
                               semilla: String = "", perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie)
        -> [CambioDeAsistentes] {
        let (layout, _) = VaultLayout.load(root: root)
        let est = estados ?? ConfigDeSerie.estados(en: root)
        var out: [CambioDeAsistentes] = []
        let rutaConfig = VaultPath(VaultLayout.configFile)
        let actual = try? String(contentsOf: rutaConfig.url(in: root), encoding: .utf8)
        let nuevo = ConfigDeSerie.completar(actual ?? "", estados: est, mailConectado: mailConectado, perfiles: perfiles)
        if nuevo != (actual ?? "") { out.append(CambioDeAsistentes(ruta: rutaConfig, antes: actual, despues: nuevo)) }
        let fm = FileManager.default
        let carpeta = FichaDeRolDeAsistente.carpeta(layout)
        for p in perfiles {
            let ruta = FichaDeRolDeAsistente.ruta(p.slug, layout: layout)
            guard !fm.fileExists(atPath: ruta.url(in: root).path) else { continue }
            let humano = p.area.flatMap(FichaDeRolDeAsistente.rolHumanoDeSerie)
                .flatMap { fm.fileExists(atPath: carpeta.appending($0 + ".md").url(in: root).path) ? $0 : nil }
            out.append(CambioDeAsistentes(ruta: ruta, antes: nil,
                                          despues: FichaDeRolDeAsistente.texto(p, rolHumano: humano, semilla: semilla)))
        }
        return out
    }

    /// Las operaciones de escritura (compare-and-swap sobre los bytes leídos; los ficheros nuevos no pisan nada).
    public static func ops(root: URL, estados: [AreaCode: AreaStatus]? = nil, mailConectado: Bool = false,
                           semilla: String = "", perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) -> [WriteOp] {
        cambios(root: root, estados: estados, mailConectado: mailConectado, semilla: semilla, perfiles: perfiles)
            .compactMap { c in
                guard let antes = c.antes else { return .create(c.ruta, text: c.despues) }
                return WriteOp.replaceText(c.ruta, base: Data(antes.utf8), text: c.despues)
            }
    }

    /// Un plan de la persona con todo lo anterior (`nil` si no hay nada que escribir).
    public static func plan(root: URL, persona: String, estados: [AreaCode: AreaStatus]? = nil,
                            mailConectado: Bool = false, semilla: String = "") -> WritePlan? {
        let o = ops(root: root, estados: estados, mailConectado: mailConectado, semilla: semilla)
        guard !o.isEmpty else { return nil }
        return WritePlan(autor: .persona(persona), descripcion: "Dejar listos los asistentes", ops: o)
    }
}
