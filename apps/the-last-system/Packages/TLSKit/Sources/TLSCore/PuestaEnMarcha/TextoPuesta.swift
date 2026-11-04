import Foundation
import Yams

// F3 · rol motor. Cambios de texto puros para preparar lo que escribe cada paso: la vista previa enseña exactamente
// el texto que se escribirá (antes y después) y el plan lo escribe de una vez con compare-and-swap
// (`WriteOp.replaceText`). Ninguna función de aquí toca el disco.

enum TextoPuesta {
    static let pendiente = "PENDIENTE"

    /// Quita el BOM.
    static func limpio(_ s: String) -> String { s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }

    /// Texto de un fichero de la foto (sin BOM).
    static func texto(_ p: VaultPath, en foto: VaultSnapshot?) -> String? {
        guard let foto, let real = foto.existing(p), let t = foto.text(real) else { return nil }
        return limpio(t)
    }

    // MARK: Secciones `## …`

    static func esEncabezado(_ linea: Substring) -> (nivel: Int, titulo: String)? {
        var s = linea.drop(while: { $0 == " " })
        var n = 0
        while s.first == "#" { n += 1; s = s.dropFirst() }
        guard (1...6).contains(n), s.isEmpty || s.first == " " else { return nil }
        return (n, s.trimmingCharacters(in: .whitespaces))
    }

    /// Rango de líneas del contenido de la sección de nivel 2 llamada `titulo` (sin el encabezado).
    static func rangoDeSeccion(_ titulo: String, en lineas: [Substring]) -> (cabecera: Int, contenido: Range<Int>)? {
        let clave = TextFolding.fold(titulo)
        var valla = false
        var cabecera: Int?
        for (i, l) in lineas.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { valla.toggle(); continue }
            if valla { continue }
            guard let h = esEncabezado(l) else { continue }
            if let c = cabecera, h.nivel <= 2 { return (c, (c + 1)..<i) }
            if cabecera == nil, h.nivel == 2, TextFolding.fold(h.titulo) == clave { cabecera = i }
        }
        if let c = cabecera { return (c, (c + 1)..<lineas.count) }
        return nil
    }

    static func lineas(_ texto: String) -> [Substring] { texto.split(separator: "\n", omittingEmptySubsequences: false) }

    /// Contenido de una sección `## titulo`, sin líneas en blanco al principio ni al final y sin las guías.
    static func seccion(_ titulo: String, en texto: String) -> String? {
        let ls = lineas(texto)
        guard let r = rangoDeSeccion(titulo, en: ls) else { return nil }
        let contenido = ls[r.contenido].filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("> Guía") }
        return contenido.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sustituye el contenido de `## titulo` (también las guías). Si no existe, la añade al final del texto o justo
    /// antes de la sección `antesDe`.
    static func sustituirSeccion(_ titulo: String, por contenido: String, en texto: String,
                                 antesDe: String? = nil) -> String {
        var ls = lineas(texto).map(String.init)
        let cuerpo = contenido.trimmingCharacters(in: .newlines)
        if let r = rangoDeSeccion(titulo, en: ls.map { Substring($0) }) {
            // Se conserva la línea en blanco que separaba de la sección siguiente.
            let hayMas = r.contenido.upperBound < ls.count
            var nuevo = [""] + (cuerpo.isEmpty ? [] : cuerpo.components(separatedBy: "\n"))
            if hayMas { nuevo.append("") }
            ls.replaceSubrange(r.contenido, with: nuevo)
            return ls.joined(separator: "\n")
        }
        let bloque = ["## \(titulo)", ""] + (cuerpo.isEmpty ? [] : cuerpo.components(separatedBy: "\n"))
        if let antesDe, let r = rangoDeSeccion(antesDe, en: ls.map { Substring($0) }) {
            ls.insert(contentsOf: bloque + [""], at: r.cabecera)
            return ls.joined(separator: "\n")
        }
        var t = texto
        while t.hasSuffix("\n\n") { t.removeLast() }
        if !t.isEmpty, !t.hasSuffix("\n") { t += "\n" }
        if !t.isEmpty { t += "\n" }
        return t + bloque.joined(separator: "\n") + "\n"
    }

    /// Añade una línea al final de `## titulo` (crea la sección al final si no está). No repite una línea que ya esté.
    static func anadirLinea(_ linea: String, aSeccion titulo: String, en texto: String) -> String {
        let actual = seccion(titulo, en: texto) ?? ""
        if actual.components(separatedBy: "\n").contains(linea) { return texto }
        var ls = lineas(texto).map(String.init)
        guard let r = rangoDeSeccion(titulo, en: ls.map { Substring($0) }) else {
            return sustituirSeccion(titulo, por: linea, en: texto)
        }
        // Tras la última línea con texto de la sección.
        var i = r.contenido.upperBound
        while i > r.contenido.lowerBound, ls[i - 1].trimmingCharacters(in: .whitespaces).isEmpty { i -= 1 }
        if i == r.contenido.lowerBound { ls.insert(contentsOf: ["", linea], at: i); return ls.joined(separator: "\n") }
        ls.insert(linea, at: i)
        return ls.joined(separator: "\n")
    }

    // MARK: Tablas

    static func celdas(_ fila: Substring) -> [String]? {
        let t = fila.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("|") else { return nil }
        var s = String(t.dropFirst())
        if s.hasSuffix("|") { s.removeLast() }
        var out: [String] = []
        var cur = ""
        var escapado = false
        for ch in s {
            if escapado { cur.append(ch); escapado = false; continue }
            if ch == "\\" { cur.append(ch); escapado = true; continue }
            if ch == "|" { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(ch)
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    static func esSeparador(_ c: [String]) -> Bool {
        !c.isEmpty && c.allSatisfy { $0.trimmingCharacters(in: CharacterSet(charactersIn: ":- ")).isEmpty && $0.contains("-") }
    }

    static func escapar(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: "\\|")
    }

    static func fila(_ c: [String]) -> String { "| " + c.joined(separator: " | ") + " |" }

    /// Primera tabla cuya cabecera tiene `columna` (dentro de `## seccion` si se da): índices de cabecera y filas.
    static func tabla(con columna: String, seccion: String?, en ls: [Substring]) -> (cabecera: Int, columnas: [String], filas: Range<Int>)? {
        var rango = 0..<ls.count
        if let seccion {
            guard let r = rangoDeSeccion(seccion, en: ls) else { return nil }
            rango = r.contenido
        }
        var i = rango.lowerBound
        while i + 1 < rango.upperBound {
            if let c = celdas(ls[i]), c.contains(where: { TextFolding.fold($0) == TextFolding.fold(columna) }),
               let sep = celdas(ls[i + 1]), esSeparador(sep) {
                var j = i + 2
                while j < rango.upperBound, celdas(ls[j]) != nil { j += 1 }
                return (i, c, (i + 2)..<j)
            }
            i += 1
        }
        return nil
    }

    /// Cambia celdas de la fila cuya `columnaClave` vale `valorClave` (sin distinguir tildes ni mayúsculas). Si la fila
    /// no existe y `crear` es `true`, la añade al final de la tabla. `nil` si no hay tabla.
    static func ponerCeldas(_ nuevas: [String: String], columnaClave: String, valorClave: String, seccion: String? = nil,
                            crear: Bool = false, en texto: String) -> String? {
        var ls = lineas(texto)
        guard let t = tabla(con: columnaClave, seccion: seccion, en: ls) else { return nil }
        let cols = t.columnas.map(TextFolding.fold)
        guard let k = cols.firstIndex(of: TextFolding.fold(columnaClave)) else { return nil }
        let clave = TextFolding.fold(LinkParser.plainText(valorClave))
        for i in t.filas {
            guard var c = celdas(ls[i]), c.count > k else { continue }
            guard TextFolding.fold(LinkParser.plainText(c[k])) == clave else { continue }
            while c.count < cols.count { c.append("") }
            var cambia = false
            for (col, v) in nuevas {
                guard let j = cols.firstIndex(of: TextFolding.fold(col)) else { continue }
                let e = escapar(v)
                if c[j] != e { c[j] = e; cambia = true }
            }
            if !cambia { return texto }
            ls[i] = Substring(fila(c))
            return ls.joined(separator: "\n")
        }
        guard crear else { return texto }
        var c = Array(repeating: "", count: cols.count)
        c[k] = escapar(valorClave)
        for (col, v) in nuevas { if let j = cols.firstIndex(of: TextFolding.fold(col)) { c[j] = escapar(v) } }
        // Una fila vacía de la plantilla (`| | | |`) se sustituye en vez de dejarla.
        if let vacia = t.filas.first(where: { celdas(ls[$0])?.allSatisfy(\.isEmpty) == true }) {
            ls[vacia] = Substring(fila(c))
        } else {
            ls.insert(Substring(fila(c)), at: t.filas.upperBound)
        }
        return ls.joined(separator: "\n")
    }

    /// Filas de la primera tabla con `columna` como diccionarios (claves tal cual en la cabecera).
    static func filas(con columna: String, seccion: String? = nil, en texto: String) -> [[String: String]] {
        let ls = lineas(texto)
        guard let t = tabla(con: columna, seccion: seccion, en: ls) else { return [] }
        return t.filas.compactMap { i in
            guard let c = celdas(ls[i]), !c.allSatisfy(\.isEmpty) else { return nil }
            var d: [String: String] = [:]
            for (n, col) in t.columnas.enumerated() { d[col] = n < c.count ? c[n] : "" }
            return d
        }
    }

    // MARK: Propiedades

    /// Pone propiedades (solo esas líneas) con `FrontmatterDocument`.
    static func ponerPropiedades(_ props: [Property], quitar: [String] = [], en texto: String) -> String {
        guard !props.isEmpty || !quitar.isEmpty else { return texto }
        var doc = FrontmatterDocument(text: texto)
        doc.merge(set: props, unset: quitar)
        return doc.text
    }

    static func propiedad(_ clave: String, en texto: String) -> String? {
        NoteDocument(text: texto).frontmatter.properties.first { $0.key == clave }?.value.displayText
            .trimmingCharacters(in: .whitespaces).nilSiVacio
    }

    // MARK: `.tls/config.yaml`

    /// Bloque de una clave de primer nivel (`agenda:` y sus líneas sangradas). Rango de líneas.
    static func bloqueYAML(_ clave: String, en ls: [Substring]) -> Range<Int>? {
        guard let i = ls.firstIndex(where: { $0.hasPrefix(clave + ":") }) else { return nil }
        var j = i + 1
        while j < ls.count {
            let l = ls[j]
            if let f = l.first, f != " ", f != "\t" { break }
            j += 1
        }
        // Sin las líneas en blanco del final.
        while j > i + 1, ls[j - 1].trimmingCharacters(in: .whitespaces).isEmpty { j -= 1 }
        return i..<j
    }

    /// Sustituye (o añade al final) el bloque de primer nivel `clave` por `bloque` (líneas ya sangradas, con la clave).
    static func ponerBloqueYAML(_ clave: String, _ bloque: [String], en texto: String) -> String {
        var ls = lineas(texto).map(String.init)
        if let r = bloqueYAML(clave, en: ls.map { Substring($0) }) {
            ls.replaceSubrange(r, with: bloque)
            return ls.joined(separator: "\n")
        }
        var t = texto
        if !t.isEmpty, !t.hasSuffix("\n") { t += "\n" }
        return t + bloque.joined(separator: "\n") + "\n"
    }

    /// Entradas de un bloque de mapa (`capacidades:`): código → sus líneas tal cual (se conservan las que no se tocan).
    static func entradasYAML(_ clave: String, en texto: String) -> [(clave: String, lineas: [String])] {
        let ls = lineas(texto)
        guard let r = bloqueYAML(clave, en: ls) else { return [] }
        let primera = ls[r.lowerBound]
        // `capacidades: {}` o `capacidades: {A: …}` en una línea: no se reparte por entradas.
        if primera.dropFirst(clave.count + 1).trimmingCharacters(in: .whitespaces).hasPrefix("{") { return [] }
        var out: [(String, [String])] = []
        for i in (r.lowerBound + 1)..<r.upperBound {
            let l = String(ls[i])
            let sangria = l.prefix(while: { $0 == " " }).count
            let t = l.trimmingCharacters(in: .whitespaces)
            if sangria == 2, !t.hasPrefix("#"), let dos = t.firstIndex(of: ":") {
                out.append((String(t[..<dos]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")), [l]))
            } else if !out.isEmpty {
                out[out.count - 1].1.append(l)
            }
        }
        return out
    }

    /// Valor escalar de primer nivel o anidado (`agenda.tope_horas_dia`) con Yams, como texto.
    static func valorYAML(_ ruta: [String], en texto: String) -> String? {
        guard let node = try? Yams.compose(yaml: texto, Resolver.basic) else { return nil }
        var cur: Node? = node
        for k in ruta { cur = cur?.mapping?[k] }
        return cur?.scalar?.string
    }

    /// `true` si el YAML se lee (lo comprueba la vista previa antes de proponer el cambio).
    static func yamlValido(_ texto: String) -> Bool {
        (try? Yams.compose(yaml: texto, Resolver.basic)) != nil
    }

    /// Texto YAML seguro para un escalar (entre comillas si hace falta).
    static func escalarYAML(_ s: String) -> String {
        let necesita = s.isEmpty || s.contains(where: { ":#{}[],&*!|>'\"%@`".contains($0) }) || s.first == " "
            || s.last == " " || ["si", "no", "true", "false", "yes", "null", "~"].contains(s.lowercased())
        guard necesita else { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
