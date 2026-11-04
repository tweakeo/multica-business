// Procedencia: las 15 comprobaciones son un port reescrito de Programa v0.5 (Manu), core/consultoria.js
// (`COMPROBACIONES` y su orden en `comprobar`), sobre las fichas y los CSV en vez de SQL. DIR-03 queda como
// «atención», no como regla dura (PLAN Anexo A). Los 7 chequeos son los de DI2 (docs/propuesta/SISTEMAS.md).
// Ver docs/PROCEDENCIA.md.
import Foundation

/// Lo que encontró un chequeo o una comprobación.
public struct ResultadoChequeo: Sendable, Hashable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    public let familia: Familia
    public let nivel: Nivel
    public let area: AreaCode?
    public let titulo: String
    /// La regla, dicha en una frase.
    public let regla: String
    /// Cómo se arregla.
    public let arreglo: String
    public let casos: [Caso]
    /// Botones que ofrece cada caso («Colgar de un objetivo», «Seguir sin objetivo»).
    public let acciones: [String]

    public var n: Int { casos.count }
    /// Rompe una regla dura y tiene casos: es rojo.
    public var esRojo: Bool { nivel == .grave && n > 0 }

    public enum Familia: String, Sendable, Hashable {
        /// Los siete chequeos de la revisión diaria (DI2).
        case chequeo
        /// Las quince comprobaciones del diagnóstico (Programa).
        case comprobacion
    }

    public enum Nivel: String, Sendable, Hashable {
        /// Rompe una regla dura: sale en Alertas.
        case grave
        /// Huele mal pero puede ser legítimo: atención.
        case flojo
        /// Para saberlo, sin más.
        case info

        public var etiqueta: String {
            switch self {
            case .grave: "Mal"
            case .flojo: "Atención"
            case .info: "Para saber"
            }
        }
    }

    public struct Caso: Sendable, Hashable {
        public let ruta: VaultPath?
        public let detalle: String
        public init(ruta: VaultPath?, detalle: String) { self.ruta = ruta; self.detalle = detalle }
    }
}

/// Los 7 chequeos y las 15 comprobaciones: deterministas, sin ningún asistente.
public struct Chequeo: Sendable {
    public let foto: FotoMetricas
    public let metas: MetasDocumento?
    public let semana: SemanaAgenda?

    public init(foto: FotoMetricas, metas: MetasDocumento?, semana: SemanaAgenda? = nil) {
        self.foto = foto; self.metas = metas; self.semana = semana
    }

    var hoy: LocalDate { foto.hoy }

    /// Todos, con los que tienen casos primero, los graves delante y, dentro, los de más casos.
    public func todos() -> [ResultadoChequeo] {
        Self.ordenar(chequeos() + comprobaciones())
    }

    /// Hay algo rojo (una regla dura rota).
    public func hayRojo() -> Bool { todos().contains(where: \.esRojo) }

    public static func ordenar(_ r: [ResultadoChequeo]) -> [ResultadoChequeo] {
        r.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            if (x.n > 0) != (y.n > 0) { return x.n > 0 }
            if (x.nivel == .grave) != (y.nivel == .grave) { return x.nivel == .grave }
            if x.n != y.n { return x.n > y.n }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Datos comunes

    var tareas: [FotoMetricas.TareaMedida] {
        foto.tareas.filter { t in t.abierta && (t.tarea.creada.map { $0 <= hoy } ?? true) }
    }

    var oportunidades: [FotoMetricas.Oportunidad] {
        foto.oportunidades.filter { $0.creada.map { $0 <= hoy } ?? true }
    }

    func nombre(_ o: FotoMetricas.Oportunidad) -> String {
        LinkParser.plainText(o.empresa ?? o.contacto ?? o.nombre)
    }

    func caso(_ t: FotoMetricas.TareaMedida, _ extra: String? = nil) -> ResultadoChequeo.Caso {
        let base = [t.tarea.numero, t.tarea.titulo].compactMap { $0 }.joined(separator: " · ")
        return .init(ruta: t.tarea.ruta, detalle: extra.map { "\(base) · \($0)" } ?? base)
    }

    func dias(_ n: Int) -> String { n == 1 ? "1 día" : "\(n) días" }

    func tareasDe(_ p: FotoMetricas.Proyecto) -> [FotoMetricas.TareaMedida] {
        foto.tareas.filter { $0.tarea.proyecto == p.ruta || $0.tarea.proyectoPorRuta == p.ruta }
    }

    // MARK: Los 7 chequeos (DI2)

    public func chequeos() -> [ResultadoChequeo] {
        func r(_ codigo: String, _ nivel: ResultadoChequeo.Nivel, _ area: AreaCode?, _ titulo: String, _ regla: String,
               _ arreglo: String, _ casos: [ResultadoChequeo.Caso]) -> ResultadoChequeo {
            ResultadoChequeo(codigo: codigo, familia: .chequeo, nivel: nivel, area: area, titulo: titulo, regla: regla,
                             arreglo: arreglo, casos: casos, acciones: [])
        }
        let trabajo = tareas.filter { !$0.esDecision }

        let sueltas = trabajo.filter { $0.tarea.proyecto == nil && $0.tarea.proyectoPorRuta == nil && $0.tarea.oportunidad == nil }
        let vencidas = trabajo.filter { $0.tarea.vence.map { $0 < hoy } ?? false }
        let enCurso = foto.proyectos.filter { $0.estado == .enCurso }
        let sinPendiente = enCurso.filter { p in !tareasDe(p).contains { $0.abierta } }
        let sinEmpezar = foto.proyectos.filter { $0.estado == .sinEmpezar }
        let conFechas = sinEmpezar.filter { p in
            (p.inicio.map { $0 <= hoy } ?? false) || tareasDe(p).contains { $0.abierta && ($0.tarea.planificada != nil || $0.tarea.vence != nil) }
        }
        let incompletas = oportunidades.filter { $0.abierta && ($0.valor == nil || $0.valor == 0 || $0.responsable == nil) }
        let evaluador = KPIEvaluador(foto: foto, metas: metas)
        let limite = hoy.adding(days: 60)
        let previstos = foto.facturas.filter { f in
            guard let v = f.vence, v >= hoy, v <= limite else { return false }
            return (evaluador.pendiente(f) ?? 0) > 0
        }
        let cargados = (semana ?? Agenda(foto: foto).semana()).dias.filter(\.pasaDelTope)

        return [
            r("CHQ-1", .flojo, nil, "Tareas sin proyecto", "Cada tarea cuelga de un proyecto o de una oportunidad, o es suelta a sabiendas",
              "Ligarla a su proyecto u oportunidad", sueltas.map { caso($0) }),
            r("CHQ-2", .grave, nil, "Tareas vencidas", "El vencimiento es un límite real: pasado, es una promesa rota",
              "Hacerla hoy o hablar con quien la espera", vencidas.map { t in
                  caso(t, "venció hace \(dias(RangoFechas.diasEntre(t.tarea.vence!, hoy)))")
              }),
            r("CHQ-3", .flojo, nil, "Proyectos sin nada pendiente", "Un proyecto en curso sin tareas abiertas está parado o terminado",
              "Planificar lo siguiente o cerrarlo", sinPendiente.map { .init(ruta: $0.ruta, detalle: $0.nombre) }),
            r("CHQ-4", .flojo, nil, "Proyectos pendientes con fechas", "Un proyecto sin empezar no tiene fechas que corran",
              "Arrancarlo o quitarle las fechas hasta que arranque", conFechas.map { .init(ruta: $0.ruta, detalle: $0.nombre) }),
            r("CHQ-5", .flojo, .ventas, "Oportunidades sin valor o sin responsable", "Sin valor y sin responsable el embudo no se puede leer",
              "Completar el valor y quién la lleva", incompletas.map { o in
                  let falta = [o.valor == nil || o.valor == 0 ? "sin valor" : nil, o.responsable == nil ? "sin responsable" : nil].compactMap { $0 }
                  return .init(ruta: o.ruta, detalle: "\(o.nombre) · \(falta.joined(separator: " y "))")
              }),
            r("CHQ-6", .info, .finanzas, "Cobro previsto a 60 días", "Lo que debería entrar en los próximos 60 días",
              "Vigilar que llegue en su fecha", previstos.map { f in
                  .init(ruta: f.ficha, detalle: "\(f.numero) · \(f.tercero) · \(FormatoBase.euros(evaluador.pendiente(f) ?? 0)) · vence \(FormatoBase.fecha(f.vence!, hoy: hoy))")
              }),
            r("CHQ-7", .flojo, .direccion, "Carga por encima del tope", "Un día se juzga por lo que cabe en él: \(FormatoBase.cifra(foto.config.topeHorasDia)) h de trabajo planificado",
              "Mover la fecha planificada de lo que no cabe", cargados.map { d in
                  .init(ruta: nil, detalle: "\(FormatoBase.fechaConDia(d.dia)) · \(d.aviso ?? d.textoCarga)")
              }),
        ]
    }

    // MARK: Las 15 comprobaciones (Programa)

    public func comprobaciones() -> [ResultadoChequeo] {
        func r(_ codigo: String, _ nivel: ResultadoChequeo.Nivel, _ area: AreaCode?, _ titulo: String, _ regla: String,
               _ arreglo: String, _ casos: [ResultadoChequeo.Caso], acciones: [String] = []) -> ResultadoChequeo {
            ResultadoChequeo(codigo: codigo, familia: .comprobacion, nivel: nivel, area: area, titulo: titulo, regla: regla,
                             arreglo: arreglo, casos: casos, acciones: acciones)
        }
        let p = foto.proyectos
        let abiertos = p.filter { $0.estado == .enCurso || $0.estado == .sinEmpezar }
        let ops = oportunidades

        // DIR-03: atención, no rechazo.
        let sinObjetivo = p.filter { $0.estado == .enCurso && $0.objetivo == nil && !$0.sinObjetivo }
        // DIR-03b: objetivos vivos sin ningún proyecto abierto que los mueva.
        let movidos = Set(abiertos.compactMap(\.objetivoRuta))
        let objetivosSolos = foto.objetivosVivos.filter { !movidos.contains($0.ruta) }
        let cuatro = ops.filter { $0.abierta && ($0.valor == nil || $0.valor == 0 || $0.estado == nil || $0.servicio == nil || $0.responsable == nil) }
        let contactosSueltos = foto.contactos.filter { $0.empresa == nil }
        let quietas = ops.filter { $0.abierta && ($0.diasQuieta(hoy: hoy) ?? 0) > 14 }
            .sorted { ($0.diasQuieta(hoy: hoy) ?? 0) > ($1.diasQuieta(hoy: hoy) ?? 0) }
        let perdidasSinMotivo = ops.filter { $0.estado == .perdida && $0.motivoPerdida == nil }
        let noIniciadosConTareas = p.filter { pr in pr.estado == .sinEmpezar && !tareasDe(pr).isEmpty }
        let fueraDeFecha = p.filter { pr in (pr.estado?.abierto ?? true) && pr.fin.map { $0 < hoy } ?? false }
        let entregaSinOportunidad = p.filter { $0.esDeEntrega && $0.oportunidad == nil }
        let evaluador = KPIEvaluador(foto: foto, metas: metas)
        let facturasVencidas = foto.facturas.filter { f in
            guard let v = f.vence, v < hoy, f.fecha.map({ $0 <= hoy }) ?? true else { return false }
            return (evaluador.pendiente(f) ?? 0) > 0
        }.sorted { ($0.vence!, $0.id) < ($1.vence!, $1.id) }
        let trimestre = RangoFechas.trimestre(de: hoy, hasta: hoy)
        let sinClasificar = foto.cuentas.flatMap(\.movimientos).filter { m in
            guard let f = m.fecha, trimestre.contiene(f) else { return false }
            return m.naturaleza == nil && m.categoria == nil && m.documentoId == nil
        }
        let trabajo = tareas.filter { !$0.esDecision }
        let enFinde = trabajo.filter { $0.tarea.planificada?.isWeekend ?? false }
        let arrastrando = trabajo.filter { t in t.tarea.planificada.map { RangoFechas.diasEntre($0, hoy) > 7 } ?? false }
            .sorted { $0.tarea.planificada! < $1.tarea.planificada! }
        let sinDueno = AreaCode.allCases.filter { !foto.tieneDueno($0) }
        let sinUmbral = (metas?.filas ?? []).filter { !$0.meta.fijado }

        return [
            r("DIR-03", .flojo, .direccion, "Proyectos en curso sin objetivo", "Un proyecto en curso debería colgar de un objetivo",
              "Colgarlo de un objetivo, o seguir sin objetivo a sabiendas",
              sinObjetivo.map { .init(ruta: $0.ruta, detalle: $0.nombre) }, acciones: ["Colgar de un objetivo", "Seguir sin objetivo"]),
            r("DIR-03b", .flojo, .direccion, "Objetivos sin ningún proyecto que los mueva", "Un objetivo sin proyecto es un deseo escrito",
              "Crear el proyecto que lo mueve, o cerrar el objetivo", objetivosSolos.map { .init(ruta: $0.ruta, detalle: $0.titulo) }),
            r("VEN-03", .grave, .ventas, "Oportunidades sin valor, estado, servicio o responsable", "Valor, estado, servicio y responsable nunca vacíos",
              "Completar la ficha: sin eso el embudo no se puede leer", cuatro.map { o in
                  let falta = [o.valor == nil || o.valor == 0 ? "valor" : nil, o.estado == nil ? "estado" : nil,
                               o.servicio == nil ? "servicio" : nil, o.responsable == nil ? "responsable" : nil].compactMap { $0 }
                  return .init(ruta: o.ruta, detalle: "\(o.nombre) · falta \(falta.joined(separator: ", "))")
              }),
            r("VEN-01", .grave, .ventas, "Contactos sueltos, sin empresa", "Todo contacto va ligado a su empresa",
              "Ligarlo, aunque la empresa sea él mismo como particular", contactosSueltos.map { .init(ruta: $0.ruta, detalle: $0.nombre) }),
            r("VEN-08", .flojo, .ventas, "Oportunidades abiertas y quietas más de 14 días", "Una oportunidad sin contacto se enfría sola",
              "Un seguimiento, o cerrarla como perdida con su motivo", quietas.map { o in
                  .init(ruta: o.ruta, detalle: "\(nombre(o)) · \(dias(o.diasQuieta(hoy: hoy) ?? 0))")
              }),
            r("VEN-11", .flojo, .ventas, "Perdidas sin motivo escrito", "Una venta perdida sin motivo no enseña nada",
              "Escribir por qué se cayó: es la materia prima del argumentario", perdidasSinMotivo.map { .init(ruta: $0.ruta, detalle: $0.nombre) }),
            r("ENT-01", .grave, .entrega, "Proyectos no iniciados con tareas ya creadas", "Un proyecto sin empezar no lleva tareas: van dentro como lista",
              "Arrancar el proyecto, o quitar las tareas hasta que arranque", noIniciadosConTareas.map { pr in
                  let n = tareasDe(pr).count
                  return .init(ruta: pr.ruta, detalle: "\(pr.nombre) · \(n == 1 ? "1 tarea" : "\(n) tareas")")
              }),
            r("ENT-03", .grave, .entrega, "Proyectos fuera de fecha", "Un plazo pasado sin renegociar es una promesa rota en silencio",
              "Replantear la fecha con el cliente hoy, no cuando pregunte", fueraDeFecha.map { pr in
                  .init(ruta: pr.ruta, detalle: "\(pr.nombre) · \(dias(RangoFechas.diasEntre(pr.fin!, hoy)))")
              }),
            r("ENT-07", .flojo, .entrega, "Proyectos de cliente sin oportunidad detrás", "Un proyecto de cliente nace de una oportunidad ganada",
              "Ligarlo a su oportunidad, o marcarlo como interno", entregaSinOportunidad.map { .init(ruta: $0.ruta, detalle: $0.nombre) }),
            r("FIN-01", .grave, .finanzas, "Facturas vencidas sin cobrar", "El dinero cobrado tarde es dinero que financias tú",
              "Reclamar hoy, con número y fecha", facturasVencidas.map { f in
                  .init(ruta: f.ficha, detalle: "\(f.tercero) · \(f.numero) · \(FormatoBase.euros(evaluador.pendiente(f) ?? 0))")
              }),
            r("FIN-06", .flojo, .finanzas, "Movimientos sin clasificar", "Sin clasificar, el trimestre sale mal y no hay forma de saberlo",
              "Clasificarlos antes del cierre del trimestre", sinClasificar.map { .init(ruta: nil, detalle: $0.concepto) }),
            r("ORG-01", .flojo, nil, "Tareas planificadas en fin de semana", "La fecha planificada nunca cae en sábado ni domingo",
              "Pasarlas al lunes: el vencimiento sí puede caer donde quiera", enFinde.map { caso($0) }),
            r("ORG-02", .grave, nil, "Tareas atrasadas arrastrando", "Una tarea que lleva días sin moverse ya no está planificada: está aparcada",
              "Replanificarla con fecha real o descartarla", arrastrando.map { t in
                  caso(t, dias(RangoFechas.diasEntre(t.tarea.planificada!, hoy)))
              }),
            r("EQU-01", .flojo, .equipo, "Áreas sin dueño distinto de ti", "Un área sin dueño propio no está delegada, está esperándote",
              "Ficha de rol y quién la ocupa. Es el salto de la etapa 5", sinDueno.map { a in
                  .init(ruta: foto.layout.areaFolder(a).appending(AreaReader.fileName), detalle: "\(a.numero) · \(a.nombre)")
              }),
            r("DIR-09", .flojo, .direccion, "Números sin umbral fijado", "Un número sin umbral se mira, no vigila",
              "Fijarlo con tu propio histórico, nunca copiado", sinUmbral.map { .init(ruta: metas?.ruta, detalle: "\($0.codigo) · \($0.indicador)") }),
        ]
    }
}
