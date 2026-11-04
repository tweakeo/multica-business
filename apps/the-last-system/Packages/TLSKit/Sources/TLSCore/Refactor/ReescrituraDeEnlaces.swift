import Foundation

/// Cálculo de los cambios de cada fichero para un conjunto de movimientos.
struct Contexto {
    let snapshot: VaultSnapshot
    let map: MoveMap
    let oldResolver: LinkResolver
    let newResolver: LinkResolver
    /// Rutas después del cambio (ficheros y carpetas), sin distinguir mayúsculas.
    let newLower: [String: VaultPath]
    let opciones: LinkRefactor.Opciones
    let requested: [Traslado]

    init(snapshot: VaultSnapshot, map: MoveMap, oldResolver: LinkResolver, newResolver: LinkResolver,
         newLower: [String: VaultPath], opciones: LinkRefactor.Opciones, requested: [Traslado]) {
        self.snapshot = snapshot; self.map = map; self.oldResolver = oldResolver; self.newResolver = newResolver
        self.newLower = newLower; self.opciones = opciones; self.requested = requested
        var files = Set<String>()
        for p in snapshot.files { files.insert(TextFolding.pathKey(map.map(p).raw)) }
        self.newFileKeys = files
        var old = Set<String>()
        for p in snapshot.files { old.insert(TextFolding.pathKey(p.raw)) }
        self.oldFileKeys = old
    }

    private let newFileKeys: Set<String>
    private let oldFileKeys: Set<String>

    func newFile(_ p: VaultPath) -> VaultPath? {
        let k = TextFolding.pathKey(p.raw)
        return newFileKeys.contains(k) ? newLower[k] : nil
    }

    func oldFile(_ p: VaultPath) -> VaultPath? {
        let k = TextFolding.pathKey(p.raw)
        return oldFileKeys.contains(k) ? snapshot.existing(p) : nil
    }

    func oldPath(_ p: VaultPath) -> VaultPath? { snapshot.existing(p) }

    static func splice(_ bytes: [UInt8], _ range: Range<Int>, _ edits: [TextEdit]) -> String {
        var out = Array(bytes[range])
        for e in edits.sorted(by: { $0.offset > $1.offset }) {
            let s = e.offset - range.lowerBound
            out.replaceSubrange(s..<(s + e.length), with: Array(e.replacement.utf8))
        }
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: Notas

    func rewriteNote(_ p: VaultPath, text: String, into result: inout FileEdits) {
        let p2 = map.map(p)
        let bytes = Array(text.utf8)
        for occ in LinkScanner.scan(text) {
            let link = occ.link
            if link.isExternal || link.target.isEmpty { continue }
            guard let before = oldResolver.resolve(link.resolvable, from: p) else { continue }
            let expected = map.map(before)
            let targetMoves = expected.raw != before.raw
            let nameChanged = expected.name != before.name
            let written = LinkScanner.string(bytes, occ.targetRange)
            var newTarget = written
            var ok = false
            switch link.style {
            case .markdown:
                func rewritten() -> String? {
                    let c = MarkdownDestination.rewrite(original: written, from: p2, to: expected, angle: occ.angle)
                    return MarkdownDestination.strictTarget(c, from: p2, exists: newFile)?.raw == expected.raw ? c : nil
                }
                if targetMoves || p2.raw != p.raw {
                    // Tiene que seguir resolviendo por ruta (nunca por nombre: sería un enlace «flojo»).
                    // Si cambió el nombre (también solo mayúsculas), se escribe el nombre nuevo.
                    let stillStrict = MarkdownDestination.strictTarget(written, from: p2, exists: newFile)?.raw == expected.raw
                    if stillStrict, !nameChanged {
                        ok = true
                    } else if let c = rewritten() {
                        newTarget = c; ok = true
                    }
                } else if newResolver.resolve(link.resolvable, from: p2)?.raw == expected.raw {
                    ok = true
                } else if let c = rewritten() {
                    newTarget = c; ok = true
                }
            case .wiki:
                let resolves = newResolver.resolve(link.resolvable, from: p2)?.raw == expected.raw
                // `[[Carpeta/nota]]`: la ruta escrita tiene que seguir siendo la de verdad.
                let pathStillTrue: Bool = {
                    guard written.contains("/") else { return true }
                    let w = TextFolding.pathKey(written)
                    let e = TextFolding.pathKey(expected.raw)
                    let eNoExt = TextFolding.pathKey(WikiTarget.isNote(expected) ? String(expected.raw.dropLast(expected.ext.count + 1)) : expected.raw)
                    return e == w || e.hasSuffix("/" + w) || eNoExt == w || eNoExt.hasSuffix("/" + w)
                }()
                // Como Obsidian al mover: si el nombre ya no es único, el enlace al movido se escribe con su ruta.
                let stemKey = TextFolding.nameKey(WikiTarget.isNote(expected) ? expected.stem : expected.name)
                let repetido = targetMoves && Set(newResolver.names[stemKey] ?? []).count > 1
                if resolves, pathStillTrue, !(targetMoves && nameChanged), !(repetido && !written.contains("/")) {
                    ok = true
                } else {
                    for c in WikiTarget.candidates(original: written, to: expected)
                    where !(repetido && !c.contains("/")) && newResolver.resolve("[[" + c + "]]", from: p2)?.raw == expected.raw {
                        newTarget = c; ok = true
                        break
                    }
                }
            }
            guard ok else {
                result.problemas.append(ProblemaDeEnlace(ruta: p, linea: occ.line, enlace: link.raw,
                                                         motivo: "No encuentro cómo escribirlo para que siga apuntando a «\(expected.stem)»."))
                continue
            }
            var local: [TextEdit] = []
            if newTarget != written {
                local.append(TextEdit(offset: occ.targetRange.lowerBound, length: occ.targetRange.count,
                                      replacement: YAMLInline.escape(newTarget, comillas: occ.comillas)))
            }
            if opciones.actualizarTextoVisible, targetMoves, nameChanged, let lr = occ.labelRange,
               let newLabel = newVisibleText(old: LinkScanner.string(bytes, lr), before: before, after: expected) {
                local.append(TextEdit(offset: lr.lowerBound, length: lr.count,
                                      replacement: YAMLInline.escape(newLabel, comillas: occ.comillas)))
            }
            guard !local.isEmpty else { continue }
            result.edits += local
            let lugar: CambioDeEnlace.Lugar
            switch occ.lugar {
            case .cuerpo: lugar = .cuerpo
            case .propiedad(let k): lugar = .propiedad(k)
            }
            result.cambios.append(CambioDeEnlace(linea: occ.line, lugar: lugar, antes: link.raw,
                                                 despues: Self.splice(bytes, occ.range, local)))
        }
        rewritePathProperties(p, bytes: bytes, into: &result)
    }

    /// Texto visible nuevo si coincidía con el nombre viejo (opción apagada por defecto).
    func newVisibleText(old: String, before: VaultPath, after: VaultPath) -> String? {
        let label = old.trimmingCharacters(in: .whitespaces)
        if label == before.stem { return after.stem }
        if let t = snapshot.text(before), WikiTarget.isNote(before) {
            let doc = NoteDocument(text: t)
            if label == doc.title(fileStem: before.stem) {
                let n = doc.title(fileStem: after.stem)
                return n == label ? nil : n
            }
        }
        return nil
    }

    /// Propiedades con una ruta en texto plano (`pdf`, `logo`…), relativas a la nota o a la raíz.
    func rewritePathProperties(_ p: VaultPath, bytes: [UInt8], into result: inout FileEdits) {
        let keys = Set(opciones.propiedadesRuta.map(TextFolding.nameKey))
        guard !keys.isEmpty else { return }
        let ls = LinkScanner.lines(bytes)
        guard let fm = LinkScanner.frontmatter(bytes, ls) else { return }
        let p2 = map.map(p)
        for i in fm.yaml {
            let l = ls[i]
            let line = LinkScanner.string(bytes, l.start..<l.end)
            guard let kl = FrontmatterDocument.parseKeyLine(line), keys.contains(TextFolding.nameKey(kl.name)),
                  !kl.value.isEmpty, !kl.value.contains("[["), !kl.value.contains("](") else { continue }
            let rawStart = l.start + kl.keyPart.utf8.count + kl.separator.utf8.count
            let rawRange = rawStart..<(rawStart + kl.value.utf8.count)
            let style = YAMLScalar.quoteStyle(of: kl.value)
            let decoded = FrontmatterReader.read("v: " + kl.value).properties.first?.value
            guard case .text(let value)? = decoded else { continue }
            let bases = [(p.parent ?? .root, p2.parent ?? .root), (VaultPath.root, VaultPath.root)]
            guard let rewritten = rewritePathValue(value, bases: bases) else { continue }
            let rendered = YAMLScalar.render(text: rewritten, preferred: style)
            result.edits.append(TextEdit(offset: rawRange.lowerBound, length: rawRange.count, replacement: rendered))
            result.cambios.append(CambioDeEnlace(linea: i + 1, lugar: .propiedad(kl.name), antes: value, despues: rewritten))
        }
    }

    /// Ruta escrita (con `#fragmento` opcional) relativa a la primera base donde existe. `nil` si no cambia.
    /// `bases`: cada base de antes con la que le corresponde después.
    func rewritePathValue(_ value: String, bases: [(VaultPath, VaultPath)]) -> String? {
        // Primero la ruta entera («Factura #12.pdf» es un nombre válido); si no existe, «ruta#fragmento».
        var formas: [(path: String, fragment: String)] = [(value.trimmingCharacters(in: .whitespaces), "")]
        if let h = value.firstIndex(of: "#") {
            formas.append((String(value[..<h]).trimmingCharacters(in: .whitespaces), String(value[h...])))
        }
        for (path, fragment) in formas {
            guard !path.isEmpty, !LinkParser.isExternal(path), !path.hasPrefix("/") else { continue }
            var seen = Set<String>()
            for (base, newBase) in bases where seen.insert(base.raw).inserted {
                let candidate = VaultPath(base.isRoot ? path : base.raw + "/" + path)
                guard !candidate.components.contains(".."), let before = oldFile(candidate) else { continue }
                let expected = map.map(before)
                guard expected.raw != before.raw || newBase.raw != base.raw else { return nil }
                let written: String
                if !newBase.isRoot, MoveMap.isUnder(expected, newBase) {
                    written = expected.components.dropFirst(newBase.components.count).joined(separator: "/")
                } else {
                    written = expected.raw
                }
                let out = written + fragment
                return out == value ? nil : out
            }
        }
        return nil
    }

    // MARK: CSV

    func rewriteCSV(_ p: VaultPath, text: String, into result: inout FileEdits) {
        let columns = Set(opciones.columnasCSV.map(TextFolding.nameKey))
        guard !columns.isEmpty else { return }
        let delimiter = CSVTable.detectDelimiter(text)
        guard let dByte = String(delimiter).utf8.first else { return }
        let bytes = Array(text.utf8)
        let records = CSVCells.parse(bytes, delimiter: dByte).filter { !$0.isBlank }
        guard let header = records.first else { return }
        let targets = header.cells.enumerated().compactMap { i, c in
            columns.contains(TextFolding.nameKey(c.value.trimmingCharacters(in: .whitespaces))) ? (i, c.value) : nil
        }
        guard !targets.isEmpty else { return }
        let p2 = map.map(p)
        // Bases: la carpeta del área (como `documento` en `Registros/emitidas.csv`), la del CSV y la raíz.
        var bases: [(VaultPath, VaultPath)] = []
        if p.components.count >= 2 {
            bases.append((VaultPath(p.components[0]), p2.components.count >= 2 ? VaultPath(p2.components[0]) : .root))
        }
        bases.append((p.parent ?? .root, p2.parent ?? .root))
        bases.append((.root, .root))
        for (n, record) in records.enumerated().dropFirst() {
            var changed = false
            for (col, name) in targets where col < record.cells.count {
                let cell = record.cells[col]
                guard !cell.value.isEmpty, !cell.value.contains(".."),
                      let rewritten = rewritePathValue(cell.value, bases: bases) else { continue }
                let encoded = CSVCells.encode(rewritten, quoted: cell.quoted, delimiter: delimiter)
                result.edits.append(TextEdit(offset: cell.range.lowerBound, length: cell.range.count, replacement: encoded))
                result.cambios.append(CambioDeEnlace(linea: n + 1, lugar: .columna(name), antes: cell.value, despues: rewritten))
                changed = true
            }
            if changed { result.filas += 1 }
        }
    }

    // MARK: Ajustes de `.tls/`

    /// Rutas de la carpeta escritas en `layout.json` (áreas, `privado`…). Solo las que existían.
    func rewriteJSON(_ p: VaultPath, text: String, into result: inout FileEdits) {
        guard p.raw == ".tls/layout.json" else { return }
        let b = Array(text.utf8)
        var i = 0
        let quote = UInt8(ascii: "\"")
        while i < b.count {
            guard b[i] == quote else { i += 1; continue }
            var j = i + 1
            while j < b.count, b[j] != quote {
                if b[j] == UInt8(ascii: "\\") { j += 2 } else { j += 1 }
            }
            guard j < b.count else { break }
            let token = i..<(j + 1)
            // ¿Clave? (lo siguiente que no es espacio son dos puntos)
            var k = j + 1
            while k < b.count, b[k] == 0x20 || b[k] == 0x09 || b[k] == 0x0A || b[k] == 0x0D { k += 1 }
            let isKey = k < b.count && b[k] == UInt8(ascii: ":")
            if !isKey,
               let value = try? JSONDecoder().decode(String.self, from: Data(b[token])),
               let new = rewriteSettingsPath(value) {
                let enc = JSONEncoder()
                enc.outputFormatting = [.withoutEscapingSlashes]
                if let data = try? enc.encode(new), let s = String(data: data, encoding: .utf8) {
                    result.edits.append(TextEdit(offset: token.lowerBound, length: token.count, replacement: s))
                    result.cambios.append(CambioDeEnlace(linea: lineNumber(b, token.lowerBound), lugar: .ajustes(p.raw),
                                                         antes: value, despues: new))
                }
            }
            i = j + 1
        }
    }

    /// Lienzos de Obsidian (`.canvas`): el `"file"` de cada nodo es una ruta desde la raíz (Obsidian también
    /// los actualiza al renombrar).
    func rewriteCanvas(_ p: VaultPath, text: String, into result: inout FileEdits) {
        let b = Array(text.utf8)
        guard let re = try? NSRegularExpression(pattern: #""file"\s*:\s*("(?:[^"\\]|\\.)*")"#) else { return }
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range(at: 1), in: text) else { continue }
            let start = text.utf8.distance(from: text.startIndex, to: r.lowerBound)
            let token = start..<(start + text.utf8.distance(from: r.lowerBound, to: r.upperBound))
            guard let value = try? JSONDecoder().decode(String.self, from: Data(b[token])),
                  let old = oldPath(VaultPath(value)), map.moves(old) else { continue }
            let new = map.map(old).raw
            let enc = JSONEncoder()
            enc.outputFormatting = [.withoutEscapingSlashes]
            guard let data = try? enc.encode(new), let s = String(data: data, encoding: .utf8) else { continue }
            result.edits.append(TextEdit(offset: token.lowerBound, length: token.count, replacement: s))
            result.cambios.append(CambioDeEnlace(linea: lineNumber(b, token.lowerBound), lugar: .propiedad("file"), antes: value, despues: new))
        }
    }

    /// `privado:` de `config.yaml` y `fichero:` de `plantillas.yaml`.
    func rewriteYAML(_ p: VaultPath, text: String, into result: inout FileEdits) {
        let b = Array(text.utf8)
        let ls = LinkScanner.lines(b)
        switch p.raw {
        case ".tls/config.yaml":
            var inPrivado = false
            for (n, l) in ls.enumerated() {
                let line = LinkScanner.string(b, l.start..<l.end)
                if let kl = FrontmatterDocument.parseKeyLine(line) {
                    inPrivado = kl.name == "privado"
                    guard inPrivado, !kl.value.isEmpty else { continue }
                    let start = l.start + kl.keyPart.utf8.count + kl.separator.utf8.count
                    if kl.value.hasPrefix("[") {
                        for item in flowItems(b, (start + 1)..<(start + kl.value.utf8.count - (kl.value.hasSuffix("]") ? 1 : 0))) {
                            rewriteYAMLScalar(p, b, item, line: n + 1, inFlow: true, settingsPath: true, into: &result)
                        }
                    } else {
                        rewriteYAMLScalar(p, b, start..<(start + kl.value.utf8.count), line: n + 1, inFlow: false,
                                          settingsPath: true, into: &result)
                    }
                    continue
                }
                guard inPrivado else { continue }
                // `  - ruta`
                var j = l.start
                while j < l.end, b[j] == 0x20 || b[j] == 0x09 { j += 1 }
                guard j < l.end, b[j] == UInt8(ascii: "-"), j + 1 < l.end, b[j + 1] == 0x20 else { continue }
                j += 2
                while j < l.end, b[j] == 0x20 { j += 1 }
                rewriteYAMLScalar(p, b, scalarRange(b, j..<l.end), line: n + 1, inFlow: false, settingsPath: true, into: &result)
            }
        case ".tls/plantillas.yaml":
            for (n, l) in ls.enumerated() {
                var j = l.start
                while j < l.end, b[j] == 0x20 { j += 1 }
                guard j > l.start else { continue }
                let line = LinkScanner.string(b, j..<l.end)
                guard let kl = FrontmatterDocument.parseKeyLine(line), kl.name == "fichero", !kl.value.isEmpty else { continue }
                let start = j + kl.keyPart.utf8.count + kl.separator.utf8.count
                rewriteTemplateFile(p, b, start..<(start + kl.value.utf8.count), line: n + 1, into: &result)
            }
        default:
            break
        }
    }

    /// Escalar YAML (con o sin comillas) que es una ruta desde la raíz.
    func rewriteYAMLScalar(_ p: VaultPath, _ b: [UInt8], _ r: Range<Int>, line: Int, inFlow: Bool, settingsPath: Bool,
                           into result: inout FileEdits) {
        let raw = LinkScanner.string(b, r).trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty, case .text(let value)? = FrontmatterReader.read("v: " + raw).properties.first?.value,
              let new = rewriteSettingsPath(value) else { return }
        let rendered = YAMLScalar.render(text: new, inFlow: inFlow, preferred: YAMLScalar.quoteStyle(of: raw))
        let tr = LinkScanner.trimmed(b, r)
        result.edits.append(TextEdit(offset: tr.lowerBound, length: tr.count, replacement: rendered))
        result.cambios.append(CambioDeEnlace(linea: line, lugar: .ajustes(p.raw), antes: value, despues: new))
    }

    /// Ruta de los ajustes, tal cual o como plantilla `{area}/…` (así escribe G3 `privado`): la forma
    /// nueva si lo que nombra se mueve (con `{area}/` si sigue en esa área); `nil` si no cambia.
    func rewriteSettingsPath(_ value: String) -> String? {
        let layout = snapshot.layout
        guard let old = oldPath(value.contains("{") ? layout.expand(value) : VaultPath(value)), map.moves(old) else { return nil }
        let new = map.map(old)
        var written = new.raw
        if value.hasPrefix("{"), let close = value.firstIndex(of: "}"),
           let code = AreaCode.allCases.first(where: { "{\($0.layoutKey)}" == String(value[...close]) }) {
            let newArea = map.map(layout.areaFolder(code))
            if MoveMap.isUnder(new, newArea) {
                let rest = new.components.dropFirst(newArea.components.count).joined(separator: "/")
                written = "{\(code.layoutKey)}" + (rest.isEmpty ? "" : "/" + rest)
            }
        }
        return written == value ? nil : written
    }

    /// `fichero:` de una plantilla: puede empezar por `{area}/` (se conserva si la plantilla sigue en esa área).
    func rewriteTemplateFile(_ p: VaultPath, _ b: [UInt8], _ r: Range<Int>, line: Int, into result: inout FileEdits) {
        let raw = LinkScanner.string(b, r)
        guard case .text(let value)? = FrontmatterReader.read("v: " + raw).properties.first?.value else { return }
        let layout = snapshot.layout
        let expanded = layout.expand(value)
        guard let old = oldPath(expanded), map.moves(old) else { return }
        let new = map.map(old)
        var written = new.raw
        if value.hasPrefix("{"), let close = value.firstIndex(of: "}"),
           let code = AreaCode.allCases.first(where: { "{\($0.layoutKey)}" == String(value[...close]) }) {
            let newArea = map.map(layout.areaFolder(code))
            if MoveMap.isUnder(new, newArea) {
                written = "{\(code.layoutKey)}/" + new.components.dropFirst(newArea.components.count).joined(separator: "/")
            }
        }
        guard written != value else { return }
        let rendered = YAMLScalar.render(text: written, preferred: YAMLScalar.quoteStyle(of: raw))
        result.edits.append(TextEdit(offset: r.lowerBound, length: r.count, replacement: rendered))
        result.cambios.append(CambioDeEnlace(linea: line, lugar: .ajustes(p.raw), antes: value, despues: written))
    }

    /// Elementos de una lista YAML en línea (`[a, "b"]`), sin los corchetes.
    func flowItems(_ b: [UInt8], _ r: Range<Int>) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = r.lowerBound
        var i = r.lowerBound
        var q: UInt8?
        while i < r.upperBound {
            let c = b[i]
            if let quote = q {
                if c == UInt8(ascii: "\\"), quote == UInt8(ascii: "\"") { i += 2; continue }
                if c == quote { q = nil }
            } else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") {
                q = c
            } else if c == UInt8(ascii: ",") {
                out.append(LinkScanner.trimmed(b, start..<i)); start = i + 1
            }
            i += 1
        }
        let last = LinkScanner.trimmed(b, start..<r.upperBound)
        if !last.isEmpty { out.append(last) }
        return out.filter { !$0.isEmpty }
    }

    /// Escalar sin el comentario final (` # …`).
    func scalarRange(_ b: [UInt8], _ r: Range<Int>) -> Range<Int> {
        var end = r.upperBound
        if r.lowerBound < r.upperBound, b[r.lowerBound] != UInt8(ascii: "\""), b[r.lowerBound] != UInt8(ascii: "'") {
            var i = r.lowerBound
            while i < r.upperBound {
                if b[i] == UInt8(ascii: "#"), i > r.lowerBound, b[i - 1] == 0x20 { end = i; break }
                i += 1
            }
        }
        return LinkScanner.trimmed(b, r.lowerBound..<end)
    }

    func lineNumber(_ b: [UInt8], _ offset: Int) -> Int {
        var n = 1
        var i = 0
        while i < offset {
            if b[i] == 0x0A { n += 1 } else if b[i] == 0x0D { n += 1; if i + 1 < offset, b[i + 1] == 0x0A { i += 1 } }
            i += 1
        }
        return n
    }
}
