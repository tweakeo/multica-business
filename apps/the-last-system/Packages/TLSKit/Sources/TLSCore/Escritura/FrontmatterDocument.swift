import Foundation

/// Nota Markdown editable: propiedades (frontmatter) y cuerpo, reescribibles byte a byte.
///
/// `set` y `unset` cambian **solo** las líneas de esas claves: el resto del bloque (orden,
/// comentarios, líneas en blanco, claves que la app no conoce, saltos `\r\n`) queda igual.
/// Una clave nueva se coloca en el orden canónico (`tls_type`, `tls_schema`, `id`, …).
/// Leer y volver a escribir sin cambios da exactamente los mismos bytes.
public struct FrontmatterDocument: Sendable, Hashable {
    /// El fichero empezaba por BOM (se conserva).
    public private(set) var bom: Bool
    /// Línea de apertura exacta (`---` y su salto), o `nil` si la nota no tiene propiedades.
    private var opening: TextLine?
    /// Líneas del bloque YAML, tal cual.
    private var lines: [TextLine]
    /// Línea de cierre exacta (`---` o `...`).
    private var closing: TextLine?
    /// Cuerpo tras el frontmatter, byte a byte.
    public private(set) var body: String
    /// Salto de línea que se usa en las líneas nuevas.
    public let eol: String

    // MARK: Lectura

    public init(text raw: String) {
        var text = raw
        bom = text.hasPrefix("\u{FEFF}")
        if bom { text.removeFirst() }
        eol = TextLines.dominantEOL(text)
        // Misma regla que `NoteDocument`: `---` en la primera línea y otra `---` (o `...`) que cierra.
        let all = TextLines.split(text)
        if let first = all.first, !first.eol.isEmpty, NoteDocument.isDelimiter(Substring(first.content), allowDots: false),
           let end = all.dropFirst().firstIndex(where: { NoteDocument.isDelimiter(Substring($0.content), allowDots: true) }) {
            opening = first
            lines = Array(all[1..<end])
            closing = all[end]
            body = TextLines.join(Array(all[(end + 1)...]))
        } else {
            opening = nil
            lines = []
            closing = nil
            body = text
        }
    }

    /// `nil` si no es UTF-8 válido.
    public init?(data: Data) {
        guard let e = EditableText(data: data) else { return nil }
        self.init(text: (e.bom ? "\u{FEFF}" : "") + e.text)
    }

    /// Texto completo (con el BOM si lo había).
    public var text: String {
        var s = bom ? "\u{FEFF}" : ""
        if let opening, let closing {
            s += opening.full
            s += TextLines.join(lines)
            s += closing.full
        }
        return s + body
    }

    public var data: Data { Data(text.utf8) }

    public var hasFrontmatter: Bool { opening != nil }

    /// YAML entre los delimitadores (igual que `NoteDocument.frontmatterText`).
    public var frontmatterText: String? {
        opening == nil ? nil : TextLines.join(lines)
    }

    /// Bloque completo de propiedades, con sus delimitadores (vacío si no hay).
    public var frontmatterBlock: String {
        guard let opening, let closing else { return "" }
        return opening.full + TextLines.join(lines) + closing.full
    }

    public var frontmatter: Frontmatter {
        frontmatterText.map(FrontmatterReader.read) ?? .empty
    }

    /// Valor actual de una clave (exacta, como está escrita).
    public func value(_ key: String) -> PropertyValue? {
        guard let entry = entries().first(where: { $0.matches(key) }) else { return nil }
        return Self.value(ofBlock: Array(lines[entry.range]), key: entry.name)
    }

    /// Claves en el orden en que están escritas.
    public var keys: [String] { entries().map(\.name) }

    /// Texto exacto (con saltos) de las líneas de una clave.
    public func rawLines(_ key: String) -> String? {
        guard let entry = entries().first(where: { $0.matches(key) }) else { return nil }
        return TextLines.join(Array(lines[entry.range]))
    }

    // MARK: Edición

    /// Pone `key: value` cambiando solo sus líneas. Si el valor ya es ese, no toca nada.
    /// Una clave nueva vacía no se escribe (las vacías no se escriben al crear).
    public mutating func set(_ key: String, _ value: PropertyValue) {
        let key = key.precomposedStringWithCanonicalMapping
        let all = entries()
        if let entry = all.first(where: { $0.matches(key) }) {
            let block = Array(lines[entry.range])
            if Self.value(ofBlock: block, key: entry.name) == value { return }
            lines.replaceSubrange(entry.range, with: Self.rewrite(block, keyName: entry.name, value: value, eol: eol))
            return
        }
        if value == .empty { return }
        let newLines = Self.render(key: key, value: value, eol: eol)
        guard opening != nil else {
            opening = TextLine(content: "---", eol: eol)
            closing = TextLine(content: "---", eol: eol)
            lines = newLines
            return
        }
        let at = insertionIndex(for: key, entries: all)
        // Si la línea anterior no termina en salto (bloque raro), se le añade.
        if at > 0, lines[at - 1].eol.isEmpty { lines[at - 1].eol = eol }
        lines.insert(contentsOf: newLines, at: at)
    }

    /// Quita las líneas de una clave. El bloque de propiedades se queda aunque quede vacío.
    public mutating func unset(_ key: String) {
        guard let entry = entries().first(where: { $0.matches(key) }) else { return }
        lines.removeSubrange(entry.range)
    }

    /// Varias claves a la vez: primero las que se quitan y después las que se ponen, en orden.
    public mutating func merge(set: [Property], unset: [String]) {
        for k in unset { self.unset(k) }
        for p in set { self.set(p.key, p.value) }
    }

    /// Sustituye las líneas de una clave por otras ya escritas (fusión con el editor).
    /// Si la clave no existe, se añaden detrás de `after` (o en su sitio canónico).
    mutating func setRawLines(_ key: String, raw: String, after: String?) {
        let newLines = TextLines.split(TextLines.terminated(raw, eol: eol))
        let all = entries()
        if let entry = all.first(where: { $0.matches(key) }) {
            lines.replaceSubrange(entry.range, with: newLines)
            return
        }
        guard opening != nil else {
            opening = TextLine(content: "---", eol: eol)
            closing = TextLine(content: "---", eol: eol)
            lines = newLines
            return
        }
        var at = insertionIndex(for: key, entries: all)
        if let after, let prev = all.first(where: { $0.matches(after) }) { at = prev.range.upperBound }
        if at > 0, lines[at - 1].eol.isEmpty { lines[at - 1].eol = eol }
        lines.insert(contentsOf: newLines, at: at)
    }

    /// Sustituye el cuerpo (el frontmatter no cambia).
    public mutating func replaceBody(_ newBody: String) {
        body = newBody
    }

    // MARK: Orden canónico

    /// Orden de las claves conocidas (PLAN §4.2 y diccionario de SISTEMAS.md §1.5). `plantilla` va la última.
    public static let canonicalOrder: [String] = [
        "tls_type", "tls_schema", "id", "numero", "codigo", "version", "titulo", "nombre", "aliases",
        "estado", "prioridad", "tipo", "clase", "relacion", "area", "areas", "rol", "responsable", "personas",
        "planificada", "vence", "estimacion_h", "dedicadas_h", "fecha", "hora", "inicio", "fin",
        "proyecto", "proyecto_id", "oportunidad", "oportunidad_id", "empresa", "empresa_id", "contacto",
        "contacto_id", "servicio", "producto_id", "objetivo", "objetivo_id", "sistema", "plan", "plantilla_id",
        "reunion", "factura", "contenido", "conversacion", "padre", "padre_id", "bloqueada_por",
        "derivado_de", "referido_por", "sustituye", "rectifica", "capacidad", "despertar",
        "valor", "precio", "importe", "base", "iva_pct", "retencion_pct", "total", "probabilidad",
        "origen", "canal", "creada", "creada_por", "cerrada", "fecha_corte", "verificacion",
    ]

    /// Rango de una clave: su posición en el orden canónico; las desconocidas, detrás de las
    /// conocidas y delante de `plantilla`.
    static func rank(_ key: String) -> Int {
        let k = key.precomposedStringWithCanonicalMapping
        if k == "plantilla" { return canonicalOrder.count + 1 }
        return canonicalOrder.firstIndex(of: k) ?? canonicalOrder.count
    }

    /// Detrás de la última clave escrita con rango menor o igual; si no hay, delante de la primera.
    private func insertionIndex(for key: String, entries all: [Entry]) -> Int {
        let r = Self.rank(key)
        if let last = all.last(where: { Self.rank($0.name) <= r }) { return last.range.upperBound }
        if let first = all.first { return first.range.lowerBound }
        // Solo comentarios o vacío: al final del bloque.
        return lines.count
    }

    // MARK: Bloques de clave

    struct Entry {
        var name: String
        var range: Range<Int>
        func matches(_ key: String) -> Bool { name == key.precomposedStringWithCanonicalMapping }
    }

    /// Claves de primer nivel con sus líneas (la de la clave y las que la continúan).
    func entries() -> [Entry] {
        var out: [Entry] = []
        var seen = Set<String>()
        var i = 0
        while i < lines.count {
            guard let parsed = Self.parseKeyLine(lines[i].content) else { i += 1; continue }
            var j = i + 1
            let allowDash = parsed.valueIsEmpty
            while j < lines.count {
                if Self.isContinuation(lines[j].content, allowDash: allowDash) { j += 1; continue }
                if lines[j].isBlank {
                    // Línea en blanco dentro de un bloque (`|`): solo si sigue una continuación.
                    var k = j
                    while k < lines.count, lines[k].isBlank { k += 1 }
                    if k < lines.count, Self.isContinuation(lines[k].content, allowDash: allowDash),
                       lines[k].content.first == " " || lines[k].content.first == "\t" {
                        j = k + 1
                        continue
                    }
                }
                break
            }
            // Clave repetida: cuenta la primera (como el lector).
            if !seen.contains(parsed.name) {
                seen.insert(parsed.name)
                out.append(Entry(name: parsed.name, range: i..<j))
            }
            i = j
        }
        return out
    }

    static func isContinuation(_ line: String, allowDash: Bool) -> Bool {
        guard let first = line.first else { return false }
        if first == " " || first == "\t" { return !line.allSatisfy { $0 == " " || $0 == "\t" } }
        if allowDash, first == "-" {
            let rest = line.dropFirst()
            return rest.isEmpty || rest.first == " " || rest.first == "\t"
        }
        return false
    }

    struct KeyLine {
        var name: String
        /// Texto hasta los dos puntos incluidos (`"clave":`).
        var keyPart: String
        /// Espacios tras los dos puntos.
        var separator: String
        /// Valor escrito, sin el comentario ni los espacios que lo preceden.
        var value: String
        /// Espacios entre el valor y el comentario.
        var padding: String
        /// Comentario final (`# …`), si lo hay.
        var comment: String?

        var valueIsEmpty: Bool { value.isEmpty }
    }

    /// Lee `clave: valor  # comentario` en la columna 0. `nil` si no es una línea de clave.
    static func parseKeyLine(_ line: String) -> KeyLine? {
        guard let first = line.first, first != " ", first != "\t", first != "#" else { return nil }
        if line.hasPrefix("---") || line.hasPrefix("...") { return nil }
        // `- elemento` es una lista, no una clave.
        if first == "-", line.dropFirst().first.map({ $0 == " " || $0 == "\t" }) ?? true { return nil }
        let chars = Array(line)
        var i = 0
        var name = ""
        if first == "\"" || first == "'" {
            // Clave entre comillas.
            var j = 1
            var s = ""
            var closed = false
            while j < chars.count {
                let c = chars[j]
                if first == "\"", c == "\\", j + 1 < chars.count { s.append(chars[j + 1]); j += 2; continue }
                if c == first {
                    if first == "'", j + 1 < chars.count, chars[j + 1] == "'" { s.append("'"); j += 2; continue }
                    closed = true; j += 1; break
                }
                s.append(c); j += 1
            }
            guard closed else { return nil }
            while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
            guard j < chars.count, chars[j] == ":" else { return nil }
            name = s
            i = j
        } else {
            if "[]{}|>!&*%@`?,".contains(first) { return nil }
            var j = 0
            while j < chars.count {
                if chars[j] == ":", j + 1 == chars.count || chars[j + 1] == " " || chars[j + 1] == "\t" { break }
                j += 1
            }
            guard j < chars.count else { return nil }
            name = String(chars[0..<j]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            i = j
        }
        let keyPart = String(chars[0...i])
        var k = i + 1
        var sep = ""
        while k < chars.count, chars[k] == " " || chars[k] == "\t" { sep.append(chars[k]); k += 1 }
        let rest = Array(chars[k...])
        // Comentario: `#` al principio del valor o tras un espacio, fuera de comillas.
        var valueEnd = rest.count
        var commentStart: Int?
        if let q = rest.first, q == "\"" || q == "'" {
            var j = 1
            while j < rest.count {
                if q == "\"", rest[j] == "\\" { j += 2; continue }
                if rest[j] == q {
                    if q == "'", j + 1 < rest.count, rest[j + 1] == "'" { j += 2; continue }
                    break
                }
                j += 1
            }
            var m = min(j + 1, rest.count)
            while m < rest.count, rest[m] == " " || rest[m] == "\t" { m += 1 }
            if m < rest.count, rest[m] == "#" { commentStart = m }
        } else if rest.first == "#" {
            commentStart = 0
        } else {
            for j in rest.indices where rest[j] == "#" && j > 0 && (rest[j - 1] == " " || rest[j - 1] == "\t") {
                commentStart = j
                break
            }
        }
        if let c = commentStart { valueEnd = c }
        var v = Array(rest[0..<valueEnd])
        var pad = ""
        while let last = v.last, last == " " || last == "\t" { pad = String(last) + pad; v.removeLast() }
        let comment = commentStart.map { String(rest[$0...]) }
        // Sin comentario, los espacios finales quedan en el relleno (se conservan al reescribir solo si hay comentario).
        return KeyLine(name: name.precomposedStringWithCanonicalMapping, keyPart: keyPart,
                       separator: sep, value: String(v), padding: pad, comment: comment)
    }

    /// Valor de una clave leyendo solo sus líneas.
    static func value(ofBlock block: [TextLine], key: String) -> PropertyValue {
        let fm = FrontmatterReader.read(TextLines.join(block))
        guard fm.isValid, let p = fm.properties.first(where: { $0.key.precomposedStringWithCanonicalMapping == key }) else {
            return .raw(TextLines.join(block))
        }
        return p.value
    }

    /// Líneas nuevas de una clave nueva.
    static func render(key: String, value: PropertyValue, eol: String) -> [TextLine] {
        let keyText = renderKey(key)
        if let inline = YAMLScalar.inline(value) {
            return [TextLine(content: inline.isEmpty ? keyText + ":" : keyText + ": " + inline, eol: eol)]
        }
        var out = [TextLine(content: keyText + ":", eol: eol)]
        if case .raw(let r) = value {
            for l in TextLines.split(r) { out.append(TextLine(content: "  " + l.content, eol: eol)) }
        }
        return out
    }

    static func renderKey(_ key: String) -> String {
        let simple = key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == " " }
            && key.first.map { $0 != "-" && $0 != " " } == true && key.last != " "
        return simple ? key : YAMLScalar.doubleQuoted(key)
    }

    /// Reescribe las líneas de una clave existente conservando su forma: la clave tal como
    /// estaba escrita, el espacio tras los dos puntos, las comillas, el comentario final (en
    /// la misma columna si cabe) y, si era una lista en bloque, la lista en bloque.
    static func rewrite(_ block: [TextLine], keyName: String, value: PropertyValue, eol: String) -> [TextLine] {
        guard let head = block.first, let parsed = parseKeyLine(head.content) else {
            return render(key: keyName, value: value, eol: eol)
        }
        // El salto final del bloque (el de su última línea) se conserva tal cual.
        let endEOL = block.last?.eol ?? eol
        let innerEOL = head.eol.isEmpty ? eol : head.eol
        // Lista en bloque (`clave:` y debajo `  - a`): se conserva la forma y la sangría.
        if case .list(let items) = value, !items.isEmpty, parsed.valueIsEmpty,
           let firstItem = block.dropFirst().first(where: { $0.content.trimmingCharacters(in: .whitespaces).hasPrefix("-") }) {
            let indent = String(firstItem.content.prefix(while: { $0 == " " || $0 == "\t" }))
            var out = [TextLine(content: head.content, eol: innerEOL)]
            for (n, item) in items.enumerated() {
                out.append(TextLine(content: indent + "- " + YAMLScalar.render(text: item),
                                    eol: n == items.count - 1 ? endEOL : innerEOL))
            }
            return out
        }
        let preferred: YAMLScalar.Quote = {
            guard case .text = value else { return .plain }
            return YAMLScalar.quoteStyle(of: parsed.value)
        }()
        if let inline = YAMLScalar.inline(value, preferred: preferred) {
            let sep = inline.isEmpty ? "" : (parsed.separator.isEmpty ? " " : parsed.separator)
            let lead = parsed.keyPart + sep + inline
            return [TextLine(content: lead + commentTail(parsed, after: lead.count), eol: endEOL)]
        }
        // Valor de varias líneas (`.raw`): sangrado bajo la clave.
        var out = [TextLine(content: parsed.keyPart + commentTail(parsed, after: parsed.keyPart.count), eol: innerEOL)]
        if case .raw(let r) = value {
            let rawLines = TextLines.split(r)
            for (n, l) in rawLines.enumerated() {
                out.append(TextLine(content: "  " + l.content, eol: n == rawLines.count - 1 ? endEOL : innerEOL))
            }
        }
        return out
    }

    /// Comentario final en la misma columna que tenía (o tras un espacio si no cabe).
    private static func commentTail(_ parsed: KeyLine, after length: Int) -> String {
        guard let comment = parsed.comment else { return "" }
        let oldColumn = parsed.keyPart.count + parsed.separator.count + parsed.value.count + parsed.padding.count
        return String(repeating: " ", count: max(1, oldColumn - length)) + comment
    }
}
