// Procedencia: lógica portada a Swift desde FORK/scripts/tls/the-last-fechas.mjs (autor: Manuel Trigo).
// Reescrito (PDFKit en vez de pdftotext/pdfinfo, Vision vía OCRService, lector ZIP propio en vez de unzip);
// sin código copiado. Ver docs/PROCEDENCIA.md.

import Foundation
import PDFKit
import TLSCore

/// Fecha de un documento y de dónde sale.
public struct FechaDocumento: Sendable, Hashable, Codable {
    public enum Fuente: String, Sendable, Hashable, Codable {
        /// Leída del propio documento (texto del PDF, escaneo o imagen).
        case documento
        /// Del nombre del fichero o de su carpeta.
        case nombre
        /// De los datos internos del fichero (fecha de creación del PDF o del documento de Office).
        case metadatos
        /// Escrita por una persona: nunca se pisa.
        case manual
        /// Puesta al convertir o importar desde otro programa.
        case importacion
    }

    /// `AAAA-MM-DD` o `AAAA-MM` (si solo se sabe el mes).
    public let fecha: String
    public let fuente: Fuente
    public let nota: String

    public init(fecha: String, fuente: Fuente, nota: String = "") {
        self.fecha = fecha; self.fuente = fuente; self.nota = nota
    }

    /// El día, si la fecha lo tiene.
    public var dia: LocalDate? { fecha.count == 10 ? LocalDate(parsing: fecha) : nil }
    public var ano: Int? { Int(fecha.prefix(4)) }
    public var mes: Int? { fecha.count >= 7 ? Int(fecha.dropFirst(5).prefix(2)) : nil }
}

/// Fecha real de los documentos cuyo nombre no la lleva (port de `the-last-fechas.mjs`).
///
/// Orden: una fecha con etiqueta en el texto del PDF («Fecha», «Emitida», «Date of issue»…), una fecha en el nombre
/// en cualquier forma habitual en España (17.06.25, «20 de mayo de 2025», «gestoría abril25»…), cualquier fecha del
/// texto, el escaneo de los PDF sin texto y de las imágenes (Vision) y, por último, la fecha de creación del PDF o
/// del documento de Office. Nunca cambia ni renombra el original.
///
/// Solo lee lo que ya está en el Mac: quien llama comprueba antes que no esté solo en iCloud (y lo hace en el hilo
/// protegido de `DatalessGuard`, así que un acceso por error da error y no descarga nada).
public struct DocumentDater: Sendable {
    public struct Opciones: Sendable {
        /// Día de hoy (el reloj de la carpeta: en el ejemplo, el fijo). Ninguna fecha puede ser posterior.
        public var hoy: LocalDate
        /// Año más antiguo que se acepta (por defecto, hace diez años): filtra números de versión y referencias.
        public var anoMinimo: Int
        /// Leer escaneos e imágenes (Vision). Si es `nil`, no se hace reconocimiento de texto.
        public var ocr: (any ReconocedorDeTexto)?

        public init(hoy: LocalDate, anoMinimo: Int? = nil, ocr: (any ReconocedorDeTexto)? = OCRService()) {
            self.hoy = hoy; self.anoMinimo = anoMinimo ?? (hoy.year - 10); self.ocr = ocr
        }
    }

    public let opciones: Opciones

    public init(opciones: Opciones) { self.opciones = opciones }

    // MARK: Fechas en un texto

    static let meses: [String: Int] = [
        "enero": 1, "ene": 1, "january": 1, "jan": 1,
        "febrero": 2, "feb": 2, "february": 2,
        "marzo": 3, "mar": 3, "march": 3,
        "abril": 4, "abr": 4, "april": 4, "apr": 4,
        "mayo": 5, "may": 5,
        "junio": 6, "jun": 6, "june": 6,
        "julio": 7, "jul": 7, "july": 7,
        "agosto": 8, "ago": 8, "august": 8, "aug": 8,
        "septiembre": 9, "setiembre": 9, "sept": 9, "sep": 9, "september": 9,
        "octubre": 10, "oct": 10, "october": 10,
        "noviembre": 11, "nov": 11, "november": 11,
        "diciembre": 12, "dic": 12, "december": 12, "dec": 12,
    ]
    /// Alternativa de meses, de la más larga a la más corta (para que «marzo» gane a «mar»).
    static let mon = meses.keys.sorted { ($0.count, $1) > ($1.count, $0) }.joined(separator: "|")

    private static func re(_ p: String, _ ci: Bool = false) -> NSRegularExpression {
        try! NSRegularExpression(pattern: p, options: ci ? [.caseInsensitive] : [])
    }

    /// Las cuatro formas de fecha, como en el original: ISO, día/mes/año, «20 de mayo de 2025» y «May 20, 2025».
    static let patrones: [(NSRegularExpression, kind: Int)] = [
        (re(#"(?<!\d)(20\d\d)[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)"#), 0),
        (re(#"(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](20\d\d|\d\d)(?!\d)"#), 1),
        (re(#"(?<!\d)(\d{1,2})(?:º)?[\s_]*(?:de[\s_]+)?("# + mon + #")\.?,?[\s_]*(?:de[\s_]+|del[\s_]+)?(20\d\d|\d\d)(?!\d)"#, true), 2),
        (re(#"\b("# + mon + #")\.?\s+(\d{1,2}),?\s+(20\d\d)(?!\d)"#, true), 3),
    ]

    static func ano4(_ y: String) -> Int { y.count == 2 ? 2000 + (Int(y) ?? 0) : (Int(y) ?? 0) }

    /// `AAAA-MM-DD` si es una fecha real, no anterior a `anoMinimo` ni posterior a hoy.
    func valida(_ y: Int, _ m: Int, _ d: Int) -> String? {
        guard y >= opciones.anoMinimo, let f = LocalDate(year: y, month: m, day: d), f <= opciones.hoy else { return nil }
        return f.description
    }

    /// Todas las fechas de `s`, en orden de lectura (posición en UTF-16, como en el original).
    func fechas(en s: String) -> [(fecha: String, indice: Int)] {
        let ns = s as NSString
        var out: [(String, Int)] = []
        for (re, kind) in Self.patrones {
            for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                func g(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
                let f: String?
                switch kind {
                case 0: f = valida(Int(g(1)) ?? 0, Int(g(2)) ?? 0, Int(g(3)) ?? 0)
                case 1: f = valida(Self.ano4(g(3)), Int(g(2)) ?? 0, Int(g(1)) ?? 0)
                case 2: f = valida(Self.ano4(g(3)), Self.meses[g(2).lowercased()] ?? 0, Int(g(1)) ?? 0)
                default: f = valida(Int(g(3)) ?? 0, Self.meses[g(1).lowercased()] ?? 0, Int(g(2)) ?? 0)
                }
                if let f { out.append((f, m.range.location)) }
            }
        }
        return out.sorted { $0.1 < $1.1 }
    }

    /// Etiquetas de la fecha del propio documento, de más fuerte a más débil. Una fecha tras «vencimiento» o
    /// «válido hasta» no es la del documento.
    static let etiquetas: [NSRegularExpression] = [
        re(#"(fecha(?:\s+de)?(?:\s+la)?\s+(?:factura|emisi[oó]n|expedici[oó]n|documento|ingreso|presentaci[oó]n|resoluci[oó]n|solicitud)|fecha\s*:|fecha\s*\n|fecha[ \t]+(?=\d)|emitid[ao](?:\s+con\s+fecha)?|date of issue|invoice date|date issued|issue date|date paid|f\.\s*operaci[oó]n)"#, true),
        re(#"(fecha\s+de\s+(?:iniciaci[oó]n|efectos?|operaci[oó]n|alta)|efectos\s*:)"#, true),
    ]
    static let noEsDelDocumento = re(#"nacimiento|nacido|vencimiento|caducidad|due|validez|hasta la fecha|comprobad"#, true)

    /// La primera fecha que sigue a una etiqueta como «Fecha:» o «Date of issue».
    func fechaConEtiqueta(_ texto: String) -> String? {
        let ns = texto as NSString
        for re in Self.etiquetas {
            for m in re.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
                let ini = max(0, m.range.location - 25)
                let fin = min(ns.length, m.range.location + m.range.length + 10)
                let alrededor = ns.substring(with: NSRange(location: ini, length: fin - ini))
                if Self.noEsDelDocumento.firstMatch(in: alrededor, range: NSRange(location: 0, length: (alrededor as NSString).length)) != nil {
                    continue
                }
                let desde = m.range.location + m.range.length
                let ventana = ns.substring(with: NSRange(location: desde, length: min(120, ns.length - desde)))
                if let f = fechas(en: ventana).first { return f.fecha }
            }
        }
        return nil
    }

    /// 02/11/2025 leído como 2 de noviembre cuando el nombre dice 11 de febrero: orden de EE. UU.
    static func intercambiadas(_ a: String, _ b: String) -> Bool {
        guard a.count == 10, b.count == 10, a.prefix(4) == b.prefix(4) else { return false }
        let am = a.dropFirst(5).prefix(2), ad = a.suffix(2), bm = b.dropFirst(5).prefix(2), bd = b.suffix(2)
        return am == bd && ad == bm
    }

    static let formatoCamara = re(#"(20\d\d)Y-(\d\d)M-(\d\d)D"#)
    static let soloMes = re(#"(?:^|[\s\-])("# + mon + #")\.?\s?(20\d\d|\d\d)?\b"#, true)
    static let anoEnRuta = re(#"(?:^|/)(20\d\d)(?:/| )"#)

    /// Fecha en el nombre de un fichero; un mes sin año toma el año de la ruta (`2025/…`).
    public func fechaEnNombre(_ nombre: String, ruta: String) -> FechaDocumento? {
        var base = nombre
        if let dot = base.lastIndex(of: "."), dot != base.startIndex { base = String(base[..<dot]) }
        base = base.replacingOccurrences(of: "_", with: " ")
        base = Self.formatoCamara.stringByReplacingMatches(in: base, range: NSRange(location: 0, length: (base as NSString).length),
                                                          withTemplate: "$1-$2-$3")
        if let d = fechas(en: base).first { return FechaDocumento(fecha: d.fecha, fuente: .nombre) }
        let ns = base as NSString
        if let m = Self.soloMes.firstMatch(in: base, range: NSRange(location: 0, length: ns.length)) {
            let mes = Self.meses[ns.substring(with: m.range(at: 1)).lowercased()] ?? 0
            var y = 0
            if m.range(at: 2).location != NSNotFound {
                y = Self.ano4(ns.substring(with: m.range(at: 2)))
            } else {
                let r = ruta as NSString
                if let a = Self.anoEnRuta.firstMatch(in: ruta, range: NSRange(location: 0, length: r.length)) {
                    y = Int(r.substring(with: a.range(at: 1))) ?? 0
                }
            }
            if y >= opciones.anoMinimo, y <= opciones.hoy.year, (1...12).contains(mes),
               y < opciones.hoy.year || mes <= opciones.hoy.month {
                return FechaDocumento(fecha: String(format: "%04d-%02d", y, mes), fuente: .nombre, nota: "solo el mes")
            }
        }
        return nil
    }

    // MARK: El nombre ya basta

    /// La app ya saca la fecha del nombre con estos dos patrones: solo los documentos que no los cumplen necesitan
    /// una fila en `Fechas de documentos.csv`.
    static let diaDeLaApp = re(#"(20\d\d)[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\d|3[01])"#)
    static let mesDeLaApp = re(#"(20\d\d)[-_.](0[1-9]|1[0-2])\b"#)

    public static func nombreLlevaFecha(_ nombre: String) -> Bool {
        let r = NSRange(location: 0, length: (nombre as NSString).length)
        return diaDeLaApp.firstMatch(in: nombre, range: r) != nil || mesDeLaApp.firstMatch(in: nombre, range: r) != nil
    }

    /// Carpetas de Finanzas cuyos documentos llevan fecha (como en el original).
    public static let gruposDeFinanzas = ["Fiscal", "Gestoría", "Trámites", "Registros"]

    /// `true` si el documento de esa ruta de la carpeta necesita una fila (está en un grupo de Finanzas, no es una
    /// nota y su nombre no lleva ya la fecha).
    public static func necesitaFila(_ ruta: VaultPath, layout: VaultLayout) -> Bool {
        let fin = layout.areaFolder(.finanzas)
        guard ruta.isDescendant(of: fin), ruta.components.count > fin.components.count + 1 else { return false }
        let grupo = TextFolding.nameKey(ruta.components[fin.components.count])
        guard gruposDeFinanzas.contains(where: { TextFolding.nameKey($0) == grupo }) else { return false }
        if ruta.name.hasPrefix(".") || ruta.name.hasPrefix("~$") { return false }
        if ["md", "csv"].contains(ruta.ext) { return false }
        return !nombreLlevaFecha(ruta.name)
    }

    // MARK: Leer el documento

    /// Fecha de un documento ya en el Mac, o `nil` si no hay nada legible. `ruta` es la que se enseña (para la
    /// fecha de la carpeta y el año de un mes suelto).
    public func fecha(de url: URL, ruta: VaultPath) -> FechaDocumento? {
        let nombre = ruta.name
        let ext = ruta.ext
        let porNombre = fechaEnNombre(nombre, ruta: ruta.raw)
        if ext == "pdf" {
            let texto = Self.textoPDF(url, paginas: 3) ?? ""
            let conEtiqueta = fechaConEtiqueta(texto)
            if let l = conEtiqueta, let n = porNombre, Self.intercambiadas(l, n.fecha) {
                return FechaDocumento(fecha: n.fecha, fuente: .documento,
                                      nota: "fecha en formato de EE. UU. (mes/día), confirmada por el nombre")
            }
            if let l = conEtiqueta {
                let nota = porNombre.map { $0.fecha.prefix(7) != l.prefix(7) ? "el nombre dice \($0.fecha)" : "" } ?? ""
                return FechaDocumento(fecha: l, fuente: .documento, nota: nota)
            }
            if let n = porNombre { return n }
            if let f = fechas(en: texto).first {
                return FechaDocumento(fecha: f.fecha, fuente: .documento, nota: "primera fecha del texto")
            }
            if texto.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, let ocr = opciones.ocr,
               let t = try? ocr.texto(dePDF: url, pagina: 0), let d = fechaConEtiqueta(t) ?? fechas(en: t).first?.fecha {
                return FechaDocumento(fecha: d, fuente: .documento, nota: "leída del escaneo (OCR)")
            }
            if let meta = fechaDeCreacionPDF(url) {
                return FechaDocumento(fecha: meta, fuente: .metadatos, nota: "fecha de creación del PDF; el texto no trae fecha")
            }
            return nil
        }
        if let n = porNombre { return n }
        let enCarpeta = fechas(en: (ruta.parent ?? .root).raw).first
        if ["png", "jpg", "jpeg", "heic"].contains(ext), let ocr = opciones.ocr,
           let t = try? ocr.texto(deImagen: url), let d = fechaConEtiqueta(t) ?? fechas(en: t).first?.fecha {
            return FechaDocumento(fecha: d, fuente: .documento, nota: "leída de la imagen (OCR)")
        }
        if ["xlsx", "docx", "pptx"].contains(ext), let meta = fechaDeCreacionOffice(url) {
            return FechaDocumento(fecha: meta, fuente: .metadatos, nota: "fecha de creación del documento")
        }
        if let c = enCarpeta, ext != "md" {
            return FechaDocumento(fecha: c.fecha, fuente: .nombre, nota: "fecha del nombre de la carpeta")
        }
        return nil
    }

    /// Texto de las primeras páginas de un PDF (PDFKit). `nil` si está dañado o cifrado.
    static func textoPDF(_ url: URL, paginas: Int) -> String? {
        guard let doc = PDFDocument(url: url), !doc.isLocked else { return nil }
        var partes: [String] = []
        for i in 0..<min(doc.pageCount, paginas) {
            if let s = doc.page(at: i)?.string { partes.append(s) }
        }
        return partes.joined(separator: "\n")
    }

    /// Fecha de creación que guarda el PDF, si cae en el intervalo aceptado.
    func fechaDeCreacionPDF(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url),
              let d = doc.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date else { return nil }
        return enIntervalo(LocalDate(date: d))
    }

    /// `dcterms:created` de `docProps/core.xml` (xlsx, docx, pptx).
    func fechaDeCreacionOffice(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.uncached]),
              let xml = LectorZip.fichero("docProps/core.xml", en: data).flatMap({ String(data: $0, encoding: .utf8) }) else {
            return nil
        }
        let re = Self.re(#"<dcterms:created[^>]*>(\d{4})-(\d\d)-(\d\d)"#)
        let ns = xml as NSString
        guard let m = re.firstMatch(in: xml, range: NSRange(location: 0, length: ns.length)),
              let f = LocalDate(year: Int(ns.substring(with: m.range(at: 1))) ?? 0, month: Int(ns.substring(with: m.range(at: 2))) ?? 0,
                                day: Int(ns.substring(with: m.range(at: 3))) ?? 0) else { return nil }
        return enIntervalo(f)
    }

    func enIntervalo(_ f: LocalDate) -> String? {
        f.year >= opciones.anoMinimo && f <= opciones.hoy ? f.description : nil
    }
}

/// Lector mínimo de ZIP para sacar un fichero pequeño (`docProps/core.xml`) sin programas externos.
/// Entiende «stored» y «deflate» (lo que usan Word, Excel y PowerPoint).
enum LectorZip {
    static func fichero(_ nombre: String, en zip: Data) -> Data? {
        let b = [UInt8](zip)
        func u16(_ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
        func u32(_ i: Int) -> Int { i + 3 < b.count ? u16(i) | u16(i + 2) << 16 : 0 }
        // Fin del directorio central: firma 0x06054b50 en los últimos 64 KB.
        guard b.count >= 22 else { return nil }
        var eocd = -1
        var i = b.count - 22
        let limite = max(0, b.count - 22 - 65_535)
        while i >= limite {
            if b[i] == 0x50, b[i + 1] == 0x4b, b[i + 2] == 0x05, b[i + 3] == 0x06 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let entradas = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<entradas {
            guard p + 46 <= b.count, u32(p) == 0x0201_4b50 else { return nil }
            let metodo = u16(p + 10)
            let comprimido = u32(p + 20)
            let tamano = u32(p + 24)
            let largoNombre = u16(p + 28), largoExtra = u16(p + 30), largoComentario = u16(p + 32)
            let local = u32(p + 42)
            guard p + 46 + largoNombre <= b.count else { return nil }
            let n = String(decoding: b[(p + 46)..<(p + 46 + largoNombre)], as: UTF8.self)
            if n == nombre {
                guard local + 30 <= b.count, u32(local) == 0x0403_4b50 else { return nil }
                let ini = local + 30 + u16(local + 26) + u16(local + 28)
                guard ini + comprimido <= b.count, tamano <= 8 << 20 else { return nil }
                let datos = Data(b[ini..<(ini + comprimido)])
                switch metodo {
                case 0: return datos
                case 8: return (try? (datos as NSData).decompressed(using: .zlib)).map { $0 as Data }
                default: return nil
                }
            }
            p += 46 + largoNombre + largoExtra + largoComentario
        }
        return nil
    }
}
