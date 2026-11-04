import Foundation
import TLSCore

// F2 · rol areas-b. Lo que pintan Finanzas › Operación y el Banco (PLAN §6.5, §4.6 y §7.3; SISTEMAS FI1–FI3), leído
// de una foto de la carpeta con el núcleo del rol de banco (`Sources/TLSCore/Finanzas`). Puro y `Sendable`: se hace
// fuera del hilo principal y en las pruebas. Nunca escribe y **nunca enseña lo privado** (los registros del banco ya lo
// dejan fuera). Lo que no se sabe es `nil` («Sin dato»), nunca 0.

/// Finanzas de un vistazo: caja, cobros, banco, trimestre y lo heredado.
struct LecturaFinanzas: Sendable {
    let hoy: LocalDate
    let cuentas: [CuentaBancaria]
    /// Saldo de la caja (todas las cuentas) y de cada cuenta, con su fuente.
    let saldo: SaldoCaja
    let runway: Runway
    /// Puntos de la gráfica de cada periodo (1S · 1M · 3M · 1A · Todo).
    let series: [RangoCaja: [PuntoCaja]]
    /// Facturas emitidas con dinero por cobrar (vencidas primero).
    let cobrosPendientes: [CobroPendiente]
    /// FIN-AR en céntimos (`nil` = sin registro de emitidas).
    let totalVencido: Int?
    /// FIN-UNREC (`nil` = sin movimientos del banco).
    let sinConciliar: Int?
    /// Facturas cargadas de ficheros heredados y aún sin revisar.
    let sinRevisar: Int
    /// Propuestas de conciliación (importe exacto, número de factura o contraparte).
    let propuestas: [PropuestaConciliacion]
    /// Movimientos abiertos (pendientes o propuestos) sin propuesta que confirmar.
    let abiertos: [MovimientoBanco]
    /// Todos los movimientos del banco (todas las cuentas).
    let movimientos: [MovimientoBanco]
    /// Lo que no se pudo leer de los registros, en castellano.
    let avisos: [String]
    /// Existe `emitidas.csv` (si no, los cobros son «Sin dato»).
    let hayEmitidas: Bool
    /// El trimestre que se enseña, su resumen y su paquete para la gestoría.
    let periodo: PeriodoTrimestre
    let trimestre: ResumenTrimestre
    let paquete: PaqueteGestoria
    /// Movimientos heredados de `Registros/importar/` (`nil` si no hay ficheros que cargar).
    let heredados: PreparacionHeredada?
    /// `1 · Dirección/Metas.md` si existe y no es privada (para proponer FIN-RUNWAY si falta).
    let metas: VaultPath?

    /// Lee todo. `periodo` = el trimestre que se enseña (`nil` = el que toca presentar ahora).
    init(foto: VaultSnapshot, hoy: LocalDate, periodo: PeriodoTrimestre? = nil) {
        let registros = RegistrosFinanzas(snapshot: foto)
        let tesoreria = Tesoreria(registros: registros, hoy: hoy)
        self.hoy = hoy
        cuentas = registros.cuentas
        saldo = tesoreria.saldo
        runway = tesoreria.runway
        var series: [RangoCaja: [PuntoCaja]] = [:]
        for r in RangoCaja.allCases { series[r] = tesoreria.serie(r) }
        self.series = series
        cobrosPendientes = tesoreria.cobrosPendientes
        totalVencido = tesoreria.totalVencido
        sinConciliar = tesoreria.sinConciliar
        sinRevisar = tesoreria.sinRevisar
        let propuestas = ConciliationMatcher(registros: registros).proponer()
        self.propuestas = propuestas
        let conPropuesta = Set(propuestas.map(\.movimiento.id))
        abiertos = registros.movimientos.filter { $0.estado.abierto && $0.pagoID == nil && !conPropuesta.contains($0.id) }
            .sorted { ($0.fecha, $0.orden) > ($1.fecha, $1.orden) }
        movimientos = registros.movimientos
        avisos = registros.avisos
        hayEmitidas = foto.existing(registros.emitidasCSV) != nil
        let fiscal = TrimestreFiscal(registros: registros, hoy: hoy)
        let p = periodo ?? fiscal.aPresentar
        self.periodo = p
        trimestre = fiscal.resumen(p)
        paquete = PreparadorPaquete(registros: registros, reloj: Reloj(hoy: hoy)).preparar(p)
        let legado = LegacyMovementsImporter(snapshot: foto)
        heredados = legado.ficheros.isEmpty ? nil : legado.preparar()
        let rutaMetas = foto.layout.areaFolder(.direccion).appending("Metas.md")
        metas = foto.layout.isPrivate(rutaMetas) ? nil : foto.existing(rutaMetas)
    }

    var cobrosVencidos: [CobroPendiente] { cobrosPendientes.filter(\.vencida) }

    /// Propuestas que se confirman con «Confirmar las exactas» (sin empates).
    var exactas: [PropuestaConciliacion] { propuestas.filter(\.exacta) }

    /// Fecha del último movimiento del banco (de cualquier cuenta).
    var ultimoMovimiento: LocalDate? { movimientos.map(\.fecha).max() }

    /// Hay algún dato del banco (movimientos o un saldo conocido).
    var hayDatosBanco: Bool { !movimientos.isEmpty || saldo.cuentas.contains { $0.saldo != nil } }

    // MARK: Una cuenta

    /// La cuenta cuya carpeta es `carpeta` (`4 · Finanzas/Registros/Bancos/<cuenta>`).
    func cuenta(carpeta: VaultPath) -> CuentaBancaria? {
        cuentas.first { TextFolding.pathKey($0.carpeta.raw) == TextFolding.pathKey(carpeta.raw) }
    }

    func propuestas(de cuenta: CuentaBancaria?) -> [PropuestaConciliacion] {
        guard let cuenta else { return propuestas }
        return propuestas.filter { $0.cuenta.id == cuenta.id }
    }

    func abiertos(de cuenta: CuentaBancaria?) -> [MovimientoBanco] {
        guard let cuenta else { return abiertos }
        return abiertos.filter { $0.cuentaID == cuenta.id }
    }

    func movimientos(de cuenta: CuentaBancaria) -> [MovimientoBanco] { movimientos.filter { $0.cuentaID == cuenta.id } }
}

/// Textos de Finanzas (importes en céntimos, fechas y frases de la caja). Sin dato, «Sin dato»; nunca 0 de relleno.
enum TextoFinanzas {
    static let sinDato = "Sin dato"

    /// `-76370` → «−763,70 €»; `nil` → «Sin dato».
    static func euros(_ centimos: Int?) -> String {
        guard let c = centimos else { return sinDato }
        let t = DineroExacto.euros(c)
        return t.hasPrefix("-") ? "−" + t.dropFirst() : t
    }

    /// Con signo siempre: «+181,50 €», «−663,00 €».
    static func eurosConSigno(_ centimos: Int) -> String {
        centimos > 0 ? "+" + euros(centimos) : euros(centimos)
    }

    /// «19 oct» (con el año si no es el de `hoy`).
    static func fecha(_ d: LocalDate, hoy: LocalDate) -> String { FormatoFicha.fechaCorta(d, hoy: hoy) }

    /// «7,9 meses» (`nil` → «Sin dato»).
    static func meses(_ m: Double?) -> String {
        guard let m, m.isFinite else { return sinDato }
        let t = String(format: "%.1f", m).replacingOccurrences(of: ".", with: ",")
        return t == "1,0" ? "1,0 mes" : "\(t) meses"
    }

    /// «−3,9 %».
    static func porcentaje(_ p: Double) -> String {
        guard p.isFinite else { return "" }
        let t = String(format: "%.1f", abs(p)).replacingOccurrences(of: ".", with: ",")
        return (p < 0 ? "−" : (p > 0 ? "+" : "")) + t + " %"
    }

    /// El nombre del periodo para una frase: «la última semana», «el último mes»…
    static func nombre(_ r: RangoCaja) -> String {
        switch r {
        case .semana: "la última semana"
        case .mes: "el último mes"
        case .trimestre: "los últimos tres meses"
        case .anio: "el último año"
        case .todo: "todo lo que hay"
        }
    }

    /// Nombre para VoiceOver del botón del periodo.
    static func nombreLargo(_ r: RangoCaja) -> String {
        switch r {
        case .semana: "Una semana"
        case .mes: "Un mes"
        case .trimestre: "Tres meses"
        case .anio: "Un año"
        case .todo: "Todo"
        }
    }

    /// De dónde sale el saldo de una cuenta: «Del banco, 17 oct», «Estimado: saldo inicial y movimientos», «Sin dato».
    static func fuente(_ s: SaldoCuenta, hoy: LocalDate) -> String {
        switch s.fuente {
        case .banco: s.fecha.map { "Del banco, \(fecha($0, hoy: hoy))" } ?? "Del banco"
        case .estimado: "Estimado: saldo inicial y movimientos"
        case .desconocido: "Sin dato: la cuenta no tiene saldo inicial ni extracto"
        }
    }

    /// «hace 3 días», «hoy», «dentro de 2 días».
    static func dias(_ n: Int) -> String {
        switch n {
        case 0: "hoy"
        case 1: "mañana"
        case -1: "ayer"
        case let x where x > 1: "dentro de \(x) días"
        default: "hace \(-n) días"
        }
    }
}

/// Cómo se mueve la caja en un periodo de la gráfica.
struct VariacionCajaFinanzas: Sendable, Hashable {
    /// Primer y último punto con saldo del periodo.
    let desde: PuntoCaja
    let hasta: PuntoCaja
    /// Sin ningún movimiento del banco en el tramo no se sabe si la caja cambió (falta el extracto): «Sin dato», nunca
    /// «0,00 €» ni «no cambia» (revisión final de F2, regla 3).
    let sinMovimientos: Bool

    init?(_ puntos: [PuntoCaja]) {
        guard let a = puntos.first(where: { $0.saldo != nil }), let b = puntos.last(where: { $0.saldo != nil }) else { return nil }
        desde = a; hasta = b
        sinMovimientos = !PuntoCaja.hayMovimientos(puntos, desde: a.fecha, hasta: b.fecha)
    }

    var diferencia: Int { (hasta.saldo ?? 0) - (desde.saldo ?? 0) }

    /// Porcentaje sobre el saldo del principio (`nil` si empezaba en 0 o en negativo).
    var porcentaje: Double? {
        guard let s = desde.saldo, s > 0 else { return nil }
        return Double(diferencia) / Double(s) * 100
    }

    /// «−763,70 € · −3,9 %» (o «Sin dato» si no hay movimientos en el tramo).
    var texto: String {
        if sinMovimientos { return "Sin dato" }
        let base = TextoFinanzas.eurosConSigno(diferencia)
        return porcentaje.map { base + " · " + TextoFinanzas.porcentaje($0) } ?? base
    }

    /// «La caja baja 763,70 € en la última semana.» / «La caja no cambia en …» / «Sin dato: falta el extracto…».
    func frase(_ r: RangoCaja) -> String {
        if sinMovimientos { return "Sin dato: falta el extracto de este periodo." }
        let d = diferencia
        if d == 0 { return "La caja no cambia en \(TextoFinanzas.nombre(r))." }
        let verbo = d > 0 ? "sube" : "baja"
        var t = "La caja \(verbo) \(TextoFinanzas.euros(abs(d))) en \(TextoFinanzas.nombre(r))"
        if desde.estimado || hasta.estimado { t += " (en parte estimado: no hay extracto de todo el periodo)" }
        return t + "."
    }
}
