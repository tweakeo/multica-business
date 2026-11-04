import Foundation

/// Algo en rojo para la sección Alertas de Hoy (que solo existe si hay alguna).
public struct AlertaHoy: Sendable, Hashable, Identifiable {
    public var id: String { origen }
    /// `numero:VEN-WON` o `regla:VEN-03`.
    public let origen: String
    public let area: AreaCode?
    /// «2 · Ventas · Ventas cobradas del mes: 660 € (alerta en 3000 €)».
    public let texto: String
    public let ruta: VaultPath?
}

/// Todo lo que calculan las métricas a la vez, con un solo reloj: lo que necesitan Hoy, las áreas y su Control.
///
/// Determinista y sin asistentes: la línea de Mika y los chequeos son reglas (los asistentes llegan después).
public struct PanelMetricas: Sendable {
    public let hoy: LocalDate
    public let foto: FotoMetricas
    public let metas: MetasDocumento?
    public let evaluador: KPIEvaluador
    public let kpis: [ValorKPI]
    public let objetivos: [RitmoObjetivo]
    public let ritmoAreas: [RitmoArea]
    public let ritmoEmpresa: RitmoEmpresa
    public let etapas: [EtapaArea]
    public let etapaEmpresa: EtapaEmpresa
    public let chequeos: [ResultadoChequeo]
    public let salud: [SenalSalud]
    public let mapa: MapaMadurez
    public let semana: SemanaAgenda
    public let mazo: Mazo
    /// Vacía si no hay nada en rojo: entonces la sección Alertas no existe.
    public let alertas: [AlertaHoy]

    /// El foco de hoy: siempre exactamente uno.
    public var foco: Tarjeta { mazo.foco }
    public var hayRojo: Bool { !alertas.isEmpty }
    /// Decisiones y preguntas abiertas (fichas de tarea `tipo: decision | pregunta`).
    public var decisionesAbiertas: Int { foto.decisionesAbiertas.filter { $0.tarea.creada.map { $0 <= hoy } ?? true }.count }

    /// Calcula todo con el reloj de la carpeta (en la demo, `hoy:` de `.tls/config.yaml`) y la zona de `agenda.zona`.
    public static func calcular(snapshot: VaultSnapshot, reloj: Reloj? = nil, catalogo: CatalogoPrograma = .deSerie,
                                eventos: [EventoAgenda] = [], estados: [EstadoTarjeta] = [],
                                historial: [DecisionTarjeta] = []) -> PanelMetricas {
        let config = ConfigMetricas.leer(snapshot.text(VaultPath(".tls/config.yaml")))
        let zona = TimeZone(identifier: config.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
        let r = reloj ?? Reloj.deCarpeta(snapshot, zona: zona)
        let foto = FotoMetricas(snapshot: snapshot, hoy: r.hoy, ahora: r.ahora)
        return PanelMetricas(foto: foto, metas: MetasDocumento.leer(snapshot), catalogo: catalogo, eventos: eventos,
                             estados: estados, historial: historial)
    }

    public init(foto: FotoMetricas, metas: MetasDocumento?, catalogo: CatalogoPrograma = .deSerie, eventos: [EventoAgenda] = [],
                estados: [EstadoTarjeta] = [], historial: [DecisionTarjeta] = []) {
        self.hoy = foto.hoy
        self.foto = foto
        self.metas = metas
        let evaluador = KPIEvaluador(foto: foto, catalogo: catalogo, metas: metas)
        self.evaluador = evaluador
        let kpis = evaluador.todos()
        self.kpis = kpis
        let ritmo = RitmoCalculador(evaluador: evaluador)
        let objetivos = ritmo.objetivos()
        self.objetivos = objetivos
        let ritmoAreas = AreaCode.allCases.map { ritmo.area(of: $0, kpis: kpis, objetivos: objetivos) }
        self.ritmoEmpresa = ritmo.empresa()
        let etapaCalc = EtapaCalculador(foto: foto, catalogo: catalogo)
        let etapas = etapaCalc.areas()
        self.etapas = etapas
        let empresa = etapaCalc.empresa(etapas)
        self.etapaEmpresa = empresa
        let semana = Agenda(foto: foto, eventos: eventos).semana()
        self.semana = semana
        let chequeos = Chequeo(foto: foto, metas: metas, semana: semana).todos()
        self.chequeos = chequeos
        let salud = SaludCalculador(evaluador: evaluador, objetivos: objetivos, kpis: kpis, etapas: etapas, chequeos: chequeos).senales()
        self.salud = salud
        let cuello = CuelloCalculador(evaluador: evaluador, etapas: etapas, empresa: empresa, salud: salud, ritmos: ritmoAreas,
                                      chequeos: chequeos, catalogo: catalogo)
        let mapa = cuello.mapa()
        self.mapa = mapa
        self.mazo = TarjetaBuilder(evaluador: evaluador, objetivos: objetivos, presiones: mapa.presiones, etapas: etapas,
                                   estados: estados, historial: historial, catalogo: catalogo).mazo()
        let alertas = Self.alertas(kpis: kpis, chequeos: chequeos, foto: foto)
        self.alertas = alertas
        // «Rojo» significa una sola cosa (revisión final de F2): un área va «En alerta» (✖) solo si tiene algo en la
        // sección Alertas; un ritmo en riesgo o crítico que no ha cruzado su alerta se enseña como «Atención». El cuello
        // sigue mirando el ritmo tal cual.
        let conAlerta = Set(alertas.compactMap(\.area))
        self.ritmoAreas = ritmoAreas.map { r in
            guard r.estado == .enAlerta, !conAlerta.contains(r.area) else { return r }
            return RitmoArea(area: r.area, estado: .atencion, marca: r.marca, frase: r.frase, pct: r.pct)
        }
    }

    /// ¿Tiene este área algo en la sección Alertas? (Lo único que se pinta en rojo con ✖.)
    public func enAlerta(_ a: AreaCode) -> Bool { alertas.contains { $0.area == a } }

    /// ¿Ha cruzado este número su alerta (está en la sección Alertas)?
    public func enAlerta(codigo: String) -> Bool { alertas.contains { $0.origen == "numero:" + codigo.uppercased() } }

    /// Lo que está en rojo: números en alerta (con meta y alerta escritas) y reglas duras rotas.
    static func alertas(kpis: [ValorKPI], chequeos: [ResultadoChequeo], foto: FotoMetricas) -> [AlertaHoy] {
        var out: [AlertaHoy] = []
        for k in kpis where k.estado == .mal && !(k.area.map(foto.enReposo) ?? false) {
            let area = k.area.map { "\($0.numero) · \($0.nombre) · " } ?? ""
            out.append(AlertaHoy(origen: "numero:\(k.codigo)", area: k.area,
                                 texto: "\(area)\(k.indicador): \(k.textoValor) (alerta en \(k.alerta.textoVisible))", ruta: nil))
        }
        for c in chequeos where c.esRojo {
            // Las reglas de todas las áreas (tareas vencidas…) toman el área de su primer caso.
            let deArea = c.area ?? c.casos.lazy.compactMap { $0.ruta.flatMap(foto.layout.area(of:)) }.first
            if let a = deArea, foto.enReposo(a) { continue }
            let area = deArea.map { "\($0.numero) · \($0.nombre) · " } ?? ""
            out.append(AlertaHoy(origen: "regla:\(c.codigo)", area: deArea,
                                 texto: "\(area)\(c.titulo): \(c.n == 1 ? "1 caso" : "\(c.n) casos")", ruta: c.casos.first?.ruta))
        }
        return out
    }

    /// Cabecera de Hoy: «2 cosas piden tu decisión. Hoy tienes 3 h de 4.»
    public func frase(decisiones: Int? = nil) -> String {
        let n = decisiones ?? decisionesAbiertas
        let d = n == 0 ? "Nada pide tu decisión." : n == 1 ? "1 cosa pide tu decisión." : "\(n) cosas piden tu decisión."
        return "\(d) \(semana.fraseHoy)."
    }

    /// La línea de Mika (determinista): «Revisé a las 8:45: nada en rojo.»
    public func lineaMika(hora: String = "8:45") -> String {
        if hoy.isWeekend { return "Los fines de semana no reviso: el lunes a las \(hora) vuelvo a mirar." }
        guard hayRojo else { return "Revisé a las \(hora): nada en rojo." }
        var areas: [String] = []
        for a in alertas {
            let nombre = a.area?.nombre ?? "sin área"
            if !areas.contains(nombre) { areas.append(nombre) }
        }
        let lista = areas.count == 1 ? areas[0] : areas.dropLast().joined(separator: ", ") + " y " + areas.last!
        let cosas = alertas.count == 1 ? "1 cosa en rojo" : "\(alertas.count) cosas en rojo"
        return "Revisé a las \(hora): \(cosas) (\(lista))."
    }

    /// Los números de un área para su pestaña Control.
    public func control(_ a: AreaCode) -> [ValorKPI] { kpis.filter { $0.area == a } }
    public func ritmo(_ a: AreaCode) -> RitmoArea? { ritmoAreas.first { $0.area == a } }
    public func etapa(_ a: AreaCode) -> EtapaArea? { etapas.first { $0.area == a } }
    public func salud(_ a: AreaCode) -> [SenalSalud] { salud.filter { $0.area == a } }
}
