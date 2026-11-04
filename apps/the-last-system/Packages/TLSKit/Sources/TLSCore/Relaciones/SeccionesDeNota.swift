import Foundation

extension MarkdownSections {
    /// Títulos de las secciones de un nivel (`##` = 2), en orden y sin repetir. El `#` del título de la nota no
    /// es una sección de las fichas (su contenido sería la nota entera).
    public static func titles(in body: String, level: Int) -> [String] {
        var vistos = Set<String>()
        return sections(TextLines.split(body)).filter { $0.level == level }.map(\.title)
            .filter { vistos.insert(TextFolding.fold($0)).inserted }
    }
}

/// Una tabla Markdown (`| a | b |` con su fila `|---|---|`) leída para enseñarla como tabla.
public struct TablaMarkdown: Sendable, Hashable {
    public let cabecera: [String]
    public let filas: [[String]]

    /// Lee las líneas de una tabla. `nil` si no lo es (menos de dos líneas o sin la fila de separación).
    public static func leer(_ lineas: [String]) -> TablaMarkdown? {
        let ls = lineas.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("|") }
        guard ls.count >= 2, esSeparacion(ls[1]) else { return nil }
        let cabecera = celdas(ls[0])
        let filas = ls.dropFirst(2).filter { !esSeparacion($0) }.map(celdas)
        return TablaMarkdown(cabecera: cabecera, filas: filas)
    }

    public init(cabecera: [String], filas: [[String]]) {
        self.cabecera = cabecera; self.filas = filas
    }

    static func esSeparacion(_ l: String) -> Bool {
        let resto = l.replacingOccurrences(of: "|", with: "")
        return !resto.isEmpty && resto.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    /// Celdas de una fila, sin los `|` de los lados (respeta `\|` dentro de una celda).
    static func celdas(_ fila: String) -> [String] {
        var s = Substring(fila.trimmingCharacters(in: .whitespaces))
        if s.hasPrefix("|") { s = s.dropFirst() }
        if s.hasSuffix("|"), !s.hasSuffix("\\|") { s = s.dropLast() }
        var out: [String] = []
        var actual = ""
        var escape = false
        for c in s {
            if escape { actual.append(c); escape = false; continue }
            if c == "\\" { escape = true; actual.append(c); continue }
            if c == "|" { out.append(actual.trimmingCharacters(in: .whitespaces)); actual = ""; continue }
            actual.append(c)
        }
        out.append(actual.trimmingCharacters(in: .whitespaces))
        return out.map { $0.replacingOccurrences(of: "\\|", with: "|") }
    }

    /// `**Total**` → («Total», negrita).
    public static func sinNegrita(_ celda: String) -> (texto: String, negrita: Bool) {
        let t = celda.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("**"), t.hasSuffix("**"), t.count > 4 {
            return (String(t.dropFirst(2).dropLast(2)), true)
        }
        return (t, false)
    }
}
