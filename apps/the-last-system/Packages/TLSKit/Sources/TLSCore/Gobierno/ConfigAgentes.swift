import Foundation
import Yams

// Lo que gobierna a los asistentes en `.tls/config.yaml` (PLAN §4.5, §5.2): `interruptor`, `pausa_areas`, `privado`,
// `capacidades` (declarada = madurez; modo = permiso) y `agentes:`. Los asistentes nunca lo escriben ni lo leen
// (`.tls/` queda fuera de lo que ven); lo escribe una persona desde Ajustes o desde la ficha del asistente
// (`EditorConfigAgentes`). Si cambia fuera de la app, los asistentes siguen con la última versión confirmada
// (`ConfigConfirmada`).

/// Interruptor global (DIR-11): apagado, ningún asistente trabaja.
public enum Interruptor: String, Sendable, Hashable, Codable {
    case encendido, apagado

    /// Lee «encendido», «apagado», `true`/`false`, «sí»/«no», «on»/«off». Lo que no se entiende, apagado.
    public init(leyendo texto: String?) {
        guard let t = texto.map({ TextFolding.fold($0.trimmingCharacters(in: .whitespaces)) }), !t.isEmpty else {
            self = .encendido
            return
        }
        switch t {
        case "encendido", "on", "true", "si", "yes", "activo": self = .encendido
        default: self = .apagado
        }
    }
}

/// Orden de los modos de menos a más permiso (para quedarse con el más restrictivo).
extension ModoCapacidad {
    public var nivel: Int {
        switch self {
        case .off: 0
        case .manual: 1
        case .asistido: 2
        case .supervisado: 3
        case .autonomo: 4
        }
    }

    /// Lee `off`, `manual`, `asistido`, `supervisado`, `autonomo` (con o sin tilde, «autónomo»).
    public init?(leyendo texto: String) {
        let t = TextFolding.fold(texto).replacingOccurrences(of: " ", with: "")
        self.init(rawValue: t)
    }

    /// En pantalla (lenguaje llano, SISTEMAS §2.5): «Lo haces tú», «Te ayuda», «Lo hace y revisas», «Lo hace solo».
    public var etiqueta: String {
        switch self {
        case .off: "Apagada"
        case .manual: "Lo haces tú"
        case .asistido: "Te ayuda"
        case .supervisado: "Lo hace y revisas"
        case .autonomo: "Lo hace solo"
        }
    }
}

/// Una función declarada en `capacidades:` (`FIN-05: {declarada: si, modo: supervisado, ejecutor: IA, …}`).
public struct CapacidadConfigurada: Sendable, Hashable {
    public let codigo: String
    /// Madurez: cuenta para la etapa. No da permiso.
    public let declarada: Bool
    /// Permiso. `nil` si no se dijo.
    public let modo: ModoCapacidad?
    public let ejecutor: String?
    public let declaradaPor: String?
    public let desde: LocalDate?

    public init(codigo: String, declarada: Bool = false, modo: ModoCapacidad? = nil, ejecutor: String? = nil,
                declaradaPor: String? = nil, desde: LocalDate? = nil) {
        self.codigo = codigo.uppercased(); self.declarada = declarada; self.modo = modo; self.ejecutor = ejecutor
        self.declaradaPor = declaradaPor; self.desde = desde
    }
}

/// Una rutina de un asistente (`rutinas:` de su entrada).
public struct RutinaDeAsistente: Sendable, Hashable {
    public let id: String
    public let nombre: String
    /// `lun`, `mar`, `mie`, `jue`, `vie`, `sab`, `dom`; o días del mes (`1`, `5`).
    public let dias: [String]
    /// `HH:MM`.
    public let hora: String?
    public let ventanaPerdidaH: Int?
    public let activa: Bool

    public init(id: String, nombre: String, dias: [String] = [], hora: String? = nil, ventanaPerdidaH: Int? = nil,
                activa: Bool = true) {
        self.id = id; self.nombre = nombre; self.dias = dias; self.hora = hora; self.ventanaPerdidaH = ventanaPerdidaH
        self.activa = activa
    }
}

/// Entrada de un asistente en `agentes:`.
public struct AsistenteConfigurado: Sendable, Hashable {
    public let slug: String
    public var activo: Bool
    public var coordinador: Bool
    /// Áreas propias: escribe solo aquí (y en sus tareas y la Bitácora).
    public var areas: [AreaCode]
    /// Trabaja también en el Buzón (Cartero, Ordenador): `areas: [buzon]`.
    public var buzon: Bool
    /// Áreas que solo lee (`lee_areas`). `leeTodas` con `[todas]`.
    public var leeAreas: [AreaCode]
    public var leeTodas: Bool
    /// Funciones que cubre (vacío = no se restringe por función).
    public var capacidades: [String]
    public var herramientasExternas: [String]
    public var modelo: String?
    public var esfuerzo: String?
    public var maxTurnos: Int?
    public var maxTareasPorEjecucion: Int
    public var presupuestoEjecucionUSD: Double?
    public var presupuestoMesUSD: Double?
    public var rutinas: [RutinaDeAsistente]

    public static let maxTareasPorDefecto = 10

    public init(slug: String, activo: Bool = false, coordinador: Bool = false, areas: [AreaCode] = [], buzon: Bool = false,
                leeAreas: [AreaCode] = [], leeTodas: Bool = false, capacidades: [String] = [],
                herramientasExternas: [String] = [], modelo: String? = nil, esfuerzo: String? = nil, maxTurnos: Int? = nil,
                maxTareasPorEjecucion: Int = AsistenteConfigurado.maxTareasPorDefecto, presupuestoEjecucionUSD: Double? = nil,
                presupuestoMesUSD: Double? = nil, rutinas: [RutinaDeAsistente] = []) {
        self.slug = slug; self.activo = activo; self.coordinador = coordinador; self.areas = areas; self.buzon = buzon
        self.leeAreas = leeAreas; self.leeTodas = leeTodas; self.capacidades = capacidades.map { $0.uppercased() }
        self.herramientasExternas = herramientasExternas; self.modelo = modelo; self.esfuerzo = esfuerzo
        self.maxTurnos = maxTurnos; self.maxTareasPorEjecucion = maxTareasPorEjecucion
        self.presupuestoEjecucionUSD = presupuestoEjecucionUSD; self.presupuestoMesUSD = presupuestoMesUSD
        self.rutinas = rutinas
    }

    /// Nombre en pantalla: `comercial` → «Comercial».
    public var nombre: String { AsistenteConfigurado.nombre(de: slug) }

    public static func nombre(de slug: String) -> String {
        let s = slug.hasPrefix("agente:") ? String(slug.dropFirst("agente:".count)) : slug
        guard let f = s.first else { return s }
        return f.uppercased() + s.dropFirst().replacingOccurrences(of: "-", with: " ")
    }

    /// Puede escribir en esa área (la suya; el coordinador, todas).
    public func escribeEn(_ area: AreaCode) -> Bool { coordinador || areas.contains(area) }

    /// Puede leer esa área (las suyas, `lee_areas`, todas o coordinador).
    public func leeEn(_ area: AreaCode) -> Bool { coordinador || leeTodas || areas.contains(area) || leeAreas.contains(area) }
}

/// `avisos:` (presupuesto de interrupciones, PLAN §5.2).
public struct AvisosConfig: Sendable, Hashable {
    public var topeTarjetasDia: Int
    public var topeNotificacionesNoRojasDia: Int

    public init(topeTarjetasDia: Int = 5, topeNotificacionesNoRojasDia: Int = 3) {
        self.topeTarjetasDia = topeTarjetasDia; self.topeNotificacionesNoRojasDia = topeNotificacionesNoRojasDia
    }
}

/// Lo que gobierna a los asistentes, leído de `.tls/config.yaml`.
public struct ConfigAgentes: Sendable, Hashable {
    public var interruptor: Interruptor
    public var pausaAreas: [AreaCode]
    /// `privado:` tal cual (rutas con `{finanzas}`… sin expandir). Lo privado vale siempre: se une al de la carpeta.
    public var privado: [String]
    public var capacidades: [String: CapacidadConfigurada]
    public var agentes: [String: AsistenteConfigurado]
    public var avisos: AvisosConfig
    /// El YAML no se pudo leer: no hay asistentes (nada trabaja con una configuración que no se entiende).
    public var ilegible: Bool

    public init(interruptor: Interruptor = .encendido, pausaAreas: [AreaCode] = [], privado: [String] = [],
                capacidades: [String: CapacidadConfigurada] = [:], agentes: [String: AsistenteConfigurado] = [:],
                avisos: AvisosConfig = AvisosConfig(), ilegible: Bool = false) {
        self.interruptor = interruptor; self.pausaAreas = pausaAreas; self.privado = privado; self.capacidades = capacidades
        self.agentes = agentes; self.avisos = avisos; self.ilegible = ilegible
    }

    /// Sin configuración: interruptor encendido y ningún asistente.
    public static let vacia = ConfigAgentes()

    public var encendido: Bool { interruptor == .encendido }

    /// Modo de una función (`nil` si no está en `capacidades:` o no dice modo).
    public func modo(_ capacidad: String) -> ModoCapacidad? { capacidades[capacidad.uppercased()]?.modo }

    public func asistente(_ slug: String) -> AsistenteConfigurado? {
        agentes[ConfigAgentes.slug(slug)]
    }

    /// Los activos, ordenados por nombre.
    public var activos: [AsistenteConfigurado] { agentes.values.filter(\.activo).sorted { $0.slug < $1.slug } }

    public func enPausa(_ area: AreaCode) -> Bool { pausaAreas.contains(area) }

    /// `agente:comercial` o `Comercial` → `comercial`.
    public static func slug(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("agente:") { t = String(t.dropFirst("agente:".count)) }
        return TextFolding.fold(t).replacingOccurrences(of: " ", with: "-")
    }

    // MARK: Lectura

    /// Lee la configuración. Lo que no se entiende queda en su valor más prudente (asistente inactivo, sin permiso).
    public static func leer(yaml texto: String?) -> ConfigAgentes {
        guard let texto, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .vacia }
        guard texto.utf8.count < 512 * 1024, let raizNodo = (try? Yams.compose(yaml: texto, Resolver.basic)) ?? nil,
              FrontmatterReader.nodeCount(raizNodo, limit: FrontmatterReader.maxNodes) <= FrontmatterReader.maxNodes,
              let raiz = raizNodo.mapping else {
            return ConfigAgentes(interruptor: .apagado, ilegible: true)
        }
        var c = ConfigAgentes()
        let r = mapa(raiz)
        if let i = r["interruptor"] { c.interruptor = Interruptor(leyendo: escalar(i)) }
        c.pausaAreas = lista(r["pausa_areas"]).compactMap(area)
        c.privado = lista(r["privado"])
        for (codigo, v) in mapa(r["capacidades"]?.mapping) {
            let d = mapa(v.mapping)
            let modo = (escalar(d["modo"]) ?? (v.mapping == nil ? escalar(v) : nil)).flatMap(ModoCapacidad.init(leyendo:))
            c.capacidades[codigo.uppercased()] = CapacidadConfigurada(
                codigo: codigo, declarada: booleano(escalar(d["declarada"])) ?? false, modo: modo,
                ejecutor: escalar(d["ejecutor"]), declaradaPor: escalar(d["declarada_por"]),
                desde: escalar(d["desde"]).flatMap { LocalDate(parsing: $0) })
        }
        for (slugCrudo, v) in mapa(r["agentes"]?.mapping) {
            let s = ConfigAgentes.slug(slugCrudo)
            guard !s.isEmpty else { continue }
            c.agentes[s] = asistente(s, mapa(v.mapping))
        }
        let avisos = mapa(r["avisos"]?.mapping)
        if let t = escalar(avisos["tope_tarjetas_dia"]).flatMap({ Int($0) }), t >= 0 { c.avisos.topeTarjetasDia = t }
        if let t = escalar(avisos["tope_notificaciones_no_rojas_dia"]).flatMap({ Int($0) }), t >= 0 {
            c.avisos.topeNotificacionesNoRojasDia = t
        }
        return c
    }

    static func asistente(_ slug: String, _ d: [String: Node]) -> AsistenteConfigurado {
        var a = AsistenteConfigurado(slug: slug)
        a.activo = booleano(escalar(d["activo"])) ?? false
        a.coordinador = booleano(escalar(d["coordinador"])) ?? false
        for t in lista(d["areas"]) {
            if TextFolding.fold(t) == "buzon" { a.buzon = true } else if let x = area(t), !a.areas.contains(x) { a.areas.append(x) }
        }
        for t in lista(d["lee_areas"]) {
            let f = TextFolding.fold(t)
            if f == "todas" || f == "todo" { a.leeTodas = true } else if f == "buzon" { a.buzon = true }
            else if let x = area(t), !a.leeAreas.contains(x) { a.leeAreas.append(x) }
        }
        a.capacidades = lista(d["capacidades"]).map { $0.uppercased() }.filter { $0 != "…" && $0 != "..." }
        a.herramientasExternas = lista(d["herramientas_externas"])
        a.modelo = escalar(d["modelo"])
        a.esfuerzo = escalar(d["esfuerzo"])
        a.maxTurnos = escalar(d["max_turnos"]).flatMap { Int($0) }
        if let n = escalar(d["max_tareas_por_ejecucion"]).flatMap({ Int($0) }), n >= 0 { a.maxTareasPorEjecucion = n }
        a.presupuestoEjecucionUSD = escalar(d["presupuesto_ejecucion_usd"]).flatMap(numero)
        a.presupuestoMesUSD = escalar(d["presupuesto_mes_usd"]).flatMap(numero)
        if case .sequence(let seq)? = d["rutinas"] {
            for n in seq {
                let m = mapa(n.mapping)
                guard let id = escalar(m["id"]) else { continue }
                a.rutinas.append(RutinaDeAsistente(id: id, nombre: escalar(m["nombre"]) ?? id, dias: lista(m["dias"]),
                                                   hora: escalar(m["hora"]),
                                                   ventanaPerdidaH: escalar(m["ventana_perdida_h"]).flatMap { Int($0) },
                                                   activa: booleano(escalar(m["activa"])) ?? true))
            }
        }
        return a
    }

    // MARK: Ayudas de YAML

    static func mapa(_ m: Node.Mapping?) -> [String: Node] {
        guard let m else { return [:] }
        var d: [String: Node] = [:]
        for (k, v) in m { if let s = k.scalar?.string { d[s] = v } }
        return d
    }

    static func escalar(_ n: Node?) -> String? {
        guard let s = n?.scalar?.string else { return nil }
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t == "~" || t == "null" ? nil : t
    }

    /// Lista YAML (`[a, b]` o con guiones) o un escalar suelto como lista de uno.
    static func lista(_ n: Node?) -> [String] {
        guard let n else { return [] }
        if case .sequence(let seq) = n { return seq.compactMap { escalar($0) } }
        return escalar(n).map { [$0] } ?? []
    }

    static func booleano(_ s: String?) -> Bool? {
        guard let s else { return nil }
        switch TextFolding.fold(s) {
        case "true", "si", "yes", "on", "1", "activo", "activa": return true
        case "false", "no", "off", "0", "inactivo", "inactiva": return false
        default: return nil
        }
    }

    static func numero(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    /// `direccion`, `Dirección`, `DIR`, `1 · Dirección` → el área.
    public static func area(_ s: String) -> AreaCode? {
        let t = TextFolding.fold(s.trimmingCharacters(in: .whitespaces))
        for a in AreaCode.allCases {
            if t == TextFolding.fold(a.rawValue) || t == a.layoutKey || t == TextFolding.fold(a.nombre)
                || t == TextFolding.fold("\(a.numero) · \(a.nombre)") { return a }
        }
        return nil
    }

    // MARK: Lo más restrictivo

    /// Mezcla dos configuraciones quedándose con lo más prudente de cada una (la confirmada y la de ahora mientras
    /// la de ahora no se confirma): interruptor apagado si lo está en alguna; pausas y lo privado, unidos; un
    /// asistente, activo solo si lo está en las dos y con lo común de sus áreas y topes; cada función, en el modo
    /// más bajo de los dos.
    public static func masRestrictiva(_ a: ConfigAgentes, _ b: ConfigAgentes) -> ConfigAgentes {
        var c = a
        c.ilegible = a.ilegible && b.ilegible
        c.interruptor = a.encendido && b.encendido ? .encendido : .apagado
        c.pausaAreas = a.pausaAreas + b.pausaAreas.filter { !a.pausaAreas.contains($0) }
        c.privado = a.privado + b.privado.filter { p in !a.privado.contains { TextFolding.pathKey($0) == TextFolding.pathKey(p) } }
        var caps: [String: CapacidadConfigurada] = [:]
        for k in Set(a.capacidades.keys).union(b.capacidades.keys) {
            let x = a.capacidades[k], y = b.capacidades[k]
            let modo: ModoCapacidad?
            switch (x?.modo, y?.modo) {
            case (let m?, let n?): modo = m.nivel <= n.nivel ? m : n
            case (let m?, nil): modo = m
            case (nil, let n?): modo = n
            default: modo = nil
            }
            let base = x ?? y!
            caps[k] = CapacidadConfigurada(codigo: k, declarada: (x?.declarada ?? false) && (y?.declarada ?? false),
                                           modo: modo, ejecutor: base.ejecutor, declaradaPor: base.declaradaPor, desde: base.desde)
        }
        c.capacidades = caps
        var agentes: [String: AsistenteConfigurado] = [:]
        for (slug, x) in a.agentes {
            guard let y = b.agentes[slug] else {
                var z = x
                z.activo = false
                agentes[slug] = z
                continue
            }
            var z = x
            z.activo = x.activo && y.activo
            z.coordinador = x.coordinador && y.coordinador
            z.areas = x.areas.filter(y.areas.contains)
            z.buzon = x.buzon && y.buzon
            z.leeTodas = x.leeTodas && y.leeTodas
            z.leeAreas = (x.leeAreas + x.areas).filter { y.leeEn($0) && x.leeEn($0) }.filter { !z.areas.contains($0) }
            if !x.capacidades.isEmpty || !y.capacidades.isEmpty {
                z.capacidades = x.capacidades.isEmpty ? y.capacidades
                    : (y.capacidades.isEmpty ? x.capacidades : x.capacidades.filter(y.capacidades.contains))
                if z.capacidades.isEmpty { z.capacidades = ["—"] }
            }
            z.herramientasExternas = x.herramientasExternas.filter(y.herramientasExternas.contains)
            z.maxTareasPorEjecucion = min(x.maxTareasPorEjecucion, y.maxTareasPorEjecucion)
            z.presupuestoEjecucionUSD = minimo(x.presupuestoEjecucionUSD, y.presupuestoEjecucionUSD)
            z.presupuestoMesUSD = minimo(x.presupuestoMesUSD, y.presupuestoMesUSD)
            z.maxTurnos = minimo(x.maxTurnos, y.maxTurnos)
            agentes[slug] = z
        }
        c.agentes = agentes
        c.avisos = AvisosConfig(topeTarjetasDia: min(a.avisos.topeTarjetasDia, b.avisos.topeTarjetasDia),
                                topeNotificacionesNoRojasDia: min(a.avisos.topeNotificacionesNoRojasDia,
                                                                  b.avisos.topeNotificacionesNoRojasDia))
        return c
    }

    static func minimo<T: Comparable>(_ a: T?, _ b: T?) -> T? {
        switch (a, b) {
        case (let x?, let y?): min(x, y)
        case (let x?, nil): x
        case (nil, let y?): y
        default: nil
        }
    }

    // MARK: Diferencias

    /// Asistentes cuyos permisos cambian de `self` a `otra` (para la tarjeta «Cambiaron los permisos de X fuera de la
    /// app»). `"interruptor"`, `"pausa"`, `"privado"`, `"funciones"` y `"avisos"` para lo que es de todos.
    public func cambios(hacia otra: ConfigAgentes) -> [String] {
        var out: [String] = []
        if interruptor != otra.interruptor { out.append("interruptor") }
        if Set(pausaAreas) != Set(otra.pausaAreas) { out.append("pausa") }
        if Set(privado.map(TextFolding.pathKey)) != Set(otra.privado.map(TextFolding.pathKey)) { out.append("privado") }
        if capacidades.mapValues(\.modo) != otra.capacidades.mapValues(\.modo) { out.append("funciones") }
        if avisos != otra.avisos { out.append("avisos") }
        for slug in Set(agentes.keys).union(otra.agentes.keys).sorted() where agentes[slug] != otra.agentes[slug] {
            out.append("agente:" + slug)
        }
        return out
    }
}
