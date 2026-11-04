// Procedencia: lectura de H1, línea de resumen y secciones `##` inspirada en
// `parseSystem` (FORK/server/internal/biz/library.go, autor: Manuel Trigo), portada a Swift.

import Foundation

/// Lee `N · Área/Área.md`:
///
/// ```
/// # Ventas
/// **Estado:** preparada, sin activar · **La lleva:** … · **Rol:** …
/// ## Qué transforma
/// Primer párrafo.
/// ## Sistemas
/// - [Embudo](Sistemas/Embudo.md): seguimiento de cada conversación.
/// ```
///
/// Si falta algo, el área se muestra igual con estado «desconocido».
public enum AreaReader {
    public static let fileName = "Área.md"

    public static func parse(markdown: String, code: AreaCode, folder: VaultPath,
                             resolve: (String) -> VaultPath?) -> AreaSummary {
        let doc = NoteDocument(text: markdown)
        let fm = doc.frontmatter
        let titulo = doc.heading ?? fm.text("name").flatMap(nonEmpty) ?? defaultTitle(code: code, folder: folder)
        var estadoTexto = ""
        var lleva: String?
        var rol: String?
        for line in doc.body.lines where line.contains("**Estado") {
            let fields = labeledFields(String(line))
            estadoTexto = fields.first { $0.label == "estado" }?.value ?? ""
            lleva = fields.first { $0.label.hasPrefix("la lleva") || $0.label.hasPrefix("lo lleva") || $0.label.hasPrefix("llevan") || $0.label.hasPrefix("lleva") }?.value
            rol = fields.first { $0.label == "rol" }?.value
            break
        }
        let sections = sections(of: doc.body)
        var transforma = sections.first { TextFolding.fold($0.heading).hasPrefix("que transforma") }
            .flatMap { firstParagraph($0.lines) }
            .map(LinkParser.plainText)
        // v2 (SISTEMAS §2.3): el estado se lee de la propiedad y, si no coincide con el texto, manda ella.
        if let e = fm.text("estado").flatMap(nonEmpty) { estadoTexto = e }
        if lleva.flatMap(nonEmpty) == nil, let o = fm.text("ocupante").flatMap(nonEmpty) { lleva = LinkParser.plainText(o) }
        if rol.flatMap(nonEmpty) == nil, let r = fm.text("rol").flatMap(nonEmpty) { rol = LinkParser.plainText(r) }
        if transforma.flatMap(nonEmpty) == nil, let c = fm.text("convierte").flatMap(nonEmpty) { transforma = c }
        let sistemasLines = sections.first { TextFolding.fold($0.heading).hasPrefix("sistemas") }?.lines ?? []
        let sistemas = systemRefs(sistemasLines, resolve: resolve) + tableSystemRefs(sistemasLines, resolve: resolve)
        return AreaSummary(code: code, folder: folder, titulo: titulo, estado: status(estadoTexto),
                           estadoTexto: estadoTexto, lleva: lleva.flatMap(nonEmpty), rol: rol.flatMap(nonEmpty),
                           transforma: transforma.flatMap(nonEmpty), sistemas: sistemas, tieneFicha: true)
    }

    /// Área sin `Área.md` (p. ej. la demo antigua): se muestra con estado desconocido.
    public static func missing(code: AreaCode, folder: VaultPath) -> AreaSummary {
        AreaSummary(code: code, folder: folder, titulo: defaultTitle(code: code, folder: folder), estado: .desconocido,
                    estadoTexto: "", lleva: nil, rol: nil, transforma: nil, sistemas: [], tieneFicha: false)
    }

    /// «activa…» → activa; «preparada…» → preparada; «en reposo…»/«reposo…» → reposo.
    public static func status(_ text: String) -> AreaStatus {
        let t = TextFolding.fold(text.trimmingCharacters(in: .whitespaces))
        if t.hasPrefix("activa") { return .activa }
        if t.hasPrefix("preparada") { return .preparada }
        if t.hasPrefix("en reposo") || t.hasPrefix("reposo") { return .reposo }
        return .desconocido
    }

    static func defaultTitle(code: AreaCode, folder: VaultPath) -> String {
        let name = folder.name
        if VaultLayout.areaNumber(ofFolder: name) != nil {
            return String(name.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? code.nombre : name
    }

    static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// `**Etiqueta:** valor · **Otra:** valor` → [(etiqueta en minúsculas, valor)].
    static func labeledFields(_ line: String) -> [(label: String, value: String)] {
        // Posiciones de cada `**…**` cuya etiqueta termina en «:» (dentro o fuera).
        var marks: [(label: String, start: String.Index, valueStart: String.Index)] = []
        var search = line.startIndex
        while let open = line.range(of: "**", range: search..<line.endIndex),
              let close = line.range(of: "**", range: open.upperBound..<line.endIndex) {
            var inner = String(line[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
            var valueStart = close.upperBound
            var isLabel = false
            if inner.hasSuffix(":") {
                inner.removeLast(); isLabel = true
            } else if valueStart < line.endIndex, line[valueStart] == ":" {
                valueStart = line.index(after: valueStart); isLabel = true
            }
            if isLabel {
                marks.append((inner.lowercased().trimmingCharacters(in: .whitespaces), open.lowerBound, valueStart))
            }
            search = close.upperBound
        }
        var out: [(String, String)] = []
        for (i, m) in marks.enumerated() {
            let end = i + 1 < marks.count ? marks[i + 1].start : line.endIndex
            var value = String(line[m.valueStart..<end]).trimmingCharacters(in: .whitespaces)
            // Separador « · » entre campos.
            while value.hasSuffix("·") { value.removeLast(); value = value.trimmingCharacters(in: .whitespaces) }
            out.append((m.label, value))
        }
        return out
    }

    struct Section { let heading: String; let lines: [String] }

    /// Secciones `## …` del cuerpo (sin bloques de código).
    static func sections(of body: String) -> [Section] {
        var out: [Section] = []
        var heading: String?
        var lines: [String] = []
        for raw in body.lines {
            let line = String(raw)
            if line.hasPrefix("## ") {
                if let h = heading { out.append(Section(heading: h, lines: lines)) }
                heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                lines = []
            } else if line.hasPrefix("# ") {
                if let h = heading { out.append(Section(heading: h, lines: lines)) }
                heading = nil; lines = []
            } else if heading != nil {
                lines.append(line)
            }
        }
        if let h = heading { out.append(Section(heading: h, lines: lines)) }
        return out
    }

    static func firstParagraph(_ lines: [String]) -> String? {
        var para: [String] = []
        for l in lines {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty {
                if para.isEmpty { continue } else { break }
            }
            if t.hasPrefix("#") { break }
            para.append(t)
        }
        return para.isEmpty ? nil : para.joined(separator: " ")
    }

    /// Elementos de lista de primer nivel: el primer enlace es el sistema y el resto, su resumen.
    static func systemRefs(_ lines: [String], resolve: (String) -> VaultPath?) -> [SystemRef] {
        var out: [SystemRef] = []
        for line in lines {
            guard let item = listItemText(line) else { continue }
            let links = LinkParser.links(in: item).filter { !$0.isExternal }
            guard let first = links.first, let r = item.range(of: first.raw) else {
                let nombre = item.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
                if !nombre.isEmpty { out.append(SystemRef(nombre: nombre, path: nil, resumen: nil)) }
                continue
            }
            let nombre = (first.label ?? first.target).replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespaces)
            var rest = String(item[r.upperBound...])
            rest = String(rest.drop(while: { $0 == ":" || $0 == "," || $0 == " " || $0 == "—" || $0 == "–" || $0 == "-" }))
            let resumen = LinkParser.plainText(rest).trimmingCharacters(in: .whitespaces)
            out.append(SystemRef(nombre: nombre.isEmpty ? first.target : nombre,
                                 path: resolve(first.resolvable),
                                 resumen: resumen.isEmpty || resumen == "." ? nil : resumen))
        }
        return out
    }

    /// Filas de la tabla de `## Sistemas` de la plantilla v2 (`| Código | Sistema | Estado |`):
    /// el primer enlace de la fila es el sistema; sin enlace, el texto de la columna «Sistema».
    static func tableSystemRefs(_ lines: [String], resolve: (String) -> VaultPath?) -> [SystemRef] {
        var out: [SystemRef] = []
        var header: [String]?
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("|") else { header = nil; continue }
            var cells = t.split(separator: "|", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if cells.first == "" { cells.removeFirst() }
            if cells.last == "" { cells.removeLast() }
            guard let h = header else { header = cells.map { TextFolding.fold($0) }; continue }
            // Separador `|---|---|`.
            if cells.allSatisfy({ $0.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " } }) { continue }
            let col = h.firstIndex(of: "sistema")
            let linked = cells.lazy.compactMap { cell in LinkParser.links(in: cell).first { !$0.isExternal } }.first
            if let link = linked {
                let nombre = (link.label ?? link.target).replacingOccurrences(of: "**", with: "")
                    .trimmingCharacters(in: .whitespaces)
                out.append(SystemRef(nombre: nombre.isEmpty ? link.target : nombre, path: resolve(link.resolvable), resumen: nil))
            } else if let c = col, c < cells.count, let nombre = nonEmpty(cells[c].replacingOccurrences(of: "**", with: "")) {
                out.append(SystemRef(nombre: nombre, path: nil, resumen: nil))
            }
        }
        return out
    }

    /// Texto de un elemento de lista sin sangría (`- `, `* `, `+ `, `1. `).
    static func listItemText(_ line: String) -> String? {
        guard let first = line.first, first != " ", first != "\t" else { return nil }
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        }
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
