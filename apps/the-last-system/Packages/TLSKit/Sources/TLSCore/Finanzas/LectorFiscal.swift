// Procedencia: lógica portada de PROG core/fiscal.js (Manu) y de core/sql/11-fiscal.sql (`periodo_trimestre` y la
// tabla de tipos fiscales). Reescrita en Swift. Ver docs/PROCEDENCIA.md.
import Foundation

/// Leer los originales de `Fiscal/` por su nombre, como ya los nombra la persona
/// (`2026-06-30 F260007 Clara Ibáñez 480,00€.pdf`).
///
/// La regla de origen: **lo que el nombre no dice, no se dice.** Nada se estima, nada se redondea y ningún PDF
/// se abre. Lo que falta se apunta con su motivo (`falta`), que es más útil que una cifra inventada.
public enum LectorFiscal {
    /// Fecha leída de un nombre.
    public struct FechaNombre: Sendable, Hashable {
        public let fecha: LocalDate
        /// El nombre solo decía el mes (`2026-03 …`): se toma el día 1.
        public let mesEntero: Bool
        /// `iso`, `puntos` (`17.06.25`) o `mes` (`mayo25`).
        public let formato: String
    }

    /// Lo leído de un original.
    public struct Documento: Sendable, Hashable {
        public enum Clase: String, Sendable, Hashable { case ingreso, gasto }
        public let clase: Clase
        public let ruta: VaultPath
        public let nombre: String
        public let fecha: LocalDate?
        public let numero: String?
        /// Cliente (ingresos) o proveedor (gastos).
        public let tercero: String?
        /// El proveedor salió de la primera palabra del nombre, no de su carpeta.
        public let terceroSupuesto: Bool
        /// Céntimos; en los gastos, negativo.
        public let importe: Int?
        public let tipoFiscal: String?
        public let categoria: String?
        /// Por qué no se sabe todo («la fecha no está al principio del nombre»…).
        public let falta: [String]
    }

    // MARK: Piezas de un nombre

    static func re(_ patron: String, _ opciones: NSRegularExpression.Options = []) -> NSRegularExpression {
        // Los patrones son fijos: si uno no compila es un error de programación.
        try! NSRegularExpression(pattern: patron, options: opciones)
    }

    static func grupos(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
    }

    static let patronFecha = #"^(\d{4})-(\d{2})(?:-(\d{2}))?\s+"#
    static let patronEuros = #"(-?\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?)\s*€"#
    static let patronNumeroPropio = #"\b((?:F|CN|T)\d{6})\b"#
    static let patronNumeroAjeno = #"\b([A-Z]{4,}\d?[A-Z]*-\d{3,}(?:-[A-Z]{2}-\d+)?|f?\d{4}-?\d{2,})\b"#
    static let patronPuntos = #"\b(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2}|\d{4})\b"#
    static let meses: [String: Int] = [
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
        "septiembre": 9, "sept": 9, "sep": 9, "octubre": 10, "oct": 10, "noviembre": 11, "nov": 11,
        "diciembre": 12, "dic": 12, "ene": 1, "feb": 2, "mar": 3, "abr": 4, "jun": 6, "jul": 7, "ago": 8,
    ]

    /// `2026-06-30 …`, `2026-03 …` (mes entero), `Amazon 17.06.25` o `Gestoría mayo25` (año de la carpeta si falta).
    public static func fecha(_ nombre: String, anioCarpeta: Int?) -> FechaNombre? {
        if let g = grupos(re(patronFecha), nombre), let a = g[1].flatMap({ Int($0) }), let m = g[2].flatMap({ Int($0) }) {
            let d = g[3].flatMap { Int($0) }
            guard let f = LocalDate(year: a, month: m, day: d ?? 1) else { return nil }
            return FechaNombre(fecha: f, mesEntero: d == nil, formato: "iso")
        }
        if let g = grupos(re(patronPuntos), nombre), let d = g[1].flatMap({ Int($0) }), let m = g[2].flatMap({ Int($0) }),
           let y = g[3] {
            let a = y.count == 2 ? 2000 + (Int(y) ?? 0) : (Int(y) ?? 0)
            if (1...12).contains(m), (1...31).contains(d), let f = LocalDate(year: a, month: m, day: d) {
                return FechaNombre(fecha: f, mesEntero: false, formato: "puntos")
            }
        }
        let claves = meses.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        if let g = grupos(re(#"\b("# + claves + #")\.?\s*(\d{2}|\d{4})?\b"#, .caseInsensitive), nombre),
           let mes = g[1].flatMap({ meses[$0.lowercased()] }) {
            let a: Int? = g[2].map { $0.count == 2 ? 2000 + (Int($0) ?? 0) : (Int($0) ?? 0) } ?? anioCarpeta
            if let a, (2000...2100).contains(a), let f = LocalDate(year: a, month: mes, day: 1) {
                return FechaNombre(fecha: f, mesEntero: true, formato: "mes")
            }
        }
        return nil
    }

    /// Importe en euros del nombre (`615,60€`, `4.560€`, `-572,40€`), en céntimos.
    public static func importe(_ nombre: String) -> Int? {
        guard let g = grupos(re(patronEuros), nombre), let t = g[1] else { return nil }
        return DineroExacto.centimos(t, decimal: ",")
    }

    /// `2026-T3`.
    public static func trimestre(de fecha: LocalDate) -> String {
        "\(fecha.year)-T\((fecha.month - 1) / 3 + 1)"
    }

    // MARK: Tipo fiscal y categoría (solo cuando el nombre no deja lugar a duda)

    static let extranjeros = ["anthropic", "openai", "claude", "notion", "stripe", "figma", "github"]

    /// Tipo fiscal por reglas fijas; lo que no encaja se queda sin tipo (y sale en la lista de pendientes).
    public static func tipoFiscal(nombre: String, proveedor: String?, importe: Int?) -> String? {
        let t = (nombre + " " + (proveedor ?? "")).lowercased()
        func hay(_ patron: String, _ en: String, _ o: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
            grupos(re(patron, o), en) != nil
        }
        if hay(#"\bcn\d{6}\b|credit note|rectificativa|abono"#, nombre) { return "rectificativa" }
        if hay("anulada|borrador|sin emitir", nombre) { return "borrador" }
        if hay("combustible|gasolina|repsol|cepsa", t, []) { return "gasolina" }
        if extranjeros.contains(where: { t.contains($0) }) { return "extranjero" }
        if hay("aseskonta|gestor[íi]a|grupo rm|urba", t, []) { return "estandar" }
        if hay(#"\bf\d{6}\b"#, nombre), importe != nil { return "ingreso" }
        return nil
    }

    static let categorias: [(String, String)] = [
        ("anthropic|openai|claude|notion|github|figma|quipu|holded|billin", "Herramientas/Software"),
        ("aseskonta|gestor[íi]a|grupo rm|urba", "Gestoría"),
        ("reta|seguridad social|tgss", "Seguridad Social (RETA)"),
        ("combustible|gasolina|repsol|cepsa|renfe|taxi|uber", "Transporte/Vehículo"),
        ("hosting|dominio|cloudflare|vercel|aws", "Infraestructura"),
        ("hacienda|aeat|modelo 30|modelo 34|modelo 39", "Impuestos"),
    ]

    public static func categoria(nombre: String, proveedor: String?) -> String? {
        let t = (nombre + " " + (proveedor ?? "")).lowercased()
        return categorias.first { grupos(re($0.0), t) != nil }?.1
    }

    // MARK: Leer un original

    public static func leerIngreso(_ ruta: VaultPath, anioCarpeta: Int?) -> Documento {
        let nombre = ruta.stem
        var falta: [String] = []
        let f = fecha(nombre, anioCarpeta: anioCarpeta)
        if f == nil { falta.append("la fecha no está al principio del nombre") }
        let numero = grupos(re(patronNumeroPropio), nombre).flatMap { $0[1] }
            ?? (nombre.range(of: "borrador", options: .caseInsensitive) != nil ? "BORRADOR" : nil)
        if numero == nil { falta.append("no se ve el número de factura") }
        let imp = importe(nombre)
        let tf = tipoFiscal(nombre: nombre, proveedor: nil, importe: imp)
        if imp == nil && tf != "borrador" { falta.append("no se ve el importe") }
        // El cliente es lo que queda entre el número y el importe o el estado.
        var resto = re(patronFecha).stringByReplacingMatches(in: nombre, range: NSRange(location: 0, length: (nombre as NSString).length), withTemplate: "")
        if let numero, numero != "BORRADOR", let r = resto.range(of: numero) { resto.removeSubrange(r) }
        for patron in ["BORRADOR sin emitir", patronEuros, "anulada|rectificativa"] {
            let ex = re(patron, .caseInsensitive)
            if let m = ex.firstMatch(in: resto, range: NSRange(location: 0, length: (resto as NSString).length)),
               let r = Range(m.range, in: resto) { resto.removeSubrange(r) }
        }
        let cliente = resto.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if cliente.isEmpty { falta.append("no se ve el cliente") }
        return Documento(clase: .ingreso, ruta: ruta, nombre: nombre, fecha: f?.fecha, numero: numero,
                         tercero: cliente.isEmpty ? nil : cliente, terceroSupuesto: false, importe: imp, tipoFiscal: tf,
                         categoria: nil, falta: falta)
    }

    /// El proveedor sale de la subcarpeta si la hay (lo fiable); si no, de la primera palabra tras la fecha.
    public static func leerGasto(_ ruta: VaultPath, subcarpeta: String?, anioCarpeta: Int?) -> Documento {
        let nombre = ruta.stem
        var falta: [String] = []
        let f = fecha(nombre, anioCarpeta: anioCarpeta)
        if f == nil { falta.append("la fecha no está al principio del nombre") }
        let sinFecha = re(patronFecha).stringByReplacingMatches(in: nombre, range: NSRange(location: 0, length: (nombre as NSString).length), withTemplate: "")
        var proveedor = subcarpeta
        var supuesto = false
        if proveedor == nil {
            proveedor = grupos(re(#"^([A-ZÁÉÍÓÚÑa-záéíóúñ&.]+(?:\s+[A-ZÁÉÍÓÚÑ][\wáéíóúñ]*)?)"#), sinFecha).flatMap { $0[1] }
            supuesto = proveedor != nil
            if proveedor == nil { falta.append("no se ve el proveedor") }
        }
        let imp = importe(nombre)
        if imp == nil { falta.append("no se ve el importe") }
        let numero = grupos(re(patronNumeroAjeno), sinFecha).flatMap { $0[1] }
        let tf = tipoFiscal(nombre: nombre, proveedor: proveedor, importe: imp)
        if tf == nil { falta.append("no se puede saber el tipo fiscal del nombre") }
        return Documento(clase: .gasto, ruta: ruta, nombre: nombre, fecha: f?.fecha, numero: numero, tercero: proveedor,
                         terceroSupuesto: supuesto, importe: imp.map { -abs($0) }, tipoFiscal: tf,
                         categoria: categoria(nombre: nombre, proveedor: proveedor), falta: falta)
    }

    /// Solo los justificantes: PDF, imagen y hoja de cálculo. Las notas `.md` no se interpretan como datos.
    public static let justificantes: Set<String> = ["pdf", "jpg", "jpeg", "png", "xlsx", "numbers", "docx", "heic"]

    // MARK: Tipos fiscales (tabla de 11-fiscal.sql)

    /// Qué hace cada tipo fiscal en el 303: si computa, qué parte del IVA se deduce y si se autoliquida.
    public struct ReglaFiscal: Sendable, Hashable {
        public let computa303: Bool
        public let parteIVA: Double
        /// Inversión del sujeto pasivo: el 21 % de la base va a la vez a devengado y a deducible.
        public let autoliquida: Double?
    }

    public static let reglas: [String: ReglaFiscal] = [
        "estandar": ReglaFiscal(computa303: true, parteIVA: 1, autoliquida: nil),
        "ingreso": ReglaFiscal(computa303: true, parteIVA: 1, autoliquida: nil),
        "extranjero": ReglaFiscal(computa303: false, parteIVA: 0, autoliquida: nil),
        "intracomunitario": ReglaFiscal(computa303: true, parteIVA: 1, autoliquida: 0.21),
        "rectificativa": ReglaFiscal(computa303: true, parteIVA: 1, autoliquida: nil),
        "inmovilizado": ReglaFiscal(computa303: true, parteIVA: 1, autoliquida: nil),
        "gasolina": ReglaFiscal(computa303: true, parteIVA: 0.5, autoliquida: nil),
        "reta": ReglaFiscal(computa303: false, parteIVA: 0, autoliquida: nil),
        "salario": ReglaFiscal(computa303: false, parteIVA: 0, autoliquida: nil),
        "hacienda": ReglaFiscal(computa303: false, parteIVA: 0, autoliquida: nil),
        "borrador": ReglaFiscal(computa303: false, parteIVA: 0, autoliquida: nil),
    ]
}
