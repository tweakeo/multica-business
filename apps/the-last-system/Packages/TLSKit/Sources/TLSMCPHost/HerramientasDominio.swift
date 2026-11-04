import Foundation
import MCP
import TLSCore
import TLSMCPShared

// Herramientas de dominio (PLAN §5.4): reflejan en las fichas lo que pasó fuera. Las gobierna el modo de su
// capacidad (§5.2): `off` nada, `manual` tarea para la persona, `asistido` propuesta, `supervisado`/`autonomo` se hace.
// Todas llevan `origen` (`ext:<servidor>:<id>`): una segunda sincronización no duplica nada.
extension ServidorDeHerramientas {
    /// Autoriza la acción de dominio y la hace, la propone o la deja como tarea, según el veredicto (por el gobierno si
    /// está conectado; si no, aquí mismo).
    func accionDeDominio(_ c: ContextoDelAsistente, accion: String, capacidad: String, area: AreaCode, plan bruto: WritePlan,
                         titulo: String, detalle: String, origen: String) async throws -> DesenlaceDeDominio {
        // Cerrojos propios antes que nada (vetos fijos y lo privado).
        // El contador de `.tls/secuencias.json` (si la plantilla lo añade) no cuenta: lo escribe la app aparte.
        let rutas = bruto.ops.map(\.path).filter { $0 != Secuencias.ruta }
        let base = peticion(c, accion, .dominio(capacidad: capacidad), rutas: rutas, area: area, plan: bruto)
        if let v = VetosFijos.comprobar(base) { try exigir(v) }
        if rutas.contains(where: { d.vista.motivoOculto($0) != nil }) { try exigir(.noEncontrado) }
        if let gobierno = d.dominio {
            let r = try await gobierno.escribir(bruto, peticion: base)
            if case .denegado(let m) = r { auditar(c, accion, ruta: rutas.first?.raw, veredicto: "denegado", motivo: m) }
            return r
        }
        let plan = preparar(bruto)
        let veredicto = await autorizar(c, accion, .dominio(capacidad: capacidad), rutas: plan.ops.map(\.path), area: area, plan: plan)
        switch veredicto {
        case .permitido:
            return .hecho(try await escribir(plan, c, dominio: true))
        case .propuesta:
            let (ruta, id) = try await crearPropuesta(
                c, titulo: titulo, problema: detalle, opciones: ["Hacerlo (recomendada)", "No hacerlo", "Hacerlo yo a mano"],
                porQue: "Lo informa otro programa (\(origen)).", area: area, origen: origen,
                plan: WritePlan(autor: .persona(d.persona), descripcion: titulo, ops: plan.ops), capacidad: capacidad)
            return .propuesta(ruta, id)
        case .tareaParaPersona:
            try comprobarTope(c)
            let (foto, reloj) = await fotoYReloj()
            let nota = try TaskStore(snapshot: foto, reloj: reloj).crear(NuevaTarea(
                titulo: titulo, area: area, responsable: d.persona, estado: .porHacer, tipo: "tarea",
                descripcion: detalle + "\n\nOrigen: " + origen, origen: origen, autor: c.autor,
                propiedades: [Property(key: "creada_por", value: .text(c.autor.etiqueta)),
                              Property(key: "capacidad", value: .text(capacidad))] + propiedadesDeEjecucion(c)))
            let tarea = preparar(nota.plan)
            try exigir(await autorizar(c, "tarea.crear", .suelo, rutas: [nota.ruta], area: area, plan: tarea))
            let r = try await escribir(tarea, c)
            sumarTarea(c.ejecucion)
            return .tareaParaPersona(r.creadas.first ?? nota.ruta)
        default:
            try exigir(veredicto)
            throw ErrorDeHerramienta("No se pudo hacer.")
        }
    }

    func respuesta(_ desenlace: DesenlaceDeDominio, hecho: String, ruta: VaultPath) -> ToolResult {
        switch desenlace {
        case .hecho(let r):
            return Respuesta.hecho(hecho, ["estado": "hecho", "ruta": .string((r.creadas.first ?? ruta).raw)])
        case .propuesta(let tarjeta, let id):
            return Respuesta.hecho("Lo he dejado como propuesta para que decida \(d.persona).",
                                   ["estado": "convertida_en_propuesta", "propuesta_id": .string(id), "ruta": .string(tarjeta.raw)])
        case .tareaParaPersona(let t):
            return Respuesta.hecho("Esta función la hace \(d.persona) a mano: le he dejado una tarea.",
                                   ["estado": "tarea_para_persona", "ruta": .string(t.raw)])
        case .denegado(let m):
            return Respuesta.error(m)
        case .noEncontrado:
            return Respuesta.noEncontrado
        }
    }

    /// ¿Hay ya algo de este origen (una ficha o una tarjeta/tarea que lo propone)?
    func yaRegistrado(_ origen: String, tipo: NoteKind, en foto: VaultSnapshot, reloj: Reloj) async -> VaultPath? {
        let lectura = LecturaDominio(snapshot: foto, reloj: reloj)
        if let f = lectura.fichas(tipo).first(where: { !$0.privada && d.vista.esVisible($0.ruta) && $0.texto("origen") == origen }) {
            return f.ruta
        }
        if let t = TaskStore(snapshot: foto, reloj: reloj).tareas.first(where: {
            $0.origen == origen && d.vista.esVisible($0.ruta) && !($0.estado?.cerrada ?? false)
        }) {
            return t.ruta
        }
        // Una propuesta aún sin decidir con ese mismo origen (modo asistido).
        return await d.propuestas.pendiente(conOrigen: origen)
    }

    func registrarContacto(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let nombre = try a.obligatorio("nombre", max: 200)
        let origen = try a.obligatorio("origen", max: 200)
        let email = try a.texto("email", max: 200)
        let (foto, reloj) = await fotoYReloj()
        if let ya = await yaRegistrado(origen, tipo: .contact, en: foto, reloj: reloj) {
            return Respuesta.hecho("Ya estaba apuntado: no lo repito.", ["estado": "ya_registrado", "ruta": .string(ya.raw)])
        }
        if let e = email.map(TextFolding.fold), let f = LecturaDominio(snapshot: foto, reloj: reloj).fichas(.contact).first(where: {
            !$0.privada && d.vista.esVisible($0.ruta) && $0.texto("email").map(TextFolding.fold) == e
        }) {
            return Respuesta.hecho("Ya hay un contacto con ese correo: no lo repito.", ["estado": "ya_registrado", "ruta": .string(f.ruta.raw)])
        }
        var poner: [Property] = [Property(key: "origen", value: .text(origen)), Property(key: "creada_por", value: .text(c.autor.etiqueta))]
        if let e = email { poner.append(Property(key: "email", value: .text(e))) }
        if let t = try a.texto("telefono", max: 40) { poner.append(Property(key: "telefono", value: .text(t))) }
        if let canal = try a.texto("canal", max: 80) { poner.append(Property(key: "canal", value: .text(canal))) }
        var valores = ["titulo": nombre, "nombre": nombre]
        if let e = email { valores["email"] = e }
        if let emp = try a.texto("empresa", max: 200) { valores["empresa"] = emp }
        var secciones: [String: String] = [:]
        if let n = try a.texto("notas", max: 4000) { secciones["Notas"] = n }
        secciones["Cómo llegó"] = "Lo apuntó \(c.asistente) (asistente) desde \(origen)."
        let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: c.autor.etiqueta, copiarGuias: false, reloj: reloj))
        let nota = try motor.preparar(PlantillaMotor.Peticion(plantilla: "contacto", valores: valores, poner: poner,
                                                             secciones: secciones, area: .ventas, autor: c.autor))
        let resultado = try await accionDeDominio(c, accion: "contacto.registrar", capacidad: CatalogoTLS.capacidadContacto,
                                                  area: .ventas, plan: nota.plan, titulo: "Apuntar el contacto «\(nombre)»",
                                                  detalle: "Contacto nuevo: \(nombre)" + (email.map { " (\($0))" } ?? "") + ".",
                                                  origen: origen)
        return respuesta(resultado, hecho: "Contacto apuntado: «\(nombre)».", ruta: nota.ruta)
    }

    func registrarOportunidad(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let nombre = try a.obligatorio("nombre", max: 200)
        let origen = try a.obligatorio("origen", max: 200)
        let (foto, reloj) = await fotoYReloj()
        if let ya = await yaRegistrado(origen, tipo: .opportunity, en: foto, reloj: reloj) {
            return Respuesta.hecho("Ya estaba apuntada: no la repito.", ["estado": "ya_registrado", "ruta": .string(ya.raw)])
        }
        let contacto = try ficha(try a.texto("contacto", max: 400), c)
        let layout = d.vista.layout
        let carpeta = layout.dir(for: "opportunity") ?? layout.areaFolder(.ventas).appending("Oportunidades")
        var slug = NombresDeFicha.slug(nombre, maximo: 60)
        if slug.isEmpty { slug = "oportunidad" }
        var ruta = carpeta.appending(slug + ".md")
        var n = 2
        while foto.existing(ruta) != nil { ruta = carpeta.appending("\(slug)-\(n).md"); n += 1 }
        var fm = "---\ntls_type: opportunity\ntls_schema: 1\nid: \(UUID().uuidString.lowercased())\n"
        fm += "nombre: \(YAMLTexto.escalar(nombre))\nestado: Prospecto\n"
        if let ct = contacto {
            let enlace = NombresDeFicha.wikilink(ct, nombre: NoteDocument(text: foto.text(ct) ?? "").title(fileStem: ct.stem), en: foto)
            fm += "contacto: \(YAMLTexto.escalar(enlace))\n"
        }
        if let v = try a.numero("valor") { fm += "valor: \(String(format: "%.2f", v))\n" }
        if let canal = try a.texto("canal", max: 80) { fm += "canal: \(YAMLTexto.escalar(canal))\n" }
        fm += "origen: \(YAMLTexto.escalar(origen))\ncreada: \(reloj.hoy)\ncreada_por: \(c.autor.etiqueta)\n---\n"
        var cuerpo = "# \(nombre)\n> Prospecto\n\n## Qué pide y alcance\n"
        if let notas = try a.texto("notas", max: 4000) { cuerpo += notas + "\n" }
        cuerpo += "\n## Decisión\n"
        let plan = WritePlan(autor: c.autor, descripcion: "Crear la oportunidad «\(nombre)»", ops: [.create(ruta, text: fm + "\n" + cuerpo)])
        let resultado = try await accionDeDominio(c, accion: "oportunidad.registrar", capacidad: CatalogoTLS.capacidadOportunidad,
                                                  area: .ventas, plan: plan, titulo: "Apuntar la oportunidad «\(nombre)»",
                                                  detalle: "Oportunidad nueva como Prospecto: \(nombre).", origen: origen)
        return respuesta(resultado, hecho: "Oportunidad apuntada como Prospecto: «\(nombre)».", ruta: ruta)
    }

    func registrarMetricas(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        let texto = try a.obligatorio("contenido", max: 400)
        let origen = try a.obligatorio("origen", max: 200)
        let metricas = try a.mapaNumerico("metricas")
        guard !metricas.isEmpty, metricas.count <= 20 else { throw ErrorDeArgumentos("«metricas» tiene que traer entre 1 y 20 cifras.") }
        guard let ruta = d.vista.resolver(texto, alcance: c.lectura).ruta, !ruta.isRoot else {
            auditar(c, "metricas.registrar", ruta: texto, veredicto: "no_encontrado")
            return Respuesta.noEncontrado
        }
        let (foto, reloj) = await fotoYReloj()
        guard let actual = foto.text(ruta) else { return Respuesta.noEncontrado }
        let marca = "\"origen\":" + Respuesta.json(.string(origen))
        let propuesta = await d.propuestas.pendiente(conOrigen: origen)
        if actual.contains("<!-- tls:metricas ") && actual.contains(marca) || propuesta != nil {
            return Respuesta.hecho("Esas cifras ya estaban apuntadas: no las repito.", ["estado": "ya_registrado", "ruta": .string(ruta.raw)])
        }
        let fecha = try a.fecha("fecha") ?? reloj.hoy
        let cifras = metricas.keys.sorted().map { k -> String in
            let v = metricas[k]!
            return "\(TextoDeAsistente.linea(k)) " + (Int(exactly: v).map(String.init) ?? String(format: "%.2f", v))
        }.joined(separator: " · ")
        let comentario = "<!-- tls:metricas {" + marca + ",\"asistente\":" + Respuesta.json(.string(c.asistente)) + "} -->"
        let linea = "- \(fecha) · \(cifras) " + comentario
        let plan = WritePlan(autor: c.autor, descripcion: "Apuntar cifras de «\(ruta.stem)»",
                             ops: [.appendToSection(ruta, section: "Métricas", text: linea, blankLine: false)])
        let area = d.vista.layout.area(of: ruta) ?? .marca
        let resultado = try await accionDeDominio(c, accion: "metricas.registrar", capacidad: CatalogoTLS.capacidadMetricas, area: area,
                                                  plan: plan, titulo: "Apuntar las cifras de «\(ruta.stem)»",
                                                  detalle: "Cifras del \(fecha): \(cifras).", origen: origen)
        return respuesta(resultado, hecho: "Cifras apuntadas en «\(ruta.stem)».", ruta: ruta)
    }

    func registrarCobroExterno(_ a: Argumentos, _ c: ContextoDelAsistente) async throws -> ToolResult {
        guard let importe = try a.numero("importe"), importe > 0 else { throw ErrorDeArgumentos("Falta «importe» (mayor que 0).") }
        guard let centimos = Int(exactly: (importe * 100).rounded()) else { throw ErrorDeArgumentos("«importe» no es una cifra válida.") }
        guard let fecha = try a.fecha("fecha") else { throw ErrorDeArgumentos("Falta «fecha».") }
        let origen = try a.obligatorio("origen", max: 200)
        let (foto, _) = await fotoYReloj()
        let registros = RegistrosFinanzas(snapshot: foto)
        let ruta = registros.pagosCSV
        guard d.vista.esVisible(ruta) else { return Respuesta.noEncontrado }
        let propuesta = await d.propuestas.pendiente(conOrigen: origen)
        if registros.pagos.contains(where: { $0.evidencia == origen }) || propuesta != nil {
            return Respuesta.hecho("Ese cobro ya estaba apuntado: no lo repito.", ["estado": "ya_registrado", "ruta": .string(ruta.raw)])
        }
        let dia = fecha.description.replacingOccurrences(of: "-", with: "")
        let usados = registros.pagos.compactMap { p -> Int? in
            guard p.id.hasPrefix("PAG-\(dia)-") else { return nil }
            return Int(p.id.dropFirst("PAG-\(dia)-".count))
        }
        let id = "PAG-\(dia)-" + String(format: "%03d", (usados.max() ?? 0) + 1)
        let fila: [String: String] = [
            "id": id, "fecha": fecha.description, "direccion": "cobro", "importe": Self.euros(centimos), "moneda": "EUR",
            "documento_id": try a.texto("documento_id", max: 60) ?? "", "proyecto_id": "", "tercero": try a.texto("tercero", max: 200) ?? "",
            "metodo": try a.texto("metodo", max: 40) ?? "", "evidencia": origen,
            // Nunca confirma: eso lo hace una persona al conciliar.
            "verificacion": "",
        ]
        var ops: [WriteOp] = []
        if foto.existing(ruta) == nil {
            ops.append(.create(ruta, text: RegistrosFinanzas.cabeceraPagos.joined(separator: ",") + "\n"))
        }
        ops.append(.insertCSVRows(ruta, rows: [fila], key: "id"))
        let plan = WritePlan(autor: c.autor, descripcion: "Apuntar un cobro sin confirmar (\(origen))", ops: ops)
        let resultado = try await accionDeDominio(c, accion: "cobro_externo.registrar", capacidad: CatalogoTLS.capacidadCobroExterno,
                                                  area: .finanzas, plan: plan, titulo: "Apuntar un cobro de \(Self.euros(centimos)) €",
                                                  detalle: "Cobro informado el \(fecha) por \(origen), sin confirmar.", origen: origen)
        if case .hecho = resultado {
            return Respuesta.hecho("Cobro apuntado sin confirmar: confirmarlo es de \(d.persona) al conciliar.",
                                   ["estado": "hecho", "id": .string(id), "ruta": .string(ruta.raw), "verificacion": ""])
        }
        return respuesta(resultado, hecho: "Cobro apuntado.", ruta: ruta)
    }
}

/// Escalares YAML seguros para el frontmatter que escribe el servidor.
enum YAMLTexto {
    static func escalar(_ s: String) -> String {
        let limpio = s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let seguro = limpio.range(of: #"^[\p{L}\p{N}][\p{L}\p{N} .,()·'/-]*$"#, options: .regularExpression) != nil
            && !limpio.hasSuffix(":") && !limpio.contains(": ") && !limpio.contains(" #")
        if seguro { return limpio }
        let escapado = limpio.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapado)\""
    }
}
