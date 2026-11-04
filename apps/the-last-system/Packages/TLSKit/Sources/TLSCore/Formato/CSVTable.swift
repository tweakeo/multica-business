import Foundation

/// Tabla CSV leída según RFC 4180: comillas, comillas dobladas, saltos de línea dentro
/// de un campo, BOM y `\r\n`. El separador se detecta (`,` o `;`, como los extractos de banco).
public struct CSVTable: Sendable, Hashable {
    public let header: [String]
    public let rows: [[String]]
    public let delimiter: Character

    public init(header: [String], rows: [[String]], delimiter: Character) {
        self.header = header; self.rows = rows; self.delimiter = delimiter
    }

    public static func parse(_ raw: String, delimiter: Character? = nil) -> CSVTable {
        let text = TextDecoding.strippingBOM(raw)
        let sep = delimiter ?? detectDelimiter(text)
        let sepScalar = sep.unicodeScalars.first!
        var records: [[String]] = []
        var record: [String] = []
        var field = String.UnicodeScalarView()
        var inQuotes = false
        var fieldStarted = false
        let scalars = Array(text.unicodeScalars)
        var i = 0
        func endField() {
            record.append(String(field))
            field = String.UnicodeScalarView()
            fieldStarted = false
        }
        func endRecord() {
            endField()
            // Una línea vacía no es un registro.
            if !(record.count == 1 && record[0].isEmpty) { records.append(record) }
            record = []
        }
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.append("\""); i += 2; continue
                    }
                    inQuotes = false
                } else {
                    field.append(c)
                }
                i += 1
                continue
            }
            switch c {
            case "\"" where !fieldStarted && field.isEmpty:
                inQuotes = true; fieldStarted = true
            case sepScalar:
                endField()
            case "\r":
                endRecord()
                if i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
            case "\n":
                endRecord()
            default:
                field.append(c); fieldStarted = true
            }
            i += 1
        }
        if fieldStarted || !field.isEmpty || !record.isEmpty { endRecord() }
        let header = records.first ?? []
        return CSVTable(header: header, rows: Array(records.dropFirst()), delimiter: sep)
    }

    /// `;` si la primera línea tiene más `;` que `,` fuera de comillas.
    static func detectDelimiter(_ text: String) -> Character {
        var commas = 0, semis = 0, tabs = 0, inQuotes = false
        for c in text.unicodeScalars {
            if c == "\"" { inQuotes.toggle(); continue }
            if inQuotes { continue }
            if c == "\n" || c == "\r" { break }
            if c == "," { commas += 1 } else if c == ";" { semis += 1 } else if c == "\t" { tabs += 1 }
        }
        if tabs > commas && tabs > semis { return "\t" }
        return semis > commas ? ";" : ","
    }
}
