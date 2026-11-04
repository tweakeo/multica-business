import Foundation

/// Un enlace de una celda de relación: el texto que se ve y la ficha a la que lleva (si existe).
public struct EnlaceFila: Hashable, Sendable {
    public let texto: String
    public let ruta: VaultPath?

    public init(texto: String, ruta: VaultPath?) {
        self.texto = texto
        self.ruta = ruta
    }
}

/// Valor ya calculado de una columna calculada: el texto, la cifra para ordenar y sumar, y si avisa.
public struct ValorCalculado: Hashable, Sendable {
    public let texto: String
    public let numero: Double?
    /// Algo pide atención (una oportunidad quieta, un cobro pendiente).
    public let aviso: Bool

    public init(_ texto: String, numero: Double? = nil, aviso: Bool = false) {
        self.texto = texto
        self.numero = numero
        self.aviso = aviso
    }
}

/// Una fila de una base: una ficha (nota con `tls_type`) o una fila de un CSV.
public struct FilaBase: Identifiable, Hashable, Sendable {
    public enum Origen: Hashable, Sendable {
        case ficha(VaultPath)
        /// Fila de un CSV, identificada por su columna clave (`id`) y su valor.
        case filaCSV(VaultPath, columnaClave: String, valorClave: String)

        /// La nota o el CSV donde vive.
        public var ruta: VaultPath {
            switch self {
            case .ficha(let p), .filaCSV(let p, _, _): p
            }
        }
    }

    public let id: String
    public let origen: Origen
    public var titulo: String
    public let tipo: NoteKind
    public let area: AreaCode?
    /// Propiedades de la ficha o columnas del CSV, tal como se leen.
    public var valores: [String: PropertyValue]
    /// Relaciones de cada propiedad, ya resueltas a su ficha.
    public var enlaces: [String: [EnlaceFila]]
    /// Columnas calculadas (clave de columna → valor).
    public var calculados: [String: ValorCalculado]
    public let modificada: Date?
    public let privado: Bool
    /// Claves que de verdad tiene (propiedades o cabecera del CSV): las que se pueden escribir tal cual.
    public let claves: [String]
    /// Documento que acompaña a la fila (el PDF de un gasto).
    public var documento: VaultPath?

    public init(id: String, origen: Origen, titulo: String, tipo: NoteKind, area: AreaCode?,
                valores: [String: PropertyValue], enlaces: [String: [EnlaceFila]] = [:],
                calculados: [String: ValorCalculado] = [:], modificada: Date?, privado: Bool, claves: [String],
                documento: VaultPath? = nil) {
        self.id = id; self.origen = origen; self.titulo = titulo; self.tipo = tipo; self.area = area
        self.valores = valores; self.enlaces = enlaces; self.calculados = calculados; self.modificada = modificada
        self.privado = privado; self.claves = claves; self.documento = documento
    }

    public var ruta: VaultPath { origen.ruta }

    public var esFilaCSV: Bool {
        if case .filaCSV = origen { return true }
        return false
    }

    // MARK: Leer una columna

    /// Valor de la columna: el primero no vacío entre su clave y sus alias.
    public func valor(_ col: ColumnaBase) -> PropertyValue? {
        switch col.clave {
        case ColumnaBase.claveTitulo: return .text(titulo)
        case ColumnaBase.claveArea: return area.map { .text($0.nombre) }
        default: break
        }
        for k in col.claves {
            if let v = valores[k], !v.estaVacio { return v }
        }
        return nil
    }

    /// Valor de una propiedad por su nombre (sin columna).
    public func valor(_ clave: String) -> PropertyValue? {
        if clave == ColumnaBase.claveTitulo { return .text(titulo) }
        if clave == ColumnaBase.claveArea { return area.map { .text($0.nombre) } }
        guard let v = valores[clave], !v.estaVacio else { return nil }
        return v
    }

    /// Texto plano de una propiedad (los enlaces, con su texto visible).
    public func texto(_ clave: String) -> String? {
        guard let v = valor(clave) else { return nil }
        let t = FormatoBase.textoVisible(v)
        return t.isEmpty ? nil : t
    }

    /// Clave que la fila tiene de verdad para esa columna (la que se escribe al editar).
    public func claveReal(_ col: ColumnaBase) -> String? {
        let presentes = Set(claves)
        if let k = col.claves.first(where: { presentes.contains($0) }) { return k }
        // Una propiedad que aún no tiene la ficha se escribe con su nombre del diccionario.
        return esFilaCSV ? nil : col.clave
    }

    public func enlaces(_ col: ColumnaBase) -> [EnlaceFila] {
        for k in col.claves {
            if let e = enlaces[k], !e.isEmpty { return e }
        }
        return []
    }

    public func calculado(_ col: ColumnaBase) -> ValorCalculado? { calculados[col.clave] }

    /// Cifra de la columna (dinero, porcentaje, número o calculada).
    public func numero(_ col: ColumnaBase) -> Double? {
        if col.tipo == .calculada { return calculado(col)?.numero }
        guard let v = valor(col) else { return nil }
        return FormatoBase.numero(FormatoBase.textoVisible(v))
    }

    public func fecha(_ col: ColumnaBase) -> LocalDate? {
        guard let v = valor(col) else { return nil }
        return LocalDate(parsing: FormatoBase.textoVisible(v))
    }

    public func fecha(_ clave: String) -> LocalDate? {
        texto(clave).flatMap { LocalDate(parsing: $0) }
    }

    /// Lo que se ve en la celda.
    public func textoCelda(_ col: ColumnaBase, hoy: LocalDate) -> String {
        switch col.tipo {
        case .calculada:
            return calculado(col)?.texto ?? "—"
        case .relacion:
            let e = enlaces(col)
            if !e.isEmpty { return e.map(\.texto).joined(separator: ", ") }
            return valor(col).map(FormatoBase.textoVisible) ?? ""
        case .dinero:
            guard let n = numero(col) else { return valor(col).map(FormatoBase.textoVisible) ?? "" }
            return FormatoBase.euros(n)
        case .porcentaje:
            guard let n = numero(col) else { return valor(col).map(FormatoBase.textoVisible) ?? "" }
            return FormatoBase.cifra(n) + " %"
        case .fecha:
            guard let d = fecha(col) else { return valor(col).map(FormatoBase.textoVisible) ?? "" }
            return FormatoBase.fecha(d, hoy: hoy)
        case .siNo:
            guard let v = valor(col) else { return "" }
            if case .bool(let b) = v { return b ? "Sí" : "No" }
            return FormatoBase.textoVisible(v)
        case .persona:
            return valor(col).map { FormatoBase.persona(FormatoBase.textoVisible($0)) } ?? ""
        case .opciones:
            guard let v = valor(col) else { return "" }
            if case .list(let l) = v { return l.map(FormatoBase.opcionVisible).joined(separator: ", ") }
            return FormatoBase.opcionVisible(FormatoBase.textoVisible(v))
        case .opcion:
            return valor(col).map { FormatoBase.opcionVisible(FormatoBase.textoVisible($0)) } ?? ""
        case .titulo, .texto, .numero:
            return valor(col).map(FormatoBase.textoVisible) ?? ""
        }
    }

    /// Valores de una columna de opciones (lista) o de una opción.
    public func valoresOpcion(_ col: ColumnaBase) -> [String] {
        guard let v = valor(col) else { return [] }
        if case .list(let l) = v { return l }
        let t = FormatoBase.textoVisible(v)
        return t.isEmpty ? [] : [t]
    }

    /// Número visible (T-0042, F-2026-0007) o código (VE2).
    public var codigo: String? { texto("numero") ?? texto("codigo") }

    /// Otros nombres (`aliases`).
    public var otrosNombres: [String] {
        switch valores["aliases"] ?? valores["alias"] {
        case .list(let l)?: l
        case .text(let t)? where !t.isEmpty: [t]
        default: []
        }
    }
}

public extension PropertyValue {
    /// Vacío, lista vacía o texto en blanco.
    var estaVacio: Bool {
        switch self {
        case .empty: true
        case .list(let l): l.isEmpty
        case .text(let s), .number(let s), .raw(let s): s.trimmingCharacters(in: .whitespaces).isEmpty
        case .bool: false
        }
    }
}

/// Formatos de las bases, en español de España: «1.234,56 €», «24 oct», «hoy».
public enum FormatoBase {
    public static let meses = ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"]
    public static let mesesLargos = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto",
                                     "septiembre", "octubre", "noviembre", "diciembre"]
    /// 1 = lunes.
    public static let diasSemana = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]

    /// Texto de un valor con los enlaces sustituidos por su texto visible (`[[x|Nombre]]` → «Nombre»).
    public static func textoVisible(_ v: PropertyValue) -> String {
        switch v {
        case .list(let l): return l.map { textoVisible(.text($0)) }.joined(separator: ", ")
        case .text(let s) where s.contains("[["):
            return LinkParser.plainText(s)
        default:
            return v.displayText
        }
    }

    /// «150.00», «150,00», «1.234,56», «-663.00» → número.
    public static func numero(_ texto: String) -> Double? {
        var t = texto.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty else { return nil }
        if t.contains(","), t.contains(".") {
            t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        } else if t.contains(",") {
            t = t.replacingOccurrences(of: ",", with: ".")
        }
        // «nan», «inf» o «1e999» no son cifras (Double los aceptaría).
        guard let n = Double(t), n.isFinite else { return nil }
        return n
    }

    /// Desde aquí no se escribe ni se enseña una cifra: no cabe en un entero sin perder dígitos.
    public static let cifraMaxima: Double = 1e15

    /// Lo que escribe una persona en una celda o un campo de cifra. Como `numero`, y además lee «1.235» o
    /// «15.000» (uno a tres dígitos y grupos de tres tras puntos) como millares, que es como la app enseña las
    /// cifras: antes, cambiar «1.234» por «1.235» guardaba 1,235. «1.5», «0.125» y «150.00» siguen siendo decimales.
    public static func numeroEscrito(_ texto: String) -> Double? {
        let t = texto.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "").replacingOccurrences(of: " ", with: "")
        if t.range(of: #"^[-+]?[1-9][0-9]{0,2}(\.[0-9]{3})+$"#, options: .regularExpression) != nil {
            return numero(t.replacingOccurrences(of: ".", with: ""))
        }
        return numero(texto)
    }

    /// La cifra para editarla: sin puntos de millares y con coma decimal («1234,56», «15000»), para que al
    /// guardarla sin tocar se lea igual.
    public static func cifraParaEditar(_ n: Double, decimales: Int? = nil) -> String {
        guard n.isFinite, abs(n) < cifraMaxima else { return n.isFinite ? String(n) : "" }
        return cifra(n, decimales: decimales).replacingOccurrences(of: ".", with: "")
    }

    /// Cifra con separador de millares y coma decimal (sin decimales si es entera).
    public static func cifra(_ n: Double, decimales: Int? = nil) -> String {
        // Sin dato que enseñar (0/0, infinito): una raya, nunca «NaN» (ni un cierre al convertir a entero).
        guard n.isFinite, abs(n) < cifraMaxima else { return "—" }
        let d = decimales ?? (n.rounded() == n ? 0 : 2)
        let escala = pow(10.0, Double(d))
        let redondeado = (abs(n) * escala).rounded()
        let entero = Int64(redondeado / escala)
        let fraccion = Int64(redondeado) - entero * Int64(escala)
        let digitos = String(entero)
        var grupos: [Substring] = []
        var fin = digitos.endIndex
        while fin > digitos.startIndex {
            let inicio = digitos.index(fin, offsetBy: -3, limitedBy: digitos.startIndex) ?? digitos.startIndex
            grupos.insert(digitos[inicio..<fin], at: 0)
            fin = inicio
        }
        var s = (n < 0 && redondeado > 0 ? "-" : "") + grupos.joined(separator: ".")
        if d > 0 {
            let f = String(fraccion)
            s += "," + String(repeating: "0", count: max(0, d - f.count)) + f
        }
        return s
    }

    /// «1.234,56 €»; `redondo` = sin decimales («3.270 €»).
    public static func euros(_ n: Double, redondo: Bool = false) -> String {
        guard n.isFinite else { return "—" }
        return cifra(redondo ? n.rounded() : n, decimales: redondo ? 0 : 2) + " €"
    }

    /// «hoy», «mañana», «ayer», «24 oct» o «24 oct 2025».
    public static func fecha(_ d: LocalDate, hoy: LocalDate) -> String {
        if d == hoy { return "hoy" }
        if d == hoy.adding(days: 1) { return "mañana" }
        if d == hoy.adding(days: -1) { return "ayer" }
        let base = "\(d.day) \(meses[d.month - 1])"
        return d.year == hoy.year ? base : "\(base) \(d.year)"
    }

    /// «vie 23 oct».
    public static func fechaConDia(_ d: LocalDate) -> String {
        "\(diasSemana[d.weekday - 1]) \(d.day) \(meses[d.month - 1])"
    }

    /// «octubre de 2026».
    public static func mes(_ year: Int, _ month: Int) -> String {
        "\(mesesLargos[month - 1]) de \(year)"
    }

    /// Lunes de la semana de `d`.
    public static func lunes(de d: LocalDate) -> LocalDate { d.adding(days: -(d.weekday - 1)) }

    /// «Semana del 19 al 25 de octubre», «Semana del 28 de septiembre al 4 de octubre».
    public static func semana(_ lunes: LocalDate) -> String {
        let domingo = lunes.adding(days: 6)
        if lunes.month == domingo.month {
            return "Semana del \(lunes.day) al \(domingo.day) de \(mesesLargos[domingo.month - 1])"
        }
        return "Semana del \(lunes.day) de \(mesesLargos[lunes.month - 1]) al \(domingo.day) de \(mesesLargos[domingo.month - 1])"
    }

    /// «10:00», «9.30», «17h», «9» → (hora, minutos). `nil` si no es una hora.
    public static func hora(_ texto: String) -> (hora: Int, minuto: Int)? {
        let t = texto.trimmingCharacters(in: .whitespaces).lowercased()
        let partes = t.split(whereSeparator: { $0 == ":" || $0 == "." || $0 == "h" }).map(String.init)
        guard (1...2).contains(partes.count), let h = Int(partes[0]), (0...23).contains(h) else { return nil }
        let m = partes.count == 2 ? Int(partes[1]) : 0
        guard let m, (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// Fecha de un fichero («21 oct»).
    public static func fecha(_ date: Date, hoy: LocalDate) -> String {
        fecha(LocalDate(date: date), hoy: hoy)
    }

    /// Persona o asistente: `lucia` → «Lucia», `agente:comercial` → «Comercial (asistente)».
    public static func persona(_ valor: String) -> String {
        let v = valor.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return "" }
        if v.lowercased().hasPrefix("agente:") {
            let nombre = String(v.dropFirst("agente:".count)).replacingOccurrences(of: "-", with: " ")
            return nombre.prefix(1).uppercased() + nombre.dropFirst() + " (asistente)"
        }
        if v.contains(" ") || v.first?.isUppercase == true { return v }
        return v.prefix(1).uppercased() + v.dropFirst()
    }

    /// Opción tal como se enseña: `cliente` → «Cliente», `ventas` → «Ventas».
    public static func opcionVisible(_ valor: String) -> String {
        if let a = AreaCode.allCases.first(where: { $0.layoutKey == valor }) { return a.nombre }
        guard let f = valor.first, f.isLowercase else { return valor }
        return valor.prefix(1).uppercased() + valor.dropFirst()
    }

    /// Plural sencillo: `cuenta(1, "ficha", "fichas")` → «1 ficha».
    public static func cuenta(_ n: Int, _ uno: String, _ varios: String) -> String {
        "\(n) \(n == 1 ? uno : varios)"
    }

    /// Iniciales de un nombre («Jorge Martín» → «JM»).
    public static func iniciales(_ nombre: String) -> String {
        let palabras = nombre.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .filter { $0.first?.isUppercase == true || $0.first?.isNumber == true }
        let p = palabras.isEmpty ? Array(nombre.split(separator: " ")) : palabras
        return p.prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}
