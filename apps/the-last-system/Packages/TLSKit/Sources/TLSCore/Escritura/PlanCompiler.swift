import Foundation
import Yams

/// Estado esperado de una ruta antes o después de un paso.
enum DiskExpectation: Sendable, Hashable, Codable {
    case absent
    case file(String)
    case directory

    /// Texto para el diario: hash, «carpeta» o nada.
    var journalText: String? {
        switch self {
        case .absent: nil
        case .file(let h): h
        case .directory: "carpeta"
        }
    }

    init(journalText: String?) {
        switch journalText {
        case nil: self = .absent
        case "carpeta": self = .directory
        case let h?: self = .file(h)
        }
    }
}

/// Lo que de verdad se hace en disco: escribir un fichero que existe, crear uno nuevo,
/// mover (sin sobrescribir) o renombrar cambiando solo mayúsculas o tildes.
struct PhysicalStep: Sendable, Hashable {
    enum Kind: String, Sendable, Codable { case escribir, crear, mover, renombrar }

    var kind: Kind
    /// Fichero (escribir, crear) u origen (mover, renombrar).
    var path: VaultPath
    var destination: VaultPath?
    /// Cómo debe estar `path` antes del paso (para mover: el origen).
    var base: DiskExpectation
    /// Bytes nuevos (escribir, crear).
    var data: Data?
    /// Bytes de antes (escribir y mover de fichero): van a la copia previa.
    var originalData: Data?
    /// Dónde estaban esos bytes al empezar el plan (nombre de la copia previa).
    var originPath: VaultPath?

    var resultHash: String? {
        switch kind {
        case .escribir, .crear: data.map(ContentHash.of)
        case .mover, .renombrar: base.journalText
        }
    }

    /// Rutas que cambian con el paso.
    var touched: [VaultPath] { [path] + (destination.map { [$0] } ?? []) }
}

/// Traduce las operaciones de un plan a pasos físicos, sobre una vista en memoria de la carpeta.
///
/// Las operaciones se aplican en orden a esa vista (lo movido se sigue con su nueva ruta), y al
/// final se comparan con lo leído del disco: primero los movimientos (en orden), después las
/// escrituras de lo que cambió y por último lo nuevo. Si algo no cuadra, no se escribe nada.
struct PlanCompiler {
    let root: URL
    let realRoot: String
    let layout: VaultLayout
    let rules: ExclusionRules
    let autor: Autor
    let hashApp: [VaultPath: String]

    enum Outcome {
        case steps([PhysicalStep], created: [VaultPath], moved: [Movimiento])
        /// Guardado de una persona que choca con un cambio de fuera: no se escribe nada.
        case conflict(path: VaultPath, mine: Data, theirs: Data)
    }

    /// Ficheros de `.tls/` que la app puede escribir (nunca `escritor.json`, que es del escritor).
    static let writableSettings: Set<String> = [
        ".tls/layout.json", ".tls/config.yaml", ".tls/secuencias.json", ".tls/propiedades.yaml",
        ".tls/plantillas.yaml", ".tls/modulos.yaml",
    ]

    /// `.tls/vistas/<base>.json`: las vistas guardadas de una base (Mosaico v2 §4.6 y pregunta 7). Un solo
    /// nivel, sin nombres ocultos y en JSON (`validate` comprueba que se lee).
    static func esVistaGuardada(_ p: VaultPath) -> Bool {
        let c = p.components
        return c.count == 3 && c[0] == ".tls" && c[1] == "vistas" && !c[2].hasPrefix(".") && p.ext == "json"
    }

    /// Ruta oculta que una persona (nunca un asistente) puede escribir. `.obsidian/` no: es de Obsidian, y crearlo
    /// no hace que Obsidian conozca la carpeta (`obsidian://open` solo abre bóvedas que Obsidian ya tiene).
    static func ajustePermitido(_ p: VaultPath) -> Bool {
        writableSettings.contains(p.raw) || esVistaGuardada(p)
    }

    // MARK: Vista en memoria

    struct Origin: Hashable {
        var diskPath: VaultPath
        var data: Data
        var hash: String
    }

    enum Node {
        case absent
        case file(Data, Origin?)
        case directory
    }

    private var nodes: [String: (path: VaultPath, node: Node)] = [:]
    private var dirMoves: [(from: VaultPath, to: VaultPath)] = []
    private var moves: [PhysicalStep] = []
    private var created: [VaultPath] = []
    private var moved: [Movimiento] = []

    init(root: URL, layout: VaultLayout, rules: ExclusionRules, autor: Autor, hashApp: [VaultPath: String]) {
        self.root = root
        self.realRoot = PathGuard.realPath(root) ?? root.path.precomposedStringWithCanonicalMapping
        self.layout = layout; self.rules = rules; self.autor = autor; self.hashApp = hashApp
    }

    static func key(_ p: VaultPath) -> String { TextFolding.pathKey(p.raw) }

    static func isUnder(_ p: VaultPath, _ dir: VaultPath) -> Bool {
        let k = key(p), d = key(dir)
        return k == d || k.hasPrefix(d + "/")
    }

    static func rebase(_ p: VaultPath, from: VaultPath, to: VaultPath) -> VaultPath {
        VaultPath(components: to.components + Array(p.components.dropFirst(from.components.count)))
    }

    /// Ruta en disco (al empezar el plan) de una ruta de la vista, o `nil` si ya no existe.
    private func diskPath(for p: VaultPath) -> VaultPath? {
        var cur = p
        for m in dirMoves.reversed() {
            if Self.isUnder(cur, m.to) { cur = Self.rebase(cur, from: m.to, to: m.from) }
            else if Self.isUnder(cur, m.from) { return nil }
        }
        return cur
    }

    private mutating func node(_ p: VaultPath) throws -> Node {
        if let n = nodes[Self.key(p)] { return n.node }
        guard let disk = diskPath(for: p) else { return .absent }
        let n = try readDisk(disk)
        nodes[Self.key(p)] = (p, n)
        return n
    }

    private mutating func set(_ p: VaultPath, _ n: Node) {
        nodes[Self.key(p)] = (p, n)
    }

    // MARK: Disco

    /// Comprueba que se puede escribir en `p`: dentro de la carpeta, sin `..`, sin pasar por
    /// enlaces, fuera de lo excluido y (salvo `.tls/` permitido) sin componentes ocultos.
    func checkAllowed(_ p: VaultPath) throws {
        guard !p.isRoot, !p.components.contains("..") else { throw WriteError.rutaNoPermitida(p.raw) }
        if p.components.contains(where: { $0.hasPrefix(".") }) {
            let allowed = Self.ajustePermitido(p) && !isAgent
            guard allowed else { throw WriteError.rutaNoPermitida(p.raw) }
        }
        if rules.excludes(p) { throw WriteError.rutaNoPermitida(p.raw) }
        if isAgent, layout.isPrivate(p) { throw WriteError.rutaNoPermitida(p.raw) }
        // Ningún componente existente puede ser un enlace simbólico.
        let canonical = TextFolding.pathKey(PathGuard.canonicalPath(p.url(in: root)))
        let expected = TextFolding.pathKey(realRoot + "/" + p.raw)
        guard canonical == expected else { throw WriteError.enlaceSimbolico(p.raw) }
    }

    var isAgent: Bool {
        if case .agente = autor { return true }
        return false
    }

    /// Lee del disco sin descargar nada de iCloud (llamar dentro de `withoutMaterializing`).
    /// Quien lee un fichero para cambiarlo comprueba antes `checkAllowed` (no se lee lo excluido).
    func readDisk(_ p: VaultPath) throws -> Node {
        guard !p.components.contains("..") else { throw WriteError.rutaNoPermitida(p.raw) }
        let url = p.url(in: root)
        guard let info = UbiquityInspector.info(url) else { return .absent }
        if info.isSymlink { throw WriteError.enlaceSimbolico(p.raw) }
        // Ningún componente puede ser un enlace simbólico (ni llevar fuera de la carpeta).
        let canonical = TextFolding.pathKey(PathGuard.canonicalPath(url))
        guard canonical == TextFolding.pathKey(realRoot + "/" + p.raw) else { throw WriteError.enlaceSimbolico(p.raw) }
        if info.isDirectory { return .directory }
        if info.dataless { throw WriteError.sinDescargar(p.raw) }
        let data: Data
        do { data = try Data(contentsOf: url, options: [.uncached]) } catch {
            if UbiquityInspector.isDataless(url) { throw WriteError.sinDescargar(p.raw) }
            throw WriteError.noExiste(p.raw)
        }
        return .file(data, Origin(diskPath: p, data: data, hash: ContentHash.of(data)))
    }

    /// Fichero existente (en la vista): sus bytes y su origen.
    private mutating func existingFile(_ p: VaultPath) throws -> (Data, Origin?) {
        try checkAllowed(p)
        switch try node(p) {
        case .absent: throw WriteError.noExiste(p.raw)
        case .directory: throw WriteError.esCarpeta(p.raw)
        case .file(let d, let o): return (d, o)
        }
    }

    private mutating func isFree(_ p: VaultPath) throws -> Bool {
        if case .absent = try node(p) {
            // El padre no puede ser un fichero.
            var parent = p.parent
            while let a = parent, !a.isRoot {
                if case .file = try node(a) { return false }
                parent = a.parent
            }
            return true
        }
        return false
    }

    /// `p` si está libre; si no, «nombre (2).ext», «nombre (3).ext»…
    private mutating func uniqueFree(_ p: VaultPath) throws -> VaultPath {
        if try isFree(p) { return p }
        let parent = p.parent ?? .root
        let ext = p.ext.isEmpty ? "" : "." + String(p.name.split(separator: ".").last ?? "")
        for n in 2...999 {
            let candidate = parent.appending("\(p.stem) (\(n))\(ext)")
            if try isFree(candidate) { return candidate }
        }
        throw WriteError.destinoOcupado(p.raw)
    }

    // MARK: Compilar

    mutating func compile(_ ops: [WriteOp]) throws -> Outcome {
        for op in ops {
            if let conflict = try apply(op) { return conflict }
        }
        var writes: [PhysicalStep] = []
        var creates: [PhysicalStep] = []
        for (_, entry) in nodes.sorted(by: { $0.value.path.raw < $1.value.path.raw }) {
            guard case .file(let data, let origin) = entry.node else { continue }
            if let origin {
                guard data != origin.data else { continue }
                writes.append(PhysicalStep(kind: .escribir, path: entry.path, base: .file(origin.hash), data: data,
                                           originalData: origin.data, originPath: origin.diskPath))
            } else {
                creates.append(PhysicalStep(kind: .crear, path: entry.path, base: .absent, data: data))
            }
        }
        let createdNow = created.filter { p in creates.contains { Self.key($0.path) == Self.key(p) } }
        return .steps(moves + writes + creates, created: createdNow, moved: moved)
    }

    /// Aplica una operación a la vista. Devuelve un conflicto si es un guardado que choca.
    private mutating func apply(_ op: WriteOp) throws -> Outcome? {
        // Copias locales: los cierres de edición no capturan `self` (acceso exclusivo).
        let esPersona = autor.esPersona
        switch op {
        case .create(let p, let data):
            try checkAllowed(p)
            let actual = try uniqueFree(p)
            try checkAllowed(actual)
            try Self.validate(actual, data: data, previous: nil)
            set(actual, .file(data, nil))
            created.append(actual)

        case .mergeFrontmatter(let p, let setProps, let unset):
            try editText(p) { old, path in
                var doc = FrontmatterDocument(text: old)
                if doc.hasFrontmatter, !doc.frontmatter.isValid { throw WriteError.propiedadesIlegibles(path.raw) }
                if !esPersona {
                    // Guardarraíl: nunca una lista vacía encima de una con contenido.
                    for prop in setProps where Self.isEmptyList(prop.value) {
                        if case .list(let cur)? = doc.value(prop.key), !cur.isEmpty { throw WriteError.listaVacia(prop.key) }
                    }
                    for k in unset {
                        if case .list(let cur)? = doc.value(k), !cur.isEmpty { throw WriteError.listaVacia(k) }
                    }
                }
                doc.merge(set: setProps, unset: unset)
                return doc.text
            }

        case .appendToSection(let p, let section, let text, let blank):
            try editText(p) { old, _ in
                var doc = FrontmatterDocument(text: old)
                doc.replaceBody(try MarkdownSections.append(to: section, in: doc.body, text: text, blankLine: blank,
                                                             create: true, eol: doc.eol))
                return doc.text
            }

        case .replaceSection(let p, let section, let text, let baseHash):
            if !esPersona {
                // Como `replaceBody` (PLAN §4.8): si no está como la dejó la app, solo propiedades y añadidos.
                let (data, _) = try existingFile(p)
                guard hashApp[p] == ContentHash.of(data) else { throw WriteError.soloAnadidos(p.raw) }
            }
            try editText(p) { old, _ in
                var doc = FrontmatterDocument(text: old)
                if !esPersona, let current = MarkdownSections.content(of: section, in: doc.body),
                   Self.hasListItems(current), !Self.hasListItems(text) {
                    throw WriteError.listaVacia(section)
                }
                doc.replaceBody(try MarkdownSections.replace(section, in: doc.body, with: text, baseHash: baseHash, eol: doc.eol))
                return doc.text
            }

        case .replaceBody(let p, let body, let baseHash):
            let (data, _) = try existingFile(p)
            let current = ContentHash.of(data)
            guard let e = EditableText(data: data) else { throw WriteError.noEsTexto(p.raw) }
            var doc = FrontmatterDocument(text: e.text)
            doc.replaceBody(body)
            let mine = EditableText(bom: e.bom, text: doc.text).data
            if autor.esPersona {
                guard let baseHash else { throw WriteError.cambioExterno(p.raw) }
                if baseHash != current { return .conflict(path: p, mine: mine, theirs: data) }
            } else {
                // Asistentes y sistema: solo sobre lo que dejó la app.
                guard hashApp[p] == current else { throw WriteError.soloAnadidos(p.raw) }
                if let baseHash, baseHash != current { throw WriteError.cambioExterno(p.raw) }
            }
            try Self.validate(p, data: mine, previous: data)
            try replace(p, with: mine)

        case .saveText(let p, let base, let text):
            guard autor.esPersona else { throw WriteError.noPermitidoAsistente(p.raw) }
            let (data, _) = try existingFile(p)
            guard let e = EditableText(data: data) else { throw WriteError.noEsTexto(p.raw) }
            let theirs = e.text
            let result: String
            if theirs == base || theirs == text {
                result = text
            } else {
                switch EditorMerge.merge(base: base, mine: text, theirs: theirs) {
                case .merged(let m): result = m
                case .conflict:
                    return .conflict(path: p, mine: EditableText(bom: e.bom, text: text).data, theirs: data)
                }
            }
            let newData = EditableText(bom: e.bom, text: result).data
            try Self.validate(p, data: newData, previous: data)
            try replace(p, with: newData)

        case .appendLine(let p, let line):
            try editText(p) { old, _ in
                MarkdownSections.appendLine(line, to: old, eol: TextLines.dominantEOL(old))
            }

        case .upsertCSVRow(let p, let row, let key):
            let (data, _) = try existingFile(p)
            guard var csv = CSVDocument(data: data) else { throw WriteError.noEsTexto(p.raw) }
            try csv.upsert(row, key: key, protectManual: !autor.esPersona)
            try replace(p, with: csv.data)

        case .insertCSVRows(let p, let rows, let key):
            let (data, _) = try existingFile(p)
            guard var csv = CSVDocument(data: data) else { throw WriteError.noEsTexto(p.raw) }
            try csv.insertNew(rows, key: key)
            try replace(p, with: csv.data)

        case .setTableCells(let p, let table, let keyColumn, let keyValue, let cells):
            try editText(p) { old, _ in
                var doc = FrontmatterDocument(text: old)
                doc.replaceBody(try MarkdownTable.setCells(in: doc.body, selector: table, keyColumn: keyColumn,
                                                           keyValue: keyValue, cells: cells, protectManual: !esPersona))
                return doc.text
            }

        case .appendTableRow(let p, let table, let cells):
            try editText(p) { old, _ in
                var doc = FrontmatterDocument(text: old)
                doc.replaceBody(try MarkdownTable.appendRow(in: doc.body, selector: table, cells: cells, eol: doc.eol))
                return doc.text
            }

        case .editRanges(let p, let edits, let baseHash):
            if isAgent { throw WriteError.noPermitidoAsistente(p.raw) }
            let (data, _) = try existingFile(p)
            guard ContentHash.of(data) == baseHash else { throw WriteError.cambioExterno(p.raw) }
            guard let e = EditableText(data: data) else { throw WriteError.noEsTexto(p.raw) }
            var bytes = Array(e.text.utf8)
            var limit = bytes.count
            for edit in edits.sorted(by: { $0.offset > $1.offset }) {
                guard edit.offset >= 0, edit.length >= 0, edit.offset + edit.length <= limit else {
                    throw WriteError.cambiosInvalidos
                }
                bytes.replaceSubrange(edit.offset..<(edit.offset + edit.length), with: Array(edit.replacement.utf8))
                limit = edit.offset
            }
            guard let text = String(bytes: bytes, encoding: .utf8), text.utf8.count == bytes.count else {
                throw WriteError.cambiosInvalidos
            }
            let newData = EditableText(bom: e.bom, text: text).data
            try Self.validate(p, data: newData, previous: data)
            try replace(p, with: newData)

        case .move(let src, let dst):
            try move(src, to: dst, unique: false)

        case .retire(let p, let apartado):
            let archivo = VaultPath(layout.archivo)
            if Self.isUnder(p, archivo) { throw WriteError.yaRetirada(p.raw) }
            var base = archivo
            if let a = apartado, !a.isEmpty { base = base.appending(a) }
            let dst = VaultPath(components: base.components + p.components)
            try move(p, to: dst, unique: true)
        }
        return nil
    }

    /// Lee un fichero de texto de la vista, aplica `edit` y lo deja en la vista (validado).
    private mutating func editText(_ p: VaultPath, _ edit: (String, VaultPath) throws -> String) throws {
        let (data, _) = try existingFile(p)
        guard let e = EditableText(data: data) else { throw WriteError.noEsTexto(p.raw) }
        let newText = try edit(e.text, p)
        let newData = EditableText(bom: e.bom, text: newText).data
        try Self.validate(p, data: newData, previous: data)
        try replace(p, with: newData)
    }

    private mutating func replace(_ p: VaultPath, with data: Data) throws {
        try checkAllowed(p)
        guard case .file(_, let origin) = try node(p) else { throw WriteError.noExiste(p.raw) }
        set(p, .file(data, origin))
    }

    private mutating func move(_ src: VaultPath, to requested: VaultPath, unique: Bool) throws {
        try checkAllowed(src)
        try checkAllowed(requested)
        if isAgent {
            // Los asistentes solo ordenan el Buzón; lo demás lo proponen.
            guard let buzon = layout.buzon, Self.isUnder(src, VaultPath(buzon)) else {
                throw WriteError.noPermitidoAsistente(src.raw)
            }
        }
        let n = try node(src)
        if case .absent = n { throw WriteError.noExiste(src.raw) }
        if Self.isUnder(requested, src), Self.key(requested) != Self.key(src) { throw WriteError.rutaNoPermitida(requested.raw) }
        // Solo cambian mayúsculas o tildes: en dos pasos, con un nombre intermedio.
        if Self.key(src) == Self.key(requested) {
            guard src.raw != requested.raw else { return }
            nodes[Self.key(src)] = (requested, n)
            if let step = physicalBase(n) {
                moves.append(PhysicalStep(kind: .renombrar, path: src, destination: requested, base: step.base,
                                          originalData: step.data, originPath: step.origin))
            }
            moved.append(Movimiento(de: src, a: requested))
            return
        }
        let dst: VaultPath
        if unique { dst = try uniqueFree(requested) } else { dst = requested }
        guard try isFree(dst) else { throw WriteError.destinoOcupado(dst.raw) }
        try checkAllowed(dst)
        set(src, .absent)
        set(dst, n)
        // Lo creado en este plan sigue a su nueva ruta.
        created = created.map { Self.isUnder($0, src) ? Self.rebase($0, from: src, to: dst) : $0 }
        if case .directory = n {
            // Lo que ya estaba en la vista dentro de la carpeta va con ella.
            for (k, e) in nodes where Self.isUnder(e.path, src) && k != Self.key(src) {
                nodes.removeValue(forKey: k)
                let np = Self.rebase(e.path, from: src, to: dst)
                nodes[Self.key(np)] = (np, e.node)
            }
            dirMoves.append((src, dst))
        }
        if let step = physicalBase(n) {
            moves.append(PhysicalStep(kind: .mover, path: src, destination: dst, base: step.base,
                                      originalData: step.data, originPath: step.origin))
        }
        moved.append(Movimiento(de: src, a: dst))
    }

    /// Estado en disco de lo que se mueve (`nil` si aún no existe: se creó en este plan).
    private func physicalBase(_ n: Node) -> (base: DiskExpectation, data: Data?, origin: VaultPath?)? {
        switch n {
        case .absent: nil
        case .directory: (.directory, nil, nil)
        case .file(_, let origin?): (.file(origin.hash), origin.data, origin.diskPath)
        case .file(_, nil): nil
        }
    }

    // MARK: Validación

    static func isEmptyList(_ v: PropertyValue) -> Bool {
        switch v {
        case .list(let l): l.isEmpty
        case .empty: true
        default: false
        }
    }

    static func hasListItems(_ text: String) -> Bool {
        TextLines.split(text).contains { l in
            let t = l.content.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ")
                || t.range(of: #"^[0-9]+[.)] "#, options: .regularExpression) != nil
        }
    }

    /// El resultado se puede volver a leer: propiedades válidas (si lo eran), CSV con cabecera,
    /// JSON y YAML de `.tls/` legibles.
    static func validate(_ p: VaultPath, data: Data, previous: Data?) throws {
        switch p.ext {
        case "md", "markdown":
            guard let doc = FrontmatterDocument(data: data) else { throw WriteError.noEsTexto(p.raw) }
            if doc.hasFrontmatter, !doc.frontmatter.isValid {
                let wasInvalid = previous.flatMap(FrontmatterDocument.init(data:)).map { $0.hasFrontmatter && !$0.frontmatter.isValid } ?? false
                if !wasInvalid { throw WriteError.propiedadesIlegibles(p.raw) }
            }
        case "csv":
            guard let text = TextDecoding.decode(data) else { throw WriteError.contenidoIlegible(p.raw) }
            let hadHeader = previous.flatMap(TextDecoding.decode).map { !CSVTable.parse($0).header.isEmpty } ?? false
            if hadHeader, CSVTable.parse(text).header.isEmpty { throw WriteError.contenidoIlegible(p.raw) }
        case "json":
            guard (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                throw WriteError.contenidoIlegible(p.raw)
            }
        case "yaml", "yml":
            guard let text = TextDecoding.decode(data) else { throw WriteError.contenidoIlegible(p.raw) }
            do { _ = try Yams.compose(yaml: text, Resolver.basic) } catch { throw WriteError.contenidoIlegible(p.raw) }
        default:
            break
        }
    }
}
