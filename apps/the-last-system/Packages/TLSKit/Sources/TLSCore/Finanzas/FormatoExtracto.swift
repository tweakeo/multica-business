import Foundation
import Yams

/// Cómo viene el extracto de una cuenta: `formato_extracto` de su `Cuenta.md` (PLAN §4.3, plantilla
/// «Cuenta bancaria»). Separador, separador decimal, forma de la fecha y qué columna del fichero es cada dato.
///
/// ```yaml
/// formato_extracto:
///   separador: ";"
///   decimal: ","
///   formato_fecha: DD/MM/AAAA
///   columnas:
///     fecha: Fecha operación
///     fecha_valor: Fecha valor
///     concepto: Concepto
///     importe: Importe          # con el signo del banco; o `cargo` y `abono` por separado
///     saldo: Saldo
/// ```
public struct FormatoExtracto: Sendable, Hashable {
    /// Forma de las fechas del fichero.
    public enum FormatoFecha: String, Sendable, Hashable, CaseIterable {
        case ddmmaaaa = "DD/MM/AAAA"
        case ddmmaaaaGuion = "DD-MM-AAAA"
        case ddmmaaaaPunto = "DD.MM.AAAA"
        case ddmmaa = "DD/MM/AA"
        case iso = "AAAA-MM-DD"
        case aaaammddBarra = "AAAA/MM/DD"
        case mmddaaaa = "MM/DD/AAAA"

        /// Lee `texto` con esta forma (con o sin ceros delante; la hora que venga detrás se ignora).
        public func leer(_ texto: String) -> LocalDate? {
            var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            if let espacio = t.firstIndex(where: { $0 == " " || $0 == "T" }), t.distance(from: t.startIndex, to: espacio) >= 6 {
                t = String(t[..<espacio])
            }
            let sep: Character
            switch self {
            case .ddmmaaaa, .ddmmaa, .mmddaaaa, .aaaammddBarra: sep = "/"
            case .ddmmaaaaGuion, .iso: sep = "-"
            case .ddmmaaaaPunto: sep = "."
            }
            let p = t.split(separator: sep, omittingEmptySubsequences: false).map(String.init)
            guard p.count == 3, p.allSatisfy({ !$0.isEmpty && $0.count <= 4 && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let a = Int(p[0]), let b = Int(p[1]), let c = Int(p[2]) else { return nil }
            switch self {
            case .ddmmaaaa, .ddmmaaaaGuion, .ddmmaaaaPunto:
                guard p[2].count == 4 else { return nil }
                return LocalDate(year: c, month: b, day: a)
            case .ddmmaa:
                guard p[2].count == 2 else { return nil }
                return LocalDate(year: 2000 + c, month: b, day: a)
            case .iso, .aaaammddBarra:
                guard p[0].count == 4 else { return nil }
                return LocalDate(year: a, month: b, day: c)
            case .mmddaaaa:
                guard p[2].count == 4 else { return nil }
                return LocalDate(year: c, month: a, day: b)
            }
        }

        /// Acepta también la forma en inglés (`DD/MM/YYYY`) y en minúsculas.
        public init?(escrito: String) {
            let t = escrito.trimmingCharacters(in: .whitespaces).uppercased()
                .replacingOccurrences(of: "YYYY", with: "AAAA").replacingOccurrences(of: "YY", with: "AA")
            guard let f = Self(rawValue: t) else { return nil }
            self = f
        }
    }

    /// Qué columna del fichero (su cabecera, tal como viene) es cada dato.
    public struct Columnas: Sendable, Hashable {
        public var fecha: String
        public var fechaValor: String?
        public var concepto: String
        /// Importe con el signo del banco (negativo = sale dinero).
        public var importe: String?
        /// Si el banco separa cargos y abonos: importe = abono − cargo.
        public var cargo: String?
        public var abono: String?
        public var saldo: String?

        public init(fecha: String, fechaValor: String? = nil, concepto: String, importe: String? = nil,
                    cargo: String? = nil, abono: String? = nil, saldo: String? = nil) {
            self.fecha = fecha; self.fechaValor = fechaValor; self.concepto = concepto
            self.importe = importe; self.cargo = cargo; self.abono = abono; self.saldo = saldo
        }

        /// Hay de dónde sacar el importe.
        public var tieneImporte: Bool { importe != nil || cargo != nil || abono != nil }
    }

    public var separador: Character
    public var decimal: Character
    public var formatoFecha: FormatoFecha
    public var columnas: Columnas

    public init(separador: Character, decimal: Character, formatoFecha: FormatoFecha, columnas: Columnas) {
        self.separador = separador; self.decimal = decimal; self.formatoFecha = formatoFecha; self.columnas = columnas
    }

    // MARK: Lectura de la ficha de la cuenta

    /// `formato_extracto` del frontmatter de una `Cuenta.md`. `nil` si no está, si está sin rellenar
    /// (la plantilla lo trae con las columnas vacías) o si no se entiende.
    public static func leer(deFicha texto: String) -> FormatoExtracto? {
        // Primero la lectura con topes (alias y tamaño) del núcleo; solo si es legible se mira el mapa.
        guard let yaml = NoteDocument(text: texto).frontmatterText, FrontmatterReader.read(yaml).isValid,
              let node = try? Yams.compose(yaml: yaml, Resolver.basic),
              case .mapping(let raiz) = node else { return nil }
        guard let fe = valor(raiz, "formato_extracto"), case .mapping(let m) = fe else { return nil }
        func escalar(_ map: Node.Mapping, _ clave: String) -> String? {
            guard let n = valor(map, clave), case .scalar(let s) = n else { return nil }
            let t = s.string.trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t == "~" || t.lowercased() == "null" ? nil : t
        }
        guard let cols = valor(m, "columnas"), case .mapping(let c) = cols,
              let fecha = escalar(c, "fecha"), let concepto = escalar(c, "concepto") else { return nil }
        let columnas = Columnas(fecha: fecha, fechaValor: escalar(c, "fecha_valor"), concepto: concepto,
                                importe: escalar(c, "importe"), cargo: escalar(c, "cargo"), abono: escalar(c, "abono"),
                                saldo: escalar(c, "saldo"))
        guard columnas.tieneImporte else { return nil }
        let separador = escalar(m, "separador").flatMap(Self.separador(escrito:)) ?? ";"
        let decimalEscrito: Character? = escalar(m, "decimal").flatMap { t -> Character? in
            t.first == "." || t.first == "," ? t.first : nil
        }
        let decimal: Character = decimalEscrito ?? (separador == ";" ? "," : ".")
        let fechaForma = escalar(m, "formato_fecha").flatMap(FormatoFecha.init(escrito:)) ?? .ddmmaaaa
        return FormatoExtracto(separador: separador, decimal: decimal, formatoFecha: fechaForma, columnas: columnas)
    }

    static func valor(_ m: Node.Mapping, _ clave: String) -> Node? {
        for (k, v) in m {
            if case .scalar(let s) = k, s.string.precomposedStringWithCanonicalMapping == clave { return v }
        }
        return nil
    }

    static func separador(escrito: String) -> Character? {
        switch escrito.lowercased() {
        case ";", "punto y coma": ";"
        case ",", "coma": ","
        case "\t", "\\t", "tab", "tabulador": "\t"
        case "|": "|"
        default: nil
        }
    }

    // MARK: Escritura en la ficha

    /// Valor de `formato_extracto` para `cambiarPropiedades` (un mapa de varias líneas).
    public var propiedad: Property {
        Property(key: "formato_extracto", value: .raw(yaml))
    }

    /// El mapa en YAML (sin la clave), con las comillas que hacen falta.
    public var yaml: String {
        func q(_ s: String) -> String { YAMLScalar.render(text: s) }
        let sep = separador == "\t" ? "\"\\t\"" : "\"\(separador)\""
        var lineas = [
            "separador: \(sep)",
            "decimal: \"\(decimal)\"",
            "formato_fecha: \(formatoFecha.rawValue)",
            "columnas:",
            "  fecha: \(q(columnas.fecha))",
        ]
        if let v = columnas.fechaValor { lineas.append("  fecha_valor: \(q(v))") }
        lineas.append("  concepto: \(q(columnas.concepto))")
        if let v = columnas.importe { lineas.append("  importe: \(q(v))") }
        if let v = columnas.cargo { lineas.append("  cargo: \(q(v))") }
        if let v = columnas.abono { lineas.append("  abono: \(q(v))") }
        if let v = columnas.saldo { lineas.append("  saldo: \(q(v))") }
        return lineas.joined(separator: "\n")
    }
}
