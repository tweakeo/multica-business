// Procedencia: port reescrito de Programa v0.5 (Manu), core/salud.js (`calcularSalud`: seis dimensiones por área,
// una regla por dimensión y, cuando no hay con qué juzgar, una señal de que falta el dato en vez de un «bien»).
// Se adapta a las fichas: los objetivos y los números de Metas.md del área cuentan en Resultado y Ritmo, y un
// objetivo sin dato no se trata como un 0 (regla de PLAN: nunca 0 inventado). Ver docs/PROCEDENCIA.md.
import Foundation

/// Una señal de salud de un área en una dimensión.
public struct SenalSalud: Sendable, Hashable, Identifiable {
    public var id: String { "\(area.rawValue)·\(dimension.rawValue)" }
    public let area: AreaCode
    public let dimension: Dimension
    public let estado: Estado
    /// Qué pasa, dicho como se lo dirías a alguien. `nil` cuando está bien.
    public let detalle: String?
    /// La señal sale de que falta un dato, no de un dato malo.
    public let porFaltaDeDato: Bool

    public enum Dimension: String, Sendable, Hashable, CaseIterable {
        case resultado = "Resultado", ritmo = "Ritmo", capacidad = "Capacidad", automatizaciones = "Automatizaciones"
        case datos = "Datos", pipeline = "Flujo"

        public var etiqueta: String { rawValue }
    }

    public enum Estado: String, Sendable, Hashable {
        case bien, atencion, mal

        public var etiqueta: String {
            switch self {
            case .bien: "Bien"
            case .atencion: "Atención"
            case .mal: "Mal"
            }
        }
    }
}

/// La salud de cada área, calculada de los datos (antes era una tabla que alguien rellenaba a mano).
public struct SaludCalculador: Sendable {
    public let foto: FotoMetricas
    public let objetivos: [RitmoObjetivo]
    public let kpis: [ValorKPI]
    public let etapas: [EtapaArea]
    public let chequeos: [ResultadoChequeo]
    public let evaluador: KPIEvaluador

    public init(evaluador: KPIEvaluador, objetivos: [RitmoObjetivo], kpis: [ValorKPI], etapas: [EtapaArea], chequeos: [ResultadoChequeo]) {
        self.evaluador = evaluador; self.foto = evaluador.foto; self.objetivos = objetivos; self.kpis = kpis
        self.etapas = etapas; self.chequeos = chequeos
    }

    var hoy: LocalDate { foto.hoy }

    /// Las señales de todas las áreas (menos las que están en reposo).
    public func senales() -> [SenalSalud] {
        AreaCode.allCases.filter { !foto.enReposo($0) }.flatMap(delArea)
    }

    public func delArea(_ a: AreaCode) -> [SenalSalud] {
        var out: [SenalSalud] = []
        func s(_ d: SenalSalud.Dimension, _ e: SenalSalud.Estado, _ detalle: String?, falta: Bool = false) {
            out.append(SenalSalud(area: a, dimension: d, estado: e, detalle: detalle, porFaltaDeDato: falta))
        }

        // Resultado y Ritmo: los objetivos del área y sus números de Metas.
        let objs = objetivos.filter { $0.objetivo.area == a && $0.estado != .sinMeta }
        let medibles = objs.filter { $0.estado.medible }
        let malosObj = medibles.filter { $0.estado == .enRiesgo || $0.estado == .critico }
        let delArea = kpis.filter { $0.area == a }
        let malosKPI = delArea.filter { $0.estado == .mal }
        let conMetaYDato = delArea.filter { $0.estado == .bien || $0.estado == .atencion || $0.estado == .mal }
        if !malosObj.isEmpty {
            s(.resultado, .mal, malosObj.count == 1 && medibles.count == 1 ? "su objetivo va en riesgo"
              : "\(malosObj.count) de \(medibles.count) objetivos del área en riesgo")
        } else if let k = malosKPI.first {
            s(.resultado, .mal, malosKPI.count == 1 ? "\(k.indicador.lowercased()) en alerta" : "\(malosKPI.count) números del área en alerta")
        } else if medibles.isEmpty && conMetaYDato.isEmpty {
            s(.resultado, .atencion, objs.isEmpty ? "sin objetivo ni número con meta: no hay forma de decir si el área va bien"
              : "su objetivo aún no tiene dato", falta: true)
        } else {
            s(.resultado, .bien, nil)
        }
        let pcts = medibles.compactMap(\.pct) + delArea.compactMap { $0.ritmo.estado.medible ? $0.ritmo.pct : nil }
        if let r = pcts.min() {
            s(.ritmo, r >= 90 ? .bien : r >= 70 ? .atencion : .mal, r >= 90 ? nil : "al \(r) % del ritmo que necesita para llegar")
        }

        // Capacidad: lo abierto frente a lo que cabe.
        let abiertas = foto.tareas.filter { t in t.abierta && !t.esDecision && t.tarea.area == a && (t.tarea.creada.map { $0 <= hoy } ?? true) }
        if !abiertas.isEmpty {
            let atrasadas = abiertas.filter { $0.tarea.planificada.map { $0 < hoy } ?? false }.count
            let horas = abiertas.compactMap(\.estimacionH).reduce(0, +)
            let tope = foto.config.topeHorasDia
            var detalle: String?
            if atrasadas > 0 {
                detalle = atrasadas == 1 ? "1 tarea pasada de fecha" : "\(atrasadas) tareas pasadas de fecha"
                if horas > 0, tope > 0 {
                    let dias = (horas / tope * 10).rounded() / 10
                    detalle! += " · \(FormatoBase.cifra(dias, decimales: dias == dias.rounded() ? 0 : 1)) días de trabajo abierto"
                }
            }
            s(.capacidad, atrasadas > 5 ? .mal : atrasadas > 0 ? .atencion : .bien, detalle)
        }

        // Automatizaciones: qué funciona sin ti, de lo declarado.
        if let e = etapas.first(where: { $0.area == a }) {
            if e.activas > 0, let pct = e.pctAuto {
                s(.automatizaciones, pct >= 60 ? .bien : pct >= 30 ? .atencion : .mal, pct >= 60 ? nil : "solo el \(pct) % de lo declarado funciona sin ti")
            } else {
                s(.automatizaciones, .atencion, "nada declarado todavía en esta área", falta: true)
            }
        }

        // Datos: lo que rompe una regla en esta área.
        let rotas = Chequeo.ordenar(chequeos.filter { $0.area == a && $0.n > 0 && $0.nivel != .info })
        let graves = rotas.filter { $0.nivel == .grave }
        if let g = graves.first {
            s(.datos, .mal, "\(g.titulo.lowercased()) · \(g.n == 1 ? "1 caso" : "\(g.n) casos")")
        } else if let f = rotas.first {
            s(.datos, .atencion, "\(f.titulo.lowercased()) · \(f.n == 1 ? "1 caso" : "\(f.n) casos")")
        } else {
            s(.datos, .bien, nil)
        }

        // Flujo propio de cada área.
        switch a {
        case .ventas:
            let ops = foto.oportunidades.filter { $0.abierta && ($0.creada.map { $0 <= hoy } ?? true) }
            let quietas = ops.filter { ($0.diasQuieta(hoy: hoy) ?? 0) > 14 }.count
            if foto.oportunidades.isEmpty {
                // Sin ninguna ficha de oportunidad no hay con qué juzgar el embudo: falta el dato.
                s(.pipeline, .atencion, "aún no hay oportunidades", falta: true)
            } else if ops.isEmpty {
                s(.pipeline, .mal, "ninguna oportunidad abierta: el embudo está vacío")
            } else {
                s(.pipeline, quietas > 2 ? .mal : quietas > 0 ? .atencion : .bien,
                  quietas == 0 ? nil : quietas == 1 ? "1 oportunidad lleva más de dos semanas sin contacto"
                  : "\(quietas) oportunidades llevan más de dos semanas sin contacto")
            }
        case .entrega:
            guard !foto.proyectos.isEmpty else { break }
            let tarde = foto.proyectos.filter { ($0.estado?.abierto ?? true) && ($0.fin.map { $0 < hoy } ?? false) }.count
            s(.pipeline, tarde > 1 ? .mal : tarde == 1 ? .atencion : .bien,
              tarde == 0 ? nil : tarde == 1 ? "1 proyecto fuera de fecha" : "\(tarde) proyectos fuera de fecha")
        case .finanzas:
            guard foto.registros.emitidas, foto.registros.pagos else { break }
            let vencidas = foto.facturas.filter { f in
                guard let v = f.vence, v < hoy else { return false }
                return (evaluador.pendiente(f) ?? 0) > 0
            }
            let eur = vencidas.compactMap { evaluador.pendiente($0) }.reduce(0, +)
            s(.pipeline, vencidas.isEmpty ? .bien : .mal, vencidas.isEmpty ? nil
              : "\(vencidas.count == 1 ? "1 factura vencida" : "\(vencidas.count) facturas vencidas") sin cobrar · \(FormatoBase.euros(eur, redondo: true))")
        case .marca:
            guard !foto.contenidos.isEmpty else { break }
            let desde = hoy.adding(days: -30)
            let publicadas = foto.contenidos.filter { c in c.esPublicado && (c.publicado.map { $0 >= desde && $0 <= hoy } ?? false) }.count
            let paradas = foto.contenidos.filter { !$0.esPublicado }.count
            s(.pipeline, publicadas == 0 ? .mal : .bien, publicadas == 0
              ? "nada publicado en 30 días · \(paradas == 1 ? "1 pieza parada" : "\(paradas) piezas paradas") en el calendario" : nil)
        case .equipo:
            guard foto.rolesDicenOcupante else {
                s(.pipeline, .atencion, foto.roles.isEmpty ? "aún no hay fichas de rol" : "ningún rol dice quién lo ocupa", falta: true)
                break
            }
            let con = AreaCode.allCases.filter { foto.tieneDueno($0) }.count
            s(.pipeline, con == 0 ? .mal : con < 3 ? .atencion : .bien,
              con == 0 ? "ningún área tiene dueño distinto de ti" : con < 6 ? "\(6 - con) áreas siguen sin dueño distinto de ti" : nil)
        case .direccion:
            if foto.objetivos.isEmpty {
                s(.pipeline, .atencion, "aún no hay objetivos", falta: true)
                break
            }
            let vivos = foto.objetivosVivos.count
            s(.pipeline, vivos == 0 ? .mal : .bien, vivos == 0 ? "ningún objetivo vivo: sin destino no hay dirección" : nil)
        }
        return out
    }
}
