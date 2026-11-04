import Foundation

/// Lo que se pide al crear una tarea.
public struct NuevaTarea: Sendable {
    public var titulo: String
    /// Área (si no hay proyecto). Por defecto, la del proyecto o la oportunidad, o Dirección.
    public var area: AreaCode?
    /// `Proyecto.md` del proyecto: la tarea nace en su carpeta `Tareas/`.
    public var proyecto: VaultPath?
    public var oportunidad: VaultPath?
    public var empresa: VaultPath?
    /// `Manu`, otra persona o `agente:<slug>`.
    public var responsable: String?
    public var estado: EstadoTarea?
    public var prioridad: String?
    /// `tarea`, `pregunta` o `decision`.
    public var tipo: String?
    public var planificada: LocalDate?
    public var vence: LocalDate?
    public var descripcion: String?
    /// `manual`, `rutina:<id>`, `regla:<evento>`, `agente:<slug>`, `importacion`.
    public var origen: String?
    /// Plantilla (`tarea`, `pregunta-asistente`, `decision-1-3-1`…).
    public var plantilla: String
    public var autor: Autor
    /// Propiedades extra (`capacidad`, `fecha_corte`…).
    public var propiedades: [Property]

    public init(titulo: String, area: AreaCode? = nil, proyecto: VaultPath? = nil, oportunidad: VaultPath? = nil,
                empresa: VaultPath? = nil, responsable: String? = nil, estado: EstadoTarea? = nil, prioridad: String? = nil,
                tipo: String? = nil, planificada: LocalDate? = nil, vence: LocalDate? = nil, descripcion: String? = nil,
                origen: String? = nil, plantilla: String = "tarea", autor: Autor = .persona("Manu"), propiedades: [Property] = []) {
        self.titulo = titulo; self.area = area; self.proyecto = proyecto; self.oportunidad = oportunidad
        self.empresa = empresa; self.responsable = responsable; self.estado = estado; self.prioridad = prioridad
        self.tipo = tipo; self.planificada = planificada; self.vence = vence; self.descripcion = descripcion
        self.origen = origen; self.plantilla = plantilla; self.autor = autor; self.propiedades = propiedades
    }
}

/// La ruta manda: lo que habría que corregir en la ficha según dónde vive.
public struct CorreccionDeUbicacion: Sendable, Hashable {
    public let tarea: VaultPath
    /// Proyecto que dice la carpeta (`nil`: la tarea está fuera de un proyecto).
    public let proyecto: VaultPath?
    public let poner: [Property]
    public let quitar: [String]
    public let motivo: String
}

public enum TareaError: Error, LocalizedError, Sendable, Equatable {
    case noEsTarea(String)
    case tituloVacio
    case noPermitidoAgente(String)
    case sinCambios

    public var errorDescription: String? {
        switch self {
        case .noEsTarea(let p): "«\(p)» no es una ficha de tarea."
        case .tituloVacio: "La tarea necesita un título."
        case .noPermitidoAgente(let e): "Un asistente no puede dejar una tarea en «\(e)»: la deja en revisión y decides tú."
        case .sinCambios: "La tarea ya está así."
        }
    }
}

/// Las fichas de tarea de una carpeta (una ficha por tarea, PLAN §4.2 con las relaciones de SISTEMAS.md).
///
/// - Cambiar de estado nunca mueve el fichero.
/// - El número sale de `.tls/secuencias.json`, ajustado al mayor visto; renumerar renombra el fichero
///   en la misma operación (con todos sus enlaces).
/// - La Actividad solo crece.
public struct TaskStore: Sendable {
    public let snapshot: VaultSnapshot
    public let tareas: [Tarea]
    public let reloj: Reloj

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.snapshot = snapshot
        self.reloj = reloj ?? Reloj.deCarpeta(snapshot)
        let resolver = snapshot.resolver
        let ids = snapshot.idIndex()
        self.tareas = snapshot.notes.filter { Self.esRutaDeTarea($0, layout: snapshot.layout) }
            .compactMap { Self.leer($0, snapshot: snapshot, resolver: resolver, ids: ids) }
    }

    /// `…/Tareas/t-NNNN-….md` fuera de las plantillas y del Archivo.
    public static func esRutaDeTarea(_ p: VaultPath, layout: VaultLayout) -> Bool {
        guard p.ext == "md", let parent = p.parent, TextFolding.nameKey(parent.name) == TextFolding.nameKey(layout.tareas),
              !VaultSnapshot.isTemplatePath(p), !layout.isArchived(p) else { return false }
        return TareaArchivo.numero(deNombre: p.name) != nil
    }

    static func leer(_ p: VaultPath, snapshot: VaultSnapshot, resolver: LinkResolver, ids: [String: VaultPath]) -> Tarea? {
        guard let text = snapshot.text(p) else { return nil }
        let doc = NoteDocument(text: text)
        let fm = doc.frontmatter
        func texto(_ k: String) -> String? { fm.properties.first(where: { $0.key == k })?.value.displayText.nilIfEmpty }
        func fecha(_ k: String) -> LocalDate? { texto(k).flatMap { LocalDate(parsing: $0) } }
        func relacion(_ k: String) -> VaultPath? {
            for key in [k, k + "_id"] {
                guard let v = texto(key) else { continue }
                if let r = ContextoPlantilla.resolve(v, from: p, resolver: resolver, ids: { ids[$0.lowercased()] }) { return r }
            }
            return nil
        }
        let numeroTexto = texto("numero")
        let n = numeroTexto.flatMap { Secuencias.captura($0, #"^T-(\d+)$"#) } ?? TareaArchivo.numero(deNombre: p.name)
        let estadoTexto = texto("estado")
        return Tarea(ruta: p, uid: texto("id"), numero: numeroTexto ?? n.map { String(format: "T-%04d", $0) }, numeroEntero: n,
                     titulo: texto("titulo") ?? doc.title(fileStem: p.stem), estado: estadoTexto.flatMap { EstadoTarea(leyendo: $0) },
                     estadoTexto: estadoTexto, prioridad: texto("prioridad"), tipo: texto("tipo"), responsable: texto("responsable"),
                     planificada: fecha("planificada"), vence: fecha("vence"), despertar: fecha("despertar"),
                     area: snapshot.layout.area(of: p), proyecto: relacion("proyecto"),
                     proyectoPorRuta: proyectoDeCarpeta(p, snapshot: snapshot), oportunidad: relacion("oportunidad"),
                     empresa: relacion("empresa"), creada: fecha("creada"), cerrada: fecha("cerrada"), origen: texto("origen"))
    }

    /// `…/Proyectos/<slug>/Tareas/x.md` → `…/Proyectos/<slug>/Proyecto.md` (si existe).
    static func proyectoDeCarpeta(_ p: VaultPath, snapshot: VaultSnapshot) -> VaultPath? {
        let c = p.components
        guard c.count >= 4, TextFolding.nameKey(c[c.count - 4]) == TextFolding.nameKey(snapshot.layout.proyectos) else { return nil }
        let carpeta = VaultPath(components: Array(c.prefix(c.count - 2)))
        return snapshot.existing(carpeta.appending("Proyecto.md"))
    }

    public func tarea(_ ruta: VaultPath) -> Tarea? {
        let k = TextFolding.pathKey(ruta.raw)
        return tareas.first { TextFolding.pathKey($0.ruta.raw) == k }
    }

    /// Carpeta donde nace una tarea: la del proyecto o `N · Área/Tareas/`.
    public func carpeta(area: AreaCode, proyecto: VaultPath?) -> VaultPath {
        if let p = proyecto, let dir = p.parent { return dir.appending(snapshot.layout.tareas) }
        return snapshot.layout.areaFolder(area).appending(snapshot.layout.tareas)
    }

    /// Siguiente número: `max(contador, mayor número visto) + 1`.
    public func siguienteNumero() -> Int {
        max(Secuencias.leer(snapshot)["tarea"] ?? 0, tareas.compactMap(\.numeroEntero).max() ?? 0,
            Secuencias.mayorVisto("tarea", año: reloj.hoy.year, en: snapshot)) + 1
    }

    // MARK: Crear

    /// Prepara la ficha nueva (`…/Tareas/t-NNNN-slug.md`) con la plantilla de tarea. El plan crea la
    /// nota y sube el contador de `.tls/secuencias.json`; nada más.
    public func crear(_ nueva: NuevaTarea) throws -> PlantillaMotor.NotaPreparada {
        let titulo = nueva.titulo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !titulo.isEmpty else { throw TareaError.tituloVacio }
        let motor = PlantillaMotor(snapshot: snapshot, opciones: .init(yo: nueva.autor.etiqueta, reloj: reloj))
        let area = nueva.area ?? nueva.proyecto.flatMap { snapshot.layout.area(of: $0) }
            ?? nueva.oportunidad.flatMap { snapshot.layout.area(of: $0) } ?? .direccion
        let n = siguienteNumero()
        var valores: [String: String] = ["titulo": titulo, "numero": String(format: "T-%04d", n),
                                         "slug": NombresDeFicha.slug(titulo, maximo: TareaArchivo.maximoSlug)]
        if let r = nueva.responsable { valores["responsable"] = r }
        var contexto: [String: VaultPath] = [:]
        if let p = nueva.proyecto { contexto["proyecto"] = p }
        if let o = nueva.oportunidad { contexto["oportunidad"] = o }
        if let e = nueva.empresa { contexto["empresa"] = e }
        var poner: [Property] = []
        if let e = nueva.estado { poner.append(Property(key: "estado", value: .text(e.rawValue))) }
        if let p = nueva.prioridad { poner.append(Property(key: "prioridad", value: .text(p))) }
        if let t = nueva.tipo { poner.append(Property(key: "tipo", value: .text(t))) }
        if let d = nueva.planificada { poner.append(Property(key: "planificada", value: .text(Tarea.laborable(d).description))) }
        if let d = nueva.vence { poner.append(Property(key: "vence", value: .text(d.description))) }
        if let o = nueva.origen { poner.append(Property(key: "origen", value: .text(o))) }
        poner += nueva.propiedades
        var secciones: [String: String] = [:]
        if let d = nueva.descripcion, !d.isEmpty { secciones["Descripción"] = d }
        let peticion = PlantillaMotor.Peticion(plantilla: nueva.plantilla, contexto: contexto, valores: valores, poner: poner,
                                               secciones: secciones, area: area,
                                               carpeta: carpeta(area: area, proyecto: nueva.proyecto), autor: nueva.autor)
        var nota = try motor.preparar(peticion)
        // El contador lo pone la tienda (también cuenta las tareas ya escritas).
        var ops = nota.plan.ops.filter { TextFolding.pathKey($0.path.raw) != TextFolding.pathKey(Secuencias.ruta.raw) }
        if let op = Secuencias.op(["tarea": n], en: snapshot) { ops.append(op) }
        nota = PlantillaMotor.NotaPreparada(ruta: nota.ruta, texto: nota.texto, titulo: nota.titulo, numero: nota.numero,
                                            faltan: nota.faltan, cursor: nota.cursor,
                                            plan: WritePlan(autor: nueva.autor, descripcion: "Crear la tarea «\(titulo)»", ops: ops))
        return nota
    }

    // MARK: Estado y actividad

    /// Cambia el estado (esa propiedad y `cerrada`) y lo apunta en la Actividad. Nunca mueve el fichero.
    /// Con `soloEstado` (arrastrar en el tablero) cambia solo la línea `estado`.
    /// Ningún asistente pone Hecha ni Cancelada.
    public func cambiarEstado(_ t: Tarea, a nuevo: EstadoTarea, autor: Autor, persona: String = "Manu",
                              nota: String? = nil, soloEstado: Bool = false) throws -> WritePlan {
        if case .agente = autor, nuevo.cerrada { throw TareaError.noPermitidoAgente(nuevo.rawValue) }
        guard t.estado != nuevo else { throw TareaError.sinCambios }
        if soloEstado {
            return WritePlan(autor: autor, descripcion: "«\(t.titulo)»: \(nuevo.rawValue)",
                             ops: [.mergeFrontmatter(t.ruta, set: [Property(key: "estado", value: .text(nuevo.rawValue))], unset: [])])
        }
        var poner = [Property(key: "estado", value: .text(nuevo.rawValue))]
        var quitar: [String] = []
        if nuevo.cerrada { poner.append(Property(key: "cerrada", value: .text(reloj.hoy.description))) }
        else if t.cerrada != nil { quitar.append("cerrada") }
        let de = t.estadoTexto ?? "sin estado"
        let texto = "Estado: \(de) → \(nuevo.rawValue)." + (nota.map { " " + $0 } ?? "")
        let evento: [String: String] = ["tipo": "estado", "de": de, "a": nuevo.rawValue]
        var (ops, porLaApp) = try actividadOps(t.ruta, autor: autor, persona: persona, texto: texto, evento: evento)
        ops.insert(.mergeFrontmatter(t.ruta, set: poner, unset: quitar), at: ops.count - 1)
        return WritePlan(autor: porLaApp ? .sistema : autor, descripcion: "«\(t.titulo)»: \(nuevo.rawValue)", ops: ops)
    }

    /// Añade una entrada a la Actividad (`### AAAA-MM-DD HH:MM · autor`). Si alguien escribió debajo
    /// de la última entrada sin encabezado (en Obsidian), primero se le pone encima su encabezado,
    /// sin tocar su texto. Ese encabezado lo pone la app: si la entrada es de un asistente, el plan
    /// va a nombre del sistema (los asistentes solo pueden añadir).
    public func anadirActividad(_ t: Tarea, autor: Autor, texto: String, evento: [String: String]? = nil,
                                persona: String = "Manu") throws -> WritePlan {
        let (ops, porLaApp) = try actividadOps(t.ruta, autor: autor, persona: persona, texto: texto, evento: evento ?? ["tipo": "comentario"])
        return WritePlan(autor: porLaApp ? .sistema : autor, descripcion: "Actividad en «\(t.titulo)»", ops: ops)
    }

    /// Operaciones de una entrada de Actividad y si hace falta que escriba la app (encabezado de un comentario suelto).
    func actividadOps(_ ruta: VaultPath, autor: Autor, persona: String, texto: String,
                      evento: [String: String]) throws -> ([WriteOp], porLaApp: Bool) {
        guard let text = snapshot.text(ruta), let data = snapshot.data(ruta) else { throw TareaError.noEsTarea(ruta.raw) }
        var ops: [WriteOp] = []
        var porLaApp = false
        let encabezado = "### \(reloj.hoy) \(reloj.hora) · "
        if let offset = Self.comentarioSinEncabezado(text) {
            if case .agente = autor { porLaApp = true }
            let eol = TextLines.dominantEOL(text)
            ops.append(.editRanges(ruta, edits: [TextEdit(offset: offset, length: 0, replacement: encabezado + persona + eol)],
                                   baseHash: ContentHash.of(data)))
        }
        // F4 · corrector (R3): el texto de un asistente nunca lleva encabezados ni comentarios de la app (no puede
        // escribir «como Manu» ni cerrar su propia entrada para que lo siguiente parezca escrito a mano).
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        var entrada = encabezado + autor.etiqueta + "\n" + (autor.esAgente ? TextoDeAsistente.neutralizar(limpio) : limpio)
        entrada += "\n" + Self.comentarioEvento(evento)
        ops.append(.appendToSection(ruta, section: "Actividad", text: entrada, blankLine: true))
        return (ops, porLaApp)
    }

    /// `<!-- tls:evento {…} -->`, con un id nuevo y escapado para que no cierre el comentario.
    static func comentarioEvento(_ campos: [String: String]) -> String {
        var c = campos
        if c["id"] == nil { c["id"] = "ev-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(6)) }
        let data = (try? JSONSerialization.data(withJSONObject: c, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "-->", with: "--\\u003e").replacingOccurrences(of: "<!--", with: "\\u003c!--")
        return "<!-- tls:evento \(json) -->"
    }

    /// Desplazamiento (bytes) del texto escrito sin encabezado tras la última entrada de Actividad, o `nil`.
    static func comentarioSinEncabezado(_ text: String) -> Int? {
        let b = Array(text.utf8)
        let ls = LinkScanner.lines(b)
        let bodyStart = LinkScanner.frontmatter(b, ls).map { $0.closing + 1 } ?? 0
        // Sección Actividad: de su encabezado al siguiente `##` (o `#`).
        var start: Int?
        var end = ls.count
        var fence: CodeFence?
        for i in bodyStart..<max(bodyStart, ls.count) {
            let line = String(decoding: b[ls[i].start..<ls[i].end], as: UTF8.self)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let f = fence { if f.closes(trimmed) { fence = nil }; continue }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            if let h = MarkdownSections.heading(line) {
                if start == nil, h.level == 2, TextFolding.fold(h.title) == "actividad" { start = i + 1; continue }
                if start != nil, h.level <= 2 { end = i; break }
            }
        }
        guard let s = start, s < end else { return nil }
        // Último límite: un encabezado de entrada (`###`), un evento o el marcador/guía del principio.
        var limite: (Int, esEncabezado: Bool)?
        for i in stride(from: end - 1, through: s, by: -1) {
            let line = String(decoding: b[ls[i].start..<ls[i].end], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("### ") { limite = (i, true); break }
            if line.hasPrefix("<!-- tls:evento") || line.hasPrefix("<!-- tls:actividad") || line.hasPrefix("> Guía:") {
                limite = (i, false); break
            }
        }
        if let l = limite, l.esEncabezado { return nil }
        let desde = (limite?.0 ?? s - 1) + 1
        for i in desde..<end {
            let line = String(decoding: b[ls[i].start..<ls[i].end], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("> Guía:") || line.hasPrefix("<!--") { continue }
            return ls[i].start
        }
        return nil
    }

    // MARK: Números

    /// Tareas con el mismo número (cada grupo, en orden: la más antigua primero).
    public func duplicados() -> [[Tarea]] {
        // Lo privado no se ofrece para renumerar (integración F2): ni se enseña ni se toca.
        let grupos = Dictionary(grouping: tareas.filter { $0.numeroEntero != nil && !snapshot.layout.isPrivate($0.ruta) },
                                by: { $0.numeroEntero! })
        return grupos.values.filter { $0.count > 1 }
            .map { $0.sorted { ($0.creada ?? LocalDate(year: 9999, month: 1, day: 1)!, $0.ruta) < ($1.creada ?? LocalDate(year: 9999, month: 1, day: 1)!, $1.ruta) } }
            .sorted { $0[0].numeroEntero! < $1[0].numeroEntero! }
    }

    /// Renumera tareas: número nuevo y fichero renombrado en la misma operación, con todos sus enlaces.
    public func renumerar(_ lista: [Tarea], autor: Autor = .persona("Manu")) throws -> RefactorPreview {
        var n = siguienteNumero()
        var traslados: [Traslado] = []
        var extra: [WriteOp] = []
        for t in lista {
            let nuevo = (t.ruta.parent ?? .root).appending(TareaArchivo.nombre(numero: n, slug: TareaArchivo.slug(deNombre: t.ruta.name)))
            traslados.append(Traslado(de: t.ruta, a: nuevo))
            extra.append(.mergeFrontmatter(t.ruta, set: [Property(key: "numero", value: .text(String(format: "T-%04d", n)))], unset: []))
            n += 1
        }
        if let op = Secuencias.op(["tarea": n - 1], en: snapshot) { extra.append(op) }
        let desc = lista.count == 1 ? "Renumerar «\(lista[0].titulo)»" : "Renumerar " + Plural.de(lista.count, "tarea", "tareas")
        return try LinkRefactor(snapshot: snapshot).preparar(traslados, descripcion: desc,
                                                             opciones: .init(autor: autor, alias: .nunca), extra: extra)
    }

    /// Renumera las repetidas (se queda con su número la más antigua de cada grupo). `nil` si no hay.
    public func resolverDuplicados(autor: Autor = .persona("Manu")) throws -> RefactorPreview? {
        let repetidas = duplicados().flatMap { $0.dropFirst() }
        return repetidas.isEmpty ? nil : try renumerar(repetidas, autor: autor)
    }

    // MARK: Ubicación

    /// Si una ficha se movió en Finder, la ruta manda: dentro de `Proyectos/<slug>/Tareas/`, su
    /// `proyecto` es ese; fuera de un proyecto, no tiene proyecto.
    public func correccionesDeUbicacion() -> [CorreccionDeUbicacion] {
        var out: [CorreccionDeUbicacion] = []
        for t in tareas {
            let fm = snapshot.frontmatter(t.ruta)
            let tieneLegado = fm.properties.contains { $0.key == "proyecto_id" && !$0.value.displayText.isEmpty }
            if let p = t.proyectoPorRuta {
                guard t.proyecto != p || tieneLegado else { continue }
                let nombre = ContextoPlantilla.nota(p, snapshot: snapshot)?.nombre ?? p.parent?.name ?? p.stem
                let enlace = NombresDeFicha.wikilink(p, nombre: nombre, en: snapshot)
                out.append(CorreccionDeUbicacion(tarea: t.ruta, proyecto: p, poner: [Property(key: "proyecto", value: .text(enlace))],
                                                 quitar: tieneLegado ? ["proyecto_id"] : [],
                                                 motivo: "Está en la carpeta del proyecto «\(nombre)»."))
            } else if t.proyecto != nil {
                let quitar = ["proyecto", "proyecto_id"].filter { k in fm.properties.contains { $0.key == k } }
                out.append(CorreccionDeUbicacion(tarea: t.ruta, proyecto: nil, poner: [], quitar: quitar,
                                                 motivo: "Ya no está en la carpeta de ningún proyecto."))
            }
        }
        return out
    }

    /// Plan con las correcciones aceptadas (solo propiedades).
    public func corregir(_ lista: [CorreccionDeUbicacion], autor: Autor = .persona("Manu")) -> WritePlan? {
        let ops = lista.map { WriteOp.mergeFrontmatter($0.tarea, set: $0.poner, unset: $0.quitar) }
        return ops.isEmpty ? nil : WritePlan(autor: autor, descripcion: "Corregir el proyecto de " + Plural.de(ops.count, "tarea", "tareas"), ops: ops)
    }
}
