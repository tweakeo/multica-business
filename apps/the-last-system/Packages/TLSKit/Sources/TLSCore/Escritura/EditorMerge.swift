import Foundation

/// Fusión a tres bandas del guardado de una persona: lo que abrió (`base`), lo que escribió
/// (`mine`) y lo que hay ahora en disco (`theirs`).
///
/// Se fusiona sin aviso solo si lo que cambió fuera son propiedades (por clave: las que tú no
/// tocaste) o un añadido al final de la Actividad (como el que deja un asistente). Cualquier otro
/// cambio de fuera en el cuerpo es un conflicto: no se escribe nada y se guardan las dos versiones.
enum EditorMerge {
    enum Result: Equatable {
        case merged(String)
        case conflict
    }

    static func merge(base: String, mine: String, theirs: String) -> Result {
        if mine == base { return .merged(theirs) }
        if theirs == base || theirs == mine { return .merged(mine) }
        let b = FrontmatterDocument(text: base)
        let m = FrontmatterDocument(text: mine)
        let t = FrontmatterDocument(text: theirs)
        guard let front = mergeFrontmatter(base: b, mine: m, theirs: t),
              let body = mergeBody(base: b.body, mine: m.body, theirs: t.body) else { return .conflict }
        var result = front
        result.replaceBody(body)
        return .merged(result.text)
    }

    // MARK: Propiedades

    /// `theirs` con los cambios de clave de `mine` encima. `nil` si una clave cambió distinto en los dos.
    static func mergeFrontmatter(base b: FrontmatterDocument, mine m: FrontmatterDocument,
                                 theirs t: FrontmatterDocument) -> FrontmatterDocument? {
        if m.frontmatterBlock == b.frontmatterBlock { return t }
        if t.frontmatterBlock == b.frontmatterBlock || t.frontmatterBlock == m.frontmatterBlock {
            var out = t
            out.replaceFrontmatter(from: m)
            return out
        }
        // Comentarios u otras líneas sueltas cambiados por ti mientras cambiaban fuera: no se adivina.
        if m.triviaLines() != b.triviaLines() { return nil }
        var out = t
        var previous: String?
        let mineKeys = m.keys
        for k in Array(Set(mineKeys + b.keys)).sorted(by: { (mineKeys.firstIndex(of: $0) ?? .max) < (mineKeys.firstIndex(of: $1) ?? .max) }) {
            let mRaw = m.rawLines(k), bRaw = b.rawLines(k), tRaw = t.rawLines(k)
            defer { if mRaw != nil { previous = k } }
            if mRaw == bRaw { continue }
            guard tRaw == bRaw || tRaw == mRaw else { return nil }
            if let mRaw {
                out.setRawLines(k, raw: mRaw, after: previous)
            } else {
                out.unset(k)
            }
        }
        return out
    }

    // MARK: Cuerpo

    struct Chunk {
        /// Clave de la sección: título plegado y aparición (o «» para lo que va antes del primer título).
        var key: String
        var text: String
    }

    /// Trozos del cuerpo partidos por los títulos de nivel 1 y 2 (fuera de bloques de código).
    static func chunks(_ body: String) -> [Chunk] {
        let lines = TextLines.split(body)
        var starts: [Int] = []
        var fence: CodeFence?
        for (i, l) in lines.enumerated() {
            let trimmed = l.content.drop(while: { $0 == " " })
            if let f = fence { if f.closes(trimmed) { fence = nil }; continue }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            if let h = MarkdownSections.heading(l.content), h.level <= 2 { starts.append(i) }
        }
        var out: [Chunk] = []
        var seen: [String: Int] = [:]
        let bounds = [0] + starts.filter { $0 > 0 }
        for (n, start) in bounds.enumerated() {
            let end = n + 1 < bounds.count ? bounds[n + 1] : lines.count
            let slice = Array(lines[start..<end])
            var key = ""
            if let first = slice.first, let h = MarkdownSections.heading(first.content), h.level <= 2 {
                let base = "\(h.level)#" + TextFolding.fold(h.title)
                let count = seen[base, default: 0]
                seen[base] = count + 1
                key = base + "#\(count)"
            }
            out.append(Chunk(key: key, text: TextLines.join(slice)))
        }
        if out.isEmpty { out.append(Chunk(key: "", text: "")) }
        return out
    }

    /// Texto sin las líneas en blanco del final, y esas líneas.
    static func splitTrailingBlank(_ text: String) -> (core: String, trail: String) {
        let lines = TextLines.split(text)
        guard let last = lines.lastIndex(where: { !$0.isBlank }) else { return ("", text) }
        return (TextLines.join(Array(lines[...last])), TextLines.join(Array(lines[(last + 1)...])))
    }

    static func isActividad(_ key: String) -> Bool {
        key.hasPrefix("2#actividad#") || key.hasPrefix("1#actividad#")
    }

    static func mergeBody(base: String, mine: String, theirs: String) -> String? {
        if theirs == base || theirs == mine { return mine }
        if mine == base { return theirs }
        // Fuera cambió el cuerpo: solo vale si fue añadir a la Actividad.
        let b = chunks(base), m = chunks(mine), t = chunks(theirs)
        let bk = b.map(\.key)
        // Las secciones de la base siguen en los dos lados y en el mismo orden; fuera solo puede
        // añadir al final una sección de Actividad.
        guard m.count >= b.count, t.count >= b.count, Array(m.prefix(b.count).map(\.key)) == bk,
              Array(t.prefix(b.count).map(\.key)) == bk else { return nil }
        let extraT = t.dropFirst(b.count)
        guard extraT.allSatisfy({ isActividad($0.key) }) else { return nil }
        var out: [String] = []
        for i in b.indices {
            let bc = splitTrailingBlank(b[i].text).core
            let tc = splitTrailingBlank(t[i].text).core
            if tc == bc {
                out.append(m[i].text)
                continue
            }
            guard isActividad(b[i].key), tc.hasPrefix(bc),
                  let merged = mergeChunk(base: b[i].text, mine: m[i].text, theirs: t[i].text) else { return nil }
            out.append(merged)
        }
        let extraM = m.dropFirst(b.count).map(\.text)
        // Lo añadido fuera (Actividad nueva) va antes que las secciones nuevas tuyas.
        for extra in extraT.map(\.text) + extraM {
            if let last = out.last, !last.isEmpty {
                let (core, trail) = splitTrailingBlank(last)
                if trail.isEmpty {
                    let eol = TextLines.dominantEOL(core)
                    out[out.count - 1] = (core.last.map(TextLines.isEOL) == true ? core : core + eol) + eol
                }
            }
            out.append(extra)
        }
        return out.joined()
    }

    /// Un trozo: si cambió en un solo lado, ese; si en los dos, solo si ambos añadieron al final.
    static func mergeChunk(base: String, mine: String, theirs: String) -> String? {
        let bc = splitTrailingBlank(base).core
        let mc = splitTrailingBlank(mine).core
        let tc = splitTrailingBlank(theirs).core
        if tc == bc || tc == mc { return mine }
        if mc == bc { return theirs }
        // Los dos añadieron al final (la Actividad): lo de fuera primero y después lo tuyo.
        guard mc.hasPrefix(bc), tc.hasPrefix(bc) else { return nil }
        let eol = TextLines.dominantEOL(base.isEmpty ? mine : base)
        var tAdd = String(tc.dropFirst(bc.count))
        if tAdd.last.map(TextLines.isEOL) != true { tAdd += eol }
        let mAdd = String(mc.dropFirst(bc.count))
        return bc + tAdd + mAdd + splitTrailingBlank(mine).trail
    }
}

extension FrontmatterDocument {
    /// Líneas del bloque que no pertenecen a ninguna clave (comentarios, líneas en blanco).
    func triviaLines() -> [String] {
        guard let yaml = frontmatterText else { return [] }
        let all = TextLines.split(yaml)
        var owned = Set<Int>()
        for e in entries() { owned.formUnion(e.range) }
        return all.indices.filter { !owned.contains($0) }.map { all[$0].content }
    }

    /// Toma el bloque de propiedades de otra nota, tal cual.
    mutating func replaceFrontmatter(from other: FrontmatterDocument) {
        let body = self.body
        self = FrontmatterDocument(text: (bom ? "\u{FEFF}" : "") + other.frontmatterBlock + body)
    }
}
