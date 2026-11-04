import Foundation
import MCP
import TLSCore
import TLSMCPShared

// Decisión (PLAN §5.4): preguntar (1-3-1), proponer (tarjeta con el plan guardado) y registrar lo que decidiste tú.
// Sensibles: `tls_solicitar_accion` **siempre** responde «aprobación requerida» y nunca ejecuta nada.
extension ServidorDeHerramientas {
    func preguntar(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        // F4 · corrector (R3): lo que escribe el asistente va sin estructura de la app (ni `## Actividad` ni
        // `### … · Manu`): así nadie puede «contestar» su propia pregunta como la persona.
        let pregunta = try a.lineaObligatoria("pregunta", max: 300)
        let porQue = try a.cuerpo("por_que", max: 2000)
        let propuesta = try a.cuerpo("propuesta", max: 2000)
        let opciones = try a.lista("opciones", max: 3).map(TextoDeAsistente.linea)
        let pedida = try a.area()
        let area = pedida.flatMap { c.areasEscribibles.contains($0) ? $0 : nil } ?? c.areas.first ?? .direccion
        try comprobarTope(c)
        let (foto, reloj) = await fotoYReloj()
        let store = TaskStore(snapshot: foto, reloj: reloj)
        var loQuePropongo = propuesta ?? ""
        if !opciones.isEmpty {
            loQuePropongo += (loQuePropongo.isEmpty ? "" : "\n\n") + opciones.enumerated().map { i, o in
                "\(i + 1). \(o)" + (i == 0 ? " (recomendada)" : "")
            }.joined(separator: "\n")
        }
        var secciones = ["Pregunta": pregunta]
        if let p = porQue { secciones["Por qué la hago"] = p }
        if !loQuePropongo.isEmpty { secciones["Lo que propongo"] = loQuePropongo }
        let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: c.autor.etiqueta, copiarGuias: false, reloj: reloj))
        let nota = try motor.preparar(PlantillaMotor.Peticion(
            plantilla: "pregunta-asistente",
            valores: ["titulo": pregunta, "asistente": c.asistente, "numero": String(format: "T-%04d", store.siguienteNumero())],
            poner: [Property(key: "responsable", value: .text(d.persona)), Property(key: "estado", value: .text(EstadoTarea.enRevision.rawValue)),
                    Property(key: "tipo", value: .text("pregunta")), Property(key: "origen", value: .text(c.autor.etiqueta)),
                    Property(key: "creada_por", value: .text(c.autor.etiqueta)), Property(key: "ejecucion", value: .text(c.ejecucion))]
                + propiedadesDeEjecucion(c),
            secciones: secciones, area: area, carpeta: store.carpeta(area: area, proyecto: nil), autor: c.autor))
        let plan = preparar(nota.plan)
        try exigir(await autorizar(c, "preguntar", .decision, rutas: [nota.ruta], area: area, plan: plan))
        let r = try await escribir(plan, c)
        sumarTarea(c.ejecucion)
        let ruta = r.creadas.first ?? nota.ruta
        let id = Self.idDe(nota.texto) ?? ruta.raw
        await d.servicios.esperarRespuesta(EsperaDeRespuesta(ejecucion: c.ejecucion, asistente: c.asistente, pregunta: ruta, preguntaID: id))
        return Respuesta.hecho("Pregunta hecha. Tu trabajo queda esperando la respuesta de \(d.persona): cierra con tls_finalizar.",
                               ["estado": "esperando_respuesta", "pregunta_id": .string(id), "numero": .opcional(nota.numero),
                                "ruta": .string(ruta.raw)])
    }

    func proponer(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let titulo = try a.lineaObligatoria("titulo", max: 200)
        let opciones = try a.lista("opciones", max: 3).map(TextoDeAsistente.linea)
        guard !opciones.isEmpty else { throw ErrorDeArgumentos("Hace falta al menos una opción (la recomendada, la primera).") }
        let problema = try a.cuerpo("problema", max: 1000) ?? titulo
        let porQue = try a.cuerpo("por_que", max: 2000) ?? ""
        let area = try a.area() ?? c.areas.first ?? .direccion
        var plan: WritePlan?
        if let destino = try a.texto("ruta", max: 400) {
            guard let ruta = d.vista.resolver(destino, alcance: c.lectura).ruta, !ruta.isRoot else {
                auditar(c, "proponer", ruta: destino, veredicto: "no_encontrado")
                return Respuesta.noEncontrado
            }
            var ops: [WriteOp] = []
            if let props = a.valores["propiedades"]?.objectValue, !props.isEmpty {
                var poner: [Property] = []
                for (k, v) in props.sorted(by: { $0.key < $1.key }) {
                    guard k.range(of: #"^[a-z][a-z0-9_]{0,40}$"#, options: .regularExpression) != nil,
                          !["tls_type", "tls_schema", "id"].contains(k), let s = v.stringValue else {
                        throw ErrorDeArgumentos("La propiedad «\(k)» no se puede proponer así.")
                    }
                    poner.append(Property(key: k, value: .text(s)))
                }
                ops.append(.mergeFrontmatter(ruta, set: poner, unset: []))
            }
            if let texto = try a.cuerpo("anadir", max: 8000) { ops.append(.appendLine(ruta, line: texto)) }
            if !ops.isEmpty { plan = WritePlan(autor: .persona(d.persona), descripcion: titulo, ops: ops) }
            // F4 · corrector (R9): una propuesta no es la puerta trasera de lo que solo hace una aprobación (emitir o
            // numerar una factura, el estado de un borrador, confirmar un cobro) ni de lo vetado (`Roles/`,
            // `AGENTS.md`, `Empresa.md`, `Metas.md`, `vence`, cerrar tareas…). El gobierno lo vuelve a mirar al aplicar.
            if let p = plan, let motivo = Autorizador.motivoParaNoProponer(p, root: d.vista.root, layout: d.vista.layout) {
                auditar(c, "proponer", ruta: ruta.raw, veredicto: "denegado", motivo: motivo)
                throw ErrorDeHerramienta(motivo)
            }
        }
        let (ruta, id) = try await crearPropuesta(c, titulo: titulo, problema: problema, opciones: opciones, porQue: porQue,
                                                  area: area, origen: nil, plan: plan)
        return Respuesta.hecho("Propuesta lista para que decida \(d.persona). Nada cambia hasta que elija.",
                               ["estado": "propuesta", "propuesta_id": .string(id), "ruta": .string(ruta.raw)])
    }

    /// Tarjeta 1-3-1 (`tipo: decision`, para la persona, `En revisión`) y el plan guardado para aplicarlo **como
    /// persona** si elige la primera opción.
    func crearPropuesta(_ c: ContextoDelAsistente, titulo: String, problema: String, opciones: [String], porQue: String,
                        area pedida: AreaCode, origen: String?, plan: WritePlan?, capacidad: String? = nil) async throws -> (VaultPath, String) {
        try comprobarTope(c)
        let area = c.areasEscribibles.contains(pedida) ? pedida : (c.areas.first ?? .direccion)
        let (foto, reloj) = await fotoYReloj()
        let store = TaskStore(snapshot: foto, reloj: reloj)
        func celda(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var tabla = "| # | Opción | A favor | En contra | Coste o riesgo |\n|---|---|---|---|---|\n"
        for (i, o) in opciones.prefix(3).enumerated() {
            tabla += "| \(i + 1) | \(celda(o))\(i == 0 && !o.contains("recomendada") ? " (recomendada)" : "") | | | |\n"
        }
        var secciones = ["Problema": problema, "Opciones": tabla]
        if !porQue.isEmpty { secciones["Por qué recomiendo la 1"] = porQue }
        let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: c.autor.etiqueta, copiarGuias: false, reloj: reloj))
        let nota = try motor.preparar(PlantillaMotor.Peticion(
            plantilla: "decision-1-3-1",
            valores: ["titulo": titulo, "numero": String(format: "T-%04d", store.siguienteNumero())],
            poner: [Property(key: "responsable", value: .text(d.persona)), Property(key: "estado", value: .text(EstadoTarea.enRevision.rawValue)),
                    Property(key: "tipo", value: .text("decision")), Property(key: "origen", value: .text(origen ?? c.autor.etiqueta)),
                    Property(key: "creada_por", value: .text(c.autor.etiqueta)), Property(key: "ejecucion", value: .text(c.ejecucion))]
                + propiedadesDeEjecucion(c),
            secciones: secciones, area: area, carpeta: store.carpeta(area: area, proyecto: nil), autor: c.autor))
        let tarjeta = preparar(nota.plan)
        try exigir(await autorizar(c, "proponer", .decision, rutas: [nota.ruta], area: area, plan: tarjeta))
        let r = try await escribir(tarjeta, c)
        sumarTarea(c.ejecucion)
        let ruta = r.creadas.first ?? nota.ruta
        let id = try await d.propuestas.guardar(PropuestaDeAsistente(tarjeta: ruta, plan: plan, autor: c.autor,
                                                                     ejecucion: c.ejecucion, resumen: titulo, capacidad: capacidad))
        return (ruta, id)
    }

    func registrarDecision(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let decision = try a.lineaObligatoria("decision", max: 500)
        let porQue = try a.linea("por_que", max: 1000)
        let area = try a.area()
        let origen = try a.texto("origen", max: 200)
        let (foto, reloj) = await fotoYReloj()
        let nueva = NuevaDecision(fecha: reloj.hoy, decision: decision, porque: porQue, area: area?.nombre, origen: origen)
        guard let o = origen, origenValido(o, c, foto: foto, reloj: reloj) else {
            // Sin una decisión tuya detrás, no se apunta: queda como propuesta.
            let (planPersona, _) = try RegistroDecisiones.anadir(nueva, en: foto, autor: .persona(d.persona))
            let (ruta, id) = try await crearPropuesta(
                c, titulo: "Apuntar la decisión: \(decision)", problema: "¿Quieres dejar esta decisión en Decisiones?",
                opciones: ["Apuntarla", "No apuntarla"], porQue: porQue ?? "", area: area ?? .direccion, origen: nil,
                plan: WritePlan(autor: .persona(d.persona), descripcion: planPersona.descripcion,
                                ops: planPersona.ops.filter { !$0.path.components.contains { $0.hasPrefix(".") } }))
            return Respuesta.hecho("No veo que lo decidieras tú (falta «chat:…» o «pregunta:…» válido): lo dejo como propuesta.",
                                   ["estado": "convertida_en_propuesta", "propuesta_id": .string(id), "ruta": .string(ruta.raw)])
        }
        let (bruto, id) = try RegistroDecisiones.anadir(nueva, en: foto, autor: c.autor)
        let plan = preparar(bruto)
        try exigir(await autorizar(c, "decision.registrar", .decision, rutas: plan.ops.map(\.path), area: area ?? .direccion,
                                   plan: plan, origen: o))
        _ = try await escribir(plan, c, dominio: true)
        return Respuesta.hecho("Decisión apuntada en Decisiones.", ["estado": "hecho", "id": .string(id), "origen": .string(o)])
    }

    /// El origen de **esta** ejecución, que pone el motor en el token y nunca el asistente: `chat:<id>` (la persona le
    /// escribe en ⌘J) o `pregunta:<ruta>` (la persona contestó su pregunta y por eso se reanudó). Una pregunta vale
    /// también por su id o su número si es la misma de la que viene la ejecución. F4 · corrector (R2): antes bastaba con
    /// que el fichero de la pregunta tuviera una línea `### … · Manu`, y esa línea la podía escribir el propio asistente.
    func origenValido(_ origen: String, _ c: ContextoDelAsistente, foto: VaultSnapshot, reloj: Reloj) -> Bool {
        guard let propio = c.origen?.trimmingCharacters(in: .whitespaces), !propio.isEmpty else { return false }
        let pedido = origen.trimmingCharacters(in: .whitespaces)
        if pedido == propio { return true }
        let prefijo = "pregunta:"
        guard propio.hasPrefix(prefijo), pedido.hasPrefix(prefijo) else { return false }
        let store = TaskStore(snapshot: foto, reloj: reloj)
        func pregunta(_ origen: String) -> VaultPath? {
            let id = String(origen.dropFirst(prefijo.count)).trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty else { return nil }
            return store.tareas.first(where: {
                $0.tipo == "pregunta" && d.vista.esVisible($0.ruta)
                    && ($0.uid == id || $0.numero?.caseInsensitiveCompare(id) == .orderedSame
                        || TextFolding.pathKey($0.ruta.raw) == TextFolding.pathKey(id))
            })?.ruta
        }
        guard let a = pregunta(propio), let b = pregunta(pedido) else { return false }
        return a == b
    }

    /// **Siempre** `{"estado":"aprobacion_requerida","id":…}`, en cualquier modo: la acción la ejecuta la app al
    /// aprobar, nunca el asistente.
    func solicitarAccion(_ args: [String: Value], _ c: ContextoDelAsistente) async -> ToolResult {
        let accion = args["accion"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        let borradorTexto = args["borrador_id"]?.stringValue?.trimmingCharacters(in: .whitespaces) ?? ""
        func respuesta(_ id: String?, registrada: Bool, motivo: String? = nil) -> ToolResult {
            var v: [String: Value] = ["estado": "aprobacion_requerida", "id": .opcional(id), "registrada": .bool(registrada)]
            if let m = motivo { v["motivo"] = .string(m) }
            let texto = registrada
                ? "Aprobación requerida: \(d.persona) lo decide en Decisiones. No se ha enviado ni hecho nada."
                : "Aprobación requerida. No se ha enviado ni hecho nada." + (motivo.map { " " + $0 } ?? "")
            auditar(c, "accion.solicitar:\(accion)", ruta: borradorTexto, veredicto: "aprobacion_requerida", motivo: motivo)
            return Respuesta.hecho(texto, v)
        }
        guard CatalogoTLS.accionesExternas.contains(accion) else {
            return respuesta(nil, registrada: false, motivo: "No conozco la acción «\(accion)».")
        }
        let (foto, reloj) = await fotoYReloj()
        guard let borrador = buscarBorrador(borradorTexto, c, foto: foto, reloj: reloj) else {
            return respuesta(nil, registrada: false, motivo: "No encuentro ese borrador: prepáralo antes con tls_preparar_borrador.")
        }
        let veredicto = await autorizar(c, "externa", .externa(accion), rutas: [borrador.ruta],
                                        area: d.vista.layout.area(of: borrador.ruta))
        switch veredicto {
        case .denegado(let m): return respuesta(nil, registrada: false, motivo: m)
        case .noEncontrado: return respuesta(nil, registrada: false, motivo: "No encuentro ese borrador.")
        default: break  // permitido o requiereAprobacion: igual, solo se pide.
        }
        do {
            let id = try await d.aprobaciones.solicitar(SolicitudDeAccion(accion: accion, borrador: borrador.ruta, borradorID: borrador.id,
                                                                         autor: c.autor, ejecucion: c.ejecucion))
            return respuesta(id, registrada: true)
        } catch {
            return respuesta(nil, registrada: false, motivo: "No se pudo apuntar la petición.")
        }
    }

    /// Un borrador (`tls_type: draft`) por su `id` o su ruta, visible para el asistente.
    func buscarBorrador(_ texto: String, _ c: ContextoDelAsistente, foto: VaultSnapshot, reloj: Reloj) -> (ruta: VaultPath, id: String)? {
        guard !texto.isEmpty else { return nil }
        let borradores = LecturaDominio(snapshot: foto, reloj: reloj).fichas(.draft).filter {
            !$0.privada && d.vista.esVisible($0.ruta, alcance: c.lectura)
        }
        if let f = borradores.first(where: { $0.uid == texto }) { return (f.ruta, f.uid ?? f.ruta.raw) }
        if let p = d.vista.resolver(texto, alcance: c.lectura).ruta,
           let f = borradores.first(where: { TextFolding.pathKey($0.ruta.raw) == TextFolding.pathKey(p.raw) }) {
            return (f.ruta, f.uid ?? f.ruta.raw)
        }
        return nil
    }
}
