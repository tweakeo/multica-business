// Procedencia: port reescrito de Programa v0.5 (Manu): core/lecturas.js (la lectura de un área sin modelo: un
// titular, un análisis corto y UNA recomendación de esta semana, con la firma de los datos con que se escribió) y
// core/areas.js (los periodos hoy · semana · mes · trimestre · todo y los números de «Análisis» de cada área).
// En F2 no hay asistente: todo es determinista. Ver docs/PROCEDENCIA.md.
import Foundation

/// Lo que diría el consultor de un área, escrito con reglas (sin asistente).
public struct LecturaArea: Sendable, Hashable {
    public let area: AreaCode
    /// Menos de ocho palabras: lo que le pasa al área.
    public let titular: String
    /// Tres o cuatro frases.
    public let texto: String
    /// Una sola recomendación, de esta semana.
    public let recomendacion: String
    /// El estado de los datos con que se escribió: si cambia, la lectura está vieja.
    public let firma: String

    /// La lectura de un área con lo que ya calculó el panel.
    public static func de(_ a: AreaCode, panel p: PanelMetricas) -> LecturaArea {
        let e = p.etapa(a)
        let salud = p.salud(a)
        let rotas = salud.filter { $0.estado == .mal }
        let flojas = salud.filter { $0.estado == .atencion }
        let presion = p.mapa.presiones.first { $0.area == a }
        let esCuello = p.mapa.cuello?.area == a
        let ritmo = p.ritmo(a)?.pct
        let cobertura = e?.cobertura ?? 0
        let manuales = e?.manuales ?? 0
        let dueno = e?.tieneDueno ?? false
        let sistemas = e?.sistemas ?? []
        let foco = sistemas.first { $0.haceFalta && $0.estado != .montado }
        let montados = sistemas.filter { $0.estado == .montado }.count
        let faltan = sistemas.filter { $0.estado == .falta }.count

        let titular: String
        if esCuello { titular = "Es el cuello de botella de la empresa" }
        else if !rotas.isEmpty { titular = rotas.count == 1 ? "Una señal mal en el área" : "\(rotas.count) señales mal en el área" }
        else if cobertura < 100 { titular = "Le falta encender lo esencial" }
        else if let f = foco { titular = "Le falta \(f.sistema.nombre.lowercased())" }
        else if manuales > 2 { titular = "Demasiado trabajo todavía a mano" }
        else if !dueno { titular = "Sin dueño distinto de ti" }
        else { titular = "En su sitio: mantener y vigilar el número" }

        var frases: [String] = []
        let etapa = e?.etapa ?? 1
        frases.append("\(a.nombre) está en la etapa \(etapa) de \(EtapaCalculador.objetivo)"
            + (cobertura < 100 ? ", con el \(cobertura) % de lo esencial encendido." : ", con lo esencial completo y el \(e?.pctAuto ?? 0) % funcionando sin ti."))
        if !sistemas.isEmpty {
            var s = "De los \(sistemas.count) sistemas que necesita, \(montados == 1 ? "1 está montado" : "\(montados) están montados")"
            s += faltan == 0 ? "." : faltan == 1 ? " y 1 no existe todavía." : " y \(faltan) no existen todavía."
            frases.append(s)
        }
        if !rotas.isEmpty {
            frases.append("Lo que está mal ahora: \(rotas.map { $0.detalle ?? $0.dimension.etiqueta.lowercased() }.joined(separator: "; ")).")
        } else if !flojas.isEmpty {
            frases.append("Lo que pide atención: \(flojas.map { $0.detalle ?? $0.dimension.etiqueta.lowercased() }.joined(separator: "; ")).")
        }
        if let r = ritmo, r < 80 { frases.append("Y va al \(r) % del ritmo que necesitaría para llegar a su meta.") }
        if esCuello, let m = presion?.motivo { frases.append("Es además lo que más frena al resto: \(m).") }

        let recomendacion: String
        if let r = rotas.first {
            recomendacion = "Arreglar primero lo que está mal: \(r.detalle ?? r.dimension.etiqueta.lowercased()). Lo demás puede esperar una semana."
        } else if cobertura < 100 {
            recomendacion = "Encender las funciones esenciales que faltan. Construir encima de lo que no está es cómo se pierden los meses."
        } else if let f = foco {
            recomendacion = "Montar «\(f.sistema.nombre)». La pregunta que hoy nadie contesta en esta área es: \(f.sistema.pregunta)"
        } else if manuales > 2 {
            recomendacion = "Bajar de escalón una de las \(manuales) cosas que aún haces a mano: elige la que repitas igual más veces."
        } else if !dueno {
            recomendacion = "Escribir la ficha de rol y buscar dueño. Un área sin dueño distinto de ti no está delegada, está esperándote."
        } else {
            recomendacion = "Nada urgente. Mantener la rutina y vigilar el número del área."
        }

        let firma = [String(etapa), String(cobertura), String(e?.pctAuto ?? -1), String(manuales), String(dueno), String(esCuello),
                     String(ritmo ?? -1), String(montados), String(faltan), String(salud.filter { $0.estado != .bien }.count)]
            .joined(separator: "|")
        return LecturaArea(area: a, titular: titular, texto: frases.joined(separator: " "), recomendacion: recomendacion, firma: firma)
    }
}

/// Periodos de los números de un área (areas.js).
public enum PeriodoArea: String, Sendable, Hashable, CaseIterable {
    case hoy, semana, mes, trimestre, todo

    public var etiqueta: String {
        switch self {
        case .hoy: "Hoy"
        case .semana: "Esta semana"
        case .mes: "Este mes"
        case .trimestre: "Este trimestre"
        case .todo: "Todo"
        }
    }

    /// El rango a día `hoy` (semana de lunes a domingo; «todo», desde el año 2000).
    public func rango(hoy: LocalDate) -> RangoFechas {
        switch self {
        case .hoy: RangoFechas(desde: hoy, hasta: hoy)
        case .semana: RangoFechas(desde: FormatoBase.lunes(de: hoy), hasta: FormatoBase.lunes(de: hoy).adding(days: 6))
        case .mes: RangoFechas.mes(de: hoy)
        case .trimestre: RangoFechas.trimestre(de: hoy)
        case .todo: RangoFechas(desde: LocalDate(year: 2000, month: 1, day: 1)!, hasta: LocalDate(year: 2100, month: 1, day: 1)!)
        }
    }
}

/// Una cifra del «Análisis» de un área, con su pie («870 € en juego»).
public struct CifraArea: Sendable, Hashable, Identifiable {
    public var id: String { nombre }
    public let nombre: String
    public let medida: MedidaKPI
    public let unidad: String
    public let pie: String?

    public var textoValor: String {
        guard let n = medida.numero else { return "Sin dato" }
        return KPIEvaluador.formatear(n, unidad: unidad)
    }
}

/// Los números de «Análisis» de cada área en un periodo (areas.js), con lo que ya calculó el panel.
public enum AnalisisArea {
    public static func cifras(_ a: AreaCode, periodo: PeriodoArea, panel p: PanelMetricas) -> [CifraArea] {
        let f = p.foto, hoy = p.hoy, ev = p.evaluador
        let r = periodo.rango(hoy: hoy)
        func dentro(_ d: LocalDate?) -> Bool { d.map { r.contiene($0) && $0 <= hoy } ?? false }
        func cuantas(_ n: Int, _ una: String, _ varias: String) -> String { n == 1 ? "1 \(una)" : "\(n) \(varias)" }
        func euros(_ n: Double) -> String { KPIEvaluador.formatear(n, unidad: "€") }
        switch a {
        case .ventas:
            let ops = f.oportunidades.filter { $0.creada.map { $0 <= hoy } ?? true }
            guard !ops.isEmpty else { return [CifraArea(nombre: "Oportunidades abiertas", medida: .sinDato("Aún no hay oportunidades"), unidad: "n", pie: nil)] }
            let abiertas = ops.filter(\.abierta)
            let ganadas = ops.filter { $0.estado == .ganada && dentro($0.cerrada) }
            let perdidas = ops.filter { $0.estado == .perdida && dentro($0.cerrada ?? $0.creada) }
            let cerradas = ganadas.count + perdidas.count
            return [
                CifraArea(nombre: "Oportunidades abiertas", medida: .cifra(Double(abiertas.count)), unidad: "n",
                          pie: "\(euros(abiertas.compactMap(\.valor).reduce(0, +))) en juego"),
                CifraArea(nombre: "Ganadas en el periodo", medida: .cifra(Double(ganadas.count)), unidad: "n",
                          pie: "\(euros(ganadas.compactMap(\.valor).reduce(0, +))) cerrados"),
                CifraArea(nombre: "Perdidas en el periodo", medida: .cifra(Double(perdidas.count)), unidad: "n", pie: nil),
                CifraArea(nombre: "Cierre", medida: cerradas == 0 ? .sinDato("Ninguna cerrada en el periodo")
                          : .cifra((100 * Double(ganadas.count) / Double(cerradas)).rounded()), unidad: "%", pie: "de las cerradas"),
            ]
        case .entrega:
            let entregados = f.proyectos.filter { $0.estado == .cerrado && dentro($0.fin) }
            let tarde = f.proyectos.filter { ($0.estado?.abierto ?? true) && ($0.fin.map { $0 < hoy } ?? false) }
            let ent = f.tareas.filter { $0.abierta && $0.tarea.area == .entrega }
            return [
                CifraArea(nombre: "Entregados en el periodo", medida: f.proyectos.isEmpty ? .sinDato("Aún no hay fichas de proyecto") : .cifra(Double(entregados.count)), unidad: "n", pie: nil),
                CifraArea(nombre: "Fuera de fecha", medida: f.proyectos.isEmpty ? .sinDato("Aún no hay fichas de proyecto") : .cifra(Double(tarde.count)), unidad: "n", pie: nil),
                CifraArea(nombre: "Horas comprometidas", medida: ent.contains { $0.estimacionH != nil } ? .cifra(ent.compactMap(\.estimacionH).reduce(0, +)) : .sinDato("Sin tareas de Entrega estimadas"),
                          unidad: "h", pie: "sin cerrar"),
            ]
        case .finanzas:
            let caja = ev.evaluar("FIN-CASH"), runway = ev.evaluar("FIN-RUNWAY")
            let pendientes = f.facturas.filter { ($0.fecha.map { $0 <= hoy } ?? true) && (ev.pendiente($0) ?? 0) > 0 }
            let pagos = f.registros.pagos
            func suma(_ dir: String) -> MedidaKPI {
                guard pagos else { return .sinDato("Falta el registro de cobros y pagos") }
                return .cifra(KPIEvaluador.redondear(f.pagos.filter { $0.confirmado && $0.direccion == dir && dentro($0.fecha) }.compactMap(\.importe).reduce(0, +), 2))
            }
            return [
                CifraArea(nombre: "Caja hoy", medida: caja.medida, unidad: "€", pie: "lo que hay en el banco ahora"),
                CifraArea(nombre: "Cobros pendientes", medida: f.registros.emitidas && pagos
                          ? .cifra(KPIEvaluador.redondear(pendientes.compactMap { ev.pendiente($0) }.reduce(0, +), 2)) : .sinDato("Faltan las facturas emitidas o los cobros"),
                          unidad: "€", pie: cuantas(pendientes.count, "factura sin cobrar", "facturas sin cobrar")),
                CifraArea(nombre: "Cobrado en el periodo", medida: suma("cobro"), unidad: "€", pie: "cobrado, no facturado"),
                CifraArea(nombre: "Pagado en el periodo", medida: suma("pago"), unidad: "€", pie: nil),
                CifraArea(nombre: "Meses de caja", medida: runway.medida, unidad: "meses", pie: "caja entre la salida de cada mes"),
            ]
        case .marca:
            let conv = f.conversaciones.filter { dentro($0.fecha) }
            return [
                CifraArea(nombre: "Conversaciones cualificadas", medida: f.conversaciones.isEmpty ? .sinDato("Aún no hay conversaciones") : .cifra(Double(conv.filter(\.cualificada).count)),
                          unidad: "n", pie: "de \(conv.count) en el periodo"),
                CifraArea(nombre: "Piezas publicadas", medida: f.contenidos.isEmpty ? .sinDato("Aún no hay contenidos") : .cifra(Double(f.contenidos.filter { $0.esPublicado && dentro($0.publicado) }.count)),
                          unidad: "n", pie: nil),
            ]
        case .equipo:
            let promovibles = TarjetaBuilder(evaluador: ev, objetivos: [], presiones: []).promovibles().count
            return [
                CifraArea(nombre: "Áreas con dueño distinto de ti", medida: f.rolesDicenOcupante ? .cifra(Double(AreaCode.allCases.filter { f.tieneDueno($0) }.count)) : .sinDato("Ningún rol dice quién lo ocupa"),
                          unidad: "n", pie: nil),
                CifraArea(nombre: "Asistentes con rol", medida: f.roles.isEmpty ? .sinDato("Aún no hay fichas de rol") : .cifra(Double(f.roles.filter { !$0.esHumano }.count)),
                          unidad: "n", pie: nil),
                CifraArea(nombre: "Funciones listas para bajar de escalón", medida: .cifra(Double(promovibles)), unidad: "n", pie: nil),
            ]
        case .direccion:
            let decisiones = decisionesRegistradas(f, rango: r)
            return [
                CifraArea(nombre: "Ritmo global", medida: p.ritmoEmpresa.pct.map { .cifra(Double($0)) } ?? .sinDato("Ningún objetivo tiene dato"), unidad: "%", pie: nil),
                CifraArea(nombre: "Objetivos en riesgo", medida: f.objetivos.isEmpty ? .sinDato("Aún no hay objetivos") : .cifra(Double(p.ritmoEmpresa.enRiesgo)), unidad: "n", pie: nil),
                CifraArea(nombre: "Decisiones registradas", medida: decisiones.map { .cifra(Double($0)) } ?? .sinDato("Aún no hay registro de decisiones"), unidad: "n", pie: nil),
                CifraArea(nombre: "Números con umbral fijado", medida: p.metas.map { m in .cifra(Double(m.filas.filter { $0.meta.fijado }.count)) } ?? .sinDato("Aún no hay Metas"),
                          unidad: "n", pie: p.metas.map { "de \($0.filas.count)" }),
            ]
        }
    }

    /// Líneas de `1 · Dirección/Decisiones.md` (`- AAAA-MM-DD · …`) con fecha en el rango, sin las sustituidas.
    /// `nil` si no hay registro.
    static func decisionesRegistradas(_ f: FotoMetricas, rango r: RangoFechas) -> Int? {
        f.decisiones.map { $0.filter { r.contiene($0) && $0 <= f.hoy }.count }
    }
}
