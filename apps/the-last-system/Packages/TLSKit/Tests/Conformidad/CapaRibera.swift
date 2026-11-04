import Foundation
import TLSCore

/// La capa hecha a mano del ejemplo de Ribera (F4 · rol «roles»): lo que tiene `App/Recursos/Ejemplos/Asesoria-Ribera`
/// además de lo que da `tls-tool convertir-g2`. Así la conformidad sigue comprobando que el ejemplo **es** la conversión
/// de G2 más exactamente estos retoques, y nada más:
///
/// - **añadidos**: los asistentes (fichas de rol `asistente-*.md` y la Bitácora de octubre, que no existen en G2);
/// - **ampliados**: ficheros de la conversión a los que solo se añaden líneas (`estado:` de cada `Área.md` y los
///   asistentes de `.tls/config.yaml`); las líneas de la conversión siguen todas, en orden;
/// - **renombrados** y **sustituciones**: los pendientes de F2 (palabras del glosario) y la fecha de la propuesta de
///   Javier Ortega (12/10), que da el seguimiento del día 7 del ejemplo.
///
/// Con `TLS_ACTUALIZAR_GOLDEN=1`, regenerar Ribera aplica esta capa a la conversión y conserva lo añadido y ampliado.
enum CapaRibera {
    static let roles = "6 · Equipo/Roles/"
    static let anadidos: [String] = ["6 · Equipo/Bitácora/2026-10.md"]
        + ["mika", "comercial", "implementador", "contable", "marca", "equipo", "cartero", "ordenador"].map { roles + "asistente-\($0).md" }

    static let ampliados: [String] = [".tls/config.yaml"]
        + ["1 · Dirección", "2 · Ventas", "3 · Entrega", "4 · Finanzas", "5 · Marca", "6 · Equipo"].map { "\($0)/Área.md" }

    static let renombrados: [(de: String, a: String)] = [
        // F4 · corrector (revisión de experiencia, P1): la decisión de ejemplo ya no propone saltarse la línea roja.
        ("6 · Equipo/Tareas/t-0002-dejar-que-el-agente-comercial-envie-recordatorios-de.md",
         "6 · Equipo/Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md"),
    ]

    static let oportunidades = "2 · Ventas/Oportunidades/"

    /// (ruta, de, a): cada `de` tiene que estar en la conversión.
    static let sustituciones: [(ruta: String, de: String, a: String)] = {
        var s: [(String, String, String)] = [
            // Glosario: «asistente», no agente; sin «runway».
            ("Empresa.md", "| Personas y agentes en capacidad |", "| Personas y asistentes en capacidad |"),
            ("1 · Dirección/Metas.md", "| Coste de agentes del mes |", "| Coste de los asistentes del mes |"),
            ("1 · Dirección/Metas.md", "| Agentes sanos |", "| Asistentes sanos |"),
            ("1 · Dirección/Metas.md", "| Meses de caja (runway) |", "| Meses de caja |"),
            ("1 · Dirección/Metas.md", "agentes sin fallo en su última ejecución / agentes de área",
             "asistentes sin fallo en su último trabajo / asistentes de área"),
            ("6 · Equipo/Área.md", "Personas y agentes en capacidad", "Personas y asistentes en capacidad"),
            ("6 · Equipo/Área.md",
             "[T-0002 · ¿Dejar que el agente Comercial envíe recordatorios de propuesta sin aprobación?](Tareas/t-0002-dejar-que-el-agente-comercial-envie-recordatorios-de.md)",
             "[T-0002 · ¿Dejar que Comercial prepare los recordatorios de propuesta con plantilla?](Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md)"),
            (roles + "responsable-de-equipo.md", "Capacidad suficiente y sana entre personas y agentes.",
             "Capacidad suficiente y sana entre personas y asistentes."),
            (roles + "responsable-de-equipo.md", "Asignación de roles, presupuestos de agentes.",
             "Asignación de roles, topes de uso de los asistentes."),
            (roles + "responsable-de-equipo.md", "Horas humanas y ejecuciones de agentes se miden por separado.",
             "Las horas de las personas y los trabajos de los asistentes se miden por separado."),
            (roles + "responsable-de-equipo.md", "- EQU-HEALTH · Agentes sanos", "- EQU-HEALTH · Asistentes sanos"),
            (roles + "responsable-de-equipo.md", "Salud de agentes, coste, rutinas caídas y roles vacantes.",
             "Salud de los asistentes, uso, rutinas caídas y roles vacantes."),
            (roles + "financiero.md", "- FIN-RUNWAY · Meses de caja (runway)", "- FIN-RUNWAY · Meses de caja"),
            ("6 · Equipo/Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md",
             "¿Dejar que el agente Comercial envíe recordatorios de propuesta sin aprobación?",
             "¿Dejar que Comercial prepare los recordatorios de propuesta con plantilla?"),
            ("6 · Equipo/Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md",
             "Hoy cada seguimiento requiere aprobación (VEN-08 supervisado). Proponer límites: solo plantillas aprobadas, máximo 2 toques, nunca a contactos dados de baja.",
             "Hoy Comercial prepara cada recordatorio de propuesta por separado y lo apruebas uno a uno. La idea: que los prepare con la plantilla que ya aprobaste a los 7 y a los 14 días, como mucho dos por propuesta y nunca a quien pidió no recibir más, y te los deje juntos para que los apruebes de una vez. Enviar seguirá pidiendo tu OK."),
        ]
        // La propuesta de Javier Ortega salió el 12/10: el lunes 19 toca su seguimiento del día 7 (lo que ya simulaban
        // las pruebas de Ventas; el Comercial lo prepara en la grabación de Ribera).
        let javier = oportunidades + "javier-ortega-renta/Propuesta v1.md"
        s.append((javier, "fecha: 2026-10-19\nvalida_hasta: 2026-11-18\n", "fecha: 2026-10-12\nvalida_hasta: 2026-11-11\n"))
        s.append((javier, "válida hasta el 18 nov", "válida hasta el 11 nov"))
        return s
    }()

    /// La conversión con los renombrados y las sustituciones (los añadidos y ampliados no se pueden generar).
    static func aplicar(_ conversion: [String: Data]) -> (arbol: [String: Data], problemas: [String]) {
        var a = conversion
        var problemas: [String] = []
        for (de, aRuta) in renombrados {
            guard let d = a.removeValue(forKey: de) else { problemas.append("no está para renombrar: \(de)"); continue }
            a[aRuta] = d
        }
        for (ruta, de, por) in sustituciones {
            guard let d = a[ruta], let t = String(data: d, encoding: .utf8) else { problemas.append("no está: \(ruta)"); continue }
            guard t.contains(de) else { problemas.append("\(ruta): ya no dice «\(de.prefix(60))»"); continue }
            a[ruta] = Data(t.replacingOccurrences(of: de, with: por).utf8)
        }
        return (a, problemas)
    }

    /// Lo que no cuadra entre la conversión (con la capa) y el ejemplo.
    static func diferencias(conversion: [String: Data], ejemplo: [String: Data]) -> [String] {
        let (a, problemas) = aplicar(conversion)
        var out = problemas
        for ruta in Set(a.keys).union(ejemplo.keys).sorted() {
            switch (a[ruta], ejemplo[ruta]) {
            case (nil, _?):
                if !anadidos.contains(ruta) { out.append("sobra \(ruta)") }
            case (_?, nil):
                out.append("falta \(ruta)")
            case (let c?, let e?):
                if anadidos.contains(ruta) { out.append("\(ruta) ya sale de la conversión: quítalo de los añadidos") }
                if ampliados.contains(ruta) {
                    if !esSubsecuencia(lineas(c), de: lineas(e)) { out.append("\(ruta) ya no contiene la conversión entera") }
                } else if c != e {
                    out.append("cambia \(ruta)")
                }
            default:
                break
            }
        }
        for r in anadidos where ejemplo[r] == nil { out.append("falta el añadido \(r)") }
        return out
    }

    /// El ejemplo que tocaría con esta conversión: la capa aplicada, y lo añadido o ampliado tal como está.
    static func ejemploRegenerado(conversion: [String: Data], ejemplo: [String: Data]) -> [String: Data] {
        var a = aplicar(conversion).arbol
        for r in anadidos + ampliados { if let e = ejemplo[r] { a[r] = e } }
        return a
    }

    static func lineas(_ d: Data) -> [Substring] {
        String(decoding: d, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Todas las líneas de `a`, en orden, dentro de `b`.
    static func esSubsecuencia(_ a: [Substring], de b: [Substring]) -> Bool {
        var i = a.startIndex
        for l in b where i < a.endIndex && l == a[i] { i += 1 }
        return i == a.endIndex
    }
}
