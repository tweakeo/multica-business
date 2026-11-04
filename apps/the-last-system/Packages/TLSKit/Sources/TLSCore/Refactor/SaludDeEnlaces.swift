import Foundation

/// Un enlace que no apunta limpiamente a una nota (SISTEMAS.md §5.4).
public struct EnlaceRevisado: Sendable, Hashable {
    public enum Estado: Sendable, Hashable {
        /// La nota aún no existe (una «miga»): se ve en gris, sin alarma.
        case pendiente
        /// Hay varias notas con ese nombre y ninguna es la más cercana.
        case ambiguo([VaultPath])
        /// Ruta relativa rota que solo se encuentra por el nombre.
        case flojo(VaultPath)
    }

    public let origen: VaultPath
    public let linea: Int
    /// Enlace tal como está escrito.
    public let enlace: String
    /// Destino escrito.
    public let destino: String
    public let estado: Estado
}

/// El nombre de una nota escrito en otra sin enlazar.
public struct MencionSinEnlazar: Sendable, Hashable {
    public let origen: VaultPath
    public let linea: Int
    /// Bytes UTF-8 (sin BOM) del texto mencionado.
    public let rango: Range<Int>
    /// Texto tal como está escrito.
    public let texto: String
    public let destino: VaultPath
    /// La línea entera, para enseñarla.
    public let extracto: String
}

/// Salud de enlaces de la carpeta: enlaces sin resolver (consultables) y menciones sin enlazar.
public struct SaludDeEnlaces: Sendable {
    public enum Estilo: Sendable { case markdown, wiki }

    public let snapshot: VaultSnapshot
    private let resolver: LinkResolver
    private let names: [String: [VaultPath]]

    public init(snapshot: VaultSnapshot) {
        self.snapshot = snapshot
        self.resolver = snapshot.resolver
        var n: [String: [VaultPath]] = [:]
        for p in snapshot.files {
            n[TextFolding.nameKey(p.name), default: []].append(p)
            if WikiTarget.isNote(p) { n[TextFolding.nameKey(p.stem), default: []].append(p) }
        }
        self.names = n.mapValues { Array(Set($0)).sorted() }
    }

    /// Enlaces de toda la carpeta que no resuelven a una sola nota por su ruta (las plantillas no cuentan).
    public func revisar() -> [EnlaceRevisado] {
        snapshot.notes.filter { !VaultSnapshot.isTemplatePath($0) }.flatMap(revisar)
    }

    /// Los de una nota.
    public func revisar(_ nota: VaultPath) -> [EnlaceRevisado] {
        guard let text = snapshot.text(nota) else { return [] }
        var out: [EnlaceRevisado] = []
        for occ in LinkScanner.scan(text) {
            let link = occ.link
            if link.isExternal || link.target.isEmpty || link.target.contains("{{") { continue }
            let resolved = resolver.resolve(link.resolvable, from: nota)
            var estado: EnlaceRevisado.Estado?
            switch link.style {
            case .markdown:
                let strict = MarkdownDestination.strictTarget(link.target, from: nota, exists: { snapshot.existing($0) })
                if strict != nil, !snapshot.isDirectory(strict!) { continue }
                if let r = resolved { estado = .flojo(r) } else {
                    let decoded = link.target.removingPercentEncoding ?? link.target
                    let found = candidates(VaultPath(decoded).name)
                    estado = found.count > 1 ? .ambiguo(found) : .pendiente
                }
            case .wiki:
                if resolved != nil { continue }
                let found = candidates(VaultPath(link.target).name)
                estado = found.count > 1 ? .ambiguo(found) : .pendiente
            }
            if let estado {
                out.append(EnlaceRevisado(origen: nota, linea: occ.line, enlace: link.raw, destino: link.target, estado: estado))
            }
        }
        return out
    }

    private func candidates(_ name: String) -> [VaultPath] {
        let k = TextFolding.nameKey(name)
        if let f = names[k], !f.isEmpty { return f }
        return names[TextFolding.nameKey(VaultPath(name).stem)] ?? []
    }

    /// «Arreglar todos» los enlaces flojos: se reescriben con la ruta correcta. Un solo plan.
    public func arreglarFlojos(autor: Autor = .persona("Manu")) -> WritePlan? {
        var ops: [WriteOp] = []
        var total = 0
        for nota in snapshot.notes where !VaultSnapshot.isTemplatePath(nota) {
            guard let text = snapshot.text(nota), let data = snapshot.data(nota) else { continue }
            var edits: [TextEdit] = []
            for occ in LinkScanner.scan(text) where occ.link.style == .markdown && !occ.link.isExternal && !occ.link.target.isEmpty {
                let written = String(decoding: Array(text.utf8)[occ.targetRange], as: UTF8.self)
                guard MarkdownDestination.strictTarget(written, from: nota, exists: { snapshot.existing($0) }) == nil,
                      let r = resolver.resolve(occ.link.resolvable, from: nota) else { continue }
                let c = MarkdownDestination.rewrite(original: written, from: nota, to: r, angle: occ.angle)
                edits.append(TextEdit(offset: occ.targetRange.lowerBound, length: occ.targetRange.count,
                                      replacement: YAMLInline.escape(c, comillas: occ.comillas)))
            }
            if !edits.isEmpty {
                total += edits.count
                ops.append(.editRanges(nota, edits: edits, baseHash: ContentHash.of(data)))
            }
        }
        guard !ops.isEmpty else { return nil }
        return WritePlan(autor: autor, descripcion: "Arreglar " + Plural.de(total, "enlace", "enlaces"), ops: ops)
    }

    // MARK: Menciones

    /// Nombres con los que se puede mencionar una nota: su título, `nombre`, `titulo` y «Otros nombres».
    public func nombres(de nota: VaultPath) -> [String] {
        var out: [String] = []
        if let text = snapshot.text(nota) {
            let doc = NoteDocument(text: text)
            let fm = doc.frontmatter
            out.append(doc.title(fileStem: nota.stem))
            for k in ["nombre", "titulo", "título", "name", "title"] { if let v = fm.properties.first(where: { $0.key == k })?.value.displayText { out.append(v) } }
            for p in fm.properties where p.key == "aliases" || p.key == "alias" {
                switch p.value {
                case .list(let l): out += l
                case .text(let t): out.append(t)
                default: break
                }
            }
        }
        out.append(nota.stem)
        var seen = Set<String>()
        return out.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && !$0.contains("{{") && seen.insert(TextFolding.fold($0)).inserted }
    }

    /// Dónde se nombra `destino` sin enlazarlo (fuera de enlaces, código y propiedades).
    public func mencionesSinEnlazar(de destino: VaultPath) -> [MencionSinEnlazar] {
        let wanted = nombres(de: destino).sorted { $0.count > $1.count }
        guard !wanted.isEmpty else { return [] }
        var out: [MencionSinEnlazar] = []
        for nota in snapshot.notes where nota != destino && !VaultSnapshot.isTemplatePath(nota) {
            guard let text = snapshot.text(nota) else { continue }
            let bytes = Array(text.utf8)
            let ls = LinkScanner.lines(bytes)
            let bodyStart = LinkScanner.frontmatter(bytes, ls).map { $0.closing + 1 } ?? 0
            let blocked = LinkScanner.scan(text).map(\.range)
            var fence: CodeFence?
            for i in bodyStart..<max(bodyStart, ls.count) {
                let l = ls[i]
                let line = String(decoding: bytes[l.start..<l.end], as: UTF8.self)
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                if let f = fence { if f.closes(trimmed) { fence = nil }; continue }
                if let f = CodeFence.opening(trimmed) { fence = f; continue }
                let code = (codeSpans(line) + Self.noEnlazable(line)).map { ($0.lowerBound + l.start)..<($0.upperBound + l.start) }
                var taken: [Range<Int>] = []
                for name in wanted {
                    var search = line.startIndex..<line.endIndex
                    while let r = line.range(of: name, options: [.caseInsensitive, .diacriticInsensitive], range: search) {
                        search = r.upperBound..<line.endIndex
                        let before = r.lowerBound == line.startIndex ? nil : line[line.index(before: r.lowerBound)]
                        let after = r.upperBound == line.endIndex ? nil : line[r.upperBound]
                        if let c = before, c.isLetter || c.isNumber { continue }
                        if let c = after, c.isLetter || c.isNumber { continue }
                        let s = l.start + line.utf8.distance(from: line.startIndex, to: r.lowerBound)
                        let e = l.start + line.utf8.distance(from: line.startIndex, to: r.upperBound)
                        let range = s..<e
                        if (blocked + code + taken).contains(where: { $0.overlaps(range) }) { continue }
                        taken.append(range)
                        out.append(MencionSinEnlazar(origen: nota, linea: i + 1, rango: range, texto: String(line[r]),
                                                     destino: destino, extracto: line.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        }
        return out.sorted { ($0.origen, $0.rango.lowerBound) < ($1.origen, $1.rango.lowerBound) }
    }

    /// URL, autoenlaces `<…>` y etiquetas `#x` de una línea (desplazamientos UTF-8): un nombre
    /// dentro de ellos no es una mención (enlazarlo los rompería).
    static let noEnlazablePatron = try! NSRegularExpression(
        pattern: #"<[^<>\s]+>|(?:\b[A-Za-z][A-Za-z0-9+.\-]*://|\bwww\.|\bmailto:)[^\s<>]+|(?<![\p{L}\p{N}_&])#[\p{L}\p{N}_/\-]+"#)

    static func noEnlazable(_ line: String) -> [Range<Int>] {
        noEnlazablePatron.matches(in: line, range: NSRange(line.startIndex..., in: line)).compactMap { m in
            guard let r = Range(m.range, in: line) else { return nil }
            return line.utf8.distance(from: line.startIndex, to: r.lowerBound)..<line.utf8.distance(from: line.startIndex, to: r.upperBound)
        }
    }

    /// Fragmentos de código de una línea (desplazamientos UTF-8).
    private func codeSpans(_ line: String) -> [Range<Int>] {
        let b = Array(line.utf8)
        var out: [Range<Int>] = []
        var i = 0
        while i < b.count {
            guard b[i] == UInt8(ascii: "`") else { i += 1; continue }
            var n = 0
            while i + n < b.count, b[i + n] == UInt8(ascii: "`") { n += 1 }
            var j = i + n
            var end: Int?
            while j < b.count {
                if b[j] == UInt8(ascii: "`") {
                    var m = 0
                    while j + m < b.count, b[j + m] == UInt8(ascii: "`") { m += 1 }
                    if m == n { end = j + m; break }
                    j += m
                } else { j += 1 }
            }
            if let end { out.append(i..<end); i = end } else { i += n }
        }
        return out
    }

    /// Convierte menciones en enlaces conservando el texto (cuerpo: estilo G3, Markdown relativo).
    public func enlazar(_ menciones: [MencionSinEnlazar], estilo: Estilo = .markdown,
                        autor: Autor = .persona("Manu")) -> WritePlan? {
        var porNota: [VaultPath: [MencionSinEnlazar]] = [:]
        for m in menciones { porNota[m.origen, default: []].append(m) }
        var ops: [WriteOp] = []
        for (nota, lista) in porNota.sorted(by: { $0.key < $1.key }) {
            guard let data = snapshot.data(nota) else { continue }
            var edits: [TextEdit] = []
            var used: [Range<Int>] = []
            for m in lista.sorted(by: { $0.rango.lowerBound < $1.rango.lowerBound }) where !used.contains(where: { $0.overlaps(m.rango) }) {
                used.append(m.rango)
                let texto = m.texto.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
                let link: String
                switch estilo {
                case .markdown:
                    let rel = MarkdownDestination.relativeComponents(from: nota, to: m.destino)
                        .map { MarkdownDestination.encode($0, style: .init()) }.joined(separator: "/")
                    link = "[\(texto)](\(rel))"
                case .wiki:
                    let unique = (names[TextFolding.nameKey(m.destino.stem)] ?? []).count <= 1
                    let target = unique ? m.destino.stem : String(m.destino.raw.dropLast(m.destino.ext.isEmpty ? 0 : m.destino.ext.count + 1))
                    link = texto == target ? "[[\(target)]]" : "[[\(target)|\(texto.replacingOccurrences(of: "|", with: "/"))]]"
                }
                edits.append(TextEdit(offset: m.rango.lowerBound, length: m.rango.count, replacement: link))
            }
            if !edits.isEmpty { ops.append(.editRanges(nota, edits: edits, baseHash: ContentHash.of(data))) }
        }
        guard !ops.isEmpty else { return nil }
        let n = ops.reduce(0) { if case .editRanges(_, let e, _) = $1 { return $0 + e.count }; return $0 }
        return WritePlan(autor: autor, descripcion: "Enlazar " + Plural.de(n, "mención", "menciones"), ops: ops)
    }
}
