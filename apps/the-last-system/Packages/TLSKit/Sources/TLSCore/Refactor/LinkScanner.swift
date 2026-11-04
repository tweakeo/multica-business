import Foundation

/// Un enlace escrito en un texto, con la posición exacta (bytes UTF-8, sin BOM) de su destino:
/// lo que hace falta para cambiar solo el destino y dejar el resto byte a byte.
public struct LinkOccurrence: Sendable, Hashable {
    public enum Lugar: Sendable, Hashable {
        case cuerpo
        /// Dentro de las propiedades, en esa clave.
        case propiedad(String)
    }

    /// Comillas YAML que rodean el enlace (solo en propiedades).
    public enum Comillas: Sendable, Hashable { case ninguna, dobles, simples }

    public let link: ParsedLink
    /// El enlace completo (`[texto](ruta)`, `[[nota|alias]]`…).
    public let range: Range<Int>
    /// Destino escrito: en Markdown la ruta (sin `<…>` ni `#sección`); en un wikilink, la nota
    /// (sin `#sección` ni `|alias`).
    public let targetRange: Range<Int>
    /// Texto visible: `[texto]` o el alias de `[[nota|alias]]`.
    public let labelRange: Range<Int>?
    /// Destino Markdown entre `<…>`.
    public let angle: Bool
    public let lugar: Lugar
    public let comillas: Comillas
    /// Línea (desde 1).
    public let line: Int
    /// Definición de referencia (`[id]: ruta`).
    public let isReference: Bool
}

/// Encuentra los enlaces de una nota con su posición: wikilinks (`[[x]]`, `[[x|alias]]`,
/// `[[x#sección]]`, `![[x]]`, también `[[x\|alias]]` dentro de tablas), enlaces Markdown
/// (`[t](ruta)`, `[t](<ruta con espacios>)`, `![t](imagen)`, con título) y definiciones de
/// referencia. Lee también los enlaces de las propiedades. Igual que `LinkParser`, no mira dentro
/// de bloques ni fragmentos de código.
public enum LinkScanner {
    static let backslash = UInt8(ascii: "\\")
    static let backtick = UInt8(ascii: "`")
    static let open = UInt8(ascii: "[")
    static let close = UInt8(ascii: "]")
    static let bang = UInt8(ascii: "!")
    static let lparen = UInt8(ascii: "(")
    static let rparen = UInt8(ascii: ")")
    static let lt = UInt8(ascii: "<")
    static let gt = UInt8(ascii: ">")
    static let bar = UInt8(ascii: "|")
    static let hash = UInt8(ascii: "#")
    static let space = UInt8(ascii: " ")
    static let tab = UInt8(ascii: "\t")
    static let colon = UInt8(ascii: ":")
    static let dquote = UInt8(ascii: "\"")
    static let squote = UInt8(ascii: "'")

    struct LineSpan { var start: Int; var end: Int }

    /// Líneas (sin el salto): `\n`, `\r\n` y `\r`.
    static func lines(_ b: [UInt8]) -> [LineSpan] {
        var out: [LineSpan] = []
        var start = 0
        var i = 0
        while i < b.count {
            if b[i] == 0x0A {
                out.append(LineSpan(start: start, end: i)); i += 1; start = i
            } else if b[i] == 0x0D {
                out.append(LineSpan(start: start, end: i))
                i += (i + 1 < b.count && b[i + 1] == 0x0A) ? 2 : 1
                start = i
            } else {
                i += 1
            }
        }
        if start < b.count { out.append(LineSpan(start: start, end: b.count)) }
        return out
    }

    static func string(_ b: [UInt8], _ r: Range<Int>) -> String {
        String(decoding: b[r], as: UTF8.self)
    }

    static func trimmed(_ b: [UInt8], _ r: Range<Int>) -> Range<Int> {
        var s = r.lowerBound, e = r.upperBound
        while s < e, b[s] == space || b[s] == tab { s += 1 }
        while e > s, b[e - 1] == space || b[e - 1] == tab { e -= 1 }
        return s..<e
    }

    static func isDelimiterLine(_ b: [UInt8], _ l: LineSpan, allowDots: Bool) -> Bool {
        let t = string(b, trimmed(b, l.start..<l.end))
        return t == "---" || (allowDots && t == "...")
    }

    /// Líneas del bloque de propiedades (sin delimitadores) y línea de cierre, si lo hay.
    /// Misma regla que `FrontmatterDocument`: `---` con salto en la primera línea y otra `---` o `...`.
    static func frontmatter(_ b: [UInt8], _ ls: [LineSpan]) -> (yaml: Range<Int>, closing: Int)? {
        guard let first = ls.first, first.end < b.count, isDelimiterLine(b, first, allowDots: false) else { return nil }
        for i in 1..<ls.count where isDelimiterLine(b, ls[i], allowDots: true) {
            return (1..<i, i)
        }
        return nil
    }

    // MARK: Lectura

    public static func scan(_ text: String) -> [LinkOccurrence] {
        let b = Array(text.utf8)
        let ls = lines(b)
        var out: [LinkOccurrence] = []
        var bodyStart = 0
        if let fm = frontmatter(b, ls) {
            var key = ""
            for i in fm.yaml {
                let l = ls[i]
                if let k = topLevelKey(b, l) { key = k }
                scanInline(b, l, line: i + 1, lugar: .propiedad(key), yaml: true, into: &out)
            }
            bodyStart = fm.closing + 1
        }
        var fence: CodeFence?
        for i in bodyStart..<max(bodyStart, ls.count) {
            let l = ls[i]
            var j = l.start
            while j < l.end, b[j] == space || b[j] == tab { j += 1 }
            let trimmed = string(b, j..<l.end)
            if let f = fence {
                if f.closes(trimmed) { fence = nil }
                continue
            }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            if let ref = referenceDefinition(b, l, line: i + 1) { out.append(ref); continue }
            scanInline(b, l, line: i + 1, lugar: .cuerpo, yaml: false, into: &out)
        }
        return out
    }

    static func hasPrefix(_ b: [UInt8], _ i: Int, _ end: Int, _ p: [UInt8]) -> Bool {
        guard end - i >= p.count else { return false }
        for k in 0..<p.count where b[i + k] != p[k] { return false }
        return true
    }

    /// Nombre de la clave si la línea es `clave: …` en la columna 0.
    static func topLevelKey(_ b: [UInt8], _ l: LineSpan) -> String? {
        guard l.start < l.end, b[l.start] != space, b[l.start] != tab, b[l.start] != hash,
              b[l.start] != UInt8(ascii: "-") else { return nil }
        let line = string(b, l.start..<l.end)
        return FrontmatterDocument.parseKeyLine(line)?.name
    }

    /// `[id]: ruta "título"` al principio de la línea (hasta 3 espacios). Las notas al pie (`[^1]:`) no cuentan.
    static func referenceDefinition(_ b: [UInt8], _ l: LineSpan, line: Int) -> LinkOccurrence? {
        var i = l.start
        var spaces = 0
        while i < l.end, b[i] == space, spaces < 3 { i += 1; spaces += 1 }
        guard i < l.end, b[i] == open, i + 1 < l.end, b[i + 1] != UInt8(ascii: "^"), b[i + 1] != open else { return nil }
        var j = i + 1
        while j < l.end, b[j] != close {
            if b[j] == backslash { j += 2; continue }
            if b[j] == open { return nil }
            j += 1
        }
        guard j < l.end, j > i + 1, j + 1 < l.end, b[j + 1] == colon else { return nil }
        let label = (i + 1)..<j
        var k = j + 2
        while k < l.end, b[k] == space || b[k] == tab { k += 1 }
        guard k < l.end else { return nil }
        var dest: Range<Int>
        var angle = false
        if b[k] == lt {
            guard let g = (k + 1..<l.end).first(where: { b[$0] == gt }) else { return nil }
            dest = (k + 1)..<g; angle = true
        } else {
            var e = k
            while e < l.end, b[e] != space, b[e] != tab { e += 1 }
            dest = k..<e
        }
        return markdownOccurrence(b, whole: l.start..<l.end, label: label, dest: dest, angle: angle, embed: false,
                                  line: line, lugar: .cuerpo, comillas: .ninguna, reference: true)
    }

    /// Recorre una línea buscando enlaces (en propiedades, `yaml` = true: sin fragmentos de código
    /// y con seguimiento de comillas YAML).
    static func scanInline(_ b: [UInt8], _ l: LineSpan, line: Int, lugar: LinkOccurrence.Lugar, yaml: Bool,
                           into out: inout [LinkOccurrence]) {
        var i = l.start
        let quotes = yaml ? yamlQuoteMap(b, l) : []
        while i < l.end {
            let c = b[i]
            if c == backslash { i += 2; continue }
            if !yaml, c == backtick {
                var n = 0
                while i + n < l.end, b[i + n] == backtick { n += 1 }
                var j = i + n
                var closed = false
                while j < l.end {
                    if b[j] == backtick {
                        var m = 0
                        while j + m < l.end, b[j + m] == backtick { m += 1 }
                        if m == n { j += m; closed = true; break }
                        j += m
                    } else { j += 1 }
                }
                i = closed ? j : i + n
                continue
            }
            if c == bang || c == open {
                let comillas = yaml ? quotes[i - l.start] : .ninguna
                if let (occ, end) = parseLink(b, at: i, end: l.end, line: line, lugar: lugar, comillas: comillas) {
                    out.append(occ)
                    i = end
                    continue
                }
            }
            i += 1
        }
    }

    /// Comillas YAML en cada posición de la línea: un escalar entre comillas solo empieza al
    /// principio de un valor (tras `: `, `- `, `[`, `{` o `,`).
    static func yamlQuoteMap(_ b: [UInt8], _ l: LineSpan) -> [LinkOccurrence.Comillas] {
        var out = [LinkOccurrence.Comillas](repeating: .ninguna, count: l.end - l.start)
        var state: LinkOccurrence.Comillas = .ninguna
        var atStart = true
        var i = l.start
        while i < l.end {
            let c = b[i]
            switch state {
            case .dobles:
                out[i - l.start] = .dobles
                if c == backslash, i + 1 < l.end { out[i + 1 - l.start] = .dobles; i += 2; continue }
                if c == dquote { state = .ninguna; atStart = false }
            case .simples:
                out[i - l.start] = .simples
                if c == squote {
                    if i + 1 < l.end, b[i + 1] == squote { out[i + 1 - l.start] = .simples; i += 2; continue }
                    state = .ninguna; atStart = false
                }
            case .ninguna:
                if atStart, c == dquote { state = .dobles; out[i - l.start] = .dobles }
                else if atStart, c == squote { state = .simples; out[i - l.start] = .simples }
                else if c == space || c == tab { /* sigue igual */ }
                else if c == UInt8(ascii: "[") || c == UInt8(ascii: "{") || c == UInt8(ascii: ",") { atStart = true }
                else if c == UInt8(ascii: "-"), atStart { atStart = true }
                else if c == colon, i + 1 >= l.end || b[i + 1] == space || b[i + 1] == tab { atStart = true }
                else if c == hash, i > l.start, b[i - 1] == space || b[i - 1] == tab { return out }
                else { atStart = false }
            }
            i += 1
        }
        return out
    }

    static func parseLink(_ b: [UInt8], at start: Int, end: Int, line: Int, lugar: LinkOccurrence.Lugar,
                          comillas: LinkOccurrence.Comillas) -> (LinkOccurrence, Int)? {
        var i = start
        var embed = false
        if b[i] == bang {
            guard i + 1 < end, b[i + 1] == open else { return nil }
            embed = true; i += 1
        }
        guard b[i] == open else { return nil }
        if i + 1 < end, b[i + 1] == open {
            return parseWiki(b, open: i, start: start, end: end, embed: embed, line: line, lugar: lugar, comillas: comillas)
        }
        return parseMarkdown(b, open: i, start: start, end: end, embed: embed, line: line, lugar: lugar, comillas: comillas)
    }

    static func parseWiki(_ b: [UInt8], open o: Int, start: Int, end: Int, embed: Bool, line: Int,
                          lugar: LinkOccurrence.Lugar, comillas: LinkOccurrence.Comillas) -> (LinkOccurrence, Int)? {
        var j = o + 2
        while j + 1 < end {
            if b[j] == close, b[j + 1] == close { break }
            if b[j] == open { return nil }
            j += 1
        }
        guard j + 1 < end else { return nil }
        let innerStart = o + 2
        var noteEnd = j
        var labelRange: Range<Int>?
        if let barIndex = (innerStart..<j).first(where: { b[$0] == bar }) {
            // `[[nota\|alias]]` dentro de una tabla: la barra invertida no es de la nota.
            noteEnd = (barIndex > innerStart && b[barIndex - 1] == backslash) ? barIndex - 1 : barIndex
            let lr = trimmed(b, (barIndex + 1)..<j)
            labelRange = lr.isEmpty ? nil : lr
        }
        var targetEnd = noteEnd
        var anchor: String?
        if let h = (innerStart..<noteEnd).first(where: { b[$0] == hash }) {
            targetEnd = h
            let a = string(b, trimmed(b, (h + 1)..<noteEnd))
            anchor = a.isEmpty ? nil : a
        }
        let target = trimmed(b, innerStart..<targetEnd)
        guard !target.isEmpty || anchor != nil else { return nil }
        let whole = start..<(j + 2)
        let link = ParsedLink(style: .wiki, target: string(b, target), anchor: anchor,
                              label: labelRange.map { string(b, $0) }, isEmbed: embed, raw: string(b, whole))
        let occ = LinkOccurrence(link: link, range: whole, targetRange: target, labelRange: labelRange, angle: false,
                                 lugar: lugar, comillas: comillas, line: line, isReference: false)
        return (occ, j + 2)
    }

    static func parseMarkdown(_ b: [UInt8], open o: Int, start: Int, end: Int, embed: Bool, line: Int,
                              lugar: LinkOccurrence.Lugar, comillas: LinkOccurrence.Comillas) -> (LinkOccurrence, Int)? {
        var depth = 0
        var j = o
        var cb: Int?
        while j < end {
            let c = b[j]
            if c == backslash { j += 2; continue }
            if c == open { depth += 1 }
            if c == close {
                depth -= 1
                if depth == 0 { cb = j; break }
            }
            j += 1
        }
        guard let cb, cb + 1 < end, b[cb + 1] == lparen else { return nil }
        var k = cb + 2
        while k < end, b[k] == space { k += 1 }
        var dest: Range<Int>
        var angle = false
        if k < end, b[k] == lt {
            guard let g = ((k + 1)..<end).first(where: { b[$0] == gt }) else { return nil }
            dest = (k + 1)..<g
            angle = true
            k = g + 1
        } else {
            var parens = 0
            let ds = k
            while k < end {
                let c = b[k]
                if c == backslash { k += 2; continue }
                if c == lparen { parens += 1 }
                if c == rparen {
                    if parens == 0 { break }
                    parens -= 1
                }
                if c == space || c == tab { break }
                k += 1
            }
            k = min(k, end)
            dest = ds..<k
        }
        // Título opcional: [x](destino "título")
        while k < end, b[k] != rparen { k += 1 }
        guard k < end else { return nil }
        let whole = start..<(k + 1)
        guard let occ = markdownOccurrence(b, whole: whole, label: (o + 1)..<cb, dest: dest, angle: angle, embed: embed,
                                           line: line, lugar: lugar, comillas: comillas, reference: false) else { return nil }
        return (occ, k + 1)
    }

    static func markdownOccurrence(_ b: [UInt8], whole: Range<Int>, label: Range<Int>, dest: Range<Int>, angle: Bool,
                                   embed: Bool, line: Int, lugar: LinkOccurrence.Lugar, comillas: LinkOccurrence.Comillas,
                                   reference: Bool) -> LinkOccurrence? {
        let destText = string(b, dest)
        var targetRange = dest
        var anchor: String?
        if !LinkParser.isExternal(destText), let h = dest.first(where: { b[$0] == hash }) {
            targetRange = dest.lowerBound..<h
            let a = string(b, (h + 1)..<dest.upperBound)
            anchor = a.removingPercentEncoding ?? a
        }
        let target = string(b, targetRange)
        guard !target.isEmpty || anchor != nil else { return nil }
        let link = ParsedLink(style: .markdown, target: target, anchor: anchor, label: string(b, label),
                              isEmbed: embed, raw: string(b, whole))
        return LinkOccurrence(link: link, range: whole, targetRange: targetRange, labelRange: label, angle: angle,
                              lugar: lugar, comillas: comillas, line: line, isReference: reference)
    }
}
