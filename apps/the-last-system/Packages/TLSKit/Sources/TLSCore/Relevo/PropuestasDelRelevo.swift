import Foundation

/// Paso 7 del relevo (PLAN §4.7 «Choque con tus textos» y §9 F6): una nota en `Buzón/` con lo que convendría cambiar y
/// **no se aplica**: el parche de `validar.py` (que admita casillas `- [ ]` en `Tareas/` y en `## Descripción`) y los
/// textos de `Empresa.md` y `AGENTS.md` que aún dicen que las tareas viven en `Tareas.md`.
///
/// `validar.py` vive en tu vault personal, fuera de la carpeta: aquí no se lee ni se toca; se deja el parche preparado.
public enum PropuestasDelRelevo {
    /// Una línea de un texto tuyo y cómo quedaría.
    public struct CambioDeTexto: Sendable, Hashable {
        public let fichero: String
        public let linea: Int
        public let antes: String
        public let despues: String
    }

    /// Nombre de la nota: «Propuestas del relevo AAAA-MM-DD.md».
    public static func nombre(_ hoy: LocalDate) -> String { "Propuestas del relevo \(hoy.description).md" }

    /// Líneas que mencionan `Tareas.md` (las tareas ahora son fichas en la carpeta `Tareas/` de cada área).
    public static func cambios(en texto: String?, fichero: String) -> [CambioDeTexto] {
        guard let texto else { return [] }
        var out: [CambioDeTexto] = []
        for (i, linea) in texto.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let l = String(linea)
            guard l.range(of: "Tareas.md", options: [.caseInsensitive]) != nil else { continue }
            let nueva = l.replacingOccurrences(of: "`Tareas.md`", with: "la carpeta `Tareas/` de cada área (una ficha por tarea)")
                .replacingOccurrences(of: "[[Tareas]]", with: "la carpeta Tareas/ de cada área (una ficha por tarea)")
                .replacingOccurrences(of: "Tareas.md", with: "la carpeta Tareas/ de cada área (una ficha por tarea)",
                                      options: [.caseInsensitive])
            out.append(CambioDeTexto(fichero: fichero, linea: i + 1, antes: l, despues: nueva))
        }
        return out
    }

    /// Texto de la nota. `empresa` y `agentes`: el texto actual de `Empresa.md` y `AGENTS.md` de la real (`nil` si no
    /// existe o está solo en iCloud: entonces se dice).
    public static func nota(hoy: LocalDate, empresa: String?, agentes: String?, soloEnICloud: [String] = []) -> String {
        var s = """
            # Propuestas del relevo \(hoy.description)

            Al pasar la copia a tu carpeta real he preparado estos cambios. **No he aplicado ninguno**: revísalos y, si te \
            parecen bien, cópialos tú.

            ## Textos de Empresa.md y AGENTS.md

            Las tareas ya no viven en `Tareas.md`: cada tarea es una ficha en la carpeta `Tareas/` de su área.

            """
        for (fichero, texto) in [("Empresa.md", empresa), ("AGENTS.md", agentes)] {
            s += "\n### \(fichero)\n\n"
            if soloEnICloud.contains(fichero) {
                s += "Está solo en iCloud: no lo he abierto para no descargarlo. Revísalo tú.\n"
                continue
            }
            guard texto != nil else {
                s += "No está en tu carpeta real: no hace falta cambiar nada.\n"
                continue
            }
            let c = cambios(en: texto, fichero: fichero)
            if c.isEmpty {
                s += "No menciona `Tareas.md`: no hace falta cambiar nada.\n"
                continue
            }
            for x in c {
                s += "- Línea \(x.linea)\n  - Ahora: \(x.antes.trimmingCharacters(in: .whitespaces))\n"
                s += "  - Propuesta: \(x.despues.trimmingCharacters(in: .whitespaces))\n"
            }
        }
        s += """

            ## Parche de validar.py

            `validar.py` (en tu vault personal) da por error una casilla `- [ ]` fuera de `Tareas.md` (hacia la línea 53). \
            Con las tareas como fichas, conviene que admita también las casillas de las notas dentro de una carpeta \
            `Tareas/` y las de la sección `## Descripción`. Este es el cambio que te propongo (adáptalo a cómo se llama \
            la comprobación en tu fichero):

            ```diff
            -    if casilla and not ruta.endswith("Tareas.md"):
            -        errores.append((ruta, n, "casilla fuera de Tareas.md"))
            +    if casilla and not casilla_permitida(ruta, seccion_actual):
            +        errores.append((ruta, n, "casilla fuera de Tareas/ o de ## Descripción"))
            +
            +def casilla_permitida(ruta, seccion):
            +    partes = ruta.replace("\\\\", "/").split("/")
            +    return (ruta.endswith("Tareas.md")
            +            or "Tareas" in partes[:-1]
            +            or (seccion or "").strip() == "Descripción")
            ```

            """
        return s
    }
}
