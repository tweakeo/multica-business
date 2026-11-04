import CoreGraphics
import CoreText
import Foundation
import GRDB
import Testing
@testable import TLSCore

/// R1 en F2: el texto de los PDF entra en la búsqueda. Solo lo que ya está en el Mac, nunca lo privado ni lo
/// archivado, solo en el índice desechable (la carpeta no cambia) y en segundo plano.
@Suite("Texto de los PDF en la búsqueda (R1, F2)", .serialized)
struct TextoPDFTests {
    /// PDF de una página con esas líneas de texto.
    static func pdf(_ url: URL, _ lineas: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &caja, nil) else { throw CocoaError(.fileWriteUnknown) }
        ctx.beginPDFPage(nil)
        var y: CGFloat = 760
        let fuente = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        for texto in lineas {
            let atributos = [kCTFontAttributeName as NSAttributedString.Key: fuente]
            let linea = CTLineCreateWithAttributedString(NSAttributedString(string: texto, attributes: atributos))
            ctx.textPosition = CGPoint(x: 72, y: y)
            CTLineDraw(linea, ctx)
            y -= 22
        }
        ctx.endPDFPage()
        ctx.closePDF()
    }

    /// Extractor que apunta qué rutas se le pidieron (por el tamaño del PDF, que es único en cada prueba).
    final class Espia: ExtractorTextoPDF, @unchecked Sendable {
        let base = ExtractorPDFKit()
        private let lock = NSLock()
        private var _leidos: [String] = []
        var leidos: [String] { lock.withLock { _leidos } }
        func texto(de data: Data) -> String? {
            let t = base.texto(de: data)
            lock.withLock { _leidos.append(t ?? "") }
            return t
        }
    }

    /// Copia de la fixture con un PDF normal, uno privado, uno archivado y uno escaneado (sin texto).
    static func carpetaConPDF() throws -> URL {
        let root = Apoyo.copiaDeFixture()
        try pdf(root.appendingPathComponent("4 · Finanzas/Facturas/proveedor-kumquat.pdf"),
                ["Factura del proveedor Kumquat Servicios", "Concepto: mantenimiento de jacarandas"])
        try pdf(root.appendingPathComponent("Privado/Expediente privado/nomina-zarzamora.pdf"),
                ["Documento con zarzamora confidencial"])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Archivo/4 · Finanzas"), withIntermediateDirectories: true)
        try pdf(root.appendingPathComponent("Archivo/4 · Finanzas/vieja-membrillo.pdf"), ["Factura vieja de membrillo"])
        try pdf(root.appendingPathComponent("4 · Finanzas/escaneado.pdf"), [])
        return root
    }

    @Test("Busca dentro de un PDF ya descargado; no dentro de uno privado ni archivado; la carpeta no cambia")
    func buscaTextoDePDF() async throws {
        let root = try Self.carpetaConPDF()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let antes = Apoyo.huellaDeArbol(root)

        let s = try Apoyo.servicio(root, state: state)
        _ = try await s.open { _ in }
        let indice = try #require(s.indiceAbierto)
        #expect(indice.textoPDF.esperar())

        // Por una palabra del cuerpo, sin tildes y con prefijo.
        let hits = s.search("jacaranda")
        #expect(hits.map(\.note.path.raw) == ["4 · Finanzas/Facturas/proveedor-kumquat.pdf"])
        #expect(hits.first?.snippet.contains("‹jacarandas›") == true)
        #expect(hits.first?.note.kind == .other)
        #expect(hits.first?.note.privado == false)
        #expect(s.search("kumquat").count == 1)
        // Lo privado y lo archivado, nunca.
        #expect(s.search("zarzamora").isEmpty)
        #expect(s.search("membrillo").isEmpty)
        let estado = try indice.estadoPDF()
        #expect(estado[VaultPath("Privado/Expediente privado/nomina-zarzamora.pdf")] == nil)
        #expect(estado[VaultPath("Archivo/4 · Finanzas/vieja-membrillo.pdf")] == nil)
        #expect(estado[VaultPath("4 · Finanzas/escaneado.pdf")]?.estado == EstadoTextoPDF.sinTexto.rawValue)
        #expect(estado[VaultPath("4 · Finanzas/Facturas/proveedor-kumquat.pdf")]?.conTexto == true)
        // Un PDF no es una nota: ni ⌘O ni la ficha lo cuentan como tal.
        #expect(s.summary(of: VaultPath("4 · Finanzas/Facturas/proveedor-kumquat.pdf")) == nil)
        s.close()
        await s.waitUntilIdle()
        // La carpeta no cambió: el texto solo vive en el índice desechable.
        #expect(Apoyo.huellaDeArbol(root) == antes)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(VaultIndex.fileName).path))
    }

    @Test("El extractor nunca recibe un PDF privado ni archivado")
    func nuncaLeePrivado() throws {
        let root = try Self.carpetaConPDF()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let layout = VaultLayout.load(root: root, extraPrivado: [VaultPath("Privado")]).layout
        let index = try VaultIndex(directory: state)
        let espia = Espia()
        index.textoPDF.extractor = espia
        let builder = IndexBuilder(root: root, layout: layout, index: index, excluded: [], indexArchivoContent: false)
        _ = try builder.fullScan(progress: nil)
        #expect(index.textoPDF.esperar())
        let leidos = espia.leidos
        #expect(leidos.count == 2, "el de Finanzas y el escaneado")
        #expect(!leidos.contains { $0.contains("zarzamora") || $0.contains("membrillo") })
        #expect(leidos.contains { $0.contains("jacarandas") })
        index.close()
    }

    @Test("Un PDF que cambia se vuelve a leer; uno borrado sale de la búsqueda; el que pasa a privado también")
    func incremental() throws {
        let root = try Self.carpetaConPDF()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        var layout = VaultLayout.load(root: root, extraPrivado: [VaultPath("Privado")]).layout
        let index = try VaultIndex(directory: state)
        let ruta = VaultPath("4 · Finanzas/Facturas/proveedor-kumquat.pdf")
        func buscar(_ q: String) -> [String] {
            index.search(match: VaultService.ftsQuery(q)!, limit: 10).map(\.0.path.raw)
        }
        var builder = IndexBuilder(root: root, layout: layout, index: index, excluded: [], indexArchivoContent: false)
        _ = try builder.fullScan(progress: nil)
        #expect(index.textoPDF.esperar())
        #expect(buscar("jacarandas") == [ruta.raw])

        // Cambia (otro tamaño): se relee y el texto viejo ya no se encuentra.
        try Self.pdf(ruta.url(in: root), ["Factura del proveedor Kumquat Servicios", "Concepto: poda de naranjos y limoneros"])
        _ = try builder.update([ruta])
        #expect(index.textoPDF.esperar())
        #expect(buscar("naranjos") == [ruta.raw])
        #expect(buscar("jacarandas").isEmpty)

        // Pasa a privado: fuera del índice al siguiente escaneo.
        layout.privado.append(VaultPath("4 · Finanzas/Facturas"))
        builder = IndexBuilder(root: root, layout: layout, index: index, excluded: [], indexArchivoContent: false)
        _ = try builder.fullScan(progress: nil)
        #expect(index.textoPDF.esperar())
        #expect(buscar("naranjos").isEmpty)
        #expect(try index.estadoPDF()[ruta] == nil)

        // Borrado: fuera.
        try FileManager.default.removeItem(at: root.appendingPathComponent("4 · Finanzas/escaneado.pdf"))
        _ = try builder.update([VaultPath("4 · Finanzas/escaneado.pdf")])
        #expect(try index.estadoPDF()[VaultPath("4 · Finanzas/escaneado.pdf")] == nil)
        index.close()
    }

    @Test("Lo que está solo en iCloud no se lee: queda «sin descargar» y conserva lo leído si ya lo estaba")
    func soloEnICloudNoSeLee() throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        let index = try VaultIndex(directory: state)
        let espia = Espia()
        index.textoPDF.extractor = espia
        let nuevo = VaultPath("4 · Finanzas/en-icloud.pdf")
        try index.db.write { db in
            try VaultIndex.registrarPDF(nuevo, area: .finanzas, size: 100, mtime: 1, dataless: true, existente: nil,
                                        forzar: false, in: db)
        }
        index.textoPDF.programar(.init(root: state) { _ in true })
        #expect(index.textoPDF.esperar())
        #expect(espia.leidos.isEmpty)
        #expect(try index.estadoPDF()[nuevo]?.estado == EstadoTextoPDF.sinDescargar.rawValue)

        // Uno ya leído que iCloud se lleva (mismo tamaño y fecha): conserva su texto.
        let leido = VaultPath("4 · Finanzas/leido.pdf")
        try index.db.write { db in
            try VaultIndex.registrarPDF(leido, area: .finanzas, size: 10, mtime: 2, dataless: false, existente: nil, forzar: false, in: db)
            try db.execute(sql: "UPDATE pdfs SET estado = 'hecho' WHERE path = ?", arguments: [leido.raw])
            let rowid = try Int64.fetchOne(db, sql: "SELECT rowid FROM pdfs WHERE path = ?", arguments: [leido.raw])!
            try db.execute(sql: "INSERT INTO pdfs_fts(rowid, title, body) VALUES (?, 'leido', 'texto de higuera')", arguments: [rowid])
            let previo = try VaultIndex.pdfRows(in: db)[leido]
            try VaultIndex.registrarPDF(leido, area: .finanzas, size: 10, mtime: 2, dataless: true, existente: previo, forzar: false, in: db)
        }
        #expect(index.search(match: VaultService.ftsQuery("higuera")!, limit: 5).map(\.0.path) == [leido])
        index.close()
    }

    @Test("Índice de la versión 3 con las tablas de los PDF; uno de la 2 se rehace solo")
    func esquema() async throws {
        #expect(VaultIndex.schemaVersion == 3)
        #expect(VaultIndex.requiredTables.isSuperset(of: ["pdfs", "pdfs_fts"]))
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        do {
            let i = try VaultIndex(directory: state)
            i.close()
        }
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try DatabasePool(path: state.appendingPathComponent(VaultIndex.fileName).path, configuration: config)
        try await pool.write { db in try db.execute(sql: "PRAGMA user_version = 2") }
        try pool.close()
        let otra = try VaultIndex(directory: state)
        #expect(try await otra.db.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 3)
        otra.close()
    }

    @Test("Cerrar mientras lee no deja la cola tocando el índice")
    func cerrarMientrasLee() throws {
        let root = Apoyo.copiaDeFixture()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        for i in 0..<12 {
            try Self.pdf(root.appendingPathComponent("4 · Finanzas/Lote/doc-\(i).pdf"), ["Documento número \(i) de prueba"])
        }
        let layout = VaultLayout.load(root: root).layout
        let index = try VaultIndex(directory: state)
        let builder = IndexBuilder(root: root, layout: layout, index: index, excluded: [], indexArchivoContent: false)
        _ = try builder.fullScan(progress: nil)
        index.close()
        // Tras cerrar, programar no hace nada (y no se cuelga).
        index.textoPDF.programar(.init(root: root) { _ in true })
        #expect(Bool(true))
    }

    @Test("El texto se limpia: espacios seguidos, saltos y caracteres de control")
    func limpiar() {
        #expect(ExtractorPDFKit.limpiar("  Hola\n\n mundo\t\u{0007}fin  ", maximo: 100) == "Hola mundo fin")
        #expect(ExtractorPDFKit.limpiar("abcdef", maximo: 3) == "abc")
    }
}
