import Foundation

/// Cómo se escribe un valor de propiedad en YAML para que `FrontmatterReader` lo lea igual
/// y Obsidian lo entienda: fechas y textos sencillos sin comillas, enlaces `"[[…]]"` entre
/// comillas dobles, listas entre corchetes, sí/no como `true`/`false`.
enum YAMLScalar {
    enum Quote: Sendable { case plain, double, single }

    /// Texto de un escalar. `preferred` conserva el estilo de comillas que ya tenía la línea.
    static func render(text s: String, inFlow: Bool = false, preferred: Quote = .plain) -> String {
        switch preferred {
        case .double: return doubleQuoted(s)
        case .single where !s.contains(where: { $0.isNewline || isControl($0) }): return singleQuoted(s)
        default: return isPlainSafe(s, inFlow: inFlow) ? s : doubleQuoted(s)
        }
    }

    /// Valor completo tras `clave: ` en una sola línea (`nil` si necesita varias: `.raw` multilínea).
    static func inline(_ value: PropertyValue, preferred: Quote = .plain) -> String? {
        switch value {
        case .empty: return ""
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n
        case .text(let s): return render(text: s, preferred: preferred)
        case .list(let items): return flowList(items)
        case .raw(let r): return r.contains(where: \.isNewline) ? nil : r
        }
    }

    static func flowList(_ items: [String]) -> String {
        "[" + items.map { render(text: $0, inFlow: true) }.joined(separator: ", ") + "]"
    }

    /// Indicadores que no pueden abrir un escalar sin comillas.
    static let leadingIndicators: Set<Character> = ["-", "?", ":", ",", "[", "]", "{", "}", "#", "&", "*", "!",
                                                     "|", ">", "'", "\"", "%", "@", "`"]
    static let flowIndicators: Set<Character> = [",", "[", "]", "{", "}"]

    static func isControl(_ c: Character) -> Bool {
        c.unicodeScalars.contains { s in
            (s.value < 0x20 && s.value != 0x09) || s.value == 0x7F || s.value == 0xFEFF
                || (0x80...0x9F).contains(s.value) || s.value == 0x2028 || s.value == 0x2029
        }
    }

    /// `true` si `s` se puede escribir sin comillas y se vuelve a leer como el mismo texto.
    static func isPlainSafe(_ s: String, inFlow: Bool) -> Bool {
        guard let first = s.first, let last = s.last else { return false }
        if first == " " || first == "\t" || last == " " || last == "\t" { return false }
        if leadingIndicators.contains(first) { return false }
        if s.contains(where: { $0.isNewline || isControl($0) }) { return false }
        if s.contains(": ") || s.contains(" #") || s.contains("\t#") || s.contains(":\t") || last == ":" { return false }
        if inFlow, s.contains(where: { flowIndicators.contains($0) || $0 == ":" || $0 == "#" }) { return false }
        if s.hasPrefix("---") || s.hasPrefix("...") { return false }
        // Lo que el lector tomaría por otra cosa (vacío, nulo, sí/no o número) va entre comillas.
        switch s {
        case "~", "null", "Null", "NULL", "true", "True", "TRUE", "false", "False", "FALSE": return false
        default: break
        }
        if FrontmatterReader.isNumber(s) { return false }
        // Formas que otros lectores de YAML (Obsidian) convierten: octal, hexadecimal, infinito…
        let lower = s.lowercased()
        if [".inf", "-.inf", "+.inf", ".nan", "yes", "no", "on", "off", "y", "n"].contains(lower) { return false }
        if lower.range(of: #"^[-+]?(0x[0-9a-f_]+|0o[0-7_]+|0b[01_]+|[0-9][0-9_]*(\.[0-9_]*)?(e[-+]?[0-9]+)?)$"#,
                       options: .regularExpression) != nil { return false }
        return true
    }

    static func doubleQuoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || (0x80...0x9F).contains(scalar.value)
                    || scalar.value == 0x2028 || scalar.value == 0x2029 || scalar.value == 0xFEFF {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    static func singleQuoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// Estilo de comillas de un valor escrito (`"x"`, `'x'` o sin comillas).
    static func quoteStyle(of raw: String) -> Quote {
        let t = raw.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("\"") { return .double }
        if t.hasPrefix("'") { return .single }
        return .plain
    }
}
