import CryptoKit
import Foundation
import TLSCore

// F4 · rol «roles». La ficha de rol de cada asistente (`6 · Equipo/Roles/asistente-<slug>.md`, `clase: agente`,
// PLAN §4.3 `role`): **descriptiva**. Cuenta a la persona qué hace, qué no hace nunca y cuándo le pregunta; los
// permisos que se aplican viven en `.tls/config.yaml`. Ningún asistente escribe aquí.
//
// El nombre lleva `asistente-` delante porque el rol de la persona del área ya se llama como el asistente
// (`comercial.md`, `implementador.md`: los crea la puesta en marcha y los trae Ribera). La ficha del asistente enlaza
// a ese rol en `rol:` cuando existe.

/// Fichas de rol de los asistentes.
public enum FichaDeRolDeAsistente {
    /// Ruta de la ficha: `{equipo}/Roles/asistente-<slug>.md` (o la carpeta de roles del `layout.json`).
    public static func ruta(_ slug: String, layout: VaultLayout) -> VaultPath {
        carpeta(layout).appending(nombreDeFichero(slug))
    }

    public static func carpeta(_ layout: VaultLayout) -> VaultPath {
        layout.dir(for: "role") ?? layout.areaFolder(.equipo).appending("Roles")
    }

    public static func nombreDeFichero(_ slug: String) -> String { "asistente-\(slug).md" }

    /// Slug del rol de la persona de cada área, como lo escribe la puesta en marcha («Comercial» → `comercial`).
    public static func rolHumanoDeSerie(_ area: AreaCode) -> String? {
        CatalogoPrograma.deSerie.roles.first { $0.area == area }.map { NombresDeFicha.slug($0.nombre) }
    }

    /// Identificador estable de la ficha (el mismo para el mismo asistente en la misma empresa).
    public static func id(_ slug: String, semilla: String = "") -> String {
        let h = Array(SHA256.hash(data: Data("tls-rol-asistente|\(semilla)|\(slug)".utf8)))
        var b = Array(h.prefix(16))
        b[6] = (b[6] & 0x0F) | 0x50
        b[8] = (b[8] & 0x3F) | 0x80
        let hex = b.map { String(format: "%02x", $0) }.joined()
        let i = hex.startIndex
        func trozo(_ a: Int, _ n: Int) -> Substring { hex[hex.index(i, offsetBy: a)..<hex.index(i, offsetBy: a + n)] }
        return "\(trozo(0, 8))-\(trozo(8, 4))-\(trozo(12, 4))-\(trozo(16, 4))-\(trozo(20, 12))"
    }

    /// Texto de la ficha.
    /// - Parameters:
    ///   - rolHumano: slug de la ficha del rol de la persona del área si existe (`comercial`); `nil`, sin enlace.
    ///   - semilla: para el `id` (el id de la empresa; vacío en el ejemplo).
    public static func texto(_ p: PerfilDeAsistente, rolHumano: String? = nil, semilla: String = "") -> String {
        var fm: [String] = [
            "---",
            "tls_type: role",
            "tls_schema: 1",
            "id: \(id(p.slug, semilla: semilla))",
            "nombre: \(p.nombre)",
            "clase: agente",
        ]
        if let rolHumano, let area = p.area,
           let nombreRol = CatalogoPrograma.deSerie.roles.first(where: { $0.area == area })?.nombre {
            fm.append("rol: \"[[\(rolHumano)|\(nombreRol)]]\"")
        }
        fm += [
            "areas: \(ConfigDeSerie.lista(p.clavesDeArea))",
            "lee_areas: \(ConfigDeSerie.lista(p.clavesQueLee))",
            "ocupante: \"\(p.autor)\"",
            "nivel: ejecucion",
            "pregunta: \(ConfigDeSerie.cadena(p.pregunta))",
            "sistemas: \(ConfigDeSerie.lista(p.sistemas))",
            "numeros: \(ConfigDeSerie.lista(p.numeros))",
            "plantilla: \"Rol de asistente v1\"",
            "---",
        ]
        var c: [String] = ["# \(p.nombre) (asistente)", "> \(cita(p))", ""]
        c.append("Esta ficha describe al asistente para que sepas qué esperar de él. Lo que puede hacer de verdad lo fija la configuración de la app: cambiar esta ficha no le da permisos.")
        c += ["", "## Misión", p.mision]
        c += ["", "## Decide sin preguntar"] + p.decideSolo.map { "- \($0)" }
        c += ["", "## Puede solo"] + p.puedeSolo.map { "- \($0)" }
        c += ["", "## Puede con tu OK"] + p.puedeConTuOK.map { "- \($0)" }
        c += ["", "## Nunca", "- Enviar, publicar, facturar, pagar o escribir a clientes sin tu OK"]
            + p.nunca.filter { !$0.hasPrefix("Enviar nada sin tu OK") }.map { "- \($0)" }
        c += ["", "## Qué recibe y qué entrega", p.entrega]
        c += ["", "## Cuándo te pregunta", p.escalado]
        c += ["", "## Escalera de autonomía",
              "| Lo que ves | Qué significa | Para subir al siguiente |",
              "|---|---|---|",
              "| Lo haces tú | Tú haces y el asistente mira | El paso escrito, hecho 3 veces a mano y un ejemplo que el asistente ya replica |",
              "| Te ayuda | Propone y tú eliges | 5 veces seguidas aprobadas sin cambios |",
              "| Lo hace y revisas | Lo hace y lo ves en el resumen | 20 veces con un 95 % sin cambios y 30 días sin incidencias |",
              "| Lo hace solo | Lo hace y lo apunta en la Bitácora | — |",
              "",
              "Se sube paso a paso, nunca el asistente entero, y siempre lo decides tú. Lo que sale de la empresa nunca pasa de «Siempre con tu OK»."]
        c += ["", "## Coste",
              "Tiene un tope de uso por trabajo y otro al mes. La app enseña el uso del mes como un porcentaje de tu tope, sacado de la Bitácora."]
        c += ["", "## Números"] + p.numeros.map { "- \($0) · \(indicador($0))" }
        c += ["", "## Sistemas"] + p.sistemas.map { "- \($0) · \(SistemaCatalogo.codigo($0)?.nombre ?? $0)" }
        c += ["", "## Rutinas"] + rutinas(p)
        c += ["", "## Instrucciones",
              "Su manual es la ficha de cada sistema que lleva, con sus «Notas para el asistente» y sus ejemplos. Las instrucciones de su rol vienen con la app. No tiene memoria oculta: lo que aprende te lo propone como mejora de la ficha del sistema, y entra cuando lo apruebas."]
        return (fm + c).joined(separator: "\n") + "\n"
    }

    /// Línea de cita: «Dirección · coordina a los demás asistentes · «¿Estamos yendo a donde dijimos?»».
    static func cita(_ p: PerfilDeAsistente) -> String {
        var partes: [String] = [p.area?.nombre ?? "Buzón"]
        if p.coordinador { partes.append("coordina a los demás asistentes") }
        if p.leeTodas { partes.append("lee todas las áreas") }
        partes.append(p.activacion.explicacion.replacingOccurrences(of: ".", with: "").lowercased())
        partes.append("«\(p.pregunta)»")
        return partes.joined(separator: " · ")
    }

    static func indicador(_ codigo: String) -> String {
        TextosPuesta.llano(CatalogoPrograma.deSerie.kpi(codigo)?.indicador ?? codigo)
    }

    /// Las rutinas y los avisos de serie, en palabras.
    static func rutinas(_ p: PerfilDeAsistente) -> [String] {
        var l = p.rutinas.map { r -> String in
            let extra = r.soloSiHayRojo ? " (solo si hay algo en rojo)" : ""
            return "- \(r.nombre) · \(cuando(r))\(extra)"
        }
        l += p.disparadores.map { "- \($0.resumen)" }
        return l.isEmpty ? ["- Sin rutinas: trabaja cuando se lo pides."] : l
    }

    /// «de lunes a viernes a las 08:45», «los lunes a las 10:00», «el día 5 de cada mes a las 09:00»…
    public static func cuando(_ r: RutinaDeAsistente) -> String {
        let hora = "a las \(r.horaTexto)"
        if let d = r.diaDelMes {
            if !r.meses.isEmpty {
                let nombres = r.meses.sorted().map { meses[$0 - 1] }
                return "el día \(d) de \(enumerar(nombres)) \(hora)"
            }
            return "el día \(d) de cada mes \(hora)"
        }
        if r.dias == DiaSemana.laborables { return "de lunes a viernes \(hora)" }
        if r.dias == Set(DiaSemana.allCases) { return "cada día \(hora)" }
        let nombres = r.dias.sorted().map { ["lunes", "martes", "miércoles", "jueves", "viernes", "sábados", "domingos"][$0.rawValue - 1] }
        return "los \(enumerar(nombres)) \(hora)"
    }

    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                        "octubre", "noviembre", "diciembre"]

    static func enumerar(_ xs: [String]) -> String {
        guard xs.count > 1 else { return xs.first ?? "" }
        return xs.dropLast().joined(separator: ", ") + " y " + xs.last!
    }

}
