import Foundation

/// Nombres de fichero de las fichas (SISTEMAS.md §1.7): kebab ASCII de 60 caracteres como máximo,
/// nombres de fichero seguros y enlaces legibles para propiedades y cuerpo.
public enum NombresDeFicha {
    /// «Talleres Martín e Hijos» → `talleres-martin-e-hijos` (como mucho `maximo` caracteres, cortando por un guion).
    public static func slug(_ texto: String, maximo: Int = 60) -> String {
        let plegado = texto.precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
        var out = ""
        var guion = false
        for u in plegado.unicodeScalars {
            if u.isASCII, CharacterSet.alphanumerics.contains(u) {
                out.unicodeScalars.append(u); guion = false
            } else if !out.isEmpty, !guion {
                out.append("-"); guion = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return recortar(out, maximo: maximo)
    }

    /// Corta un slug largo por el último guion que deje al menos la mitad.
    public static func recortar(_ slug: String, maximo: Int) -> String {
        guard slug.count > maximo else { return slug }
        let corto = String(slug.prefix(maximo))
        if let g = corto.lastIndex(of: "-"), corto.distance(from: corto.startIndex, to: g) >= maximo / 2 {
            return String(corto[..<g])
        }
        return corto.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Nombre de fichero seguro conservando tildes y espacios (sin `/ : \ # ^ [ ] |` ni saltos).
    public static func fichero(_ texto: String) -> String {
        // `/ : \` no valen en un nombre; con `# ^ [ ] |` los enlaces de Obsidian dejan de funcionar.
        let prohibidos = CharacterSet(charactersIn: "/:\\\n\r\t#^[]|")
        var limpio = texto.unicodeScalars.map { prohibidos.contains($0) ? " " : String($0) }.joined()
        limpio = limpio.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        while limpio.hasPrefix(".") { limpio.removeFirst() }
        return limpio.precomposedStringWithCanonicalMapping
    }

    /// Texto visible de un wikilink (sin `|` ni corchetes que lo rompan).
    public static func textoDeWikilink(_ texto: String) -> String {
        texto.replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    /// Destino de wikilink para una nota: su nombre si es único en la carpeta; si no, la ruta sin `.md`.
    public static func destinoWiki(_ ruta: VaultPath, en snapshot: VaultSnapshot) -> String {
        let key = TextFolding.nameKey(ruta.stem)
        let repetidos = snapshot.files.filter { WikiTarget.isNote($0) && TextFolding.nameKey($0.stem) == key }.count
        if repetidos <= 1 { return ruta.stem }
        return WikiTarget.isNote(ruta) ? String(ruta.raw.dropLast(ruta.ext.count + 1)) : ruta.raw
    }

    /// `[[slug|Nombre]]` para una propiedad (decisión 1 de SISTEMAS.md).
    public static func wikilink(_ ruta: VaultPath, nombre: String, en snapshot: VaultSnapshot) -> String {
        let destino = destinoWiki(ruta, en: snapshot)
        let visible = textoDeWikilink(nombre)
        return visible == destino ? "[[\(destino)]]" : "[[\(destino)|\(visible)]]"
    }

    /// `[Nombre](ruta relativa)` para el cuerpo, el estilo de G3 (`%20` en los espacios).
    public static func enlaceMarkdown(_ nombre: String, desde origen: VaultPath, a destino: VaultPath) -> String {
        let visible = nombre.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        let rel = MarkdownDestination.relativeComponents(from: origen, to: destino)
            .map { MarkdownDestination.encode($0, style: .init()) }.joined(separator: "/")
        return "[\(visible)](\(rel))"
    }
}
