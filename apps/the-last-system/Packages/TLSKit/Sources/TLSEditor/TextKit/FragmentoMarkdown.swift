import AppKit
import TLSDesign

/// Fragmento de TextKit 2 que dibuja lo que el texto no tiene: el fondo de los bloques de código y de los
/// avisos, las barras de cita, la raya de un separador, las casillas, las viñetas y los fondos redondeados
/// del código en línea y las etiquetas. Los caracteres de debajo siguen ahí (invisibles): el texto no cambia.
final class FragmentoMarkdown: NSTextLayoutFragment {
    private let deco: DecoracionBloque
    private let casillas: [(NSRange, Bool)]
    private let vinetas: [NSRange]
    private let fondos: [(NSRange, TLSColor)]
    private let apariencia: NSAppearance?
    private let escala: CGFloat

    init(textElement: NSTextElement, range: NSTextRange?, deco: DecoracionBloque, apariencia: NSAppearance?, escala: CGFloat) {
        self.deco = deco
        self.apariencia = apariencia
        self.escala = escala
        var casillas: [(NSRange, Bool)] = []
        var vinetas: [NSRange] = []
        var fondos: [(NSRange, TLSColor)] = []
        if let p = textElement as? NSTextParagraph {
            let s = p.attributedString
            let todo = NSRange(location: 0, length: s.length)
            if !deco.marcasVisibles {
                s.enumerateAttribute(.tlsCasilla, in: todo) { v, r, _ in
                    if let b = v as? Bool { casillas.append((r, b)) }
                }
                s.enumerateAttribute(.tlsVineta, in: todo) { v, r, _ in
                    if v != nil { vinetas.append(r) }
                }
            }
            s.enumerateAttribute(.tlsFondo, in: todo) { v, r, _ in
                if let c = v as? TLSColorCaja { fondos.append((r, c.color)) }
            }
        }
        self.casillas = casillas
        self.vinetas = vinetas
        self.fondos = fondos
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) { nil }

    private var anchoContenedor: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    private var ocupaTodoElAncho: Bool { deco.fondo != nil || deco.cita > 0 || deco.separador }

    override var renderingSurfaceBounds: CGRect {
        var r = super.renderingSurfaceBounds
        if ocupaTodoElAncho {
            r = r.union(CGRect(x: -layoutFragmentFrame.minX, y: -8, width: anchoContenedor,
                               height: layoutFragmentFrame.height + 16))
        }
        return r
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let pintar = {
            self.dibujarFondos(at: point, in: context)
            super.draw(at: point, in: context)
            self.dibujarEncima(at: point, in: context)
        }
        if let apariencia { apariencia.performAsCurrentDrawingAppearance(pintar) } else { pintar() }
    }

    // MARK: Detrás del texto

    private func dibujarFondos(at point: CGPoint, in ctx: CGContext) {
        let lineas = textLineFragments
        let x0 = point.x - layoutFragmentFrame.minX
        if let fondo = deco.fondo {
            let pos: PosicionEnBloque
            let color: NSColor
            switch fondo {
            case .codigo(let p):
                pos = p
                color = TLSPaleta.bandeja.ns
            case .aviso(let tipo, let p):
                pos = p
                color = AspectoAviso.colores(tipo).fondo.ns
            }
            // Las líneas de en medio se solapan medio punto con la siguiente para que no se vea la costura.
            let arriba = pos.esPrimera ? (lineas.first?.typographicBounds.minY ?? 0) - 6 : -0.5
            let abajo = pos.esUltima ? (lineas.last?.typographicBounds.maxY ?? layoutFragmentFrame.height) + 6
                                     : layoutFragmentFrame.height + 0.5
            let rect = CGRect(x: x0, y: point.y + arriba, width: anchoContenedor, height: abajo - arriba)
            let radio: CGFloat = TLSRadio.campo
            let camino = NSBezierPath()
            let tl = pos.esPrimera ? radio : 0, bl = pos.esUltima ? radio : 0
            // Rectángulo con las esquinas de arriba o de abajo redondeadas (coordenadas giradas: y hacia abajo).
            camino.move(to: CGPoint(x: rect.minX, y: rect.minY + tl))
            if tl > 0 { camino.appendArc(withCenter: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: 180, endAngle: 270) }
            camino.line(to: CGPoint(x: rect.maxX - tl, y: rect.minY))
            if tl > 0 { camino.appendArc(withCenter: CGPoint(x: rect.maxX - tl, y: rect.minY + tl), radius: tl, startAngle: 270, endAngle: 360) }
            camino.line(to: CGPoint(x: rect.maxX, y: rect.maxY - bl))
            if bl > 0 { camino.appendArc(withCenter: CGPoint(x: rect.maxX - bl, y: rect.maxY - bl), radius: bl, startAngle: 0, endAngle: 90) }
            camino.line(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
            if bl > 0 { camino.appendArc(withCenter: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: 90, endAngle: 180) }
            camino.close()
            color.setFill()
            camino.fill()
            if case .aviso(let tipo, let p) = fondo, p.esPrimera, let primera = lineas.first {
                let lado = 17 * escala
                let y = point.y + primera.typographicBounds.minY + (primera.typographicBounds.height - lado) / 2
                dibujarSimbolo(AspectoAviso.simbolo(tipo), color: AspectoAviso.colores(tipo).tinta.ns,
                               en: CGRect(x: x0 + 14, y: y, width: lado, height: lado))
            }
        }
        for (r, color) in fondos {
            color.ns.setFill()
            for rect in rectangulos(de: r, en: lineas) {
                NSBezierPath(roundedRect: rect.offsetBy(dx: point.x, dy: point.y).insetBy(dx: -3, dy: 0),
                             xRadius: 5, yRadius: 5).fill()
            }
        }
    }

    // MARK: Encima del texto

    private func dibujarEncima(at point: CGPoint, in ctx: CGContext) {
        let lineas = textLineFragments
        let x0 = point.x - layoutFragmentFrame.minX
        if deco.cita > 0 {
            TLSPaleta.bordeControl.ns.setFill()
            for i in 0..<deco.cita {
                NSBezierPath(roundedRect: CGRect(x: x0 + 2 + CGFloat(i) * 16, y: point.y, width: 3,
                                                 height: layoutFragmentFrame.height), xRadius: 1.5, yRadius: 1.5).fill()
            }
        }
        if deco.separador, let l = lineas.first {
            TLSPaleta.separador.ns.setFill()
            let y = point.y + l.typographicBounds.midY
            NSRect(x: x0, y: y.rounded(), width: anchoContenedor, height: 1).fill()
        }
        for r in vinetas {
            for rect in rectangulos(de: r, en: lineas) {
                let d = 5.5 * escala
                let c = CGPoint(x: point.x + rect.midX, y: point.y + centroY(r))
                TLSPaleta.textoSecundario.ns.setFill()
                NSBezierPath(ovalIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)).fill()
            }
        }
        for (r, hecha) in casillas {
            guard let rect = rectangulos(de: r, en: lineas).first else { continue }
            let lado = min(15 * escala, rect.width + 2)
            let caja = CGRect(x: point.x + rect.midX - lado / 2, y: point.y + centroY(r) - lado / 2,
                              width: lado, height: lado)
            let camino = NSBezierPath(roundedRect: caja.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            if hecha {
                TLSPaleta.principal.ns.setFill()
                camino.fill()
                let check = NSBezierPath()
                check.lineWidth = 1.8 * escala
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                check.move(to: CGPoint(x: caja.minX + lado * 0.26, y: caja.minY + lado * 0.53))
                check.line(to: CGPoint(x: caja.minX + lado * 0.43, y: caja.minY + lado * 0.70))
                check.line(to: CGPoint(x: caja.minX + lado * 0.75, y: caja.minY + lado * 0.32))
                TLSPaleta.sobrePrincipal.ns.setStroke()
                check.stroke()
            } else {
                TLSPaleta.superficie.ns.setFill()
                camino.fill()
                TLSPaleta.bordeControl.ns.setStroke()
                camino.lineWidth = 1.2
                camino.stroke()
            }
        }
    }

    /// Centro vertical (coordenadas del fragmento) de la altura de la x del tramo: donde van la viñeta y la casilla.
    private func centroY(_ r: NSRange) -> CGFloat {
        guard let linea = linea(de: r.location) else { return 8 }
        let s = linea.attributedString
        let fuente = (s.attribute(.font, at: min(r.location, max(0, s.length - 1)), effectiveRange: nil) as? NSFont)
            ?? NSFont.systemFont(ofSize: 15)
        return linea.typographicBounds.minY + linea.glyphOrigin.y - fuente.xHeight / 2
    }

    private func linea(de indice: Int) -> NSTextLineFragment? {
        textLineFragments.first { NSLocationInRange(indice, $0.characterRange) || NSMaxRange($0.characterRange) == indice }
    }

    /// Rectángulos (coordenadas del fragmento) que ocupa un tramo, uno por línea.
    private func rectangulos(de r: NSRange, en lineas: [NSTextLineFragment]) -> [CGRect] {
        var out: [CGRect] = []
        for l in lineas {
            let cr = l.characterRange
            let a = max(r.location, cr.location), b = min(NSMaxRange(r), NSMaxRange(cr))
            guard b > a else { continue }
            let xa = l.locationForCharacter(at: a).x
            let xb = l.locationForCharacter(at: b).x
            let tb = l.typographicBounds
            let fuente = (l.attributedString.attribute(.font, at: a, effectiveRange: nil) as? NSFont)
            let alto = fuente.map { $0.ascender - $0.descender + 2 } ?? tb.height
            let arriba = tb.minY + l.glyphOrigin.y - (fuente?.ascender ?? tb.height) - 1
            out.append(CGRect(x: tb.minX + min(xa, xb), y: arriba, width: abs(xb - xa), height: alto))
        }
        return out
    }

    private func dibujarSimbolo(_ nombre: String, color: NSColor, en rect: CGRect) {
        let config = NSImage.SymbolConfiguration(pointSize: rect.height * 0.9, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: nombre, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let s = img.size
        let escalaImg = min(rect.width / max(s.width, 1), rect.height / max(s.height, 1))
        let w = s.width * escalaImg, h = s.height * escalaImg
        img.draw(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h), from: .zero, operation: .sourceOver,
                 fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Delegado de la disposición: da `FragmentoMarkdown` a las líneas que dibujan algo.
final class DelegadoDisposicion: NSObject, NSTextLayoutManagerDelegate {
    /// Apariencia y escala con las que se dibuja (las pone el controlador en el hilo principal).
    nonisolated(unsafe) var apariencia: NSAppearance?
    nonisolated(unsafe) var escala: CGFloat = 1

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        if let p = textElement as? NSTextParagraph, p.attributedString.length > 0,
           let deco = p.attributedString.attribute(.tlsBloque, at: 0, effectiveRange: nil) as? DecoracionBloque {
            return FragmentoMarkdown(textElement: textElement, range: textElement.elementRange, deco: deco,
                                     apariencia: apariencia, escala: escala)
        }
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
