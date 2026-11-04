import AppKit
import CoreText
import Foundation
import PDFKit

/// Ficheros generados en una carpeta temporal propia de cada prueba (se borra al terminar).
struct FicherosDePrueba {
    let carpeta: URL

    init() throws {
        carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-visores-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    }

    func limpiar() { try? FileManager.default.removeItem(at: carpeta) }

    /// PDF con una página por elemento (cada uno, líneas de texto) y, si se pide, un índice.
    @discardableResult
    func pdf(_ nombre: String = "factura.pdf", paginas: [[String]], indice: [(String, Int)] = []) throws -> URL {
        let url = carpeta.appendingPathComponent(nombre)
        var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { throw CocoaError(.fileWriteUnknown) }
        for lineas in paginas {
            ctx.beginPDFPage(nil)
            var y: CGFloat = 760
            for (i, texto) in lineas.enumerated() {
                let fuente = NSFont.systemFont(ofSize: i == 0 ? 22 : 13, weight: i == 0 ? .bold : .regular)
                let linea = CTLineCreateWithAttributedString(NSAttributedString(string: texto, attributes: [.font: fuente]))
                ctx.textPosition = CGPoint(x: 72, y: y)
                CTLineDraw(linea, ctx)
                y -= i == 0 ? 40 : 22
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        if !indice.isEmpty, let doc = PDFDocument(url: url) {
            let raiz = PDFOutline()
            for (i, (titulo, pagina)) in indice.enumerated() {
                let entrada = PDFOutline()
                entrada.label = titulo
                if let page = doc.page(at: pagina - 1) {
                    entrada.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 842))
                }
                raiz.insertChild(entrada, at: i)
            }
            doc.outlineRoot = raiz
            doc.write(to: url)
        }
        return url
    }

    /// PNG de `ancho × alto` píxeles, azul noche.
    @discardableResult
    func png(_ nombre: String = "logo.png", ancho: Int = 300, alto: Int = 200) throws -> URL {
        let url = carpeta.appendingPathComponent(nombre)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: ancho, pixelsHigh: alto, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { throw CocoaError(.fileWriteUnknown) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(red: 30 / 255, green: 42 / 255, blue: 120 / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: ancho, height: alto).fill()
        NSColor.white.setFill()
        NSRect(x: ancho / 4, y: alto / 4, width: ancho / 2, height: alto / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        return url
    }

    @discardableResult
    func svg(_ nombre: String = "marca.svg") throws -> URL {
        let url = carpeta.appendingPathComponent(nombre)
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="#1E2A78"/></svg>"##.utf8)
            .write(to: url)
        return url
    }

    static func huella(_ url: URL) throws -> Data {
        try Data(contentsOf: url)
    }
}
