import AppKit
import CoreText
import Foundation
import PDFKit
import SwiftUI
import Testing
import TLSCore
import TLSDesign
import TLSVisores
@testable import TLSUI

/// Capturas fuera de pantalla del rol de visores (sin abrir la app): visor de PDF, Carpeta, renombrar con su
/// vista previa, el arranque y una incrustación, en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>`.
@Suite("Capturas · visores, Carpeta y arranque", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasVisoresTests {
    let capturas = CapturasTests()
    let pruebas = SesionEscrituraTests()

    /// PDF de varias páginas con índice, en una carpeta temporal.
    static func pdfDePrueba(en carpeta: URL) throws -> URL {
        let url = carpeta.appendingPathComponent("Factura F-2026-0014.pdf")
        var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { throw CocoaError(.fileWriteUnknown) }
        let paginas: [[String]] = [
            ["Factura F-2026-0014", "Asesoría Ribera Demo SL · B00000000 (ficticio)", "", "Cliente: Talleres Martín SL",
             "Servicio: Trimestrales 2026", "Fecha: 14/10/2026"],
            ["Conceptos", "Asesoría fiscal trimestral (T3)          240,00 €", "IVA 21 %                                        50,40 €",
             "", "Total                                          290,40 €"],
            ["Condiciones", "Pago por transferencia en 15 días.", "Cláusula de confidencialidad."],
            ["Anexo", "Documentación recibida del cliente."],
        ]
        for lineas in paginas {
            ctx.beginPDFPage(nil)
            ctx.setFillColor(CGColor(red: 30 / 255, green: 42 / 255, blue: 120 / 255, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 800, width: 595, height: 42))
            var y: CGFloat = 740
            for (i, texto) in lineas.enumerated() {
                let fuente = NSFont.systemFont(ofSize: i == 0 ? 26 : 14, weight: i == 0 ? .bold : .regular)
                let linea = CTLineCreateWithAttributedString(NSAttributedString(string: texto, attributes: [.font: fuente]))
                ctx.textPosition = CGPoint(x: 64, y: y)
                CTLineDraw(linea, ctx)
                y -= i == 0 ? 44 : 24
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        if let doc = PDFDocument(url: url) {
            let raiz = PDFOutline()
            for (i, (t, p)) in [("Factura", 0), ("Conceptos y total", 1), ("Condiciones", 2), ("Anexo", 3)].enumerated() {
                let e = PDFOutline()
                e.label = t
                if let page = doc.page(at: p) { e.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 842)) }
                raiz.insertChild(e, at: i)
            }
            doc.outlineRoot = raiz
            doc.write(to: url)
        }
        return url
    }

    @Test("Visor de PDF: páginas, índice y búsqueda")
    func visorPDF() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tls-capturas-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let url = try Self.pdfDePrueba(en: tmp)
        for oscuro in [false, true] {
            let c = ControladorPDF()
            c.cargar(url: url)
            c.panel = .miniaturas
            try await capturas.capturar(VisorPDF(controlador: c, url: url).padding(24).background(TLSPaleta.fondo.color),
                                        ancho: 1100, alto: 780, oscuro: oscuro, nombre: "visores-pdf", ventana: true)
            let b = ControladorPDF()
            b.cargar(url: url)
            b.buscar("total")
            try await capturas.capturar(VisorPDF(controlador: b, url: url).padding(24).background(TLSPaleta.fondo.color),
                                        ancho: 1100, alto: 780, oscuro: oscuro, nombre: "visores-pdf-busqueda", ventana: true)
        }
        let i = ControladorPDF()
        i.cargar(url: url, pagina: 2)
        i.panel = .indice
        try await capturas.capturar(VisorPDF(controlador: i, url: url).padding(24).background(TLSPaleta.fondo.color),
                                    ancho: 760, alto: 620, oscuro: false, nombre: "visores-pdf-indice-estrecho", ventana: true)
        // Incrustación en una nota (`![[factura.pdf#page=2]]`) y la vista previa compacta de una ficha.
        let incrustada = VStack(alignment: .leading, spacing: 16) {
            Text("Notas de la reunión").tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
            IncrustacionFichero(url: url, tipo: .pdf, pagina: 2, alAbrir: {})
            HStack(alignment: .top, spacing: 16) {
                VistaPreviaPDF(url: url, alAbrir: {}).frame(width: 260)
                VistaPreviaPDF(url: url, pagina: 2, alto: 200, alAbrir: {}).frame(width: 220)
            }
        }
        .padding(24)
        .background(TLSPaleta.fondo.color)
        for oscuro in [false, true] {
            try await capturas.capturar(incrustada, ancho: 820, alto: 980, oscuro: oscuro, nombre: "visores-incrustacion", ventana: true)
        }
    }

    @Test("Carpeta, fichero de Ribera, renombrar con vista previa y lo movido fuera")
    func carpeta() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }

        func pantalla(_ destino: Destino, _ nav: Navegacion) -> some View {
            PantallaDestino(destino: destino, sesion: sesion)
                .environment(e.model)
                .environment(\.navegacion, nav)
        }
        for oscuro in [false, true] {
            try await capturas.capturar(pantalla(.carpeta(nil), Navegacion(raiz: .carpeta(nil))),
                                        ancho: 1000, alto: 760, oscuro: oscuro, nombre: "visores-carpeta-raiz", ventana: true)
            let nav = Navegacion(raiz: .carpeta(nil))
            nav.entrar(.carpeta(VaultPath("2 · Ventas/Contactos")))
            nav.actualizarRecuerdo(de: .carpeta(VaultPath("2 · Ventas/Contactos"))) { $0.seleccion = [pruebas.jorge.raw] }
            try await capturas.capturar(pantalla(.carpeta(VaultPath("2 · Ventas/Contactos")), nav),
                                        ancho: 1000, alto: 760, oscuro: oscuro, nombre: "visores-carpeta-contactos", ventana: true)
            let pdf = VaultPath("4 · Finanzas/Fiscal/2026/T3/Gastos/movil-levante/2026-07-10 Movil Levante ML-07-2026 78,65€.pdf")
            try await capturas.capturar(pantalla(.fichero(pdf), Navegacion(raiz: .carpeta(nil))),
                                        ancho: 1100, alto: 820, oscuro: oscuro, nombre: "visores-fichero-ribera", ventana: true)
        }

        let modelo = CarpetaModelo(carpeta: VaultPath("2 · Ventas/Productos"), sesion: sesion)
        await modelo.cargar()
        try await capturas.capturar(HojaRenombrar(modelo: modelo, ruta: VaultPath("2 · Ventas/Productos/renta.md"),
                                                  nombrePropuesto: "renta-anual"),
                                    ancho: 600, alto: 620, oscuro: false, nombre: "visores-renombrar", ventana: true)
        try await capturas.capturar(HojaNueva(modelo: CarpetaModelo(carpeta: VaultPath("2 · Ventas/Contactos"), sesion: sesion),
                                              seleccion: pruebas.jorge, alCrear: { _ in }),
                                    ancho: 600, alto: 620, oscuro: false, nombre: "visores-nueva", ventana: true)

        // Lo movido en Finder (solo en la copia temporal) y su tarjeta.
        try FileManager.default.moveItem(at: e.carpeta.appendingPathComponent("2 · Ventas/Productos/Oferta.md"),
                                         to: e.carpeta.appendingPathComponent("2 · Ventas/Productos/Versiones/Oferta.md"))
        try await capturas.capturar(pantalla(.carpeta(VaultPath("2 · Ventas/Productos")), Navegacion(raiz: .carpeta(VaultPath("2 · Ventas/Productos")))),
                                    ancho: 1000, alto: 620, oscuro: false, nombre: "visores-carpeta-movido-fuera", ventana: true)
    }

    @Test("Arranque con el ejemplo instalado y una copia")
    func arranque() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-capturas-arranque-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup", isDirectory: true)))
        let instalador = InstaladorEjemplo(origen: SesionEscrituraTests.ribera, empresas: base.appendingPathComponent("Empresas")) { _ in }
        for oscuro in [false, true] {
            try await capturas.capturar(LauncherView(instalador: instalador).environment(model),
                                        ancho: 760, alto: 540, oscuro: oscuro, nombre: "visores-arranque-vacio", ventana: true)
        }
        _ = try await instalador.instalarOAbrir(en: model)
        let copia = base.appendingPathComponent("Empresas/Mi empresa (copia)")
        try FileManager.default.createDirectory(at: copia, withIntermediateDirectories: true)
        try model.register(VaultEntry(nombre: "Estudio Ribera", ruta: copia.path, bookmark: nil, clase: .copia, escritura: .permitida))
        for oscuro in [false, true] {
            try await capturas.capturar(LauncherView(instalador: instalador).environment(model),
                                        ancho: 760, alto: 540, oscuro: oscuro, nombre: "visores-arranque", ventana: true)
        }
    }
}
