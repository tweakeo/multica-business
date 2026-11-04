import Foundation

// Reglas del dominio (PLAN §4.7, SISTEMAS §3.3 y §3.4). Ningún módulo llama a otro: cada regla escucha un evento y
// devuelve un plan que el `MotorDeDominio` ejecuta como `Autor.sistema` a través del `CommandBus`.
//
// | Evento | Función | Qué deja escrito |
// |---|---|---|
// | contacto.creado | VEN-04 | Tarea «Preparar diagnóstico de …» |
// | conversacion.cualificada | MAR-07 | Empresa y contacto, enlazados a la conversación |
// | cobro.confirmado | VEN-07 · ENT-01 | Oportunidad Ganada y su proyecto de entrega (una sola vez) |
// | oportunidad.aceptada / oportunidad.ganada | FIN-02 · FIN-10 | Borrador de factura y de contrato (si no los hay) |
// | oportunidad.ganada | ENT-01 | El proyecto de entrega, si aún no existe |
// | proyecto.creado | ENT-02 | Las tareas del plan de entrega, en días laborables |
// | proyecto.cerrado | ENT-11 · MAR-05 | Testimonio y caso de éxito para Marca (como Idea) |
//
// Reglas fijas: ninguna confirma un cobro, emite, envía, publica ni paga (`GuardaDeReglas`); como mucho dejan un
// borrador. Si la función está en «off» o «manual», la regla deja una tarea para una persona en lugar de actuar.
// SISTEMAS §3.4.6 corrige el PLAN: contrato y factura salen en `oportunidad.aceptada`; aquí salen en la primera de
// las dos (aceptada o ganada) y nunca dos veces (misma clave).
//
// Procedencia: lógica portada de PROG `core/reglas.js` (Manu): una regla por evento y función, cada una con su
// capacidad para auditar quién hizo qué, y la comprobación «si ya existe, no se repite». Reescrita en Swift sobre
// fichas Markdown en vez de tablas. Ver docs/PROCEDENCIA.md.

/// Lo que una regla tiene a mano al preparar su plan.
public struct ContextoRegla: Sendable {
    public let evento: EventoDominio
    public let lectura: LecturaDominio
    /// La persona de la carpeta: responsable de las tareas que deja una regla.
    public let persona: String
    /// Modo de la función en `.tls/config.yaml` (`nil` si no se dice).
    public let modo: ModoCapacidad?

    public var hoy: LocalDate { lectura.hoy }
    public var origen: String { "regla:" + evento.tipo.rawValue }
}

/// Lo que devuelve una regla.
public enum ResultadoRegla: Sendable {
    /// No hay nada que hacer (ya está hecho, falta un dato…), con el motivo.
    case nada(String)
    /// Plan que hay que escribir, con su resumen para el registro.
    case plan(WritePlan, resumen: String)
}

/// Una regla: escucha un evento y prepara un plan.
public struct Regla: Sendable, Identifiable {
    /// `VEN-07·ganada`: única entre las reglas.
    public let id: String
    public let evento: TipoEvento
    /// Código de la función que la respalda (`VEN-07`).
    public let capacidad: String
    public let nombre: String
    /// Clave de lo que hace (idempotencia). Dos reglas que hacen lo mismo comparten clave.
    public let clave: @Sendable (EventoDominio, LecturaDominio) -> String
    /// Tarea para una persona cuando la función está en «off» o «manual» (`nil`: no hace nada).
    public let paraPersona: (@Sendable (ContextoRegla) -> String?)?
    public let preparar: @Sendable (ContextoRegla) throws -> ResultadoRegla

    public init(id: String, evento: TipoEvento, capacidad: String, nombre: String,
                clave: (@Sendable (EventoDominio, LecturaDominio) -> String)? = nil,
                paraPersona: (@Sendable (ContextoRegla) -> String?)? = nil,
                preparar: @escaping @Sendable (ContextoRegla) throws -> ResultadoRegla) {
        self.id = id; self.evento = evento; self.capacidad = capacidad; self.nombre = nombre
        self.clave = clave ?? { e, _ in "\(id):\(e.clave)" }
        self.paraPersona = paraPersona; self.preparar = preparar
    }
}

/// Lo que una regla nunca puede escribir (SISTEMAS §3.4.5 y regla 4 de F2: ninguna salida sin una persona).
public enum GuardaDeReglas {
    public enum Motivo: Error, LocalizedError, Sendable, Equatable {
        case cobro(String)
        case emision(String)
        case salida(String)

        public var errorDescription: String? {
            switch self {
            case .cobro(let p): "Una regla no confirma cobros: «\(p)» lo confirma siempre una persona."
            case .emision(let p): "Una regla no emite facturas: «\(p)» se queda en borrador hasta que lo revise una persona."
            case .salida(let p): "Una regla no envía ni publica nada: «\(p)» espera a una persona."
            }
        }
    }

    /// Estados de factura que solo pone una persona.
    static let estadosDeFactura: Set<String> = ["emitida", "enviada", "cobrada", "rectificada"]
    /// Estados de borradores y contenidos que significan que algo salió.
    static let estadosDeSalida: Set<String> = ["enviado", "enviada", "publicado", "publicada", "aprobado", "aprobada", "aceptado", "aceptada"]

    public static func comprobar(_ plan: WritePlan, lectura: LecturaDominio) throws {
        for op in plan.ops {
            let p = op.path
            let nombre = TextFolding.nameKey(p.name)
            switch op {
            case .upsertCSVRow(_, let fila, _):
                try revisarFilas(p, nombre, [fila])
            case .insertCSVRows(_, let filas, _):
                try revisarFilas(p, nombre, filas)
            case .mergeFrontmatter(_, let set, _):
                try revisar(p, set, tipo: lectura.ficha(p)?.tipo)
            case .create(_, let data):
                guard p.ext == "md", let e = EditableText(data: data) else {
                    if nombre == "pagos.csv" { throw Motivo.cobro(p.stem) }
                    continue
                }
                let fm = NoteDocument(text: e.text).frontmatter
                try revisar(p, fm.properties, tipo: NoteKindResolver.kind(of: p, frontmatter: fm, layout: lectura.layout))
            case .editRanges, .replaceBody, .saveText, .replaceSection, .setTableCells:
                if ["pagos.csv", "emitidas.csv"].contains(nombre) { throw Motivo.cobro(p.stem) }
            default:
                continue
            }
        }
    }

    /// Filas de los registros de dinero: una regla no emite ni confirma cobros.
    static func revisarFilas(_ p: VaultPath, _ nombre: String, _ filas: [[String: String]]) throws {
        guard ["pagos.csv", "emitidas.csv", "movimientos.csv"].contains(nombre) else { return }
        if nombre == "emitidas.csv" { throw Motivo.emision(p.stem) }
        for fila in filas {
            let valores = fila.values.map(TextFolding.fold)
            if nombre == "pagos.csv" || valores.contains("conciliado") || valores.contains("confirmado") {
                throw Motivo.cobro(p.stem)
            }
        }
    }

    static func revisar(_ p: VaultPath, _ props: [Property], tipo: NoteKind?) throws {
        for prop in props {
            let v = TextFolding.fold(prop.value.displayText)
            switch prop.key {
            case "estado" where tipo == .invoice && estadosDeFactura.contains(v): throw Motivo.emision(p.stem)
            case "estado" where [.draft, .content, .proposal, .quote, .agreement].contains(tipo) && estadosDeSalida.contains(v):
                throw Motivo.salida(p.stem)
            case "verificacion" where v == "confirmado" && tipo == .receipt: throw Motivo.cobro(p.stem)
            case "estado_conciliacion" where v == "conciliado": throw Motivo.cobro(p.stem)
            default: continue
            }
        }
    }
}

/// Las reglas de serie.
public enum ReglasDeSerie {
    public static var todas: [Regla] {
        [preparaDiagnostico, conversacionAContacto, cobroGanaYAbreProyecto, facturaEnBorrador(.oportunidadAceptada),
         facturaEnBorrador(.oportunidadGanada), contratoEnBorrador(.oportunidadAceptada), contratoEnBorrador(.oportunidadGanada),
         proyectoDeLaGanada, tareasDelPlan, testimonio, casoDeExito]
    }

    // MARK: VEN-04 · contacto.creado → tarea «Preparar diagnóstico»

    static let preparaDiagnostico = Regla(
        id: "VEN-04·diagnostico", evento: .contactoCreado, capacidad: "VEN-04", nombre: "Preparar el diagnóstico del contacto nuevo",
        clave: { e, _ in "VEN-04·diagnostico:\(e.entidad)" },
        paraPersona: { ctx in "Preparar diagnóstico de \(ctx.lectura.ficha(ctx.evento.ruta)?.nombre ?? ctx.evento.ruta.stem)" }
    ) { ctx in
        guard let c = ctx.lectura.ficha(ctx.evento.ruta) else { return .nada("El contacto ya no está en su sitio.") }
        let enlace = NombresDeFicha.wikilink(c.ruta, nombre: c.nombre, en: ctx.lectura.snapshot)
        // Si ya hay una tarea de esta regla para este contacto, no se repite.
        let k = TextFolding.pathKey(c.ruta.raw)
        let ya = ctx.lectura.fichas(.task).contains { t in
            t.texto("origen") == ctx.origen && ctx.lectura.relacion(t, "contacto").map { TextFolding.pathKey($0.raw) == k } == true
        }
        if ya { return .nada("Ya tiene su tarea de diagnóstico.") }
        let nueva = NuevaTarea(titulo: "Preparar diagnóstico de \(c.nombre)", area: .ventas,
                               empresa: ctx.lectura.relacion(c, "empresa"), responsable: ctx.persona, estado: .porHacer,
                               tipo: "tarea", planificada: FormatosPlantilla.sumarLaborables(ctx.hoy, 1), origen: ctx.origen,
                               autor: .sistema,
                               propiedades: [Property(key: "contacto", value: .text(enlace)),
                                             Property(key: "capacidad", value: .text("VEN-04"))])
        let nota = try TaskStore(snapshot: ctx.lectura.snapshot, reloj: ctx.lectura.reloj).crear(nueva)
        return .plan(nota.plan, resumen: "Tarea «\(nota.titulo)»")
    }

    // MARK: MAR-07 · conversacion.cualificada → empresa y contacto

    static let conversacionAContacto = Regla(
        id: "MAR-07·contacto", evento: .conversacionCualificada, capacidad: "MAR-07", nombre: "Dar de alta a quien escribió",
        clave: { e, _ in "MAR-07·contacto:\(e.entidad)" },
        paraPersona: { ctx in "Dar de alta el contacto de «\(ctx.lectura.ficha(ctx.evento.ruta)?.nombre ?? ctx.evento.ruta.stem)»" }
    ) { ctx in
        let l = ctx.lectura
        guard let conv = l.ficha(ctx.evento.ruta) else { return .nada("La conversación ya no está en su sitio.") }
        if l.relacion(conv, "contacto") != nil { return .nada("La conversación ya tiene su contacto.") }
        let perfil = conv.texto("nombre") ?? conv.texto("perfil") ?? conv.nombre
        let persona = perfil.hasPrefix("@") ? String(perfil.dropFirst()) : perfil
        guard !persona.trimmingCharacters(in: .whitespaces).isEmpty else { return .nada("La conversación no dice quién escribió.") }
        let empresaNombre = conv.texto("empresa").flatMap { $0.contains("[[") || $0.contains("](") ? nil : $0 } ?? persona
        let motor = PlantillaMotor(snapshot: l.snapshot, opciones: .init(yo: Autor.sistema.etiqueta, reloj: l.reloj))
        var ops: [WriteOp] = []
        var comunes: [Property] = [Property(key: "origen", value: .text(ctx.origen))]
        if let canal = conv.texto("canal") { comunes.append(Property(key: "canal", value: .text(canal))) }
        let convEnlace = NombresDeFicha.wikilink(conv.ruta, nombre: conv.nombre, en: l.snapshot)
        // Cada persona y cada empresa existen una sola vez: si ya están (mismo nombre), se enlazan.
        func existente(_ tipo: NoteKind, _ nombre: String) -> FichaDominio? {
            let k = TextFolding.fold(nombre)
            return l.fichas(tipo).first { !$0.privada && TextFolding.fold($0.nombre) == k }
        }
        let empresa: (ruta: VaultPath, nombre: String)
        var nuevas: [VaultPath] = []
        var empresaNueva: PlantillaMotor.NotaPreparada?
        if let e = l.relacion(conv, "empresa").flatMap({ l.ficha($0) }) ?? existente(.organization, empresaNombre) {
            empresa = (e.ruta, e.nombre)
        } else {
            let nota = try motor.preparar(.init(plantilla: "empresa", valores: ["titulo": empresaNombre], poner: comunes, autor: .sistema))
            empresaNueva = nota
            nuevas.append(nota.ruta)
            empresa = (nota.ruta, empresaNombre)
        }
        let contacto: (ruta: VaultPath, nombre: String)
        var contactoNuevo: PlantillaMotor.NotaPreparada?
        if let c = existente(.contact, persona) {
            contacto = (c.ruta, c.nombre)
        } else {
            // La ruta del contacto se sabe antes de escribir sus enlaces: si comparte nombre con la empresa nueva,
            // los dos enlaces se escriben con su ruta (si no, `[[pedro-llorens]]` iría a la propia ficha).
            let tanteo = try motor.preparar(.init(plantilla: "contacto", valores: ["titulo": persona], autor: .sistema))
            nuevas.append(tanteo.ruta)
            let empresaEnlace = enlace(empresa.ruta, nombre: empresa.nombre, en: l.snapshot, nuevas: nuevas)
            var poner = comunes + [Property(key: "empresa", value: .text(empresaEnlace)),
                                   Property(key: "conversacion", value: .text(convEnlace))]
            if let pieza = conv.texto("contenido") { poner.append(Property(key: "contenido", value: .text(pieza))) }
            let nota = try motor.preparar(.init(plantilla: "contacto", valores: ["titulo": persona], poner: poner, autor: .sistema))
            contactoNuevo = nota
            contacto = (nota.ruta, persona)
        }
        if let e = empresaNueva { ops += e.plan.ops }
        if let c = contactoNuevo { ops += c.plan.ops }
        let contactoEnlace = enlace(contacto.ruta, nombre: contacto.nombre, en: l.snapshot, nuevas: nuevas)
        ops.append(.mergeFrontmatter(conv.ruta, set: [Property(key: "contacto", value: .text(contactoEnlace))], unset: []))
        return .plan(WritePlan(autor: .sistema, descripcion: "Dar de alta a «\(persona)» desde su conversación", ops: ops),
                     resumen: "Contacto «\(contacto.nombre)» y empresa «\(empresa.nombre)»")
    }

    /// Enlace `[[nombre|Visible]]` a una ficha que puede ser nueva: si otra ficha (ya escrita o nueva en el mismo plan)
    /// se llama igual, el enlace lleva su ruta para que no vaya a otra.
    static func enlace(_ ruta: VaultPath, nombre: String, en snapshot: VaultSnapshot, nuevas: [VaultPath] = []) -> String {
        let key = TextFolding.nameKey(ruta.stem)
        let yo = TextFolding.pathKey(ruta.raw)
        let otros = (snapshot.files + nuevas).filter { p in
            p.ext == "md" && TextFolding.pathKey(p.raw) != yo && TextFolding.nameKey(p.stem) == key
        }
        guard !otros.isEmpty else { return NombresDeFicha.wikilink(ruta, nombre: nombre, en: snapshot) }
        let destino = String(ruta.raw.dropLast(ruta.ext.count + 1))
        let visible = NombresDeFicha.textoDeWikilink(nombre)
        return "[[\(destino)|\(visible)]]"
    }

    // MARK: VEN-07 · cobro.confirmado → Ganada y proyecto (una sola vez)

    static let cobroGanaYAbreProyecto = Regla(
        id: "VEN-07·ganada", evento: .cobroConfirmado, capacidad: "VEN-07", nombre: "El cobro confirmado gana la oportunidad y abre su proyecto",
        // Una sola vez por oportunidad, aunque lleguen más cobros (el final, otro hito…).
        clave: { e, l in
            let pago = l.pagos.first { $0.id == e.entidad }
            let opo = pago.flatMap { l.oportunidad(de: $0) }.flatMap { l.ficha($0) }
            return "VEN-07·ganada:" + (opo?.clave ?? "cobro:\(e.entidad)")
        },
        paraPersona: { ctx in
            let l = ctx.lectura
            guard let pago = l.pagos.first(where: { $0.id == ctx.evento.entidad }), let o = l.oportunidad(de: pago), let f = l.ficha(o)
            else { return nil }
            return "Pasar «\(f.nombre)» a Ganada y abrir su proyecto"
        }
    ) { ctx in
        let l = ctx.lectura
        guard let pago = l.pagos.first(where: { $0.id == ctx.evento.entidad }) else { return .nada("No encuentro el cobro \(ctx.evento.entidad).") }
        guard pago.esCobroConfirmado else { return .nada("El cobro \(pago.id) no está confirmado.") }
        guard let ruta = l.oportunidad(de: pago), let opo = l.ficha(ruta) else {
            return .nada("El cobro \(pago.id) no va a ninguna oportunidad: es un ingreso suelto.")
        }
        guard !opo.privada else { return .nada("La oportunidad es privada: la pasa a Ganada una persona.") }
        var ops: [WriteOp] = []
        var hecho: [String] = []
        if LecturaDominio.estadoOportunidad(opo.estado) != "Ganada" {
            var poner = [Property(key: "estado", value: .text("Ganada"))]
            if opo.texto("cerrada") == nil { poner.append(Property(key: "cerrada", value: .text((pago.fecha ?? ctx.hoy).description))) }
            ops.append(.mergeFrontmatter(opo.ruta, set: poner, unset: []))
            hecho.append("«\(opo.nombre)» Ganada")
        }
        if l.proyectosDeEntrega(de: opo.ruta).isEmpty {
            let (op, ruta) = try proyectoDeEntrega(opo, ctx: ctx)
            ops += op
            hecho.append("proyecto en «\(ruta.parent?.name ?? ruta.raw)»")
        }
        guard !ops.isEmpty else { return .nada("«\(opo.nombre)» ya estaba Ganada y con su proyecto.") }
        return .plan(WritePlan(autor: .sistema, descripcion: "Cobro confirmado: «\(opo.nombre)» Ganada", ops: ops),
                     resumen: hecho.joined(separator: " y "))
    }

    // MARK: ENT-01 · oportunidad.ganada → su proyecto, si aún no existe

    static let proyectoDeLaGanada = Regla(
        id: "ENT-01·proyecto", evento: .oportunidadGanada, capacidad: "ENT-01", nombre: "La oportunidad ganada tiene su proyecto",
        clave: { e, _ in "ENT-01·proyecto:\(e.entidad)" },
        paraPersona: { ctx in "Abrir el proyecto de «\(ctx.lectura.ficha(ctx.evento.ruta)?.nombre ?? ctx.evento.ruta.stem)»" }
    ) { ctx in
        let l = ctx.lectura
        guard let opo = l.ficha(ctx.evento.ruta) else { return .nada("La oportunidad ya no está en su sitio.") }
        guard l.proyectosDeEntrega(de: opo.ruta).isEmpty else { return .nada("«\(opo.nombre)» ya tiene su proyecto.") }
        guard l.tieneCobroConfirmado(opo.ruta) else {
            return .nada("«\(opo.nombre)» no tiene un cobro confirmado: el proyecto nace con el cobro.")
        }
        let (ops, ruta) = try proyectoDeEntrega(opo, ctx: ctx)
        return .plan(WritePlan(autor: .sistema, descripcion: "Abrir el proyecto de «\(opo.nombre)»", ops: ops),
                     resumen: "Proyecto en «\(ruta.parent?.name ?? ruta.raw)»")
    }

    /// El proyecto de entrega de una oportunidad (plantilla «Proyecto de entrega»), en curso desde hoy (laborable).
    static func proyectoDeEntrega(_ opo: FichaDominio, ctx: ContextoRegla) throws -> ([WriteOp], VaultPath) {
        let l = ctx.lectura
        let empresa = l.relacion(opo, "empresa").flatMap { l.ficha($0) }
        let servicio = l.relacion(opo, "servicio").flatMap { l.ficha($0) }
        let plan = servicio.flatMap { l.relacion($0, "plan") }.flatMap { l.ficha($0) }
        // Carpeta: `<empresa>-<servicio>` (o la de la oportunidad, para un particular), sin pisar otra.
        let base = [empresa?.ruta.stem, servicio?.ruta.stem].compactMap { $0 }.count == 2
            ? "\(empresa!.ruta.stem)-\(servicio!.ruta.stem)" : opo.ruta.stem
        let proyectos = l.layout.areaFolder(.entrega).appending(l.layout.proyectos)
        var carpeta = proyectos.appending(NombresDeFicha.fichero(base))
        var n = 2
        while l.snapshot.existing(carpeta) != nil {
            carpeta = proyectos.appending(NombresDeFicha.fichero("\(base)-\(n)"))
            n += 1
        }
        let inicio = Tarea.laborable(ctx.hoy)
        var poner = [Property(key: "estado", value: .text("En curso")), Property(key: "inicio", value: .text(inicio.description)),
                     Property(key: "origen", value: .text(ctx.origen))]
        if let dias = plan?.texto("dias_proyecto").flatMap({ Int($0) }), dias > 0 {
            poner.append(Property(key: "fin", value: .text(FormatosPlantilla.sumarLaborables(inicio, dias - 1).description)))
        }
        if let p = plan {
            poner.append(Property(key: "plan", value: .text(NombresDeFicha.wikilink(p.ruta, nombre: p.nombre, en: l.snapshot))))
        }
        var valores: [String: String] = [:]
        if empresa == nil { valores["empresa.nombre"] = l.relacion(opo, "contacto").flatMap { l.ficha($0) }?.nombre ?? opo.nombre }
        if servicio == nil { valores["servicio.nombre"] = opo.nombre }
        let motor = PlantillaMotor(snapshot: l.snapshot, opciones: .init(yo: ctx.persona, reloj: l.reloj))
        let nota = try motor.preparar(.init(plantilla: "proyecto-de-entrega", desde: opo.ruta, valores: valores, poner: poner,
                                            carpeta: carpeta, autor: .sistema))
        return (nota.plan.ops, nota.ruta)
    }

    // MARK: FIN-02 · borrador de factura

    static func facturaEnBorrador(_ evento: TipoEvento) -> Regla {
        Regla(id: "FIN-02·factura·\(evento.rawValue)", evento: evento, capacidad: "FIN-02", nombre: "Preparar la factura en borrador",
              clave: { e, _ in "FIN-02·factura:\(e.entidad)" },
              paraPersona: { ctx in "Preparar la factura de «\(ctx.lectura.ficha(ctx.evento.ruta)?.nombre ?? ctx.evento.ruta.stem)»" }
        ) { ctx in
            let l = ctx.lectura
            guard let opo = l.ficha(ctx.evento.ruta) else { return .nada("La oportunidad ya no está en su sitio.") }
            if let f = l.que(apuntan: opo.ruta, por: "oportunidad", tipo: .invoice).first {
                return .nada("Ya tiene factura: «\(f.texto("numero") ?? f.nombre)».")
            }
            let precio = opo.centimos("precio_congelado") ?? l.precioDeOferta(opo.propiedades, desde: opo.ruta)?.centimos
            let servicio = l.relacion(opo, "servicio").flatMap { l.ficha($0) }
            let iva = l.relacion(opo, "oferta_version").flatMap { l.ficha($0) }?.texto("iva_pct") ?? servicio?.texto("iva_pct")
            var linea: [String: String] = ["concepto": servicio?.nombre ?? opo.nombre, "cantidad": "1", "descuento": "0"]
            if let p = precio { linea["precio"] = Euros.escrito(p); linea["importe"] = Euros.escrito(p) }
            if let i = iva { linea["iva_pct"] = i }
            var valores: [String: String] = [:]
            if l.relacion(opo, "empresa") == nil {
                valores["empresa.slug"] = l.relacion(opo, "contacto")?.stem ?? opo.ruta.stem
            }
            let motor = PlantillaMotor(snapshot: l.snapshot, opciones: .init(yo: Autor.sistema.etiqueta, reloj: l.reloj))
            let nota = try motor.preparar(.init(plantilla: "factura", desde: opo.ruta, valores: valores, listas: ["linea": [linea]],
                                                poner: [Property(key: "origen", value: .text(ctx.origen))], autor: .sistema))
            return .plan(WritePlan(autor: .sistema, descripcion: "Factura en borrador de «\(opo.nombre)»", ops: nota.plan.ops),
                         resumen: "Factura en borrador «\(nota.ruta.stem)»")
        }
    }

    // MARK: FIN-10 · borrador de contrato

    static func contratoEnBorrador(_ evento: TipoEvento) -> Regla {
        Regla(id: "FIN-10·contrato·\(evento.rawValue)", evento: evento, capacidad: "FIN-10", nombre: "Preparar el contrato en borrador",
              clave: { e, _ in "FIN-10·contrato:\(e.entidad)" },
              paraPersona: { ctx in "Preparar el contrato de «\(ctx.lectura.ficha(ctx.evento.ruta)?.nombre ?? ctx.evento.ruta.stem)»" }
        ) { ctx in
            let l = ctx.lectura
            guard let opo = l.ficha(ctx.evento.ruta) else { return .nada("La oportunidad ya no está en su sitio.") }
            if let c = l.que(apuntan: opo.ruta, por: "oportunidad", tipo: .agreement).first {
                return .nada("Ya tiene contrato: «\(c.nombre)».")
            }
            let motor = PlantillaMotor(snapshot: l.snapshot, opciones: .init(yo: Autor.sistema.etiqueta, reloj: l.reloj))
            do {
                let nota = try motor.preparar(.init(plantilla: "contrato", desde: opo.ruta, autor: .sistema))
                return .plan(WritePlan(autor: .sistema, descripcion: "Contrato en borrador de «\(opo.nombre)»", ops: nota.plan.ops),
                             resumen: "Contrato en borrador")
            } catch PlantillaError.yaExiste {
                return .nada("Ya tiene contrato.")
            }
        }
    }

    // MARK: ENT-02 · proyecto.creado → tareas del plan de entrega

    static let tareasDelPlan = Regla(
        id: "ENT-02·tareas", evento: .proyectoCreado, capacidad: "ENT-02", nombre: "Crear las tareas del plan de entrega",
        clave: { e, _ in "ENT-02·tareas:\(e.entidad)" },
        paraPersona: { ctx in "Crear las tareas del plan de entrega de «\(ctx.lectura.ficha(ctx.evento.ruta)?.nombre ?? ctx.evento.ruta.stem)»" }
    ) { ctx in
        let l = ctx.lectura
        guard let proyecto = l.ficha(ctx.evento.ruta) else { return .nada("El proyecto ya no está en su sitio.") }
        guard l.esDeEntrega(proyecto.propiedades, ruta: proyecto.ruta) else { return .nada("Es un proyecto interno: no tiene plan de entrega.") }
        let planRuta = l.relacion(proyecto, "plan")
            ?? l.relacion(proyecto, "servicio").flatMap { l.ficha($0) }.flatMap { l.relacion($0, "plan") }
            ?? l.relacion(proyecto, "oportunidad").flatMap { l.ficha($0) }.flatMap { l.relacion($0, "servicio") }
                .flatMap { l.ficha($0) }.flatMap { l.relacion($0, "plan") }
        guard let pr = planRuta, let texto = l.snapshot.text(pr) else { return .nada("El servicio no tiene plan de entrega.") }
        let plan = PlanDeEntrega.leer(texto)
        let tareas = plan.fases.flatMap { f in f.tareas.map { (f, $0) } }
        guard !tareas.isEmpty else { return .nada("El plan de entrega no tiene tareas.") }
        // Si ya hay tareas de esta regla en el proyecto, no se repiten.
        let carpeta = proyecto.ruta.parent ?? .root
        if l.fichas(.task).contains(where: { $0.ruta.isDescendant(of: carpeta) && $0.texto("origen") == ctx.origen }) {
            return .nada("El proyecto ya tiene las tareas de su plan.")
        }
        let inicio = Tarea.laborable(proyecto.fecha("inicio") ?? ctx.hoy)
        let responsable = proyecto.texto("responsable") ?? ctx.persona
        let nuevas = tareas.map { fase, t -> NuevaTarea in
            let quien: String
            switch TextFolding.fold(t.quien ?? "") {
            case "", "responsable": quien = responsable
            default: quien = t.quien!
            }
            let props = [Property(key: "fase", value: .text(fase.nombre)), Property(key: "capacidad", value: .text("ENT-02"))]
            return NuevaTarea(titulo: t.titulo, proyecto: proyecto.ruta, responsable: quien, estado: .porHacer, tipo: "tarea",
                              planificada: FormatosPlantilla.sumarLaborables(inicio, t.dia),
                              descripcion: t.seAcepta.map { "Se acepta cuando: \($0)" }, origen: ctx.origen,
                              autor: .sistema, propiedades: props)
        }
        guard let lote = try TareasEnLote.preparar(nuevas, snapshot: l.snapshot, reloj: l.reloj, autor: .sistema,
                                                   descripcion: "Tareas del plan de «\(proyecto.nombre)»") else {
            return .nada("El plan de entrega no tiene tareas.")
        }
        return .plan(lote.plan, resumen: Plural.de(lote.rutas.count, "tarea", "tareas") + " del plan, en días laborables")
    }

    // MARK: ENT-11 · MAR-05 · proyecto.cerrado → testimonio y caso para Marca

    static let testimonio = contenidoDeCierre(id: "ENT-11·testimonio", capacidad: "ENT-11", plantilla: "testimonio", tipo: "testimonio",
                                              nombre: "Pedir el testimonio al cerrar") { p, l in
        let quien = l.relacion(p, "empresa").flatMap { l.ficha($0) }?.nombre ?? l.relacion(p, "contacto").flatMap { l.ficha($0) }?.nombre ?? p.nombre
        return "Testimonio de \(quien)"
    }

    static let casoDeExito = contenidoDeCierre(id: "MAR-05·caso", capacidad: "MAR-05", plantilla: "caso-de-exito", tipo: "caso",
                                               nombre: "Proponer el caso de cliente") { p, _ in "Caso: \(p.nombre)" }

    static func contenidoDeCierre(id: String, capacidad: String, plantilla: String, tipo: String, nombre: String,
                                  titulo: @escaping @Sendable (FichaDominio, LecturaDominio) -> String) -> Regla {
        Regla(id: id, evento: .proyectoCerrado, capacidad: capacidad, nombre: nombre,
              clave: { e, _ in "\(id):\(e.entidad)" },
              paraPersona: { ctx in ctx.lectura.ficha(ctx.evento.ruta).map { titulo($0, ctx.lectura) } }
        ) { ctx in
            let l = ctx.lectura
            guard let p = l.ficha(ctx.evento.ruta) else { return .nada("El proyecto ya no está en su sitio.") }
            if l.que(apuntan: p.ruta, por: "proyecto", tipo: .content).contains(where: { TextFolding.fold($0.texto("tipo") ?? "") == tipo }) {
                return .nada("Ya hay un \(tipo) de este proyecto.")
            }
            let motor = PlantillaMotor(snapshot: l.snapshot, opciones: .init(yo: ctx.persona, reloj: l.reloj))
            let t = titulo(p, l)
            let nota = try motor.preparar(.init(plantilla: plantilla, desde: p.ruta, valores: ["titulo": t],
                                                poner: [Property(key: "origen", value: .text(ctx.origen))], area: .marca, autor: .sistema))
            return .plan(WritePlan(autor: .sistema, descripcion: "«\(t)» para Marca", ops: nota.plan.ops), resumen: "«\(t)» como idea en Marca")
        }
    }
}
