import Foundation
import PDFKit
import Testing
import TLSCore
@testable import TLSImport

@Suite("Ordenar lo que tienes · fechas de documentos y reconocimiento de texto", .serialized)
struct FechasYOCRTests {
    static let hoy = EmpresaDePrueba.hoy

    func dater(_ ocr: (any ReconocedorDeTexto)? = nil) -> DocumentDater {
        DocumentDater(opciones: .init(hoy: Self.hoy, ocr: ocr))
    }

    func temporal(_ nombre: String, _ datos: Data) throws -> (URL, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tls-fechas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent(nombre)
        try datos.write(to: u)
        return (dir, u)
    }

    @Test("PDF: la fecha con etiqueta manda; «vencimiento» no es la del documento")
    func etiquetas() throws {
        let d = dater()
        #expect(d.fechaConEtiqueta("Factura nº 7\nFecha de emisión: 14/10/2026\nVencimiento: 30/10/2026") == "2026-10-14")
        #expect(d.fechaConEtiqueta("Fecha de vencimiento: 30/10/2026") == nil)
        #expect(d.fechaConEtiqueta("Date of issue: October 2, 2026") == "2026-10-02")
        #expect(d.fechas(en: "Del 03-02-2026 al 2026-05-01").map(\.fecha) == ["2026-02-03", "2026-05-01"])
        #expect(DocumentDater.intercambiadas("2025-02-11", "2025-11-02"))
        let (dir, u) = try temporal("Factura proveedor.pdf", pdf("FACTURA\nFecha: 05/09/2026\nVencimiento: 05/10/2026"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = try #require(d.fecha(de: u, ruta: VaultPath("4 · Finanzas/Fiscal/Factura proveedor.pdf")))
        #expect(f.fecha == "2026-09-05" && f.fuente == .documento)
    }

    @Test("PDF con fecha de EE. UU. que el nombre confirma al revés")
    func formatoEEUU() throws {
        let (dir, u) = try temporal("Recibo 2026-02-11.pdf", pdf("Receipt\nDate paid: 11/02/2026"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = try #require(dater().fecha(de: u, ruta: VaultPath("Recibo 2026-02-11.pdf")))
        // El texto se lee 11 de febrero (día/mes); el nombre dice 2026-02-11: coinciden.
        #expect(f.fecha == "2026-02-11")
        // El texto dice 03/05/2026 (se lee 3 de mayo) y el nombre 2026-03-05: es el orden de EE. UU. y manda el nombre.
        let (dir2, u2) = try temporal("Recibo 2026-03-05.pdf", pdf("Receipt\nDate paid: 03/05/2026"))
        defer { try? FileManager.default.removeItem(at: dir2) }
        let g = try #require(dater().fecha(de: u2, ruta: VaultPath("Recibo 2026-03-05.pdf")))
        #expect(g.fecha == "2026-03-05" && g.fuente == .documento)
        #expect(g.nota == "fecha en formato de EE. UU. (mes/día), confirmada por el nombre")
    }

    @Test("Sin texto ni nombre: escaneo (OCR) y, si no, la fecha de creación del PDF")
    func escaneoYMetadatos() throws {
        let falso = ReconocedorFalso("FACTURA\nFecha: 07/07/2026")
        let (dir, u) = try temporal("escaneo.pdf", pdfEscaneado("FACTURA Fecha: 07/07/2026"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = try #require(dater(falso).fecha(de: u, ruta: VaultPath("escaneo.pdf")))
        #expect(f.fecha == "2026-07-07" && f.fuente == .documento && f.nota == "leída del escaneo (OCR)")
        #expect(falso.llamadas.withLock { $0 } == 1)
        // Sin OCR que lea nada: los metadatos.
        let (dir2, u2) = try temporal("vacio.pdf", pdfConFechaDeCreacion("D:20260304120000Z"))
        defer { try? FileManager.default.removeItem(at: dir2) }
        let g = try #require(dater(ReconocedorFalso("")).fecha(de: u2, ruta: VaultPath("vacio.pdf")))
        #expect(g.fecha == "2026-03-04" && g.fuente == .metadatos)
    }

    @Test("Documentos de Office: la fecha de creación de docProps/core.xml (guardado y comprimido)")
    func office() throws {
        let core = Data(#"<?xml version="1.0"?><cp:coreProperties><dcterms:created xsi:type="dcterms:W3CDTF">2026-05-06T10:00:00Z</dcterms:created></cp:coreProperties>"#.utf8)
        for comprimir in [false, true] {
            let (dir, u) = try temporal("Contrato.docx", zip("docProps/core.xml", core, comprimir: comprimir))
            defer { try? FileManager.default.removeItem(at: dir) }
            let f = try #require(dater().fecha(de: u, ruta: VaultPath("Contrato.docx")))
            #expect(f.fecha == "2026-05-06" && f.fuente == .metadatos)
        }
    }

    @Test("La fecha de la carpeta, para lo que no tiene otra; las notas no")
    func carpeta() throws {
        let (dir, u) = try temporal("hoja.xlsx", Data("no es un zip".utf8))
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = try #require(dater().fecha(de: u, ruta: VaultPath("Gestoría/2026-04-30 cierre/hoja.xlsx")))
        #expect(f.fecha == "2026-04-30" && f.nota == "fecha del nombre de la carpeta")
        #expect(DocumentDater.necesitaFila(VaultPath("4 · Finanzas/Fiscal/2026/T3/Gastos/luz.pdf"), layout: .humana))
        #expect(!DocumentDater.necesitaFila(VaultPath("4 · Finanzas/Fiscal/2026/T3/Gastos/2026-07-01 luz.pdf"), layout: .humana))
        #expect(!DocumentDater.necesitaFila(VaultPath("4 · Finanzas/Fiscal/2026/T3/nota.md"), layout: .humana))
        #expect(!DocumentDater.necesitaFila(VaultPath("2 · Ventas/luz.pdf"), layout: .humana))
    }

    @Test("Vision lee de verdad una imagen y una página escaneada, todo en el Mac")
    func visionDeVerdad() throws {
        let (dir, u) = try temporal("ticket.png", png("Fecha: 12/03/2026\nTOTAL 15,00"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let texto = try OCRService().texto(deImagen: u)
        #expect(texto.contains("12/03/2026"), "Leído: \(texto)")
        let f = try #require(dater(OCRService()).fecha(de: u, ruta: VaultPath("ticket.png")))
        #expect(f.fecha == "2026-03-12" && f.nota == "leída de la imagen (OCR)")
        let (dir2, u2) = try temporal("escaneo.pdf", pdfEscaneado("Fecha: 21/09/2026"))
        defer { try? FileManager.default.removeItem(at: dir2) }
        let g = try #require(dater(OCRService()).fecha(de: u2, ruta: VaultPath("escaneo.pdf")))
        #expect(g.fecha == "2026-09-21" && g.nota == "leída del escaneo (OCR)")
    }

    @Test("Las notas de las fechas no usan jerga")
    func glosario() {
        for nota in ["fecha en formato de EE. UU. (mes/día), confirmada por el nombre", "primera fecha del texto",
                     "leída del escaneo (OCR)", "fecha de creación del PDF; el texto no trae fecha", "leída de la imagen (OCR)",
                     "fecha de creación del documento", "fecha del nombre de la carpeta", "solo el mes"] {
            #expect(jerga(nota).isEmpty)
        }
    }
}
