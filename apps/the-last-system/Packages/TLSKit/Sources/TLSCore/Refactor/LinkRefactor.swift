import Foundation

/// Un movimiento pedido: de una ruta a otra (renombrar es mover dentro de la misma carpeta).
public struct Traslado: Sendable, Hashable, Codable {
    public var de: VaultPath
    public var a: VaultPath
    public init(de: VaultPath, a: VaultPath) { self.de = de; self.a = a }
}

/// Errores al preparar un cambio en bloque, con texto para la persona.
public enum RefactorError: Error, LocalizedError, Sendable, Equatable {
    case noExiste(String)
    case destinoOcupado(String)
    case nombreNoValido(String)
    case dentroDeSiMisma(String)
    case carpetaDeLaApp(String)
    case rutaNoPermitida(String)
    case sinCambios
    case enlacesEnRiesgo(Int)

    public var errorDescription: String? {
        switch self {
        case .noExiste(let p): "No encuentro «\(p)». Puede que se haya movido."
        case .destinoOcupado(let p): "Ya hay algo llamado «\(p)». Elige otro nombre."
        case .nombreNoValido(let n): "«\(n)» no sirve como nombre: no puede estar vacío, empezar por punto ni llevar / : \\ # ^ [ ] |."
        case .dentroDeSiMisma(let p): "No puedo mover «\(p)» dentro de sí misma."
        case .carpetaDeLaApp(let p): "«\(p)» la usa la app para funcionar. Su nombre se cambia desde Ajustes."
        case .rutaNoPermitida(let p): "No puedo mover nada a «\(p)»."
        case .sinCambios: "El nombre nuevo es igual al de ahora."
        case .enlacesEnRiesgo(let n):
            n == 1 ? "Un enlace dejaría de apuntar a su nota. Revísalo antes de seguir."
                : "\(n) enlaces dejarían de apuntar a su nota. Revísalos antes de seguir."
        }
    }
}

/// Un enlace (o una ruta en una tabla o en los ajustes) que cambia.
public struct CambioDeEnlace: Sendable, Hashable {
    public enum Lugar: Sendable, Hashable {
        case cuerpo
        case propiedad(String)
        /// Columna de un CSV.
        case columna(String)
        /// Ajustes de la carpeta (`.tls/…`).
        case ajustes(String)
    }

    public let linea: Int
    public let lugar: Lugar
    public let antes: String
    public let despues: String
}

/// Lo que cambia en un fichero.
public struct CambioDeFichero: Sendable, Hashable {
    /// Ruta antes del cambio.
    public let ruta: VaultPath
    /// Ruta después (la misma si no se mueve).
    public let rutaFinal: VaultPath
    public let enlaces: [CambioDeEnlace]
    /// Nombre anterior que se añade a «Otros nombres» (`aliases`).
    public let alias: String?
}

/// Un enlace que el cambio no puede mantener apuntando a su nota.
public struct ProblemaDeEnlace: Sendable, Hashable {
    public let ruta: VaultPath
    public let linea: Int
    public let enlace: String
    public let motivo: String

    public init(ruta: VaultPath, linea: Int, enlace: String, motivo: String) {
        self.ruta = ruta; self.linea = linea; self.enlace = enlace; self.motivo = motivo
    }
}

/// Vista previa de un cambio en bloque: qué se mueve, qué enlaces cambian y el plan que lo hace
/// (todo o nada, y se deshace de una vez).
public struct RefactorPreview: Sendable {
    public let descripcion: String
    public let traslados: [Traslado]
    /// Ficheros que cambian por dentro o se mueven, en orden de ruta.
    public let cambios: [CambioDeFichero]
    /// Enlaces actualizados en notas (cuerpo y propiedades) y en ajustes.
    public let enlaces: Int
    /// Notas cuyo texto cambia.
    public let notas: Int
    /// Filas de CSV que cambian.
    public let filasCSV: Int
    /// Notas solo en iCloud: no se pueden revisar (si enlazan aquí, se quedarían en la ruta antigua).
    public let sinDescargar: [VaultPath]
    /// Ficheros con un conflicto pendiente que el cambio toca.
    public let enConflicto: [VaultPath]
    /// Ficheros de texto que no son UTF-8: no se revisan.
    public let noEditables: [VaultPath]
    public let problemas: [ProblemaDeEnlace]
    public let plan: WritePlan

    /// «Renombrar "Panadería Sol" actualizará 12 enlaces en 7 notas y 1 fila de CSV».
    public var resumen: String {
        var partes: [String] = []
        if enlaces > 0 { partes.append(Plural.de(enlaces, "enlace", "enlaces") + " en " + Plural.de(notas, "nota", "notas")) }
        if filasCSV > 0 { partes.append(Plural.de(filasCSV, "fila de CSV", "filas de CSV")) }
        if partes.isEmpty { return descripcion + " no cambiará ningún enlace." }
        return descripcion + " actualizará " + Plural.lista(partes) + "."
    }

    /// Aviso tras aplicarlo («Actualicé 12 enlaces en 7 notas»).
    public var avisoHecho: String {
        let total = enlaces + filasCSV
        guard total > 0 else { return "Hecho. No había enlaces que actualizar." }
        return "Actualicé " + Plural.de(total, "enlace", "enlaces") + " en "
            + Plural.de(cambios.filter { !$0.enlaces.isEmpty }.count, "fichero", "ficheros")
    }

    /// `true` si ningún enlace corre peligro.
    public var esSeguro: Bool { problemas.isEmpty }
}

/// Renombrar y mover notas o carpetas actualizando todas las referencias, como Obsidian
/// (SISTEMAS.md §5.2): wikilinks con y sin alias, sección o incrustados; enlaces Markdown
/// relativos desde cualquier carpeta (con `%20`, `<…>`, sin `.md`, con `#sección`); enlaces en
/// propiedades y listas; rutas en columnas de CSV, en propiedades de ruta y en los ajustes
/// (`layout.json`, `privado`, `plantillas.yaml`).
///
/// - Solo cambia el destino de cada enlace: el texto visible y el resto de bytes no.
/// - Garantía: ningún enlace cambia de destino salvo el de lo que se mueve (se comprueba con el
///   resolutor antes de escribir; lo que no se puede mantener sale en `problemas`).
/// - Todo va en un único `WritePlan` (todo o nada) que se deshace de una vez.
public struct LinkRefactor: Sendable {
    public struct Opciones: Sendable {
        public enum Alias: Sendable, Hashable {
            /// Añade el nombre anterior si cambia el nombre que se ve.
            case automatico
            /// Añade siempre el nombre anterior (o el del fichero) si cambia.
            case siempre
            case nunca
        }

        public var autor: Autor
        public var alias: Alias
        /// Cambia también el texto visible si coincidía con el nombre viejo (apagado por defecto).
        public var actualizarTextoVisible: Bool
        /// Columnas de CSV que guardan rutas.
        public var columnasCSV: [String]
        /// Propiedades que guardan una ruta en texto plano.
        public var propiedadesRuta: [String]
        /// Ficheros con un conflicto pendiente (de `ConflictRegistry`), para avisar.
        public var conflictos: [VaultPath]

        public init(autor: Autor = .persona("Manu"), alias: Alias = .automatico, actualizarTextoVisible: Bool = false,
                    columnasCSV: [String] = ["ruta", "documento", "evidencia", "justificante", "pdf"],
                    propiedadesRuta: [String] = ["pdf", "logo", "ubicacion", "evidencia", "documento", "justificante"],
                    conflictos: [VaultPath] = []) {
            self.autor = autor; self.alias = alias; self.actualizarTextoVisible = actualizarTextoVisible
            self.columnasCSV = columnasCSV; self.propiedadesRuta = propiedadesRuta; self.conflictos = conflictos
        }
    }

    public let snapshot: VaultSnapshot

    public init(snapshot: VaultSnapshot) {
        self.snapshot = snapshot
    }

    /// Lee la carpeta (sin descargar nada) y prepara el motor.
    public init(root: URL, excluidas: [VaultPath] = []) {
        self.snapshot = VaultSnapshot.read(root: root, excluded: excluidas)
    }

    // MARK: Órdenes

    /// Cambia el nombre de una nota o carpeta. Si `nombre` no lleva extensión, se conserva la del fichero.
    public func renombrar(_ ruta: VaultPath, a nombre: String, opciones: Opciones = Opciones()) throws -> RefactorPreview {
        guard let real = existing(ruta) else { throw RefactorError.noExiste(ruta.raw) }
        var nuevo = try Self.validName(nombre)
        if !snapshot.isDirectory(real), !Self.hasKnownExtension(nuevo, like: real) {
            let ext = Self.extensionText(of: real)
            if !ext.isEmpty { nuevo += "." + ext }
        }
        let destino = (real.parent ?? .root).appending(nuevo)
        guard destino.raw != real.raw else { throw RefactorError.sinCambios }
        return try preparar([Traslado(de: real, a: destino)], descripcion: "Renombrar «\(nombreVisible(real))»",
                            opciones: opciones)
    }

    /// Mueve una nota o carpeta a otra carpeta (que puede no existir aún).
    public func mover(_ ruta: VaultPath, a carpeta: VaultPath, opciones: Opciones = Opciones()) throws -> RefactorPreview {
        guard let real = existing(ruta) else { throw RefactorError.noExiste(ruta.raw) }
        let destino = carpeta.appending(real.name)
        guard destino.raw != real.raw else { throw RefactorError.sinCambios }
        return try preparar([Traslado(de: real, a: destino)], descripcion: "Mover «\(nombreVisible(real))»",
                            opciones: opciones)
    }

    /// Prepara uno o varios movimientos (en orden) con todos sus enlaces. `extra` son operaciones
    /// que van en el mismo plan, después de los cambios de enlaces y antes de mover (se escriben
    /// sobre las rutas de antes): p. ej. cambiar `numero` al renumerar una tarea.
    public func preparar(_ traslados: [Traslado], descripcion: String? = nil, opciones: Opciones = Opciones(),
                         extra: [WriteOp] = []) throws -> RefactorPreview {
        let moves = try validate(traslados)
        let map = MoveMap(moves: moves.map { ($0.de, $0.a) })
        let newFiles = snapshot.files.map(map.map)
        var newLower: [String: VaultPath] = [:]
        for p in newFiles + snapshot.directories.map(map.map) { newLower[TextFolding.pathKey(p.raw)] = p }
        let ctx = Contexto(snapshot: snapshot, map: map, oldResolver: snapshot.resolver,
                           newResolver: LinkResolver(paths: newFiles), newLower: newLower, opciones: opciones,
                           requested: moves)

        var editOps: [WriteOp] = []
        var aliasOps: [WriteOp] = []
        var cambios: [CambioDeFichero] = []
        var problemas: [ProblemaDeEnlace] = []
        var enlaces = 0, notas = 0, filas = 0
        let aliases = aliasChanges(moves, opciones: opciones)

        let paths = snapshot.textPaths + VaultSnapshot.settingsFiles.filter { snapshot.text($0) != nil }
        for p in paths {
            guard let text = snapshot.text(p), let data = snapshot.data(p) else { continue }
            var result = FileEdits()
            switch p.ext {
            case "md", "markdown":
                ctx.rewriteNote(p, text: text, into: &result)
            case "csv":
                ctx.rewriteCSV(p, text: text, into: &result)
            case "json":
                ctx.rewriteJSON(p, text: text, into: &result)
            case "canvas":
                ctx.rewriteCanvas(p, text: text, into: &result)
            case "yaml", "yml":
                ctx.rewriteYAML(p, text: text, into: &result)
            default:
                break
            }
            problemas += result.problemas
            let alias = aliases[p]
            let moved = map.moves(p)
            if !result.edits.isEmpty {
                editOps.append(.editRanges(p, edits: result.edits, baseHash: ContentHash.of(data)))
                if p.ext == "csv" { filas += result.filas } else {
                    enlaces += result.cambios.count
                    if !p.raw.hasPrefix(".tls/") { notas += 1 }
                }
            }
            if let alias { aliasOps.append(alias.op) }
            if !result.edits.isEmpty || moved || alias != nil {
                cambios.append(CambioDeFichero(ruta: p, rutaFinal: map.map(p), enlaces: result.cambios, alias: alias?.nombre))
            }
        }
        // Lo que se mueve sin texto que leer (PDF, imágenes, notas sin descargar) también sale en la lista.
        let listed = Set(cambios.map(\.ruta))
        for p in snapshot.files where map.moves(p) && !listed.contains(p) {
            cambios.append(CambioDeFichero(ruta: p, rutaFinal: map.map(p), enlaces: [], alias: nil))
        }
        cambios.sort { $0.ruta < $1.ruta }

        let ops = editOps + extra + aliasOps + moves.map { WriteOp.move($0.de, to: $0.a) }
        let desc = descripcion ?? defaultDescription(moves)
        let touched = Set(cambios.map { TextFolding.pathKey($0.ruta.raw) })
        let enConflicto = opciones.conflictos.filter { touched.contains(TextFolding.pathKey($0.raw)) }
        let sinDescargar = snapshot.dataless.filter { snapshot.files.contains($0) && ($0.ext == "md" || $0.ext == "csv") }.sorted()
        let noEditables = snapshot.noEditables.sorted()
        return RefactorPreview(descripcion: desc, traslados: moves, cambios: cambios, enlaces: enlaces, notas: notas,
                               filasCSV: filas, sinDescargar: sinDescargar, enConflicto: enConflicto,
                               noEditables: noEditables, problemas: problemas,
                               plan: WritePlan(autor: opciones.autor, descripcion: desc, ops: ops))
    }

    /// Arregla los enlaces de algo que ya se movió fuera de la app (en Finder): la foto tiene lo movido
    /// en su ruta nueva y los enlaces siguen en la vieja. El plan solo cambia enlaces (no mueve nada).
    /// Si los enlaces ya apuntan a la ruta nueva (lo movió Obsidian), no hay nada que hacer.
    public func arreglarMovimientoExterno(_ traslados: [Traslado], opciones: Opciones = Opciones()) throws -> RefactorPreview {
        for t in traslados {
            guard snapshot.existing(t.a) != nil else { throw RefactorError.noExiste(t.a.raw) }
            if TextFolding.pathKey(t.de.raw) != TextFolding.pathKey(t.a.raw), let ocupado = snapshot.existing(t.de) {
                throw RefactorError.destinoOcupado(ocupado.raw)
            }
        }
        // Vista «de antes»: lo movido vuelve a su ruta vieja.
        let atras = MoveMap(moves: traslados.reversed().map { ($0.a, $0.de) })
        var texts: [VaultPath: VaultSnapshot.Texto] = [:]
        for (p, t) in snapshot.texts { texts[atras.map(p)] = t }
        let files = snapshot.files.map(atras.map).sorted()
        let dirs = snapshot.directories.map(atras.map).sorted()
        var lower: [String: VaultPath] = [:]
        for p in files + dirs { lower[TextFolding.pathKey(p.raw)] = p }
        let antes = VaultSnapshot(root: snapshot.root, layout: snapshot.layout, files: files, directories: dirs,
                                  dataless: Set(snapshot.dataless.map(atras.map)), noEditables: Set(snapshot.noEditables.map(atras.map)),
                                  texts: texts, lowerIndex: lower)
        let nombre = traslados.count == 1 ? "«\(traslados[0].a.stem)»" : Plural.de(traslados.count, "elemento", "elementos")
        let previa = try LinkRefactor(snapshot: antes).preparar(traslados, descripcion: "Arreglar los enlaces de \(nombre)",
                                                                opciones: opciones)
        let adelante = MoveMap(moves: traslados.map { ($0.de, $0.a) })
        let ops: [WriteOp] = previa.plan.ops.compactMap { op in
            switch op {
            case .editRanges(let p, let e, let h): .editRanges(adelante.map(p), edits: e, baseHash: h)
            case .mergeFrontmatter(let p, let s, let u): .mergeFrontmatter(adelante.map(p), set: s, unset: u)
            case .move: nil
            default: op
            }
        }
        return RefactorPreview(descripcion: previa.descripcion, traslados: previa.traslados, cambios: previa.cambios,
                               enlaces: previa.enlaces, notas: previa.notas, filasCSV: previa.filasCSV,
                               sinDescargar: previa.sinDescargar, enConflicto: previa.enConflicto,
                               noEditables: previa.noEditables, problemas: previa.problemas,
                               plan: WritePlan(autor: opciones.autor, descripcion: previa.descripcion, ops: ops))
    }

    /// Al crear notas nuevas: los enlaces que ya existían y que, por el nombre repetido, irían a otra nota
    /// (o quedarían ambiguos) se reescriben con su ruta, con el mismo motor que al renombrar. Van en el mismo
    /// plan que la creación. `[]` si ningún nombre se repite.
    public func protegerEnlaces(alCrear nuevas: [VaultPath], opciones: Opciones = Opciones()) -> [WriteOp] {
        let claves = Set(nuevas.map { TextFolding.nameKey($0.name) } + nuevas.map { TextFolding.nameKey($0.stem) })
        guard snapshot.files.contains(where: { claves.contains(TextFolding.nameKey($0.name)) || claves.contains(TextFolding.nameKey($0.stem)) })
        else { return [] }
        let files = snapshot.files + nuevas
        var lower: [String: VaultPath] = [:]
        for p in files + snapshot.directories { lower[TextFolding.pathKey(p.raw)] = p }
        let ctx = Contexto(snapshot: snapshot, map: MoveMap(moves: []), oldResolver: snapshot.resolver,
                           newResolver: LinkResolver(paths: files), newLower: lower, opciones: opciones, requested: [])
        var ops: [WriteOp] = []
        for p in snapshot.notes {
            guard let text = snapshot.text(p), let data = snapshot.data(p) else { continue }
            var r = FileEdits()
            ctx.rewriteNote(p, text: text, into: &r)
            if !r.edits.isEmpty { ops.append(.editRanges(p, edits: r.edits, baseHash: ContentHash.of(data))) }
        }
        return ops
    }

    /// Aplica una vista previa. Si algún enlace corre peligro, no escribe nada salvo que se pida.
    @discardableResult
    public static func aplicar(_ preview: RefactorPreview, con bus: CommandBus,
                               aunqueHayaProblemas: Bool = false) async throws -> WriteResult {
        if !preview.problemas.isEmpty, !aunqueHayaProblemas {
            throw RefactorError.enlacesEnRiesgo(preview.problemas.count)
        }
        return try await bus.ejecutar(preview.plan)
    }

    /// Ruta real de una nota o carpeta (una nota se puede nombrar sin `.md`).
    func existing(_ ruta: VaultPath) -> VaultPath? {
        if let p = snapshot.existing(ruta) { return p }
        return ruta.ext.isEmpty ? snapshot.existing(VaultPath(ruta.raw + ".md")) : nil
    }

    // MARK: Validación

    /// Nombre válido para un fichero o carpeta (NFC, sin espacios alrededor).
    static func validName(_ raw: String) throws -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        // Como Obsidian: `\ / :` no valen en un nombre y con `# ^ [ ] |` los enlaces dejan de funcionar.
        guard !n.isEmpty, n != ".", n != "..", !n.hasPrefix("."), !n.contains(where: { "/:\\#^[]|".contains($0) }),
              !n.contains(where: { $0.isNewline || $0.unicodeScalars.contains { $0.value < 0x20 } }),
              n.utf8.count <= 255 else { throw RefactorError.nombreNoValido(raw) }
        return n
    }

    static func extensionText(of p: VaultPath) -> String {
        let n = p.name
        guard let dot = n.lastIndex(of: "."), dot != n.startIndex else { return "" }
        return String(n[n.index(after: dot)...])
    }

    /// `true` si `nombre` ya termina en la extensión del fichero.
    static func hasKnownExtension(_ nombre: String, like p: VaultPath) -> Bool {
        let ext = extensionText(of: p)
        return !ext.isEmpty && nombre.lowercased().hasSuffix("." + ext.lowercased())
    }

    /// Comprueba los movimientos sobre una vista que avanza con cada uno.
    func validate(_ traslados: [Traslado]) throws -> [Traslado] {
        guard !traslados.isEmpty else { throw RefactorError.sinCambios }
        var out: [Traslado] = []
        let layout = snapshot.layout
        let protected = [VaultPath(layout.archivo)] + (layout.buzon.map { [VaultPath($0)] } ?? [])
        // La vista actual (rutas de la foto tras lo ya movido), al día con cada traslado: un fichero cambia una entrada;
        // una carpeta, lo que cuelga de ella. Así miles de traslados (una importación) no rehacen el mapa cada vez.
        var currentFiles: [String: VaultPath] = [:]
        var currentDirs: [String: VaultPath] = [:]
        for p in snapshot.files { currentFiles[TextFolding.pathKey(p.raw)] = p }
        for p in snapshot.directories { currentDirs[TextFolding.pathKey(p.raw)] = p }
        func mover(_ src: VaultPath, _ dst: VaultPath) {
            func rebase(_ e: inout [String: VaultPath]) {
                for (k, v) in e where MoveMap.isUnder(v, src) {
                    e.removeValue(forKey: k)
                    let n = VaultPath(components: dst.components + Array(v.components.dropFirst(src.components.count)))
                    e[TextFolding.pathKey(n.raw)] = n
                }
            }
            let k = TextFolding.pathKey(src.raw)
            if currentDirs[k] == nil, currentFiles[k] != nil {
                currentFiles.removeValue(forKey: k)
                currentFiles[TextFolding.pathKey(dst.raw)] = dst
            } else {
                rebase(&currentFiles)
                rebase(&currentDirs)
            }
        }
        func actual(_ k: String) -> VaultPath? { currentDirs[k] ?? currentFiles[k] }
        for t in traslados {
            guard let src = actual(TextFolding.pathKey(t.de.raw)) else { throw RefactorError.noExiste(t.de.raw) }
            let dst = t.a
            guard !dst.isRoot else { throw RefactorError.rutaNoPermitida(dst.raw) }
            for c in dst.components { _ = try Self.validName(c) }
            if protected.contains(where: { TextFolding.pathKey($0.raw) == TextFolding.pathKey(src.raw) }) {
                throw RefactorError.carpetaDeLaApp(src.raw)
            }
            if src.raw == dst.raw { throw RefactorError.sinCambios }
            let sameKey = TextFolding.pathKey(src.raw) == TextFolding.pathKey(dst.raw)
            if !sameKey {
                if MoveMap.isUnder(dst, src) { throw RefactorError.dentroDeSiMisma(src.raw) }
                if let busy = actual(TextFolding.pathKey(dst.raw)) { throw RefactorError.destinoOcupado(busy.raw) }
                // Ninguna carpeta del camino puede ser un fichero.
                var parent = dst.parent
                while let a = parent, !a.isRoot {
                    if let hit = currentFiles[TextFolding.pathKey(a.raw)] { throw RefactorError.destinoOcupado(hit.raw) }
                    parent = a.parent
                }
            }
            out.append(Traslado(de: src, a: dst))
            mover(src, dst)
        }
        return out
    }

    // MARK: Nombres y alias

    func nombreVisible(_ p: VaultPath) -> String {
        if let t = snapshot.text(p), p.ext == "md" || p.ext == "markdown" {
            return NoteDocument(text: t).title(fileStem: p.stem)
        }
        return snapshot.isDirectory(p) ? p.name : p.stem
    }

    func defaultDescription(_ moves: [Traslado]) -> String {
        guard moves.count == 1, let m = moves.first else { return "Mover " + Plural.de(moves.count, "elemento", "elementos") }
        return m.de.parent == m.a.parent ? "Renombrar «\(nombreVisible(m.de))»" : "Mover «\(nombreVisible(m.de))»"
    }

    struct AliasChange { var nombre: String; var op: WriteOp }

    /// El nombre anterior pasa a «Otros nombres» cuando cambia el nombre que se ve (SISTEMAS.md §5.2).
    func aliasChanges(_ moves: [Traslado], opciones: Opciones) -> [VaultPath: AliasChange] {
        guard opciones.alias != .nunca else { return [:] }
        var out: [VaultPath: AliasChange] = [:]
        for m in moves where m.de.ext == "md" || m.de.ext == "markdown" {
            // Solo las rutas de la foto (lo movido antes en el mismo plan ya no está en ella).
            guard let text = snapshot.text(m.de) else { continue }
            let note = NoteDocument(text: text)
            let before = note.title(fileStem: m.de.stem)
            let after = note.title(fileStem: m.a.stem)
            var candidate: String?
            if before != after { candidate = before }
            else if opciones.alias == .siempre, m.de.stem != m.a.stem, m.de.stem != after { candidate = m.de.stem }
            guard let name = candidate else { continue }
            let doc = FrontmatterDocument(text: text)
            var list: [String] = []
            switch doc.value("aliases") {
            case .list(let l)?: list = l
            case .text(let t)?: list = [t]
            default: break
            }
            guard !list.contains(name) else { continue }
            out[m.de] = AliasChange(nombre: name, op: .mergeFrontmatter(m.de, set: [Property(key: "aliases", value: .list(list + [name]))], unset: []))
        }
        return out
    }
}

/// Cambios calculados para un fichero.
struct FileEdits {
    var edits: [TextEdit] = []
    var cambios: [CambioDeEnlace] = []
    var problemas: [ProblemaDeEnlace] = []
    var filas = 0
}

/// Plurales sencillos para los avisos.
enum Plural {
    static func de(_ n: Int, _ uno: String, _ varios: String) -> String {
        n == 1 ? "1 \(uno)" : "\(n) \(varios)"
    }

    static func lista(_ partes: [String]) -> String {
        guard partes.count > 1 else { return partes.first ?? "" }
        return partes.dropLast().joined(separator: ", ") + " y " + partes.last!
    }
}
