import Foundation

/// Lo que dice una incrustación de una nota sobre el fichero que enseña, como Obsidian:
/// `![[factura-2026-014.pdf#page=3]]`, `![[acta.pdf#page=2&height=500]]`, `![[logo.png|300]]`,
/// `![](Materiales/acta%20final.pdf#page=2)`.
///
/// El texto de la nota no cambia nunca: la incrustación es un enlace normal. TLSUI resuelve `destino` a una
/// ruta de la carpeta (con las mismas reglas que cualquier enlace) y pasa la URL al visor.
public struct ReferenciaIncrustada: Sendable, Hashable {
    /// Destino sin el fragmento (`#…`) ni el tamaño (`|…`), tal como hay que resolverlo.
    public let destino: String
    /// Página de un PDF (1 = la primera), de `#page=N`.
    public let pagina: Int?
    /// Alto del bloque en puntos, de `#height=N` (PDF) o `|AxB` (imagen).
    public let alto: CGFloat?
    /// Ancho en puntos de una imagen, de `|300` o `|300x200`.
    public let ancho: CGFloat?
    /// Lo que va tras `#` cuando no es `page` ni `height` (una sección).
    public let seccion: String?

    public init(destino: String, pagina: Int? = nil, alto: CGFloat? = nil, ancho: CGFloat? = nil, seccion: String? = nil) {
        self.destino = destino; self.pagina = pagina; self.alto = alto; self.ancho = ancho; self.seccion = seccion
    }

    /// Tipo de fichero por la extensión del destino.
    public var tipo: TipoFichero { TipoFichero.de(nombre: destino) }

    /// Lee lo de dentro de `![[…]]` (wikilink) o el destino de `![](…)` (Markdown, con `%20`).
    public static func leer(_ texto: String, markdown: Bool = false) -> ReferenciaIncrustada {
        var t = texto.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("![[") { t.removeFirst(3) } else if t.hasPrefix("[[") { t.removeFirst(2) }
        if t.hasSuffix("]]") { t.removeLast(2) }
        if markdown, t.hasPrefix("<"), t.hasSuffix(">") { t = String(t.dropFirst().dropLast()) }

        // `|300` o `|300x200` (tamaño de imagen) o `|Texto` (alias, se ignora).
        var ancho: CGFloat?
        var alto: CGFloat?
        if !markdown, let barra = t.firstIndex(of: "|") {
            let tras = String(t[t.index(after: barra)...]).trimmingCharacters(in: .whitespaces)
            t = String(t[..<barra])
            let partes = tras.lowercased().split(separator: "x", omittingEmptySubsequences: false)
            if let a = partes.first.flatMap({ Double($0) }), a > 0 {
                ancho = CGFloat(a)
                if partes.count == 2, let b = Double(partes[1]), b > 0 { alto = CGFloat(b) }
            }
        }

        var pagina: Int?
        var seccion: String?
        if let almohadilla = t.firstIndex(of: "#") {
            let fragmento = String(t[t.index(after: almohadilla)...])
            t = String(t[..<almohadilla])
            var resto: [String] = []
            for parte in fragmento.split(separator: "&") {
                let kv = parte.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if kv.count == 2, kv[0].lowercased() == "page", let n = Int(kv[1]), n > 0 {
                    pagina = n
                } else if kv.count == 2, kv[0].lowercased() == "height", let h = Double(kv[1]), h > 0 {
                    alto = CGFloat(h)
                } else {
                    resto.append(String(parte))
                }
            }
            if !resto.isEmpty { seccion = resto.joined(separator: "&") }
        }
        var destino = t.trimmingCharacters(in: .whitespaces)
        if markdown { destino = destino.removingPercentEncoding ?? destino }
        return ReferenciaIncrustada(destino: destino, pagina: pagina, alto: alto, ancho: ancho, seccion: seccion)
    }
}
