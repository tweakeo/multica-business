import Foundation

/// Secciones `## Nombre` del cuerpo de una nota, para añadir o sustituir sin tocar el resto.
///
/// Una sección va desde su encabezado hasta el siguiente de su nivel o superior (o el final).
/// Los encabezados dentro de bloques de código no cuentan. El nombre se compara sin tildes ni
/// mayúsculas («Descripción» = «descripcion»).
public enum MarkdownSections {
    public struct Section: Sendable, Hashable {
        public let level: Int
        public let title: String
        /// Índice (en las líneas del cuerpo) del encabezado.
        let headingLine: Int
        /// Líneas de contenido: de la siguiente al encabezado hasta antes del siguiente encabezado.
        let contentLines: Range<Int>
        /// Fin del contenido sin las líneas en blanco del final.
        let lastContentLine: Int?
    }

    /// Encabezado ATX (`#` a `######`, hasta 3 espacios delante). Devuelve nivel y título.
    static func heading(_ line: String) -> (level: Int, title: String)? {
        var s = Substring(line)
        var spaces = 0
        while s.first == " ", spaces < 3 { s = s.dropFirst(); spaces += 1 }
        var level = 0
        while s.first == "#" { level += 1; s = s.dropFirst() }
        guard (1...6).contains(level) else { return nil }
        guard s.isEmpty || s.first == " " || s.first == "\t" else { return nil }
        var title = s.trimmingCharacters(in: .whitespaces)
        if title.allSatisfy({ $0 == "#" }) {
            title = ""
        } else if let r = title.range(of: #"[ \t]+#+[ \t]*$"#, options: .regularExpression) {
            title.removeSubrange(r)
        }
        return (level, title.trimmingCharacters(in: .whitespaces))
    }

    /// Secciones de un cuerpo (líneas ya separadas).
    static func sections(_ lines: [TextLine]) -> [Section] {
        var heads: [(Int, Int, String)] = []
        var fence: CodeFence?
        for (i, l) in lines.enumerated() {
            let trimmed = l.content.drop(while: { $0 == " " })
            if let f = fence {
                if f.closes(trimmed) { fence = nil }
                continue
            }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            if let h = heading(l.content) { heads.append((i, h.level, h.title)) }
        }
        var out: [Section] = []
        for (n, h) in heads.enumerated() {
            let end = heads[(n + 1)...].first(where: { $0.1 <= h.1 })?.0 ?? lines.count
            let content = (h.0 + 1)..<end
            let last = content.reversed().first(where: { !lines[$0].isBlank })
            out.append(Section(level: h.1, title: h.2, headingLine: h.0, contentLines: content, lastContentLine: last))
        }
        return out
    }

    static func find(_ name: String, in lines: [TextLine], level: Int? = nil) -> Section? {
        let key = TextFolding.fold(name.trimmingCharacters(in: .whitespaces))
        return sections(lines).first { s in
            (level == nil || s.level == level) && TextFolding.fold(s.title) == key
        }
    }

    /// Títulos de las secciones del cuerpo, en orden.
    public static func titles(in body: String) -> [String] {
        sections(TextLines.split(body)).map(\.title)
    }

    /// Texto del contenido de una sección (sin el encabezado ni las líneas en blanco finales).
    public static func content(of name: String, in body: String, level: Int? = nil) -> String? {
        let lines = TextLines.split(body)
        guard let s = find(name, in: lines, level: level) else { return nil }
        guard let last = s.lastContentLine else { return "" }
        return TextLines.join(Array(lines[s.contentLines.lowerBound...last]))
    }

    /// Huella del contenido de una sección (la que espera `replaceSection`).
    public static func hash(of name: String, in body: String, level: Int? = nil) -> String? {
        content(of: name, in: body, level: level).map(ContentHash.of)
    }

    /// Añade `text` al final de una sección (tras su última línea con texto). Si la sección no
    /// existe y `create` es `true`, se crea al final del cuerpo con encabezado de nivel 2.
    /// `blankLine`: deja una línea en blanco entre lo que había y lo nuevo.
    static func append(to name: String, in body: String, text: String, blankLine: Bool, create: Bool,
                       eol: String) throws -> String {
        var lines = TextLines.split(body)
        let addition = TextLines.split(TextLines.terminated(text, eol: eol))
        guard let s = find(name, in: lines) else {
            guard create else { throw WriteError.seccionNoEncontrada(name) }
            if let i = lines.indices.last, lines[i].eol.isEmpty { lines[i].eol = eol }
            var tail: [TextLine] = []
            // Una línea en blanco entre lo anterior y la sección nueva (si no la había ya).
            if let lastText = lines.lastIndex(where: { !$0.isBlank }), lastText == lines.count - 1 {
                tail.append(TextLine(content: "", eol: eol))
            }
            tail.append(TextLine(content: "## " + name, eol: eol))
            if blankLine { tail.append(TextLine(content: "", eol: eol)) }
            return TextLines.join(lines + tail + addition)
        }
        let insertAt: Int
        var block = addition
        if let last = s.lastContentLine {
            if lines[last].eol.isEmpty { lines[last].eol = eol }
            insertAt = last + 1
            if blankLine { block.insert(TextLine(content: "", eol: eol), at: 0) }
        } else {
            // Sección vacía: justo debajo del encabezado.
            if lines[s.headingLine].eol.isEmpty { lines[s.headingLine].eol = eol }
            insertAt = s.headingLine + 1
            if blankLine { block.insert(TextLine(content: "", eol: eol), at: 0) }
        }
        lines.insert(contentsOf: block, at: insertAt)
        return TextLines.join(lines)
    }

    /// Sustituye el contenido de una sección si su huella es `baseHash`. Conserva el encabezado
    /// y las líneas en blanco que la separan de la siguiente.
    static func replace(_ name: String, in body: String, with text: String, baseHash: String, eol: String) throws -> String {
        var lines = TextLines.split(body)
        guard let s = find(name, in: lines) else { throw WriteError.seccionNoEncontrada(name) }
        let current: String = s.lastContentLine.map { TextLines.join(Array(lines[s.contentLines.lowerBound...$0])) } ?? ""
        guard ContentHash.of(current) == baseHash else { throw WriteError.seccionCambiada(name) }
        let replacement = TextLines.split(TextLines.terminated(text, eol: eol))
        if let last = s.lastContentLine {
            let hadEOL = !lines[last].eol.isEmpty
            var block = replacement
            // Al final del fichero sin salto: igual que estaba.
            if !hadEOL, let i = block.indices.last { block[i].eol = "" }
            lines.replaceSubrange(s.contentLines.lowerBound...last, with: block)
        } else {
            if lines[s.headingLine].eol.isEmpty { lines[s.headingLine].eol = eol }
            lines.insert(contentsOf: replacement, at: s.headingLine + 1)
        }
        return TextLines.join(lines)
    }

    /// Añade una línea tras la última línea con texto del cuerpo (las líneas en blanco del final se conservan).
    static func appendLine(_ line: String, to body: String, eol: String) -> String {
        var lines = TextLines.split(body)
        let new = TextLine(content: TextLines.normalized(line, eol: eol).trimmingCharacters(in: .newlines), eol: eol)
        guard let last = lines.lastIndex(where: { !$0.isBlank }) else {
            return TextLines.join(lines + [new])
        }
        if lines[last].eol.isEmpty {
            lines[last].eol = eol
            lines.insert(TextLine(content: new.content, eol: ""), at: last + 1)
        } else {
            lines.insert(new, at: last + 1)
        }
        return TextLines.join(lines)
    }
}
