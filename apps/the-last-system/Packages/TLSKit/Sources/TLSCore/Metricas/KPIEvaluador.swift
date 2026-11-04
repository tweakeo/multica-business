// Procedencia: el ritmo de cada número dentro de su propio periodo es un port reescrito de Programa v0.5 (Manu),
// core/sql/08-metricas.sql (`metrica_valor`, `ritmo_objetivos`). Las fórmulas de cada código salen de la sección
// «Cómo se mide» de Metas.md (hechos, ver Recursos/Programa/kpi.json). Ver docs/PROCEDENCIA.md.
import Foundation

/// El valor de un número: una cifra o «Sin dato» con su motivo. Nunca un 0 inventado.
public enum MedidaKPI: Sendable, Hashable {
    case cifra(Double)
    case sinDato(String)

    public var numero: Double? {
        if case .cifra(let n) = self { return n }
        return nil
    }

    public var motivoSinDato: String? {
        if case .sinDato(let m) = self { return m }
        return nil
    }
}

/// Cómo está un número frente a su meta y su alerta.
public enum EstadoKPI: String, Sendable, Hashable, CaseIterable {
    case bien, atencion, mal, sinMeta, sinDato

    public var etiqueta: String {
        switch self {
        case .bien: "Bien"
        case .atencion: "Atención"
        case .mal: "Mal"
        case .sinMeta: "Sin meta"
        case .sinDato: "Sin dato"
        }
    }
}

/// Ritmo: si al paso que vas llegas a la meta (Programa: ahead, on track, attention, at risk, critical).
public enum EstadoRitmo: String, Sendable, Hashable, CaseIterable {
    case adelantado, enRitmo, atencion, enRiesgo, critico, sinDato, sinMeta

    public var etiqueta: String {
        switch self {
        case .adelantado: "Adelantado"
        case .enRitmo: "En ritmo"
        case .atencion: "Atención"
        case .enRiesgo: "En riesgo"
        case .critico: "Crítico"
        case .sinDato: "Sin dato"
        case .sinMeta: "Sin meta"
        }
    }

    /// Cuánto se ha quedado atrás (para elegir el «más atrasado»). Sin dato o sin meta no cuentan.
    public var retraso: Int {
        switch self {
        case .adelantado: 1
        case .enRitmo: 2
        case .atencion: 3
        case .enRiesgo: 4
        case .critico: 5
        case .sinDato, .sinMeta: 0
        }
    }

    /// Se puede juzgar (ni sin dato ni sin meta).
    public var medible: Bool { retraso > 0 }

    /// En trayectoria (adelantado o en ritmo).
    public var enTrayectoria: Bool { self == .adelantado || self == .enRitmo }

    /// Umbrales de Programa (08-metricas): real frente a lo esperado a estas alturas.
    public static func desde(real: Double, esperado: Double, meta: Double) -> EstadoRitmo {
        if esperado <= 0 { return .enRitmo }
        if real >= meta { return .adelantado }
        if real >= esperado * 1.05 { return .adelantado }
        if real >= esperado * 0.95 { return .enRitmo }
        if real >= esperado * 0.80 { return .atencion }
        if real >= esperado * 0.55 { return .enRiesgo }
        return .critico
    }
}

/// El ritmo de un número.
public struct RitmoKPI: Sendable, Hashable {
    public let estado: EstadoRitmo
    /// Real / esperado, en %, para los que se suman a lo largo del periodo.
    public let pct: Int?
    /// Lo esperado a día de hoy.
    public let esperado: Double?
}

/// Un número clave evaluado: valor, meta, alerta, estado, ritmo y de dónde sale (la fila de Control).
public struct ValorKPI: Sendable, Hashable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    public let indicador: String
    public let area: AreaCode?
    public let unidad: String
    public let sentido: SentidoKPI
    public let periodo: PeriodoKPI
    public let rango: RangoFechas
    public let medida: MedidaKPI
    public let meta: Umbral
    public let alerta: Umbral
    public let estado: EstadoKPI
    public let ritmo: RitmoKPI
    /// «Sale de 14 oportunidades».
    public let fuente: String
    public let calculo: String
    /// Está en la tabla de `Metas.md`.
    public let enMetas: Bool

    /// «70 %», «325,50 €», «7,9 meses», «Sin dato».
    public var textoValor: String {
        guard let n = medida.numero else { return "Sin dato" }
        return KPIEvaluador.formatear(n, unidad: unidad)
    }

    /// La meta tal como está escrita, o «Sin meta».
    public var textoMeta: String { meta.vacioDeTexto ? "Sin meta" : meta.textoVisible }
    public var textoAlerta: String { alerta.vacioDeTexto ? "Sin alerta" : alerta.textoVisible }
    public var metaFijada: Bool { meta.fijado }
}

/// Calcula cada número clave desde las fichas y los CSV de la carpeta (PLAN §6.5 «Control»).
///
/// - Sin la fuente de un número, «Sin dato» con el motivo; sin meta, «Sin meta». Nunca un 0 de relleno.
/// - Cada número se mide en su periodo (mes, trimestre, 30 o 90 días) y, para un objetivo, en el del objetivo.
/// - Lo que pasa después de `hoy` (el reloj inyectado) no cuenta.
public struct KPIEvaluador: Sendable {
    public let foto: FotoMetricas
    public let catalogo: CatalogoPrograma
    public let metas: MetasDocumento?

    public init(foto: FotoMetricas, catalogo: CatalogoPrograma = .deSerie, metas: MetasDocumento?) {
        self.foto = foto; self.catalogo = catalogo; self.metas = metas
    }

    public var hoy: LocalDate { foto.hoy }

    // MARK: Evaluar

    /// Los números de la tabla de `Metas.md`, en su orden. Sin `Metas.md`, los del catálogo que vienen de Ribera.
    public func todos() -> [ValorKPI] {
        if let metas, !metas.filas.isEmpty { return metas.filas.map { evaluar($0.codigo) } }
        return catalogo.kpis.filter { $0.origen == "ribera" }.map { evaluar($0.codigo) }
    }

    public func delArea(_ a: AreaCode) -> [ValorKPI] { todos().filter { $0.area == a } }

    public func evaluar(_ codigo: String) -> ValorKPI {
        let def = catalogo.kpi(codigo)
        let fila = metas?.fila(codigo)
        let como = metas?.comoSeMide[codigo.uppercased()]
        let unidad = def?.unidad ?? Self.unidad(deUmbral: fila?.meta.texto ?? fila?.alerta.texto ?? "")
        let sentido = como?.sentido ?? def?.sentido ?? .mas
        let periodo = def?.periodo ?? .ahora
        let rango = periodo.rango(hoy: hoy)
        let (medida, fuente) = medir(codigo, rango: rango)
        let meta = fila?.meta ?? .vacio
        let alerta = fila?.alerta ?? .vacio
        let estado = Self.estado(medida, meta: meta, alerta: alerta, sentido: sentido)
        let ritmo = Self.ritmo(medida, estado: estado, meta: meta, sentido: sentido, periodo: periodo,
                               acumulable: def?.acumulable ?? false, hoy: hoy)
        return ValorKPI(codigo: fila?.codigo ?? def?.codigo ?? codigo, indicador: fila?.indicador.nilSiVacio ?? def?.indicador ?? codigo,
                        area: def?.area ?? Self.area(deCodigo: codigo), unidad: unidad, sentido: sentido, periodo: periodo,
                        rango: rango, medida: medida, meta: meta, alerta: alerta, estado: estado, ritmo: ritmo, fuente: fuente,
                        calculo: como?.calculo.nilSiVacio ?? def?.calculo ?? "", enMetas: fila != nil)
    }

    /// Estado frente a meta y alerta. Llegar a la alerta ya es alerta; llegar a la meta ya es meta.
    public static func estado(_ medida: MedidaKPI, meta: Umbral, alerta: Umbral, sentido: SentidoKPI) -> EstadoKPI {
        guard let v = medida.numero else { return .sinDato }
        let m = meta.numero, a = alerta.numero
        switch sentido {
        case .mas:
            if let a, v <= a { return .mal }
            guard let m else { return .sinMeta }
            return v >= m ? .bien : .atencion
        case .menos:
            if let a, v >= a { return .mal }
            guard let m else { return .sinMeta }
            return v <= m ? .bien : .atencion
        case .rango:
            guard let m else { return .sinMeta }
            let maximo = meta.maximo ?? m
            if v >= m && v <= maximo { return .bien }
            if let a, (v <= a && a < m) || (v >= a && a > maximo) { return .mal }
            return .atencion
        }
    }

    /// Ritmo de un número: los que se suman en el periodo, frente a la parte del periodo que ya pasó; los de nivel,
    /// por su estado.
    static func ritmo(_ medida: MedidaKPI, estado: EstadoKPI, meta: Umbral, sentido: SentidoKPI, periodo: PeriodoKPI,
                      acumulable: Bool, hoy: LocalDate) -> RitmoKPI {
        guard let v = medida.numero else { return RitmoKPI(estado: .sinDato, pct: nil, esperado: nil) }
        guard let m = meta.numero else { return RitmoKPI(estado: .sinMeta, pct: nil, esperado: nil) }
        if acumulable, periodo == .mes || periodo == .trimestre {
            let completo = periodo == .mes ? RangoFechas.mes(de: hoy) : RangoFechas.trimestre(de: hoy)
            let pasados = RangoFechas.diasEntre(completo.desde, hoy) + 1
            let esperado = (m * Double(pasados) / Double(completo.dias) * 100).rounded() / 100
            switch sentido {
            case .menos:
                // Gastar menos de lo que toca a estas alturas es ir en ritmo.
                let pct = v > 0 ? Int((100 * esperado / v).rounded()) : nil
                let e: EstadoRitmo = v <= esperado ? .enRitmo : (v <= m ? .atencion : .critico)
                return RitmoKPI(estado: e, pct: pct, esperado: esperado)
            default:
                let pct = esperado > 0 ? Int((100 * v / esperado).rounded()) : nil
                return RitmoKPI(estado: EstadoRitmo.desde(real: v, esperado: esperado, meta: m), pct: pct, esperado: esperado)
            }
        }
        let e: EstadoRitmo = switch estado {
        case .bien: .enRitmo
        case .atencion: .atencion
        case .mal: .critico
        case .sinMeta: .sinMeta
        case .sinDato: .sinDato
        }
        return RitmoKPI(estado: e, pct: nil, esperado: nil)
    }

    // MARK: Medir

    /// El valor de un código en un rango (por defecto, el de su periodo) y de dónde sale.
    public func medir(_ codigo: String, rango: RangoFechas? = nil) -> (MedidaKPI, String) {
        let c = codigo.uppercased()
        let r = rango ?? (catalogo.kpi(c)?.periodo ?? .ahora).rango(hoy: hoy)
        let f = foto
        // Lo que todavía no existía a día de hoy (fichas creadas después) no cuenta.
        let ops = f.oportunidades.filter { $0.creada.map { $0 <= hoy } ?? true }
        let tareas = f.tareas.filter { $0.tarea.creada.map { $0 <= hoy } ?? true }
        func abierta(_ t: FotoMetricas.TareaMedida) -> Bool {
            guard let e = t.tarea.estado, e.cerrada else { return true }
            // Cerrada después de hoy: a día de hoy seguía abierta.
            if let c = t.cerradaEn, c > hoy { return true }
            return false
        }
        func cuenta(_ n: Int, _ cosa: String, _ cosas: String) -> String { n == 1 ? "1 \(cosa)" : "\(n) \(cosas)" }

        switch c {
        case "DIR-APR":
            guard !tareas.isEmpty || !f.borradores.isEmpty else { return (.sinDato("Aún no hay tareas ni borradores"), "Sin fuente") }
            let b = f.borradores.filter(\.pendiente).count
            let t = tareas.filter { abierta($0) && $0.tarea.estado == .enRevision && !$0.esDecision }.count
            let fuentes = [tareas.isEmpty ? nil : cuenta(tareas.count, "tarea", "tareas"),
                           f.borradores.isEmpty ? nil : cuenta(f.borradores.count, "borrador", "borradores")].compactMap { $0 }
            return (.cifra(Double(b + t)), "Sale de \(fuentes.joined(separator: " y "))")

        case "DIR-DEC", "DIR-DEC14":
            guard !tareas.isEmpty else { return (.sinDato("Aún no hay fichas de tarea"), "Sin fuente") }
            var dec = tareas.filter { abierta($0) && $0.esDecision }
            if c == "DIR-DEC14" {
                dec = dec.filter { t in t.tarea.creada.map { RangoFechas.diasEntre($0, hoy) >= 14 } ?? false }
            }
            return (.cifra(Double(dec.count)), "Sale de \(cuenta(tareas.count, "tarea", "tareas"))")

        case "DIR-OBJ":
            let ritmo = RitmoCalculador(evaluador: self)
            let medibles = ritmo.objetivos(excepto: "DIR-OBJ").filter { $0.estado.medible }
            guard !medibles.isEmpty else {
                return (.sinDato("Ningún objetivo en curso tiene número y dato"), "Sale de \(cuenta(f.objetivos.count, "objetivo", "objetivos"))")
            }
            let bien = medibles.filter { $0.estado.enTrayectoria }.count
            return (.cifra(Self.redondear(100 * Double(bien) / Double(medibles.count), 1)),
                    "Sale de \(cuenta(medibles.count, "objetivo con dato", "objetivos con dato"))")

        case "ENT-ACTIVE":
            guard !f.proyectos.isEmpty else { return (.sinDato("Aún no hay fichas de proyecto"), "Sin fuente") }
            let n = f.proyectos.filter { ($0.esDeEntrega || $0.area == .entrega) && $0.estado == .enCurso }.count
            return (.cifra(Double(n)), "Sale de \(cuenta(f.proyectos.count, "proyecto", "proyectos"))")

        case "ENT-ONTIME":
            let ent = tareas.filter { $0.tarea.area == .entrega }
            guard !ent.isEmpty else { return (.sinDato("Aún no hay tareas en 3 · Entrega"), "Sin fuente") }
            // El día de cierre: `cerrada` o, si se cerró en el tablero (que solo cambia `estado`), el de su Actividad.
            let cerradas = ent.filter { t in
                t.tarea.estado == .hecha && t.tarea.vence != nil && t.cerradaEn.map { r.contiene($0) } ?? false
            }
            guard !cerradas.isEmpty else {
                return (.sinDato("Ninguna tarea de Entrega se cerró con vencimiento en \(PeriodoKPI.dias30.etiqueta)"),
                        "Sale de \(cuenta(ent.count, "tarea de Entrega", "tareas de Entrega"))")
            }
            let aTiempo = cerradas.filter { t in t.cerradaEn.flatMap { c in t.tarea.vence.map { c <= $0 } } ?? false }.count
            return (.cifra(Self.redondear(100 * Double(aTiempo) / Double(cerradas.count), 1)),
                    "Sale de \(cuenta(cerradas.count, "tarea cerrada", "tareas cerradas"))")

        case "ENT-INC":
            // Integración F2: lo mismo que cuenta la Operación de Entrega con su cuenta atrás (24/48/72 h hábiles).
            guard !f.incidencias.isEmpty else {
                return (.sinDato("Ningún expediente tiene aún registro de incidencias"), "Saldrá de los registros de incidencias")
            }
            let zona = TimeZone(identifier: f.config.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
            // La hora del reloj inyectado (determinista); sin él, la de la máquina.
            let ahora = Self.ahora(hoy: hoy, zona: zona, reloj: f.ahora ?? Date())
            let n = f.incidencias.reduce(0) { $0 + $1.fueraDePlazo(ahora: ahora, zona: zona).count }
            return (.cifra(Double(n)), "Sale de \(cuenta(f.incidencias.count, "registro de incidencias", "registros de incidencias"))")

        case "ENT-OVERDUE":
            let ent = tareas.filter { $0.tarea.area == .entrega }
            guard !ent.isEmpty else { return (.sinDato("Aún no hay tareas en 3 · Entrega"), "Sin fuente") }
            let n = ent.filter { t in abierta(t) && t.tarea.vence.map { $0 < hoy } ?? false }.count
            return (.cifra(Double(n)), "Sale de \(cuenta(ent.count, "tarea de Entrega", "tareas de Entrega"))")

        case "EQU-COST":
            guard f.registros.bitacora else { return (.sinDato("Aún no hay bitácora de los asistentes"), "Sin fuente") }
            let suma = f.usos.filter { r.contiene($0.fecha) }.map(\.usd).reduce(0, +)
            return (.cifra(Self.redondear(suma, 2)), "Sale de la bitácora de los asistentes")

        case "EQU-ROLES":
            // Los roles de las personas: las fichas de los asistentes (`clase: agente`) siempre dicen su ocupante y se
            // cuentan aparte («Asistentes con rol»), como «Áreas con dueño distinto de ti» (F4).
            let roles = f.roles.filter(\.esHumano)
            guard !roles.isEmpty else { return (.sinDato("Aún no hay fichas de rol"), "Sin fuente") }
            guard f.rolesDicenOcupante else {
                return (.sinDato("Ningún rol dice quién lo ocupa: escríbelo en «ocupante»"), "Sale de \(cuenta(roles.count, "rol", "roles"))")
            }
            let con = roles.filter { !($0.ocupante ?? "").isEmpty }.count
            return (.cifra(Self.redondear(100 * Double(con) / Double(roles.count), 1)), "Sale de \(cuenta(roles.count, "rol", "roles"))")

        case "FIN-AR":
            guard f.registros.emitidas else { return (.sinDato("Falta el registro de facturas emitidas"), "Sin fuente") }
            guard f.registros.pagos else { return (.sinDato("Falta el registro de cobros y pagos"), "Sin fuente") }
            let emitidas = f.facturas.filter { $0.fecha.map { $0 <= hoy } ?? true }
            guard !emitidas.isEmpty else { return (.sinDato("No hay facturas emitidas"), "Sale de emitidas.csv") }
            var total = 0.0
            for fa in emitidas {
                guard let pendiente = pendiente(fa), pendiente > 0, let v = fa.vence, v < hoy else { continue }
                total += pendiente
            }
            return (.cifra(Self.redondear(total, 2)), "Sale de \(cuenta(emitidas.count, "factura emitida", "facturas emitidas")) y sus cobros")

        case "FIN-CASH":
            let caja = cajaDisponible()
            guard let v = caja.total else { return (.sinDato(caja.motivo), caja.fuente) }
            return (.cifra(v), caja.fuente)

        case "FIN-MARGIN":
            guard f.registros.emitidas, f.registros.recibidas else {
                return (.sinDato("Faltan los registros de facturas emitidas y recibidas"), "Sin fuente")
            }
            let ingresos = f.facturas.filter { $0.fecha.map { r.contiene($0) } ?? false }.compactMap { $0.base ?? $0.total }.reduce(0, +)
            let gastos = f.gastos.filter { $0.fecha.map { r.contiene($0) } ?? false }.compactMap { $0.base ?? $0.total }.reduce(0, +)
            guard ingresos > 0 else { return (.sinDato("Sin ingresos facturados \(PeriodoKPI.mes.etiqueta)"), "Sale de emitidas.csv y recibidas.csv") }
            return (.cifra(Self.redondear(100 * (ingresos - gastos) / ingresos, 1)),
                    "Sale de \(FormatoBase.euros(ingresos)) facturados y \(FormatoBase.euros(gastos)) de gastos")

        case "FIN-RUNWAY":
            let caja = cajaDisponible()
            guard let v = caja.total else { return (.sinDato(caja.motivo), caja.fuente) }
            guard let salida = salidaMensual() else {
                return (.sinDato("Hace falta al menos un mes entero de movimientos del banco"), "Sale de los movimientos del banco")
            }
            guard salida.media > 0 else { return (.sinDato("No sale dinero en los meses con movimientos"), "Sale de los movimientos del banco") }
            return (.cifra(Self.redondear(v / salida.media, 1)),
                    "Sale de la caja y de \(FormatoBase.euros(salida.media)) de salida al mes (media de \(cuenta(salida.meses, "mes", "meses")))")

        case "FIN-UNREC":
            let movs = f.cuentas.flatMap(\.movimientos).filter { $0.fecha.map { $0 <= hoy } ?? true }
            guard !movs.isEmpty else { return (.sinDato("No hay movimientos del banco importados"), "Sin fuente") }
            let n = movs.filter { !$0.resuelto }.count
            return (.cifra(Double(n)), "Sale de \(cuenta(movs.count, "movimiento", "movimientos")) del banco")

        case "MAR-PUB":
            guard !f.contenidos.isEmpty else { return (.sinDato("Aún no hay fichas de contenido"), "Sin fuente") }
            let n = f.contenidos.filter { $0.esPublicado && $0.evidencia != nil && $0.publicado.map { r.contiene($0) } ?? false }.count
            return (.cifra(Double(n)), "Sale de \(cuenta(f.contenidos.count, "contenido", "contenidos"))")

        case "MAR-QCONV":
            guard !f.conversaciones.isEmpty else { return (.sinDato("Aún no hay fichas de conversación"), "Sin fuente") }
            let n = f.conversaciones.filter { $0.cualificada && $0.fecha.map { r.contiene($0) } ?? false }.count
            return (.cifra(Double(n)), "Sale de \(cuenta(f.conversaciones.count, "conversación", "conversaciones"))")

        case "VEN-CONV":
            guard !ops.isEmpty else { return (.sinDato("Aún no hay oportunidades"), "Sin fuente") }
            let con = ops.filter { o in o.conPropuesta && (o.aceptada ?? o.cerrada ?? o.creada).map { r.contiene($0) } ?? false }
            guard !con.isEmpty else {
                return (.sinDato("Ninguna oportunidad recibió propuesta en \(PeriodoKPI.dias90.etiqueta)"), "Sale de \(cuenta(ops.count, "oportunidad", "oportunidades"))")
            }
            let si = con.filter { $0.estado == .aceptada || $0.estado == .ganada }.count
            return (.cifra(Self.redondear(100 * Double(si) / Double(con.count), 1)), "Sale de \(cuenta(con.count, "oportunidad con propuesta", "oportunidades con propuesta"))")

        case "VEN-FCST":
            guard !ops.isEmpty else { return (.sinDato("Aún no hay oportunidades"), "Sin fuente") }
            let abiertas = ops.filter(\.abierta)
            let con = abiertas.filter { $0.valor != nil && $0.probabilidad != nil }
            guard !con.isEmpty || abiertas.isEmpty else { return (.sinDato("Ninguna oportunidad abierta tiene valor y probabilidad"), "Sale de \(cuenta(abiertas.count, "oportunidad abierta", "oportunidades abiertas"))") }
            let suma = con.map { $0.valor! * $0.probabilidad! / 100 }.reduce(0, +)
            return (.cifra(Self.redondear(suma, 2)), "Sale de \(cuenta(abiertas.count, "oportunidad abierta", "oportunidades abiertas"))")

        case "VEN-PIPE":
            guard !ops.isEmpty else { return (.sinDato("Aún no hay oportunidades"), "Sin fuente") }
            let abiertas = ops.filter(\.abierta)
            let suma = abiertas.compactMap(\.valor).reduce(0, +)
            return (.cifra(Self.redondear(suma, 2)), "Sale de \(cuenta(abiertas.count, "oportunidad abierta", "oportunidades abiertas"))")

        case "VEN-STALE", "VEN-STALE7":
            guard !ops.isEmpty else { return (.sinDato("Aún no hay oportunidades"), "Sin fuente") }
            let abiertas = ops.filter(\.abierta)
            let n = abiertas.filter { o in
                guard let d = o.diasQuieta(hoy: hoy) else { return false }
                return c == "VEN-STALE" ? d > 14 : d >= 7
            }.count
            return (.cifra(Double(n)), "Sale de \(cuenta(abiertas.count, "oportunidad abierta", "oportunidades abiertas"))")

        case "VEN-WON":
            guard !ops.isEmpty else { return (.sinDato("Aún no hay oportunidades"), "Sin fuente") }
            // «Σ valor de oportunidades ganadas (cobro confirmado) en el mes» (Metas.md): cuenta el día del cobro
            // confirmado. Con VEN-07 es el mismo día que `cerrada`; si no se encuentra el cobro, vale `cerrada`.
            let ganadas = ops.filter { $0.estado == .ganada && ($0.cobrada ?? $0.cerrada).map { r.contiene($0) } ?? false }
            return (.cifra(Self.redondear(ganadas.compactMap(\.valor).reduce(0, +), 2)),
                    "Sale de \(cuenta(ganadas.count, "oportunidad ganada", "oportunidades ganadas")) en el periodo")

        default:
            if let def = catalogo.kpi(c), !def.calculable {
                return (.sinDato("Aún no hay de dónde sacarlo"), def.fuentes.first.map { "Saldrá de \($0)" } ?? "Sin fuente")
            }
            return (.sinDato("La app no sabe calcular este número"), "Sin fuente")
        }
    }

    /// El día de la carpeta con la hora de ahora (en el ejemplo, su día fijo; en una carpeta de verdad, ahora mismo).
    static func ahora(hoy: LocalDate, zona: TimeZone, reloj: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let h = cal.dateComponents([.hour, .minute], from: reloj)
        var c = DateComponents()
        c.year = hoy.year; c.month = hoy.month; c.day = hoy.day; c.hour = h.hour; c.minute = h.minute
        return cal.date(from: c) ?? reloj
    }

    // MARK: Caja

    /// Caja disponible a día de hoy: suma de los saldos conocidos.
    public struct Caja: Sendable, Hashable {
        public let total: Double?
        public let porCuenta: [SaldoCuenta]
        public let motivo: String
        public let fuente: String
    }

    public struct SaldoCuenta: Sendable, Hashable {
        public let cuenta: String
        public let ruta: VaultPath
        /// `nil`: desconocido.
        public let saldo: Double?
    }

    public func cajaDisponible() -> Caja {
        let cuentas = foto.cuentas
        guard !cuentas.isEmpty else {
            return Caja(total: nil, porCuenta: [], motivo: "Sin datos del banco: importa un extracto", fuente: "Sin fuente")
        }
        let saldos = cuentas.map { SaldoCuenta(cuenta: $0.nombre, ruta: $0.ruta, saldo: $0.saldo(a: hoy)) }
        let conocidos = saldos.compactMap(\.saldo)
        guard !conocidos.isEmpty else {
            return Caja(total: nil, porCuenta: saldos, motivo: "Sin datos del banco: importa un extracto o escribe el saldo inicial",
                        fuente: "Sale de \(cuentas.count == 1 ? "1 cuenta" : "\(cuentas.count) cuentas")")
        }
        // Con una cuenta sin saldo, la suma de las demás no es la caja: sin dato, diciendo cuál falta.
        let faltan = saldos.filter { $0.saldo == nil }.map(\.cuenta)
        let fuente = "Sale de \(cuentas.count == 1 ? "1 cuenta" : "\(cuentas.count) cuentas")"
        guard faltan.isEmpty else {
            return Caja(total: nil, porCuenta: saldos, motivo: "Falta el saldo de \(faltan.joined(separator: ", "))", fuente: fuente)
        }
        return Caja(total: Self.redondear(conocidos.reduce(0, +), 2), porCuenta: saldos, motivo: "", fuente: fuente)
    }

    /// Traspasos entre tus cuentas: los que lo dicen (`naturaleza: traspaso`) y los que casan con un movimiento
    /// contrario del mismo importe en otra cuenta tuya con 3 días de margen (uno con uno). No son salidas.
    public func traspasos() -> Set<String> {
        let movs = foto.cuentas.enumerated().flatMap { i, c in c.movimientos.map { (cuenta: i, mov: $0) } }
        var out = Set(movs.filter { $0.mov.esTraspaso }.map(\.mov.id))
        var usados = out
        for m in movs {
            guard let i = m.mov.importe, i < 0, let f = m.mov.fecha, !usados.contains(m.mov.id) else { continue }
            let centimos = Int((i * 100).rounded())
            if let o = movs.first(where: { o in
                guard o.cuenta != m.cuenta, !usados.contains(o.mov.id), let oi = o.mov.importe, let of = o.mov.fecha else { return false }
                return Int((oi * 100).rounded()) == -centimos && abs(RangoFechas.diasEntre(f, of)) <= 3
            }) {
                usados.insert(m.mov.id); usados.insert(o.mov.id)
                out.insert(m.mov.id); out.insert(o.mov.id)
            }
        }
        return out
    }

    /// Salida mensual media de los 3 últimos meses cerrados que los movimientos cubren enteros (sin traspasos entre
    /// tus cuentas). Un mes que el último extracto no cubre hasta el final no cuenta: con medio mes, la salida
    /// saldría más baja y los meses de caja, más altos de lo que son. `nil` si no hay ningún mes entero con datos.
    public func salidaMensual() -> (media: Double, meses: Int)? {
        let cuentas = foto.cuentas.filter { c in c.movimientos.contains { $0.fecha.map { $0 <= hoy } ?? false } }
        guard !cuentas.isEmpty else { return nil }
        // Desde cuándo hay datos (el día siguiente al saldo inicial o el primer movimiento) y hasta cuándo (el último).
        let inicios = cuentas.compactMap { c -> LocalDate? in
            if let f = c.fechaSaldoInicial { return f.adding(days: 1) }
            return c.movimientos.compactMap(\.fecha).min()
        }
        guard let desde = inicios.min(),
              let hasta = cuentas.flatMap(\.movimientos).compactMap(\.fecha).filter({ $0 <= hoy }).max() else { return nil }
        let traspasos = self.traspasos()
        var total = 0.0, meses = 0
        var mes = RangoFechas.mes(de: RangoFechas.mes(de: hoy).desde.adding(days: -1))
        while meses < 3, mes.desde >= desde {
            if mes.hasta <= hasta {
                total += cuentas.flatMap(\.movimientos).filter { m in
                    guard let f = m.fecha, let i = m.importe, i < 0, !traspasos.contains(m.id) else { return false }
                    return mes.contiene(f)
                }.compactMap(\.importe).map { -$0 }.reduce(0, +)
                meses += 1
            }
            mes = RangoFechas.mes(de: mes.desde.adding(days: -1))
        }
        guard meses > 0 else { return nil }
        return (Self.redondear(total / Double(meses), 2), meses)
    }

    /// Lo que falta por cobrar de una factura a día de hoy (cobros confirmados hasta hoy).
    public func pendiente(_ f: FotoMetricas.Factura) -> Double? {
        guard let total = f.total else { return nil }
        let cobrado = foto.pagos.filter { p in
            p.confirmado && p.direccion == "cobro" && p.documentoId?.uppercased() == f.id.uppercased() && (p.fecha.map { $0 <= hoy } ?? true)
        }.compactMap(\.importe).reduce(0, +)
        return max(0, Self.redondear(total - cobrado, 2))
    }

    // MARK: Formato

    public static func formatear(_ n: Double, unidad: String) -> String {
        switch unidad {
        case "%": return "\(FormatoBase.cifra(n.rounded())) %"
        case "€": return n == n.rounded() ? FormatoBase.euros(n, redondo: true) : FormatoBase.euros(n)
        case "meses": return "\(FormatoBase.cifra(n, decimales: 1)) \(n == 1 ? "mes" : "meses")"
        case "h": return "\(FormatoBase.cifra(n, decimales: n == n.rounded() ? 0 : 1)) h"
        case "USD": return "\(FormatoBase.cifra(n, decimales: 2)) USD"
        default: return FormatoBase.cifra(n)
        }
    }

    static func unidad(deUmbral texto: String) -> String {
        let t = TextFolding.fold(texto)
        if t.contains("%") { return "%" }
        if t.contains("€") { return "€" }
        if t.contains("mes") { return "meses" }
        return "n"
    }

    static func area(deCodigo c: String) -> AreaCode? {
        AreaCode(rawValue: String(c.uppercased().prefix(3)))
    }

    static func redondear(_ x: Double, _ decimales: Int) -> Double {
        let e = pow(10.0, Double(decimales))
        return (x * e).rounded() / e
    }
}
