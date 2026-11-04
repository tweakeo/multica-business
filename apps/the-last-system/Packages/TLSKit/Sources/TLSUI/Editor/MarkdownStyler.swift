import AppKit
import TLSDesign

/// Texto fuente con estilo para el visor (solo lectura). No cambia ningún carácter:
/// los marcadores se quedan visibles y se atenúan.
public enum MarkdownStyler {
    /// Tramos para el visor, o `nil` si la nota es tan grande que se muestra sin estilo.
    /// Puro: se puede llamar fuera del hilo principal.
    public static func spans(forMarkdown text: String) -> [MarkdownSpan]? {
        text.utf16.count <= maxStyledLength ? MarkdownSpans.compute(text) : nil
    }

    public static let baseSize: CGFloat = 14
    /// A partir de este tamaño (unidades UTF-16) se muestra sin estilo: aplicar estilos a una nota
    /// enorme bloquea la ventana. Los tramos se calculan fuera del hilo principal (`VaultSession`).
    public static let maxStyledLength = 256 * 1024

    /// Clave del atributo `.link` para un wikilink (se guarda como `[[Destino]]`).
    static func wikilinkValue(_ target: String) -> String { "[[\(target)]]" }

    public static func attributed(markdown text: String) -> NSAttributedString {
        attributed(markdown: text, spans: nil)
    }

    /// `spans`: tramos ya calculados (en segundo plano); si es `nil` se calculan aquí.
    public static func attributed(markdown text: String, spans precomputed: [MarkdownSpan]?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes())
        guard text.utf16.count <= maxStyledLength else { return result }
        let full = NSRange(location: 0, length: result.length)
        let spans = precomputed ?? MarkdownSpans.compute(text)

        // Orden: bloques y tamaños primero, después rasgos y enlaces.
        let order: (MarkdownSpan.Kind) -> Int = { kind in
            switch kind {
            case .codeBlock, .blockQuote, .thematicBreak: 0
            case .heading: 1
            case .headingMarker: 2
            case .strong, .emphasis, .strikethrough: 3
            case .inlineCode: 4
            case .checkedItem: 5
            case .checkbox: 6
            case .link, .wikilink: 7
            }
        }
        for span in spans.sorted(by: { order($0.kind) < order($1.kind) }) {
            let range = NSIntersectionRange(span.range, full)
            guard range.length > 0 else { continue }
            apply(span.kind, to: range, in: result)
        }
        return result
    }

    /// Texto sin estilo, en monoespaciada (archivos de texto).
    public static func plain(_ text: String) -> NSAttributedString {
        var attrs = baseAttributes()
        attrs[.font] = NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)
        return NSAttributedString(string: text, attributes: attrs)
    }

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 4
        return [
            .font: NSFont.systemFont(ofSize: baseSize),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
    }

    private static func apply(_ kind: MarkdownSpan.Kind, to range: NSRange, in s: NSMutableAttributedString) {
        switch kind {
        case .heading(let level):
            let size: CGFloat = switch level {
            case 1: 24
            case 2: 19
            case 3: 16
            default: baseSize + 1
            }
            s.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: .semibold), range: range)
        case .headingMarker, .thematicBreak:
            s.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
        case .strong:
            addTraits(.bold, range: range, in: s)
        case .emphasis:
            addTraits(.italic, range: range, in: s)
        case .strikethrough:
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .inlineCode, .codeBlock:
            s.enumerateAttribute(.font, in: range) { value, sub, _ in
                let size = (value as? NSFont)?.pointSize ?? baseSize
                s.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular),
                               range: sub)
            }
            s.addAttribute(.backgroundColor, value: TLSTokens.superficieNS, range: range)
        case .blockQuote:
            s.addAttribute(.foregroundColor, value: TLSPaleta.textoSecundario.ns, range: range)
        case .checkbox:
            addTraits(.bold, range: range, in: s)
            s.addAttribute(.foregroundColor, value: TLSPaleta.textoSecundario.ns, range: range)
        case .checkedItem:
            s.addAttribute(.foregroundColor, value: TLSPaleta.textoSecundario.ns, range: range)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .link(let target):
            s.addAttribute(.link, value: target, range: range)
        case .wikilink(let target):
            s.addAttribute(.link, value: wikilinkValue(target), range: range)
        }
    }

    /// Añade rasgos (negrita, cursiva) conservando tamaño y familia.
    private static func addTraits(_ traits: NSFontDescriptor.SymbolicTraits, range: NSRange,
                                  in s: NSMutableAttributedString) {
        s.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: baseSize)
            let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits))
            let converted = NSFont(descriptor: descriptor, size: font.pointSize) ?? font
            s.addAttribute(.font, value: converted, range: sub)
        }
    }
}
