import AppKit
import Foundation
import Testing
@testable import TLSUI

@Suite("Visor · tramos de Markdown")
struct MarkdownSpansTests {
    private func spans(_ text: String) -> [MarkdownSpan] { MarkdownSpans.compute(text) }

    private func substring(_ text: String, _ range: NSRange) -> String {
        (text as NSString).substring(with: range)
    }

    @Test("Encabezado y almohadillas")
    func heading() throws {
        let text = "# Ventas\n\nTexto"
        let s = spans(text)
        let h = try #require(s.first { if case .heading(1) = $0.kind { return true }; return false })
        #expect(substring(text, h.range) == "# Ventas")
        let marker = try #require(s.first { $0.kind == .headingMarker })
        #expect(substring(text, marker.range) == "#")
    }

    @Test("Negrita tras letras con tilde (UTF-8 → UTF-16)")
    func strongAfterAccents() throws {
        let text = "Ñandú **Estado:** activa"
        let strong = try #require(spans(text).first { $0.kind == .strong })
        #expect(substring(text, strong.range) == "**Estado:**")
    }

    @Test("Posiciones correctas en la segunda línea")
    func secondLine() throws {
        let text = "línea con tildes áéí\n*cursiva* y `código`"
        let s = spans(text)
        let em = try #require(s.first { $0.kind == .emphasis })
        #expect(substring(text, em.range) == "*cursiva*")
        let code = try #require(s.first { $0.kind == .inlineCode })
        #expect(substring(text, code.range) == "`código`")
    }

    @Test("Enlace relativo con %20: destino tal cual")
    func link() throws {
        let text = "- [Diagnóstico y propuesta](Sistemas/Diagn%C3%B3stico%20y%20propuesta.md): de la conversación."
        let link = try #require(spans(text).first { if case .link = $0.kind { return true }; return false })
        #expect(link.kind == .link(target: "Sistemas/Diagn%C3%B3stico%20y%20propuesta.md"))
        #expect(substring(text, link.range) == "[Diagnóstico y propuesta](Sistemas/Diagn%C3%B3stico%20y%20propuesta.md)")
    }

    @Test("Wikilinks, sin contar los que están en código")
    func wikilinks() throws {
        let text = "Ver [[Rumbo|el rumbo]] y [[Decisiones#2026]] pero no `[[Código]]`"
        let wikis = spans(text).filter { if case .wikilink = $0.kind { return true }; return false }
        #expect(wikis.map(\.kind) == [.wikilink(target: "Rumbo"), .wikilink(target: "Decisiones")])
        #expect(substring(text, wikis[0].range) == "[[Rumbo|el rumbo]]")
    }

    @Test("Casillas: marca y texto tachado si está hecha")
    func checkboxes() throws {
        let text = "- [ ] Preparar diagnóstico\n- [x] Enviar propuesta\n"
        let s = spans(text)
        let boxes = s.filter { if case .checkbox = $0.kind { return true }; return false }
        #expect(boxes.count == 2)
        #expect(boxes[0].kind == .checkbox(checked: false))
        #expect(substring(text, boxes[0].range) == "[ ]")
        #expect(boxes[1].kind == .checkbox(checked: true))
        #expect(substring(text, boxes[1].range) == "[x]")
        let done = try #require(s.first { $0.kind == .checkedItem })
        #expect(substring(text, done.range).contains("Enviar propuesta"))
        #expect(!substring(text, done.range).contains("Preparar"))
    }

    @Test("Bloque de código")
    func codeBlock() throws {
        let text = "Antes\n\n```\nlet a = 1\n```\n\nDespués"
        let block = try #require(spans(text).first { $0.kind == .codeBlock })
        #expect(substring(text, block.range).contains("let a = 1"))
        #expect(!substring(text, block.range).contains("Después"))
    }

    @Test("Ningún tramo se sale del texto")
    func rangesInBounds() {
        let text = "# T\n\n> cita **fuerte**\n\n1. [ ] uno\n2. [x] dos\n\n---\n\nfin sin salto"
        let length = (text as NSString).length
        for span in spans(text) {
            #expect(span.range.location >= 0 && NSMaxRange(span.range) <= length, "\(span)")
        }
    }

    @Test("El estilo no cambia ni un carácter y marca los enlaces")
    func styler() throws {
        let text = "# Ventas\n\n**Estado:** preparada · [Oferta](Sistemas/Oferta.md) · [[Rumbo]]"
        let styled = MarkdownStyler.attributed(markdown: text)
        #expect(styled.string == text)

        let ns = text as NSString
        let linkAt = ns.range(of: "[Oferta]").location
        #expect(styled.attribute(.link, at: linkAt, effectiveRange: nil) as? String == "Sistemas/Oferta.md")
        let wikiAt = ns.range(of: "[[Rumbo]]").location
        #expect(styled.attribute(.link, at: wikiAt, effectiveRange: nil) as? String == "[[Rumbo]]")

        let titleFont = try #require(styled.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        #expect(titleFont.pointSize > MarkdownStyler.baseSize)
        let boldFont = try #require(styled.attribute(.font, at: ns.range(of: "Estado").location,
                                                     effectiveRange: nil) as? NSFont)
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("Texto plano en monoespaciada")
    func plain() throws {
        let styled = MarkdownStyler.plain("a,b\n1,2")
        let font = try #require(styled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.isFixedPitch)
    }
}
