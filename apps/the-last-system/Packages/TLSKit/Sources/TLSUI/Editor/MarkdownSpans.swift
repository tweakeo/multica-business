import Foundation
import Markdown

/// Tramos con estilo de un texto Markdown, calculados con swift-markdown (más wikilinks y casillas).
///
/// Es puro y sin AppKit: los rangos son `NSRange` (UTF-16) sobre el texto tal cual, para
/// aplicarlos sin cambiar ni un carácter (el visor muestra el texto fuente).
public struct MarkdownSpan: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case heading(level: Int)
        /// Las almohadillas de un encabezado.
        case headingMarker
        case strong
        case emphasis
        case strikethrough
        case inlineCode
        case codeBlock
        /// Enlace Markdown; `target` es el destino tal cual está escrito.
        case link(target: String)
        /// `[[Destino|alias]]`; `target` sin alias ni ancla.
        case wikilink(target: String)
        case blockQuote
        /// Marca `[ ]` o `[x]` de una casilla.
        case checkbox(checked: Bool)
        /// Texto de una casilla marcada.
        case checkedItem
        case thematicBreak
    }

    public let kind: Kind
    public let range: NSRange

    public init(_ kind: Kind, _ range: NSRange) {
        self.kind = kind; self.range = range
    }
}

public enum MarkdownSpans {
    public static func compute(_ text: String) -> [MarkdownSpan] {
        let index = LineIndex(text)
        let document = Document(parsing: text, options: [])
        var walker = SpanWalker(index: index, text: text as NSString)
        walker.visit(document)
        var spans = walker.spans
        spans.append(contentsOf: wikilinks(in: text, excluding: walker.codeRanges))
        return spans
    }

    // MARK: Wikilinks

    private static let wikilinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([^\]\|#\n]+)(#[^\]\|\n]*)?(\|[^\]\n]*)?\]\]"#)

    static func wikilinks(in text: String, excluding code: [NSRange]) -> [MarkdownSpan] {
        let ns = text as NSString
        return wikilinkRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard !code.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { return nil }
            let target = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            return MarkdownSpan(.wikilink(target: target), m.range)
        }
    }
}

/// Convierte posiciones de swift-markdown (línea y columna en bytes UTF-8, base 1) a UTF-16.
///
/// Las líneas se cortan como en CommonMark: en «\r\n», «\n» y «\r». (En Swift «\r\n» es un solo
/// `Character`, así que `split(separator: "\n")` no corta las notas con saltos de Windows.)
struct LineIndex {
    private struct Line {
        let utf16Start: Int
        let bytes: ArraySlice<UInt8>
    }

    private let lines: [Line]
    let utf16Length: Int

    init(_ text: String) {
        let bytes = Array(text.utf8)
        var lines: [Line] = []
        var lineStart = 0
        var offset = 0
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            guard b == 0x0A || b == 0x0D else { i += 1; continue }
            let line = bytes[lineStart..<i]
            lines.append(Line(utf16Start: offset, bytes: line))
            let breakLength = (b == 0x0D && i + 1 < bytes.count && bytes[i + 1] == 0x0A) ? 2 : 1
            offset += Self.utf16Count(line) + breakLength
            i += breakLength
            lineStart = i
        }
        lines.append(Line(utf16Start: offset, bytes: bytes[lineStart..<bytes.count]))
        self.lines = lines
        self.utf16Length = text.utf16.count
    }

    /// Unidades UTF-16 de un trozo de UTF-8 válido: 1 por escalar, 2 si va fuera del plano básico.
    static func utf16Count(_ bytes: ArraySlice<UInt8>) -> Int {
        var n = 0
        for b in bytes where b & 0xC0 != 0x80 { n += b >= 0xF0 ? 2 : 1 }
        return n
    }

    func offset(_ location: SourceLocation) -> Int {
        let li = location.line - 1
        guard li >= 0 else { return 0 }
        guard li < lines.count else { return utf16Length }
        let line = lines[li]
        let bytes = max(0, location.column - 1)
        let units: Int
        if bytes >= line.bytes.count {
            // Columna más allá del final de la línea: apunta al salto de línea.
            units = Self.utf16Count(line.bytes) + (bytes > line.bytes.count ? 1 : 0)
        } else {
            units = Self.utf16Count(line.bytes.prefix(bytes))
        }
        return min(line.utf16Start + units, utf16Length)
    }

    func range(_ source: SourceRange?) -> NSRange? {
        guard let source else { return nil }
        let start = offset(source.lowerBound)
        let end = max(start, offset(source.upperBound))
        return NSRange(location: start, length: end - start)
    }
}

private struct SpanWalker: MarkupWalker {
    let index: LineIndex
    let text: NSString
    var spans: [MarkdownSpan] = []
    var codeRanges: [NSRange] = []

    init(index: LineIndex, text: NSString) {
        self.index = index; self.text = text
    }

    private mutating func add(_ kind: MarkdownSpan.Kind, _ markup: Markup) {
        guard let r = index.range(markup.range), r.length > 0 else { return }
        spans.append(MarkdownSpan(kind, r))
    }

    mutating func visitHeading(_ heading: Heading) {
        if let r = index.range(heading.range), r.length > 0 {
            spans.append(MarkdownSpan(.heading(level: heading.level), r))
            // Almohadillas iniciales de los encabezados ATX.
            let line = text.substring(with: r)
            var hashes = 0
            for ch in line { if ch == "#" { hashes += 1 } else { break } }
            if hashes > 0 {
                spans.append(MarkdownSpan(.headingMarker, NSRange(location: r.location, length: hashes)))
            }
        }
        descendInto(heading)
    }

    mutating func visitStrong(_ strong: Strong) {
        add(.strong, strong)
        descendInto(strong)
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        add(.emphasis, emphasis)
        descendInto(emphasis)
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        add(.strikethrough, strikethrough)
        descendInto(strikethrough)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if let r = index.range(inlineCode.range), r.length > 0 {
            spans.append(MarkdownSpan(.inlineCode, r))
            codeRanges.append(r)
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if let r = index.range(codeBlock.range), r.length > 0 {
            spans.append(MarkdownSpan(.codeBlock, r))
            codeRanges.append(r)
        }
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        if let r = index.range(html.range), r.length > 0 { codeRanges.append(r) }
    }

    mutating func visitLink(_ link: Link) {
        if let destination = link.destination, !destination.isEmpty {
            add(.link(target: destination), link)
        }
        descendInto(link)
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        add(.blockQuote, blockQuote)
        descendInto(blockQuote)
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        add(.thematicBreak, thematicBreak)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox, let r = index.range(listItem.range), r.length > 0 {
            let checked = checkbox == .checked
            // La marca está en la primera línea del elemento: «- [ ] texto».
            let first = text.lineRange(for: NSRange(location: r.location, length: 0))
            let marker = text.range(of: #"\[[ xX]\]"#, options: .regularExpression,
                                    range: NSIntersectionRange(first, r))
            if marker.location != NSNotFound {
                spans.append(MarkdownSpan(.checkbox(checked: checked), marker))
                if checked {
                    let start = NSMaxRange(marker)
                    let end = NSMaxRange(r)
                    if end > start {
                        spans.append(MarkdownSpan(.checkedItem, NSRange(location: start, length: end - start)))
                    }
                }
            }
        }
        descendInto(listItem)
    }
}
