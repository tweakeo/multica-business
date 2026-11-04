import Foundation

// Pedir, comprobar, aprobar, rechazar y caducar aprobaciones (PLAN §5.2, línea roja de la decisión 6). Lo usan
// `tls-mcp` (`tls_solicitar_accion`, que siempre responde «aprobación requerida») y Decisiones (Aprobar,
// «Aprobar con mis cambios», Descartar). Al aprobar, la app vuelve a comprobar huella, versión, interruptor y
// permisos, y ejecuta ella (`EjecutorDeAprobaciones`); el asistente nunca.

/// Lo que recibe el asistente al pedir una acción externa.
public struct RespuestaDeSolicitud: Sendable, Hashable, Codable {
    /// `aprobacion_requerida`, `denegado`, `no_encontrado` o `solo_lectura`.
    public let estado: String
    public let id: String?
    public let motivo: String?

    /// `{"estado":"aprobacion_requerida","id":"apr-…"}`.
    public var json: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? e.encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

/// ¿Sigue valiendo lo que se pidió?
public enum VigenciaDeAprobacion: Sendable, Hashable {
    case vigente
    /// «Cambió desde que lo preparó el asistente»: Aprobar se desactiva; «Aprobar con mis cambios», no.
    case cambio
    case caducada
    case cerrada(Aprobacion.Estado)
    /// La ficha ya no está (se movió o se retiró).
    case sinFicha
}

/// Lo que enseña la hoja de confirmación: literalmente qué sale, a quién y por cuánto (sin huellas).
public struct DetalleDeAprobacion: Sendable, Hashable {
    public let aprobacion: Aprobacion
    public let borrador: Borrador?
    public let vigencia: VigenciaDeAprobacion
    /// Huella de lo que enseña esta hoja (no se enseña): «Aprobar con mis cambios» la devuelve para aprobar eso o nada.
    public var vista: String? = nil
    /// «Enviar un correo»…
    public var accion: String { aprobacion.accion.titulo }
    public var aQuien: [String] { borrador?.para ?? aprobacion.carga.destinatarios }
    public var asunto: String? { borrador?.asunto ?? aprobacion.carga.asunto }
    public var queSale: String { borrador?.cuerpo ?? aprobacion.carga.cuerpo ?? "" }
    public var porCuanto: String? { (borrador?.importe ?? aprobacion.carga.importe).map(Euros.texto) }

    /// `nil` si se puede aprobar tal cual; si no, por qué (para desactivar el botón).
    public var motivoNoAprobar: String? {
        switch vigencia {
        case .vigente: nil
        case .cambio: "Cambió desde que lo preparó el asistente"
        case .caducada: "Lleva más de 14 días sin decidir"
        case .cerrada(let e): "Ya está \(e.texto)"
        case .sinFicha: "La ficha ya no está en su sitio"
        }
    }

    /// «Aprobar con mis cambios» vale mientras siga abierta.
    public var puedeAprobarConCambios: Bool {
        switch vigencia {
        case .vigente, .cambio: true
        default: false
        }
    }
}

/// Lo que cambia la persona al «Aprobar con mis cambios» (lo que no se da, se queda como está).
public struct CambiosDeAprobacion: Sendable, Hashable {
    public var para: [String]?
    public var asunto: String?
    public var cuerpo: String?
    public var importe: Int?

    public init(para: [String]? = nil, asunto: String? = nil, cuerpo: String? = nil, importe: Int? = nil) {
        self.para = para; self.asunto = asunto; self.cuerpo = cuerpo; self.importe = importe
    }

    var vacios: Bool { para == nil && asunto == nil && cuerpo == nil && importe == nil }
}

public actor Aprobaciones {
    public nonisolated let bus: CommandBus
    public nonisolated let autorizador: Autorizador
    public nonisolated let store: ApprovalStore
    public nonisolated let ejecutor: EjecutorDeAprobaciones
    nonisolated let foto: @Sendable () -> VaultSnapshot

    public init(bus: CommandBus, autorizador: Autorizador, ejecutor: EjecutorDeAprobaciones = EjecutorDeAprobaciones(),
                snapshot: (@Sendable () -> VaultSnapshot)? = nil) {
        self.bus = bus
        self.autorizador = autorizador
        self.store = ApprovalStore(estado: autorizador.estado)
        self.ejecutor = ejecutor
        let writer = bus.writer
        self.foto = snapshot ?? { VaultSnapshot.read(entry: writer.entry, root: writer.root) }
    }

    var ahora: Date { autorizador.opciones.ahora() }
    /// F4 · corrector (R8): huella de lo último que enseñó la hoja de cada aprobación (`detalle`).
    private var vistas: [String: String] = [:]

    // MARK: Pedir (asistente)

    /// `tls_solicitar_accion {accion, borrador_id}`: si el asistente puede pedirlo, la respuesta es siempre
    /// «aprobación requerida» (en cualquier modo, incluso autónomo); lo privado, «no encontrado».
    public func solicitar(accion: AccionExterna, borrador: VaultPath, asistente: String, ejecucion: ContextoEjecucion? = nil,
                          capacidad: String? = nil, herramienta: String? = nil) async throws -> RespuestaDeSolicitud {
        let slug = ConfigAgentes.slug(asistente)
        let d = autorizador.decidir(SolicitudAutorizacion(autor: .agente(slug), tipo: .externa, rutas: [borrador],
                                                          capacidad: capacidad, externa: accion, herramienta: herramienta,
                                                          ejecucion: ejecucion))
        guard d.resultado == .requiereAprobacion else {
            return RespuestaDeSolicitud(estado: d.resultado.rawValue, id: nil,
                                        motivo: d.resultado == .noEncontrado ? "No encontrado." : d.motivo)
        }
        let snapshot = foto()
        guard let real = snapshot.existing(borrador), let texto = snapshot.text(real),
              let b = Borrador.leer(real, texto: texto, layout: snapshot.layout) else {
            return RespuestaDeSolicitud(estado: DecisionAutorizacion.Resultado.noEncontrado.rawValue, id: nil, motivo: "No encontrado.")
        }
        if let propia = b.accion, propia != accion, !(propia == .escribirCliente && accion == .enviarCorreo) {
            throw ErrorDeGobierno.borradorNoValido("El borrador es para «\(propia.titulo)», no para «\(accion.titulo)».")
        }
        let carga = try cargaDe(b, snapshot: snapshot, asistente: slug)
        let a = try store.registrar(accion: accion, herramienta: herramienta, ruta: real, agente: slug, ejecucion: ejecucion?.id,
                                    carga: carga, ahora: ahora)
        // El espejo en la ficha (lo escribe la app): «Pendiente de tu OK» y el número de la aprobación.
        if b.tipo != "factura" {
            _ = try? await bus.ejecutar(Borradores.planEspejo(real, estado: .pendiente, aprobacion: a.id))
        } else {
            _ = try? await bus.ejecutar(WritePlan(autor: .sistema, descripcion: "«\(real.stem)»: pendiente de tu OK",
                                                  ops: [.mergeFrontmatter(real, set: [Property(key: "aprobacion", value: .text(a.id))],
                                                                          unset: [])]))
        }
        return RespuestaDeSolicitud(estado: DecisionAutorizacion.Resultado.requiereAprobacion.rawValue, id: a.id, motivo: nil)
    }

    /// F5 · corrector (P1-1): un **correo** que preparó un asistente sin pedir la aprobación (el Cartero no pide acciones
    /// externas: solo prepara respuestas). Lo pide la persona desde Decisiones, en nombre de quien lo preparó y con las
    /// mismas comprobaciones que si lo pidiera él (Autorizador, huella, versión); después se aprueba en la hoja de
    /// siempre, que enseña qué sale y a quién. Devuelve el número de la aprobación (o la que ya estuviera abierta).
    public func pedirParaAprobar(borrador: VaultPath, autor: Autor) async throws -> String {
        guard autor.esPersona else { throw ErrorDeGobierno.soloPersonas }
        let snapshot = foto()
        guard let real = snapshot.existing(borrador), let texto = snapshot.text(real),
              let b = Borrador.leer(real, texto: texto, layout: snapshot.layout) else {
            throw ErrorDeGobierno.noEncontrado(borrador.stem)
        }
        if let ya = b.aprobacion, let a = try store.aprobacion(ya), a.estado.abierta { return ya }
        let accion = b.accion ?? .enviarCorreo
        guard accion == .enviarCorreo || accion == .escribirCliente else {
            throw ErrorDeGobierno.borradorNoValido("Desde aquí solo se preparan correos para aprobar. Abre el borrador para revisarlo.")
        }
        guard let asistente = b.asistente else {
            throw ErrorDeGobierno.borradorNoValido("Este borrador no lo preparó un asistente: ábrelo y envíalo tú desde Mail.")
        }
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        // Lo pide la persona (el Cartero trabaja en el Buzón, no en Ventas: no podría pedirlo él). Queda apuntado como
        // `ejecucion: persona:<nombre>`, con quien lo preparó como autor del contenido y atado a su huella.
        let carga = try cargaDe(b, snapshot: snapshot, asistente: nil)
        let a = try store.registrar(accion: accion, ruta: real, agente: asistente, ejecucion: Aprobacion.prefijoPersona + quien,
                                    carga: carga, ahora: ahora)
        _ = try? await bus.ejecutar(Borradores.planEspejo(real, estado: .pendiente, aprobacion: a.id))
        return a.id
    }

    /// La carga de un borrador: lo que sale, a quién, por cuánto, sus adjuntos (por huella) y su versión.
    func cargaDe(_ b: Borrador, snapshot: VaultSnapshot, asistente: String?) throws -> CargaAprobacion {
        if let s = asistente {
            for p in b.adjuntos where !autorizador.decidirLectura(p, asistente: s).permitido { throw ErrorDeGobierno.noEncontrado(p.name) }
        }
        return try CargaAprobacion.de(b, snapshot: snapshot)
    }

    // MARK: Mirar

    /// Lo que enseña Decisiones (y si se puede aprobar tal cual). Si alguien cambió el contenido, queda invalidada.
    public func detalle(_ id: String) throws -> DetalleDeAprobacion {
        guard let a = try store.aprobacion(id) else { throw ErrorDeGobierno.aprobacionNoEncontrada }
        let (v, b) = try vigencia(a)
        var d = DetalleDeAprobacion(aprobacion: try store.aprobacion(id) ?? a, borrador: b, vigencia: v)
        if let b, let carga = try? cargaDe(b, snapshot: foto(), asistente: nil) {
            let h = ApprovalStore.hash(accion: a.accion, herramienta: a.herramienta, carga: carga)
            d.vista = h
            vistas[id] = h
        }
        return d
    }

    /// Huella de lo que hay ahora en la ficha de una aprobación (`nil` si ya no se lee como borrador o factura).
    func huellaActual(_ a: Aprobacion) -> String? {
        let snapshot = foto()
        guard let ruta = a.ruta, let real = snapshot.existing(ruta), let texto = snapshot.text(real),
              let b = Borrador.leer(real, texto: texto, layout: snapshot.layout),
              let carga = try? cargaDe(b, snapshot: snapshot, asistente: nil) else { return nil }
        return ApprovalStore.hash(accion: a.accion, herramienta: a.herramienta, carga: carga)
    }

    func vigencia(_ a: Aprobacion) throws -> (VigenciaDeAprobacion, Borrador?) {
        guard a.estado.abierta else { return (.cerrada(a.estado), nil) }
        if a.caduca <= ahora { return (.caducada, nil) }
        let snapshot = foto()
        guard let ruta = a.ruta, let real = snapshot.existing(ruta), let texto = snapshot.text(real),
              let b = Borrador.leer(real, texto: texto, layout: snapshot.layout) else { return (.sinFicha, nil) }
        if a.estado == .invalidada { return (.cambio, b) }
        let carga = try? cargaDe(b, snapshot: snapshot, asistente: nil)
        guard let carga, ApprovalStore.hash(accion: a.accion, herramienta: a.herramienta, carga: carga) == a.hash else {
            try store.invalidar(a.id, motivo: "Cambió desde que lo preparó el asistente.")
            return (.cambio, b)
        }
        return (.vigente, b)
    }

    // MARK: Decidir (persona)

    /// «Aprobar» (⌘↩): solo si nada cambió desde que se pidió. Vuelve a comprobar huella, versión, interruptor y permisos
    /// y ejecuta la app.
    public func aprobar(_ id: String, autor: Autor) async throws -> ResultadoDeAprobacion {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        guard let a = try store.aprobacion(id) else { throw ErrorDeGobierno.aprobacionNoEncontrada }
        let (v, b) = try vigencia(a)
        switch v {
        case .vigente: break
        case .cambio: throw ErrorDeGobierno.cambioDesdeQueLoPreparo
        case .caducada:
            try await caducar()
            throw ErrorDeGobierno.caducada
        case .cerrada(let e): throw ErrorDeGobierno.aprobacionCerrada(e.texto)
        case .sinFicha: throw ErrorDeGobierno.noEncontrado(a.ruta?.stem ?? a.entidadId)
        }
        try recomprobar(a)
        guard try store.marcarAprobada(id, por: quien, hash: a.hash, carga: a.carga, conCambios: false, ahora: ahora) else {
            throw ErrorDeGobierno.aprobacionCerrada("decidida")
        }
        return try await ejecutar(id, borrador: b, autor: autor)
    }

    /// «Aprobar con mis cambios»: aplica tus cambios al borrador (como tú), calcula la huella nueva y aprueba en el mismo
    /// gesto. Sin cambios, aprueba lo que hay ahora (también si otro lo cambió: lo que ves es lo que se aprueba).
    ///
    /// `vista`: la huella de lo que enseñó la hoja (`DetalleDeAprobacion.vista`); sin ella, la de la última hoja abierta
    /// (`detalle`). Si el borrador cambió mientras la hoja estaba abierta, no se aprueba nada
    /// (`ErrorDeGobierno.cambioMientrasLoMirabas`): lo que se aprueba es siempre lo que se vio más tus cambios.
    public func aprobarConMisCambios(_ id: String, autor: Autor, cambios: CambiosDeAprobacion? = nil,
                                     vista: String? = nil) async throws -> ResultadoDeAprobacion {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        guard let a = try store.aprobacion(id) else { throw ErrorDeGobierno.aprobacionNoEncontrada }
        guard a.estado.abierta else { throw ErrorDeGobierno.aprobacionCerrada(a.estado.texto) }
        guard a.caduca > ahora else {
            try await caducar()
            throw ErrorDeGobierno.caducada
        }
        guard let ruta = a.ruta else { throw ErrorDeGobierno.noEncontrado(a.entidadId) }
        if let esperada = vista ?? vistas[id], huellaActual(a) != esperada {
            throw ErrorDeGobierno.cambioMientrasLoMirabas
        }
        if let c = cambios, !c.vacios {
            let snapshot = foto()
            guard let real = snapshot.existing(ruta), let texto = snapshot.text(real), let data = snapshot.data(real),
                  let b = Borrador.leer(real, texto: texto, layout: snapshot.layout) else { throw ErrorDeGobierno.noEncontrado(ruta.stem) }
            guard b.tipo != "factura" else {
                throw ErrorDeGobierno.borradorNoValido("Cambia la factura en su ficha y apruébala después.")
            }
            try await escribirCambios(c, en: real, texto: texto, datos: data, autor: autor)
        }
        let snapshot = foto()
        guard let real = snapshot.existing(ruta), let texto = snapshot.text(real),
              let b = Borrador.leer(real, texto: texto, layout: snapshot.layout) else { throw ErrorDeGobierno.noEncontrado(ruta.stem) }
        let carga = try cargaDe(b, snapshot: snapshot, asistente: nil)
        let hash = ApprovalStore.hash(accion: a.accion, herramienta: a.herramienta, carga: carga)
        try recomprobar(a)
        guard try store.marcarAprobada(id, por: quien, hash: hash, carga: carga, conCambios: hash != a.hash, ahora: ahora) else {
            throw ErrorDeGobierno.aprobacionCerrada("decidida")
        }
        vistas[id] = nil
        return try await ejecutar(id, borrador: b, autor: autor)
    }

    /// Escribe en el borrador lo que cambia la persona (propiedades y la sección «Mensaje»), como ella.
    func escribirCambios(_ c: CambiosDeAprobacion, en ruta: VaultPath, texto: String, datos: Data, autor: Autor) async throws {
        var ops: [WriteOp] = []
        var poner: [Property] = []
        if let p = c.para { poner.append(Property(key: "para", value: .list(p))) }
        if let s = c.asunto { poner.append(Property(key: "asunto", value: .text(s))) }
        if let i = c.importe { poner.append(Property(key: "importe", value: .number(Euros.escrito(i)))) }
        if !poner.isEmpty { ops.append(.mergeFrontmatter(ruta, set: poner, unset: [])) }
        if let cuerpo = c.cuerpo {
            let body = FrontmatterDocument(text: texto).body
            if let h = MarkdownSections.hash(of: "Mensaje", in: body, level: 2) {
                ops.append(.replaceSection(ruta, section: "Mensaje", text: cuerpo.trimmingCharacters(in: .newlines) + "\n", baseSectionHash: h))
            } else {
                ops.append(.replaceBody(ruta, body: cuerpo.trimmingCharacters(in: .newlines) + "\n", baseHash: ContentHash.of(datos)))
            }
        }
        guard !ops.isEmpty else { return }
        let r = try await bus.ejecutar(WritePlan(autor: autor, descripcion: "Cambios en «\(ruta.stem)» antes de aprobar", ops: ops))
        if let c = r.conflicto { throw ErrorDeGobierno.borradorNoValido(c.detalle) }
    }

    /// «Descartar».
    public func rechazar(_ id: String, autor: Autor, motivo: String? = nil) async throws {
        guard case .persona(let quien) = autor else { throw ErrorDeGobierno.soloPersonas }
        guard let a = try store.aprobacion(id) else { throw ErrorDeGobierno.aprobacionNoEncontrada }
        guard try store.rechazar(id, por: quien, motivo: motivo, ahora: ahora) else { throw ErrorDeGobierno.aprobacionCerrada(a.estado.texto) }
        try await espejo(a, .descartado)
    }

    /// Caduca lo que lleva 14 días sin decidir (y lo refleja en sus borradores).
    @discardableResult
    public func caducar() async throws -> [Aprobacion] {
        let caducadas = try store.caducar(ahora: ahora)
        for a in caducadas { try? await espejo(a, .caducado) }
        return caducadas
    }

    // MARK: Ejecutar (la app)

    /// Interruptor encendido, el asistente sigue activo y el área de la ficha, en marcha. Y, por si cambió algo más
    /// (la función apagada, el alcance del asistente, la ficha ahora privada), se vuelve a preguntar al Autorizador
    /// como si el asistente la pidiera ahora: tiene que salir «aprobación requerida» otra vez.
    func recomprobar(_ a: Aprobacion) throws {
        let cfg = autorizador.estadoDeConfig().efectiva
        // F5 · corrector (P1-1): la pidió una persona (un correo del Cartero): no depende de los asistentes; solo de que
        // la ficha siga ahí y no sea privada (la huella y la versión ya se comprobaron).
        if a.pedidaPorPersona {
            if let r = a.ruta, autorizador.contexto().layout.isPrivate(r) { throw ErrorDeGobierno.noEncontrado(r.stem) }
            return
        }
        guard cfg.encendido else { throw ErrorDeGobierno.interruptorApagado }
        guard let asis = cfg.asistente(a.agente), asis.activo else {
            throw ErrorDeGobierno.sinPermiso("\(AsistenteConfigurado.nombre(de: a.agente)) ya no está activo: no hago lo que preparó.")
        }
        if let r = a.ruta, let area = autorizador.contexto().layout.area(of: r), cfg.enPausa(area) {
            throw ErrorDeGobierno.sinPermiso("El área \(area.nombre) está en pausa.")
        }
        // F4 · corrector (pendiente de la revisión de seguridad): el Autorizador entero, otra vez.
        let d = autorizador.decidir(SolicitudAutorizacion(
            autor: .agente(a.agente), tipo: .externa, rutas: a.ruta.map { [$0] } ?? [],
            capacidad: a.accion == .emitirFactura ? "FIN-02" : nil, externa: a.accion, herramienta: a.herramienta,
            ejecucion: a.ejecucion.map { ContextoEjecucion(id: $0) }))
        guard d.resultado == .requiereAprobacion else {
            throw ErrorDeGobierno.sinPermiso(d.resultado == .noEncontrado ? "La ficha ya no está a su alcance: no hago lo que preparó."
                                             : d.motivo)
        }
    }

    func ejecutar(_ id: String, borrador: Borrador?, autor: Autor) async throws -> ResultadoDeAprobacion {
        guard let aprobada = try store.aprobacion(id) else { throw ErrorDeGobierno.aprobacionNoEncontrada }
        let curso = AprobacionEnCurso(aprobacion: aprobada, borrador: borrador, persona: autor, bus: bus, snapshot: foto())
        let r: ResultadoDeAprobacion
        do {
            r = try await ejecutor.ejecutar(curso)
        } catch {
            try? store.anotarFallo(id, motivo: error.localizedDescription)
            throw error
        }
        try store.marcarEjecutada(id, resultado: r.texto, ahora: ahora)
        if let e = r.espejo { try? await espejo(aprobada, e) }
        return r
    }

    func espejo(_ a: Aprobacion, _ e: EstadoBorrador) async throws {
        guard let ruta = a.ruta else { return }
        let snapshot = foto()
        guard let real = snapshot.existing(ruta), let texto = snapshot.text(real),
              let b = Borrador.leer(real, texto: texto, layout: snapshot.layout), b.tipo != "factura" else { return }
        _ = try await bus.ejecutar(Borradores.planEspejo(real, estado: e, aprobacion: a.id))
    }
}
