import Foundation
import TLSAgents
import TLSCore

// F5 · rol mail. Conectar Mail activa al Cartero (PLAN §5.1: «Cartero · Buzón · activo cuando conectes Mail»): lo
// escribe la PERSONA en `.tls/config.yaml` (con `EditorConfigAgentes`, que deja confirmado el cambio), nunca un asistente.
// Si la carpeta ya tenía al Cartero (inactivo), se respeta lo suyo y solo cambia `activo`; si no lo tenía, entra con su
// configuración de serie (Buzón, lee Ventas y Finanzas, triaje L–V 08:30, haiku, esfuerzo bajo).

public enum ConexionDelCartero {
    public static let slug = PerfilDeAsistente.cartero.slug

    /// La entrada de serie del Cartero (la del catálogo), activa o no.
    public static func deSerie(activo: Bool) -> AsistenteConfigurado {
        let lineas = ["agentes:"] + ConfigDeSerie.entrada(.cartero, activo: activo).map { "  " + $0 }
        let leido = ConfigAgentes.leer(yaml: lineas.joined(separator: "\n") + "\n").asistente(slug)
        return leido ?? AsistenteConfigurado(slug: slug, activo: activo, buzon: true, leeAreas: [.ventas, .finanzas],
                                             modelo: "haiku", esfuerzo: "low")
    }

    /// La entrada que queda en la configuración con `activo` puesto (lo demás, como estaba).
    public static func entrada(activo: Bool, config texto: String?) -> AsistenteConfigurado {
        var a = ConfigAgentes.leer(yaml: texto).asistente(slug) ?? deSerie(activo: activo)
        a.activo = activo
        if !a.buzon { a.buzon = true }
        return a
    }

    /// Activa (o desactiva) al Cartero como persona. Lo hace la pantalla Conexiones al conectar o desconectar Mail.
    @discardableResult
    public static func activar(_ activo: Bool = true, bus: CommandBus, autor: Autor) async throws -> WriteResult {
        guard autor.esPersona else { throw ErrorDeGobierno.soloPersonas }
        let url = EditorConfigAgentes.ruta.url(in: bus.writer.root)
        let texto = (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
        return try await EditorConfigAgentes.aplicar(.asistente(entrada(activo: activo, config: texto)), bus: bus, autor: autor)
    }

    /// ¿Está activo el Cartero en esta configuración?
    public static func activo(config texto: String?) -> Bool {
        ConfigAgentes.leer(yaml: texto).asistente(slug)?.activo ?? false
    }
}
