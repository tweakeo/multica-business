import Foundation
import TLSCore

/// Fichas de Ventas, Dirección, Marca y Equipo.
extension ConversionG2 {
    func escribirFichas() {
        carpeta.registros("organization").forEach(escribirEmpresa)
        carpeta.registros("contact").forEach(escribirContacto)
        carpeta.registros("service").forEach(escribirServicio)
        carpeta.registros("offer").forEach(escribirVersion)
        carpeta.registros("opportunity").forEach(escribirOportunidad)
        carpeta.registros("objective").forEach(escribirObjetivo)
        escribirDecisiones()
        carpeta.registros("routine").forEach(escribirRutina)
        carpeta.registros("role").forEach(escribirRol)
        carpeta.registros("content").forEach(escribirContenido)
        carpeta.registros("conversation").forEach(escribirConversacion)
        carpeta.registros("brand_identity").prefix(1).forEach(escribirMarca)
        carpeta.registros("script").forEach(escribirGuion)
        escribirMetas()
    }

    // MARK: Ventas

    /// Papel y ciclo de vida a partir de `kind` de G2.
    func relacionYEstado(_ r: G2Registro) -> (relacion: String?, estado: String?) {
        if r.campos.texto("archived_at") != nil {
            return (relacionDe(r.campos.texto("kind")), "Archivado")
        }
        switch r.campos.texto("kind") ?? "" {
        case "lead", "prospect": return ("cliente", "Interesado")
        case "client", "customer": return ("cliente", "Activo")
        case "former_client": return ("cliente", "Antiguo cliente")
        case "supplier", "vendor": return ("proveedor", "Activo")
        case "partner", "collaborator": return ("colaborador", "Activo")
        case "advisor", "gestoria": return ("gestoría", "Activo")
        case "": return (nil, nil)
        default:
            avisar("Tipos de empresa o persona que no se reconocen", r, queHacer: "Pon «relacion» y «estado» a mano.")
            return (nil, nil)
        }
    }

    func relacionDe(_ kind: String?) -> String? {
        switch kind ?? "" {
        case "supplier", "vendor": "proveedor"
        case "partner", "collaborator": "colaborador"
        case "advisor", "gestoria": "gestoría"
        case "": nil
        default: "cliente"
        }
    }

    func escribirEmpresa(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Ventas/Organizaciones", destino: area(.ventas).carpeta + "/Empresas")
        let c = r.campos
        let (relacion, estado) = relacionYEstado(r)
        var fm = FrontmatterNuevo(tipo: "organization", id: id)
        fm.texto("nombre", c.texto("name"))
        fm.texto("nif", c.texto("tax_id"))
        fm.texto("ciudad", c.texto("city"))
        fm.texto("email", c.texto("email"))
        fm.texto("telefono", c.texto("phone"))
        fm.texto("sector", c.texto("sector"))
        fm.poner("relacion", relacion.map { .lista([.texto($0)]) })
        fm.texto("estado", estado)
        fm.texto("canal", c.texto("source_channel"))
        fm.poner("contenido", enlace(c.texto("source_content_id"), campo: "source_content_id", en: r))
        fm.literal("origen", "importacion")
        fm.literal("creada", c.fecha("created_at"))
        revisar(r, usados: ["name", "tax_id", "city", "email", "phone", "sector", "kind", "source_channel",
                            "source_content_id", "origin", "created_at", "archived_at"],
                motivos: ["legal_form": "La forma jurídica va en el nombre."])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [c.texto("sector"), c.texto("city"), relacion, estado]
        nota.seccion("Qué hace")
        nota.seccion("Cómo trabajamos con ella")
        nota.seccion("Notas", r.cuerpoUtil.map { reescribirRutasG2($0, desde: d.ruta) })
        nota.seccion("Historial")
        nota.pie = fuente
        escribir(d.ruta, nota)
    }

    func escribirContacto(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Ventas/Contactos", destino: area(.ventas).carpeta + "/Contactos")
        let c = r.campos
        let (relacion, estado) = relacionYEstado(r)
        let empresa = c.texto("organization_id").flatMap { destinos[$0] }
        let conversaciones = carpeta.registros("conversation")
            .filter { $0.campos.texto("contact_id") == id }
            .sorted { ($0.campos.texto("occurred_at") ?? "", $0.id ?? "") < ($1.campos.texto("occurred_at") ?? "", $1.id ?? "") }
        var fm = FrontmatterNuevo(tipo: "contact", id: id)
        fm.texto("nombre", c.texto("name"))
        fm.poner("empresa", enlace(c.texto("organization_id"), campo: "organization_id", en: r))
        fm.texto("cargo", c.texto("position"))
        fm.texto("email", c.texto("email"))
        fm.texto("telefono", c.texto("phone"))
        fm.poner("relacion", relacion.map { .lista([.texto($0)]) })
        fm.texto("estado", estado)
        fm.texto("canal", c.texto("source_channel"))
        fm.poner("conversacion", conversaciones.first.flatMap { $0.id }.flatMap { destinos[$0] }.map(wikilink))
        fm.poner("contenido", enlace(c.texto("source_content_id"), campo: "source_content_id", en: r))
        fm.poner("no_contactar", c.bool("opted_out").map { .bool($0) })
        fm.literal("origen", "importacion")
        fm.literal("creada", c.fecha("created_at"))
        if conversaciones.count > 1 {
            avisar("Personas con más de una conversación (se enlaza la primera)", r, queHacer: "Revisa cuál es la que la trajo.")
        }
        revisar(r, usados: ["name", "organization_id", "position", "email", "phone", "kind", "source_channel",
                            "source_content_id", "opted_out", "origin", "created_at", "archived_at"])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [c.texto("position"), empresa?.nombre, estado]
        nota.seccion("Cómo llegó")
        nota.seccion("Lo que le importa")
        nota.seccion("Notas", r.cuerpoUtil.map { reescribirRutasG2($0, desde: d.ruta) })
        nota.seccion("Historial")
        nota.pie = fuente
        escribir(d.ruta, nota)
    }

    /// Versiones de oferta de un servicio, de la más nueva a la más antigua.
    func versiones(de servicioId: String) -> [G2Registro] {
        carpeta.registros("offer").filter { $0.campos.texto("service_id") == servicioId }
            .sorted { (G2Numero.entero($0.campos.texto("version") ?? "") ?? 0) > (G2Numero.entero($1.campos.texto("version") ?? "") ?? 0) }
    }

    /// La versión vigente: la activa más nueva o, si no hay, la más nueva.
    func versionVigente(de servicioId: String) -> G2Registro? {
        let todas = versiones(de: servicioId)
        return todas.first { $0.campos.bool("active") == true } ?? todas.first
    }

    func recurrencia(_ s: String?) -> String? {
        switch s ?? "" {
        case "": nil
        case "none", "once": "ninguna"
        case "monthly": "mensual"
        case "quarterly": "trimestral"
        case "annual", "yearly": "anual"
        default: s
        }
    }

    func escribirServicio(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Entrega/Servicios", destino: area(.ventas).carpeta + "/Productos y " + area(.entrega).carpeta + "/Planes de entrega")
        let c = r.campos
        let vigente = versionVigente(de: id)
        let activo = c.bool("active") != false && c.texto("archived_at") == nil
        let precio = vigente?.campos.entero("price_minor")
        var fm = FrontmatterNuevo(tipo: "service", id: id)
        fm.texto("nombre", c.texto("name"))
        fm.texto("codigo", c.texto("code"))
        fm.texto("estado", activo ? "Activo" : "Retirado")
        fm.literal("version", vigente?.campos.texto("version"))
        fm.literal("valido_desde", vigente?.campos.fecha("valid_from"))
        if precio != nil { fm.texto("modelo_precio", "fijo") }
        fm.literal("precio", precio.map(Dinero.texto))
        fm.texto("unidad", vigente?.campos.texto("billing_unit"))
        fm.literal("iva_pct", vigente?.campos.entero("tax_rate_bp").map { Dinero.porcentaje(puntosBasicos: $0) })
        fm.literal("retencion_pct", vigente?.campos.entero("withholding_bp").map { Dinero.porcentaje(puntosBasicos: $0) })
        fm.texto("recurrencia", recurrencia(c.texto("recurrence")))
        fm.poner("plan", destinos["plan:\(id)"].map(wikilink))
        revisar(r, usados: ["name", "code", "active", "archived_at", "recurrence", "description", "template", "created_at"],
                motivos: ["template_version": "Pasa a «version» del plan de entrega.",
                          "version": "Número de revisión interno de G2; la versión del servicio sale de su oferta vigente."])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        let unidad = vigente?.campos.texto("billing_unit")
        nota.resumen = [activo ? "Activo" : "Retirado",
                        precio.map { "\(Dinero.legible($0))\(unidad.map { " por \($0)" } ?? "") + IVA" },
                        vigente?.campos.texto("version").map { "versión \($0)" }]
        nota.seccion("Para quién")
        nota.seccion("Qué resuelve", c.texto("description"))
        nota.seccion("Incluye")
        nota.seccion("No incluye")
        nota.seccion("Condiciones de cobro", vigente?.campos.texto("conditions"))
        nota.seccion("Cliente ideal y anticliente")
        nota.seccion("Objeciones")
        escribir(d.ruta, nota)
        if let plan = destinos["plan:\(id)"], let plantilla = c.mapa("template") {
            escribirPlan(r, plantilla: plantilla, destino: plan, servicio: d, activo: activo)
        }
    }

    /// Quién hace una tarea del plan: `agent:entrega` → `agente:implementador`; `lead` → `responsable`.
    func quien(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        if s.hasPrefix("agent:") {
            let slug = String(s.dropFirst(6))
            let porArea = ["direccion": "mika", "ventas": "comercial", "entrega": "implementador",
                           "finanzas": "contable", "marca": "marca", "equipo": "equipo"]
            return "agente:" + (porArea[slug] ?? slug)
        }
        switch s {
        case "lead", "owner", "member": return "responsable"
        case "client", "customer": return "cliente"
        default: return s
        }
    }

    func escribirPlan(_ r: G2Registro, plantilla: G2Mapa, destino d: DestinoV2, servicio: DestinoV2, activo: Bool) {
        let id = IDsDerivados.id("plan:" + (r.id ?? r.ruta.raw))
        var fm = FrontmatterNuevo(tipo: "delivery_template", id: id)
        fm.texto("nombre", d.nombre)
        fm.literal("clase", "entrega")
        fm.poner("servicio", wikilink(servicio))
        fm.literal("version", r.campos.texto("template_version"))
        fm.texto("estado", activo ? "En uso" : "Retirado")
        fm.literal("dias_proyecto", plantilla.texto("project_days"))
        fm.texto("terminado_cuando", plantilla.texto("done_when"))
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [activo ? "En uso" : "Retirado", plantilla.texto("project_days").map { "\($0) días" }]
        nota.seccion("Terminado cuando", plantilla.texto("done_when"))
        var estadosSinSitio = false
        var renombrados = Set<String>()
        for (i, fase) in plantilla.lista("phases").compactMap(\.mapa).enumerated() {
            var filas: [[String]] = []
            var descripciones: [String] = []
            for t in fase.lista("tasks").compactMap(\.mapa) {
                let titulo = t.texto("title") ?? ""
                filas.append([titulo, t.texto("offset") ?? "", t.texto("duration") ?? "", t.texto("due_slack") ?? "",
                              quien(t.texto("assignee")), t.texto("acceptance") ?? ""])
                if let desc = t.texto("description") { descripciones.append("- \(titulo): \(desc)") }
                if t.texto("status") != nil { estadosSinSitio = true }
                if let a = t.texto("assignee"), quien(a) != a { renombrados.insert("\(a) → \(quien(a))") }
            }
            var contenido = TablaMarkdown.texto(["Tarea", "Día", "Dura", "Margen", "Quién", "Se acepta cuando"], filas)
            if !descripciones.isEmpty { contenido += "\n\n" + descripciones.joined(separator: "\n") }
            nota.seccion("Fase \(i + 1) · \(fase.texto("name") ?? "")", contenido)
        }
        nota.seccion("Pagos por fase")
        nota.seccion("Kit por sesión")
        if !renombrados.isEmpty {
            avisar("Quién hace cada tarea del plan, con los nombres de la v2 (\(renombrados.sorted().joined(separator: "; ")))", r,
                   queHacer: "Nada, salvo que en tu empresa se llamen de otra forma.")
        }
        if estadosSinSitio {
            let clave = "service.template.phases.tasks.status"
            avisarCampo(clave, r, motivo: "Columna del tablero de G2: en la v2 el estado lo lleva cada tarea.")
        }
        avisar("Los días de los planes de entrega se copian tal cual (G2 no dice si son laborables)", r,
               queHacer: "Confírmalo: en la v2 los días de un plan son laborables.")
        escribir(d.ruta, nota)
    }

    func avisarCampo(_ clave: String, _ r: G2Registro, motivo: String) {
        revisarClave(clave, r, motivo: motivo)
    }

    func escribirVersion(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Ventas/Ofertas", destino: area(.ventas).carpeta + "/Productos/Versiones")
        let c = r.campos
        let servicio = porId[c.texto("service_id") ?? ""]
        let codigoServicio = servicio?.campos.texto("code")
        let version = c.texto("version")
        let estado = c.bool("active") == true ? "Aprobada" : "Sustituida"
        let precio = c.entero("price_minor")
        var fm = FrontmatterNuevo(tipo: "offer", id: id)
        fm.poner("servicio", enlace(c.texto("service_id"), campo: "service_id", en: r))
        if let codigoServicio, let version { fm.texto("codigo", "\(codigoServicio)-v\(version)") }
        fm.literal("version", version)
        fm.texto("estado", estado)
        fm.literal("precio", precio.map(Dinero.texto))
        fm.texto("unidad", c.texto("billing_unit"))
        fm.literal("iva_pct", c.entero("tax_rate_bp").map { Dinero.porcentaje(puntosBasicos: $0) })
        fm.literal("retencion_pct", c.entero("withholding_bp").map { Dinero.porcentaje(puntosBasicos: $0) })
        fm.literal("valido_desde", c.fecha("valid_from"))
        revisar(r, usados: ["service_id", "version", "active", "price_minor", "billing_unit", "tax_rate_bp",
                            "withholding_bp", "valid_from", "conditions", "created_at", "currency"])
        let nombreServicio = servicio?.campos.texto("name") ?? d.nombre
        var nota = NotaNueva(frontmatter: fm, titulo: "\(nombreServicio) · versión \(version ?? "?")")
        nota.resumen = [estado,
                        precio.map { "\(Dinero.legible($0))\(c.texto("billing_unit").map { " por \($0)" } ?? "") + IVA" },
                        c.fecha("valid_from").map { "desde \(G2Fecha.corta($0))" }]
        nota.seccion("Para quién")
        nota.seccion("Qué resuelve")
        nota.seccion("Incluye")
        nota.seccion("No incluye")
        nota.seccion("Condiciones de cobro", c.texto("conditions"))
        nota.seccion("Qué cambia respecto a la versión anterior")
        escribir(d.ruta, nota)
    }

    /// Etapa de G2 → estado de la oportunidad (SISTEMAS.md §3.5).
    func estadoOportunidad(_ etapa: String?, _ r: G2Registro) -> String? {
        switch etapa ?? "" {
        case "": return nil
        case "entrada", "cualificacion", "prospecto", "lead": return "Prospecto"
        case "diagnostico": return "Diagnóstico"
        case "propuesta", "negociacion": return "Propuesta"
        case "aceptada": return "Aceptada"
        case "ganada": return "Ganada"
        case "perdida": return "Perdida"
        case "pausada": return "Pausada"
        default:
            avisar("Etapas de oportunidad que no se reconocen", r, queHacer: "Pon el estado a mano.")
            return nil
        }
    }

    func escribirOportunidad(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Ventas/Oportunidades", destino: area(.ventas).carpeta + "/Oportunidades")
        let c = r.campos
        let estado = estadoOportunidad(c.texto("stage"), r)
        if c.texto("stage") == "entrada" || c.texto("stage") == "cualificacion" {
            registrarNoConvertido("opportunity.stage (entrada, cualificacion)", ruta: r.ruta.raw,
                                  motivo: "En la v2 las dos etapas son «Prospecto».")
        }
        let propuesta = c.mapa("proposal")
        let valor = c.entero("value_minor")
        let conversacion = carpeta.registros("conversation")
            .filter { $0.campos.texto("contact_id") != nil && $0.campos.texto("contact_id") == c.texto("contact_id") }
            .sorted { ($0.campos.texto("occurred_at") ?? "") < ($1.campos.texto("occurred_at") ?? "") }.first
        var fm = FrontmatterNuevo(tipo: "opportunity", id: id)
        fm.texto("nombre", c.texto("title"))
        fm.texto("estado", estado)
        fm.poner("empresa", enlace(c.texto("organization_id"), campo: "organization_id", en: r))
        fm.poner("contacto", enlace(c.texto("contact_id"), campo: "contact_id", en: r))
        fm.poner("servicio", enlace(c.texto("service_id"), campo: "service_id", en: r))
        fm.poner("oferta_version", enlace(c.texto("offer_version_id"), campo: "offer_version_id", en: r))
        fm.literal("precio_congelado", propuesta?.entero("unit_price_minor").map(Dinero.texto))
        fm.literal("valor", valor.map(Dinero.texto))
        fm.literal("probabilidad", c.texto("probability"))
        fm.texto("canal", c.texto("channel"))
        fm.poner("conversacion", conversacion?.id.flatMap { destinos[$0] }.map(wikilink))
        fm.texto("siguiente_paso", c.texto("next_action"))
        fm.literal("siguiente_fecha", c.fecha("next_action_on"))
        fm.literal("creada", c.fecha("created_at"))
        fm.literal("aceptada", c.fecha("accepted_at"))
        fm.literal("cerrada", c.fecha("won_at"))
        fm.texto("motivo_perdida", c.texto("lost_reason"))
        fm.literal("origen", "importacion")
        if c.texto("project_id") != nil {
            avisar("Oportunidades y facturas que citan un proyecto que no está en la exportación", r,
                   queHacer: "Crea el proyecto de entrega si hace falta; la referencia no se ha copiado.")
        }
        revisar(r, usados: ["title", "stage", "organization_id", "contact_id", "service_id", "offer_version_id", "proposal",
                            "value_minor", "probability", "channel", "next_action", "next_action_on", "created_at",
                            "accepted_at", "won_at", "lost_reason", "origin", "archived_at", "currency"])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        let siguiente = c.texto("next_action").map { paso in
            "siguiente: \(paso)" + (c.fecha("next_action_on").map { " el \(G2Fecha.corta($0))" } ?? "")
        }
        nota.resumen = [estado, valor.map { Dinero.legible($0) }, c.texto("probability").map { "\($0) %" }, siguiente]
        nota.seccion("Cliente")
        nota.seccion("Qué pide y alcance")
        nota.seccion("Condiciones por acordar")
        nota.seccion("Decisión")
        nota.seccion("Seguimiento")
        nota.seccion("Documentos")
        if let cuerpo = r.cuerpoUtil { nota.seccion("Notas", reescribirRutasG2(cuerpo, desde: d.ruta)) }
        nota.pie = fuente
        escribir(d.ruta, nota)
        if let propuesta, !G2Valor.mapa(propuesta).vacio, let pd = destinos["propuesta:\(id)"] {
            escribirPropuesta(r, propuesta: propuesta, destino: pd, oportunidad: d, estadoOportunidad: estado)
        }
    }

    func escribirPropuesta(_ r: G2Registro, propuesta p: G2Mapa, destino d: DestinoV2, oportunidad: DestinoV2,
                           estadoOportunidad: String?) {
        let c = r.campos
        let estado: String? = switch estadoOportunidad {
        case "Aceptada", "Ganada": "Aceptada"
        case "Perdida": "Rechazada"
        case "Propuesta", "Pausada": "Enviada"
        default: nil
        }
        let base = p.entero("base_minor"), cuota = p.entero("tax_minor"), ret = p.entero("withholding_minor")
        let total = p.entero("total_minor")
        let iva = p.entero("tax_rate_bp").map { Dinero.porcentaje(puntosBasicos: $0) }
        let retPct = p.entero("withholding_bp").map { Dinero.porcentaje(puntosBasicos: $0) }
        var fm = FrontmatterNuevo(tipo: "proposal", id: IDsDerivados.id("propuesta:" + (r.id ?? r.ruta.raw)))
        fm.poner("oportunidad", wikilink(oportunidad))
        fm.literal("version", "1")
        fm.texto("estado", estado)
        fm.literal("fecha", p.fecha("generated_at"))
        fm.literal("valida_hasta", p.fecha("valid_until"))
        fm.poner("empresa", enlace(c.texto("organization_id"), campo: "organization_id", en: r))
        fm.poner("contacto", enlace(c.texto("contact_id"), campo: "contact_id", en: r))
        fm.poner("servicio", enlace(c.texto("service_id"), campo: "service_id", en: r))
        fm.poner("oferta_version", enlace(p.texto("offer_version_id"), campo: "proposal.offer_version_id", en: r))
        fm.literal("iva_pct", iva)
        fm.literal("retencion_pct", retPct)
        fm.literal("base", base.map(Dinero.texto))
        fm.literal("cuota_iva", cuota.map(Dinero.texto))
        fm.literal("retencion", ret.map(Dinero.texto))
        fm.literal("total", total.map(Dinero.texto))
        fm.literal("origen", "importacion")
        for clave in p.claves where !["base_minor", "tax_minor", "withholding_minor", "total_minor", "tax_rate_bp",
                                     "withholding_bp", "generated_at", "valid_until", "offer_version_id", "offer_version",
                                     "service", "quantity", "unit_price_minor", "billing_unit", "conditions", "currency",
                                     "notes"].contains(clave) && !(p[clave]?.vacio ?? true) {
            revisarClave("opportunity.proposal.\(clave)", r, motivo: "No tiene sitio en la propuesta v2.")
        }
        let quien = c.texto("organization_id").flatMap { destinos[$0]?.nombre } ?? c.texto("contact_id").flatMap { destinos[$0]?.nombre }
        var nota = NotaNueva(frontmatter: fm, titulo: "Propuesta para \(quien ?? oportunidad.nombre)")
        nota.resumen = [estado, total.map { Dinero.legible($0) }, p.fecha("valid_until").map { "válida hasta el \(G2Fecha.corta($0))" },
                        "versión 1"]
        nota.seccion("Lo que nos contaste")
        nota.seccion("Lo que proponemos")
        nota.seccion("Incluye")
        nota.seccion("No incluye")
        nota.seccion("Calendario")
        var inversion: String?
        if let base {
            let cantidad = p.texto("quantity") ?? ""
            let unidad = p.entero("unit_price_minor").map { Dinero.legible($0) } ?? ""
            let concepto = [p.texto("service"), p.texto("billing_unit").map { "por \($0)" }].compactMap { $0 }.joined(separator: " ")
            var texto = TablaMarkdown.texto(["Concepto", "Cantidad", "Precio", "IVA", "Importe"],
                                            [[concepto, cantidad, unidad, iva.map { "\($0) %" } ?? "", Dinero.legible(base)]])
            var totales: [[String]] = [["Base imponible", Dinero.legible(base)]]
            if let cuota { totales.append(["IVA \(iva.map { "\($0) %" } ?? "")", Dinero.legible(cuota)]) }
            if let ret { totales.append(["Retención IRPF \(retPct.map { "\($0) %" } ?? "")", "−" + Dinero.legible(ret)]) }
            if let total { totales.append(["**Total**", "**\(Dinero.legible(total))**"]) }
            texto += "\n\n" + TablaMarkdown.texto(["Total", "Importe"], totales)
            inversion = texto
        }
        nota.seccion("Inversión", inversion)
        nota.seccion("Pagos")
        nota.seccion("Condiciones", p.texto("conditions"))
        nota.seccion("Siguientes pasos")
        nota.seccion("Aceptación")
        nota.seccion("Para ti (no se envía)", p.texto("notes"))
        escribir(d.ruta, nota)
    }

    func revisarClave(_ clave: String, _ r: G2Registro, motivo: String) {
        // Mismo acumulador que `revisar`, para claves anidadas.
        registrarNoConvertido(clave, ruta: r.ruta.raw, motivo: motivo)
    }

    // MARK: Dirección

    func unidad(_ u: String?) -> String? {
        switch u ?? "" {
        case "", "n": nil
        case "EUR": "€"
        default: u
        }
    }

    func escribirObjetivo(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Dirección/Objetivos", destino: area(.direccion).carpeta + "/Objetivos")
        let c = r.campos
        let kpi = carpeta.registros("kpi").first { $0.campos.texto("code") == c.texto("kpi_code") && c.texto("kpi_code") != nil }
        let periodo = c.texto("period").flatMap(G2Fecha.periodoTrimestral)
        let u = unidad(kpi?.campos.texto("unit"))
        let estado: String? = switch c.texto("status") ?? "" {
        case "active": "En curso"
        case "achieved", "done": "Conseguido"
        case "missed", "failed": "No conseguido"
        case "deferred": "Aplazado"
        case "": nil
        default: c.texto("status")
        }
        var fm = FrontmatterNuevo(tipo: "objective", id: id)
        fm.texto("titulo", c.texto("title"))
        fm.literal("area", area(codigo: c.texto("area"))?.layoutKey)
        fm.texto("periodo", periodo.map { "T\($0.trimestre) \($0.anio)" })
        if let p = periodo {
            let l = G2Fecha.limites(anio: p.anio, trimestre: p.trimestre)
            fm.literal("desde", l.desde)
            fm.literal("hasta", l.hasta)
        }
        fm.literal("meta", c.texto("target"))
        fm.texto("unidad", u)
        switch c.texto("kind") {
        case "cumulative": fm.poner("acumulado", .bool(true))
        case "level": fm.poner("acumulado", .bool(false))
        default: break
        }
        fm.texto("medido_por", c.texto("kpi_code"))
        fm.texto("estado", estado)
        revisar(r, usados: ["title", "area", "period", "target", "kind", "kpi_code", "status", "created_at", "archived_at"],
                motivos: ["baseline": "Sin sitio en el objetivo v2.", "deferred_to": "Sin sitio en el objetivo v2."])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [periodo.map { "T\($0.trimestre) \($0.anio)" },
                        c.texto("target").map { "meta \($0)\(u.map { " \($0)" } ?? "")" },
                        c.texto("kpi_code").map { "se mide con \($0)" }]
        nota.seccion("Por qué")
        let como: String? = switch c.texto("kind") {
        case "cumulative": "Se suma a lo largo del periodo."
        case "level": "Se mira el nivel en cada momento."
        case "compliance": "Se cumple o no se cumple."
        default: nil
        }
        nota.seccion("Cómo se mide", como)
        let aprendido = [c.texto("result").map { "Resultado: \($0)" }, c.texto("learnings").map { "Aprendido: \($0)" }]
            .compactMap { $0 }.map { "- \($0)" }.joined(separator: "\n")
        nota.seccion("Revisiones", aprendido.isEmpty ? nil : aprendido)
        escribir(d.ruta, nota)
    }

    func escribirDecisiones() {
        let decisiones = carpeta.registros("decision")
        var lineas: [(fecha: String, id: String, texto: String)] = []
        let rutaRegistro = ruta(.direccion, "Decisiones.md")
        for r in decisiones where !estaAbierta(r) {
            guard let id = r.id, let d = destinos[id] else { continue }
            contar(r)
            bloque("Dirección/Decisiones", destino: area(.direccion).carpeta + "/Decisiones.md y Decisiones/")
            let c = r.campos
            let dia = c.fecha("decided_at") ?? c.fecha("created_at") ?? fecha
            let codigo = area(codigo: c.texto("area"))
            let estado = c.texto("status") == "superseded" ? "Sustituida" : "Tomada"
            var fm = FrontmatterNuevo(tipo: "decision", id: id)
            fm.texto("titulo", c.texto("title"))
            fm.literal("fecha", dia)
            fm.literal("area", codigo?.layoutKey)
            fm.texto("estado", estado)
            fm.poner("sustituye", enlace(c.texto("supersedes_id"), campo: "supersedes_id", en: r))
            let afecta = c.lista("refs").compactMap(\.mapa).compactMap { $0.texto("id") }
                .compactMap { enlace($0, campo: "refs", en: r) }
            if !afecta.isEmpty { fm.poner("afecta", .lista(afecta)) }
            fm.literal("origen", "importacion")
            revisar(r, usados: ["title", "decided_at", "created_at", "area", "status", "supersedes_id", "refs",
                                "decision", "why", "purpose"])
            var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
            nota.resumen = ["\(estado) el \(G2Fecha.corta(dia))", codigo.map { area($0).nombre }]
            nota.seccion("Qué se decide", c.texto("decision"))
            nota.seccion("Por qué", c.texto("why"))
            nota.seccion("Para qué", c.texto("purpose"))
            nota.seccion("Alcance")
            nota.seccion("Datos que había", r.cuerpoUtil.map { reescribirRutasG2($0, desde: d.ruta) })
            nota.seccion("Opciones descartadas")
            nota.seccion("Qué hay que poner al día")
            nota.seccion("Revisiones")
            escribir(d.ruta, nota)
            let campos = [c.texto("decision") ?? d.nombre, c.texto("why"), codigo.map { area($0).nombre },
                          Nombres.enlaceMarkdown(d.nombre, desde: rutaRegistro, a: d.ruta)].compactMap { $0 }
            let marca = "<!-- tls:decision {\"id\":\"\(id)\",\"origen\":\"importacion\"} -->"
            lineas.append((dia, id, "- \(dia) · " + campos.joined(separator: " · ") + " " + marca))
        }
        for tarea in tareas {
            if tarea.registro.tipo == "task" {
                escribirTarea(tarea.registro, numero: tarea.numero, area: tarea.area, destino: tarea.destino)
            } else {
                escribirTareaDeDecision(tarea.registro, numero: tarea.numero, area: tarea.area, destino: tarea.destino)
            }
        }
        var fm = FrontmatterNuevo(tipo: "log", id: IDsDerivados.id("registro:decisiones"))
        fm.literal("registro", "decisiones")
        var nota = NotaNueva(frontmatter: fm, titulo: "Decisiones")
        nota.resumen = ["Cada decisión, una vez y el mismo día. Solo se añade: lo superado se marca «(sustituida)» y nunca se borra."]
        let porAnio = Dictionary(grouping: lineas.sorted { ($0.fecha, $0.id) < ($1.fecha, $1.id) }) { String($0.fecha.prefix(4)) }
        for anio in porAnio.keys.sorted() {
            nota.seccion(anio, porAnio[anio]!.map(\.texto).joined(separator: "\n"))
        }
        escribir(rutaRegistro, nota)
    }

    func escribirTareaDeDecision(_ r: G2Registro, numero: String, area codigo: AreaCode, destino d: DestinoV2) {
        contar(r)
        bloque("Dirección/Decisiones (abiertas)", destino: "Tareas/ de su área, una ficha por tarea")
        let c = r.campos
        var fm = FrontmatterNuevo(tipo: "task", id: r.id ?? IDsDerivados.id("tarea:" + r.ruta.raw))
        fm.texto("numero", numero)
        fm.texto("titulo", c.texto("title"))
        fm.texto("estado", "En revisión")
        fm.literal("tipo", "decision")
        fm.literal("area", codigo.layoutKey)
        fm.literal("origen", "importacion")
        fm.literal("creada", c.fecha("created_at"))
        revisar(r, usados: ["title", "status", "area", "created_at", "decision", "why", "purpose", "refs",
                            "supersedes_id", "decided_at"])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = ["Decisión pendiente", area(codigo).nombre]
        nota.seccion("Problema", r.cuerpoUtil.map { reescribirRutasG2($0, desde: d.ruta) })
        nota.seccion("Opciones")
        nota.seccion("Actividad", "<!-- tls:actividad · para comentar, escribe debajo de la última entrada -->")
        escribir(d.ruta, nota)
    }

    /// Estado de una tarea: los de Multica (PLAN §4.2) y los nombres que se aceptan al leer.
    func estadoTarea(_ s: String?, _ r: G2Registro) -> String? {
        switch (s ?? "").lowercased() {
        case "": return nil
        case "backlog", "sin programar": return "Sin programar"
        case "todo", "por hacer", "pendiente": return "Por hacer"
        case "in_progress", "en curso", "en progreso": return "En curso"
        case "in_review", "en revisión", "en revision", "por revisar": return "En revisión"
        case "blocked", "bloqueada", "bloqueado": return "Bloqueada"
        case "done", "hecha", "hecho": return "Hecha"
        case "cancelled", "canceled", "cancelada": return "Cancelada"
        default:
            avisar("Estados de tarea que no se reconocen", r, queHacer: "Pon el estado a mano.")
            return s
        }
    }

    /// Una tarea de G2 → su ficha (PLAN §4.2), con las relaciones como enlaces.
    func escribirTarea(_ r: G2Registro, numero: String, area codigo: AreaCode, destino d: DestinoV2) {
        contar(r)
        bloque("Tareas", destino: "Tareas/ de su área, una ficha por tarea")
        let c = r.campos
        func primero(_ claves: String...) -> String? { claves.lazy.compactMap { c.texto($0) }.first }
        func fecha(_ claves: String...) -> String? { claves.lazy.compactMap { c.fecha($0) }.first }
        let prioridad: String? = switch (primero("priority", "prioridad") ?? "").lowercased() {
        case "urgent", "urgente": "Urgente"
        case "high", "alta": "Alta"
        case "medium", "media": "Media"
        case "low", "baja": "Baja"
        default: nil
        }
        let tipo: String = switch (primero("kind", "tipo") ?? "").lowercased() {
        case "question", "pregunta": "pregunta"
        case "decision": "decision"
        default: "tarea"
        }
        let responsable = primero("assignee", "responsable").map { quien($0) == "responsable" ? nil : quien($0) } ?? nil
        let estado = estadoTarea(primero("status", "estado"), r)
        var fm = FrontmatterNuevo(tipo: "task", id: r.id ?? IDsDerivados.id("tarea:" + r.ruta.raw))
        fm.texto("numero", numero)
        fm.texto("titulo", d.nombre)
        fm.texto("estado", estado)
        fm.texto("prioridad", prioridad)
        fm.literal("tipo", tipo)
        fm.texto("responsable", responsable)
        fm.literal("planificada", fecha("planned_on", "scheduled_on", "planificada"))
        fm.literal("vence", fecha("due_date", "due_on", "vence"))
        fm.literal("estimacion_h", primero("estimate_hours", "estimacion_h"))
        fm.literal("dedicadas_h", primero("spent_hours", "dedicadas_h"))
        fm.literal("area", codigo.layoutKey)
        fm.poner("proyecto", enlace(primero("project_id", "proyecto_id"), campo: "project_id", en: r))
        fm.poner("oportunidad", enlace(primero("opportunity_id", "oportunidad_id"), campo: "opportunity_id", en: r))
        fm.poner("empresa", enlace(primero("organization_id", "empresa_id"), campo: "organization_id", en: r))
        fm.poner("padre", enlace(primero("parent_id", "padre_id"), campo: "parent_id", en: r))
        let bloqueos = (c.textos("blocked_by") + c.textos("bloqueada_por")).compactMap { enlace($0, campo: "blocked_by", en: r) }
        if !bloqueos.isEmpty { fm.poner("bloqueada_por", .lista(bloqueos)) }
        fm.texto("capacidad", primero("capability", "capacidad"))
        fm.literal("despertar", fecha("wake_on", "despertar"))
        fm.literal("origen", "importacion")
        fm.literal("creada", fecha("created_at", "creada"))
        fm.literal("cerrada", fecha("completed_at", "closed_at", "done_at", "cerrada"))
        revisar(r, usados: ["title", "titulo", "number", "numero", "status", "estado", "priority", "prioridad", "kind", "tipo",
                            "assignee", "responsable", "planned_on", "scheduled_on", "planificada", "due_date", "due_on", "vence",
                            "estimate_hours", "estimacion_h", "spent_hours", "dedicadas_h", "area", "project_id", "proyecto_id",
                            "opportunity_id", "oportunidad_id", "organization_id", "empresa_id", "parent_id", "padre_id",
                            "blocked_by", "bloqueada_por", "capability", "capacidad", "wake_on", "despertar", "created_at",
                            "creada", "completed_at", "closed_at", "done_at", "cerrada", "description", "descripcion"],
                motivos: ["assignee_id": "G2 no guarda nombres de personas, solo identificadores.",
                          "assignee_type": "G2 no guarda nombres de personas, solo identificadores."])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [estado, responsable.map { $0.hasPrefix("agente:") ? "\(String($0.dropFirst(7)).capitalized) (asistente)" : $0 },
                        fecha("due_date", "due_on", "vence").map { "vence el \(G2Fecha.corta($0))" }]
        let descripcion = [primero("description", "descripcion"), r.cuerpoUtil].compactMap { $0 }.joined(separator: "\n\n")
        nota.seccion("Descripción", descripcion.isEmpty ? nil : reescribirRutasG2(descripcion, desde: d.ruta))
        nota.seccion("Actividad", "<!-- tls:actividad · para comentar, escribe debajo de la última entrada -->")
        escribir(d.ruta, nota)
    }

    func escribirRutina(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else {
            avisar("Registros de rutina sin fecha reconocible", r, queHacer: "Están en Archivo/Importación; revísalos a mano.")
            return
        }
        contar(r)
        bloque("Dirección/Rutinas", destino: area(.direccion).carpeta + "/Rutinas")
        let c = r.campos
        let esSemana = c.texto("kind") == "week"
        var fm = FrontmatterNuevo(tipo: "routine_log", id: id)
        fm.literal("tipo", esSemana ? "semana" : "dia")
        fm.literal("fecha", d.ruta.stem)
        if esSemana { fm.texto("semana", c.texto("period_key").map { $0.uppercased().replacingOccurrences(of: "-W", with: "-S") }) }
        fm.literal("cerrada", c.fecha("closed_at"))
        revisar(r, usados: ["kind", "period_key", "focus", "plan", "review", "verdict", "closed_at", "created_at"])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.seccion("Foco", c.texto("focus"))
        nota.seccion("Plan", c.texto("plan"))
        nota.seccion("Revisión", c.texto("review"))
        nota.seccion("Veredicto", c.texto("verdict"))
        escribir(d.ruta, nota)
    }

    /// `1 · Dirección/Metas.md` con la tabla de G3 y, debajo, cómo se mide cada número.
    func escribirMetas() {
        let kpis = carpeta.registros("kpi").sorted { ($0.campos.texto("code") ?? "") < ($1.campos.texto("code") ?? "") }
        var filas: [[String]] = []
        var como: [String] = []
        for r in kpis {
            contar(r)
            bloque("Dirección/KPI", destino: area(.direccion).carpeta + "/Metas.md")
            let c = r.campos
            let u = unidad(c.texto("unit"))
            func conUnidad(_ v: String?) -> String {
                guard let v else { return "" }
                guard let u else { return v }
                return u == "%" ? "\(v) %" : "\(v) \(u)"
            }
            filas.append([c.texto("code") ?? "", c.texto("name") ?? "", conUnidad(c.texto("target")), conUnidad(c.texto("alert")), ""])
            let periodo: String? = switch c.texto("period") ?? "" {
            case "now": "ahora"
            case "month": "cada mes"
            case "quarter": "cada trimestre"
            case "": nil
            case let p where p.hasSuffix("d"): "últimos \(p.dropLast()) días"
            case let p: p
            }
            let sentido: String? = switch c.texto("direction") ?? "" {
            case "up": "más es mejor"
            case "down": "menos es mejor"
            case "range": "dentro de un rango"
            default: nil
            }
            let partes = [c.texto("formula"), periodo, sentido, c.bool("enabled") == false ? "apagado" : nil].compactMap { $0 }
            if let code = c.texto("code") { como.append("- \(code) · " + partes.joined(separator: " · ")) }
            revisar(r, usados: ["code", "name", "unit", "target", "alert", "period", "direction", "formula", "enabled", "area",
                                "created_at"],
                    motivos: ["owner_role_id": "El dueño del número va en el rol."])
        }
        var fm = FrontmatterNuevo(tipo: "log", id: IDsDerivados.id("registro:metas"))
        fm.literal("registro", "metas")
        var nota = NotaNueva(frontmatter: fm, titulo: "Metas")
        nota.resumen = ["Un número por pregunta. La meta y la alerta se escriben antes de ver el dato."]
        nota.entradilla = TablaMarkdown.texto(["Código", "Indicador", "Meta", "Alerta", "Por qué"], filas)
        nota.seccion("Cómo se mide", como.isEmpty ? nil : como.joined(separator: "\n"))
        escribir(ruta(.direccion, "Metas.md"), nota)
    }

    // MARK: Equipo y Marca

    func escribirRol(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Equipo/Roles", destino: area(.equipo).carpeta + "/Roles")
        let c = r.campos
        let codigo = area(codigo: c.texto("area"))
        let clase: String? = switch c.texto("occupant_type") ?? "" {
        case "member": "humano"
        case "agent": "agente"
        default: nil
        }
        let numeros = c.textos("kpi_codes")
        var fm = FrontmatterNuevo(tipo: "role", id: id)
        fm.texto("nombre", c.texto("name"))
        fm.literal("clase", clase)
        if let codigo { fm.poner("areas", .lista([.texto(codigo.layoutKey)])) }
        if !numeros.isEmpty { fm.poner("numeros", .lista(numeros.map { .texto($0) })) }
        revisar(r, usados: ["name", "occupant_type", "area", "kpi_codes", "mission", "decisions", "limits", "created_at",
                            "archived_at"])
        if c.texto("occupant_id") != nil {
            avisar("Roles con ocupante sin nombre (G2 solo guarda un identificador)", r,
                   queHacer: "Escribe quién ocupa el rol en «ocupante».")
        }
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [codigo.map { area($0).nombre }]
        nota.seccion("Misión", c.texto("mission"))
        nota.seccion("Decide sin preguntar", c.texto("decisions"))
        nota.seccion("Puede solo")
        nota.seccion("Puede con tu OK")
        nota.seccion("Nunca", c.texto("limits"))
        nota.seccion("Qué recibe y qué entrega")
        let nombresKPI = Dictionary(carpeta.registros("kpi").compactMap { k in k.campos.texto("code").map { ($0, k.campos.texto("name") ?? "") } },
                                    uniquingKeysWith: { a, _ in a })
        nota.seccion("Números", numeros.isEmpty ? nil : numeros.map { "- \($0)" + ((nombresKPI[$0]).map { " · \($0)" } ?? "") }.joined(separator: "\n"))
        nota.seccion("Sistemas")
        nota.seccion("Escalado")
        nota.seccion("Rutinas")
        var texto = nota.texto
        if let cuerpo = r.cuerpoUtil {
            texto += "\n" + reescribirRutasG2(cuerpo, desde: d.ruta) + "\n"
        }
        escribir(d.ruta, texto: texto)
    }

    func escribirContenido(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Marca/Contenidos", destino: area(.marca).carpeta + "/Contenidos")
        let c = r.campos
        let tipo: String? = switch c.texto("format") ?? "" {
        case "": nil
        case "artículo", "articulo", "article": "articulo"
        case "reel", "video", "vídeo", "short": "video"
        case "email", "newsletter": "newsletter"
        case let f: f
        }
        let estado: String? = switch c.texto("status") ?? "" {
        case "idea": "Idea"
        case "borrador", "draft": "Borrador"
        case "revision", "review": "En revisión"
        case "aprobado", "approved": "Aprobado"
        case "programado", "scheduled": "Programado"
        case "publicado", "published": "Publicado"
        case "descartado", "discarded": "Descartado"
        case "": nil
        default: c.texto("status")
        }
        var fm = FrontmatterNuevo(tipo: "content", id: id)
        fm.texto("titulo", c.texto("title"))
        fm.literal("tipo", tipo)
        fm.texto("estado", estado)
        fm.texto("pilar", c.texto("pillar"))
        if let canal = c.texto("channel") { fm.poner("canales", .lista([.texto(canal)])) }
        fm.literal("publicar", c.fecha("scheduled_at"))
        fm.literal("publicado", c.fecha("published_at"))
        fm.poner("derivado_de", enlace(c.texto("derived_from_id"), campo: "derived_from_id", en: r))
        fm.texto("evidencia_url", c.texto("evidence_url"))
        fm.texto("motivo", c.texto("failure_reason"))
        revisar(r, usados: ["title", "format", "status", "pillar", "channel", "scheduled_at", "published_at",
                            "derived_from_id", "evidence_url", "failure_reason", "notes", "archived_at"],
                motivos: ["created_at": "La pieza se fecha por «publicar» y «publicado»."])
        var nota = NotaNueva(frontmatter: fm, titulo: d.nombre)
        nota.resumen = [estado, tipo, c.texto("pillar"), c.fecha("scheduled_at").map { "se publica el \(G2Fecha.corta($0))" }]
        nota.seccion("Texto", r.cuerpoUtil.map { reescribirRutasG2($0, desde: d.ruta) })
        if let notas = c.texto("notes") { nota.seccion("Notas", notas) }
        escribir(d.ruta, nota)
    }

    func escribirConversacion(_ r: G2Registro) {
        guard let id = r.id, let d = destinos[id] else { return }
        contar(r)
        bloque("Marca/Conversaciones", destino: area(.marca).carpeta + "/Conversaciones")
        let c = r.campos
        let estado: String? = switch c.bool("qualified") {
        case true?: "Cualificada"
        case false?: "No cualifica"
        case nil: nil
        }
        let contacto = c.texto("contact_id").flatMap { destinos[$0] }
        let pieza = c.texto("content_id").flatMap { destinos[$0] }
        let oportunidad = c.texto("contact_id").flatMap { cid in
            carpeta.registros("opportunity").filter { $0.campos.texto("contact_id") == cid }
        }.flatMap { $0.count == 1 ? $0[0].id.flatMap { destinos[$0] } : nil }
        var fm = FrontmatterNuevo(tipo: "conversation", id: id)
        fm.poner("contacto", enlace(c.texto("contact_id"), campo: "contact_id", en: r))
        fm.texto("perfil", c.texto("handle"))
        fm.texto("canal", c.texto("channel"))
        fm.poner("contenido", enlace(c.texto("content_id"), campo: "content_id", en: r))
        fm.literal("fecha", c.fecha("occurred_at"))
        fm.texto("estado", estado)
        fm.poner("oportunidad", oportunidad.map(wikilink))
        revisar(r, usados: ["contact_id", "handle", "channel", "content_id", "occurred_at", "qualified", "summary"],
                motivos: ["created_at": "La conversación se fecha por cuándo ocurrió."])
        var nota = NotaNueva(frontmatter: fm, titulo: "\(contacto?.nombre ?? c.texto("handle") ?? d.nombre) en \(c.texto("channel") ?? "")")
        nota.resumen = [estado, c.fecha("occurred_at").map(G2Fecha.corta), pieza.map { "viene de «\($0.nombre)»" }]
        nota.seccion("Lo que dijo", c.texto("summary"))
        nota.seccion("Contexto", r.cuerpoUtil)
        nota.seccion("Decisión de Ventas")
        escribir(d.ruta, nota)
    }

    func escribirMarca(_ r: G2Registro) {
        guard let d = destinos["marca"] else { return }
        contar(r)
        bloque("Marca/Identidad.md", destino: area(.marca).carpeta + "/Marca.md")
        var fm = FrontmatterNuevo(tipo: "brand", id: r.id ?? IDsDerivados.id("marca"))
        fm.texto("nombre", nombreEmpresa)
        fm.literal("version", r.campos.texto("version"))
        revisar(r, usados: ["version"])
        var nota = NotaNueva(frontmatter: fm)
        nota.cuerpoLiteral = reescribirRutasG2(r.cuerpo, desde: d.ruta)
        escribir(d.ruta, nota)
    }

    func escribirGuion(_ r: G2Registro) {
        guard let d = notaDeRutaG2[r.ruta.raw] else { return }
        contar(r)
        bloque(r.ruta.parent?.raw ?? "Guiones", destino: d.ruta.parent?.raw ?? "")
        let codigo = area(deCarpetaG2: r.ruta) ?? .ventas
        var fm = FrontmatterNuevo(tipo: "asset", id: r.id ?? IDsDerivados.id("activo:" + r.ruta.raw))
        fm.texto("nombre", d.nombre)
        fm.literal("area", codigo.layoutKey)
        fm.literal("version", r.campos.texto("version"))
        revisar(r, usados: ["version"])
        var nota = NotaNueva(frontmatter: fm)
        nota.cuerpoLiteral = reescribirRutasG2(r.cuerpo, desde: d.ruta)
        escribir(d.ruta, nota)
    }
}
