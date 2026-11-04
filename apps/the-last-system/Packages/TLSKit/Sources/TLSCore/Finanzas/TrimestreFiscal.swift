// Procedencia: plazos del trimestre portados de PROG core/sql/11-fiscal.sql (`periodo_trimestre`) y cálculo del 303
// portado de PROG core/importar-notion.js (`calcular303`) y 11-fiscal.sql (`fiscal_303`), ambos de Manu. Reescrito en
// Swift sobre emitidas.csv y recibidas.csv. Ver docs/PROCEDENCIA.md.
import Foundation

/// Un trimestre natural con sus plazos. Las fechas se derivan, no se escriben: el 303 del T4 vence el 30 de
/// enero y no el 20 como los otros tres.
public struct PeriodoTrimestre: Sendable, Hashable, Comparable, Identifiable {
    public let anio: Int
    public let numero: Int

    public init?(anio: Int, numero: Int) {
        guard (1...4).contains(numero), (1900...2999).contains(anio) else { return nil }
        self.anio = anio; self.numero = numero
    }

    public init(contiene fecha: LocalDate) {
        anio = fecha.year
        numero = (fecha.month - 1) / 3 + 1
    }

    public var id: String { "\(anio)-T\(numero)" }
    /// «T3 2026».
    public var titulo: String { "T\(numero) \(anio)" }
    /// `2026/T3` (carpeta bajo `Fiscal/`).
    public var carpeta: String { "\(anio)/T\(numero)" }

    public var desde: LocalDate { LocalDate(year: anio, month: (numero - 1) * 3 + 1, day: 1)! }
    public var hasta: LocalDate {
        let mes = numero * 3
        return LocalDate(year: anio, month: mes, day: mes == 6 || mes == 9 ? 30 : 31)!
    }
    /// Día 5 del mes siguiente: cierre previo para preparar el paquete.
    public var precierre: LocalDate { numero == 4 ? LocalDate(year: anio + 1, month: 1, day: 5)! : LocalDate(year: anio, month: numero * 3 + 1, day: 5)! }
    /// Último día para presentar (20; el T4, 30 de enero).
    public var plazo: LocalDate { numero == 4 ? LocalDate(year: anio + 1, month: 1, day: 30)! : LocalDate(year: anio, month: numero * 3 + 1, day: 20)! }
    /// Último día para domiciliar el pago (15; el T4, 25 de enero).
    public var domiciliacion: LocalDate { numero == 4 ? LocalDate(year: anio + 1, month: 1, day: 25)! : LocalDate(year: anio, month: numero * 3 + 1, day: 15)! }

    public var anterior: PeriodoTrimestre { numero == 1 ? PeriodoTrimestre(anio: anio - 1, numero: 4)! : PeriodoTrimestre(anio: anio, numero: numero - 1)! }
    public var siguiente: PeriodoTrimestre { numero == 4 ? PeriodoTrimestre(anio: anio + 1, numero: 1)! : PeriodoTrimestre(anio: anio, numero: numero + 1)! }

    public func contiene(_ f: LocalDate) -> Bool { f >= desde && f <= hasta }

    /// El que toca presentar ahora: el anterior hasta su plazo; después, el de hoy.
    public static func aPresentar(hoy: LocalDate) -> PeriodoTrimestre {
        let actual = PeriodoTrimestre(contiene: hoy)
        return hoy <= actual.anterior.plazo ? actual.anterior : actual
    }

    public static func < (a: PeriodoTrimestre, b: PeriodoTrimestre) -> Bool { (a.anio, a.numero) < (b.anio, b.numero) }
}

/// Algo que falta para cerrar el trimestre (también va a `diferencias.csv` del paquete).
public struct FaltaTrimestre: Sendable, Hashable {
    /// «gasto sin justificante», «ingreso sin IVA conocido», «movimiento sin conciliar»…
    public let tipo: String
    public let fecha: LocalDate?
    public let descripcion: String
    public let importe: Int?
    /// Id del registro (factura, movimiento) del que sale.
    public let id: String?
}

/// Si un modelo aplica a esta empresa.
public enum AplicaModelo: Sendable, Hashable {
    case si
    /// No aplica, con el motivo («Las sociedades no presentan el 130»).
    case no(String)
    /// No se sabe (por ejemplo, si eres autónomo o sociedad).
    case sinDato(String)
}

/// Estimación de un modelo del trimestre. **Estimado**: la gestoría lo revisa y lo presenta.
public struct EstimacionModelo: Sendable, Hashable {
    public let modelo: String
    public let aplica: AplicaModelo
    /// Resultado (positivo a ingresar, negativo a compensar o devolver). `nil` = «Sin dato» (ver `faltan`).
    public let resultado: Int?
    /// Lo que suman los datos que sí hay (aunque falten otros).
    public let parcial: Int?
    /// Líneas del cálculo (concepto e importe).
    public let lineas: [Linea]
    public let faltan: [FaltaTrimestre]
    /// Avisos sobre lo que el cálculo no puede saber.
    public let notas: [String]

    public struct Linea: Sendable, Hashable {
        public let concepto: String
        public let importe: Int
    }
}

/// Totales de un libro (ingresos o gastos) del trimestre.
public struct TotalesLibro: Sendable, Hashable {
    public let documentos: Int
    public let base: Int?
    public let iva: Int?
    public let retencion: Int?
    public let total: Int?
}

/// El trimestre de un vistazo: totales, modelos estimados, plazos y qué falta.
public struct ResumenTrimestre: Sendable {
    public let periodo: PeriodoTrimestre
    public let ingresos: TotalesLibro
    public let gastos: TotalesLibro
    public let modelo303: EstimacionModelo
    public let modelo130: EstimacionModelo
    public let modelo111: EstimacionModelo
    public let modelo115: EstimacionModelo
    /// Días hasta el plazo de presentación (negativo si ya pasó).
    public let diasHastaPlazo: Int
    /// Todo lo que falta (sin repetir).
    public let faltan: [FaltaTrimestre]
}

/// Forma jurídica: decide si aplica el 130 (solo autónomos en estimación directa).
public enum FormaJuridica: String, Sendable, Hashable {
    case autonomo, sociedad

    /// De `.tls/config.yaml`: `fiscal: {forma: autonomo|sociedad}` o, si no, por la primera letra del NIF de
    /// `facturacion.nif` (una cifra o X, Y, Z, K, L, M = persona; otra letra = sociedad). `nil` si no se sabe.
    public static func deCarpeta(_ snapshot: VaultSnapshot) -> FormaJuridica? {
        guard let texto = snapshot.text(VaultPath(".tls/config.yaml")),
              FrontmatterReader.read(texto).isValid else { return nil }
        let fm = FrontmatterReader.read(texto)
        func mapa(_ clave: String) -> String? {
            guard case .raw(let r)? = fm.value(clave) else { return nil }
            return r
        }
        if let f = mapa("fiscal").flatMap({ FrontmatterReader.read($0).text("forma") }) {
            let t = TextFolding.fold(f)
            if t.hasPrefix("autonom") || t == "persona" { return .autonomo }
            if t.hasPrefix("socied") || t == "sl" || t == "sa" { return .sociedad }
        }
        guard let nif = mapa("facturacion").flatMap({ FrontmatterReader.read($0).text("nif") })?
            .trimmingCharacters(in: .whitespaces).uppercased(), let primera = nif.first else { return nil }
        if primera.isNumber || "XYZKLM".contains(primera) { return .autonomo }
        if "ABCDEFGHJNPQRSUVW".contains(primera) { return .sociedad }
        return nil
    }
}

/// Estimaciones del trimestre (SISTEMAS FI3, PLAN §6.5 · Trimestre): 303 (IVA repercutido − soportado de
/// emitidas y recibidas), 130 si eres autónomo, 111 (retenciones a profesionales y nóminas) y 115 (alquileres).
/// Lo que no está en los registros no se supone: el modelo queda «Sin dato» con lo que falta.
public struct TrimestreFiscal: Sendable {
    public let registros: RegistrosFinanzas
    public let hoy: LocalDate
    public let forma: FormaJuridica?

    public init(registros: RegistrosFinanzas, hoy: LocalDate, forma: FormaJuridica? = nil) {
        self.registros = registros
        self.hoy = hoy
        self.forma = forma ?? FormaJuridica.deCarpeta(registros.snapshot)
    }

    public init(snapshot: VaultSnapshot, reloj: Reloj? = nil) {
        self.init(registros: RegistrosFinanzas(snapshot: snapshot), hoy: (reloj ?? Reloj.deCarpeta(snapshot)).hoy)
    }

    public var aPresentar: PeriodoTrimestre { PeriodoTrimestre.aPresentar(hoy: hoy) }

    func emitidas(_ p: PeriodoTrimestre) -> [FacturaRegistro] { registros.emitidas.filter { $0.fecha.map(p.contiene) ?? false } }
    func recibidas(_ p: PeriodoTrimestre) -> [FacturaRegistro] { registros.recibidas.filter { $0.fecha.map(p.contiene) ?? false } }

    static func esAlquiler(_ f: FacturaRegistro) -> Bool {
        let c = TextFolding.fold((f.categoria ?? "") + " " + (f.naturaleza ?? ""))
        return c.contains("alquiler") || c.contains("arrendamiento")
    }

    static func regla(_ f: FacturaRegistro) -> LectorFiscal.ReglaFiscal? {
        f.tipoFiscal.flatMap { LectorFiscal.reglas[TextFolding.fold($0)] }
    }

    /// Sumas de un libro. Sin facturas, o con alguna sin ese dato, «Sin dato» (`nil`), nunca 0.
    public func totales(_ facturas: [FacturaRegistro]) -> TotalesLibro {
        func suma(_ k: KeyPath<FacturaRegistro, Int?>) -> Int? {
            guard !facturas.isEmpty else { return nil }
            let v = facturas.map { $0[keyPath: k] }
            return v.contains { $0 == nil } ? nil : v.compactMap { $0 }.reduce(0, +)
        }
        return TotalesLibro(documentos: facturas.count, base: suma(\.base), iva: suma(\.iva), retencion: suma(\.retencion),
                            total: suma(\.total))
    }

    public func resumen(_ p: PeriodoTrimestre) -> ResumenTrimestre {
        let m303 = modelo303(p), m130 = modelo130(p), m111 = modelo111(p), m115 = modelo115(p)
        var faltan: [FaltaTrimestre] = []
        for f in m303.faltan + m130.faltan + m111.faltan + m115.faltan where !faltan.contains(f) { faltan.append(f) }
        return ResumenTrimestre(periodo: p, ingresos: totales(emitidas(p)), gastos: totales(recibidas(p)),
                                modelo303: m303, modelo130: m130, modelo111: m111, modelo115: m115,
                                diasHastaPlazo: ConciliationMatcher.dias(de: hoy, a: p.plazo), faltan: faltan)
    }

    // MARK: 303

    public func modelo303(_ p: PeriodoTrimestre) -> EstimacionModelo {
        var devengado = 0, deducible = 0
        var faltan: [FaltaTrimestre] = []
        var notas: [String] = []
        for f in emitidas(p) {
            let r = Self.regla(f)
            if r?.computa303 == false { continue }
            guard let iva = f.iva else {
                faltan.append(FaltaTrimestre(tipo: "ingreso sin IVA conocido", fecha: f.fecha,
                                             descripcion: "La factura \(f.numeroVisible) no dice su IVA", importe: f.total, id: f.id))
                continue
            }
            devengado += iva
        }
        var autoliquidado = 0
        for f in recibidas(p) {
            let r = Self.regla(f)
            if r?.computa303 == false { continue }
            if let auto = r?.autoliquida {
                guard let base = f.base else {
                    faltan.append(FaltaTrimestre(tipo: "gasto sin base conocida", fecha: f.fecha,
                                                 descripcion: "La factura \(f.numeroVisible) de \(f.tercero ?? "un proveedor") no dice su base",
                                                 importe: f.total, id: f.id))
                    continue
                }
                let cuota = Int((Double(abs(base)) * auto).rounded())
                autoliquidado += cuota
                continue
            }
            guard let iva = f.iva else {
                faltan.append(FaltaTrimestre(tipo: "gasto sin IVA conocido", fecha: f.fecha,
                                             descripcion: "La factura \(f.numeroVisible) de \(f.tercero ?? "un proveedor") no dice su IVA",
                                             importe: f.total, id: f.id))
                continue
            }
            deducible += Int((Double(iva) * (r?.parteIVA ?? 1)).rounded())
        }
        if autoliquidado > 0 { notas.append("Incluye la autoliquidación de compras intracomunitarias (en devengado y en deducible).") }
        let sinTipo = recibidas(p).filter { $0.tipoFiscal == nil }.count
        if sinTipo > 0 {
            notas.append("Las facturas recibidas no dicen su tipo fiscal: todo su IVA se toma como deducible. La gestoría lo revisa.")
        }
        let parcial = (devengado + autoliquidado) - (deducible + autoliquidado)
        let lineas = [EstimacionModelo.Linea(concepto: "IVA repercutido", importe: devengado + autoliquidado),
                      EstimacionModelo.Linea(concepto: "IVA soportado deducible", importe: deducible + autoliquidado)]
        let hayDatos = !emitidas(p).isEmpty || !recibidas(p).isEmpty
        return EstimacionModelo(modelo: "303", aplica: .si, resultado: faltan.isEmpty && hayDatos ? parcial : nil,
                                parcial: hayDatos ? parcial : nil, lineas: lineas, faltan: faltan,
                                notas: hayDatos ? notas : ["No hay facturas del trimestre en los registros."])
    }

    // MARK: 130

    /// Pago fraccionado del IRPF (autónomos): 20 % del rendimiento acumulado del año − retenciones que te
    /// practicaron − lo que salió en los trimestres anteriores.
    public func modelo130(_ p: PeriodoTrimestre) -> EstimacionModelo {
        guard let forma else {
            return EstimacionModelo(modelo: "130", aplica: .sinDato("No sé si eres autónomo o sociedad: dilo en los ajustes de la carpeta."),
                                    resultado: nil, parcial: nil, lineas: [], faltan: [], notas: [])
        }
        guard forma == .autonomo else {
            return EstimacionModelo(modelo: "130", aplica: .no("Las sociedades no presentan el 130."),
                                    resultado: nil, parcial: nil, lineas: [], faltan: [], notas: [])
        }
        var anteriores = 0
        var resultado: Int?
        var parcial = 0
        var lineas: [EstimacionModelo.Linea] = []
        var faltan: [FaltaTrimestre] = []
        // Cada trimestre del año hasta este, acumulando (el 130 es acumulado).
        for n in 1...p.numero {
            let hastaFecha = PeriodoTrimestre(anio: p.anio, numero: n)!.hasta
            let desdeFecha = PeriodoTrimestre(anio: p.anio, numero: 1)!.desde
            let ing = registros.emitidas.filter { $0.fecha.map { $0 >= desdeFecha && $0 <= hastaFecha } ?? false }
            let gas = registros.recibidas.filter { f in
                (f.fecha.map { $0 >= desdeFecha && $0 <= hastaFecha } ?? false) && TextFolding.fold(f.tipoFiscal ?? "") != "borrador"
            }
            var falta: [FaltaTrimestre] = []
            for f in ing where f.base == nil {
                falta.append(FaltaTrimestre(tipo: "ingreso sin base conocida", fecha: f.fecha,
                                            descripcion: "La factura \(f.numeroVisible) no dice su base", importe: f.total, id: f.id))
            }
            for f in gas where f.base == nil {
                falta.append(FaltaTrimestre(tipo: "gasto sin base conocida", fecha: f.fecha,
                                            descripcion: "La factura \(f.numeroVisible) de \(f.tercero ?? "un proveedor") no dice su base",
                                            importe: f.total, id: f.id))
            }
            let rendimiento = ing.compactMap(\.base).reduce(0, +) - gas.compactMap { $0.base.map(abs) }.reduce(0, +)
            let retenciones = ing.compactMap(\.retencion).reduce(0, +)
            let cuota = max(0, Int((Double(rendimiento) * 0.2).rounded()) - retenciones - anteriores)
            if n == p.numero {
                faltan = falta
                parcial = cuota
                resultado = falta.isEmpty ? cuota : nil
                lineas = [EstimacionModelo.Linea(concepto: "Rendimiento del año hasta el trimestre", importe: rendimiento),
                          EstimacionModelo.Linea(concepto: "20 % del rendimiento", importe: Int((Double(rendimiento) * 0.2).rounded())),
                          EstimacionModelo.Linea(concepto: "Retenciones que te practicaron", importe: retenciones),
                          EstimacionModelo.Linea(concepto: "Pagado en trimestres anteriores", importe: anteriores)]
            } else {
                anteriores += cuota
            }
        }
        return EstimacionModelo(modelo: "130", aplica: .si, resultado: resultado, parcial: parcial, lineas: lineas, faltan: faltan,
                                notas: ["Solo cuenta las facturas: la cuota de autónomos y otros gastos sin factura los añade la gestoría."])
    }

    // MARK: 111 y 115

    /// Retenciones a profesionales (facturas recibidas con retención que no son alquiler) y de nóminas.
    public func modelo111(_ p: PeriodoTrimestre) -> EstimacionModelo {
        let conRetencion = recibidas(p).filter { !Self.esAlquiler($0) && ($0.retencion ?? 0) != 0 }
        let suma = conRetencion.compactMap(\.retencion).map(abs).reduce(0, +)
        let nominas = registros.movimientos.filter { m in
            p.contiene(m.fecha) && m.importe < 0 && (TextFolding.fold(m.naturaleza ?? "").hasPrefix("nomina")
                || TextFolding.fold(m.categoria ?? "").hasPrefix("nomina"))
        }
        var faltan: [FaltaTrimestre] = []
        for m in nominas {
            faltan.append(FaltaTrimestre(tipo: "nómina sin retención registrada", fecha: m.fecha,
                                         descripcion: "\(m.concepto): la retención de la nómina no está en los registros",
                                         importe: m.importe, id: m.id))
        }
        if conRetencion.isEmpty && nominas.isEmpty {
            return EstimacionModelo(modelo: "111", aplica: .no("No hay retenciones a profesionales ni nóminas en el trimestre."),
                                    resultado: nil, parcial: nil, lineas: [], faltan: [], notas: [])
        }
        return EstimacionModelo(modelo: "111", aplica: .si, resultado: faltan.isEmpty ? suma : nil, parcial: suma,
                                lineas: [EstimacionModelo.Linea(concepto: "Retenciones en facturas de profesionales", importe: suma)],
                                faltan: faltan, notas: [])
    }

    /// Retenciones de los alquileres (facturas recibidas de alquiler con retención).
    public func modelo115(_ p: PeriodoTrimestre) -> EstimacionModelo {
        let alquileres = recibidas(p).filter(Self.esAlquiler)
        let conRetencion = alquileres.filter { ($0.retencion ?? 0) != 0 }
        let sinDato = alquileres.filter { $0.retencion == nil }
        if conRetencion.isEmpty && sinDato.isEmpty {
            return EstimacionModelo(modelo: "115", aplica: .no("No hay alquileres con retención en el trimestre."),
                                    resultado: nil, parcial: nil, lineas: [], faltan: [], notas: [])
        }
        let faltan = sinDato.map {
            FaltaTrimestre(tipo: "alquiler sin retención conocida", fecha: $0.fecha,
                           descripcion: "La factura \($0.numeroVisible) de \($0.tercero ?? "alquiler") no dice su retención",
                           importe: $0.total, id: $0.id)
        }
        let suma = conRetencion.compactMap(\.retencion).map(abs).reduce(0, +)
        return EstimacionModelo(modelo: "115", aplica: .si, resultado: faltan.isEmpty ? suma : nil, parcial: suma,
                                lineas: [EstimacionModelo.Linea(concepto: "Retenciones de alquileres", importe: suma)],
                                faltan: faltan, notas: [])
    }
}
