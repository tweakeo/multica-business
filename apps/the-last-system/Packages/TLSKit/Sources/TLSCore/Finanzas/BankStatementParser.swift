import Foundation

/// Una fila del extracto, ya leída.
public struct FilaExtracto: Sendable, Hashable {
    /// Fila del fichero (1 = la primera, contando la cabecera y lo que haya encima).
    public let fila: Int
    public let fecha: LocalDate
    public let fechaValor: LocalDate?
    /// Concepto tal como viene (sin espacios a los lados, en NFC).
    public let concepto: String
    /// Céntimos, con el signo del banco (negativo = sale dinero).
    public let importe: Int
    /// Saldo que da el banco tras el movimiento, si lo da.
    public let saldo: Int?

    public init(fila: Int, fecha: LocalDate, fechaValor: LocalDate?, concepto: String, importe: Int, saldo: Int?) {
        self.fila = fila; self.fecha = fecha; self.fechaValor = fechaValor
        self.concepto = concepto; self.importe = importe; self.saldo = saldo
    }
}

/// Una fila que no se pudo leer y por qué (para la vista previa).
public struct AvisoExtracto: Sendable, Hashable {
    public let fila: Int
    public let motivo: String
}

/// El extracto leído: sus filas, el formato con el que se leyó y lo que no se pudo leer.
public struct ExtractoLeido: Sendable, Hashable {
    public let filas: [FilaExtracto]
    /// El formato usado: el de la cuenta o el que se adivinó (para guardarlo en `Cuenta.md`).
    public let formato: FormatoExtracto
    /// `true` si el formato se adivinó (la cuenta no tenía uno).
    public let formatoAdivinado: Bool
    public let avisos: [AvisoExtracto]
}

public enum ErrorExtracto: Error, LocalizedError, Sendable, Equatable {
    case ilegible
    case vacio
    case sinCabecera
    case sinColumna(String)

    public var errorDescription: String? {
        switch self {
        case .ilegible: "No puedo leer este fichero como texto. ¿Es el extracto en CSV que da el banco?"
        case .vacio: "El extracto no tiene movimientos."
        case .sinCabecera:
            "No encuentro la fila con los nombres de las columnas (fecha, concepto e importe). Revisa que sea el extracto en CSV."
        case .sinColumna(let c):
            "El extracto no tiene la columna «\(c)» que dice el formato de la cuenta. Puede que el banco haya cambiado el formato."
        }
    }
}

/// Lee extractos de banco en CSV (PLAN §4.6 · entrada del banco).
///
/// - `;` con coma decimal, o `,` (o tabulador) con punto decimal; con el formato de la cuenta
///   (`formato_extracto`) o adivinando las columnas por su nombre.
/// - Fechas `DD/MM/AAAA` o ISO (y las variantes de `FormatoExtracto.FormatoFecha`).
/// - El importe conserva el signo del banco; si el banco separa cargos y abonos, importe = abono − cargo.
/// - BOM, `\r\n`, UTF-16 con BOM y Windows-1252 (extractos antiguos); líneas de cabecera del banco
///   encima de la tabla y filas de totales al final (se avisan y se saltan).
public enum BankStatementParser {
    /// Filas que se miran buscando la cabecera.
    static let filasCabecera = 30

    public static func leer(_ data: Data, formato: FormatoExtracto? = nil) throws -> ExtractoLeido {
        guard let texto = TextDecoding.decode(data) else { throw ErrorExtracto.ilegible }
        return try leer(texto: texto, formato: formato)
    }

    public static func leer(texto bruto: String, formato: FormatoExtracto? = nil) throws -> ExtractoLeido {
        let texto = TextDecoding.strippingBOM(bruto)
        guard texto.contains(where: { !$0.isWhitespace }) else { throw ErrorExtracto.vacio }
        if let formato {
            let registros = registros(texto, separador: formato.separador)
            guard let (i, cols) = cabecera(registros, buscando: formato.columnas) else {
                // Di qué columna falta (la primera que no aparece en ninguna fila de arriba).
                let falta = [formato.columnas.fecha, formato.columnas.concepto].first { c in
                    !registros.prefix(filasCabecera).contains { $0.map(normalizar).contains(normalizar(c)) }
                } ?? formato.columnas.importe ?? formato.columnas.fecha
                throw ErrorExtracto.sinColumna(falta)
            }
            return leerFilas(registros, cabecera: i, indices: cols, formato: formato, adivinado: false)
        }
        // Sin formato: el separador con el que aparece una cabecera reconocible.
        for sep in separadoresCandidatos(texto) {
            let registros = registros(texto, separador: sep)
            guard let (i, nombres) = cabeceraAdivinada(registros) else { continue }
            let datos = registros.dropFirst(i + 1)
            let decimal = adivinarDecimal(datos, nombres: nombres, separador: sep)
            let fechaForma = adivinarFecha(datos.compactMap { r in nombres.fecha < r.count ? r[nombres.fecha] : nil })
            let cab = registros[i]
            func nombre(_ j: Int?) -> String? { j.map { cab[$0].trimmingCharacters(in: .whitespaces) } }
            let columnas = FormatoExtracto.Columnas(
                fecha: nombre(nombres.fecha)!, fechaValor: nombre(nombres.fechaValor), concepto: nombre(nombres.concepto)!,
                importe: nombre(nombres.importe), cargo: nombre(nombres.cargo), abono: nombre(nombres.abono),
                saldo: nombre(nombres.saldo))
            let formato = FormatoExtracto(separador: sep, decimal: decimal, formatoFecha: fechaForma, columnas: columnas)
            return leerFilas(registros, cabecera: i, indices: nombres, formato: formato, adivinado: true)
        }
        throw ErrorExtracto.sinCabecera
    }

    // MARK: Registros

    /// Registros RFC 4180 con el separador dado (líneas vacías fuera).
    static func registros(_ texto: String, separador: Character) -> [[String]] {
        let t = CSVTable.parse(texto, delimiter: separador)
        return t.header.isEmpty && t.rows.isEmpty ? [] : [t.header] + t.rows
    }

    /// Separadores a probar, el más probable primero (el que más aparece fuera de comillas).
    static func separadoresCandidatos(_ texto: String) -> [Character] {
        var cuenta: [Character: Int] = [";": 0, ",": 0, "\t": 0]
        var entreComillas = false
        for c in texto.prefix(20_000) {
            if c == "\"" { entreComillas.toggle(); continue }
            if !entreComillas, cuenta[c] != nil { cuenta[c]! += 1 }
        }
        return cuenta.sorted { $0.value != $1.value ? $0.value > $1.value : String($0.key) < String($1.key) }.map(\.key)
    }

    // MARK: Cabecera

    struct Indices {
        var fecha: Int
        var fechaValor: Int?
        var concepto: Int
        var importe: Int?
        var cargo: Int?
        var abono: Int?
        var saldo: Int?
    }

    /// Nombre de columna para comparar: sin tildes, en minúsculas, `_` como espacio, sin «(eur)» ni «€».
    static func normalizar(_ s: String) -> String {
        var t = TextFolding.fold(s.trimmingCharacters(in: .whitespacesAndNewlines))
        for quitar in ["(eur)", "(€)", "€", "eur."] { t = t.replacingOccurrences(of: quitar, with: " ") }
        t = t.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: ". ")
        t = t.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        if t.hasSuffix(" eur") { t = String(t.dropLast(4)) }
        return t.trimmingCharacters(in: .whitespaces)
    }

    static let sinonimos: [(campo: String, nombres: [String])] = [
        ("fecha_valor", ["fecha valor", "f. valor", "fecha de valor", "valor", "value date"]),
        ("fecha", ["fecha", "fecha operacion", "fecha de operacion", "f. operacion", "fecha oper.", "f. oper.",
                   "fecha contable", "fecha movimiento", "fecha mov.", "date", "fecha de la operacion"]),
        ("concepto", ["concepto", "descripcion", "concepto comun", "concepto/descripcion", "movimiento", "detalle",
                      "observaciones", "description", "texto", "concepto propio"]),
        ("importe", ["importe", "cantidad", "importe operacion", "importe de la operacion", "amount", "importe eur"]),
        ("cargo", ["cargo", "cargos", "debe", "salida", "salidas", "debito"]),
        ("abono", ["abono", "abonos", "haber", "entrada", "entradas", "credito"]),
        ("saldo", ["saldo", "saldo disponible", "disponible", "saldo contable", "balance", "saldo tras la operacion"]),
    ]

    /// Cabecera reconocida por los nombres habituales de los bancos.
    static func cabeceraAdivinada(_ registros: [[String]]) -> (Int, Indices)? {
        for (i, r) in registros.prefix(filasCabecera).enumerated() {
            let n = r.map(normalizar)
            var usados = Set<Int>()
            func buscar(_ campo: String) -> Int? {
                let nombres = sinonimos.first { $0.campo == campo }!.nombres
                if let j = n.indices.first(where: { !usados.contains($0) && nombres.contains(n[$0]) }) {
                    usados.insert(j); return j
                }
                return nil
            }
            // La fecha valor antes que la fecha, para que «fecha valor» no se tome como la fecha.
            let fv = buscar("fecha_valor")
            guard let f = buscar("fecha"), let c = buscar("concepto") else { continue }
            let imp = buscar("importe"), car = buscar("cargo"), abo = buscar("abono"), sal = buscar("saldo")
            guard imp != nil || car != nil || abo != nil else { continue }
            return (i, Indices(fecha: f, fechaValor: fv, concepto: c, importe: imp, cargo: car, abono: abo, saldo: sal))
        }
        return nil
    }

    /// Cabecera con los nombres que dice el formato de la cuenta.
    static func cabecera(_ registros: [[String]], buscando cols: FormatoExtracto.Columnas) -> (Int, Indices)? {
        for (i, r) in registros.prefix(filasCabecera).enumerated() {
            let n = r.map(normalizar)
            func col(_ nombre: String?) -> Int?? {
                guard let nombre else { return .some(nil) }
                guard let j = n.firstIndex(of: normalizar(nombre)) else { return nil }
                return .some(j)
            }
            guard let f = col(cols.fecha) ?? nil, let c = col(cols.concepto) ?? nil,
                  let fv = col(cols.fechaValor), let imp = col(cols.importe), let car = col(cols.cargo),
                  let abo = col(cols.abono), let sal = col(cols.saldo) else { continue }
            return (i, Indices(fecha: f, fechaValor: fv, concepto: c, importe: imp, cargo: car, abono: abo, saldo: sal))
        }
        return nil
    }

    // MARK: Adivinar

    /// Coma decimal si algún importe acaba en `,d` o `,dd`; punto si acaba en `.d` o `.dd` con coma
    /// delante o sin coma. Con `;` y sin pistas, coma (el formato de los bancos españoles).
    static func adivinarDecimal(_ datos: ArraySlice<[String]>, nombres: Indices, separador: Character) -> Character {
        let cols = [nombres.importe, nombres.cargo, nombres.abono, nombres.saldo].compactMap { $0 }
        var coma = 0, punto = 0
        for r in datos {
            for j in cols where j < r.count {
                let v = DineroExacto.limpiar(r[j])
                guard let ultimo = v.lastIndex(where: { $0 == "," || $0 == "." }) else { continue }
                let tras = v[v.index(after: ultimo)...]
                guard (1...2).contains(tras.count), tras.allSatisfy({ $0.isNumber }) else { continue }
                if v[ultimo] == "," { coma += 1 } else { punto += 1 }
            }
        }
        if coma != punto { return coma > punto ? "," : "." }
        return separador == ";" ? "," : "."
    }

    /// La forma de fecha con la que se leen más fechas (empate: la española, día delante).
    static func adivinarFecha(_ valores: [String]) -> FormatoExtracto.FormatoFecha {
        let muestras = valores.prefix(400)
        var mejor = FormatoExtracto.FormatoFecha.ddmmaaaa
        var mejorCuenta = -1
        for f in FormatoExtracto.FormatoFecha.allCases {
            let n = muestras.filter { f.leer($0) != nil }.count
            if n > mejorCuenta { mejor = f; mejorCuenta = n }
        }
        return mejor
    }

    // MARK: Filas

    static func leerFilas(_ registros: [[String]], cabecera: Int, indices: Indices, formato: FormatoExtracto,
                          adivinado: Bool) -> ExtractoLeido {
        var filas: [FilaExtracto] = []
        var avisos: [AvisoExtracto] = []
        for (k, r) in registros.enumerated() where k > cabecera {
            let n = k + 1
            func campo(_ j: Int?) -> String? {
                guard let j, j < r.count else { return nil }
                let v = r[j].trimmingCharacters(in: .whitespacesAndNewlines)
                return v.isEmpty ? nil : v
            }
            if r.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let fechaTexto = campo(indices.fecha) else {
                avisos.append(AvisoExtracto(fila: n, motivo: "sin fecha: no es un movimiento")); continue
            }
            guard let fecha = formato.formatoFecha.leer(fechaTexto) else {
                avisos.append(AvisoExtracto(fila: n, motivo: "fecha que no entiendo («\(fechaTexto)»)")); continue
            }
            let importe: Int?
            if indices.importe != nil {
                importe = campo(indices.importe).flatMap { DineroExacto.centimos($0, decimal: formato.decimal) }
            } else {
                let cargoTexto = campo(indices.cargo), abonoTexto = campo(indices.abono)
                let cargo = cargoTexto.map { DineroExacto.centimos($0, decimal: formato.decimal) }
                let abono = abonoTexto.map { DineroExacto.centimos($0, decimal: formato.decimal) }
                if (cargoTexto == nil && abonoTexto == nil) || cargo == .some(nil) || abono == .some(nil) {
                    importe = nil
                } else {
                    // El cargo resta aunque el banco lo escriba en positivo.
                    importe = (abono.flatMap { $0 }.map { abs($0) } ?? 0) - (cargo.flatMap { $0 }.map { abs($0) } ?? 0)
                }
            }
            guard let importe else {
                avisos.append(AvisoExtracto(fila: n, motivo: "importe que no entiendo")); continue
            }
            var saldo: Int?
            if let s = campo(indices.saldo) {
                guard let v = DineroExacto.centimos(s, decimal: formato.decimal) else {
                    avisos.append(AvisoExtracto(fila: n, motivo: "saldo que no entiendo («\(s)»)")); continue
                }
                saldo = v
            }
            let concepto = (campo(indices.concepto) ?? "").precomposedStringWithCanonicalMapping
            let fechaValor = campo(indices.fechaValor).flatMap { formato.formatoFecha.leer($0) }
            filas.append(FilaExtracto(fila: n, fecha: fecha, fechaValor: fechaValor, concepto: concepto,
                                      importe: importe, saldo: saldo))
        }
        return ExtractoLeido(filas: filas, formato: formato, formatoAdivinado: adivinado, avisos: avisos)
    }
}
