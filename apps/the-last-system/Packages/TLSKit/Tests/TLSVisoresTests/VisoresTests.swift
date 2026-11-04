import AppKit
import Foundation
import PDFKit
import Synchronization
import Testing
@testable import TLSVisores

/// Visor de PDF (R1): páginas, zoom, búsqueda, índice, selección y copia, sin escribir el fichero.
@Suite("TLSVisores · PDF", .serialized)
@MainActor
struct VisorPDFTests {
    static let paginas: [[String]] = [
        ["Factura F-2026-0014", "Asesoría Ribera Demo SL", "Talleres Martín", "Trimestrales 2026"],
        ["Conceptos", "Asesoría fiscal trimestral 240,00 €", "IVA 21 % 50,40 €", "Total 290,40 €"],
        ["Anexo", "Cláusula de confidencialidad", "Firma"],
    ]

    @Test("Abre un PDF generado: páginas, ir a una página y empezar en la de #page=N")
    func paginas() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.pdf(paginas: Self.paginas)
        let c = ControladorPDF()
        #expect(c.cargar(url: url))
        #expect(c.totalPaginas == 3)
        #expect(c.numeroPagina == 1)
        #expect(c.textoPagina == "Página 1 de 3")
        c.ir(aPagina: 2)
        #expect(c.numeroPagina == 2)
        c.paginaSiguiente()
        #expect(c.numeroPagina == 3)
        #expect(!c.puedeIrAdelante)
        c.ir(aPagina: 99)
        #expect(c.numeroPagina == 3)
        c.ir(aPagina: -4)
        #expect(c.numeroPagina == 1)
        #expect(c.texto(dePagina: 2)?.contains("290,40") == true)

        let otro = ControladorPDF()
        #expect(otro.cargar(url: url, pagina: 3))
        #expect(otro.numeroPagina == 3)
    }

    @Test("Buscar en el texto: sin mayúsculas ni tildes, con la página y el trozo de línea")
    func buscar() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.pdf(paginas: Self.paginas)
        let c = ControladorPDF()
        c.cargar(url: url)
        #expect(c.buscar("total") == 1)
        #expect(c.resultados.first?.pagina == 2)
        #expect(c.resultados.first?.fragmento.contains("290,40") == true)
        #expect(c.numeroPagina == 2)
        #expect(c.panel == .resultados)
        #expect(c.textoResultados == "1 de 1")
        #expect(c.buscar("CLAUSULA") == 1)
        #expect(c.resultados.first?.pagina == 3)
        #expect(c.buscar("asesoría") == 2)
        c.siguienteResultado()
        #expect(c.resultadoElegido == 1)
        #expect(c.numeroPagina == 2)
        c.siguienteResultado()
        #expect(c.resultadoElegido == 0)
        c.anteriorResultado()
        #expect(c.resultadoElegido == 1)
        #expect(c.buscar("no aparece") == 0)
        #expect(c.textoResultados == "No sale en el PDF")
        c.limpiarBusqueda()
        #expect(c.resultados.isEmpty && c.busqueda.isEmpty)
    }

    @Test("Índice del PDF: entradas con su página y navegar con ellas")
    func indice() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.pdf(paginas: Self.paginas, indice: [("Factura", 1), ("Conceptos y total", 2), ("Anexo", 3)])
        let c = ControladorPDF()
        c.cargar(url: url)
        #expect(c.indice.map(\.titulo) == ["Factura", "Conceptos y total", "Anexo"])
        #expect(c.indice.map(\.pagina) == [1, 2, 3])
        c.ir(a: c.indice[2])
        #expect(c.numeroPagina == 3)
    }

    @Test("Zoom: ajustar a ancho, a página, acercar, alejar y tamaño real")
    func zoom() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.pdf(paginas: Self.paginas)
        let c = ControladorPDF()
        c.vista.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        c.cargar(url: url)
        #expect(c.ajuste == .ancho)
        #expect(c.vista.displayMode == .singlePageContinuous && c.vista.autoScales)
        c.ajustarPagina()
        #expect(c.ajuste == .pagina)
        #expect(c.vista.displayMode == .singlePage && c.vista.autoScales)
        c.tamanoReal()
        #expect(c.ajuste == .libre)
        #expect(abs(c.escala - 1) < 0.001)
        #expect(c.textoEscala == "100 %")
        c.acercar()
        #expect(c.escala > 1.2)
        c.alejar()
        c.alejar()
        #expect(c.escala < 1)
        for _ in 0..<40 { c.alejar() }
        #expect(c.escala >= ControladorPDF.escalaMinima - 0.0001)
        c.ajustarAncho()
        #expect(c.ajuste == .ancho && c.vista.autoScales)
    }

    @Test("Elegir texto y copiarlo (en un portapapeles propio, no en el del Mac)")
    func copiar() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.pdf(paginas: Self.paginas)
        let c = ControladorPDF()
        c.cargar(url: url)
        let portapapeles = NSPasteboard(name: NSPasteboard.Name("tls-pruebas-\(UUID().uuidString)"))
        defer { portapapeles.releaseGlobally() }
        #expect(!c.copiarSeleccion(en: portapapeles))
        #expect(c.elegir(texto: "Talleres Martín"))
        #expect(c.textoSeleccionado == "Talleres Martín")
        #expect(c.copiarSeleccion(en: portapapeles))
        #expect(portapapeles.string(forType: .string) == "Talleres Martín")
    }

    @Test("Nunca escribe el fichero: tras navegar, buscar, hacer zoom y elegir, los bytes son los mismos")
    func noEscribe() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.pdf(paginas: Self.paginas, indice: [("Factura", 1)])
        let antes = try FicherosDePrueba.huella(url)
        let fecha = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let c = ControladorPDF()
        c.cargar(url: url)
        c.buscar("total")
        _ = c.elegir(texto: "Firma")
        c.acercar()
        c.ajustarPagina()
        c.paginaSiguiente()
        if let clic = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
            #expect(c.vista.menu(for: clic)?.items.contains { $0.title == "Copiar" } == true)
        }
        #expect(try FicherosDePrueba.huella(url) == antes)
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == fecha)
    }

    @Test("Un fichero que no es PDF da un error en llano, sin romper")
    func pdfDanado() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = f.carpeta.appendingPathComponent("roto.pdf")
        try Data("esto no es un PDF".utf8).write(to: url)
        let c = ControladorPDF()
        #expect(!c.cargar(url: url))
        #expect(c.error?.contains("No he podido abrir este PDF") == true)
        #expect(c.totalPaginas == 0)
        #expect(c.buscar("x") == 0)
    }
}

@Suite("TLSVisores · imágenes y miniaturas", .serialized)
@MainActor
struct VisorImagenTests {
    @Test("Imagen: tamaño en píxeles, ajustar, tamaño real, acercar y alejar")
    func zoom() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let url = try f.png(ancho: 300, alto: 200)
        let c = ControladorImagen()
        c.lienzo.frame = NSRect(x: 0, y: 0, width: 150, height: 150)
        #expect(c.cargar(url: url))
        #expect(c.tamano == CGSize(width: 300, height: 200))
        #expect(c.textoTamano == "300 × 200")
        #expect(c.ajustada)
        #expect(abs(c.escala - 0.5) < 0.01)
        c.tamanoReal()
        #expect(!c.ajustada && abs(c.escala - 1) < 0.001)
        c.acercar()
        #expect(c.escala > 1.2)
        c.alejar()
        c.alejar()
        #expect(c.escala < 1)
        c.ajustar()
        #expect(c.ajustada && abs(c.escala - 0.5) < 0.01)
    }

    @Test("SVG y fichero dañado")
    func svgYDanado() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let c = ControladorImagen()
        #expect(c.cargar(url: try f.svg()))
        #expect(c.tamano.width > 0)
        let roto = f.carpeta.appendingPathComponent("roto.png")
        try Data("nada".utf8).write(to: roto)
        #expect(!c.cargar(url: roto))
        #expect(c.error != nil)
    }

    @Test("Miniaturas: la página pedida de un PDF y una imagen reducida, sin pasar del lado")
    func miniaturas() async throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let pdf = try f.pdf(paginas: VisorPDFTests.paginas)
        let pagina2 = try #require(await MiniaturaFichero.generar(url: pdf, pagina: 2, lado: 300))
        #expect(max(pagina2.tamano.width, pagina2.tamano.height) == 300)
        #expect(pagina2.tamano.height > pagina2.tamano.width)
        #expect(MiniaturaFichero.paginas(dePDF: pdf) == 3)
        let png = try f.png(ancho: 1200, alto: 600)
        let reducida = try #require(await MiniaturaFichero.generar(url: png, lado: 200))
        #expect(max(reducida.tamano.width, reducida.tamano.height) <= 200)
        #expect(await MiniaturaFichero.generar(url: try f.svg(), lado: 100) != nil)
    }
}

/// iCloud: mirar nunca descarga; abrir pide la descarga, enseña el progreso y deja «Volver a intentarlo».
@Suite("TLSVisores · iCloud", .serialized)
@MainActor
struct ICloudTests {
    /// iCloud de mentira: el fichero «llega» tras `pasos` comprobaciones desde que se pidió.
    final class ICloudFalso: AccesoICloud, Sendable {
        private let datos = Mutex<(pedidas: Int, comprobaciones: Int, fallar: Bool, pasos: Int)>((0, 0, false, 2))
        init(fallar: Bool = false, pasos: Int = 2) { datos.withLock { $0.fallar = fallar; $0.pasos = pasos } }
        var pedidas: Int { datos.withLock { $0.pedidas } }
        func noFallar() { datos.withLock { $0.fallar = false } }
        func estado(de url: URL) -> EstadoICloud {
            datos.withLock { e in
                guard e.pedidas > 0 else { return .soloEnICloud(tamano: 2_048) }
                e.comprobaciones += 1
                return e.comprobaciones > e.pasos ? .local : .soloEnICloud(tamano: 2_048)
            }
        }
        func pedirDescarga(de url: URL) throws {
            try datos.withLock { e in
                if e.fallar { throw CocoaError(.fileReadUnknown) }
                e.pedidas += 1
            }
        }
    }

    let url = URL(fileURLWithPath: "/no/existe/acta.pdf")

    @Test("Comprobar solo mira: no pide la descarga")
    func comprobarNoDescarga() {
        let falso = ICloudFalso()
        let d = DescargaICloud(url: url, acceso: falso)
        d.comprobar()
        #expect(d.fase == .soloEnICloud)
        #expect(d.tamano == 2_048)
        #expect(falso.pedidas == 0)
        #expect(d.texto.contains("solo en iCloud"))
    }

    @Test("Abrir pide la descarga una vez y queda lista cuando llega")
    func descargar() async {
        let falso = ICloudFalso(pasos: 2)
        let d = DescargaICloud(url: url, acceso: falso, intervalo: .milliseconds(20))
        d.descargar()
        #expect(falso.pedidas == 1)
        #expect(d.fase == .descargando)
        // Con todo el paquete de pruebas a la vez, el hilo principal puede estar ocupado varios segundos: se espera
        // más (en cuanto está lista, sigue).
        let fin = Date().addingTimeInterval(30)
        while d.fase != .lista, Date() < fin { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(d.fase == .lista)
        #expect(falso.pedidas == 1)
    }

    @Test("Si falla, «Volver a intentarlo» la pide otra vez; si tarda, lo dice")
    func falloYReintento() async {
        let falso = ICloudFalso(fallar: true)
        let d = DescargaICloud(url: url, acceso: falso, intervalo: .milliseconds(20))
        d.descargar()
        guard case .fallo = d.fase else { Issue.record("Esperaba un fallo"); return }
        falso.noFallar()
        d.reintentar()
        #expect(falso.pedidas == 1)
        let lento = ICloudFalso(pasos: 10_000)
        let t = DescargaICloud(url: url, acceso: lento, intervalo: .milliseconds(10), limite: .milliseconds(60))
        t.descargar()
        let fin = Date().addingTimeInterval(5)
        while t.fase != .tardando, Date() < fin { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(t.fase == .tardando)
        t.cancelar()
    }

    @Test("Las miniaturas no descargan: lo que está en iCloud no se pinta")
    func miniaturaNoDescarga() async {
        let falso = ICloudFalso()
        #expect(await MiniaturaFichero.generar(url: url, tipo: .pdf, acceso: falso) == nil)
        #expect(MiniaturaFichero.paginas(dePDF: url, acceso: falso) == nil)
        #expect(falso.pedidas == 0)
    }

    @Test("El de verdad: un fichero normal está en el Mac; el marcador antiguo «.x.icloud», en iCloud")
    func sistema() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let acceso = AccesoICloudSistema()
        let normal = try f.png()
        #expect(acceso.estado(de: normal) == .local)
        #expect(acceso.estado(de: f.carpeta.appendingPathComponent("no-esta.pdf")) == .noExiste)
        try Data().write(to: f.carpeta.appendingPathComponent(".acta.pdf.icloud"))
        #expect(acceso.estado(de: f.carpeta.appendingPathComponent("acta.pdf")) == .soloEnICloud(tamano: nil))
    }
}

/// Incrustaciones `![[…]]` y `![](…)` (R1): qué dice cada una.
@Suite("TLSVisores · incrustaciones")
struct ReferenciaTests {
    @Test("#page, #height, |ancho y destino Markdown con %20")
    func leer() {
        let a = ReferenciaIncrustada.leer("![[factura-2026-014.pdf#page=3]]")
        #expect(a.destino == "factura-2026-014.pdf" && a.pagina == 3 && a.alto == nil)
        #expect(a.tipo == .pdf)
        let b = ReferenciaIncrustada.leer("acta.pdf#page=2&height=500")
        #expect(b.destino == "acta.pdf" && b.pagina == 2 && b.alto == 500)
        let c = ReferenciaIncrustada.leer("Materiales/logo.png|300")
        #expect(c.destino == "Materiales/logo.png" && c.ancho == 300 && c.alto == nil && c.tipo == .imagen)
        let d = ReferenciaIncrustada.leer("logo.png|300x200")
        #expect(d.ancho == 300 && d.alto == 200)
        let e = ReferenciaIncrustada.leer("Materiales/acta%20final.pdf#page=2", markdown: true)
        #expect(e.destino == "Materiales/acta final.pdf" && e.pagina == 2)
        let f = ReferenciaIncrustada.leer("<Materiales/acta final.pdf>", markdown: true)
        #expect(f.destino == "Materiales/acta final.pdf")
        let g = ReferenciaIncrustada.leer("Notas#Resumen")
        #expect(g.destino == "Notas" && g.seccion == "Resumen" && g.pagina == nil)
        let h = ReferenciaIncrustada.leer("x.pdf#page=0")
        #expect(h.pagina == nil)
    }

    @Test("Tipo por nombre y qué se incrusta")
    func tipos() {
        #expect(TipoFichero.de(nombre: "Materiales/acta.pdf") == .pdf)
        #expect(TipoFichero.de(nombre: "sin-extension") == .otro)
        #expect(TipoFichero.de(nombre: ".oculto") == .otro)
        #expect(TipoFichero.pdf.seIncrusta && TipoFichero.audio.seIncrusta && !TipoFichero.otro.seIncrusta)
        #expect(TipoFichero.video.tieneMiniatura && !TipoFichero.audio.tieneMiniatura)
        #expect(IncrustacionFichero.altoPorDefecto(.pdf) == 420)
        #expect(IncrustacionFichero.altoAmpliado(.pdf, base: 420) == 840)
        #expect(IncrustacionFichero.altoAmpliado(.audio, base: 52) == 52)
    }
}
