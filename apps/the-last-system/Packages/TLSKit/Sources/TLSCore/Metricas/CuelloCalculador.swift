// Procedencia: port reescrito de Programa v0.5 (Manu): core/sql/05-diseno.sql (`cuello_botella`: presión =
// (100 − ritmo) + rotas × 25 + flojas × 10 + a mano × 3, y su motivo), core/madurez.js (`matriz` y `camino`: primero lo
// que desbloquea a lo demás) y core/consultoria.js (el veredicto determinista). Ver docs/PROCEDENCIA.md.
import Foundation

/// Cuánto frena un área al resto.
public struct PresionArea: Sendable, Hashable, Identifiable {
    public var id: AreaCode { area }
    public let area: AreaCode
    /// Ritmo del área en % (100 si ningún número suyo tiene porcentaje).
    public let ritmo: Int
    public let etapa: Int
    public let progreso: Double
    public let rotas: Int
    public let flojas: Int
    public let manuales: Int
    public let presion: Double
    public let motivo: String

    public static let sinSenales = "sin señales de bloqueo"
    public var bloquea: Bool { motivo != Self.sinSenales }
}

/// Un tramo del camino: en qué orden se arreglan las áreas y qué deja cada una a la siguiente.
public struct TramoCamino: Sendable, Hashable, Identifiable {
    public var id: AreaCode { area }
    public let orden: Int
    public let area: AreaCode
    public let etapa: Int
    public let progreso: Double
    public let esCuello: Bool
    public let porque: String
    public let entrada: String
    public let salida: String
}

/// El mapa 6 × 6 (áreas × etapas) con el cuello en texto.
public struct MapaMadurez: Sendable, Hashable {
    public let etapas: [EtapaStd]
    public let filas: [EtapaArea]
    public let presiones: [PresionArea]
    public let cuello: PresionArea?
    public let empresa: EtapaEmpresa
    public let camino: [TramoCamino]
    /// «El cuello es 2 · Ventas: su objetivo va en riesgo.» o «Ningún área da señales de bloqueo ahora mismo.»
    public let textoCuello: String
    /// El diagnóstico en un párrafo, sin asistente.
    public let veredicto: String

    /// La celda (área, etapa) es la de esa área.
    public func marcada(_ a: AreaCode, etapa: Int) -> Bool { filas.first { $0.area == a }?.etapa == etapa }
}

/// El cuello de botella: no el área que peor funciona, sino la que más bloquea al resto.
public struct CuelloCalculador: Sendable {
    public let foto: FotoMetricas
    public let etapas: [EtapaArea]
    public let empresa: EtapaEmpresa
    public let salud: [SenalSalud]
    public let ritmos: [RitmoArea]
    public let chequeos: [ResultadoChequeo]
    public let catalogo: CatalogoPrograma
    public let evaluador: KPIEvaluador

    public init(evaluador: KPIEvaluador, etapas: [EtapaArea], empresa: EtapaEmpresa, salud: [SenalSalud], ritmos: [RitmoArea],
                chequeos: [ResultadoChequeo], catalogo: CatalogoPrograma = .deSerie) {
        self.evaluador = evaluador; self.foto = evaluador.foto; self.etapas = etapas; self.empresa = empresa
        self.salud = salud; self.ritmos = ritmos; self.chequeos = chequeos; self.catalogo = catalogo
    }

    /// Orden de la cadena de valor (madurez.js): a igualdad, se toca antes lo que va antes en la cadena.
    static let cadena: [AreaCode] = [.ventas, .entrega, .finanzas, .equipo, .direccion, .marca]

    /// La presión de cada área (las que están en reposo no cuentan), de más a menos.
    public func presiones() -> [PresionArea] {
        let areas = AreaCode.allCases.filter { !foto.enReposo($0) }
        let out = areas.map { a -> PresionArea in
            let e = etapas.first { $0.area == a }
            let ritmo = ritmos.first { $0.area == a }?.pct ?? 100
            let senales = salud.filter { $0.area == a }
            let rotas = senales.filter { $0.estado == .mal }
            let flojas = senales.filter { $0.estado == .atencion }
            let manuales = e?.manuales ?? 0
            let presion = Double(100 - min(ritmo, 100)) + Double(rotas.count) * 25 + Double(flojas.count) * 10 + Double(manuales) * 3
            let motivo: String
            if let r = rotas.first { motivo = r.detalle ?? r.dimension.etiqueta.lowercased() }
            else if ritmo < 80 { motivo = "por debajo del ritmo necesario para su meta" }
            else if let f = flojas.first { motivo = f.detalle ?? f.dimension.etiqueta.lowercased() }
            else if manuales > 3 { motivo = "demasiado trabajo todavía a mano" }
            else { motivo = PresionArea.sinSenales }
            return PresionArea(area: a, ritmo: ritmo, etapa: e?.etapa ?? 1, progreso: e?.progreso ?? 1, rotas: rotas.count,
                               flojas: flojas.count, manuales: manuales, presion: presion, motivo: motivo)
        }
        return out.enumerated().sorted { x, y in
            x.element.presion != y.element.presion ? x.element.presion > y.element.presion : x.offset < y.offset
        }.map(\.element)
    }

    /// El cuello de verdad: el primero con un motivo (un área con «sin señales de bloqueo» no es un cuello).
    public func cuello(_ p: [PresionArea]? = nil) -> PresionArea? {
        (p ?? presiones()).first(where: \.bloquea)
    }

    public static func textoCuello(_ c: PresionArea?) -> String {
        guard let c else { return "Ningún área da señales de bloqueo ahora mismo." }
        return "El cuello es \(c.area.numero) · \(c.area.nombre): \(c.motivo)."
    }

    public func mapa() -> MapaMadurez {
        let p = presiones()
        let c = cuello(p)
        let camino = self.camino(presiones: p, cuello: c)
        return MapaMadurez(etapas: catalogo.etapas, filas: etapas, presiones: p, cuello: c, empresa: empresa, camino: camino,
                           textoCuello: Self.textoCuello(c), veredicto: veredicto(cuello: c))
    }

    /// El camino: manda el cuello; después lo más atrasado y, a igualdad, la cadena de valor.
    public func camino(presiones p: [PresionArea], cuello c: PresionArea?) -> [TramoCamino] {
        let hoy = foto.hoy
        let abiertas = foto.oportunidades.filter { $0.abierta && ($0.creada.map { $0 <= hoy } ?? true) }
        let eurAbierto = abiertas.compactMap(\.valor).reduce(0, +)
        let quietas = abiertas.filter { ($0.diasQuieta(hoy: hoy) ?? 0) > 14 }.count
        let enMarcha = foto.proyectos.filter { $0.estado == .enCurso || $0.estado == .sinEmpezar }.count
        let tarde = foto.proyectos.filter { ($0.estado?.abierto ?? true) && ($0.fin.map { $0 < hoy } ?? false) }.count
        let vencido = foto.facturas.filter { f in f.vence.map { $0 < hoy } ?? false }.compactMap { evaluador.pendiente($0) }.reduce(0, +)

        func entrada(_ a: AreaCode) -> String {
            switch a {
            case .ventas:
                return "Hoy hay \(abiertas.count == 1 ? "1 oportunidad abierta" : "\(abiertas.count) oportunidades abiertas") por \(FormatoBase.euros(eurAbierto, redondo: true))"
                    + (quietas > 0 ? (quietas == 1 ? ", y 1 lleva más de dos semanas sin contacto." : ", y \(quietas) llevan más de dos semanas sin contacto.") : ".")
            case .entrega:
                return "\(enMarcha == 1 ? "1 proyecto en marcha" : "\(enMarcha) proyectos en marcha")"
                    + (tarde > 0 ? ", \(tarde) fuera de fecha." : ", ninguno fuera de fecha.")
            case .finanzas:
                return "Con la venta y la entrega ordenadas ya hay datos que analizar"
                    + (vencido > 0 ? "; ahora mismo hay \(FormatoBase.euros(vencido)) vencidos sin cobrar." : ".")
            case .equipo: return "Con los márgenes sobre la mesa se ve qué aporta cada persona y qué perfil falta."
            case .direccion: return "Con las áreas ordenadas y los datos llegando solos, dejas de ser imprescindible."
            case .marca: return "Con el sistema en uso y la entrega sólida, la marca puede prometer sin miedo."
            }
        }
        func salida(_ a: AreaCode) -> String {
            switch a {
            case .ventas: "Un seguimiento que no pierde ninguna, y saber de dónde sale el próximo cliente."
            case .entrega: "Se entrega igual cada vez y sin ti dentro, que es lo que libera tiempo para vender."
            case .finanzas: "Margen real por cliente y por servicio, y saber cuántos meses aguanta la empresa."
            case .equipo: "Roles con criterio escrito: lo que no está escrito no se delega."
            case .direccion: "Rutinas y números para dirigir, y soltar el día a día."
            case .marca: "Que te conozcan antes de hablar contigo."
            }
        }
        func puntos(_ x: PresionArea) -> Double {
            (c?.area == x.area ? -100 : 0) + x.progreso * 10 + Double(Self.cadena.firstIndex(of: x.area) ?? 0) * 1.5
                + (x.rotas > 0 ? -8 : 0)
        }
        let orden = p.sorted { puntos($0) < puntos($1) }
        return orden.enumerated().map { i, x in
            let porque: String
            if c?.area == x.area { porque = "Es el cuello: \(x.motivo)" }
            else if x.rotas > 0 { porque = x.rotas == 1 ? "1 señal mal en el área" : "\(x.rotas) señales mal en el área" }
            else if x.progreso < 3 { porque = "Todavía no está escrito lo que ya se hace" }
            else if x.progreso < 4 { porque = "Escrito pero sin quien lo haga ni rutina" }
            else if x.progreso < 5 { porque = "Se hace a mano lo que se decide siempre igual" }
            else { porque = "Falta un dueño distinto de ti" }
            return TramoCamino(orden: i + 1, area: x.area, etapa: x.etapa, progreso: x.progreso, esCuello: c?.area == x.area,
                               porque: porque, entrada: entrada(x.area), salida: salida(x.area))
        }
    }

    /// Una frase de diagnóstico, determinista (sin asistente).
    public func veredicto(cuello c: PresionArea?) -> String {
        let graves = chequeos.filter(\.esRojo)
        let casos = graves.map(\.n).reduce(0, +)
        var t = empresa.porque + " "
        t += c.map { "Lo que más pesa hoy es \($0.area.nombre): \($0.motivo). " } ?? "Ningún área da señales de bloqueo ahora mismo. "
        // Las mismas palabras que Hoy (revisión final de F2): lo que se incumple está en sus Alertas; sin «regla dura».
        guard casos > 0 else { return t + "Ninguna regla básica se incumple ahora mismo." }
        let reglas = graves.count == 1 ? "1 regla básica se incumple" : "\(graves.count) reglas básicas se incumplen"
        return t + "Y \(reglas) (\(casos == 1 ? "1 caso" : "\(casos) casos")): las tienes en las Alertas de Hoy."
    }
}
