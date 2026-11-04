import Foundation

/// CSV editable que se reescribe byte a byte: conserva el BOM, los saltos (`\r\n`), el
/// separador, las comillas de cada campo, las filas que no se tocan y las columnas que la
/// app no conoce. Lee igual que `CSVTable` (RFC 4180).
///
/// La actualización es por clave (`id`) y en su sitio; una fila nueva va al final.
public struct CSVDocument: Sendable, Hashable {
    public let bom: Bool
    public let delimiter: Character
    /// Salto de línea de las filas nuevas (el primero del fichero).
    public let eol: String

    /// Un registro: texto exacto, su salto y los campos (en bruto y leídos).
    struct Record: Sendable, Hashable {
        var rawFields: [String]
        var eol: String
        var fields: [String]
        /// Línea vacía: no es un registro (se conserva tal cual).
        var isBlank: Bool { rawFields.count == 1 && rawFields[0].isEmpty }
    }

    private var records: [Record]
    /// Primer registro con datos: la cabecera.
    private var headerIndex: Int?

    public init(text raw: String, delimiter: Character? = nil) {
        var text = raw
        bom = text.hasPrefix("\u{FEFF}")
        if bom { text.removeFirst() }
        let sep = delimiter ?? CSVTable.detectDelimiter(text)
        self.delimiter = sep
        self.eol = TextLines.dominantEOL(text)
        self.records = Self.parse(text, delimiter: sep)
        self.headerIndex = records.firstIndex { !$0.isBlank }
    }

    /// `nil` si no es UTF-8 válido.
    public init?(data: Data) {
        guard let e = EditableText(data: data) else { return nil }
        self.init(text: (e.bom ? "\u{FEFF}" : "") + e.text)
    }

    public var text: String {
        var s = bom ? "\u{FEFF}" : ""
        let sep = String(delimiter)
        for r in records { s += r.rawFields.joined(separator: sep) + r.eol }
        return s
    }

    public var data: Data { Data(text.utf8) }

    public var header: [String] {
        headerIndex.map { records[$0].fields } ?? []
    }

    /// Filas de datos como diccionarios (cabecera → valor). Lo que falta va vacío.
    public var rows: [[String: String]] {
        dataIndices.map { dict(records[$0]) }
    }

    private var dataIndices: [Int] {
        guard let h = headerIndex else { return [] }
        return records.indices.filter { $0 > h && !records[$0].isBlank }
    }

    private func dict(_ r: Record) -> [String: String] {
        var d: [String: String] = [:]
        for (i, h) in header.enumerated() { d[h] = i < r.fields.count ? r.fields[i] : "" }
        return d
    }

    func column(_ name: String) -> Int? {
        let h = header.map { $0.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping }
        let n = name.trimmingCharacters(in: .whitespaces).precomposedStringWithCanonicalMapping
        if let i = h.firstIndex(of: n) { return i }
        return h.firstIndex { $0.lowercased() == n.lowercased() }
    }

    /// Fila con `key` = `value` (`nil` si no hay).
    public func row(key: String, value: String) -> [String: String]? {
        guard let k = column(key) else { return nil }
        return dataIndices.first { i in k < records[i].fields.count && records[i].fields[k] == value }.map { dict(records[$0]) }
    }

    public enum UpsertResult: Sendable, Hashable { case insertada, actualizada, sinCambios }

    /// Inserta o actualiza la fila con la clave `key` de `values`. Solo cambian los campos
    /// dados (los demás, también las columnas desconocidas, quedan como estaban).
    /// `protectManual`: las filas con `fuente` u `origen` = manual no se tocan.
    @discardableResult
    public mutating func upsert(_ values: [String: String], key: String = "id", protectManual: Bool) throws -> UpsertResult {
        guard headerIndex != nil else { throw WriteError.csvSinCabecera }
        guard let k = column(key), let keyValue = values.first(where: { column($0.key) == k })?.value, !keyValue.isEmpty else {
            throw WriteError.columnaDesconocida(key)
        }
        var targets: [(Int, String)] = []
        for (name, value) in values {
            guard let i = column(name) else { throw WriteError.columnaDesconocida(name) }
            targets.append((i, value))
        }
        let matches = dataIndices.filter { k < records[$0].fields.count && records[$0].fields[k] == keyValue }
        guard matches.count <= 1 else { throw WriteError.claveDuplicada(keyValue) }
        if let idx = matches.first {
            var r = records[idx]
            if protectManual, Self.isManual(dict(r)) { throw WriteError.filaManual(keyValue) }
            var changed = false
            for (i, value) in targets {
                while r.fields.count <= i { r.fields.append(""); r.rawFields.append("") }
                if r.fields[i] == value { continue }
                r.fields[i] = value
                r.rawFields[i] = encode(value)
                changed = true
            }
            guard changed else { return .sinCambios }
            records[idx] = r
            return .actualizada
        }
        var fields = Array(repeating: "", count: header.count)
        for (i, value) in targets { fields[i] = value }
        let new = Record(rawFields: fields.map(encode), eol: "", fields: fields)
        // Tras el último registro con datos; las líneas en blanco del final se quedan detrás.
        let lastData = records.lastIndex { !$0.isBlank } ?? (records.count - 1)
        if records[lastData].eol.isEmpty {
            // El fichero no terminaba en salto: la fila nueva tampoco lleva salto.
            records[lastData].eol = eol
            records.insert(new, at: lastData + 1)
        } else {
            var withEOL = new
            withEOL.eol = eol
            records.insert(withEOL, at: lastData + 1)
        }
        return .insertada
    }

    /// Añade filas nuevas tras el último registro con datos, en el separador y el orden de columnas del fichero.
    /// **Nunca pisa ni repite**: si la clave de alguna ya está en el fichero (o se repite entre ellas), lanza
    /// `WriteError.filaYaExiste` y no cambia nada. Una sola lectura del CSV para todas (un extracto de un año).
    public mutating func insertNew(_ rows: [[String: String]], key: String = "id") throws {
        guard headerIndex != nil else { throw WriteError.csvSinCabecera }
        guard let k = column(key) else { throw WriteError.columnaDesconocida(key) }
        let ancho = header.count
        var columnas: [String: Int] = [:]
        func indice(_ nombre: String) throws -> Int {
            if let i = columnas[nombre] { return i }
            guard let i = column(nombre) else { throw WriteError.columnaDesconocida(nombre) }
            columnas[nombre] = i
            return i
        }
        var claves = Set(dataIndices.compactMap { k < records[$0].fields.count ? records[$0].fields[k] : nil })
        var nuevos: [Record] = []
        for values in rows {
            var fields = Array(repeating: "", count: ancho)
            for (name, value) in values { fields[try indice(name)] = value }
            let clave = fields[k]
            guard !clave.isEmpty else { throw WriteError.columnaDesconocida(key) }
            guard claves.insert(clave).inserted else { throw WriteError.filaYaExiste(clave) }
            nuevos.append(Record(rawFields: fields.map(encode), eol: eol, fields: fields))
        }
        guard !nuevos.isEmpty else { return }
        // Como `upsert`: tras el último registro con datos; las líneas en blanco del final se quedan detrás. Si el
        // fichero no terminaba en salto, la última fila nueva tampoco lo lleva.
        let lastData = records.lastIndex { !$0.isBlank } ?? (records.count - 1)
        if records[lastData].eol.isEmpty {
            records[lastData].eol = eol
            nuevos[nuevos.count - 1].eol = ""
        }
        records.insert(contentsOf: nuevos, at: lastData + 1)
    }

    /// Fila escrita a mano: `fuente` u `origen` = manual.
    public static func isManual(_ row: [String: String]) -> Bool {
        for (k, v) in row where ["fuente", "origen"].contains(k.trimmingCharacters(in: .whitespaces).lowercased()) {
            if v.trimmingCharacters(in: .whitespaces).lowercased() == "manual" { return true }
        }
        return false
    }

    /// Campo con comillas solo si hace falta (separador, comillas o saltos).
    func encode(_ value: String) -> String {
        let needs = value.contains(delimiter) || value.contains("\"") || value.contains(where: { $0.isNewline })
        guard needs else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: Lectura exacta

    /// Registros con sus campos en bruto. Misma gramática que `CSVTable.parse`.
    static func parse(_ text: String, delimiter: Character) -> [Record] {
        let sep = delimiter.unicodeScalars.first!
        let scalars = Array(text.unicodeScalars)
        var records: [Record] = []
        var rawFields: [String] = []
        var fields: [String] = []
        var raw = String.UnicodeScalarView()
        var value = String.UnicodeScalarView()
        var inQuotes = false
        var fieldStarted = false
        var i = 0
        func endField() {
            rawFields.append(String(raw)); fields.append(String(value))
            raw = String.UnicodeScalarView(); value = String.UnicodeScalarView()
            fieldStarted = false
        }
        func endRecord(_ eol: String) {
            endField()
            records.append(Record(rawFields: rawFields, eol: eol, fields: fields))
            rawFields = []; fields = []
        }
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                raw.append(c)
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        raw.append(scalars[i + 1]); value.append("\""); i += 2; continue
                    }
                    inQuotes = false
                } else {
                    value.append(c)
                }
                i += 1
                continue
            }
            switch c {
            case "\"" where !fieldStarted && value.isEmpty:
                inQuotes = true; fieldStarted = true; raw.append(c)
            case sep:
                endField()
            case "\r":
                if i + 1 < scalars.count, scalars[i + 1] == "\n" { endRecord("\r\n"); i += 1 } else { endRecord("\r") }
            case "\n":
                endRecord("\n")
            default:
                value.append(c); raw.append(c); fieldStarted = true
            }
            i += 1
        }
        if fieldStarted || !raw.isEmpty || !rawFields.isEmpty { endRecord("") }
        return records
    }
}
