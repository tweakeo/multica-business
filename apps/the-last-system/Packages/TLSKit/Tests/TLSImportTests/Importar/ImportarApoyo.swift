import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import Synchronization
import Testing
import TLSCore
@testable import TLSImport

/// Empresa ficticia desordenada para las pruebas del paso 2. Nada de datos reales: nombres inventados y una carpeta
/// privada con nombre neutro («Expediente privado»).
struct EmpresaDePrueba {
    let base: URL
    let raiz: URL
    let estado: URL
    let asup: URL
    let entry: VaultEntry
    static let hoy = LocalDate(year: 2026, month: 10, day: 19)!

    init(nombre: String = "Empresa Prueba") throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        base = tmp.appendingPathComponent("tls-importar-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        raiz = base.appendingPathComponent(nombre, isDirectory: true)
        estado = base.appendingPathComponent("estado", isDirectory: true)
        asup = base.appendingPathComponent("asup", isDirectory: true)
        for d in [raiz, estado, asup] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        entry = VaultEntry(nombre: nombre, ruta: raiz.path, bookmark: nil, clase: .copia, escritura: .permitida)
    }

    func url(_ rel: String) -> URL { VaultPath(rel).url(in: raiz) }

    @discardableResult
    func escribir(_ rel: String, _ texto: String) throws -> URL {
        try escribir(rel, datos: Data(texto.utf8))
    }

    @discardableResult
    func escribir(_ rel: String, datos: Data) throws -> URL {
        let u = url(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: u)
        return u
    }

    func texto(_ rel: String) -> String? { try? String(contentsOf: url(rel), encoding: .utf8) }
    func existe(_ rel: String) -> Bool { FileManager.default.fileExists(atPath: url(rel).path) }

    func limpiar() { try? FileManager.default.removeItem(at: base) }

    /// La copia de trabajo, con su estructura de áreas y un desorden típico.
    static func desordenada() throws -> EmpresaDePrueba {
        let e = try EmpresaDePrueba()
        try e.escribir(".tls/layout.json", "{\"preset\": \"humana\"}")
        try e.escribir(".tls/config.yaml", "version: 1\nid: 6f1d3c2a-0000-4000-8000-000000000001\nclase: copia\nprivado: []\n")
        try e.escribir("Empresa.md", "# Empresa de prueba\n")
        for a in AreaCode.allCases { try e.escribir("\(a.numero) · \(a.nombre)/Área.md", "# \(a.nombre)\n") }
        try e.escribir("2 · Ventas/Contactos/ana-lopez.md", "---\ntls_type: contact\ntls_schema: 1\nid: 11111111-1111-4111-8111-111111111111\nnombre: Ana López Ya\n---\n# Ana López (la que ya estaba)\n")
        try e.escribir("4 · Finanzas/Fechas de documentos.csv",
                       "ruta,fecha,fuente,nota\nFiscal/2026/T1/Gastos/recibo.pdf,2026-01-10,manual,escrita a mano\n")
        try e.escribir("4 · Finanzas/Fiscal/2026/T1/Gastos/recibo.pdf", datos: pdf("Recibo sin fecha visible"))
        // El desorden.
        try e.escribir("Clientes/Ana López.md", "---\ntipo: persona\nempresa: Panadería Sol\n---\n# Ana López\nTrabaja en [Panadería Sol](../Empresas%20sueltas/Panader%C3%ADa%20Sol.md).\n")
        try e.escribir("Empresas sueltas/Panadería Sol.md", "---\ntipo: empresa\n---\n# Panadería Sol\nContacto: [Ana](../Clientes/Ana%20L%C3%B3pez.md)\n")
        try e.escribir("Facturas/Factura 2025-03-15 Proveedor.pdf", datos: pdf("Factura de un proveedor"))
        try e.escribir("Facturas/Factura proveedor luz.pdf", datos: pdf("Factura\nFecha de factura: 12/03/2025\nTotal 40,00"))
        try e.escribir("Fotos/logo.png", datos: png("LOGO"))
        try e.escribir("Notas/Ideas sueltas.md", "Cosas que pensar.\n")
        try e.escribir("Notas/Ideas sueltas (1).md", "Cosas que pensar.\n")   // copia exacta
        try e.escribir("Viejo/Acta reunión 2019-05-02.md", "Acta de una reunión antigua.\n")
        try e.escribir("Expediente privado/secreto.md", "contenido privado de prueba\n")
        return e
    }

    /// Fuente de la carpeta de la empresa con su carpeta privada.
    var fuente: FuenteImportacion {
        .carpetaDeLaEmpresa(raiz, privado: [VaultPath("Expediente privado")])
    }

    func writer() async throws -> VaultWriter {
        try await VaultWriter.open(entry: entry, root: raiz,
                                   options: .init(stateDirectory: estado, appSupport: asup, app: "The Last System pruebas"))
    }

    func bus() async throws -> CommandBus { CommandBus(writer: try await writer()) }

    /// Foto completa (también ocultos y `Archivo/`): sirve para demostrar que no se escribió nada.
    func fotoCompleta() async throws -> Inventory {
        try await Inventory.make(of: raiz, exclusiones: [VaultPath("Expediente privado")], completo: true)
    }

    /// Foto como la del criterio 4 (sin `Archivo/`, sin lo privado).
    func foto() async throws -> Inventory {
        try await Inventory.make(of: raiz, exclusiones: [VaultPath("Expediente privado")])
    }
}

/// Carpeta de fuera (una exportación) en un temporal propio.
struct CarpetaDeFuera {
    let raiz: URL
    init(_ base: URL, nombre: String) throws {
        raiz = base.appendingPathComponent(nombre, isDirectory: true)
        try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
    }

    @discardableResult
    func escribir(_ rel: String, _ texto: String) throws -> URL { try escribir(rel, datos: Data(texto.utf8)) }

    @discardableResult
    func escribir(_ rel: String, datos: Data) throws -> URL {
        let u = VaultPath(rel).url(in: raiz)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datos.write(to: u)
        return u
    }
}

// MARK: - Documentos sintéticos

/// Un PDF de una página con texto (que PDFKit puede leer).
func pdf(_ texto: String) -> Data {
    let data = NSMutableData()
    var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let ctx = CGContext(consumer: consumer, mediaBox: &caja, nil)!
    ctx.beginPDFPage(nil)
    var y: CGFloat = 780
    for linea in texto.split(separator: "\n", omittingEmptySubsequences: false) {
        dibujar(String(linea), en: ctx, x: 60, y: y, tamano: 14)
        y -= 22
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

/// Un PDF mínimo sin texto escrito a mano, con `CreationDate` en sus datos internos (`D:AAAAMMDDHHmmSSZ`).
/// (Quartz y PDFKit siempre ponen la fecha de hoy al crear un PDF.)
func pdfConFechaDeCreacion(_ fecha: String) -> Data {
    let objetos = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>",
        "<< /CreationDate (\(fecha)) /Producer (prueba) >>",
    ]
    var out = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (i, o) in objetos.enumerated() {
        offsets.append(out.utf8.count)
        out += "\(i + 1) 0 obj\n\(o)\nendobj\n"
    }
    let xref = out.utf8.count
    out += "xref\n0 \(objetos.count + 1)\n0000000000 65535 f \n"
    for o in offsets { out += String(format: "%010d 00000 n \n", o) }
    out += "trailer\n<< /Size \(objetos.count + 1) /Root 1 0 R /Info 4 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    return Data(out.utf8)
}

/// Un PDF «escaneado»: la página es solo una imagen con el texto (sin capa de texto).
func pdfEscaneado(_ texto: String) -> Data {
    let img = imagen(texto, ancho: 1240, alto: 1754, tamano: 64)
    let data = NSMutableData()
    var caja = CGRect(x: 0, y: 0, width: 595, height: 842)
    let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &caja, nil)!
    ctx.beginPDFPage(nil)
    ctx.draw(img, in: caja)
    ctx.endPDFPage()
    ctx.closePDF()
    return data as Data
}

func dibujar(_ texto: String, en ctx: CGContext, x: CGFloat, y: CGFloat, tamano: CGFloat) {
    let font = CTFontCreateWithName("Helvetica" as CFString, tamano, nil)
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: texto, attributes: attrs))
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

/// Imagen blanca con texto negro grande (para el reconocimiento de texto).
func imagen(_ texto: String, ancho: Int = 1600, alto: Int = 500, tamano: CGFloat = 72) -> CGImage {
    let ctx = CGContext(data: nil, width: ancho, height: alto, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: ancho, height: alto))
    var y = CGFloat(alto) - tamano * 1.6
    for linea in texto.split(separator: "\n") {
        dibujar(String(linea), en: ctx, x: 60, y: y, tamano: tamano)
        y -= tamano * 1.4
    }
    return ctx.makeImage()!
}

func png(_ texto: String, ancho: Int = 1600, alto: Int = 500) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, imagen(texto, ancho: ancho, alto: alto), nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

/// ZIP mínimo (como un .docx) con un fichero, guardado sin comprimir o con «deflate».
func zip(_ nombre: String, _ contenido: Data, comprimir: Bool) -> Data {
    func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
    func u32(_ v: Int) -> [UInt8] { u16(v & 0xffff) + u16((v >> 16) & 0xffff) }
    let datos = comprimir ? (try! (contenido as NSData).compressed(using: .zlib)) as Data : contenido
    let n = Array(nombre.utf8)
    let crc = 0   // el lector no lo comprueba
    var out: [UInt8] = []
    out += u32(0x0403_4b50) + u16(20) + u16(0) + u16(comprimir ? 8 : 0) + u16(0) + u16(0) + u32(crc)
    out += u32(datos.count) + u32(contenido.count) + u16(n.count) + u16(0) + n + [UInt8](datos)
    let central = out.count
    out += u32(0x0201_4b50) + u16(20) + u16(20) + u16(0) + u16(comprimir ? 8 : 0) + u16(0) + u16(0) + u32(crc)
    out += u32(datos.count) + u32(contenido.count) + u16(n.count) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0) + u32(0) + n
    let tam = out.count - central
    out += u32(0x0605_4b50) + u16(0) + u16(0) + u16(1) + u16(1) + u32(tam) + u32(central) + u16(0)
    return Data(out)
}

/// Lo que ningún texto para la persona puede decir (PLAN §6.9).
func jerga(_ texto: String) -> [String] {
    let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash"]
    let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
    return prohibidas.filter { palabras.contains($0) }
}

// MARK: - Claude falso

/// Ejecutable falso que hace de `claude -p`: apunta sus argumentos y lo que recibe, y responde con un JSON fijo.
/// Nunca se lanza Claude de verdad en las pruebas.
struct ClaudeFalso: EjecutorClasificacion {
    let dir: URL
    let script: URL

    init(base: URL, respuesta: String, falla: Bool = false) throws {
        dir = base.appendingPathComponent("claude-falso-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        script = dir.appendingPathComponent("claude")
        try Data(respuesta.utf8).write(to: dir.appendingPathComponent("respuesta.json"))
        let cuerpo = falla ? "exit 3" : "cat \"$DIR/respuesta.json\""
        let sh = "#!/bin/sh\nDIR=\"\(dir.path)\"\nprintf '%s\\n' \"$@\" >> \"$DIR/args.txt\"\ncat >> \"$DIR/entrada.txt\"\n\(cuerpo)\n"
        try Data(sh.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    }

    var argumentos: String { (try? String(contentsOf: dir.appendingPathComponent("args.txt"), encoding: .utf8)) ?? "" }
    var entradas: String { (try? String(contentsOf: dir.appendingPathComponent("entrada.txt"), encoding: .utf8)) ?? "" }

    func ejecutar(peticion: String, esquema: String) async throws -> Data {
        let p = Process()
        p.executableURL = script
        p.arguments = ["-p", "--output-format", "json", "--json-schema", esquema, "--no-session-persistence"]
        let entrada = Pipe(), salida = Pipe()
        p.standardInput = entrada
        p.standardOutput = salida
        try p.run()
        entrada.fileHandleForWriting.write(Data(peticion.utf8))
        try entrada.fileHandleForWriting.close()
        let data = salida.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw FalloFalso() }
        return data
    }

    struct FalloFalso: LocalizedError {
        var errorDescription: String? { "el programa terminó con error" }
    }
}

/// Reconocedor falso (no usa Vision): devuelve siempre el mismo texto y cuenta las llamadas.
final class ReconocedorFalso: ReconocedorDeTexto, Sendable {
    let texto: String
    let llamadas = Mutex(0)
    init(_ texto: String) { self.texto = texto }
    func texto(deImagen url: URL) throws -> String { llamadas.withLock { $0 += 1 }; return texto }
    func texto(dePDF url: URL, pagina: Int) throws -> String { llamadas.withLock { $0 += 1 }; return texto }
}

/// Inventario + zona + vista previa de una empresa de prueba.
func prepararZona(_ e: EmpresaDePrueba, externas: [FuenteImportacion] = [],
                  fs: any FileSystemAccess = LocalFileSystem()) async throws -> ZonaPreparacion {
    let inv = try await InventarioImportacion.hacer([e.fuente] + externas, opciones: .init(hoy: EmpresaDePrueba.hoy),
                                                    fileSystem: fs)
    return ZonaPreparacion(inventario: inv, layout: VaultLayout.load(root: e.raiz).layout, hoy: EmpresaDePrueba.hoy)
}

func applier(_ e: EmpresaDePrueba, ocr: (any ReconocedorDeTexto)? = nil) -> ImportApplier {
    ImportApplier(carpeta: e.raiz, opciones: .init(hoy: EmpresaDePrueba.hoy, ocr: ocr))
}
