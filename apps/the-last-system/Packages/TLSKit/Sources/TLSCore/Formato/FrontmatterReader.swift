import Foundation
import Yams

/// Propiedades de una nota en el orden en que están escritas.
public struct Frontmatter: Sendable, Hashable {
    public let properties: [Property]
    /// `false` si el YAML no se pudo leer (la nota se muestra igualmente, sin propiedades).
    public let isValid: Bool

    public static let empty = Frontmatter(properties: [], isValid: true)

    public init(properties: [Property], isValid: Bool) {
        self.properties = properties; self.isValid = isValid
    }

    /// Valor de una clave canónica (`name`, `title`, `notes`…) aceptando sus alias en español.
    /// Gana la primera clave escrita que coincida.
    public func value(_ canonical: String) -> PropertyValue? {
        let wanted = canonical.lowercased()
        for p in properties where FrontmatterReader.canonicalKey(p.key) == wanted {
            return p.value
        }
        return nil
    }

    /// Texto de una clave canónica, `nil` si está vacía.
    public func text(_ canonical: String) -> String? {
        guard let v = value(canonical) else { return nil }
        let s = v.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// `title`/`titulo`/`título`; si no hay, `name`/`nombre`.
    public var titleText: String? { text("title") ?? text("name") }
}

/// Lee el frontmatter con Yams sin resolver tipos de fecha: las fechas quedan como texto.
public enum FrontmatterReader {
    /// Nombres de campo en español que se leen como la clave que significan (solo para título y tipo).
    public static let aliases: [String: String] = ["nombre": "name", "titulo": "title", "título": "title", "notas": "notes"]

    public static func canonicalKey(_ key: String) -> String {
        let k = key.precomposedStringWithCanonicalMapping.lowercased()
        return aliases[k] ?? k
    }

    /// Tope de nodos YAML (contando cada aparición de un alias). Una «bomba de alias» de pocas líneas
    /// se expande a millones de nodos: se trata como frontmatter ilegible en vez de colgar la lectura.
    static let maxNodes = 5_000
    /// Tope de tamaño del frontmatter.
    static let maxBytes = 512 * 1024

    public static func read(_ yaml: String) -> Frontmatter {
        if yaml.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .empty }
        guard yaml.utf8.count <= maxBytes else { return Frontmatter(properties: [], isValid: false) }
        let node: Node?
        do {
            // Resolver vacío: Yams no convierte nada (ni fechas ni números); la clasificación es nuestra.
            node = try Yams.compose(yaml: yaml, Resolver.basic)
        } catch {
            return Frontmatter(properties: [], isValid: false)
        }
        guard let node else { return .empty }
        guard case .mapping(let mapping) = node, nodeCount(node, limit: maxNodes) <= maxNodes else {
            return Frontmatter(properties: [], isValid: false)
        }
        var props: [Property] = []
        var seen = Set<String>()
        for (k, v) in mapping {
            let key = scalarText(k) ?? literal(k)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            props.append(Property(key: key, value: value(of: v)))
        }
        return Frontmatter(properties: props, isValid: true)
    }

    static func value(of node: Node) -> PropertyValue {
        switch node {
        case .scalar(let s):
            return scalarValue(s)
        case .sequence(let seq):
            var items: [String] = []
            for item in seq {
                switch item {
                case .scalar(let s):
                    if case .empty = scalarValue(s) { continue }
                    items.append(s.string)
                default:
                    return .raw(literal(node))
                }
            }
            return .list(items)
        case .mapping:
            return .raw(literal(node))
        case .alias:
            return .raw(literal(node))
        }
    }

    static func scalarValue(_ s: Node.Scalar) -> PropertyValue {
        let text = s.string
        guard s.style == .plain || s.style == .any else { return .text(text) }
        let t = text.trimmingCharacters(in: .whitespaces)
        switch t {
        case "", "~", "null", "Null", "NULL": return .empty
        case "true", "True", "TRUE": return .bool(true)
        case "false", "False", "FALSE": return .bool(false)
        default: break
        }
        if isNumber(t) { return .number(t) }
        return .text(text)
    }

    /// Entero o decimal YAML 1.2 (`12`, `-3.5`, `1e3`). `2026-10-21` o `10:30` no lo son.
    static func isNumber(_ s: String) -> Bool {
        var chars = Substring(s)
        if chars.first == "-" || chars.first == "+" { chars = chars.dropFirst() }
        guard !chars.isEmpty else { return false }
        var digits = 0, dots = 0, sawExp = false
        var i = chars.startIndex
        while i < chars.endIndex {
            let c = chars[i]
            if c.isASCII, c.isNumber { digits += 1 }
            else if c == "." && !sawExp { dots += 1; if dots > 1 { return false } }
            else if (c == "e" || c == "E") && digits > 0 && !sawExp {
                sawExp = true
                let next = chars.index(after: i)
                if next < chars.endIndex, chars[next] == "-" || chars[next] == "+" { i = next }
                let after = chars.index(after: i)
                guard after < chars.endIndex else { return false }
            } else { return false }
            i = chars.index(after: i)
        }
        return digits > 0
    }

    /// Nodos del árbol, parando en cuanto se pasa de `limit` (los alias ya vienen resueltos).
    static func nodeCount(_ node: Node, limit: Int) -> Int {
        var count = 0
        var stack = [node]
        while let n = stack.popLast() {
            count += 1
            if count > limit { return count }
            switch n {
            case .scalar, .alias: break
            case .sequence(let seq): stack.append(contentsOf: seq)
            case .mapping(let m): for (k, v) in m { stack.append(k); stack.append(v) }
            }
        }
        return count
    }

    static func scalarText(_ node: Node) -> String? {
        if case .scalar(let s) = node { return s.string }
        return nil
    }

    /// YAML literal de un nodo (para mapas y listas anidadas).
    static func literal(_ node: Node) -> String {
        ((try? Yams.serialize(node: node, allowUnicode: true)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension PropertyValue {
    /// Representación JSON (para la columna `frontmatter` del índice).
    var jsonFragment: String {
        func quote(_ s: String) -> String {
            let data = (try? JSONEncoder().encode(s)) ?? Data("\"\"".utf8)
            return String(decoding: data, as: UTF8.self)
        }
        switch self {
        case .text(let s), .raw(let s): return quote(s)
        case .number(let s): return Self.isJSONNumber(s) ? s : quote(s)
        case .bool(let b): return b ? "true" : "false"
        case .list(let l): return "[" + l.map(quote).joined(separator: ",") + "]"
        case .empty: return "null"
        }
    }

    /// Número que JSON acepta tal cual (sin `+`, sin ceros a la izquierda).
    static func isJSONNumber(_ s: String) -> Bool {
        s.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil
    }
}

extension Frontmatter {
    /// Objeto JSON con las claves en su orden original.
    var json: String {
        let enc = JSONEncoder()
        let pairs = properties.map { p -> String in
            let k = String(decoding: (try? enc.encode(p.key)) ?? Data("\"\"".utf8), as: UTF8.self)
            return k + ":" + p.value.jsonFragment
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }
}
