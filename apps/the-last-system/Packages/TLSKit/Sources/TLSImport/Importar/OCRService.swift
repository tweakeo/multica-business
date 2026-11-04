// Procedencia: lógica portada a Swift desde FORK/scripts/tls/tls-ocr.swift (autor: Manuel Trigo).
// Reescrito como servicio (sin compilar un ejecutable aparte; imágenes con ImageIO y páginas de PDF con
// CoreGraphics); sin código copiado. Ver docs/PROCEDENCIA.md.

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Reconoce el texto de una imagen o de una página escaneada. Se sustituye en las pruebas.
public protocol ReconocedorDeTexto: Sendable {
    func texto(deImagen url: URL) throws -> String
    func texto(dePDF url: URL, pagina: Int) throws -> String
}

public enum OCRError: Error, LocalizedError, Sendable {
    case imagenIlegible(String)
    case paginaIlegible(String)

    public var errorDescription: String? {
        switch self {
        case .imagenIlegible(let n): "No he podido abrir la imagen «\(n)»."
        case .paginaIlegible(let n): "No he podido leer la página escaneada de «\(n)»."
        }
    }
}

/// Texto de escaneos e imágenes con Vision (español e inglés, precisión alta), todo en el Mac.
///
/// Solo para ficheros que ya están en el Mac: quien llama lo comprueba antes (y lo hace en el hilo protegido de
/// `DatalessGuard`, donde un acceso por error a algo que solo está en iCloud da error en vez de descargarlo).
public struct OCRService: ReconocedorDeTexto {
    public var idiomas: [String]
    /// Resolución a la que se pinta una página de PDF antes de leerla (como el original: 200 ppp).
    public var ppp: CGFloat

    public init(idiomas: [String] = ["es-ES", "en-US"], ppp: CGFloat = 200) {
        self.idiomas = idiomas; self.ppp = ppp
    }

    public func texto(deImagen url: URL) throws -> String {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { throw OCRError.imagenIlegible(url.lastPathComponent) }
        return try reconocer(img)
    }

    public func texto(dePDF url: URL, pagina: Int = 0) throws -> String {
        guard let img = Self.pintar(pdf: url, pagina: pagina, ppp: ppp) else { throw OCRError.paginaIlegible(url.lastPathComponent) }
        return try reconocer(img)
    }

    /// Líneas reconocidas, de arriba abajo.
    public func reconocer(_ imagen: CGImage) throws -> String {
        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLevel = .accurate
        peticion.recognitionLanguages = idiomas
        peticion.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: imagen, options: [:]).perform([peticion])
        return (peticion.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Una página de un PDF como imagen (fondo blanco) a `ppp` puntos por pulgada.
    static func pintar(pdf url: URL, pagina: Int, ppp: CGFloat) -> CGImage? {
        guard let doc = CGPDFDocument(url as CFURL), !doc.isEncrypted || doc.isUnlocked,
              let page = doc.page(at: pagina + 1) else { return nil }
        let caja = page.getBoxRect(.mediaBox)
        let escala = ppp / 72
        let ancho = Int((caja.width * escala).rounded()), alto = Int((caja.height * escala).rounded())
        guard ancho > 0, alto > 0, ancho * alto <= 60_000_000,
              let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return nil
        }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
        ctx.scaleBy(x: escala, y: escala)
        ctx.translateBy(x: -caja.minX, y: -caja.minY)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }
}
