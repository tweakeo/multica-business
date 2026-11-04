// Procedencia: port reescrito de Programa v0.5 (Manu), core/tarjetas.js: las tarjetas no se guardan, se generan del
// estado; cada una contesta cinco preguntas (qué pasa · por qué importa · qué hago · qué pasa si no · qué recomienda);
// la prioridad combina factores con pesos (`PESO`) y umbrales calibrados (`nivelPrioridad`); el nivel del rol decide
// qué clases llegan. Solo se guarda lo que la persona decidió sobre ellas. Los generadores leen fichas y CSV en vez
// de SQL. El tope de 5 tarjetas al día que no son rojas es de PLAN §4.5 (`avisos.tope_tarjetas_dia`).
// Ver docs/PROCEDENCIA.md.
import Foundation

public enum TipoTarjeta: String, Sendable, Hashable, CaseIterable {
    case ejecutar, seguimiento, revisar, cobro, excepcion, decidir, riesgo, criterio, planificar

    public var etiqueta: String {
        switch self {
        case .ejecutar: "Hacer"
        case .seguimiento: "Seguimiento"
        case .revisar: "Revisar"
        case .cobro: "Cobro"
        case .excepcion: "Excepción"
        case .decidir: "Decidir"
        case .riesgo: "Riesgo"
        case .criterio: "Criterio"
        case .planificar: "Planificar"
        }
    }
}

/// Qué clases de tarjeta llegan a cada nivel de rol: un responsable no recibe las tareas de su equipo, sino sus
/// excepciones. El titular lo ve todo.
public enum NivelTarjeta: Int, Sendable, Hashable, Comparable, CaseIterable {
    case ejecucion, responsable, direccion, titular

    public static func < (a: NivelTarjeta, b: NivelTarjeta) -> Bool { a.rawValue < b.rawValue }
}

/// La prioridad que se enseña sale de los puntos y del riesgo real, no de un campo que alguien rellena.
public enum PrioridadTarjeta: String, Sendable, Hashable {
    case normal, atencion, critico, riesgoEmpresarial

    public var etiqueta: String {
        switch self {
        case .normal: "Normal"
        case .atencion: "Atención"
        case .critico: "Crítico"
        case .riesgoEmpresarial: "Riesgo para la empresa"
        }
    }

    /// Roja: no entra en el tope diario.
    public var esRoja: Bool { self == .critico || self == .riesgoEmpresarial }
}

/// Los factores con los que se puntúa una tarjeta (0–10), guardados para poder explicar el orden.
public struct FactoresTarjeta: Sendable, Hashable {
    public var urgencia = 0.0, impacto = 0.0, plazo = 0.0, riesgo = 0.0
    public var dependencias = 0.0, estrategia = 0.0, relacion = 0.0, responsabilidad = 0.0

    public init(urgencia: Double = 0, impacto: Double = 0, plazo: Double = 0, riesgo: Double = 0, dependencias: Double = 0,
                estrategia: Double = 0, relacion: Double = 0, responsabilidad: Double = 0) {
        self.urgencia = urgencia; self.impacto = impacto; self.plazo = plazo; self.riesgo = riesgo
        self.dependencias = dependencias; self.estrategia = estrategia; self.relacion = relacion
        self.responsabilidad = responsabilidad
    }

    /// Pesos de tarjetas.js.
    public var puntos: Double {
        let total = urgencia * 1.0 + impacto * 1.2 + plazo * 1.1 + riesgo * 1.3 + dependencias * 0.9 + estrategia * 1.0
            + relacion * 0.6 + responsabilidad * 0.8
        return (total * 10).rounded() / 10
    }

    /// Umbrales calibrados con la distribución real de puntos (12 a 47): sin calibrar, casi todo salía crítico.
    public var prioridad: PrioridadTarjeta {
        if riesgo >= 8 { return .riesgoEmpresarial }
        if puntos >= 36 { return .critico }
        if puntos >= 24 { return .atencion }
        return .normal
    }
}

/// Lo que hace el botón de una tarjeta. Nunca sale nada fuera sin la persona: «preparar» deja un borrador.
public enum AccionTarjeta: Sendable, Hashable {
    case abrir(VaultPath)
    case marcarHecha(VaultPath)
    case prepararMensaje(VaultPath)
    case prepararReclamacion(factura: String, ficha: VaultPath?)
    case decidirPlan(VaultPath)
    case replantearPlazo(VaultPath)
    case meterEnEmbudo(VaultPath)
    case fijarUmbral(String)
    case verArea(AreaCode)
    case bajarDeEscalon(capacidad: String, a: Ejecutor)
    case convertirEnRegla(patron: String, accion: String)
    case verSemana
}

public struct BotonTarjeta: Sendable, Hashable {
    public let etiqueta: String
    public let accion: AccionTarjeta
}

/// Lo que se puede hacer con una tarjeta además de su botón.
public enum AccionDisponible: String, Sendable, Hashable {
    case ejecutar, posponer, delegar, descartar, contexto
}

/// Una tarjeta: contesta las cinco preguntas y trae una recomendación y un botón.
public struct Tarjeta: Sendable, Hashable, Identifiable {
    /// Determinista: `tipo:entidad:id`.
    public let id: String
    public let tipo: TipoTarjeta
    public let nivel: NivelTarjeta
    public let area: AreaCode?
    public let titulo: String
    /// Qué pasa.
    public let quePasa: String
    /// Por qué importa.
    public let porQueImporta: String
    /// Qué hago (el botón, dicho como frase).
    public var queHago: String { boton.etiqueta }
    /// Qué pasa si no.
    public let siNo: String
    /// Qué recomienda.
    public let recomendacion: String
    public let boton: BotonTarjeta
    public let acciones: [AccionDisponible]
    public let impactoEUR: Double?
    public let horas: Double?
    public let factores: FactoresTarjeta
    /// Clase de decisión, para aprender de lo que decides (`seguimiento-oportunidad-Propuesta`).
    public let patron: String
    public let contexto: VaultPath?

    public var puntos: Double { factores.puntos }
    public var prioridad: PrioridadTarjeta { factores.prioridad }
}

/// Lo que la persona decidió sobre una tarjeta (lo único que se guarda; lo guarda quien la enseña).
public struct EstadoTarjeta: Sendable, Hashable, Codable {
    public let id: String
    public var pospuestaHasta: LocalDate?
    public var descartada: Bool
    public var resuelta: Bool

    public init(id: String, pospuestaHasta: LocalDate? = nil, descartada: Bool = false, resuelta: Bool = false) {
        self.id = id; self.pospuestaHasta = pospuestaHasta; self.descartada = descartada; self.resuelta = resuelta
    }
}

/// Una decisión ya tomada sobre una tarjeta (el rastro para aprender).
public struct DecisionTarjeta: Sendable, Hashable, Codable {
    public let patron: String
    public let accion: String
    public init(patron: String, accion: String) { self.patron = patron; self.accion = accion }
}

/// Las tarjetas de un área (se entra en un bloque y se procesa entero).
public struct MazoArea: Sendable, Hashable, Identifiable {
    public var id: String { area?.rawValue ?? "general" }
    public let area: AreaCode?
    public let tarjetas: [Tarjeta]
    public var puntos: Double { tarjetas.map(\.puntos).max() ?? 0 }
}

/// El mazo del día.
public struct Mazo: Sendable, Hashable {
    /// Todas las vivas, de más a menos puntos.
    public let tarjetas: [Tarjeta]
    /// Las que se enseñan hoy: todas las rojas y, como mucho, el tope de las demás.
    public let mostradas: [Tarjeta]
    /// Las que no rojas que esperan a otro día por el tope.
    public let fueraDelTope: Int
    public let mazos: [MazoArea]
    /// Exactamente una: la de más puntos (o, sin ninguna viva, «Nada urgente: reparte la semana»).
    public let foco: Tarjeta

    public var total: Int { tarjetas.count }
    public var rojas: Int { tarjetas.filter { $0.prioridad.esRoja }.count }
    public var impactoTotal: Double { tarjetas.compactMap(\.impactoEUR).reduce(0, +) }
}

/// Genera las tarjetas del estado de la carpeta y elige UN foco.
public struct TarjetaBuilder: Sendable {
    public let evaluador: KPIEvaluador
    public let objetivos: [RitmoObjetivo]
    public let presiones: [PresionArea]
    public let etapas: [EtapaArea]
    public let estados: [String: EstadoTarjeta]
    public let historial: [DecisionTarjeta]
    public let catalogo: CatalogoPrograma

    public init(evaluador: KPIEvaluador, objetivos: [RitmoObjetivo], presiones: [PresionArea], etapas: [EtapaArea] = [],
                estados: [EstadoTarjeta] = [], historial: [DecisionTarjeta] = [], catalogo: CatalogoPrograma = .deSerie) {
        self.evaluador = evaluador; self.objetivos = objetivos; self.presiones = presiones; self.etapas = etapas
        self.estados = Dictionary(estados.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        self.historial = historial; self.catalogo = catalogo
    }

    var foto: FotoMetricas { evaluador.foto }
    var hoy: LocalDate { foto.hoy }

    // MARK: Escalas de tarjetas.js

    /// Impacto en euros, de 0 a 10.
    public static func impacto(_ eur: Double?) -> Double {
        guard let eur, eur > 0 else { return 0 }
        return min(10, log10(max(eur, 1)) * 2.4)
    }

    /// Plazo: cuanto menos margen, más peso. Vencido pesa el máximo.
    public static func plazo(_ dias: Int?) -> Double {
        guard let d = dias else { return 0 }
        return d < 0 ? 10 : d == 0 ? 9 : Double(max(0, 8 - d))
    }

    static func euros(_ n: Double) -> String { n == n.rounded() ? FormatoBase.euros(n, redondo: true) : FormatoBase.euros(n) }
    static func dias(_ n: Int) -> String { n == 1 ? "1 día" : "\(n) días" }
    static func nombre(_ s: String?) -> String? { s.map(LinkParser.plainText)?.nilSiVacio }

    // MARK: Mazo

    public func mazo(nivelMax: NivelTarjeta = .titular) -> Mazo {
        let vivas = generar().filter { $0.nivel <= nivelMax }.filter { t in
            guard let e = estados[t.id] else { return true }
            if e.descartada || e.resuelta { return false }
            if let p = e.pospuestaHasta, p > hoy { return false }
            return true
        }.enumerated().sorted { a, b in
            a.element.puntos != b.element.puntos ? a.element.puntos > b.element.puntos : a.offset < b.offset
        }.map(\.element)
        let tope = foto.config.topeTarjetasDia
        var noRojas = 0
        var mostradas: [Tarjeta] = []
        for t in vivas {
            if t.prioridad.esRoja { mostradas.append(t); continue }
            if noRojas < tope { mostradas.append(t); noRojas += 1 }
        }
        var porArea: [MazoArea] = []
        for a in [nil] + AreaCode.allCases.map(Optional.some) {
            let t = mostradas.filter { $0.area == a }
            if !t.isEmpty { porArea.append(MazoArea(area: a, tarjetas: t)) }
        }
        porArea.sort { $0.puntos > $1.puntos }
        return Mazo(tarjetas: vivas, mostradas: mostradas, fueraDelTope: vivas.count - mostradas.count, mazos: porArea,
                    foco: mostradas.first ?? calma())
    }

    /// El foco de hoy: siempre exactamente uno.
    public func foco() -> Tarjeta { mazo().foco }

    /// Sin nada vivo, el foco es repartir la semana.
    func calma() -> Tarjeta {
        Tarjeta(id: "planificar:semana:\(FormatoBase.lunes(de: hoy))", tipo: .planificar, nivel: .ejecucion, area: .direccion,
                titulo: "Nada urgente: reparte la semana", quePasa: "No hay nada vencido, ni en rojo, ni esperando tu decisión.",
                porQueImporta: "Un día sin incendios es el momento de adelantar lo importante.",
                siNo: "La semana se llena sola de lo urgente.",
                recomendacion: "Elige una cosa importante y planifícala en el hueco de hoy.",
                boton: BotonTarjeta(etiqueta: "Ver tu semana", accion: .verSemana), acciones: [.ejecutar],
                impactoEUR: nil, horas: nil, factores: FactoresTarjeta(), patron: "planificar-semana", contexto: nil)
    }

    // MARK: Generadores

    /// Todas las tarjetas que salen del estado de hoy (sin filtrar por lo decidido ni por el tope).
    public func generar() -> [Tarjeta] {
        ejecutar() + seguimientos() + revisar() + cobros() + proyectosTarde() + conversaciones() + riesgos() + cuellos()
            + promovibles() + umbrales() + reglas()
    }

    /// EJECUTAR · el trabajo del día que ya está planificado.
    func ejecutar() -> [Tarjeta] {
        foto.tareas.filter { t in
            guard t.abierta, !t.esDecision, t.tarea.estado == .porHacer || t.tarea.estado == .enCurso else { return false }
            if t.tarea.creada.map({ $0 > hoy }) ?? false { return false }
            return (t.tarea.planificada.map { $0 <= hoy } ?? false) || (t.tarea.vence.map { $0 <= hoy.adding(days: 7) } ?? false)
        }.map { t in
            let x = t.tarea
            let diasPlazo = (x.vence ?? x.planificada).map { RangoFechas.diasEntre(hoy, $0) }
            let op = x.oportunidad.flatMap { r in foto.oportunidades.first { $0.ruta == r } }
            let eur = op?.valor
            let proyecto = (x.proyecto ?? x.proyectoPorRuta).flatMap { r in foto.proyectos.first { $0.ruta == r } }
            let prio = TextFolding.fold(x.prioridad ?? "")
            let urgencia: Double = prio == "urgente" ? 8 : prio == "alta" ? 6 : prio == "media" || prio == "normal" ? 4 : 1
            let vencida = x.vence != nil && (diasPlazo ?? 0) < 0
            let f = FactoresTarjeta(urgencia: urgencia, impacto: Self.impacto(eur), plazo: Self.plazo(diasPlazo),
                                    riesgo: vencida ? 7 : 0, dependencias: proyecto != nil ? 3 : 0, responsabilidad: 6)
            let horas = t.estimacionH.map { "\(FormatoBase.cifra($0, decimales: $0 == $0.rounded() ? 0 : 1)) h estimadas. " } ?? "Sin estimar. "
            return Tarjeta(
                id: "ejecutar:tarea:\(x.uid ?? x.ruta.raw)", tipo: .ejecutar, nivel: .ejecucion, area: x.area ?? .entrega,
                titulo: x.titulo,
                quePasa: proyecto.map { p in "Del proyecto \(p.nombre)" + (Self.nombre(p.empresa).map { " · \($0)" } ?? "") + "." } ?? "Tarea suelta, sin proyecto.",
                porQueImporta: eur.map { "La oportunidad asociada vale \(Self.euros($0))." }
                    ?? (x.vence != nil ? "Tiene una fecha de vencimiento real, no de organización." : "Está planificada para hoy o antes."),
                siNo: vencida ? "Ya está vencida desde hace \(Self.dias(-(diasPlazo ?? 0)))." : "Se arrastra y empuja al resto de la semana.",
                recomendacion: horas + (prio == "urgente" ? "Hacerla hoy sí o sí." : "Hacerla en el bloque de su área."),
                boton: BotonTarjeta(etiqueta: "Marcar hecha", accion: .marcarHecha(x.ruta)),
                acciones: [.ejecutar, .posponer, .delegar, .contexto], impactoEUR: eur, horas: t.estimacionH, factores: f,
                patron: "ejecutar-tarea-\(x.area?.rawValue.lowercased() ?? "sin-area")", contexto: x.ruta)
        }
    }

    /// SEGUIMIENTO · una oportunidad callada (5 días o más sin contacto).
    func seguimientos() -> [Tarjeta] {
        foto.oportunidades.filter { o in
            o.abierta && (o.creada.map { $0 <= hoy } ?? true) && (o.diasQuieta(hoy: hoy) ?? 0) >= 5
        }.map { o in
            let d = o.diasQuieta(hoy: hoy) ?? 0
            let contacto = Self.nombre(o.contacto) ?? o.nombre
            let titulo = "Retomar a \(contacto)" + (Self.nombre(o.empresa).map { " · \($0)" } ?? "")
            let que = [Self.nombre(o.servicio), o.valor.map { "por \(Self.euros($0))" }].compactMap { $0 }.joined(separator: " ")
            let f = FactoresTarjeta(urgencia: Double(min(8, d)), impacto: Self.impacto(o.valor), riesgo: d >= 10 ? 6 : 2,
                                    estrategia: 6, relacion: 5, responsabilidad: 7)
            return Tarjeta(
                id: "seguimiento:oportunidad:\(o.ruta.raw)", tipo: .seguimiento, nivel: .ejecucion, area: .ventas, titulo: titulo,
                quePasa: (que.isEmpty ? "" : "\(que), ") + "en \(o.estado?.rawValue ?? "estado sin escribir"), \(Self.dias(d)) sin contacto.",
                porQueImporta: "Una oportunidad quieta no está en el embudo: está en tu memoria.",
                siNo: d >= 10 ? "A partir de dos semanas de silencio, la mayoría no vuelve." : "Cada día de silencio hace más raro el siguiente mensaje.",
                recomendacion: "Un mensaje corto que retome lo último que dijo, no un «¿cómo lo llevas?».",
                boton: BotonTarjeta(etiqueta: "Preparar el mensaje", accion: .prepararMensaje(o.ruta)),
                acciones: [.ejecutar, .posponer, .descartar, .contexto], impactoEUR: o.valor, horas: nil, factores: f,
                patron: "seguimiento-oportunidad-\(o.estado?.rawValue ?? "sin-estado")", contexto: o.ruta)
        }
    }

    /// REVISAR · algo hecho que espera tu visto bueno.
    func revisar() -> [Tarjeta] {
        foto.tareas.filter { $0.abierta && !$0.esDecision && $0.tarea.estado == .enRevision && ($0.tarea.creada.map { $0 <= hoy } ?? true) }.map { t in
            let x = t.tarea
            let proyecto = (x.proyecto ?? x.proyectoPorRuta).flatMap { r in foto.proyectos.first { $0.ruta == r } }
            return Tarjeta(
                id: "revisar:tarea:\(x.uid ?? x.ruta.raw)", tipo: .revisar, nivel: .ejecucion, area: x.area ?? .entrega,
                titulo: "Revisar: \(x.titulo)",
                quePasa: "Está hecho y esperando tu visto bueno" + (proyecto.map { " en \($0.nombre)" } ?? "") + ".",
                porQueImporta: "Lo que espera revisión bloquea a quien viene detrás.",
                siNo: "El trabajo avanza a medias y nadie sabe si vale.",
                recomendacion: "Revisar o devolver con un motivo concreto. No dejarlo en el aire.",
                boton: BotonTarjeta(etiqueta: "Dar el visto bueno", accion: .marcarHecha(x.ruta)),
                acciones: [.ejecutar, .posponer, .contexto], impactoEUR: nil, horas: t.estimacionH,
                factores: FactoresTarjeta(urgencia: 6, plazo: 5, dependencias: 7, responsabilidad: 8),
                patron: "revisar-entregable", contexto: x.ruta)
        }
    }

    /// COBRO · una factura vencida sin cobrar.
    func cobros() -> [Tarjeta] {
        foto.facturas.compactMap { f -> Tarjeta? in
            guard let v = f.vence, v < hoy, f.fecha.map({ $0 <= hoy }) ?? true,
                  let pendiente = evaluador.pendiente(f), pendiente > 0 else { return nil }
            let d = RangoFechas.diasEntre(v, hoy)
            let fa = FactoresTarjeta(urgencia: 7, impacto: Self.impacto(pendiente), plazo: Self.plazo(-d), riesgo: d > 30 ? 8 : 4,
                                     relacion: 4, responsabilidad: 7)
            return Tarjeta(
                id: "cobro:factura:\(f.id)", tipo: .cobro, nivel: .responsable, area: .finanzas,
                titulo: "Reclamar la factura \(f.numero) · \(f.tercero)",
                quePasa: "\(Self.euros(pendiente)) vencidos hace \(Self.dias(d)).",
                porQueImporta: "El cobro es lo único que convierte una venta en caja.",
                siNo: "Cuanto más tarde se reclama, más incómoda es la conversación y más tarda en entrar.",
                recomendacion: "Reclamación escrita hoy, con el número de factura y la fecha de vencimiento.",
                boton: BotonTarjeta(etiqueta: "Preparar la reclamación", accion: .prepararReclamacion(factura: f.id, ficha: f.ficha)),
                acciones: [.ejecutar, .posponer, .delegar, .contexto], impactoEUR: pendiente, horas: nil, factores: fa,
                patron: "reclamar-factura", contexto: f.ficha)
        }
    }

    /// EXCEPCIÓN · un proyecto fuera de fecha o que llega justo.
    func proyectosTarde() -> [Tarjeta] {
        foto.proyectos.compactMap { p -> Tarjeta? in
            guard p.estado == .enCurso || p.estado == .sinEmpezar, let fin = p.fin, fin < hoy.adding(days: 5) else { return nil }
            let d = RangoFechas.diasEntre(hoy, fin)
            let vencido = fin < hoy
            let abiertas = foto.tareas.filter { ($0.tarea.proyecto == p.ruta || $0.tarea.proyectoPorRuta == p.ruta) && $0.abierta }.count
            let partes = [Self.nombre(p.empresa), abiertas == 1 ? "1 tarea abierta" : "\(abiertas) tareas abiertas",
                          vencido ? "\(Self.dias(-d)) de retraso" : "\(Self.dias(d)) de margen"].compactMap { $0 }
            let f = FactoresTarjeta(urgencia: vencido ? 9 : 5, plazo: Self.plazo(d), riesgo: vencido ? 8 : 3, dependencias: 6,
                                    relacion: 7, responsabilidad: 8)
            return Tarjeta(
                id: "excepcion:proyecto:\(p.ruta.raw)", tipo: .excepcion, nivel: .responsable, area: p.area ?? .entrega,
                titulo: "\(p.nombre) \(vencido ? "está fuera de fecha" : "llega justo de fecha")",
                quePasa: partes.joined(separator: " · ") + ".",
                porQueImporta: "La alerta de vencidos no se negocia a la baja: uno es información, dos es un patrón.",
                siNo: "El cliente se enterará del retraso antes de que se lo cuentes, y eso ya es otra conversación.",
                recomendacion: abiertas > 0 ? "Decidir qué se cae de las \(abiertas == 1 ? "tareas abiertas" : "\(abiertas) tareas abiertas") o mover la fecha con el cliente, hoy."
                    : "Cerrarlo formalmente o mover la fecha con el cliente.",
                boton: BotonTarjeta(etiqueta: "Replantear el plazo", accion: .replantearPlazo(p.ruta)),
                acciones: [.ejecutar, .posponer, .contexto], impactoEUR: nil, horas: nil, factores: f,
                patron: "proyecto-fuera-de-fecha", contexto: p.ruta)
        }
    }

    /// DECIDIR · una conversación cualificada que no ha entrado al embudo.
    func conversaciones() -> [Tarjeta] {
        foto.conversaciones.filter { $0.cualificada && $0.contacto == nil && $0.oportunidad == nil && ($0.fecha.map { $0 <= hoy } ?? true) }.map { c in
            let quien = c.perfil.map(LinkParser.plainText) ?? c.ruta.stem
            return Tarjeta(
                id: "decidir:conversacion:\(c.ruta.raw)", tipo: .decidir, nivel: .responsable, area: .ventas,
                titulo: "\(quien) encaja y no está en el embudo",
                quePasa: "Una conversación cualificada sin contacto ni oportunidad.",
                porQueImporta: "Cualificada por: \(c.motivo ?? "sin motivo apuntado"). El mensaje directo es el canal más caliente que hay.",
                siNo: "Se queda en la bandeja de la red social, que es donde mueren.",
                recomendacion: "Convertirlo en contacto con su origen, para que Ventas sepa de dónde salió.",
                boton: BotonTarjeta(etiqueta: "Meterlo al embudo", accion: .meterEnEmbudo(c.ruta)),
                acciones: [.ejecutar, .descartar, .contexto], impactoEUR: nil, horas: nil,
                factores: FactoresTarjeta(urgencia: 6, impacto: 5, estrategia: 7, relacion: 6, responsabilidad: 5),
                patron: "conversacion-cualificada", contexto: c.ruta)
        }
    }

    /// RIESGO · un objetivo que no va a llegar.
    func riesgos() -> [Tarjeta] {
        objetivos.filter { [.atencion, .enRiesgo, .critico].contains($0.estado) }.map { r in
            let o = r.objetivo
            let u = (o.unidad ?? "").isEmpty ? "n" : o.unidad!
            func cifra(_ n: Double) -> String { KPIEvaluador.formatear(n, unidad: u) }
            let falta = r.falta ?? 0
            let restantes = r.diasRestantes ?? 7
            let semanas = max(1, Int((Double(max(restantes, 1)) / 7).rounded(.up)))
            let esEuro = u == "€"
            let f = FactoresTarjeta(
                urgencia: r.estado == .critico ? 9 : r.estado == .enRiesgo ? 7 : 4,
                impacto: esEuro ? Self.impacto(falta) : 5, plazo: Self.plazo(r.diasRestantes),
                riesgo: o.prioritario ? 9 : r.estado == .critico ? 7 : 4, estrategia: 9, responsabilidad: 7)
            let porSemana = KPIEvaluador.redondear(falta / Double(semanas), u == "n" ? 1 : 2)
            return Tarjeta(
                id: "riesgo:objetivo:\(o.ruta.raw)", tipo: .riesgo, nivel: .direccion, area: o.area,
                // «Vas al 53 % de lo previsto» se entiende mejor que «53 % del ritmo» (revisión final de F2). Sin dato no
                // se escribe un 0.
                titulo: "\(o.titulo): " + (r.pct.map { "vas al \($0)\u{00A0}% de lo previsto" } ?? "por debajo de lo previsto"),
                quePasa: "\(r.real.map(cifra) ?? "Sin dato") de \(r.esperado.map(cifra) ?? "Sin dato") esperados a estas alturas.",
                porQueImporta: "Quedan \(Self.dias(max(0, restantes))) y faltan \(cifra(falta)).",
                siNo: o.prioritario ? "Es un objetivo prioritario: fallarlo cambia el trimestre." : "El periodo se cierra por debajo y arrastra al siguiente.",
                recomendacion: o.acumulado ? "Hacen falta \(cifra(porSemana)) por semana durante \(semanas == 1 ? "1 semana" : "\(semanas) semanas")."
                    : "Recuperar el nivel de \(cifra(o.meta ?? 0)).",
                boton: BotonTarjeta(etiqueta: "Decidir el plan", accion: .decidirPlan(o.ruta)),
                acciones: [.ejecutar, .posponer, .contexto], impactoEUR: esEuro ? falta : nil, horas: nil, factores: f,
                patron: "objetivo-\(r.estado.rawValue)", contexto: o.ruta)
        }
    }

    /// EXCEPCIÓN · el cuello de botella (como mucho dos, con presión de más de 40).
    func cuellos() -> [Tarjeta] {
        presiones.filter { $0.presion > 40 && $0.bloquea }.prefix(2).enumerated().map { i, p in
            Tarjeta(
                id: "excepcion:cuello:\(p.area.rawValue)", tipo: .excepcion, nivel: .direccion, area: p.area,
                titulo: "\(p.area.nombre) está frenando al resto",
                quePasa: "Ritmo al \(min(p.ritmo, 100)) % · etapa \(p.etapa)"
                    + (p.manuales == 0 ? "." : p.manuales == 1 ? " · 1 función todavía a mano." : " · \(p.manuales) funciones todavía a mano."),
                porQueImporta: "Motivo: \(p.motivo). El cuello no es el área que peor funciona, es la que más te bloquea.",
                siNo: "Mejorar cualquier otra área no cambia el resultado de la empresa.",
                recomendacion: i == 0 ? "Trabajar solo esta área hasta que sus señales dejen de aparecer, y volver a mirar el mapa."
                    : "Segundo foco, después del primero. No los dos a la vez.",
                boton: BotonTarjeta(etiqueta: "Ver el área", accion: .verArea(p.area)),
                acciones: [.contexto, .posponer], impactoEUR: nil, horas: nil,
                factores: FactoresTarjeta(urgencia: i == 0 ? 7 : 4, riesgo: 6, dependencias: 9, estrategia: 10, responsabilidad: 8),
                patron: "cuello-de-botella", contexto: nil)
        }
    }

    /// CRITERIO · lo que ya se ejecuta siempre igual (3 veces o más en la bitácora) y podría bajar de escalón.
    func promovibles() -> [Tarjeta] {
        var out: [Tarjeta] = []
        for (codigo, veces) in foto.ejecuciones.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) where veces >= 3 {
            guard let cap = catalogo.capacidades.first(where: { $0.codigo == codigo }),
                  let d = foto.config.capacidades[codigo], d.declarada else { continue }
            let hoyEj = d.ejecutor ?? cap.ejecutorRecomendado
            guard let siguiente = hoyEj.siguiente, hoyEj != .script else { continue }
            out.append(Tarjeta(
                id: "criterio:capacidad:\(codigo)", tipo: .criterio, nivel: .direccion, area: cap.area,
                titulo: "\(cap.nombre) ya se hace siempre igual",
                quePasa: "Se ha hecho \(veces) veces con \(hoyEj.etiqueta.lowercased()).",
                porQueImporta: "Un criterio que se repite igual es una regla sin escribir. Y lo que no está escrito no se puede delegar.",
                siNo: "Seguirá costando atención cada vez, para siempre.",
                recomendacion: "Bajarla de \(hoyEj.etiqueta.lowercased()) a \(siguiente.etiqueta.lowercased()). Es lo que mueve la etapa.",
                boton: BotonTarjeta(etiqueta: "Bajar a \(siguiente.etiqueta.lowercased())", accion: .bajarDeEscalon(capacidad: codigo, a: siguiente)),
                acciones: [.ejecutar, .posponer, .descartar], impactoEUR: nil, horas: nil,
                factores: FactoresTarjeta(urgencia: 3, dependencias: 3, estrategia: 8, responsabilidad: 6),
                patron: "promover-capacidad", contexto: nil))
            if out.count == 4 { break }
        }
        return out
    }

    /// DECIDIR · un número sin umbral no puede avisar de nada (como mucho tres).
    func umbrales() -> [Tarjeta] {
        guard let metas = evaluador.metas else { return [] }
        let sin = metas.filas.filter { !$0.meta.fijado }.sorted { a, b in
            let x = KPIEvaluador.area(deCodigo: a.codigo)?.numero ?? 9, y = KPIEvaluador.area(deCodigo: b.codigo)?.numero ?? 9
            return x != y ? x < y : a.codigo < b.codigo
        }
        return sin.prefix(3).map { fila in
            let escrito = fila.meta.vacioDeTexto && fila.alerta.vacioDeTexto ? "La meta y la alerta están en blanco."
                : "Meta escrita: «\(fila.meta.texto)». Alerta escrita: «\(fila.alerta.texto)». Ninguna tiene cifra."
            return Tarjeta(
                id: "decidir:numero:\(fila.codigo)", tipo: .decidir, nivel: .direccion, area: KPIEvaluador.area(deCodigo: fila.codigo),
                titulo: "\(fila.indicador) no tiene umbral", quePasa: escrito,
                porQueImporta: "Un umbral sin fijar se mira, no vigila: no puede avisar solo.",
                siNo: "El número seguirá siendo decorativo, y te enterarás de los problemas por otra vía.",
                recomendacion: "Fijarlo con tu propio histórico. Un umbral copiado de otro miente desde el primer día.",
                boton: BotonTarjeta(etiqueta: "Fijar el umbral", accion: .fijarUmbral(fila.codigo)),
                acciones: [.ejecutar, .posponer, .descartar], impactoEUR: nil, horas: nil,
                factores: FactoresTarjeta(urgencia: 2, estrategia: 6, responsabilidad: 5),
                patron: "numero-sin-umbral", contexto: metas.ruta)
        }
    }

    /// CRITERIO · la misma decisión ante la misma clase de tarjeta, 3 veces o más.
    func reglas() -> [Tarjeta] {
        var cuenta: [DecisionTarjeta: Int] = [:]
        for d in historial { cuenta[d, default: 0] += 1 }
        return cuenta.filter { $0.value >= 3 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.patron < $1.key.patron }
            .prefix(2).map { d, n in
                Tarjeta(
                    id: "criterio:patron:\(d.patron):\(d.accion)", tipo: .criterio, nivel: .titular, area: .direccion,
                    titulo: "Has resuelto «\(d.patron)» con «\(d.accion)» \(n) veces",
                    quePasa: "Siempre la misma decisión ante la misma clase de tarjeta.",
                    porQueImporta: "Eso ya no es criterio: es una regla que todavía te cuesta atención.",
                    siNo: "Seguirás decidiendo lo mismo una y otra vez.",
                    recomendacion: "Convertirlo en regla: cuando aparezca «\(d.patron)», hacer «\(d.accion)» sin preguntar.",
                    boton: BotonTarjeta(etiqueta: "Convertir en regla", accion: .convertirEnRegla(patron: d.patron, accion: d.accion)),
                    acciones: [.ejecutar, .descartar], impactoEUR: nil, horas: nil,
                    factores: FactoresTarjeta(urgencia: 2, estrategia: 9, responsabilidad: 3),
                    patron: "aprender-regla", contexto: nil)
            }
    }
}
