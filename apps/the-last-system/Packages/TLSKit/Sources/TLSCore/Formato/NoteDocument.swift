import Foundation

/// Una nota Markdown separada en propiedades (frontmatter) y cuerpo, sin tocar el texto.
///
/// El frontmatter solo cuenta si la nota empieza por una línea `---` y hay otra
/// línea `---` (o `...`) que lo cierra. El cuerpo es el texto exacto que sigue.
public struct NoteDocument: Sendable, Hashable {
    /// Texto completo, sin BOM.
    public let text: String
    /// YAML entre los delimitadores, o `nil` si la nota no tiene propiedades.
    public let frontmatterText: String?
    /// Texto tras el frontmatter, byte a byte.
    public let body: String
    /// Primer encabezado H1 del cuerpo (fuera de bloques de código).
    public let heading: String?

    public init(text raw: String) {
        let text = TextDecoding.strippingBOM(raw)
        self.text = text
        var front: String?
        var body = text
        let lines = text.lineRanges()
        if let first = lines.first, Self.isDelimiter(text[first.content], allowDots: false) {
            for line in lines.dropFirst() where Self.isDelimiter(text[line.content], allowDots: true) {
                let yamlStart = first.enclosing.upperBound
                front = yamlStart < line.content.lowerBound
                    ? String(text[yamlStart..<line.content.lowerBound]) : ""
                body = String(text[line.enclosing.upperBound...])
                break
            }
        }
        self.frontmatterText = front
        self.body = body
        self.heading = Self.firstHeading(in: body)
    }

    public init(data: Data) {
        self.init(text: TextDecoding.decode(data) ?? "")
    }

    /// Propiedades leídas del frontmatter, en el orden en que están escritas.
    public var frontmatter: Frontmatter {
        guard let front = frontmatterText else { return .empty }
        return FrontmatterReader.read(front)
    }

    /// Título visible: H1, luego `title`/`titulo`, luego `name`/`nombre`, luego el nombre del fichero.
    public func title(fileStem: String, frontmatter: Frontmatter? = nil) -> String {
        if let h = heading, !h.isEmpty { return h }
        let fm = frontmatter ?? self.frontmatter
        if let t = fm.titleText, !t.isEmpty { return t }
        return fileStem
    }

    static func isDelimiter(_ line: Substring, allowDots: Bool) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t == "---" || (allowDots && t == "...")
    }

    /// Primer `# Título` del texto, saltando bloques de código cercados.
    public static func firstHeading(in body: String) -> String? {
        var fence: CodeFence?
        for line in body.lines {
            let trimmed = line.drop(while: { $0 == " " })
            if let f = fence {
                if f.closes(trimmed) { fence = nil }
                continue
            }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            guard line.hasPrefix("# ") || line == "#" else { continue }
            var h = line.dropFirst(1).trimmingCharacters(in: .whitespaces)
            // «# Título #» → «Título», pero «# Lenguaje C#» se queda igual: en CommonMark el cierre
            // de almohadillas solo cuenta si va tras un espacio.
            if h.allSatisfy({ $0 == "#" }) {
                h = ""
            } else if let r = h.range(of: #"[ \t]+#+[ \t]*$"#, options: .regularExpression) {
                h.removeSubrange(r)
            }
            h = h.trimmingCharacters(in: .whitespaces)
            return h.isEmpty ? nil : h
        }
        return nil
    }
}
