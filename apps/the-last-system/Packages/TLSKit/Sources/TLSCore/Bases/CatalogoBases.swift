import Foundation

/// Las 24 bases de serie (DISENO-MOSAICO-V2 §4.2), con sus columnas (§4.7), sus pestañas (SISTEMAS §1.4),
/// su vista por defecto y su plantilla. Los `id` son el contrato con la barra lateral (`BaseConocida`).
public enum CatalogoBases {
    // MARK: Valores del diccionario, en su orden (SISTEMAS §3.5)

    public static let estadosCliente = ["Interesado", "Activo", "Antiguo cliente", "Archivado"]
    public static let relaciones = ["cliente", "proveedor", "colaborador", "gestoría", "otro"]
    public static let etapas = ["Prospecto", "Diagnóstico", "Propuesta", "Aceptada", "Ganada", "Perdida", "Pausada"]
    public static let etapasAbiertas = ["Prospecto", "Diagnóstico", "Propuesta", "Aceptada"]
    public static let estadosServicio = ["En pruebas", "Activo", "Retirado"]
    public static let estadosPropuesta = ["Borrador", "Aprobada", "Enviada", "Aceptada", "Rechazada", "Caducada"]
    public static let tiposReunion = ["Descubrimiento", "Seguimiento", "Sesión", "Interna"]
    public static let estadosReunion = ["Prevista", "Hecha", "Cancelada"]
    public static let estadosProyecto = ["Sin empezar", "En curso", "Pausado", "Cerrado", "Archivado"]
    public static let gravedades = ["Leve", "Media", "Grave"]
    public static let estadosIncidencia = ["Recibida", "En curso", "Resuelta", "Cerrada"]
    public static let estadosTarea = ["Sin programar", "Por hacer", "En curso", "En revisión", "Bloqueada", "Hecha", "Cancelada"]
    public static let tiposTarea = ["tarea", "pregunta", "decision"]
    public static let estadosFactura = ["Borrador", "Emitida", "Enviada", "Cobrada", "Rectificada"]
    public static let tiposContenido = ["post", "carrusel", "video", "newsletter", "articulo", "anuncio", "caso", "testimonio"]
    public static let estadosContenido = ["Idea", "Borrador", "En revisión", "Aprobado", "Programado", "Publicado", "Descartado"]
    public static let estadosConversacion = ["Nueva", "En curso", "Cualificada", "Descartada"]
    public static let estadosSistema = ["Falta", "A medias", "Montado", "Funciona sin ti"]
    public static let estadosActivo = ["En uso", "Retirado"]
    public static let estadosDecision = ["Propuesta", "Tomada", "Revisada", "Sustituida"]
    public static let estadosObjetivo = ["En curso", "Cumplido", "No cumplido"]
    public static let estadosColaboracion = ["Propuesta", "Activa", "Terminada"]
    public static let estadosBorrador = ["Pendiente de tu OK", "Aprobado", "Enviado", "Descartado"]
    public static let clasesRol = ["humano", "asistente"]
    public static let areasClave = AreaCode.allCases.map(\.layoutKey)

    // MARK: Columnas comunes

    private static func titulo(_ etiqueta: String, ancho: Double = 220, deSerie: Bool = true) -> ColumnaBase {
        ColumnaBase(ColumnaBase.claveTitulo, etiqueta, .titulo, ancho: ancho, deSerie: deSerie)
    }

    private static func rel(_ clave: String, _ etiqueta: String, con base: String, alias: [String] = [],
                            deSerie: Bool = true, ancho: Double = 170) -> ColumnaBase {
        ColumnaBase(clave, etiqueta, .relacion, alias: alias, relacionCon: base, ancho: ancho, deSerie: deSerie)
    }

    private static func estado(_ opciones: [String], etiqueta: String = "Estado", clave: String = "estado",
                               alias: [String] = ["status"]) -> ColumnaBase {
        ColumnaBase(clave, etiqueta, .opcion, alias: alias, opciones: opciones, ancho: 132)
    }

    private static func fecha(_ clave: String, _ etiqueta: String, alias: [String] = [], deSerie: Bool = true) -> ColumnaBase {
        ColumnaBase(clave, etiqueta, .fecha, alias: alias, ancho: 110, deSerie: deSerie)
    }

    private static func dinero(_ clave: String, _ etiqueta: String, alias: [String] = [], deSerie: Bool = true) -> ColumnaBase {
        ColumnaBase(clave, etiqueta, .dinero, alias: alias, ancho: 96, deSerie: deSerie)
    }

    private static func texto(_ clave: String, _ etiqueta: String, alias: [String] = [], deSerie: Bool = true,
                              ancho: Double = 160) -> ColumnaBase {
        ColumnaBase(clave, etiqueta, .texto, alias: alias, ancho: ancho, deSerie: deSerie)
    }

    private static func calc(_ clave: String, _ etiqueta: String, _ calculo: Calculo, _ explicacion: String,
                             deSerie: Bool = true, ancho: Double = 120) -> ColumnaBase {
        ColumnaBase(clave, etiqueta, .calculada, calculo: calculo, explicacion: explicacion, ancho: ancho, deSerie: deSerie)
    }

    private static let responsable = ColumnaBase("responsable", "Responsable", .persona, alias: ["assignee"], ancho: 140)
    private static let areaColumna = ColumnaBase(ColumnaBase.claveArea, "Área", .opcion, opciones: AreaCode.allCases.map(\.nombre), ancho: 110)
    private static let creada = fecha("creada", "Creada", alias: ["created_at", "entrada"], deSerie: false)

    private static func porEstado(_ pares: [(String, [String])], archivados: [String] = [], clave: String = "estado") -> [PestanaBase] {
        pares.map { titulo, valores in
            PestanaBase(titulo, .valores(clave, valores), archivada: !Set(valores).isDisjoint(with: archivados))
        }
    }

    // MARK: Las 24

    public static let deSerie: [ColeccionBase] = [
        // Comunes
        ColeccionBase(
            id: "tareas", nombre: "Tareas", singular: "tarea", femenino: true, icono: "checkmark.square", area: nil,
            fuentes: [.fichas([.task])], hogar: "Tareas/ de cada área y proyecto", notaIndice: nil,
            frase: "Todo lo que hay que hacer, de todas las áreas y proyectos, con quién lo hace y para cuándo.",
            vista: .lista, vistas: [.lista, .tabla, .tablero, .calendario],
            columnas: [
                ColumnaBase("numero", "Número", .texto, ancho: 84),
                titulo("Título", ancho: 260),
                areaColumna,
                rel("proyecto", "Proyecto u oportunidad", con: "proyectos", alias: ["oportunidad"]),
                responsable,
                fecha("planificada", "Planificada"),
                fecha("vence", "Vence"),
                estado(estadosTarea),
                ColumnaBase("tipo", "Tipo", .opcion, opciones: tiposTarea, ancho: 100, deSerie: false),
                creada,
            ],
            agruparPor: "estado",
            pestanas: [
                PestanaBase("Lo mío", .mio),
                PestanaBase("Hoy", .hoy("planificada")),
                PestanaBase("Semana", .semana("planificada")),
                PestanaBase("Vencidas", .vencidas("vence")),
                PestanaBase("Sin programar", .valores("estado", ["Sin programar"])),
            ],
            cerrados: ["Hecha", "Cancelada"], fechaCalendario: "vence", plantilla: "tarea", creaConTitulo: true),
        ColeccionBase(
            id: "sistemas", nombre: "Sistemas", singular: "sistema", femenino: false, icono: "gearshape.2", area: nil,
            fuentes: [.fichas([.system])], hogar: "N · Área/Sistemas", notaIndice: nil,
            frase: "Cómo se hace cada cosa en la empresa: sus pasos, quién los lleva y cómo va.",
            vista: .lista, vistas: [.lista, .tabla, .galeria],
            columnas: [
                ColumnaBase("codigo", "Código", .texto, ancho: 80),
                titulo("Nombre"),
                areaColumna,
                estado(estadosSistema),
                texto("numero_clave", "Número clave", ancho: 120),
                fecha("revisado", "Revisado"),
                calc("_pasos", "Pasos sin ti", .pasosSinTi, "Se calcula con los pasos del sistema que no haces tú."),
                rel("rol", "Rol", con: "roles", deSerie: false),
            ],
            agruparPor: ColumnaBase.claveArea,
            pestanas: porEstado(estadosSistema.map { ($0, [$0]) }),
            cerrados: [], fechaCalendario: "revisado", plantilla: "ficha-de-sistema"),
        ColeccionBase(
            id: "activos", nombre: "Activos", singular: "activo", femenino: false, icono: "cube", area: nil,
            fuentes: [.fichas([.asset])], hogar: "N · Área/Activos", notaIndice: nil,
            frase: "Lo que usan los sistemas: plantillas, textos y documentos que se reutilizan.",
            vista: .galeria, vistas: [.galeria, .tabla, .lista],
            columnas: [
                titulo("Nombre"),
                rel("sistema", "Sistema", con: "sistemas"),
                estado(estadosActivo),
                fecha("ultimo_uso", "Último uso"),
                ColumnaBase("buen_ejemplo", "Buen ejemplo", .siNo, ancho: 100),
                areaColumna,
            ],
            agruparPor: ColumnaBase.claveArea,
            pestanas: AreaCode.allCases.map { PestanaBase($0.nombre, .valores(ColumnaBase.claveArea, [$0.nombre])) },
            cerrados: ["Retirado"], fechaCalendario: "ultimo_uso", plantilla: "activo"),
        ColeccionBase(
            id: "borradores", nombre: "Borradores", singular: "borrador", femenino: false, icono: "envelope", area: nil,
            fuentes: [.fichas([.draft])], hogar: "N · Área/Borradores", notaIndice: nil,
            frase: "Correos y mensajes preparados que esperan tu OK antes de salir.",
            vista: .lista, vistas: [.lista, .tabla],
            columnas: [
                texto("para", "Para", ancho: 170),
                titulo("Asunto", ancho: 260),
                ColumnaBase("tipo", "Tipo", .texto, ancho: 110),
                ColumnaBase("preparado_por", "Preparado por", .persona, alias: ["autor"], ancho: 140),
                estado(estadosBorrador),
            ],
            agruparPor: "estado",
            pestanas: [
                PestanaBase("Pendientes de tu OK", .valores("estado", ["Pendiente de tu OK", "Pendiente"])),
                PestanaBase("Enviados", .valores("estado", ["Enviado"])),
            ],
            cerrados: ["Enviado", "Descartado"], fechaCalendario: "fecha", plantilla: "borrador-de-mensaje"),

        // 1 · Dirección
        ColeccionBase(
            id: "decisiones", nombre: "Decisiones", singular: "decisión", femenino: true, icono: "signpost.right.and.left",
            area: .direccion, fuentes: [.fichas([.decision])], hogar: "{direccion}/Decisiones", notaIndice: nil,
            frase: "Lo que se decide, por qué y cuándo hay que revisarlo.",
            vista: .lista, vistas: [.lista, .tabla, .calendario],
            columnas: [
                fecha("fecha", "Fecha"),
                titulo("Decisión", ancho: 280),
                ColumnaBase("area", "Área", .opcion, opciones: areasClave, ancho: 110),
                ColumnaBase("afecta", "Afecta a", .relacion, relacionCon: nil, ancho: 180),
                fecha("revisar", "Revisar el"),
                estado(estadosDecision),
            ],
            agruparPor: "estado",
            pestanas: porEstado(estadosDecision.map { ($0, [$0]) }, archivados: ["Sustituida"]),
            cerrados: ["Sustituida"], fechaCalendario: "fecha", plantilla: "ficha-de-decision"),
        ColeccionBase(
            id: "rutinas", nombre: "Rutinas", singular: "rutina", femenino: true, icono: "arrow.triangle.2.circlepath",
            area: .direccion, fuentes: [.fichas([.routine])], hogar: "{direccion}/Rutinas", notaIndice: nil,
            frase: "Las revisiones que se repiten: qué miras y cuándo.",
            vista: .lista, vistas: [.lista, .tabla, .calendario],
            columnas: [
                titulo("Rutina"),
                fecha("proxima", "Próxima"),
                texto("veredicto", "Último veredicto", alias: ["ultimo_veredicto"], ancho: 220),
                texto("cadencia", "Cada cuánto", deSerie: false),
            ],
            agruparPor: nil, pestanas: [], cerrados: [], fechaCalendario: "proxima", plantilla: "rutina"),
        ColeccionBase(
            id: "objetivos", nombre: "Objetivos", singular: "objetivo", femenino: false, icono: "scope", area: .direccion,
            fuentes: [.fichas([.objective])], hogar: "{direccion}/Objetivos", notaIndice: nil,
            frase: "Las metas del trimestre y la cifra que las mide.",
            vista: .galeria, vistas: [.galeria, .tabla, .lista],
            columnas: [
                titulo("Objetivo", ancho: 280),
                calc("_cifra", "Cifra", .cifraObjetivo, "Sale del número clave que lo mide."),
                ColumnaBase("meta", "Meta", .numero, ancho: 80),
                calc("_ritmo", "Ritmo", .ritmoObjetivo, "Compara la cifra con lo que tocaría a estas alturas del periodo."),
                texto("periodo", "Periodo", ancho: 100),
                estado(estadosObjetivo),
            ],
            agruparPor: "periodo", pestanas: [], cerrados: ["Cumplido", "No cumplido"], fechaCalendario: "hasta",
            plantilla: "objetivo", modulo: "objetivos"),

        // 2 · Ventas
        ColeccionBase(
            id: "contactos", nombre: "Contactos", singular: "contacto", femenino: false, icono: "person.crop.circle",
            area: .ventas, fuentes: [.fichas([.contact])], hogar: "{ventas}/Contactos",
            notaIndice: "{ventas}/Contactos/Contactos.md",
            frase: "Las personas con las que trabajas: clientes, interesados, proveedores y colaboradores.",
            vista: .tabla, vistas: [.tabla, .lista, .galeria, .tablero],
            columnas: [
                titulo("Nombre"),
                rel("empresa", "Empresa", con: "empresas", alias: ["empresa_id"]),
                ColumnaBase("relacion", "Relación", .opciones, opciones: relaciones, ancho: 120),
                estado(estadosCliente),
                calc("_ultimo", "Último contacto", .ultimoContacto, "La última reunión o conversación que lo enlaza."),
                texto("siguiente_paso", "Siguiente paso", ancho: 220),
                fecha("siguiente_fecha", "Fecha del siguiente paso", deSerie: false),
                texto("email", "Correo", deSerie: false, ancho: 200),
                texto("canal", "Canal", deSerie: false, ancho: 100),
                creada,
            ],
            agruparPor: "estado",
            pestanas: porEstado([("Activos", ["Activo"]), ("Interesados", ["Interesado"]),
                                 ("Antiguos clientes", ["Antiguo cliente"]), ("Archivados", ["Archivado"])],
                                archivados: ["Archivado"]),
            cerrados: ["Archivado"], fechaCalendario: "siguiente_fecha", plantilla: "contacto", creaConTitulo: true),
        ColeccionBase(
            id: "empresas", nombre: "Empresas", singular: "empresa", femenino: true, icono: "building.2", area: .ventas,
            fuentes: [.fichas([.organization])], hogar: "{ventas}/Empresas", notaIndice: "{ventas}/Empresas/Empresas.md",
            frase: "Las empresas con las que trabajas y qué relación tienen contigo.",
            vista: .galeria, vistas: [.galeria, .tabla, .lista, .tablero],
            columnas: [
                titulo("Nombre"),
                ColumnaBase("tipo", "Tipo", .texto, alias: ["sector"], ancho: 130),
                ColumnaBase("relacion", "Relación", .opciones, opciones: relaciones, ancho: 120),
                estado(estadosCliente),
                calc("_proyectos", "Proyectos activos", .proyectosActivos, "Proyectos sin cerrar que enlazan esta empresa.", ancho: 130),
                calc("_pendiente", "Pendiente de cobro", .pendienteDeCobro,
                     "Facturas emitidas o enviadas a esta empresa menos lo cobrado.", ancho: 140),
                texto("canal", "Canal", deSerie: false, ancho: 100),
                creada,
            ],
            agruparPor: "estado",
            pestanas: porEstado([("Activas", ["Activo"]), ("Interesadas", ["Interesado"]),
                                 ("Antiguos clientes", ["Antiguo cliente"]), ("Archivadas", ["Archivado"])],
                                archivados: ["Archivado"]),
            cerrados: ["Archivado"], fechaCalendario: "creada", plantilla: "empresa", creaConTitulo: true),
        ColeccionBase(
            id: "oportunidades", nombre: "Oportunidades", singular: "oportunidad", femenino: true, icono: "target",
            area: .ventas, fuentes: [.fichas([.opportunity])], hogar: "{ventas}/Oportunidades",
            notaIndice: "{ventas}/Oportunidades/Oportunidades.md",
            frase: "Cada oportunidad es una ficha. Nace junto a su contacto y su empresa, y termina en Ganada (con el cobro visto en el banco) o en Perdida con su motivo.",
            vista: .tablero, vistas: [.tabla, .tablero, .calendario, .galeria, .lista],
            columnas: [
                titulo("Oportunidad"),
                rel("empresa", "Empresa", con: "empresas", alias: ["empresa_id"]),
                rel("contacto", "Contacto", con: "contactos", alias: ["contacto_id"], deSerie: false),
                rel("servicio", "Servicio", con: "servicios", alias: ["producto_id"], ancho: 140),
                estado(etapas, etiqueta: "Etapa", alias: ["stage", "status"]),
                dinero("valor", "Valor", alias: ["value_minor"]),
                ColumnaBase("probabilidad", "Prob.", .porcentaje, ancho: 70),
                calc("_ponderado", "Ponderado", .ponderado, "Valor × probabilidad.", deSerie: false, ancho: 100),
                calc("_dias", "Días en la etapa", .diasEnEtapa, "Días desde que entró en su etapa; más de 7 abierta es quieta.", ancho: 130),
                texto("siguiente_paso", "Siguiente paso", ancho: 220),
                fecha("siguiente_fecha", "Fecha del siguiente paso", deSerie: false),
                ColumnaBase("responsable", "Responsable", .persona, alias: ["assignee"], ancho: 140, deSerie: false),
                texto("canal", "Canal", deSerie: false, ancho: 100),
                creada,
            ],
            agruparPor: "estado", pestanas: [],
            cerrados: ["Ganada", "Perdida", "Pausada"], plegadas: ["Perdida", "Pausada"],
            fechaCalendario: "siguiente_fecha", plantilla: "oportunidad"),
        ColeccionBase(
            id: "servicios", nombre: "Servicios", singular: "servicio", femenino: false, icono: "tag", area: .ventas,
            fuentes: [.fichas([.service])], hogar: "{ventas}/Productos", notaIndice: "{ventas}/Productos/Oferta.md",
            frase: "Lo que vendes, con su precio y su estado.",
            vista: .galeria, vistas: [.galeria, .tabla, .lista],
            columnas: [
                titulo("Nombre"),
                dinero("precio", "Precio", alias: ["price_minor"]),
                estado(estadosServicio),
                calc("_clientes", "Clientes activos", .clientesActivos, "Clientes con una oportunidad Aceptada o Ganada de este servicio."),
                calc("_ingresos", "Ingresos del año", .ingresosDelAno, "Total de las facturas de este servicio en el año."),
                texto("codigo", "Código", deSerie: false, ancho: 80),
                texto("unidad", "Unidad", deSerie: false, ancho: 100),
            ],
            agruparPor: "estado",
            pestanas: porEstado([("Activos", ["Activo"]), ("En pruebas", ["En pruebas"]), ("Retirados", ["Retirado"])],
                                archivados: ["Retirado"]),
            cerrados: ["Retirado"], fechaCalendario: "valido_desde", plantilla: "servicio"),
        ColeccionBase(
            id: "propuestas", nombre: "Propuestas", singular: "propuesta", femenino: true, icono: "doc.text", area: .ventas,
            fuentes: [.fichas([.proposal, .quote, .agreement])], hogar: "{ventas}/Oportunidades", notaIndice: nil,
            frase: "Propuestas, presupuestos y contratos de cada oportunidad, con su versión.",
            vista: .tabla, vistas: [.tabla, .lista, .tablero],
            columnas: [
                titulo("Referencia"),
                rel("empresa", "Empresa", con: "empresas"),
                calc("_tipo", "Tipo", .tipoDeFicha, "Sale del tipo de documento.", ancho: 110),
                ColumnaBase("version", "Versión", .numero, ancho: 70),
                dinero("total", "Total"),
                estado(estadosPropuesta),
                fecha("valida_hasta", "Válida hasta"),
                rel("oportunidad", "Oportunidad", con: "oportunidades", deSerie: false),
                fecha("fecha", "Fecha", deSerie: false),
            ],
            agruparPor: "estado",
            pestanas: porEstado(estadosPropuesta.map { ($0, [$0]) }),
            cerrados: ["Aceptada", "Rechazada", "Caducada"], fechaCalendario: "valida_hasta", plantilla: "propuesta"),
        ColeccionBase(
            id: "reuniones", nombre: "Reuniones", singular: "reunión", femenino: true, icono: "calendar.badge.clock",
            area: .ventas, fuentes: [.fichas([.meeting])], hogar: "Reuniones/ de cada oportunidad, proyecto o área",
            notaIndice: nil, frase: "Descubrimientos, seguimientos, sesiones y reuniones internas.",
            vista: .calendario, vistas: [.calendario, .tabla, .lista],
            columnas: [
                fecha("fecha", "Fecha"),
                titulo("Título", ancho: 260),
                rel("empresa", "Empresa", con: "empresas"),
                ColumnaBase("tipo", "Tipo", .opcion, opciones: tiposReunion, ancho: 130),
                estado(estadosReunion),
                calc("_acciones", "Acciones pendientes", .accionesPendientes, "Las acciones del acta que aún no son tareas hechas."),
                texto("hora", "Hora", deSerie: false, ancho: 70),
            ],
            agruparPor: "tipo",
            pestanas: tiposReunion.map { PestanaBase($0, .valores("tipo", [$0])) },
            cerrados: ["Hecha", "Cancelada"], fechaCalendario: "fecha", plantilla: "reunion", escalaCalendario: .semana),

        // 3 · Entrega
        ColeccionBase(
            id: "proyectos", nombre: "Proyectos", singular: "proyecto", femenino: false, icono: "square.stack.3d.up",
            area: .entrega, fuentes: [.fichas([.project])], hogar: "{entrega}/Proyectos",
            notaIndice: "{entrega}/Proyectos/Proyectos.md",
            frase: "Cada encargo en marcha, con su fase, su avance y lo cobrado.",
            vista: .tabla, vistas: [.tabla, .tablero, .lista, .cronograma],
            columnas: [
                titulo("Nombre"),
                rel("empresa", "Empresa", con: "empresas"),
                texto("fase", "Fase", ancho: 140),
                calc("_avance", "Avance", .avanceProyecto, "Sesiones hechas sobre las incluidas."),
                calc("_cobrado", "Cobrado", .cobradoProyecto, "Lo cobrado de las facturas de este proyecto."),
                fecha("proxima_sesion", "Próxima sesión"),
                responsable,
                estado(estadosProyecto),
                fecha("inicio", "Inicio", alias: ["start"], deSerie: false),
                fecha("fin", "Fin", alias: ["end"], deSerie: false),
            ],
            agruparPor: "estado",
            pestanas: porEstado(estadosProyecto.map { ($0 == "Archivado" ? "Archivados" : $0, [$0]) }, archivados: ["Archivado"]),
            cerrados: ["Cerrado", "Archivado"], fechaCalendario: "proxima_sesion", cronograma: ("inicio", "fin"),
            plantilla: "proyecto-de-entrega"),
        ColeccionBase(
            id: "planes-de-entrega", nombre: "Planes de entrega", singular: "plan de entrega", femenino: false,
            icono: "list.bullet.rectangle", area: .entrega, fuentes: [.fichas([.deliveryTemplate])],
            hogar: "{entrega}/Planes de entrega", notaIndice: nil,
            frase: "Cómo se entrega cada servicio: sus fases y sus sesiones.",
            vista: .lista, vistas: [.lista, .tabla],
            columnas: [
                titulo("Nombre"),
                rel("servicio", "Servicio", con: "servicios"),
                ColumnaBase("dias_proyecto", "Días", .numero, alias: ["dias"], ancho: 70),
                ColumnaBase("sesiones", "Sesiones", .numero, ancho: 80),
                ColumnaBase("estado", "Estado", .texto, ancho: 100, deSerie: false),
            ],
            agruparPor: nil, pestanas: [], cerrados: [], fechaCalendario: nil, plantilla: "plan-de-entrega"),
        ColeccionBase(
            id: "incidencias", nombre: "Incidencias", singular: "incidencia", femenino: true, icono: "exclamationmark.bubble",
            area: .entrega, fuentes: [.fichas([.incident])], hogar: "Incidencias/ de cada proyecto", notaIndice: nil,
            frase: "Lo que falla en un proyecto y cómo se resuelve.",
            vista: .tablero, vistas: [.tablero, .tabla, .lista],
            columnas: [
                ColumnaBase("numero", "Número", .texto, ancho: 84),
                titulo("Título", ancho: 240),
                rel("proyecto", "Proyecto", con: "proyectos"),
                ColumnaBase("gravedad", "Gravedad", .opcion, opciones: gravedades, ancho: 100),
                fecha("plazo", "Plazo"),
                estado(estadosIncidencia),
            ],
            agruparPor: "estado",
            pestanas: gravedades.map { PestanaBase($0, .valores("gravedad", [$0])) },
            cerrados: ["Resuelta", "Cerrada"], fechaCalendario: "plazo", plantilla: "ficha-de-incidencia"),

        // 4 · Finanzas
        ColeccionBase(
            id: "facturas", nombre: "Facturas", singular: "factura", femenino: true, icono: "eurosign.circle",
            area: .finanzas, fuentes: [.fichas([.invoice])], hogar: "{finanzas}/Fiscal", notaIndice: nil,
            frase: "Cada factura con su número, su estado y lo cobrado.",
            vista: .tabla, vistas: [.tabla, .lista, .tablero, .calendario],
            columnas: [
                ColumnaBase("numero", "Número", .texto, ancho: 110),
                // Un particular no tiene empresa: se ve su contacto.
                rel("empresa", "Empresa", con: "empresas", alias: ["contacto"]),
                fecha("fecha", "Fecha"),
                fecha("vence", "Vence"),
                dinero("total", "Total"),
                estado(estadosFactura),
                calc("_cobrado", "Cobrado", .cobradoFactura, "Cobros confirmados de esta factura en el registro de pagos."),
                titulo("Factura", ancho: 200, deSerie: false),
                rel("oportunidad", "Oportunidad", con: "oportunidades", deSerie: false),
                rel("proyecto", "Proyecto", con: "proyectos", deSerie: false),
            ],
            agruparPor: "estado",
            pestanas: porEstado([("Borradores", ["Borrador"]), ("Emitidas", ["Emitida"]), ("Enviadas", ["Enviada"]),
                                 ("Cobradas", ["Cobrada"]), ("Rectificadas", ["Rectificada"])]),
            cerrados: ["Cobrada", "Rectificada"], fechaCalendario: "vence", plantilla: "factura"),
        ColeccionBase(
            id: "cobros", nombre: "Cobros", singular: "cobro", femenino: false, icono: "checkmark.seal", area: .finanzas,
            fuentes: [.fichas([.receipt]),
                      .filasCSV(carpeta: "{finanzas}/Registros", nombre: "pagos.csv", clave: "id", soloSi: ["direccion": "cobro"])],
            hogar: "{finanzas}/Registros/pagos.csv y Cobros", notaIndice: nil,
            frase: "Lo cobrado, con su factura y su movimiento del banco.",
            vista: .tabla, vistas: [.tabla, .lista, .calendario],
            columnas: [
                fecha("fecha", "Fecha"),
                ColumnaBase("factura", "Factura", .texto, alias: ["documento_id"], ancho: 120),
                ColumnaBase("empresa", "Empresa", .texto, alias: ["tercero"], ancho: 190),
                dinero("importe", "Importe"),
                ColumnaBase("movimiento", "Movimiento", .texto, alias: ["pago_id", "evidencia"], ancho: 200),
                ColumnaBase("verificacion", "Confirmado", .opcion, opciones: ["confirmado", "pendiente"], ancho: 110),
                ColumnaBase("metodo", "Método", .texto, ancho: 110, deSerie: false),
                titulo("Cobro", ancho: 160, deSerie: false),
            ],
            agruparPor: nil, pestanas: [], cerrados: [], fechaCalendario: "fecha", plantilla: nil,
            motivoSinCrear: "Un cobro nace desde su factura, cuando confirmas que el dinero está en el banco."),
        ColeccionBase(
            id: "gastos", nombre: "Gastos", singular: "gasto", femenino: false, icono: "cart", area: .finanzas,
            fuentes: [.filasCSV(carpeta: "{finanzas}/Registros", nombre: "recibidas.csv", clave: "id", soloSi: [:])],
            hogar: "{finanzas}/Registros/recibidas.csv", notaIndice: nil,
            frase: "Las facturas recibidas, con su base, su IVA y su categoría.",
            vista: .tabla, vistas: [.tabla, .lista, .calendario, .galeria],  // Galería: la miniatura de cada PDF (R1, F2)
            columnas: [
                fecha("fecha_documento", "Fecha", alias: ["fecha"]),
                ColumnaBase("tercero", "Proveedor", .texto, ancho: 200),
                dinero("base", "Base"),
                dinero("iva", "IVA"),
                dinero("total_documento", "Total", alias: ["total"]),
                ColumnaBase("categoria", "Categoría", .texto, ancho: 130),
                ColumnaBase("numero_documento", "Número", .texto, ancho: 120, deSerie: false),
                dinero("retencion", "Retención", deSerie: false),
                titulo("Gasto", ancho: 160, deSerie: false),
            ],
            agruparPor: "categoria", pestanas: [], cerrados: [], fechaCalendario: "fecha_documento", plantilla: nil,
            motivoSinCrear: "Los gastos entran con «Incorporar gasto», desde su factura en PDF.", pestanasPor: "categoria"),
        ColeccionBase(
            id: "movimientos", nombre: "Movimientos", singular: "movimiento", femenino: false, icono: "arrow.left.arrow.right",
            area: .finanzas,
            fuentes: [.filasCSV(carpeta: "{finanzas}/Registros/Bancos", nombre: "movimientos.csv", clave: "id", soloSi: [:])],
            hogar: "{finanzas}/Registros/Bancos", notaIndice: nil,
            frase: "Los movimientos del banco y con qué se concilian.",
            vista: .tabla, vistas: [.tabla, .lista, .calendario],
            columnas: [
                fecha("fecha", "Fecha"),
                ColumnaBase("concepto", "Concepto", .texto, ancho: 280),
                dinero("importe", "Importe"),
                dinero("saldo", "Saldo"),
                ColumnaBase("documento_id", "Conciliado con", .texto, alias: ["pago_id"], ancho: 150),
                ColumnaBase("estado_conciliacion", "Conciliación", .opcion, opciones: ["pendiente", "conciliado", "ignorado"],
                            ancho: 120, deSerie: false),
                ColumnaBase("categoria", "Categoría", .texto, ancho: 150, deSerie: false),
                titulo("Movimiento", ancho: 160, deSerie: false),
            ],
            agruparPor: nil,
            pestanas: [PestanaBase("Sin conciliar", .noValores("estado_conciliacion", ["conciliado", "ignorado"])),
                       PestanaBase("Conciliados", .valores("estado_conciliacion", ["conciliado"]))],
            cerrados: [], fechaCalendario: "fecha", plantilla: nil,
            motivoSinCrear: "Los movimientos entran al importar el extracto del banco."),

        // 5 · Marca
        ColeccionBase(
            id: "contenidos", nombre: "Contenidos", singular: "contenido", femenino: false, icono: "square.and.pencil",
            area: .marca, fuentes: [.fichas([.content])], hogar: "{marca}/Contenidos", notaIndice: "{marca}/Contenidos/Contenidos.md",
            frase: "Lo que publicas: ideas, borradores y publicaciones.",
            vista: .calendario, vistas: [.calendario, .tablero, .tabla, .lista, .cronograma],
            columnas: [
                titulo("Título", ancho: 280),
                ColumnaBase("tipo", "Tipo", .opcion, opciones: tiposContenido, ancho: 110),
                ColumnaBase("canales", "Canal", .opciones, alias: ["canal"], ancho: 130),
                estado(estadosContenido),
                fecha("publicar", "Fecha de publicar", alias: ["fecha_publicar", "programada", "publicado", "publicada", "fecha"]),
                texto("pilar", "Pilar", deSerie: false),
            ],
            agruparPor: "estado",
            pestanas: tiposContenido.map { PestanaBase($0.capitalized, .valores("tipo", [$0]), id: $0) },
            cerrados: ["Publicado", "Descartado"], fechaCalendario: "publicar", cronograma: ("publicar", "publicar"),
            plantilla: "post", creaConTitulo: true),
        ColeccionBase(
            id: "conversaciones", nombre: "Conversaciones", singular: "conversación", femenino: true,
            icono: "bubble.left.and.bubble.right", area: .marca, fuentes: [.fichas([.conversation])],
            hogar: "{marca}/Conversaciones", notaIndice: "{marca}/Conversaciones/Conversaciones.md",
            frase: "Las conversaciones que trae una publicación y en qué acaban.",
            vista: .lista, vistas: [.lista, .tabla, .tablero],
            columnas: [
                rel("contacto", "Contacto", con: "contactos"),
                rel("contenido", "Pieza de origen", con: "contenidos", ancho: 220),
                texto("canal", "Canal", ancho: 100),
                fecha("fecha", "Fecha"),
                rel("oportunidad", "Oportunidad", con: "oportunidades"),
                estado(estadosConversacion),
                titulo("Conversación", ancho: 180, deSerie: false),
            ],
            agruparPor: "estado",
            pestanas: porEstado(estadosConversacion.map { ($0, [$0]) }),
            cerrados: ["Descartada"], fechaCalendario: "fecha", plantilla: "conversacion"),

        // 6 · Equipo
        ColeccionBase(
            id: "roles", nombre: "Roles", singular: "rol", femenino: false, icono: "person.text.rectangle", area: .equipo,
            fuentes: [.fichas([.role])], hogar: "{equipo}/Roles", notaIndice: "{equipo}/Roles/Roles.md",
            frase: "Quién lleva qué: personas y asistentes.",
            vista: .galeria, vistas: [.galeria, .tabla, .lista],
            columnas: [
                titulo("Rol"),
                ColumnaBase("ocupante", "Ocupante", .persona, ancho: 150),
                ColumnaBase("areas", "Áreas", .opciones, opciones: areasClave, ancho: 160),
                calc("_sistemas", "Sistemas", .sistemasDelRol, "Sistemas que nombran este rol."),
                ColumnaBase("clase", "Clase", .opcion, opciones: clasesRol, ancho: 100, deSerie: false),
            ],
            agruparPor: "clase",
            pestanas: [PestanaBase("Personas", .valores("clase", ["humano", "persona"])),
                       PestanaBase("Asistentes", .valores("clase", ["asistente", "agente"]))],
            cerrados: [], fechaCalendario: nil, plantilla: "rol"),
        ColeccionBase(
            id: "colaboraciones", nombre: "Colaboraciones", singular: "colaboración", femenino: true, icono: "person.2",
            area: .equipo, fuentes: [.fichas([.collaboration])], hogar: "{equipo}/Colaboraciones",
            notaIndice: "{equipo}/Colaboraciones/Colaboraciones.md",
            frase: "Con quién colaboras y en qué proyecto.",
            vista: .lista, vistas: [.lista, .tabla],
            columnas: [
                rel("contacto", "Colaborador", con: "contactos"),
                rel("proyecto", "Proyecto", con: "proyectos"),
                estado(estadosColaboracion),
                fecha("desde", "Desde"),
                titulo("Acuerdo", ancho: 200, deSerie: false),
            ],
            agruparPor: "estado",
            pestanas: porEstado(estadosColaboracion.map { ($0, [$0]) }, archivados: ["Terminada"]),
            cerrados: ["Terminada"], fechaCalendario: "desde", plantilla: "acuerdo-de-colaboracion"),
    ]

    /// Base por su `id`.
    public static func coleccion(_ id: String) -> ColeccionBase? {
        deSerie.first { $0.id == id }
    }

    /// Base que guarda fichas de ese tipo (la primera que lo declara).
    public static func coleccion(paraTipo tipo: NoteKind) -> ColeccionBase? {
        deSerie.first { $0.tipos.contains(tipo) }
    }

    /// Todos los tipos de ficha que salen en alguna base.
    public static var tiposEnBases: Set<NoteKind> { Set(deSerie.flatMap(\.tipos)) }

    /// Orden de «Todas las bases»: Comunes y las áreas 1–6.
    public static var grupos: [(grupo: GrupoBase, bases: [ColeccionBase])] {
        let grupos = Set(deSerie.map(\.grupo)).sorted()
        return grupos.map { g in (g, deSerie.filter { $0.grupo == g }) }
    }
}
