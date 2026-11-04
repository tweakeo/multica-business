// Procedencia: port reescrito de Programa v0.5 (Manu), core/sql/08-metricas.sql (`ritmo_objetivos`: cada objetivo
// medido en su propio periodo, esperado = meta × parte del periodo transcurrida) y core/sql/05-diseno.sql
// (`ritmo_empresa`: cada objetivo capado a 100 antes de promediar). La regla «el área toma el ritmo de su número más
// atrasado» es de PLAN §9 F2 y SISTEMAS.md DI3. Ver docs/PROCEDENCIA.md.
import Foundation

/// El ritmo de un objetivo: si al paso que va llega a su meta.
public struct RitmoObjetivo: Sendable, Hashable, Identifiable {
    public var id: VaultPath { objetivo.ruta }
    public let objetivo: FotoMetricas.Objetivo
    public let estado: EstadoRitmo
    /// Lo conseguido en el periodo del objetivo (`nil`: sin dato).
    public let real: Double?
    /// Lo que tocaba a estas alturas.
    public let esperado: Double?
    public let diasTotal: Int?
    public let diasPasados: Int?
    public let diasRestantes: Int?
    /// Real / esperado, en %.
    public let pct: Int?
    /// Real / meta, en %.
    public let avancePct: Int?
    /// Lo que falta para la meta (0 si ya se llegó).
    public let falta: Double?
    /// Por qué no hay ritmo («Sin dato: …», «Sin número»).
    public let motivo: String?

    public var unidad: String { objetivo.unidad ?? "" }
}

/// El ritmo de un área: el de su número más atrasado (objetivos del área y números de `Metas.md`).
public struct RitmoArea: Sendable, Hashable, Identifiable {
    public var id: AreaCode { area }
    public let area: AreaCode
    public let estado: Estado
    /// El número que marca el ritmo (el más atrasado).
    public let marca: String?
    /// «VEN-WON · 660 € de 6000 €», «Ninguna cifra con meta», «Se activa más adelante».
    public let frase: String
    /// Real / esperado del número más atrasado que tiene porcentaje (para el cuello).
    public let pct: Int?

    public enum Estado: String, Sendable, Hashable {
        case enRitmo, atencion, enAlerta, sinMeta, sinDato, enReposo

        public var etiqueta: String {
            switch self {
            case .enRitmo: "En ritmo"
            case .atencion: "Atención"
            case .enAlerta: "En alerta"
            case .sinMeta: "Sin meta"
            case .sinDato: "Sin dato"
            case .enReposo: "En reposo"
            }
        }

        init(_ r: EstadoRitmo) {
            switch r {
            case .adelantado, .enRitmo: self = .enRitmo
            case .atencion: self = .atencion
            case .enRiesgo, .critico: self = .enAlerta
            case .sinDato: self = .sinDato
            case .sinMeta: self = .sinMeta
            }
        }
    }
}

/// El ritmo de la empresa (Programa `ritmo_empresa`).
public struct RitmoEmpresa: Sendable, Hashable {
    /// Media de los ritmos de los objetivos con dato, cada uno capado a 100 (ir sobrado en uno no tapa ir corto en otro).
    public let pct: Int?
    public let enRiesgo: Int
    public let sinDato: Int
    public let objetivos: Int
    public let estado: EstadoRitmo
}

/// Pace: objetivos medidos en su periodo y el ritmo de cada área.
public struct RitmoCalculador: Sendable {
    public let evaluador: KPIEvaluador

    public init(evaluador: KPIEvaluador) { self.evaluador = evaluador }

    public var hoy: LocalDate { evaluador.hoy }

    /// Los objetivos vivos, cada uno con su ritmo (los terminados o aplazados no). `excepto`: sin los que mide ese
    /// código (DIR-OBJ se calcula con los demás objetivos, nunca consigo mismo).
    public func objetivos(excepto codigo: String? = nil) -> [RitmoObjetivo] {
        evaluador.foto.objetivosVivos.filter { codigo == nil || $0.medidoPor != codigo?.uppercased() }.map(ritmo(de:))
    }

    public func ritmo(de o: FotoMetricas.Objetivo) -> RitmoObjetivo {
        if o.medidoPor == "DIR-OBJ" {
            // Objetivo sobre los objetivos: se mide con los demás (nunca consigo mismo).
            let otros = RitmoCalculador(evaluador: evaluador).objetivos(excepto: "DIR-OBJ").filter { $0.estado.medible }
            guard !otros.isEmpty, let meta = o.meta else {
                return RitmoObjetivo(objetivo: o, estado: o.meta == nil ? .sinMeta : .sinDato, real: nil, esperado: nil, diasTotal: nil,
                                     diasPasados: nil, diasRestantes: nil, pct: nil, avancePct: nil, falta: nil,
                                     motivo: "Sin dato: ningún otro objetivo tiene número y dato")
            }
            let real = KPIEvaluador.redondear(100 * Double(otros.filter { $0.estado.enTrayectoria }.count) / Double(otros.count), 1)
            return RitmoObjetivo(objetivo: o, estado: EstadoRitmo.desde(real: real, esperado: meta, meta: meta), real: real,
                                 esperado: meta, diasTotal: nil, diasPasados: nil, diasRestantes: o.hasta.map { RangoFechas.diasEntre(hoy, $0) },
                                 pct: meta > 0 ? Int((100 * real / meta).rounded()) : nil,
                                 avancePct: meta > 0 ? Int((100 * real / meta).rounded()) : nil,
                                 falta: max(0, meta - real), motivo: nil)
        }
        func sin(_ e: EstadoRitmo, _ motivo: String) -> RitmoObjetivo {
            RitmoObjetivo(objetivo: o, estado: e, real: nil, esperado: nil, diasTotal: nil, diasPasados: nil, diasRestantes: nil,
                          pct: nil, avancePct: nil, falta: nil, motivo: motivo)
        }
        guard let meta = o.meta, let desde = o.desde, let hasta = o.hasta, let codigo = o.medidoPor else {
            return sin(.sinMeta, "Sin número: le falta meta, periodo o el número que lo mide")
        }
        let diasTotal = max(1, RangoFechas.diasEntre(desde, hasta) + 1)
        let diasPasados = max(0, min(RangoFechas.diasEntre(desde, hoy) + 1, diasTotal))
        let diasRestantes = RangoFechas.diasEntre(hoy, hasta)
        let def = evaluador.catalogo.kpi(codigo)
        // Los que se suman se miden dentro del periodo del objetivo; los de nivel, a día de hoy.
        let acumula = o.acumulado || (def?.acumulable ?? false)
        let rango: RangoFechas? = acumula ? RangoFechas(desde: desde, hasta: min(hoy, hasta)) : nil
        if acumula, hoy < desde {
            return RitmoObjetivo(objetivo: o, estado: .enRitmo, real: nil, esperado: 0, diasTotal: diasTotal, diasPasados: 0,
                                 diasRestantes: diasRestantes, pct: nil, avancePct: nil, falta: meta, motivo: "Aún no ha empezado")
        }
        let (medida, _) = evaluador.medir(codigo, rango: rango)
        guard let real = medida.numero else {
            return sin(.sinDato, medida.motivoSinDato.map { "Sin dato: \($0)" } ?? "Sin dato")
        }
        let esperado = o.acumulado ? KPIEvaluador.redondear(meta * Double(diasPasados) / Double(diasTotal), 2) : meta
        let menos = (def?.sentido ?? .mas) == .menos
        let estado: EstadoRitmo
        let pct: Int?
        if menos {
            // Menos es mejor (p. ej. tareas vencidas): en ritmo si no pasa de lo esperado.
            pct = real > 0 ? Int((100 * esperado / real).rounded()) : nil
            estado = real <= esperado ? .enRitmo : EstadoRitmo.desde(real: esperado, esperado: real, meta: .infinity)
        } else {
            pct = esperado > 0 ? Int((100 * real / esperado).rounded()) : nil
            estado = EstadoRitmo.desde(real: real, esperado: esperado, meta: meta)
        }
        return RitmoObjetivo(objetivo: o, estado: estado, real: real, esperado: esperado, diasTotal: diasTotal,
                             diasPasados: diasPasados, diasRestantes: diasRestantes, pct: pct,
                             avancePct: meta != 0 ? Int((100 * real / meta).rounded()) : nil,
                             falta: menos ? max(0, real - meta) : max(0, KPIEvaluador.redondear(meta - real, 2)), motivo: nil)
    }

    /// Ritmo de la empresa entera.
    public func empresa() -> RitmoEmpresa {
        let objs = objetivos().filter { $0.estado != .sinMeta }
        let conPct = objs.compactMap(\.pct)
        let media = conPct.isEmpty ? nil : Int((Double(conPct.map { min(100, $0) }.reduce(0, +)) / Double(conPct.count)).rounded())
        let medibles = objs.map(\.estado).filter(\.medible)
        let estado: EstadoRitmo
        if medibles.contains(.critico) { estado = .critico }
        else if medibles.contains(.enRiesgo) { estado = .enRiesgo }
        else if medibles.contains(.atencion) { estado = .atencion }
        else if medibles.isEmpty { estado = .sinDato }
        else if (conPct.min() ?? 0) >= 105 { estado = .adelantado }
        else { estado = .enRitmo }
        return RitmoEmpresa(pct: media, enRiesgo: objs.filter { $0.estado == .enRiesgo || $0.estado == .critico }.count,
                            sinDato: objs.filter { $0.estado == .sinDato }.count, objetivos: objs.count, estado: estado)
    }

    /// El ritmo de cada área: el de su número más atrasado.
    public func areas(kpis: [ValorKPI]? = nil) -> [RitmoArea] {
        let valores = kpis ?? evaluador.todos()
        let objs = objetivos()
        return AreaCode.allCases.map { area(of: $0, kpis: valores, objetivos: objs) }
    }

    public func area(of a: AreaCode, kpis: [ValorKPI], objetivos: [RitmoObjetivo]) -> RitmoArea {
        if evaluador.foto.enReposo(a) {
            return RitmoArea(area: a, estado: .enReposo, marca: nil, frase: "En reposo", pct: nil)
        }
        struct Candidato { let codigo: String; let estado: EstadoRitmo; let frase: String; let pct: Int? }
        var candidatos: [Candidato] = []
        for k in kpis where k.area == a {
            let frase: String
            if let n = k.medida.numero {
                frase = "\(k.indicador): \(KPIEvaluador.formatear(n, unidad: k.unidad))" + (k.meta.fijado ? " (meta \(k.meta.textoVisible))" : "")
            } else {
                frase = "\(k.indicador): sin dato"
            }
            candidatos.append(Candidato(codigo: k.codigo, estado: k.ritmo.estado, frase: frase, pct: k.ritmo.pct))
        }
        for o in objetivos where o.objetivo.area == a {
            let frase: String
            if let real = o.real, let meta = o.objetivo.meta {
                let u = o.unidad
                frase = "\(o.objetivo.titulo): \(KPIEvaluador.formatear(real, unidad: u.isEmpty ? "n" : u)) de \(KPIEvaluador.formatear(meta, unidad: u.isEmpty ? "n" : u))"
            } else {
                frase = "\(o.objetivo.titulo): \(o.estado.etiqueta.lowercased())"
            }
            candidatos.append(Candidato(codigo: o.objetivo.medidoPor ?? o.objetivo.titulo, estado: o.estado, frase: frase, pct: o.pct))
        }
        let medibles = candidatos.filter { $0.estado.medible }
        guard let peor = medibles.max(by: { a, b in
            a.estado.retraso != b.estado.retraso ? a.estado.retraso < b.estado.retraso : (a.pct ?? 1000) > (b.pct ?? 1000)
        }) else {
            if candidatos.contains(where: { $0.estado == .sinDato }) {
                return RitmoArea(area: a, estado: .sinDato, marca: nil, frase: "Sus números aún no tienen dato", pct: nil)
            }
            return RitmoArea(area: a, estado: .sinMeta, marca: nil,
                             frase: candidatos.isEmpty ? "Ningún número del área en Metas" : "Ningún número del área tiene meta", pct: nil)
        }
        let pcts = medibles.compactMap(\.pct)
        return RitmoArea(area: a, estado: RitmoArea.Estado(peor.estado), marca: peor.codigo, frase: peor.frase, pct: pcts.min())
    }
}
