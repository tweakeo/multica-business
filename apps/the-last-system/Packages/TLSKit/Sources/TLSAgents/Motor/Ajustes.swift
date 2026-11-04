import Foundation
import TLSCore
import Yams

// Lo que el motor lee de `.tls/config.yaml` (PLAN §4.5): el interruptor, `pausa_areas` y, por asistente, si está
// activo, su área, topes de uso, modelo y rutinas. El motor nunca escribe la configuración (ni ningún asistente).
//
// De dónde sale el texto lo decide quien construye el motor (`FuenteDeAjustes`): en la app, la **última versión
// confirmada** de gobierno (`estado.sqlite.config_confirmada`, PLAN §4.5 «Cambios hechos fuera de la app»); en las
// pruebas, un texto fijo. `AjustesDeLaCarpeta` lee el fichero tal cual y solo sirve hasta que esté la de gobierno.

/// Día de la semana de una rutina (1 = lunes … 7 = domingo, como `LocalDate.weekday`).
public enum DiaSemana: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case lunes = 1, martes, miercoles, jueves, viernes, sabado, domingo

    /// «lun», «lunes», «L», «mon», «1»… (sin acentos ni mayúsculas).
    public init?(texto: String) {
        let t = TextFolding.fold(texto).trimmingCharacters(in: .whitespaces)
        switch t {
        case "l", "lu", "lun", "lunes", "mon", "monday", "1": self = .lunes
        case "m", "ma", "mar", "martes", "tue", "tuesday", "2": self = .martes
        case "x", "mi", "mie", "miercoles", "wed", "wednesday", "3": self = .miercoles
        case "j", "ju", "jue", "jueves", "thu", "thursday", "4": self = .jueves
        case "v", "vi", "vie", "viernes", "fri", "friday", "5": self = .viernes
        case "s", "sa", "sab", "sabado", "sat", "saturday", "6": self = .sabado
        case "d", "do", "dom", "domingo", "sun", "sunday", "7": self = .domingo
        default: return nil
        }
    }

    public static func < (a: DiaSemana, b: DiaSemana) -> Bool { a.rawValue < b.rawValue }

    public static let laborables: Set<DiaSemana> = [.lunes, .martes, .miercoles, .jueves, .viernes]

    public var corto: String {
        ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"][rawValue - 1]
    }
}

/// Una rutina de un asistente (`agentes.<slug>.rutinas` en `config.yaml`).
///
/// ```yaml
/// rutinas:
///   - {id: algo-rojo, nombre: "¿Algo rojo?", dias: [lun,mar,mie,jue,vie], hora: "08:45", ventana_perdida_h: 6,
///      activa: true, solo_si_rojo: true}
///   - {id: cobros, nombre: "Cobros pendientes", dia_mes: 5, hora: "09:00"}
///   - {id: gestoria, nombre: "Lista para la gestoría", dia_mes: 1, meses: [1,4,7,10], hora: "09:00"}
/// ```
/// Sin `dias` ni `dia_mes`: de lunes a viernes. `dia_mes` (1–28) manda sobre `dias`.
public struct RutinaDeAsistente: Sendable, Hashable, Codable {
    public var id: String
    public var nombre: String
    public var dias: Set<DiaSemana>
    public var diaDelMes: Int?
    /// Meses en que toca (1–12); vacío = todos.
    public var meses: Set<Int>
    public var hora: Int
    public var minuto: Int
    /// Si el Mac estaba dormido o apagado, cuántas horas después del hueco aún se lanza (la última perdida).
    public var ventanaPerdidaH: Double
    public var activa: Bool
    /// El núcleo pasa antes los chequeos y comprobaciones deterministas: solo si hay rojo se lanza el asistente
    /// («¿Algo rojo?» de Mika).
    public var soloSiHayRojo: Bool
    /// Qué hacer, en palabras (va en el primer mensaje del trabajo). Sin ella, el nombre.
    public var instruccion: String?

    public init(id: String, nombre: String? = nil, dias: Set<DiaSemana> = DiaSemana.laborables, diaDelMes: Int? = nil,
                meses: Set<Int> = [], hora: Int, minuto: Int = 0, ventanaPerdidaH: Double = 6, activa: Bool = true,
                soloSiHayRojo: Bool = false, instruccion: String? = nil) {
        self.id = id; self.nombre = nombre ?? id; self.dias = dias; self.diaDelMes = diaDelMes; self.meses = meses
        self.hora = hora; self.minuto = minuto; self.ventanaPerdidaH = ventanaPerdidaH; self.activa = activa
        self.soloSiHayRojo = soloSiHayRojo; self.instruccion = instruccion
    }

    /// `HH:MM`.
    public var horaTexto: String { String(format: "%02d:%02d", hora, minuto) }

    /// ¿Toca este día?
    public func toca(_ dia: LocalDate) -> Bool {
        if !meses.isEmpty && !meses.contains(dia.month) { return false }
        if let d = diaDelMes { return dia.day == d }
        guard let w = DiaSemana(rawValue: dia.weekday) else { return false }
        return dias.contains(w)
    }
}

/// Lo que `config.yaml` dice de un asistente (PLAN §4.5).
public struct AjustesDeAsistente: Sendable, Hashable {
    public var slug: String
    public var activo: Bool
    public var coordinador: Bool
    /// Área propia (la primera manda para el brief y para «área en reposo»).
    public var areas: [AreaCode]
    /// Áreas que puede leer (además de las suyas); `todas` = las seis.
    public var leeAreas: [AreaCode]
    public var capacidades: [String]
    public var herramientasExternas: [String]
    public var modelo: String?
    public var esfuerzo: String?
    public var maxTareasPorEjecucion: Int
    public var presupuestoEjecucionUSD: Double
    public var presupuestoMesUSD: Double
    public var rutinas: [RutinaDeAsistente]

    public init(slug: String, activo: Bool = false, coordinador: Bool = false, areas: [AreaCode] = [],
                leeAreas: [AreaCode] = [], capacidades: [String] = [], herramientasExternas: [String] = [],
                modelo: String? = nil, esfuerzo: String? = nil, maxTareasPorEjecucion: Int = 10,
                presupuestoEjecucionUSD: Double = 0.5, presupuestoMesUSD: Double = 15, rutinas: [RutinaDeAsistente] = []) {
        self.slug = slug; self.activo = activo; self.coordinador = coordinador; self.areas = areas
        self.leeAreas = leeAreas; self.capacidades = capacidades; self.herramientasExternas = herramientasExternas
        self.modelo = modelo; self.esfuerzo = esfuerzo; self.maxTareasPorEjecucion = maxTareasPorEjecucion
        self.presupuestoEjecucionUSD = presupuestoEjecucionUSD; self.presupuestoMesUSD = presupuestoMesUSD
        self.rutinas = rutinas
    }

    public var areaPropia: AreaCode? { areas.first }

    public func rutina(_ id: String) -> RutinaDeAsistente? { rutinas.first { $0.id == id } }
}

/// Los ajustes de los asistentes de una carpeta.
public struct AjustesDeAsistentes: Sendable, Hashable {
    /// `interruptor: encendido | apagado` (DIR-11). Sin la clave, encendido: sin `agentes:` no hay nadie a quien lanzar.
    public var interruptor: Bool
    public var pausaAreas: Set<AreaCode>
    public var agentes: [String: AjustesDeAsistente]
    /// `agenda.zona` (Europe/Madrid por defecto): las rutinas se calculan en esta zona.
    public var zona: TimeZone
    /// Reloj fijo de la demo (`hoy:`).
    public var hoy: LocalDate?
    public var clase: String?
    /// `avisos.tope_tarjetas_dia`: tarjetas nuevas no rojas al día (5).
    public var topeTarjetasDia: Int

    public init(interruptor: Bool = true, pausaAreas: Set<AreaCode> = [], agentes: [String: AjustesDeAsistente] = [:],
                zona: TimeZone = TimeZone(identifier: "Europe/Madrid") ?? .current, hoy: LocalDate? = nil,
                clase: String? = nil, topeTarjetasDia: Int = 5) {
        self.interruptor = interruptor; self.pausaAreas = pausaAreas; self.agentes = agentes; self.zona = zona
        self.hoy = hoy; self.clase = clase; self.topeTarjetasDia = topeTarjetasDia
    }

    public static let vacios = AjustesDeAsistentes()

    public func agente(_ slug: String) -> AjustesDeAsistente? { agentes[slug] }

    /// Asistentes activos, en orden de nombre.
    public var activos: [AjustesDeAsistente] { agentes.values.filter(\.activo).sorted { $0.slug < $1.slug } }

    /// Lee `config.yaml`. Lo que no se entiende queda en su valor por defecto (nunca lanza).
    public static func leer(yaml texto: String?) -> AjustesDeAsistentes {
        var a = AjustesDeAsistentes()
        guard let texto, let node = try? Yams.compose(yaml: texto, Resolver.basic), case .mapping = node else { return a }
        let r = mapa(node)
        if let i = escalar(r["interruptor"]) {
            a.interruptor = !["apagado", "off", "false", "no", "pausa", "en pausa", "0"].contains(TextFolding.fold(i))
        }
        a.pausaAreas = Set(lista(r["pausa_areas"]).compactMap(area))
        let agenda = mapa(r["agenda"])
        if let z = escalar(agenda["zona"]), let tz = TimeZone(identifier: z) { a.zona = tz }
        a.hoy = escalar(r["hoy"]).flatMap { LocalDate(parsing: $0) }
        a.clase = escalar(r["clase"])
        if let t = escalar(mapa(r["avisos"])["tope_tarjetas_dia"]).flatMap({ Int($0) }), t >= 0 { a.topeTarjetasDia = t }
        for (slug, nodo) in mapaOrdenado(r["agentes"]) {
            let d = mapa(nodo)
            let s = TextFolding.fold(slug)
            guard AgentPaths.isSafeName(s) else { continue }
            var g = AjustesDeAsistente(slug: s)
            g.activo = booleano(d["activo"]) ?? false
            g.coordinador = booleano(d["coordinador"]) ?? false
            g.areas = lista(d["areas"]).compactMap(area)
            let lee = lista(d["lee_areas"])
            g.leeAreas = lee.contains { TextFolding.fold($0) == "todas" } ? AreaCode.allCases : lee.compactMap(area)
            g.capacidades = lista(d["capacidades"]).map { $0.uppercased() }
            g.herramientasExternas = lista(d["herramientas_externas"])
            g.modelo = escalar(d["modelo"])
            g.esfuerzo = escalar(d["esfuerzo"])
            if let n = escalar(d["max_tareas_por_ejecucion"]).flatMap({ Int($0) }), n >= 0 { g.maxTareasPorEjecucion = n }
            if let v = escalar(d["presupuesto_ejecucion_usd"]).flatMap(numero), v >= 0 { g.presupuestoEjecucionUSD = v }
            if let v = escalar(d["presupuesto_mes_usd"]).flatMap(numero), v >= 0 { g.presupuestoMesUSD = v }
            if case .sequence(let seq)? = d["rutinas"] {
                g.rutinas = seq.compactMap(rutina)
            }
            a.agentes[s] = g
        }
        return a
    }

    // MARK: Lectura del YAML

    static func mapa(_ n: Node?) -> [String: Node] {
        guard case .mapping(let m)? = n else { return [:] }
        var d: [String: Node] = [:]
        for (k, v) in m { if case .scalar(let s) = k { d[s.string] = v } }
        return d
    }

    static func mapaOrdenado(_ n: Node?) -> [(String, Node)] {
        guard case .mapping(let m)? = n else { return [] }
        return m.compactMap { k, v in
            if case .scalar(let s) = k { return (s.string, v) }
            return nil
        }
    }

    static func escalar(_ n: Node?) -> String? {
        guard case .scalar(let s)? = n else { return nil }
        let t = s.string.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "~" || t == "null" ? nil : t
    }

    static func lista(_ n: Node?) -> [String] {
        switch n {
        case .sequence(let seq)?: return seq.compactMap { escalar($0) }
        case .scalar?: return escalar(n).map { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } } ?? []
        default: return []
        }
    }

    static func booleano(_ n: Node?) -> Bool? {
        guard let t = escalar(n).map(TextFolding.fold) else { return nil }
        if ["true", "si", "yes", "1", "encendido", "activo", "activa"].contains(t) { return true }
        if ["false", "no", "0", "apagado", "inactivo", "inactiva"].contains(t) { return false }
        return nil
    }

    static func numero(_ t: String) -> Double? {
        Double(t.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    static func area(_ t: String) -> AreaCode? {
        let f = TextFolding.fold(t).trimmingCharacters(in: .whitespaces)
        for a in AreaCode.allCases where f == TextFolding.fold(a.nombre) || f == a.layoutKey || f == a.rawValue.lowercased()
            || f == "\(a.numero)" || f == "\(a.numero) · \(TextFolding.fold(a.nombre))" {
            return a
        }
        return nil
    }

    /// `"08:45"`, `8:45`, `845` o los minutos desde medianoche que da YAML 1.1 para `08:45` sin comillas.
    static func horaYMinuto(_ t: String) -> (Int, Int)? {
        let partes = t.split(separator: ":")
        if partes.count == 2, let h = Int(partes[0]), let m = Int(partes[1]), (0..<24).contains(h), (0..<60).contains(m) {
            return (h, m)
        }
        if partes.count == 1, let n = Int(t), n >= 0 {
            if n < 24 { return (n, 0) }
            if n < 2400, n % 100 < 60 { return (n / 100, n % 100) }
        }
        return nil
    }

    static func rutina(_ n: Node) -> RutinaDeAsistente? {
        let d = mapa(n)
        guard let id = escalar(d["id"]).map({ TextFolding.fold($0) }), AgentPaths.isSafeName(id),
              let (h, m) = escalar(d["hora"]).flatMap(horaYMinuto) else { return nil }
        var dias = Set(lista(d["dias"]).compactMap(DiaSemana.init(texto:)))
        if lista(d["dias"]).contains(where: { ["todos", "diario", "cada dia"].contains(TextFolding.fold($0)) }) {
            dias = Set(DiaSemana.allCases)
        }
        if dias.isEmpty { dias = DiaSemana.laborables }
        let diaMes = escalar(d["dia_mes"]).flatMap { Int($0) }.flatMap { (1...28).contains($0) ? $0 : nil }
        let meses = Set(lista(d["meses"]).compactMap { Int($0) }.filter { (1...12).contains($0) })
        return RutinaDeAsistente(
            id: id, nombre: escalar(d["nombre"]), dias: dias, diaDelMes: diaMes, meses: meses, hora: h, minuto: m,
            ventanaPerdidaH: escalar(d["ventana_perdida_h"]).flatMap(numero) ?? 6,
            activa: booleano(d["activa"]) ?? true,
            soloSiHayRojo: booleano(d["solo_si_rojo"]) ?? (id == "algo-rojo"),
            instruccion: escalar(d["instruccion"]))
    }
}

/// De dónde saca el motor los ajustes (en la app: la configuración confirmada de gobierno).
public protocol FuenteDeAjustes: Sendable {
    func ajustes() async -> AjustesDeAsistentes
}

/// Ajustes fijos (pruebas y simulaciones).
public struct AjustesFijos: FuenteDeAjustes {
    public var valor: AjustesDeAsistentes
    public init(_ valor: AjustesDeAsistentes) { self.valor = valor }
    public func ajustes() async -> AjustesDeAsistentes { valor }
}

/// Lee `.tls/config.yaml` de la carpeta tal cual está. **Provisional**: la app debe usar la versión confirmada de
/// gobierno (los cambios hechos fuera de la app no se aplican hasta confirmarlos).
public struct AjustesDeLaCarpeta: FuenteDeAjustes {
    public var root: URL
    public init(root: URL) { self.root = root }
    public func ajustes() async -> AjustesDeAsistentes {
        let url = root.appendingPathComponent(".tls/config.yaml")
        return AjustesDeAsistentes.leer(yaml: try? String(contentsOf: url, encoding: .utf8))
    }
}

/// Ajustes que devuelve un cierre (para enchufar la fuente de gobierno sin depender de su tipo).
public struct AjustesConCierre: FuenteDeAjustes {
    let cierre: @Sendable () async -> AjustesDeAsistentes
    public init(_ cierre: @escaping @Sendable () async -> AjustesDeAsistentes) { self.cierre = cierre }
    public func ajustes() async -> AjustesDeAsistentes { await cierre() }
}
