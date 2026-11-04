import Foundation

// Por aquí escribe un asistente (lo usa `tls-mcp`): el Autorizador decide y, según su respuesta, el plan se escribe
// (`CommandBus`, `Autor.agente`), se convierte en propuesta (modo asistido: tarea `tipo: decision` para ti con el plan
// guardado), en una tarea para una persona (modo manual), pide aprobación (acción externa) o se deniega. Las propuestas
// se aplican como persona al elegir.

/// Lo que pasó con lo que pidió un asistente.
public enum ResultadoGobernado: Sendable {
    case escrito(WriteResult, DecisionAutorizacion)
    case propuesta(Propuesta, tarea: VaultPath, DecisionAutorizacion)
    case tareaParaPersona(VaultPath, DecisionAutorizacion)
    /// Sale de la empresa: hay que preparar un borrador y pedir la aprobación (`Aprobaciones.solicitar`).
    case aprobacionRequerida(DecisionAutorizacion)
    /// Denegado, no encontrado o solo lectura.
    case denegado(DecisionAutorizacion)

    public var decision: DecisionAutorizacion {
        switch self {
        case .escrito(_, let d), .propuesta(_, _, let d), .tareaParaPersona(_, let d), .aprobacionRequerida(let d), .denegado(let d): d
        }
    }

    /// Lo que se le dice al asistente.
    public var respuestaParaAsistente: String {
        switch self {
        case .escrito: "hecho"
        case .propuesta(let p, _, _): "queda como propuesta para la persona (\(p.id))"
        case .tareaParaPersona(let r, _): "queda como tarea para la persona: \(r.stem)"
        case .aprobacionRequerida: "aprobación requerida"
        case .denegado(let d): d.respuestaParaAsistente
        }
    }
}

public actor EscrituraDeAsistente {
    public nonisolated let bus: CommandBus
    public nonisolated let autorizador: Autorizador
    public nonisolated let propuestas: AlmacenPropuestas
    /// Quién decide las propuestas y recibe las tareas (`titular`, «Manu»).
    public nonisolated let persona: String
    nonisolated let foto: @Sendable () -> VaultSnapshot

    public init(bus: CommandBus, autorizador: Autorizador, persona: String = "Manu",
                snapshot: (@Sendable () -> VaultSnapshot)? = nil) {
        self.bus = bus
        self.autorizador = autorizador
        self.propuestas = AlmacenPropuestas(estado: autorizador.estado)
        self.persona = persona
        let writer = bus.writer
        self.foto = snapshot ?? { VaultSnapshot.read(entry: writer.entry, root: writer.root) }
    }

    /// Escribe (o convierte) lo que pide un asistente. `solicitud` añade lo que sabe quien llama (la función, el
    /// origen de una decisión, la acción externa); lo demás sale del propio plan.
    ///
    /// `asistente`: para un plan que `TaskStore` puso a nombre de la app porque lleva el encabezado de un comentario
    /// escrito a mano (`anadirActividad`, `cambiarEstado`). Se decide como si lo escribiera ese asistente; si se
    /// permite, se escribe tal cual.
    public func escribir(_ plan: WritePlan, asistente: String? = nil, solicitud: SolicitudAutorizacion? = nil,
                         ejecucion: ContextoEjecucion? = nil) async throws -> ResultadoGobernado {
        let slug: String
        if case .agente(let s) = plan.autor {
            slug = s
        } else if plan.autor == .sistema, let a = asistente {
            slug = a
        } else {
            let d = DecisionAutorizacion(resultado: .denegado, paso: 2, motivo: "Por aquí solo escriben los asistentes.",
                                         solicitud: solicitud ?? SolicitudAutorizacion(autor: plan.autor, tipo: .fichaEditar))
            return .denegado(d)
        }
        // El contador de `.tls/secuencias.json` (al crear tareas) es cosa de la app: se escribe aparte, como sistema.
        let (propio, contador) = Self.separarContador(plan)
        var comoAsistente = propio
        comoAsistente.autor = .agente(slug)
        let d = autorizador.decidir(plan: comoAsistente, solicitud: solicitud, ejecucion: ejecucion)
        switch d.resultado {
        case .permitido:
            if propio.autor != comoAsistente.autor { _ = autorizador.consumirPermiso(comoAsistente) }
            let r = try await bus.ejecutar(propio)
            if r.hecho, let c = contador {
                _ = try? await bus.ejecutar(WritePlan(autor: .sistema, descripcion: "Contador de tareas", ops: [c]))
            }
            return .escrito(r, d)
        case .propuesta:
            let (p, t) = try await proponer(comoAsistente, agente: slug, ejecucion: ejecucion?.id ?? solicitud?.ejecucion?.id,
                                            capacidad: d.solicitud.capacidadEfectiva, motivo: d.motivo)
            return .propuesta(p, tarea: t, d)
        case .tareaParaPersona:
            let t = try await tareaParaPersona(comoAsistente, agente: slug, capacidad: d.solicitud.capacidadEfectiva)
            return .tareaParaPersona(t, d)
        case .requiereAprobacion:
            return .aprobacionRequerida(d)
        case .denegado, .noEncontrado, .soloLectura:
            return .denegado(d)
        }
    }

    // MARK: Propuestas

    /// Guarda el plan y crea la tarea de decisión para la persona (la escribe la app).
    public func proponer(_ plan: WritePlan, agente: String, ejecucion: String?, capacidad: String?, clase: Propuesta.Clase = .propuesta,
                         problema: String? = nil, porque: String? = nil, motivo: String? = nil) async throws -> (Propuesta, VaultPath) {
        let id = AlmacenPropuestas.nuevoID()
        let snapshot = foto()
        let nombre = AsistenteConfigurado.nombre(de: agente)
        let area = plan.ops.lazy.compactMap { snapshot.layout.area(of: $0.path) }.first ?? .direccion
        let titulo: String = switch clase {
        case .propuesta: "Propuesta de \(nombre): \(plan.descripcion)"
        case .mejora: "Propuesta de mejora de \(nombre): \(plan.descripcion)"
        case .criterio: "Criterio: \(plan.descripcion)"
        }
        let cambios = plan.ops.map { "- " + Self.enLlano($0) }.joined(separator: "\n")
        let nueva = NuevaTarea(
            titulo: titulo, area: area, responsable: persona, estado: .enRevision, tipo: "decision", origen: "agente:\(agente)",
            plantilla: "decision-1-3-1", autor: .sistema,
            propiedades: [Property(key: "responsable", value: .text(persona)),
                          Property(key: "creada_por", value: .text("agente:\(agente)")),
                          Property(key: "propuesta", value: .text(id))]
                + (capacidad.map { [Property(key: "capacidad", value: .text($0))] } ?? []))
        var nota = try TaskStore(snapshot: snapshot).crear(nueva)
        let secciones: [(String, String)] = [
            ("Problema", problema ?? "\(nombre) (asistente) quiere: \(plan.descripcion). \(motivo ?? "Te lo propone y decides tú.")"),
            ("Opciones", "1. Aplicar el cambio tal cual (recomendada)\n2. Dejarlo como está"),
            ("Por qué recomiendo la 1", porque ?? "Es lo que \(nombre) preparó para su trabajo. Si lo apruebas, se aplica en un paso y se puede deshacer."),
            ("Qué cambia si se aprueba", cambios),
        ]
        var texto = nota.texto
        var doc = FrontmatterDocument(text: texto)
        var cuerpo = doc.body
        for (s, t) in secciones {
            if let h = MarkdownSections.hash(of: s, in: cuerpo, level: 2),
               let nuevo = try? MarkdownSections.replace(s, in: cuerpo, with: t + "\n", baseHash: h, eol: doc.eol) {
                cuerpo = nuevo
            }
        }
        doc.replaceBody(cuerpo)
        texto = doc.text
        let ops = nota.plan.ops.map { op -> WriteOp in
            if case .create(let p, _) = op, p == nota.ruta { return .create(p, text: texto) }
            return op
        }
        nota = PlantillaMotor.NotaPreparada(ruta: nota.ruta, texto: texto, titulo: nota.titulo, numero: nota.numero,
                                            faltan: nota.faltan, cursor: nota.cursor,
                                            plan: WritePlan(autor: .sistema, descripcion: "Propuesta de \(nombre)", ops: ops))
        let r = try await bus.ejecutar(nota.plan)
        let ruta = r.creadas.first ?? nota.ruta
        let p = try propuestas.guardar(plan, agente: agente, ejecucion: ejecucion, capacidad: capacidad, clase: clase,
                                       descripcion: plan.descripcion, tarea: ruta, id: id, ahora: autorizador.opciones.ahora())
        return (p, ruta)
    }

    /// Modo manual: una tarea para la persona con lo que el asistente haría (lo escribe la app).
    func tareaParaPersona(_ plan: WritePlan, agente: String, capacidad: String?) async throws -> VaultPath {
        let snapshot = foto()
        let nombre = AsistenteConfigurado.nombre(de: agente)
        let area = plan.ops.lazy.compactMap { snapshot.layout.area(of: $0.path) }.first ?? .direccion
        let desc = "\(nombre) (asistente) lo haría, pero esta función la haces tú.\n\nLo que haría:\n"
            + plan.ops.map { "- " + Self.enLlano($0) }.joined(separator: "\n")
        let nueva = NuevaTarea(titulo: plan.descripcion, area: area, responsable: persona, estado: .porHacer,
                               descripcion: desc, origen: "agente:\(agente)", autor: .sistema,
                               propiedades: [Property(key: "creada_por", value: .text("agente:\(agente)"))]
                                   + (capacidad.map { [Property(key: "capacidad", value: .text($0))] } ?? []))
        let nota = try TaskStore(snapshot: snapshot).crear(nueva)
        let r = try await bus.ejecutar(nota.plan)
        return r.creadas.first ?? nota.ruta
    }

    /// «Aplicar»: el plan guardado se escribe como la persona, y la tarea de la propuesta queda Hecha.
    public func aplicar(_ id: String, autor: Autor) async throws -> WriteResult {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        guard let p = try propuestas.propuesta(id) else { throw ErrorDeGobierno.propuestaNoEncontrada }
        guard p.estado == .pendiente else { throw ErrorDeGobierno.propuestaCerrada }
        // F4 · corrector (R9): al aplicar se vuelve a mirar; lo que solo hace una aprobación o está vetado no se aplica
        // de un clic aunque se guardara (la ficha pudo cambiar de tipo después).
        if let motivo = autorizador.motivoParaNoProponer(p.plan) { throw ErrorDeGobierno.sinPermiso(motivo) }
        let plan = WritePlan(autor: autor, descripcion: p.descripcion, ops: p.plan.ops)
        let r = try await bus.ejecutar(plan)
        try propuestas.marcar(id, .aplicada, por: quien, resultado: r.hecho ? "aplicada" : "sin cambios",
                              ahora: autorizador.opciones.ahora())
        try await cerrarTarea(p, autor: autor, texto: "Aplicada.")
        return r
    }

    /// «Dejarlo como está»: no se escribe nada y la tarea queda Cancelada.
    public func descartar(_ id: String, autor: Autor, motivo: String? = nil) async throws {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        guard let p = try propuestas.propuesta(id) else { throw ErrorDeGobierno.propuestaNoEncontrada }
        guard p.estado == .pendiente else { throw ErrorDeGobierno.propuestaCerrada }
        try propuestas.marcar(id, .descartada, por: quien, resultado: motivo, ahora: autorizador.opciones.ahora())
        try await cerrarTarea(p, autor: autor, texto: "Descartada." + (motivo.map { " " + $0 } ?? ""), estado: .cancelada)
    }

    func cerrarTarea(_ p: Propuesta, autor: Autor, texto: String, estado: EstadoTarea = .hecha) async throws {
        guard let ruta = p.tarea, case .persona(let quien) = autor else { return }
        let store = TaskStore(snapshot: foto())
        guard let t = store.tarea(ruta), t.estado != estado else { return }
        let plan = try store.cambiarEstado(t, a: estado, autor: autor, persona: quien, nota: texto)
        _ = try await bus.ejecutar(plan)
    }

    /// Separa la operación del contador de tareas (`.tls/secuencias.json`), que no escribe un asistente.
    static func separarContador(_ plan: WritePlan) -> (WritePlan, WriteOp?) {
        let k = TextFolding.pathKey(Secuencias.ruta.raw)
        guard let i = plan.ops.firstIndex(where: { TextFolding.pathKey($0.path.raw) == k }) else { return (plan, nil) }
        var p = plan
        let op = p.ops.remove(at: i)
        return (p, op)
    }

    /// Una operación en palabras («Crear «x»», «Cambiar estado de «y»»…).
    static func enLlano(_ op: WriteOp) -> String {
        switch op {
        case .create(let p, _): "Crear «\(p.stem)» en \(p.parent?.raw ?? "la carpeta")"
        case .mergeFrontmatter(let p, let set, let unset):
            "Cambiar \((set.map(\.key) + unset).joined(separator: ", ")) de «\(p.stem)»"
        case .appendToSection(let p, let s, _, _): "Añadir a «\(s)» de «\(p.stem)»"
        case .replaceSection(let p, let s, _, _): "Cambiar «\(s)» de «\(p.stem)»"
        case .replaceBody(let p, _, _), .saveText(let p, _, _), .editRanges(let p, _, _): "Cambiar el texto de «\(p.stem)»"
        case .appendLine(let p, _): "Añadir una línea a «\(p.stem)»"
        case .upsertCSVRow(let p, _, _), .insertCSVRows(let p, _, _): "Guardar filas en «\(p.name)»"
        case .setTableCells(let p, _, _, _, _), .appendTableRow(let p, _, _): "Cambiar una tabla de «\(p.stem)»"
        case .move(let a, let b): "Mover «\(a.stem)» a \(b.parent?.raw ?? "la carpeta")"
        case .retire(let p, _): "Retirar «\(p.stem)» al Archivo"
        }
    }
}
