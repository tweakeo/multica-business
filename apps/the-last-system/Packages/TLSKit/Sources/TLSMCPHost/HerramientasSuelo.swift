import Foundation
import MCP
import TLSAgents
import TLSCore
import TLSMCPShared

// Herramientas del suelo fijo (PLAN §5.2 `PermisoBase`): valen sin OK en cualquier modo salvo `off`, con el
// interruptor encendido, el rol activo, el área sin pausa y fuera de lo privado. Nunca `vence`, Hecha ni Cancelada.
extension ServidorDeHerramientas {
    func crearTarea(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let titulo = try a.lineaObligatoria("titulo", max: 200)
        let estadoTexto = try a.texto("estado", max: 20)
        let estado = try estadoTexto.map(Self.estadoDeAsistente) ?? .porHacer
        let responsable = try responsable(try a.texto("responsable", max: 80)) ?? d.persona
        // F4 · corrector (R4): encargar a otro asistente es delegar (solo el coordinador, con su profundidad).
        let delegacion = try delegacionPorResponsable(responsable, c, accion: "tarea.crear")
        let proyecto = try ficha(try a.texto("proyecto", max: 400), c)
        let oportunidad = try ficha(try a.texto("oportunidad", max: 400), c)
        // F5 · mail: una tarea que sale de un correo (solo el Cartero) lleva su enlace en `origen`.
        let origenCorreo = try await origenDeCorreo(a, c)
        let (foto, reloj) = await fotoYReloj()
        let area = try a.area() ?? proyecto.flatMap { d.vista.layout.area(of: $0) } ?? c.areas.first ?? .direccion
        guard areasParaCorreo(c, desdeCorreo: origenCorreo != nil).contains(area) else {
            throw ErrorDeHerramienta("Solo puedes crear tareas en tus áreas (\(c.areas.map(\.nombre).joined(separator: ", "))).")
        }
        try comprobarTope(c)
        var extra: [Property] = [Property(key: "creada_por", value: .text(c.autor.etiqueta))] + propiedadesDeEjecucion(c)
        if let cap = try a.linea("capacidad", max: 12) { extra.append(Property(key: "capacidad", value: .text(cap.uppercased()))) }
        if let p = delegacion { extra.append(Property(key: "delegacion", value: .number(String(p)))) }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let nota = try store.crear(NuevaTarea(
            titulo: titulo, area: area, proyecto: proyecto, oportunidad: oportunidad, responsable: responsable, estado: estado,
            prioridad: try a.linea("prioridad", max: 10), tipo: "tarea", planificada: try a.fecha("planificada"),
            descripcion: try a.cuerpo("descripcion", max: 8000), origen: origenCorreo ?? c.autor.etiqueta, autor: c.autor,
            propiedades: extra))
        let plan = preparar(nota.plan)
        try exigir(await autorizar(c, "tarea.crear", .suelo, rutas: [nota.ruta], area: area, profundidad: delegacion, plan: plan))
        let r = try await escribir(plan, c)
        sumarTarea(c.ejecucion)
        let ruta = r.creadas.first ?? nota.ruta
        if let p = delegacion, let slug = DetectorResponsable.slug(responsable) {
            await d.servicios.delegar(Delegacion(de: c.asistente, a: slug, tarea: ruta, profundidad: p, ejecucion: c.ejecucion))
        }
        return Respuesta.hecho("Tarea creada: \(nota.numero ?? "") «\(titulo)».",
                               ["ruta": .string(ruta.raw), "numero": .opcional(nota.numero), "estado": .string(estado.rawValue),
                                "responsable": .string(responsable)])
    }

    func actualizarTarea(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let id = try a.obligatorio("tarea", max: 400)
        let nuevoEstado = try a.texto("estado", max: 20).map(Self.estadoDeAsistente)
        let planificada = try a.fecha("planificada")
        let responsable = try responsable(try a.texto("responsable", max: 80))
        let prioridad = try a.linea("prioridad", max: 10)
        let nota = try a.texto("nota", max: 2000)
        let (foto, reloj) = await fotoYReloj()
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let t = try tarea(id, en: store, c, paraEscribir: true)
        var poner: [Property] = []
        var cambios: [String] = []
        if let p = planificada {
            let laborable = Tarea.laborable(p)
            if laborable != t.planificada {
                poner.append(Property(key: "planificada", value: .text(laborable.description)))
                cambios.append("Planificada: \(t.planificada?.description ?? "sin fecha") → \(laborable)")
            }
        }
        var delegacion: Int?
        if let r = responsable, r != t.responsable {
            // F4 · corrector (R4): pasar una tarea a otro asistente es delegar.
            delegacion = try delegacionPorResponsable(r, c, accion: "tarea.mover")
            poner.append(Property(key: "responsable", value: .text(r)))
            if let p = delegacion { poner.append(Property(key: "delegacion", value: .number(String(p)))) }
            cambios.append("Responsable: \(t.responsable ?? "nadie") → \(r)")
        }
        if let p = prioridad, p != t.prioridad {
            poner.append(Property(key: "prioridad", value: .text(p)))
            cambios.append("Prioridad: \(t.prioridad ?? "sin prioridad") → \(p)")
        }
        let cambiaEstado = nuevoEstado != nil && nuevoEstado != t.estado
        guard cambiaEstado || !poner.isEmpty else { throw ErrorDeHerramienta("La tarea ya está así: no hay nada que cambiar.") }
        var plan: WritePlan
        if cambiaEstado, let e = nuevoEstado {
            let texto = ([nota] + cambios.map { $0 + "." }).compactMap { $0 }.joined(separator: " ")
            plan = try store.cambiarEstado(t, a: e, autor: c.autor, persona: d.persona, nota: texto.isEmpty ? nil : texto)
        } else {
            let texto = (cambios.map { $0 + "." } + [nota].compactMap { $0 }).joined(separator: " ")
            plan = try store.anadirActividad(t, autor: c.autor, texto: texto, evento: ["tipo": "cambio"], persona: d.persona)
        }
        if !poner.isEmpty {
            plan.ops.insert(.mergeFrontmatter(t.ruta, set: poner, unset: []), at: max(0, plan.ops.count - 1))
        }
        try exigir(await autorizar(c, "tarea.mover", .suelo, rutas: [t.ruta], area: t.area, profundidad: delegacion, plan: plan))
        _ = try await escribir(plan, c)
        if let p = delegacion, let r = responsable, let slug = DetectorResponsable.slug(r) {
            await d.servicios.delegar(Delegacion(de: c.asistente, a: slug, tarea: t.ruta, profundidad: p, ejecucion: c.ejecucion))
        }
        return Respuesta.hecho("Tarea «\(t.titulo)» actualizada.",
                               ["ruta": .string(t.ruta.raw), "estado": .string((nuevoEstado ?? t.estado)?.rawValue ?? t.estadoTexto ?? "")])
    }

    func comentar(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let id = try a.obligatorio("tarea", max: 400)
        let texto = try a.obligatorio("texto", max: 8000)
        let (foto, reloj) = await fotoYReloj()
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let t = try tarea(id, en: store, c, paraEscribir: false)
        let plan = try store.anadirActividad(t, autor: c.autor, texto: texto, evento: ["tipo": "comentario"], persona: d.persona)
        try exigir(await autorizar(c, "comentar", .suelo, rutas: [t.ruta], area: t.area, plan: plan))
        _ = try await escribir(plan, c)
        return Respuesta.hecho("Comentario añadido a «\(t.titulo)».", ["ruta": .string(t.ruta.raw)])
    }

    /// Con el formato del gobierno (`Borradores.plan`): así `Borrador.leer` y el hash de la aprobación lo leen igual.
    func prepararBorrador(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let accionTexto = try a.obligatorio("accion", max: 20)
        guard CatalogoTLS.accionesExternas.contains(accionTexto), let accion = AccionExterna(leyendo: accionTexto) else {
            throw ErrorDeArgumentos("No conozco la acción «\(accionTexto)».")
        }
        if let tipo = try a.texto("tipo", max: 20), !["correo", "mensaje", "publicacion", "factura", "pago"].contains(tipo) {
            throw ErrorDeArgumentos("No conozco el tipo «\(tipo)».")
        }
        let asunto = try a.obligatorio("asunto", max: 300)
        let cuerpo = try a.obligatorio("cuerpo", max: 20_000)
        var para = try a.lista("para", max: 20)
        // F5 · mail: una respuesta a un correo (el Cartero, solo a correos que conoce la app); sin destinatario, el remitente.
        let enRespuestaA = try a.texto("en_respuesta_a", max: 400)
        var desdeCorreo = false
        if let r = enRespuestaA, c.asistente == Self.slugCartero {
            guard EnlaceDeCorreo.esEnlace(r), let f = d.correo, await f.mensaje(r) != nil else {
                throw ErrorDeHerramienta("No conozco el correo al que respondes.")
            }
            desdeCorreo = true
        }
        if para.isEmpty, let remitente = await remitenteDe(enRespuestaA) { para = [remitente] }
        let (foto, reloj) = await fotoYReloj()
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let tarea = try a.texto("tarea", max: 400).map { try self.tarea($0, en: store, c, paraEscribir: false) }
        let oportunidad = try ficha(try a.texto("oportunidad", max: 400), c)
        let area = try a.area() ?? tarea?.area ?? oportunidad.flatMap { d.vista.layout.area(of: $0) } ?? c.areas.first ?? .direccion
        guard areasParaCorreo(c, desdeCorreo: desdeCorreo).contains(area) else {
            throw ErrorDeHerramienta("Solo puedes preparar borradores en tus áreas.")
        }
        let nuevo = NuevoBorrador(
            accion: accion, area: area, asunto: asunto, cuerpo: cuerpo, para: para,
            paraTi: (try a.texto("notas", max: 4000)) ?? "Preparado por \(c.asistente) (asistente). Enviar pide tu OK.",
            enRespuestaA: enRespuestaA, tarea: tarea?.ruta, oportunidad: oportunidad,
            ejecucion: c.ejecucion)
        let (ruta0, bruto) = Borradores.plan(nuevo, layout: d.vista.layout, autor: c.autor)
        let plan = preparar(bruto)
        try exigir(await autorizar(c, "borrador.preparar", .suelo, rutas: [ruta0], area: area, plan: plan))
        let r = try await escribir(plan, c)
        let ruta = r.creadas.first ?? ruta0
        let texto: String? = plan.ops.compactMap { op -> String? in
            if case .create(_, let data) = op { return String(data: data, encoding: .utf8) }
            return nil
        }.first
        let id = texto.flatMap(Self.idDe) ?? ruta.raw
        return Respuesta.hecho("Borrador preparado. No se envía nada: para enviarlo, pide la aprobación con tls_solicitar_accion.",
                               ["borrador_id": .string(id), "ruta": .string(ruta.raw), "accion": .string(accion.rawValue)])
    }

    func moverArchivo(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let desdeTexto = try a.obligatorio("desde", max: 400)
        let aTexto = try a.obligatorio("a", max: 400)
        guard let buzon = d.vista.layout.buzon else { throw ErrorDeHerramienta("Esta carpeta no tiene Buzón.") }
        guard let desde = d.vista.resolver(desdeTexto).ruta, !desde.isRoot else {
            auditar(c, "buzon.mover", ruta: desdeTexto, veredicto: "no_encontrado")
            return Respuesta.noEncontrado
        }
        guard TextFolding.pathKey(desde.raw).hasPrefix(TextFolding.pathKey(buzon) + "/") else {
            throw ErrorDeHerramienta("Solo puedo mover lo que está en el Buzón.")
        }
        guard let destino = d.vista.resolver(aTexto, alcance: c.escritura, debeExistir: false).ruta, !destino.isRoot,
              !VetosFijos.rutaVetada(destino, layout: d.vista.layout) else {
            auditar(c, "buzon.mover", ruta: aTexto, veredicto: "denegado", motivo: "destino no permitido")
            throw ErrorDeHerramienta("No puedo mover a «\(aTexto)».")
        }
        let plan = WritePlan(autor: c.autor, descripcion: "Mover «\(desde.stem)» desde el Buzón", ops: [.move(desde, to: destino)])
        try exigir(await autorizar(c, "buzon.mover", .suelo, rutas: [desde, destino], area: d.vista.layout.area(of: destino), plan: plan))
        let r = try await escribir(plan, c)
        let final = r.movidas.first?.a ?? destino
        return Respuesta.hecho("Movido a «\(final.raw)» (se puede deshacer).", ["de": .string(desde.raw), "a": .string(final.raw)])
    }

    func proponerConciliacion(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let movimiento = try a.obligatorio("movimiento", max: 40)
        let factura = try a.texto("factura", max: 60)
        guard c.areasEscribibles.contains(.finanzas) else { throw ErrorDeHerramienta("Las conciliaciones son de Finanzas.") }
        let (foto, reloj) = await fotoYReloj()
        let conciliador = Conciliador(snapshot: foto, reloj: reloj)
        let candidatas = conciliador.propuestas.filter {
            $0.movimiento.id == movimiento && (factura == nil || $0.factura.id == factura || $0.factura.numeroVisible == factura)
                && d.vista.esVisible($0.cuenta.movimientosCSV)
        }
        guard let p = candidatas.first else {
            throw ErrorDeHerramienta("No veo una conciliación clara para «\(movimiento)»: coméntalo en tu resumen.")
        }
        guard let plan = conciliador.planProponer([p], autor: c.autor) else {
            return Respuesta.hecho("Ya estaba propuesta.", ["movimiento": .string(movimiento), "factura": .string(p.factura.id)])
        }
        try exigir(await autorizar(c, "conciliacion.proponer", .suelo, rutas: plan.ops.map(\.path), area: .finanzas, plan: plan))
        _ = try await escribir(plan, c)
        return Respuesta.hecho("Conciliación propuesta: confirmarla es de \(d.persona).",
                               ["movimiento": .string(movimiento), "factura": .string(p.factura.numeroVisible), "motivo": .string(p.motivo)])
    }

    func avisar(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let texto = try a.obligatorio("texto", max: 500)
        let nivelTexto = try a.texto("nivel", max: 10) ?? AvisoDeAsistente.Nivel.info.rawValue
        guard let nivel = AvisoDeAsistente.Nivel(rawValue: nivelTexto) else { throw ErrorDeArgumentos("No conozco el nivel «\(nivelTexto)».") }
        let ruta = try a.texto("ruta", max: 400).flatMap { d.vista.resolver($0, alcance: c.lectura).ruta }
        try exigir(await autorizar(c, "avisar", .suelo, rutas: ruta.map { [$0] } ?? []))
        let sale = await d.servicios.avisar(AvisoDeAsistente(ejecucion: c.ejecucion, asistente: c.asistente, texto: texto,
                                                             nivel: nivel, ruta: ruta))
        return Respuesta.hecho(sale ? "Aviso enviado." : "Hoy ya hay muchos avisos: este irá al resumen.",
                               ["estado": .string(sale ? "avisado" : "al_resumen")])
    }

    func programarSeguimiento(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let id = try a.obligatorio("tarea", max: 400)
        guard let fecha = try a.fecha("fecha") else { throw ErrorDeArgumentos("Falta «fecha».") }
        let motivo = try a.texto("motivo", max: 500)
        let (foto, reloj) = await fotoYReloj()
        guard fecha >= reloj.hoy else { throw ErrorDeArgumentos("La fecha tiene que ser hoy o más adelante.") }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let t = try tarea(id, en: store, c, paraEscribir: true)
        var plan = try store.anadirActividad(t, autor: c.autor, texto: "Seguimiento programado para el \(fecha)." + (motivo.map { " " + $0 } ?? ""),
                                             evento: ["tipo": "seguimiento", "despertar": fecha.description], persona: d.persona)
        plan.ops.insert(.mergeFrontmatter(t.ruta, set: [Property(key: "despertar", value: .text(fecha.description))], unset: []),
                        at: max(0, plan.ops.count - 1))
        try exigir(await autorizar(c, "seguimiento.programar", .suelo, rutas: [t.ruta], area: t.area, plan: plan))
        _ = try await escribir(plan, c)
        return Respuesta.hecho("Volveré a mirarla el \(fecha).", ["ruta": .string(t.ruta.raw), "despertar": .string(fecha.description)])
    }

    func delegar(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        guard c.coordinador else { throw ErrorDeHerramienta("Solo el coordinador puede delegar.") }
        let slug = try a.obligatorio("asistente", max: 40).lowercased()
        guard slug.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }), slug != c.asistente else {
            throw ErrorDeArgumentos("«asistente» no es válido.")
        }
        let titulo = try a.lineaObligatoria("titulo", max: 200)
        let profundidad = c.profundidad + 1
        guard profundidad <= ContextoDelAsistente.profundidadMaxima else {
            auditar(c, "delegar", veredicto: "denegado", motivo: "profundidad \(profundidad)")
            throw ErrorDeHerramienta("No se puede delegar más de \(ContextoDelAsistente.profundidadMaxima) niveles: hazlo tú o pregunta.")
        }
        try comprobarTope(c)
        let area = try a.area() ?? .direccion
        let (foto, reloj) = await fotoYReloj()
        let store = TaskStore(snapshot: foto, reloj: reloj)
        let nota = try store.crear(NuevaTarea(
            titulo: titulo, area: area, responsable: "agente:" + slug, estado: .porHacer, tipo: "tarea",
            descripcion: try a.cuerpo("descripcion", max: 8000), origen: c.autor.etiqueta, autor: c.autor,
            propiedades: [Property(key: "creada_por", value: .text(c.autor.etiqueta)),
                          Property(key: "delegacion", value: .number(String(profundidad)))] + propiedadesDeEjecucion(c)))
        let plan = preparar(nota.plan)
        try exigir(await autorizar(c, "delegar", .suelo, rutas: [nota.ruta], area: area, profundidad: profundidad, plan: plan))
        let r = try await escribir(plan, c)
        sumarTarea(c.ejecucion)
        let ruta = r.creadas.first ?? nota.ruta
        await d.servicios.delegar(Delegacion(de: c.asistente, a: slug, tarea: ruta, profundidad: profundidad, ejecucion: c.ejecucion))
        return Respuesta.hecho("Encargado a \(slug): «\(titulo)».", ["ruta": .string(ruta.raw), "numero": .opcional(nota.numero),
                                                                     "profundidad": .int(profundidad)])
    }

    func finalizar(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let resumen = try a.obligatorio("resumen", max: 4000)
        let estado = try a.texto("estado_tarea", max: 20).map(Self.estadoDeAsistente) ?? .enRevision
        try exigir(await autorizar(c, "finalizar", .suelo, rutas: c.tarea.map { [$0] } ?? []))
        await d.servicios.finalizar(FinDeEjecucion(ejecucion: c.ejecucion, asistente: c.asistente, resumen: resumen,
                                                   estadoTarea: estado, tarea: c.tarea))
        return Respuesta.hecho("Trabajo cerrado. La app apunta tu resumen en la Actividad y en la Bitácora.",
                               ["estado": "finalizado", "estado_tarea": .string(estado.rawValue)])
    }

    /// F4 · corrector (R4): de quién puede ser lo que crea o reasigna un asistente: de la persona o suyo. Ponerle otro
    /// asistente es encargárselo (el motor lo lanzaría): eso es delegar, solo el coordinador y hasta 2 niveles; se apunta
    /// la profundidad en la tarea (`delegacion: n`). Devuelve esa profundidad, o `nil` si no es una delegación.
    func delegacionPorResponsable(_ responsable: String, _ c: ContextoDelAsistente, accion: String) throws -> Int? {
        guard let slug = DetectorResponsable.slug(responsable), slug != ConfigAgentes.slug(c.asistente) else { return nil }
        guard c.coordinador else {
            auditar(c, accion, veredicto: "denegado", motivo: "encargo a agente:\(slug) sin ser coordinador")
            throw ErrorDeHerramienta("Solo puedes dejar la tarea para \(d.persona) o para ti. Si hace falta otro asistente, "
                                     + "dilo en tu resumen y lo decide el coordinador.")
        }
        let profundidad = c.profundidad + 1
        guard profundidad <= ContextoDelAsistente.profundidadMaxima else {
            auditar(c, accion, veredicto: "denegado", motivo: "profundidad \(profundidad)")
            throw ErrorDeHerramienta("No se puede delegar más de \(ContextoDelAsistente.profundidadMaxima) niveles: hazlo tú o pregunta.")
        }
        return profundidad
    }

    /// Estados que puede poner un asistente: nunca Hecha ni Cancelada.
    static func estadoDeAsistente(_ texto: String) throws -> EstadoTarea {
        guard let e = EstadoTarea(leyendo: texto) else { throw ErrorDeArgumentos("No conozco el estado «\(texto)».") }
        guard !e.cerrada else {
            throw ErrorDeArgumentos("Un asistente no pone una tarea en «\(e.rawValue)»: la deja en revisión y decide la persona.")
        }
        return e
    }
}

/// `agente:<slug>` → slug (sin mayúsculas ni tildes); `nil` si no es un asistente.
enum DetectorResponsable {
    static func slug(_ responsable: String?) -> String? {
        guard let r = responsable?.trimmingCharacters(in: .whitespaces), r.lowercased().hasPrefix("agente:") else { return nil }
        let s = ConfigAgentes.slug(String(r.dropFirst("agente:".count)))
        return s.isEmpty ? nil : s
    }
}
