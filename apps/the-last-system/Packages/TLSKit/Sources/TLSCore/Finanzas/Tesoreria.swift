import Foundation

/// De dónde sale el saldo de una cuenta (PLAN §4.6 · Saldo).
public enum FuenteSaldo: String, Sendable, Hashable {
    /// El último saldo que dio el banco en un extracto.
    case banco
    /// Saldo inicial de la ficha más los movimientos (o un saldo del banco más movimientos sin saldo): «Estimado».
    case estimado
    /// Ni saldo del banco ni saldo inicial: no se sabe.
    case desconocido
}

public struct SaldoCuenta: Sendable, Hashable {
    public let cuenta: CuentaBancaria
    /// Céntimos. `nil` = desconocido (nunca 0).
    public let saldo: Int?
    /// Fecha del último dato que lo sostiene.
    public let fecha: LocalDate?
    public let fuente: FuenteSaldo
}

/// Caja de la empresa: la suma de las cuentas.
public struct SaldoCaja: Sendable, Hashable {
    public let cuentas: [SaldoCuenta]
    /// `nil` si no hay cuentas o alguna tiene el saldo desconocido.
    public let total: Int?
    /// Suma de lo que sí se sabe.
    public let conocido: Int
    /// Alguna cifra no sale de un extracto: la interfaz pone «Estimado».
    public let estimado: Bool
    /// Fecha del dato más reciente.
    public let fecha: LocalDate?

    public var cuentasSinDato: [CuentaBancaria] { cuentas.filter { $0.saldo == nil }.map(\.cuenta) }
}

/// Meses que aguanta la caja: caja ÷ salidas medias de los últimos meses completos (Metas.md, FIN-RUNWAY:
/// «media 3 meses»). Los traspasos entre cuentas propias no cuentan como salida.
public struct Runway: Sendable, Hashable {
    /// Meses con un decimal. `nil` = «Sin dato» (con `motivo`).
    public let meses: Double?
    /// Salida media por mes (céntimos).
    public let salidaMedia: Int?
    /// Meses usados para la media (`2026-07`).
    public let mesesUsados: [String]
    public let estimado: Bool
    public let motivo: String?
}

/// Un punto de la gráfica de caja.
public struct PuntoCaja: Sendable, Hashable {
    public let fecha: LocalDate
    /// `nil` si ese día no se sabe (la gráfica se corta, no baja a 0).
    public let saldo: Int?
    public let estimado: Bool
    /// Ese día hay algún movimiento en alguna cuenta. Sin ninguno en un tramo, no se sabe si la caja cambió (falta el
    /// extracto): la variación del tramo es «Sin dato», nunca «no cambia» (revisión final de F2, regla 3).
    public var conMovimientos: Bool = false

    public init(fecha: LocalDate, saldo: Int?, estimado: Bool, conMovimientos: Bool = false) {
        self.fecha = fecha; self.saldo = saldo; self.estimado = estimado; self.conMovimientos = conMovimientos
    }

    /// ¿Hay algún movimiento después de `desde` y hasta `hasta` (incluido)? Si no, la variación entre los dos es
    /// «Sin dato».
    public static func hayMovimientos(_ puntos: [PuntoCaja], desde: LocalDate, hasta: LocalDate) -> Bool {
        puntos.contains { $0.conMovimientos && $0.fecha > desde && $0.fecha <= hasta }
    }
}

/// Periodos de la gráfica de caja (DISENO-MOSAICO-V2 §6 · Gráficas).
public enum RangoCaja: String, Sendable, Hashable, CaseIterable, Identifiable {
    case semana = "1S", mes = "1M", trimestre = "3M", anio = "1A", todo = "Todo"

    public var id: String { rawValue }

    /// Días que se ven (sin contar hoy). `nil` = desde el primer dato.
    public var dias: Int? {
        switch self {
        case .semana: 6
        case .mes: 29
        case .trimestre: 90
        case .anio: 364
        case .todo: nil
        }
    }

    public var titulo: String {
        switch self {
        case .semana: "Última semana"
        case .mes: "Último mes"
        case .trimestre: "Últimos tres meses"
        case .anio: "Último año"
        case .todo: "Todo"
        }
    }
}

/// Una factura emitida con dinero por cobrar.
public struct CobroPendiente: Sendable, Hashable, Identifiable {
    public var id: String { factura.id }
    public let factura: FacturaRegistro
    /// Céntimos por cobrar.
    public let pendiente: Int
    public let vence: LocalDate?
    /// Días desde el vencimiento (solo si ya venció).
    public let diasVencida: Int?

    public var vencida: Bool { diasVencida != nil }
}

/// Tesorería (SISTEMAS FI2): saldo, meses de caja, gráfica, cobros vencidos y movimientos sin conciliar.
/// Calcula sobre los registros; no escribe. Sin datos dice «Sin dato» (`nil`), nunca 0.
public struct Tesoreria: Sendable {
    public let registros: RegistrosFinanzas
    public let hoy: LocalDate
    /// Meses completos para la salida media.
    public static let mesesMedia = 3

    public init(registros: RegistrosFinanzas, hoy: LocalDate) {
        self.registros = registros
        self.hoy = hoy
    }

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        let r = reloj ?? Reloj.deCarpeta(snapshot)
        self.init(registros: RegistrosFinanzas(snapshot: snapshot), hoy: r.hoy)
    }

    // MARK: Saldo

    /// Línea de saldos de una cuenta: el saldo tras cada movimiento (hasta hoy) y de dónde sale.
    struct Linea {
        /// Saldo antes del primer movimiento y desde qué día vale (`nil` si no se sabe).
        var inicio: (fecha: LocalDate?, saldo: Int?)
        var pasos: [(fecha: LocalDate, saldo: Int?, banco: Bool)]
    }

    func linea(_ cuenta: CuentaBancaria) -> Linea {
        let movs = registros.movimientos(de: cuenta).filter { $0.fecha <= hoy }
        // Con un saldo del banco, el de antes del primer movimiento sale de él hacia atrás.
        if let k = movs.firstIndex(where: { $0.saldo != nil }) {
            let antes = movs[k].saldo! - movs[...k].map(\.importe).reduce(0, +)
            var saldo = antes
            var pasos: [(LocalDate, Int?, Bool)] = []
            var banco = true
            for m in movs {
                if let s = m.saldo { saldo = s; banco = true } else { saldo += m.importe; banco = false }
                pasos.append((m.fecha, saldo, banco))
            }
            let desde = cuenta.fechaSaldoInicial.map { min($0, movs.first!.fecha.adding(days: -1)) } ?? movs.first!.fecha.adding(days: -1)
            return Linea(inicio: (desde, antes), pasos: pasos)
        }
        // Sin saldos del banco: saldo inicial de la ficha más los movimientos posteriores. Un saldo inicial con fecha
        // posterior a hoy aún no vale: hoy el saldo es desconocido (como en `KPIEvaluador`: una sola caja).
        if let inicial = cuenta.saldoInicial, cuenta.fechaSaldoInicial.map({ $0 <= hoy }) ?? true {
            let posteriores = movs.filter { m in cuenta.fechaSaldoInicial.map { m.fecha > $0 } ?? true }
            var saldo = inicial
            var pasos: [(LocalDate, Int?, Bool)] = []
            for m in posteriores {
                saldo += m.importe
                pasos.append((m.fecha, saldo, false))
            }
            return Linea(inicio: (cuenta.fechaSaldoInicial ?? posteriores.first?.fecha.adding(days: -1), inicial), pasos: pasos)
        }
        return Linea(inicio: (nil, nil), pasos: movs.map { ($0.fecha, nil, false) })
    }

    public func saldo(de cuenta: CuentaBancaria) -> SaldoCuenta {
        let l = linea(cuenta)
        if let ultimo = l.pasos.last {
            guard let s = ultimo.saldo else { return SaldoCuenta(cuenta: cuenta, saldo: nil, fecha: nil, fuente: .desconocido) }
            return SaldoCuenta(cuenta: cuenta, saldo: s, fecha: ultimo.fecha, fuente: ultimo.banco ? .banco : .estimado)
        }
        if let s = l.inicio.saldo {
            return SaldoCuenta(cuenta: cuenta, saldo: s, fecha: l.inicio.fecha, fuente: .estimado)
        }
        return SaldoCuenta(cuenta: cuenta, saldo: nil, fecha: nil, fuente: .desconocido)
    }

    public var saldo: SaldoCaja {
        let cuentas = registros.cuentas.map(saldo(de:))
        let conocidos = cuentas.compactMap(\.saldo)
        let total: Int? = cuentas.isEmpty || conocidos.count < cuentas.count ? nil : conocidos.reduce(0, +)
        return SaldoCaja(cuentas: cuentas, total: total, conocido: conocidos.reduce(0, +),
                         estimado: cuentas.contains { $0.fuente != .banco }, fecha: cuentas.compactMap(\.fecha).max())
    }

    // MARK: Meses de caja

    /// Traspasos entre cuentas propias: los declarados (`naturaleza: traspaso`) y los que casan con un
    /// movimiento contrario del mismo importe en otra cuenta propia con 3 días de margen (uno con uno).
    public var traspasos: Set<String> {
        var out = Set(registros.movimientos.filter(\.esTraspasoDeclarado).map(\.id))
        let movs = registros.movimientos
        var usados = out
        for m in movs where m.importe < 0 && !usados.contains(m.id) {
            if let o = movs.first(where: { o in
                o.cuentaID != m.cuentaID && o.importe == -m.importe && !usados.contains(o.id)
                    && abs(ConciliationMatcher.dias(de: m.fecha, a: o.fecha)) <= ConciliationMatcher.margenDias
            }) {
                usados.insert(m.id); usados.insert(o.id)
                out.insert(m.id); out.insert(o.id)
            }
        }
        return out
    }

    public var runway: Runway {
        let caja = saldo
        guard !registros.cuentas.isEmpty else {
            return Runway(meses: nil, salidaMedia: nil, mesesUsados: [], estimado: false, motivo: "Sin datos del banco: importa un extracto")
        }
        // Meses completos antes del mes de hoy, cubiertos por los datos (desde el primer dato de la caja).
        let inicio = registros.cuentas.compactMap { c -> LocalDate? in
            let l = linea(c)
            return l.inicio.fecha.map { $0.adding(days: 1) } ?? l.pasos.first?.fecha
        }.min()
        guard let inicio else {
            return Runway(meses: nil, salidaMedia: nil, mesesUsados: [], estimado: false, motivo: "Sin datos del banco: importa un extracto")
        }
        // Integración F2 (una sola caja con `KPIEvaluador`): un mes solo cuenta si los movimientos del banco lo cubren
        // **entero** (hasta el último movimiento a hoy). Un extracto atrasado no infla los meses de caja con meses sin
        // datos que parecerían meses sin gastos.
        let hasta = registros.movimientos.lazy.map(\.fecha).filter { $0 <= self.hoy }.max()
        var meses: [(Int, Int)] = []
        var a = hoy.year, m = hoy.month
        while meses.count < Self.mesesMedia {
            m -= 1
            if m == 0 { m = 12; a -= 1 }
            guard let primero = LocalDate(year: a, month: m, day: 1), primero >= inicio else { break }
            guard let siguiente = LocalDate(year: m == 12 ? a + 1 : a, month: m == 12 ? 1 : m + 1, day: 1) else { break }
            if let hasta, siguiente.adding(days: -1) <= hasta { meses.append((a, m)) }
        }
        guard !meses.isEmpty else {
            // Si además falta el saldo de una cuenta, eso es lo primero que hay que arreglar.
            return Runway(meses: nil, salidaMedia: nil, mesesUsados: [], estimado: caja.estimado,
                          motivo: caja.total == nil ? "Falta el saldo de alguna cuenta"
                              : "Hace falta al menos un mes completo de movimientos del banco")
        }
        let traspasos = self.traspasos
        let claves = Set(meses.map { String(format: "%04d-%02d", $0.0, $0.1) })
        let salidas = registros.movimientos.filter { mv in
            mv.importe < 0 && !traspasos.contains(mv.id)
                && claves.contains(String(format: "%04d-%02d", mv.fecha.year, mv.fecha.month))
        }.map { -$0.importe }.reduce(0, +)
        // Redondeo al céntimo (no truncado), como `KPIEvaluador.salidaMensual`.
        let media = Int((Double(salidas) / Double(meses.count)).rounded())
        let usados = meses.map { String(format: "%04d-%02d", $0.0, $0.1) }.sorted()
        guard let total = caja.total else {
            return Runway(meses: nil, salidaMedia: media, mesesUsados: usados, estimado: caja.estimado,
                          motivo: "Falta el saldo de alguna cuenta")
        }
        guard media > 0 else {
            return Runway(meses: nil, salidaMedia: 0, mesesUsados: usados, estimado: caja.estimado,
                          motivo: "No hubo salidas de dinero en esos meses")
        }
        let valor = (Double(total) / Double(media) * 10).rounded() / 10
        return Runway(meses: valor, salidaMedia: media, mesesUsados: usados, estimado: caja.estimado, motivo: nil)
    }

    // MARK: Gráfica

    /// Saldo de la caja día a día (hasta hoy). Un día sin dato de alguna cuenta va sin saldo.
    public func serie(_ rango: RangoCaja) -> [PuntoCaja] {
        let lineas = registros.cuentas.map(linea)
        guard !lineas.isEmpty else { return [] }
        let primeros = lineas.compactMap { $0.inicio.fecha ?? $0.pasos.first?.fecha }
        guard let primero = primeros.min() else { return [] }
        let desde = rango.dias.map { max(primero, hoy.adding(days: -$0)) } ?? primero
        guard desde <= hoy else { return [] }
        // Por cuenta: el saldo al final de cada día.
        func saldo(_ l: Linea, en dia: LocalDate) -> (Int?, Bool)? {
            if let ultimo = l.pasos.last(where: { $0.fecha <= dia }) { return (ultimo.saldo, !ultimo.banco) }
            if let f = l.inicio.fecha, f <= dia { return (l.inicio.saldo, true) }
            return nil
        }
        var puntos: [PuntoCaja] = []
        var dia = desde
        while dia <= hoy {
            var total: Int? = 0
            var estimado = false
            for l in lineas {
                guard let r = saldo(l, en: dia), let s = r.0 else { total = nil; break }
                total? += s
                estimado = estimado || r.1
            }
            let conMovimientos = lineas.contains { l in l.pasos.contains { $0.fecha == dia } }
            puntos.append(PuntoCaja(fecha: dia, saldo: total, estimado: total != nil && estimado, conMovimientos: conMovimientos))
            dia = dia.adding(days: 1)
        }
        return puntos
    }

    // MARK: Cobros

    /// Facturas emitidas con algo por cobrar (las vencidas primero, la más antigua arriba).
    /// Las filas heredadas sin revisar no entran (ver `sinRevisar`).
    public var cobrosPendientes: [CobroPendiente] {
        registros.emitidas.compactMap { f -> CobroPendiente? in
            guard !f.sinRevisar, let p = registros.pendiente(de: f), p > 0 else { return nil }
            let dias = f.vence.map { ConciliationMatcher.dias(de: $0, a: hoy) }
            return CobroPendiente(factura: f, pendiente: p, vence: f.vence, diasVencida: dias.flatMap { $0 > 0 ? $0 : nil })
        }.sorted { a, b in
            if a.vencida != b.vencida { return a.vencida }
            return (a.vence ?? a.factura.fecha ?? hoy, a.factura.id) < (b.vence ?? b.factura.fecha ?? hoy, b.factura.id)
        }
    }

    public var cobrosVencidos: [CobroPendiente] { cobrosPendientes.filter(\.vencida) }

    /// FIN-AR: lo pendiente de las emitidas vencidas. `nil` si no hay facturas emitidas («Sin dato»).
    public var totalVencido: Int? {
        registros.emitidas.isEmpty ? nil : cobrosVencidos.map(\.pendiente).reduce(0, +)
    }

    /// Facturas heredadas que aún no se han revisado (no cuentan en cobros).
    public var sinRevisar: Int { registros.emitidas.filter(\.sinRevisar).count }

    /// FIN-UNREC: movimientos ni conciliados ni ignorados. `nil` si no hay movimientos («Sin dato»).
    public var sinConciliar: Int? {
        // Lo que aún no había pasado a `hoy` no cuenta (como `KPIEvaluador`, FIN-UNREC).
        let movs = registros.movimientos.filter { $0.fecha <= hoy }
        return movs.isEmpty ? nil : movs.filter { $0.estado.abierto }.count
    }
}
