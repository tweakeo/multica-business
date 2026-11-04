import Foundation

/// Reloj de la carpeta: el de verdad o, en la demo, el día fijo de `.tls/config.yaml` (`hoy:`).
public struct Reloj: Sendable {
    public var hoy: LocalDate
    public var ahora: Date
    public var zona: TimeZone

    public init(hoy: LocalDate, ahora: Date = Date(), zona: TimeZone = .current) {
        self.hoy = hoy; self.ahora = ahora; self.zona = zona
    }

    /// Reloj del sistema.
    public static func sistema(zona: TimeZone = .current) -> Reloj {
        let now = Date()
        return Reloj(hoy: LocalDate(date: now, timeZone: zona), ahora: now, zona: zona)
    }

    /// El de la carpeta: si `.tls/config.yaml` fija `hoy`, ese día (con la hora de ahora).
    public static func deCarpeta(_ snapshot: VaultSnapshot, zona: TimeZone = .current) -> Reloj {
        var r = sistema(zona: zona)
        if let text = snapshot.text(VaultPath(".tls/config.yaml")),
           let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("hoy:") }),
           let kl = FrontmatterDocument.parseKeyLine(String(line)),
           let d = LocalDate(parsing: kl.value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))) {
            r.hoy = d
        }
        return r
    }

    /// `HH:MM`.
    public var hora: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.hour, .minute], from: ahora)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

/// Formatos de las variables (`{{total:€}}`, `{{vence:corta}}`…) y fechas de periodo.
public enum FormatosPlantilla {
    static let mesesCortos = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    static let meses = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre",
                        "octubre", "noviembre", "diciembre"]

    /// Aplica un formato. Si el valor no encaja con el formato, se devuelve tal cual.
    public static func aplicar(_ valor: String, formato: String) -> String {
        switch formato {
        case "€": return euros(valor) ?? valor
        case "%": return valor.isEmpty ? valor : "\(valor.replacingOccurrences(of: ".", with: ",")) %"
        case "corta":
            if let d = LocalDate(parsing: valor) { return "\(d.day) \(mesesCortos[d.month - 1])" }
            return valor
        case "larga":
            if let d = LocalDate(parsing: valor) { return "\(d.day) de \(meses[d.month - 1]) de \(d.year)" }
            if let (y, m) = mes(valor) { return "\(meses[m - 1]) de \(y)" }
            return valor
        case "letra": return enLetra(valor) ?? valor
        case "sino":
            switch valor.lowercased() {
            case "true", "sí", "si", "yes": return "sí"
            case "false", "no": return "no"
            default: return valor
            }
        case "cifras": return String(valor.filter(\.isNumber))
        case "hhmm": return valor.replacingOccurrences(of: ":", with: "")
        case "corto": return valor.split(separator: " ").first.map(String.init) ?? valor
        default: return valor
        }
    }

    static func mes(_ s: String) -> (Int, Int)? {
        let p = s.split(separator: "-")
        guard p.count == 2, p[0].count == 4, let y = Int(p[0]), let m = Int(p[1]), (1...12).contains(m) else { return nil }
        return (y, m)
    }

    /// Céntimos de un importe escrito con punto (`150.00`, `-663`, `181,50` también vale). `nil` si no es un número.
    public static func centimos(_ s: String) -> Int? {
        var t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "€", with: "").trimmingCharacters(in: .whitespaces)
        if t.contains(","), !t.contains(".") { t = t.replacingOccurrences(of: ",", with: ".") }
        guard !t.isEmpty, let d = Decimal(string: t, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var value = d * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    /// `1840.5` → `1.840,50 €`.
    public static func euros(_ s: String) -> String? {
        guard let c = centimos(s) else { return nil }
        let signo = c < 0 ? "-" : ""
        let a = abs(c)
        var entero = String(a / 100)
        if entero.count > 3 {
            var grupos: [String] = []
            while entero.count > 3 { grupos.insert(String(entero.suffix(3)), at: 0); entero = String(entero.dropLast(3)) }
            grupos.insert(entero, at: 0)
            entero = grupos.joined(separator: ".")
        }
        return "\(signo)\(entero),\(String(format: "%02d", a % 100)) €"
    }

    /// Importe en letra: `181.50` → «ciento ochenta y un euros con cincuenta céntimos».
    public static func enLetra(_ s: String) -> String? {
        guard let c = centimos(s), c >= 0, c < 100_000_000_000 else { return nil }
        let e = c / 100, ct = c % 100
        // «un millón de euros», pero «un millón cien euros».
        let de = e >= 1_000_000 && e % 1_000_000 == 0
        var out = numero(e, apocope: true) + (de ? " de" : "") + (e == 1 ? " euro" : " euros")
        if ct > 0 { out += " con " + numero(ct, apocope: true) + (ct == 1 ? " céntimo" : " céntimos") }
        return out
    }

    static let unidades = ["cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez",
                           "once", "doce", "trece", "catorce", "quince", "dieciséis", "diecisiete", "dieciocho", "diecinueve",
                           "veinte", "veintiuno", "veintidós", "veintitrés", "veinticuatro", "veinticinco", "veintiséis",
                           "veintisiete", "veintiocho", "veintinueve"]
    static let decenas = ["", "", "", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa"]
    static let centenas = ["", "ciento", "doscientos", "trescientos", "cuatrocientos", "quinientos", "seiscientos",
                           "setecientos", "ochocientos", "novecientos"]

    /// Número en letra. `apocope`: «un» y «veintiún» delante de un sustantivo («un euro»).
    static func numero(_ n: Int, apocope: Bool) -> String {
        func menorDeCien(_ n: Int) -> String {
            if n < 30 {
                if apocope, n == 1 { return "un" }
                if apocope, n == 21 { return "veintiún" }
                return unidades[n]
            }
            let d = decenas[n / 10]
            let u = n % 10
            if u == 0 { return d }
            return d + " y " + (apocope && u == 1 ? "un" : unidades[u])
        }
        func menorDeMil(_ n: Int) -> String {
            if n == 100 { return "cien" }
            let c = n / 100, r = n % 100
            if c == 0 { return menorDeCien(r) }
            return r == 0 ? centenas[c] : centenas[c] + " " + menorDeCien(r)
        }
        func numeroConApocope(_ k: Int) -> String {
            // «veintiún mil», «treinta y un millones»: delante de mil y millones va la forma corta.
            if k == 100 { return "cien" }
            let c = k / 100, r = k % 100
            var t: String
            if r < 30 { t = r == 1 ? "un" : (r == 21 ? "veintiún" : (r == 0 ? "" : unidades[r])) }
            else { let u = r % 10; t = decenas[r / 10] + (u == 0 ? "" : " y " + (u == 1 ? "un" : unidades[u])) }
            if c > 0 { t = centenas[c] + (t.isEmpty ? "" : " " + t) }
            return t
        }
        if n == 0 { return "cero" }
        var partes: [String] = []
        let millones = n / 1_000_000
        let miles = (n / 1000) % 1000
        let resto = n % 1000
        if millones > 0 {
            partes.append(millones == 1 ? "un millón" : numeroConApocope(millones) + " millones")
        }
        if miles > 0 {
            partes.append(miles == 1 ? "mil" : numeroConApocope(miles) + " mil")
        }
        if resto > 0 { partes.append(menorDeMil(resto)) }
        return partes.joined(separator: " ")
    }

    // MARK: Periodos

    /// `2026-S43` (semana ISO).
    public static func semana(_ d: LocalDate) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let c = cal.dateComponents([.weekOfYear, .yearForWeekOfYear], from: d.date())
        return String(format: "%04d-S%02d", c.yearForWeekOfYear ?? d.year, c.weekOfYear ?? 1)
    }

    /// `T4 2026`.
    public static func trimestre(_ d: LocalDate) -> String { "T\((d.month - 1) / 3 + 1) \(d.year)" }

    /// `2026-10`.
    public static func mes(_ d: LocalDate) -> String { String(format: "%04d-%02d", d.year, d.month) }

    /// `n` días laborables después (sábado y domingo no cuentan).
    public static func sumarLaborables(_ d: LocalDate, _ n: Int) -> LocalDate {
        var cur = d
        var left = abs(n)
        let step = n >= 0 ? 1 : -1
        while left > 0 {
            cur = cur.adding(days: step)
            if !cur.isWeekend { left -= 1 }
        }
        return cur
    }
}
