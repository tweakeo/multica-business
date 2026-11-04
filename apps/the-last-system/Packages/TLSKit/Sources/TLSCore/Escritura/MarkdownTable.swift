import Foundation

/// Qué tabla de una nota: la primera (o la `indice`-ésima) que cumpla las condiciones.
public struct TableSelector: Sendable, Hashable, Codable {
    /// Solo tablas dentro de esta sección (`## Viaje`).
    public var seccion: String?
    /// Solo tablas con esta columna en la cabecera (`Código`).
    public var columna: String?
    /// Entre las que cumplen, cuál (0 = la primera).
    public var indice: Int

    public init(seccion: String? = nil, columna: String? = nil, indice: Int = 0) {
        self.seccion = seccion; self.columna = columna; self.indice = indice
    }
}

/// Tablas Markdown con barras (`| a | b |`) dentro de una nota.
///
/// Cambiar celdas solo reescribe esas celdas (conservando el relleno y la alineación de
/// la fila); añadir una fila copia el estilo de la cabecera. El resto de la nota no se toca.
public enum MarkdownTable {
    struct Located {
        var headerLine: Int
        var delimiterLine: Int
        /// Filas de datos (índices de línea).
        var rows: Range<Int>
        var header: [String]
    }

    /// Celdas de una fila: texto sin barras, con su relleno original.
    struct Row {
        var leadingPipe: Bool
        var trailingPipe: Bool
        /// Celdas tal cual (con espacios).
        var cells: [String]
        /// Lo que va tras la última barra (espacios).
        var tail: String
        /// Sangría antes de la primera barra.
        var indent: String

        func render() -> String {
            var s = indent
            if leadingPipe { s += "|" }
            s += cells.joined(separator: "|")
            if trailingPipe { s += "|" }
            return s + tail
        }
    }

    /// Separa una fila por barras no escapadas (`\|` no separa) y fuera de código.
    static func parseRow(_ line: String) -> Row? {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var rest = Substring(line.dropFirst(indent.count))
        var tail = ""
        while let last = rest.last, last == " " || last == "\t" { tail = String(last) + tail; rest = rest.dropLast() }
        guard rest.contains("|") else { return nil }
        let leading = rest.first == "|"
        if leading { rest = rest.dropFirst() }
        var cells: [String] = []
        var current = ""
        var inCode = false
        var endedWithPipe = false
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            endedWithPipe = false
            let next = rest.index(after: i)
            if c == "\\", next < rest.endIndex {
                current.append(c); current.append(rest[next])
                i = rest.index(after: next); continue
            }
            if c == "`" { inCode.toggle() }
            if c == "|", !inCode {
                cells.append(current); current = ""; endedWithPipe = true
            } else {
                current.append(c)
            }
            i = next
        }
        if !endedWithPipe { cells.append(current) }
        guard !cells.isEmpty else { return nil }
        return Row(leadingPipe: leading, trailingPipe: endedWithPipe, cells: cells, tail: tail, indent: indent)
    }

    static func isDelimiterRow(_ line: String) -> Bool {
        guard let row = parseRow(line), !row.cells.isEmpty else { return false }
        return row.cells.allSatisfy { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            return t.range(of: #"^:?-+:?$"#, options: .regularExpression) != nil
        }
    }

    static func cellText(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|")
    }

    /// Tablas del texto (fuera de bloques de código).
    static func tables(_ lines: [TextLine]) -> [Located] {
        var out: [Located] = []
        var fence: CodeFence?
        var i = 0
        while i < lines.count {
            let trimmed = lines[i].content.drop(while: { $0 == " " })
            if let f = fence {
                if f.closes(trimmed) { fence = nil }
                i += 1; continue
            }
            if let f = CodeFence.opening(trimmed) { fence = f; i += 1; continue }
            if i + 1 < lines.count, let head = parseRow(lines[i].content), isDelimiterRow(lines[i + 1].content) {
                var j = i + 2
                while j < lines.count, !lines[j].isBlank, parseRow(lines[j].content) != nil { j += 1 }
                out.append(Located(headerLine: i, delimiterLine: i + 1, rows: (i + 2)..<j,
                                   header: head.cells.map(cellText)))
                i = j
                continue
            }
            i += 1
        }
        return out
    }

    static func locate(_ selector: TableSelector, in lines: [TextLine]) -> Located? {
        var candidates = tables(lines)
        if let name = selector.seccion {
            guard let s = MarkdownSections.find(name, in: lines) else { return nil }
            candidates = candidates.filter { s.contentLines.contains($0.headerLine) }
        }
        if let col = selector.columna {
            let key = TextFolding.fold(col)
            candidates = candidates.filter { $0.header.contains { TextFolding.fold($0) == key } }
        }
        guard selector.indice >= 0, selector.indice < candidates.count else { return nil }
        return candidates[selector.indice]
    }

    static func column(_ name: String, in header: [String]) -> Int? {
        if let exact = header.firstIndex(where: { $0 == name }) { return exact }
        let key = TextFolding.fold(name)
        return header.firstIndex { TextFolding.fold($0) == key }
    }

    /// Filas de una tabla como diccionarios (cabecera → texto).
    public static func rows(in text: String, selector: TableSelector = TableSelector()) -> [[String: String]]? {
        let lines = TextLines.split(text)
        guard let t = locate(selector, in: lines) else { return nil }
        return t.rows.compactMap { i in
            guard let r = parseRow(lines[i].content) else { return nil }
            var d: [String: String] = [:]
            for (n, h) in t.header.enumerated() where n < r.cells.count { d[h] = cellText(r.cells[n]) }
            return d
        }
    }

    /// Escribe `value` en una celda conservando su relleno (y el ancho, si cabe).
    static func replaceCell(_ raw: String, with value: String) -> String {
        let escaped = escape(value)
        if raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let cell = " " + escaped + " "
            return cell.count < raw.count ? cell + String(repeating: " ", count: raw.count - cell.count) : cell
        }
        let leading = String(raw.prefix(while: { $0 == " " || $0 == "\t" }))
        var cell = leading + escaped
        if let last = raw.last, last == " " || last == "\t" {
            cell += String(repeating: " ", count: max(1, raw.count - cell.count))
        }
        return cell
    }

    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Cambia celdas de la fila cuya columna `keyColumn` vale `keyValue`.
    static func setCells(in text: String, selector: TableSelector, keyColumn: String, keyValue: String,
                         cells: [String: String], protectManual: Bool) throws -> String {
        var lines = TextLines.split(text)
        guard let t = locate(selector, in: lines) else { throw WriteError.tablaNoEncontrada }
        guard let keyIdx = column(keyColumn, in: t.header) else { throw WriteError.columnaDesconocida(keyColumn) }
        let matches = t.rows.filter { i in
            guard let r = parseRow(lines[i].content), keyIdx < r.cells.count else { return false }
            return cellText(r.cells[keyIdx]) == keyValue
        }
        guard let lineIndex = matches.first else { throw WriteError.filaNoEncontrada(keyValue) }
        guard matches.count == 1 else { throw WriteError.claveDuplicada(keyValue) }
        guard var row = parseRow(lines[lineIndex].content) else { throw WriteError.filaNoEncontrada(keyValue) }
        if protectManual, isManual(row: row, header: t.header) { throw WriteError.filaManual(keyValue) }
        var changed = false
        for (name, value) in cells.sorted(by: { $0.key < $1.key }) {
            guard let idx = column(name, in: t.header) else { throw WriteError.columnaDesconocida(name) }
            while row.cells.count <= idx { row.cells.append(" ") }
            if cellText(row.cells[idx]) == value { continue }
            row.cells[idx] = replaceCell(row.cells[idx], with: value)
            changed = true
        }
        guard changed else { return text }
        lines[lineIndex].content = row.render()
        return TextLines.join(lines)
    }

    /// Añade una fila al final de la tabla con el estilo de la cabecera.
    static func appendRow(in text: String, selector: TableSelector, cells: [String: String], eol: String) throws -> String {
        var lines = TextLines.split(text)
        guard let t = locate(selector, in: lines), let head = parseRow(lines[t.headerLine].content) else {
            throw WriteError.tablaNoEncontrada
        }
        for name in cells.keys where column(name, in: t.header) == nil { throw WriteError.columnaDesconocida(name) }
        var values = Array(repeating: "", count: t.header.count)
        for (name, value) in cells { if let i = column(name, in: t.header) { values[i] = value } }
        let row = Row(leadingPipe: head.leadingPipe, trailingPipe: head.trailingPipe,
                      cells: values.map { " " + escape($0) + " " },
                      tail: "", indent: head.indent)
        let last = t.rows.isEmpty ? t.delimiterLine : t.rows.upperBound - 1
        if lines[last].eol.isEmpty { lines[last].eol = eol }
        let isEnd = last == lines.count - 1
        lines.insert(TextLine(content: row.render(), eol: isEnd && text.last.map(TextLines.isEOL) != true ? "" : eol), at: last + 1)
        return TextLines.join(lines)
    }

    /// Fila escrita a mano (`Fuente` u `Origen` = manual): los procesos automáticos no la tocan.
    static func isManual(row: Row, header: [String]) -> Bool {
        for name in ["fuente", "origen"] {
            if let i = column(name, in: header), i < row.cells.count,
               TextFolding.fold(cellText(row.cells[i])) == "manual" { return true }
        }
        return false
    }
}
