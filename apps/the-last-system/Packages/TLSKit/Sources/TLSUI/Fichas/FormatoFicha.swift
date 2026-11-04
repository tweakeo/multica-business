import Foundation
import TLSCore
import TLSDesign

/// Cómo se enseñan en una ficha los valores escritos en la carpeta: importes, fechas y estados.
enum FormatoFicha {
    static let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    static let dias = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]

    /// `181.50` → «181,50 €»; `1500` → «1.500 €». `nil` si no es un número.
    static func euros(_ texto: String?) -> String? {
        guard let t = texto?.trimmingCharacters(in: .whitespaces), !t.isEmpty,
              let v = Decimal(string: t.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
              !v.isNaN else { return nil }
        return euros(v)
    }

    static func euros(_ v: Decimal) -> String {
        guard !v.isNaN else { return "—" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.minimumGroupingDigits = 1
        var copia = v
        var redondo = Decimal()
        NSDecimalRound(&redondo, &copia, 0, .plain)
        let entero = redondo == v
        f.minimumFractionDigits = entero ? 0 : 2
        f.maximumFractionDigits = 2
        return (f.string(from: v as NSDecimalNumber) ?? "\(v)") + " €"
    }

    static func numero(_ texto: String?) -> Decimal? {
        guard let t = texto?.trimmingCharacters(in: .whitespaces), !t.isEmpty,
              let v = Decimal(string: t.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")),
              !v.isNaN else { return nil }
        return v
    }

    /// «30 oct» (con el año si no es el de `hoy`).
    static func fechaCorta(_ d: LocalDate, hoy: LocalDate? = nil) -> String {
        let base = "\(d.day) \(meses[max(0, min(11, d.month - 1))])"
        if let hoy, hoy.year != d.year { return base + " \(d.year)" }
        return base
    }

    /// «vie 30 oct».
    static func fechaConDia(_ d: LocalDate, hoy: LocalDate? = nil) -> String {
        dias[max(0, min(6, d.weekday - 1))] + " " + fechaCorta(d, hoy: hoy)
    }

    /// «hoy», «mañana», «ayer», «el vie 30 oct».
    static func cuando(_ d: LocalDate, hoy: LocalDate) -> String {
        if d == hoy { return "hoy" }
        if d == hoy.adding(days: 1) { return "mañana" }
        if d == hoy.adding(days: -1) { return "ayer" }
        return "el " + fechaConDia(d, hoy: hoy)
    }

    /// Días entre dos fechas (positivo si `b` va después).
    static func dias(de a: LocalDate, a b: LocalDate) -> Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.dateComponents([.day], from: a.date(), to: b.date()).day ?? 0
    }

    /// Fecha escrita (`2026-10-30`) en palabras; el texto tal cual si no es una fecha.
    static func fechaLegible(_ texto: String, hoy: LocalDate) -> String {
        guard let d = LocalDate(parsing: texto) else { return texto }
        return fechaConDia(d, hoy: hoy)
    }

    /// Primera letra en mayúscula («a medias» → «A medias»).
    static func capital(_ s: String) -> String {
        guard let p = s.first else { return s }
        return p.uppercased() + s.dropFirst()
    }

    /// Estado de una ficha como `TLSEstado` (icono y color; la palabra la pone la ficha).
    static func tlsEstado(_ tipo: NoteKind, _ estado: String?, hoy: LocalDate, vence: LocalDate? = nil) -> TLSEstado {
        guard let estado else { return .sinDato }
        let k = TextFolding.fold(estado)
        if let vence, vence < hoy, EstadosDeFicha.abierta(tipo, estado: estado) { return .mal }
        switch k {
        case "hecha", "cobrada", "ganada", "activo", "aceptada", "funciona sin ti", "montado", "publicado", "resuelta",
             "cerrado", "en uso", "activa", "firmado":
            return .bien
        case "bloqueada", "perdida", "rechazada", "caducada", "falta", "cancelada":
            return k == "cancelada" ? .sinDato : .mal
        case "en revision", "a medias", "borrador", "pausada", "pausado", "por confirmar":
            return .atencion
        default:
            return .sinDato
        }
    }

    /// Una línea de otra nota para enseñarla («Enlazan aquí», «Menciones sin enlazar»): sin las rayas de las tablas,
    /// las viñetas ni la sintaxis de los enlaces.
    static func extracto(_ linea: String) -> String {
        var t = linea.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") {
            t = t.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
        for p in ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "> "] where t.hasPrefix(p) {
            t.removeFirst(p.count)
            break
        }
        return LinkParser.plainText(t)
    }

    /// La línea de resumen sin los trozos que son un estado del tipo («… · Interesado»): el estado ya va en su
    /// pastilla y, en cuanto cambia, la línea escrita lo contradecía («Interesado» junto a «Activo»).
    static func sinEstado(_ linea: String?, tipo: NoteKind) -> String? {
        guard let linea else { return nil }
        let estados = Set(EstadosDeFicha.posibles(tipo).map(TextFolding.fold))
        guard !estados.isEmpty else { return linea }
        let partes = linea.components(separatedBy: " · ").filter { !estados.contains(TextFolding.fold($0.trimmingCharacters(in: .whitespaces))) }
        let s = partes.joined(separator: " · ")
        return s.isEmpty ? nil : s
    }

    /// Línea de resumen de la nota (`> Talleres Martín e Hijos SL · Interesado`, bajo el título).
    static func lineaResumen(_ cuerpo: String) -> String? {
        var vistoTitulo = false
        for l in cuerpo.split(separator: "\n", omittingEmptySubsequences: false).prefix(12) {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("# ") { vistoTitulo = true; continue }
            if t.isEmpty { continue }
            if t.hasPrefix("> "), !t.hasPrefix("> Guía:") {
                let s = String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                return s.contains("{{") ? nil : LinkParser.plainText(s)
            }
            if vistoTitulo { return nil }
        }
        return nil
    }
}
