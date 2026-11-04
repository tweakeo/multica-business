import Foundation

/// Celdas de un CSV con su posición exacta (bytes UTF-8, sin BOM), para cambiar una sola celda
/// sin tocar nada más. Lee como `CSVTable` (RFC 4180: comillas, comillas dobladas y saltos dentro
/// de un campo).
enum CSVCells {
    struct Cell: Sendable, Hashable {
        /// Bytes del campo tal como está escrito (con sus comillas).
        var range: Range<Int>
        var value: String
        var quoted: Bool
    }

    struct Record: Sendable {
        var cells: [Cell]
        var isBlank: Bool { cells.count == 1 && cells[0].range.isEmpty }
    }

    static func parse(_ b: [UInt8], delimiter: UInt8) -> [Record] {
        var records: [Record] = []
        var cells: [Cell] = []
        var i = 0
        let quote = UInt8(ascii: "\"")
        while i <= b.count {
            // Un campo empieza en `i`.
            let start = i
            var value: [UInt8] = []
            var quoted = false
            if i < b.count, b[i] == quote {
                quoted = true
                i += 1
                while i < b.count {
                    if b[i] == quote {
                        if i + 1 < b.count, b[i + 1] == quote { value.append(quote); i += 2; continue }
                        i += 1
                        break
                    }
                    value.append(b[i]); i += 1
                }
                // Lo que siga hasta el separador (no debería haber nada) se toma tal cual.
                while i < b.count, b[i] != delimiter, b[i] != 0x0A, b[i] != 0x0D { value.append(b[i]); i += 1 }
            } else {
                while i < b.count, b[i] != delimiter, b[i] != 0x0A, b[i] != 0x0D { value.append(b[i]); i += 1 }
            }
            cells.append(Cell(range: start..<i, value: String(decoding: value, as: UTF8.self), quoted: quoted))
            if i >= b.count {
                let rec = Record(cells: cells)
                if !(rec.isBlank && start == b.count) { records.append(rec) }
                break
            }
            if b[i] == delimiter { i += 1; continue }
            // Fin de registro.
            records.append(Record(cells: cells))
            cells = []
            if b[i] == 0x0D, i + 1 < b.count, b[i + 1] == 0x0A { i += 2 } else { i += 1 }
            if i == b.count { break }
        }
        return records
    }

    /// Texto de una celda nueva, con comillas si las tenía o si las necesita.
    static func encode(_ value: String, quoted: Bool, delimiter: Character) -> String {
        let needs = value.contains(delimiter) || value.contains("\"") || value.contains(where: \.isNewline)
            || value.hasPrefix(" ") || value.hasSuffix(" ")
        guard quoted || needs else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
