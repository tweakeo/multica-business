// Procedencia: la resolución de enlaces relativos con %20 sigue la lógica de
// `noteRefs` (FORK/server/internal/biz/databases.go, autor: Manuel Trigo), portada a Swift.

import Foundation

/// Un enlace escrito en una nota.
public struct ParsedLink: Sendable, Hashable {
    public enum Style: String, Sendable { case markdown, wiki }

    public let style: Style
    /// Markdown: destino tal cual (`Sistemas/Rumbo%20y%20mapa.md`). Wiki: nota (`Nota` en `[[Nota#Sección|alias]]`).
    public let target: String
    /// Sección (`#Sección`) sin la almohadilla.
    public let anchor: String?
    /// Texto visible (`[texto](…)` o el alias de `[[Nota|alias]]`).
    public let label: String?
    /// `![…](…)` o `![[…]]`.
    public let isEmbed: Bool
    /// Texto completo del enlace en la nota.
    public let raw: String

    /// Destino en la forma que acepta `LinkResolver.resolve` (y que se guarda en el índice).
    public var resolvable: String {
        switch style {
        case .markdown: target
        case .wiki: "[[" + target + (anchor.map { "#" + $0 } ?? "") + "]]"
        }
    }

    /// `true` para http(s), mailto… (no apuntan a la carpeta).
    public var isExternal: Bool { LinkParser.isExternal(target) }
}

/// Enlaces Markdown relativos (estilo G3, con `%20` o `<…>`) y wikilinks `[[Nota]]`,
/// `[[Nota|alias]]`, `[[Nota#Sección]]`. Ignora bloques y fragmentos de código.
public enum LinkParser {
    public static func links(in markdown: String) -> [ParsedLink] {
        var out: [ParsedLink] = []
        var fence: CodeFence?
        for line in markdown.lines {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            if let f = fence {
                if f.closes(trimmed) { fence = nil }
                continue
            }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            scanLine(Array(line), into: &out)
        }
        return out
    }

    static func isExternal(_ target: String) -> Bool {
        let t = target.lowercased()
        if t.contains("://") { return true }
        for scheme in ["mailto:", "tel:", "message:", "obsidian:", "data:"] where t.hasPrefix(scheme) { return true }
        return false
    }

    /// Texto de un fragmento con los enlaces sustituidos por su texto visible.
    public static func plainText(_ s: String) -> String {
        var result = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if let (link, end) = parseLink(chars, at: i) {
                // Markdown y wikilink: el texto visible, o el destino si no lo hay.
                result += link.label ?? link.target
                i = end
            } else {
                result.append(chars[i]); i += 1
            }
        }
        return result
    }

    static func scanLine(_ chars: [Character], into out: inout [ParsedLink]) {
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" { i += 2; continue }
            if c == "`" {
                // Fragmento de código: salta hasta el mismo número de comillas.
                var n = 0
                while i + n < chars.count, chars[i + n] == "`" { n += 1 }
                var j = i + n
                var closed = false
                while j < chars.count {
                    if chars[j] == "`" {
                        var m = 0
                        while j + m < chars.count, chars[j + m] == "`" { m += 1 }
                        if m == n { j += m; closed = true; break }
                        j += m
                    } else { j += 1 }
                }
                i = closed ? j : i + n
                continue
            }
            if let (link, end) = parseLink(chars, at: i) {
                out.append(link)
                i = end
                continue
            }
            i += 1
        }
    }

    /// Intenta leer un enlace que empieza en `i` (`[[`, `![[`, `[`, `![`).
    static func parseLink(_ chars: [Character], at start: Int) -> (ParsedLink, Int)? {
        var i = start
        var embed = false
        if chars[i] == "!" {
            guard i + 1 < chars.count, chars[i + 1] == "[" else { return nil }
            embed = true; i += 1
        }
        guard chars[i] == "[" else { return nil }
        if i + 1 < chars.count, chars[i + 1] == "[" {
            return parseWiki(chars, open: i, start: start, embed: embed)
        }
        return parseMarkdown(chars, open: i, start: start, embed: embed)
    }

    static func parseWiki(_ chars: [Character], open: Int, start: Int, embed: Bool) -> (ParsedLink, Int)? {
        var j = open + 2
        while j + 1 < chars.count {
            if chars[j] == "]" && chars[j + 1] == "]" { break }
            if chars[j] == "[" { return nil }
            j += 1
        }
        guard j + 1 < chars.count else { return nil }
        let inner = String(chars[(open + 2)..<j])
        var notePart = inner
        var label: String?
        if let bar = inner.firstIndex(of: "|") {
            notePart = String(inner[..<bar])
            label = String(inner[inner.index(after: bar)...]).trimmingCharacters(in: .whitespaces)
        }
        var anchor: String?
        if let hash = notePart.firstIndex(of: "#") {
            anchor = String(notePart[notePart.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
            notePart = String(notePart[..<hash])
        }
        let target = notePart.trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty || anchor != nil else { return nil }
        let end = j + 2
        let link = ParsedLink(style: .wiki, target: target, anchor: anchor?.isEmpty == true ? nil : anchor,
                              label: label?.isEmpty == true ? nil : label, isEmbed: embed,
                              raw: String(chars[start..<end]))
        return (link, end)
    }

    static func parseMarkdown(_ chars: [Character], open: Int, start: Int, embed: Bool) -> (ParsedLink, Int)? {
        // Texto entre corchetes (admite corchetes anidados equilibrados).
        var depth = 0
        var j = open
        var closeBracket: Int?
        while j < chars.count {
            let c = chars[j]
            if c == "\\" { j += 2; continue }
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 { closeBracket = j; break }
            }
            j += 1
        }
        guard let cb = closeBracket, cb + 1 < chars.count, chars[cb + 1] == "(" else { return nil }
        let label = String(chars[(open + 1)..<cb])
        var k = cb + 2
        while k < chars.count, chars[k] == " " { k += 1 }
        var dest = ""
        if k < chars.count, chars[k] == "<" {
            // [texto](<ruta con espacios (y paréntesis).md>)
            guard let gt = chars[(k + 1)...].firstIndex(of: ">") else { return nil }
            dest = String(chars[(k + 1)..<gt])
            k = gt + 1
        } else {
            var parens = 0
            let destStart = k
            while k < chars.count {
                let c = chars[k]
                if c == "\\" { k += 2; continue }
                if c == "(" { parens += 1 }
                if c == ")" {
                    if parens == 0 { break }
                    parens -= 1
                }
                if c == " " || c == "\t" { break }
                k += 1
            }
            dest = String(chars[destStart..<min(k, chars.count)])
        }
        // Título opcional: [x](destino "título")
        while k < chars.count, chars[k] != ")" { k += 1 }
        guard k < chars.count else { return nil }
        let end = k + 1
        var target = dest
        var anchor: String?
        if let hash = dest.firstIndex(of: "#"), !isExternal(dest) {
            anchor = String(dest[dest.index(after: hash)...])
            target = String(dest[..<hash])
        }
        guard !target.isEmpty || anchor != nil else { return nil }
        let link = ParsedLink(style: .markdown, target: target,
                              anchor: anchor.map { $0.removingPercentEncoding ?? $0 },
                              label: label, isEmbed: embed, raw: String(chars[start..<end]))
        return (link, end)
    }
}
