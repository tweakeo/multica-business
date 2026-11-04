import Foundation

/// Movimientos de un cambio en bloque, en orden: dónde acaba cada ruta.
struct MoveMap: Sendable {
    var moves: [(from: VaultPath, to: VaultPath)]

    static func key(_ p: VaultPath) -> String { TextFolding.pathKey(p.raw) }

    static func isUnder(_ p: VaultPath, _ dir: VaultPath) -> Bool {
        let k = key(p), d = key(dir)
        return k == d || k.hasPrefix(d + "/")
    }

    /// Ruta final de `p` tras todos los movimientos (la misma si no se mueve).
    func map(_ p: VaultPath) -> VaultPath {
        var cur = p
        for m in moves where Self.isUnder(cur, m.from) {
            cur = VaultPath(components: m.to.components + Array(cur.components.dropFirst(m.from.components.count)))
        }
        return cur
    }

    func moves(_ p: VaultPath) -> Bool { map(p).raw != p.raw }
}

/// Cómo se escribe el destino de un enlace Markdown relativo, conservando la forma del original:
/// `%20` o `<…>`, tildes tal cual o codificadas, con o sin `.md`, `./` delante.
enum MarkdownDestination {
    struct Style {
        var encodeNonASCII = false
        var encodeParens = false
        var angle = false
        var dotPrefix = false
        var withExtension = true
    }

    static func style(of raw: String, angle: Bool, targetExt: String) -> Style {
        var s = Style()
        s.angle = angle
        s.encodeNonASCII = raw.range(of: "%[89A-Fa-f][0-9A-Fa-f]", options: .regularExpression) != nil
        s.encodeParens = raw.range(of: "%2[89]", options: [.regularExpression, .caseInsensitive]) != nil
        s.dotPrefix = raw.hasPrefix("./")
        let decoded = raw.removingPercentEncoding ?? raw
        let ext = VaultPath(decoded).ext
        // Sin extensión escrita y el destino es una nota: se sigue escribiendo sin `.md`.
        s.withExtension = !(ext.isEmpty && (targetExt == "md" || targetExt == "markdown"))
        return s
    }

    /// Componentes relativos de `to` vista desde la carpeta de `from`.
    static func relativeComponents(from: VaultPath, to: VaultPath) -> [String] {
        let base = from.parent?.components ?? []
        let dest = to.components
        var common = 0
        while common < min(base.count, dest.count - 1),
              TextFolding.pathKey(base[common]) == TextFolding.pathKey(dest[common]) { common += 1 }
        return Array(repeating: "..", count: base.count - common) + Array(dest[common...])
    }

    /// Destino nuevo, reutilizando tal cual los tramos que no cambian del destino original.
    static func rewrite(original raw: String, from: VaultPath, to: VaultPath, angle: Bool) -> String {
        let st = style(of: raw, angle: angle, targetExt: to.ext)
        var parts = relativeComponents(from: from, to: to)
        if !st.withExtension, let last = parts.last, let dot = last.lastIndex(of: "."), dot != last.startIndex {
            parts[parts.count - 1] = String(last[..<dot])
        }
        var originals = raw.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if originals.first == "." { originals.removeFirst() }
        var out: [String] = []
        for (n, part) in parts.enumerated() {
            // Las carpetas se comparan sin distinguir mayúsculas; el nombre final, exacto.
            let same: (String) -> Bool = n == parts.count - 1
                ? { decode($0) == part }
                : { TextFolding.pathKey(decode($0)) == TextFolding.pathKey(part) }
            if n < originals.count, same(originals[n]) {
                out.append(originals[n])
            } else {
                out.append(encode(part, style: st))
            }
        }
        var text = out.joined(separator: "/")
        if st.dotPrefix { text = "./" + text }
        if !st.angle, !st.encodeParens, !balanced(text) {
            text = text.replacingOccurrences(of: "(", with: "%28").replacingOccurrences(of: ")", with: "%29")
        }
        return text
    }

    static func decode(_ s: String) -> String {
        (s.removingPercentEncoding ?? s).precomposedStringWithCanonicalMapping
    }

    static func balanced(_ s: String) -> Bool {
        var depth = 0
        for c in s {
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0
    }

    static func encode(_ component: String, style st: Style) -> String {
        if st.angle {
            // Entre `<…>` solo estorban los propios ángulos y los saltos.
            var out = ""
            for c in component {
                switch c {
                case "<": out += "%3C"
                case ">": out += "%3E"
                case "\n", "\r", "\r\n": out += "%0A"
                default: out.append(c)
                }
            }
            return out
        }
        var out = ""
        for scalar in component.precomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar {
            case " ": out += "%20"
            case "%": out += "%25"
            case "#": out += "%23"
            case "<": out += "%3C"
            case ">": out += "%3E"
            case "\\": out += "%5C"
            case "(" where st.encodeParens: out += "%28"
            case ")" where st.encodeParens: out += "%29"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F || (scalar.value > 0x7F && st.encodeNonASCII) {
                    for byte in String(scalar).utf8 { out += String(format: "%%%02X", byte) }
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }

    /// Resolución estricta de un destino Markdown: solo por ruta (relativa, o desde la raíz si
    /// empieza por `/`), sin buscar por nombre. Así no se dejan enlaces «flojos».
    static func strictTarget(_ target: String, from: VaultPath, exists: (VaultPath) -> VaultPath?) -> VaultPath? {
        var dest = target.trimmingCharacters(in: .whitespaces)
        if dest.hasPrefix("<"), dest.hasSuffix(">") { dest = String(dest.dropFirst().dropLast()) }
        let decoded = dest.removingPercentEncoding ?? dest
        let candidate: VaultPath?
        if decoded.hasPrefix("/") { candidate = VaultPath(decoded) } else { candidate = from.resolvingRelative(dest) }
        guard let c = candidate, !c.isRoot, !c.components.contains("..") else { return nil }
        if let p = exists(c) { return p }
        if c.ext.isEmpty, let p = exists(VaultPath(c.raw + ".md")) { return p }
        return nil
    }
}

/// Formas de escribir el destino de un wikilink hacia una ruta, de la más parecida al original a la más explícita.
enum WikiTarget {
    static func isNote(_ p: VaultPath) -> Bool { p.ext == "md" || p.ext == "markdown" }

    static func candidates(original: String, to: VaultPath) -> [String] {
        let written = VaultPath(original)
        let writtenExt = written.ext
        // `[[x.md]]`, `[[logo.png]]`: con extensión si se escribió o si el destino no es una nota.
        let withExt = !isNote(to) || (!writtenExt.isEmpty && writtenExt == to.ext)
        func form(_ comps: [String], ext: Bool) -> String {
            var c = comps
            if !ext, isNote(to), let last = c.last {
                c[c.count - 1] = VaultPath(last).stem
            }
            return c.joined(separator: "/")
        }
        let full = to.components
        var out: [String] = []
        if original.contains("/") {
            let k = min(written.components.count, full.count)
            out.append(form(Array(full.suffix(k)), ext: withExt))
        } else {
            out.append(form([to.name], ext: withExt))
        }
        out.append(form(full, ext: withExt))
        out.append(form(full, ext: true))
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }
}

/// Texto que va dentro de una propiedad YAML con esas comillas.
enum YAMLInline {
    static func escape(_ s: String, comillas: LinkOccurrence.Comillas) -> String {
        switch comillas {
        case .dobles:
            return s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        case .simples:
            return s.replacingOccurrences(of: "'", with: "''")
        case .ninguna:
            return s
        }
    }
}
