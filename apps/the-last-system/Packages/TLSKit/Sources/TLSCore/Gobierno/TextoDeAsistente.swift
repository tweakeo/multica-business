import Foundation

// F4 · corrector final (revisión de seguridad R3). Lo que escribe un asistente en el cuerpo de una ficha (Actividad,
// secciones, descripción, resumen de cierre) nunca puede parecer estructura de la app: un encabezado de entrada
// (`### 2026-10-19 10:05 · Manu`), una sección (`## Actividad`), un comentario de la app (`<!-- tls:evento … -->`) o un
// separador. Si pudiera, un asistente escribiría «como la persona»: una mención que despierta a otro asistente con la
// voz de Manu, o la respuesta a su propia pregunta. Se escapa el primer carácter (Obsidian lo enseña igual, como
// texto) y los comentarios HTML en cualquier sitio de la línea.

public enum TextoDeAsistente {
    /// El texto con cada línea que empieza por `#`, `<!--`, `---`/`===` (o `>` seguido de `Guía:`) escapada, y sin
    /// comentarios HTML abiertos o cerrados en medio de una línea.
    public static func neutralizar(_ texto: String) -> String {
        var lineas: [String] = []
        for linea in texto.components(separatedBy: "\n") {
            lineas.append(neutralizarLinea(linea))
        }
        return lineas.joined(separator: "\n")
    }

    /// Una sola línea (títulos y frases): sin saltos de línea y neutralizada.
    public static func linea(_ texto: String) -> String {
        let una = texto.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        return neutralizarLinea(una)
    }

    /// Idempotente: lo ya escapado no se vuelve a escapar.
    static func neutralizarLinea(_ linea: String) -> String {
        var l = linea.replacingOccurrences(of: #"(?<!\\)<!--"#, with: #"\\<!--"#, options: .regularExpression)
            .replacingOccurrences(of: "-->", with: "--\\>")
        let sangria = l.prefix { $0 == " " || $0 == "\t" }
        let resto = l.dropFirst(sangria.count)
        if resto.hasPrefix("#") || resto.hasPrefix("> Guía:") || resto.hasPrefix(">Guía:") {
            l = String(sangria) + "\\" + resto
        } else if resto.count >= 3, resto.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == "-" || $0 == "=" }) {
            l = String(sangria) + "\\" + resto
        }
        return l
    }

    /// `true` si el texto ya no lleva nada que se lea como estructura de la app.
    public static func esNeutro(_ texto: String) -> Bool { neutralizar(texto) == texto }
}
