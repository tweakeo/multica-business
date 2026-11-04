import Foundation
import TLSCore

/// Valor del frontmatter de un registro G2, con mapas y listas anidados (`proposal`, `lines`, `template`…).
///
/// Se construye solo con `FrontmatterReader` (TLSCore): los mapas y las listas de mapas llegan como
/// YAML literal (`.raw`) y se vuelven a leer por partes. Las fechas y los números quedan como texto.
enum G2Valor: Sendable, Hashable {
    case texto(String)
    case numero(String)
    case bool(Bool)
    case nulo
    case lista([G2Valor])
    case mapa(G2Mapa)

    /// Texto sin espacios alrededor; `nil` si está vacío, es nulo o no es un escalar.
    var texto: String? {
        switch self {
        case .texto(let s), .numero(let s):
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t == "null" ? nil : t
        case .bool(let b): return b ? "true" : "false"
        case .nulo, .lista, .mapa: return nil
        }
    }

    var mapa: G2Mapa? {
        if case .mapa(let m) = self { return m }
        return nil
    }

    var lista: [G2Valor]? {
        if case .lista(let l) = self { return l }
        return nil
    }

    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .texto(let s): return s == "true" ? true : (s == "false" ? false : nil)
        default: return nil
        }
    }

    /// `true` si no aporta nada (nulo, texto vacío, lista o mapa vacíos).
    var vacio: Bool {
        switch self {
        case .nulo: return true
        case .texto, .numero, .bool: return texto == nil
        case .lista(let l): return l.allSatisfy(\.vacio)
        case .mapa(let m): return m.pares.allSatisfy { $0.valor.vacio }
        }
    }
}

/// Mapa YAML con las claves en el orden en que están escritas.
struct G2Mapa: Sendable, Hashable {
    struct Par: Sendable, Hashable {
        let clave: String
        let valor: G2Valor
    }

    var pares: [Par]

    static let vacio = G2Mapa(pares: [])

    subscript(_ clave: String) -> G2Valor? {
        pares.first { $0.clave == clave }?.valor
    }

    var claves: [String] { pares.map(\.clave) }

    func texto(_ clave: String) -> String? { self[clave]?.texto }
    func mapa(_ clave: String) -> G2Mapa? { self[clave]?.mapa }
    func lista(_ clave: String) -> [G2Valor] { self[clave]?.lista ?? [] }
    func bool(_ clave: String) -> Bool? { self[clave]?.bool }

    /// Entero exacto (acepta `15000`, `1.84e+06`); `nil` si no hay valor o tiene decimales.
    func entero(_ clave: String) -> Int? {
        guard let t = texto(clave) else { return nil }
        return G2Numero.entero(t)
    }

    /// Fecha `AAAA-MM-DD` (de una fecha o de un instante con zona; se pasa a hora de Madrid).
    func fecha(_ clave: String) -> String? {
        guard let t = texto(clave) else { return nil }
        return G2Fecha.dia(t)
    }

    /// Lista de textos (ignora vacíos).
    func textos(_ clave: String) -> [String] {
        lista(clave).compactMap(\.texto)
    }
}

enum G2Numero {
    /// Entero exacto a partir de un texto YAML (también en notación científica).
    static func entero(_ texto: String) -> Int? {
        let t = texto.trimmingCharacters(in: .whitespaces)
        if let i = Int(t) { return i }
        guard let d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var valor = d
        var redondeado = Decimal()
        NSDecimalRound(&redondeado, &valor, 0, .plain)
        guard redondeado == d else { return nil }
        return NSDecimalNumber(decimal: redondeado).intValue
    }

    /// Decimal exacto de un texto YAML.
    static func decimal(_ texto: String) -> Decimal? {
        Decimal(string: texto.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// Fechas de G2: `2026-10-19`, `2026-10-19T23:52:07.147465+02:00` o `…Z`. Siempre en hora de Madrid.
enum G2Fecha {
    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    static func dia(_ texto: String) -> String? {
        let t = texto.trimmingCharacters(in: .whitespaces)
        if t.count == 10, esDia(t) { return t }
        guard let instante = instante(t) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        let c = cal.dateComponents([.year, .month, .day], from: instante)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func esDia(_ t: String) -> Bool {
        t.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    /// Instante ISO 8601 con zona (con o sin fracciones de segundo).
    static func instante(_ t: String) -> Date? {
        let conFraccion = ISO8601DateFormatter()
        conFraccion.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = conFraccion.date(from: t) { return d }
        let sin = ISO8601DateFormatter()
        sin.formatOptions = [.withInternetDateTime]
        return sin.date(from: t)
    }

    /// Hora `HH:MM` en Madrid de un instante.
    static func hora(_ texto: String) -> String? {
        guard let instante = instante(texto.trimmingCharacters(in: .whitespaces)) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        let c = cal.dateComponents([.hour, .minute], from: instante)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Componentes de un día `AAAA-MM-DD`.
    static func partes(_ dia: String) -> (anio: Int, mes: Int, dia: Int)? {
        let p = dia.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return (p[0], p[1], p[2])
    }

    /// Trimestre (1–4) de un día.
    static func trimestre(_ dia: String) -> Int? {
        guard let p = partes(dia) else { return nil }
        return (p.mes - 1) / 3 + 1
    }

    static let mesesCortos = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"]

    /// «30 oct».
    static func corta(_ dia: String) -> String {
        guard let p = partes(dia), (1...12).contains(p.mes) else { return dia }
        return "\(p.dia) \(mesesCortos[p.mes - 1])"
    }

    /// Lunes de una semana ISO (`2026-W42` → `2026-10-12`).
    static func lunes(semanaISO texto: String) -> String? {
        let t = texto.uppercased()
        guard let r = t.range(of: #"^(\d{4})-W(\d{2})$"#, options: .regularExpression), r.lowerBound == t.startIndex else { return nil }
        let anio = Int(t.prefix(4))!, semana = Int(t.suffix(2))!
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = madrid
        var c = DateComponents()
        c.yearForWeekOfYear = anio; c.weekOfYear = semana; c.weekday = 2
        guard let d = cal.date(from: c) else { return nil }
        let p = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }

    /// `2026-T4` o `2026-t4` → (2026, 4).
    static func periodoTrimestral(_ texto: String) -> (anio: Int, trimestre: Int)? {
        let t = texto.uppercased()
        guard t.range(of: #"^\d{4}-T[1-4]$"#, options: .regularExpression) != nil else { return nil }
        return (Int(t.prefix(4))!, Int(String(t.last!))!)
    }

    /// Primer y último día de un trimestre.
    static func limites(anio: Int, trimestre: Int) -> (desde: String, hasta: String) {
        let mesInicio = (trimestre - 1) * 3 + 1
        let mesFin = mesInicio + 2
        let ultimo = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var dias = ultimo[mesFin - 1]
        if mesFin == 2, anio % 4 == 0, anio % 100 != 0 || anio % 400 == 0 { dias = 29 }
        return (String(format: "%04d-%02d-01", anio, mesInicio), String(format: "%04d-%02d-%02d", anio, mesFin, dias))
    }
}

enum G2YAML {
    /// Lee un frontmatter G2 completo. `nil` si el YAML no se entiende.
    static func leer(_ yaml: String) -> G2Mapa? {
        let fm = FrontmatterReader.read(yaml)
        guard fm.isValid else { return nil }
        return G2Mapa(pares: fm.properties.map { G2Mapa.Par(clave: $0.key, valor: valor($0.value)) })
    }

    static func valor(_ v: PropertyValue) -> G2Valor {
        switch v {
        case .text(let s): return .texto(s)
        case .number(let s): return .numero(s)
        case .bool(let b): return .bool(b)
        case .empty: return .nulo
        case .list(let items): return .lista(items.map { .texto($0) })
        case .raw(let literal): return anidado(literal)
        }
    }

    /// Un mapa o una lista escritos como YAML literal por `FrontmatterReader`.
    static func anidado(_ literal: String) -> G2Valor {
        let t = literal.trimmingCharacters(in: .newlines)
        if t.hasPrefix("- ") || t == "-" || t.hasPrefix("-\n") {
            guard let m = leer(secuenciaComoMapa(t)) else { return .texto(literal) }
            return .lista(m.pares.map(\.valor))
        }
        guard let m = leer(t) else { return .texto(literal) }
        return .mapa(m)
    }

    /// Convierte una lista en bloque (`- a: 1` …) en un mapa `"0": …` que `FrontmatterReader` sabe leer.
    /// Las líneas de cada elemento ya vienen sangradas dos espacios por el serializador de YAML.
    static func secuenciaComoMapa(_ literal: String) -> String {
        var out: [String] = []
        var i = 0
        for line in literal.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == "-" {
                out.append("\"\(i)\":")
                i += 1
            } else if line.hasPrefix("- ") {
                let contenido = line.dropFirst(2)
                if esInicioDeMapa(contenido) {
                    out.append("\"\(i)\":")
                    out.append("  " + contenido)
                } else {
                    out.append("\"\(i)\": " + contenido)
                }
                i += 1
            } else {
                out.append(String(line))
            }
        }
        return out.joined(separator: "\n")
    }

    /// `clave: valor` o `clave:` (y no un escalar entre comillas ni una lista en línea).
    static func esInicioDeMapa(_ s: Substring) -> Bool {
        guard let first = s.first, first != "'", first != "\"", first != "[", first != "{", first != "|", first != ">" else {
            return false
        }
        return s.contains(": ") || s.hasSuffix(":")
    }
}
