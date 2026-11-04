import Foundation
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol asistentes. Lo que enseñan Asistentes, la ficha de cada asistente y Equipo › Asistentes, calculado fuera del
// hilo principal a partir de lo que hay en disco: la configuración (la confirmada, si la app ya tiene gobierno), la
// Bitácora del mes, el estado del motor (`estado.sqlite`: cola, trabajos y uso) y los perfiles de serie. Lo que pasa en
// vivo (`EstadoEnVivo`) se mezcla al pintar. Solo lee; nada de esto escribe en la carpeta.

// MARK: - Estado de un asistente

/// Cómo está un asistente ahora (PLAN §6.4 y §6.5): trabajando, en cola, esperando tu respuesta, en reposo, en pausa o
/// apagado. El color nunca va solo: cada uno lleva su icono y su palabra.
enum EstadoDeAsistente: Hashable, Sendable {
    /// Trabajando ahora, con la frase en directo («Leyendo…», «Creando tarea…»).
    case trabajando(String)
    /// Tiene trabajos esperando su turno.
    case enCola(Int)
    /// Te hizo una pregunta y espera tu respuesta.
    case esperandoRespuesta
    /// Activo y sin nada que hacer ahora.
    case enReposo
    /// No trabaja ahora por una pausa: el interruptor general, su área en pausa, preparada o en reposo.
    case enPausa(String)
    /// No está activo en la configuración.
    case apagado(String)

    /// F4 · corrector (revisión de experiencia, P2): un asistente sin trabajo está «Libre»; «En reposo» es solo de las
    /// áreas (no se mezclan las dos cosas).
    var palabra: String {
        switch self {
        case .trabajando: "Trabajando"
        case .enCola: "En cola"
        case .esperandoRespuesta: "Esperando tu respuesta"
        case .enReposo: "Libre"
        case .enPausa: "En pausa"
        case .apagado: "Apagado"
        }
    }

    var simbolo: String {
        switch self {
        case .trabajando: "bolt.circle.fill"
        case .enCola: "clock"
        case .esperandoRespuesta: "questionmark.bubble.fill"
        case .enReposo: "checkmark.circle"
        case .enPausa: "pause.circle"
        case .apagado: "power"
        }
    }

    /// Color que refuerza (nunca solo). F4 · corrector (revisión de experiencia, P3): lo que te toca (una pregunta) no
    /// es «Atención» (eso es que algo se tuerce): va neutro, con su icono y su palabra.
    var tlsEstado: TLSEstado {
        switch self {
        case .trabajando: .bien
        default: .sinDato
        }
    }

    /// La frase que acompaña a la palabra.
    var detalle: String {
        switch self {
        case .trabajando(let f): f
        case .enCola(let n): n == 1 ? "Un trabajo espera su turno" : "\(n) trabajos esperan su turno"
        case .esperandoRespuesta: "Te ha hecho una pregunta: contéstale en Decisiones"
        case .enReposo: "Nada que hacer ahora"
        case .enPausa(let m), .apagado(let m): m
        }
    }

    var trabajando: Bool { if case .trabajando = self { true } else { false } }
}

// MARK: - Uso

/// El uso del mes de un asistente frente a su tope. Dentro va en dólares (lo que informa Claude Code); en pantalla,
/// siempre como parte del tope («uso del mes: 34 % de tu tope»). Lo simulado lo dice.
struct UsoDelMes: Hashable, Sendable {
    var usadoUSD: Double
    var topeUSD: Double
    var simulado: Bool

    static let cero = UsoDelMes(usadoUSD: 0, topeUSD: 15, simulado: false)

    /// Con uso real se enseña el real; si solo hay uso simulado (el ejemplo), el simulado con su marca.
    static func de(real: Double, simulado: Double, tope: Double) -> UsoDelMes {
        if real > 0 || simulado <= 0 { return UsoDelMes(usadoUSD: real, topeUSD: tope, simulado: false) }
        return UsoDelMes(usadoUSD: simulado, topeUSD: tope, simulado: true)
    }

    var porcentaje: Int? { topeUSD > 0 ? Int((usadoUSD / topeUSD * 100).rounded()) : nil }

    /// «34 %», «menos del 1 %».
    var cifra: String {
        guard let p = porcentaje else { return "Sin tope" }
        if p == 0, usadoUSD > 0 { return "menos del 1 %" }
        return "\(p) %"
    }

    /// «uso del mes: 34 % de tu tope» (y «(Simulado)» si lo es).
    var frase: String {
        guard porcentaje != nil else { return "Sin tope de uso fijado" }
        return "uso del mes: \(cifra) de tu tope" + (simulado ? " (Simulado)" : "")
    }

    /// La frase sin «(Simulado)», cuando la marca va al lado.
    var fraseSinMarca: String {
        guard porcentaje != nil else { return "Sin tope de uso fijado" }
        return "uso del mes: \(cifra) de tu tope"
    }

    /// De 0 a 1, para la barra.
    var fraccion: Double { topeUSD > 0 ? min(1, max(0, usadoUSD / topeUSD)) : 0 }

    /// Lo que gastó un trabajo, como parte del tope del mes («2 % de tu tope»).
    static func parte(_ usd: Double, de tope: Double) -> String {
        guard tope > 0 else { return "sin tope fijado" }
        guard usd > 0 else { return "0 % de tu tope" }
        let p = Int((usd / tope * 100).rounded())
        return p == 0 ? "menos del 1 % de tu tope" : "\(p) % de tu tope"
    }
}

// MARK: - Bitácora

/// Una línea de la Bitácora (`6 · Equipo/Bitácora/AAAA-MM.md`) tal como se enseña.
struct ApunteBitacora: Identifiable, Hashable, Sendable {
    let id: String
    let linea: TLSCore.LineaBitacora

    var agente: String { linea.agente }
    var fecha: LocalDate { linea.fecha }
    var hora: String { linea.hora }
    var mes: String { String(format: "%04d-%02d", linea.fecha.year, linea.fecha.month) }

    /// Lo hizo la simulación (el ejemplo): la línea empieza por «Simulado» o la ejecución es de la demo.
    var simulado: Bool {
        TextFolding.fold(linea.que).hasPrefix("simulado") || (linea.ejecucion?.hasPrefix("sim-") ?? false)
    }

    /// Qué hizo, sin «Simulado:» delante (la marca va aparte).
    var que: String {
        var t = linea.que.trimmingCharacters(in: .whitespaces)
        for p in ["Simulado: ", "Simulado, ", "Simulado. ", "Simulado:"] where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        return FormatoFicha.capital(t)
    }

    var resultado: String { linea.resultado }

    /// Cómo acabó, con su color (que nunca va solo: la palabra va al lado).
    var estado: TLSEstado {
        let r = TextFolding.fold(linea.resultado)
        if r.contains("error") || r.contains("fall") || r.contains("rechaz") { return .mal }
        // Lo que espera tu OK o tu respuesta no es «Atención»: va neutro (F4 · corrector, P3).
        if r.contains("pendiente") || r.contains("esperando") || r.contains("propuesta") { return .sinDato }
        if r.contains("hecho") { return .bien }
        return .sinDato
    }

    /// Lee las líneas de un mes (`ruta` para el identificador estable).
    static func leer(_ texto: String, ruta: VaultPath) -> [ApunteBitacora] {
        var out: [ApunteBitacora] = []
        for (n, l) in texto.components(separatedBy: .newlines).enumerated() {
            if let linea = TLSCore.LineaBitacora.leer(l) { out.append(ApunteBitacora(id: "\(ruta.raw)#\(n)", linea: linea)) }
        }
        return out
    }
}

// MARK: - Trabajos

/// Un trabajo del asistente tal como lo guarda el motor (`estado.sqlite.ejecuciones`).
struct TrabajoDeAsistente: Identifiable, Hashable, Sendable {
    let id: String
    let agente: String
    /// Lo que dejó dicho al terminar o, si no, por qué trabajó.
    let titulo: String
    /// Por qué trabajó («Rutina «Repaso del embudo»», «Se lo pediste»…).
    let porQue: String
    let estado: EstadoDeEjecucion
    /// Por qué no terminó, en palabras.
    let motivo: String?
    let costeUSD: Double
    let simulado: Bool
    let fecha: Date
    let tarea: VaultPath?
    let intento: Int
    let sesion: String?
    let pregunta: String?

    init(_ e: Ejecucion, nombreRutina: (String) -> String?) {
        id = e.id
        agente = e.agente
        porQue = Self.porQue(e.disparo, nombreRutina: nombreRutina)
        let resumen = e.resumen?.trimmingCharacters(in: .whitespacesAndNewlines)
        titulo = (resumen?.isEmpty == false ? resumen : nil) ?? porQue
        estado = e.estado
        switch e.estado {
        case .fallida: motivo = e.motivo?.explanation ?? e.nota ?? "No pudo terminar."
        case .cancelada: motivo = e.nota
        default: motivo = nil
        }
        costeUSD = e.costeUSD
        simulado = e.simulado
        fecha = e.terminada ?? e.empezada ?? e.creada
        tarea = e.tarea
        intento = e.intento
        sesion = e.sesion?.uuidString.lowercased()
        pregunta = e.pregunta
    }

    static func porQue(_ d: Disparo, nombreRutina: (String) -> String?) -> String {
        switch d.tipo {
        case .rutina:
            let n = d.rutina.flatMap(nombreRutina) ?? d.rutina ?? "su rutina"
            return "Rutina «\(n)»"
        case .evento:
            switch d.datos["evento"] {
            case "contacto.creado"?: return "Entró un contacto nuevo"
            case "extracto.importado"?: return "Se importó un extracto del banco"
            case "proyecto.creado"?: return "Empezó un proyecto"
            case "proyecto.cerrado"?: return "Se cerró un proyecto"
            default: return "Algo cambió en la carpeta"
            }
        case .tarea: return d.datos["titulo"].map { "La tarea «\($0)»" } ?? "Una tarea que tiene asignada"
        case .mencion: return "Lo mencionaste en una tarea"
        case .despertar: return "Un seguimiento programado"
        case .accion: return d.datos["peticion"].map { "Le pediste: \($0)" } ?? "Se lo pediste"
        case .chat: return "Conversación con ⌘J"
        case .respuesta: return "Le contestaste una pregunta"
        }
    }

    var palabra: String {
        switch estado {
        case .pendiente: "Pendiente"
        case .enCola: "En cola"
        case .enCurso: "Trabajando"
        case .esperandoRespuesta: "Esperando tu respuesta"
        case .completada: "Terminado"
        case .fallida: "No pudo terminar"
        case .cancelada: "Cancelado"
        }
    }

    var tlsEstado: TLSEstado {
        switch estado {
        case .completada: .bien
        case .fallida: .mal
        default: .sinDato
        }
    }
}

// MARK: - Rutinas

/// Una rutina de un asistente con lo que hace falta para enseñarla y cambiarla.
struct RutinaVista: Identifiable, Hashable, Sendable {
    var id: String { rutina.id }
    let rutina: TLSAgents.RutinaDeAsistente
    /// No está en la configuración: es la de serie de su perfil (el motor usa esa).
    let deSerie: Bool
    /// Pausada sola tras fallar mucho (la reanuda la persona).
    let autopausa: String?
    let proxima: Date?

    /// «de lunes a viernes a las 08:45», «el día 5 de cada mes a las 09:00».
    var cuando: String { FichaDeRolDeAsistente.cuando(rutina) }
}

struct UltimoTrabajo: Hashable, Sendable {
    let texto: String
    let dia: LocalDate
    let hora: String?
    let simulado: Bool
}

struct ProximaRutina: Hashable, Sendable {
    let nombre: String
    let fecha: Date
    let soloSiHayRojo: Bool
}

// MARK: - Un asistente

struct AsistenteEnLista: Identifiable, Hashable, Sendable {
    var id: String { slug }
    let slug: String
    let nombre: String
    /// «tu asistente de Ventas».
    let descripcion: String
    let perfil: PerfilDeAsistente?
    let area: AreaCode?
    let esDelSistema: Bool
    let coordinador: Bool
    /// Tiene entrada en la configuración.
    let enConfig: Bool
    let activo: Bool
    let ajustes: AjustesDeAsistente
    let rutinas: [RutinaVista]
    /// El estado según lo guardado (sin lo que pasa en vivo).
    let estadoGuardado: EstadoDeAsistente
    let ultima: UltimoTrabajo?
    let proxima: ProximaRutina?
    let uso: UsoDelMes

    /// `agente:comercial`.
    var autor: String { "agente:\(slug)" }

    /// El estado con lo que pasa en vivo encima.
    func estado(vivo: TrabajoEnVivo?) -> EstadoDeAsistente {
        guard let vivo else { return estadoGuardado }
        switch vivo.fase {
        case .trabajando: return .trabajando(vivo.frase)
        case .esperandoRespuesta: return .esperandoRespuesta
        case .enCola:
            switch estadoGuardado {
            case .enCola, .enPausa, .apagado: return estadoGuardado
            default: return .enCola(1)
            }
        default: return estadoGuardado
        }
    }

    /// Icono propio: Mika y los asistentes, `sparkle` (DISENO §1.11); los del sistema, el del Buzón.
    var simbolo: String { esDelSistema ? "tray.full" : "sparkle" }
}

// MARK: - Lo que se lee

/// Lo que hace falta leer (se reúne en el hilo principal y se calcula fuera).
struct FuentesDeAsistentes: Sendable {
    /// `.tls/config.yaml` tal cual está.
    var textoFichero: String?
    /// Con gobierno: el texto confirmado y la configuración que se aplica.
    var textoConfirmado: String?
    var efectiva: ConfigAgentes?
    /// «Cambiaron los permisos de X fuera de la app: confirmar», si hay algo que confirmar.
    var cambiosDeFuera: String?
    var estadosArea: [AreaCode: AreaStatus] = [:]
    var perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie
    var ejecuciones: [Ejecucion] = []
    /// Uso del mes guardado por el motor, por asistente: real y simulado.
    var usoMotor: [String: (real: Double, simulado: Double)] = [:]
    var pausadas: [RutinaPausada] = []
    var bitacora: [ApunteBitacora] = []
    var ahora: Date = Date()
    /// El ejemplo (todo lo que hacen los asistentes es simulado).
    var demo = false
    /// F4 · corrector (P2): por qué no hay motor en esta empresa (falta Claude Code). `nil` si lo hay o es el ejemplo.
    var sinMotor: String?
}

/// Todo lo que enseñan las pantallas de asistentes.
struct LecturaAsistentes: Sendable {
    let asistentes: [AsistenteEnLista]
    let config: ConfigAgentes
    let ajustes: AjustesDeAsistentes
    let interruptor: Bool
    let pausaAreas: Set<AreaCode>
    let cambiosDeFuera: String?
    let hayGobierno: Bool
    let demo: Bool
    let ahora: Date
    let zona: TimeZone
    let hoy: LocalDate
    let estadosArea: [AreaCode: AreaStatus]
    /// Todas las líneas de la Bitácora leídas (las más recientes primero).
    let bitacora: [ApunteBitacora]
    /// Los trabajos guardados por el motor (los más recientes primero).
    let trabajos: [TrabajoDeAsistente]
    let usoTotal: UsoDelMes
    let textoFichero: String?

    var mes: String { String(format: "%04d-%02d", hoy.year, hoy.month) }

    /// Lo que dice cada asistente cuando falta Claude Code (no pueden trabajar aunque estén encendidos).
    static let faltaClaude = "Falta Claude Code en este Mac"

    func asistente(_ slug: String) -> AsistenteEnLista? {
        let s = ConfigAgentes.slug(slug)
        return asistentes.first { $0.slug == s }
    }

    func trabajos(de slug: String) -> [TrabajoDeAsistente] { trabajos.filter { $0.agente == slug } }
    func bitacora(de slug: String) -> [ApunteBitacora] { bitacora.filter { $0.agente == slug } }

    /// Los meses que tienen Bitácora, el más reciente primero.
    var mesesDeBitacora: [String] { Array(Set(bitacora.map(\.mes))).sorted(by: >) }

    static let vacia = LecturaAsistentes.calcular(FuentesDeAsistentes())

    // MARK: Cálculo

    static func calcular(_ f: FuentesDeAsistentes) -> LecturaAsistentes {
        let ajustes: AjustesDeAsistentes
        let config: ConfigAgentes
        if let e = f.efectiva {
            ajustes = AjustesDeGobierno.combinar(confirmado: f.textoConfirmado, efectiva: e)
            config = e
        } else {
            ajustes = AjustesDeAsistentes.leer(yaml: f.textoFichero)
            config = ConfigAgentes.leer(yaml: f.textoFichero)
        }
        let zona = ajustes.zona
        let hoy = LocalDate(date: f.ahora, timeZone: zona)
        let mes = String(format: "%04d-%02d", hoy.year, hoy.month)
        let interruptor = ajustes.interruptor && config.encendido
        let pausa = ajustes.pausaAreas.union(config.pausaAreas)
        let pausadas = Dictionary(f.pausadas.map { ($0.rutina, $0) }, uniquingKeysWith: { a, _ in a })
        let scheduler = RoutineScheduler(zona: zona)

        // Bitácora del mes por asistente: uso real y simulado.
        var usoBitacora: [String: (real: Double, simulado: Double)] = [:]
        for a in f.bitacora where a.mes == mes {
            guard let u = a.linea.usoUSD else { continue }
            var x = usoBitacora[a.agente] ?? (0, 0)
            if a.simulado { x.simulado += u } else { x.real += u }
            usoBitacora[a.agente] = x
        }

        var slugs = f.perfiles.map(\.slug)
        for s in ajustes.agentes.keys.sorted() where !slugs.contains(s) { slugs.append(s) }

        let ejecuciones = f.ejecuciones.sorted { $0.creada > $1.creada }
        var lista: [AsistenteEnLista] = []
        var totalReal = 0.0, totalSimulado = 0.0, totalTope = 0.0
        for slug in slugs {
            let perfil = f.perfiles.first { $0.slug == slug }
            let enConfig = ajustes.agente(slug) != nil
            var aj = ajustes.agente(slug) ?? AjustesDeAsistente(slug: slug)
            if !enConfig, let p = perfil {
                aj.areas = p.area.map { [$0] } ?? []
                aj.coordinador = p.coordinador
                aj.capacidades = p.capacidades
                aj.presupuestoMesUSD = p.ajustes.presupuestoMesUSD
                aj.presupuestoEjecucionUSD = p.ajustes.presupuestoEjecucionUSD
                aj.maxTareasPorEjecucion = p.ajustes.maxTareasPorEjecucion
            }
            let area = aj.areaPropia ?? perfil?.area
            let suyas = ejecuciones.filter { $0.agente == slug }

            // Puede trabajar ahora (para la próxima rutina).
            var pausaMotivo: String?
            if !interruptor {
                pausaMotivo = "Todos los asistentes están en pausa"
            } else if f.sinMotor != nil, !f.demo {
                pausaMotivo = LecturaAsistentes.faltaClaude
            } else if let a = area, pausa.contains(a) {
                pausaMotivo = "Su área está en pausa"
            } else if let a = area, f.estadosArea[a] == .preparada {
                pausaMotivo = "Su área está preparada: aún no trabaja en ella"
            } else if let a = area, f.estadosArea[a] == .reposo {
                pausaMotivo = "Su área está en reposo"
            }
            let puede = aj.activo && pausaMotivo == nil

            let deSerie = aj.rutinas.isEmpty
            let base = deSerie ? (perfil?.rutinas ?? []) : aj.rutinas
            let rutinas = base.map { r -> RutinaVista in
                let clave = "\(slug).\(r.id)"
                let auto = pausadas[clave].map { $0.motivo }
                let proxima = (puede && r.activa && auto == nil) ? scheduler.siguienteHueco(r, despues: f.ahora) : nil
                return RutinaVista(rutina: r, deSerie: deSerie, autopausa: auto, proxima: proxima)
            }
            let proxima = rutinas.compactMap { v in v.proxima.map { (v, $0) } }.min { $0.1 < $1.1 }
                .map { ProximaRutina(nombre: $0.0.rutina.nombre, fecha: $0.1, soloSiHayRojo: $0.0.rutina.soloSiHayRojo) }

            // Estado guardado.
            let estado: EstadoDeAsistente
            let pendientes = suyas.filter { $0.estado == .pendiente || $0.estado == .enCola }.count
            if suyas.contains(where: { $0.estado == .enCurso }) {
                estado = .trabajando("Trabajando…")
            } else if suyas.contains(where: { $0.estado == .esperandoRespuesta }) {
                estado = .esperandoRespuesta
            } else if !aj.activo {
                // F4 · corrector (P2): el motivo, del estado real de su área (no «en reposo» si está preparada).
                let porArea: String? = switch area.flatMap({ f.estadosArea[$0] }) {
                case .preparada?: "Su área está preparada: empieza cuando la actives"
                case .reposo?: "Su área está en reposo: empieza cuando la actives"
                default: nil
                }
                estado = .apagado(enConfig ? (porArea ?? perfil?.activacion.explicacion ?? "No está activo")
                                           : "Aún no está en la configuración de los asistentes")
            } else if let m = pausaMotivo {
                estado = .enPausa(m)
            } else if pendientes > 0 {
                estado = .enCola(pendientes)
            } else {
                estado = .enReposo
            }

            // Último trabajo: del motor o, si es más reciente, de la Bitácora.
            var ultima: UltimoTrabajo?
            if let e = suyas.first(where: { $0.estado.esFinal }) {
                let fecha = e.terminada ?? e.creada
                let t = TrabajoDeAsistente(e, nombreRutina: { id in base.first { $0.id == id }?.nombre })
                ultima = UltimoTrabajo(texto: t.titulo, dia: LocalDate(date: fecha, timeZone: zona),
                                       hora: FormatoAsistentes.hora(fecha, zona: zona), simulado: e.simulado)
            }
            if let b = f.bitacora.filter({ $0.agente == slug }).max(by: { ($0.fecha, $0.hora) < ($1.fecha, $1.hora) }) {
                if ultima.map({ ($0.dia, $0.hora ?? "") < (b.fecha, b.hora) }) ?? true {
                    ultima = UltimoTrabajo(texto: b.que, dia: b.fecha, hora: b.hora, simulado: b.simulado)
                }
            }

            // Uso del mes: lo del motor y lo de la Bitácora apuntan los mismos trabajos; se toma el mayor.
            let m = f.usoMotor[slug] ?? (0, 0)
            let b = usoBitacora[slug] ?? (0, 0)
            let real = max(m.real, b.real), simulado = max(m.simulado, b.simulado)
            let uso = UsoDelMes.de(real: real, simulado: simulado, tope: aj.presupuestoMesUSD)
            totalReal += real
            totalSimulado += simulado
            if aj.activo { totalTope += aj.presupuestoMesUSD }

            lista.append(AsistenteEnLista(
                slug: slug, nombre: perfil?.nombre ?? AsistenteConfigurado.nombre(de: slug),
                descripcion: perfil?.descripcion ?? (area.map { "tu asistente de \($0.nombre)" } ?? "asistente"),
                perfil: perfil, area: area, esDelSistema: perfil?.esDelSistema ?? (area == nil),
                coordinador: aj.coordinador || (perfil?.coordinador ?? false), enConfig: enConfig, activo: aj.activo,
                ajustes: aj, rutinas: rutinas, estadoGuardado: estado, ultima: ultima, proxima: proxima, uso: uso))
        }

        let nombres: [String: [TLSAgents.RutinaDeAsistente]] = Dictionary(uniqueKeysWithValues: lista.map { ($0.slug, $0.rutinas.map(\.rutina)) })
        let trabajos = ejecuciones.map { e in
            TrabajoDeAsistente(e, nombreRutina: { id in nombres[e.agente]?.first { $0.id == id }?.nombre })
        }
        return LecturaAsistentes(
            asistentes: lista, config: config, ajustes: ajustes, interruptor: interruptor, pausaAreas: pausa,
            cambiosDeFuera: f.cambiosDeFuera, hayGobierno: f.efectiva != nil, demo: f.demo, ahora: f.ahora, zona: zona,
            hoy: hoy, estadosArea: f.estadosArea,
            bitacora: f.bitacora.sorted { ($0.fecha, $0.hora, $0.id) > ($1.fecha, $1.hora, $1.id) },
            trabajos: trabajos,
            usoTotal: UsoDelMes.de(real: totalReal, simulado: totalSimulado, tope: totalTope),
            textoFichero: f.textoFichero)
    }
}

// MARK: - Formato

enum FormatoAsistentes {
    /// «10:00».
    static func hora(_ d: Date, zona: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        let c = cal.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// «hoy a las 10:00», «mañana a las 08:45», «el vie 23 oct a las 09:00».
    static func cuando(_ d: Date, zona: TimeZone, hoy: LocalDate) -> String {
        let dia = LocalDate(date: d, timeZone: zona)
        return FormatoFicha.cuando(dia, hoy: hoy) + " a las " + hora(d, zona: zona)
    }

    /// «hoy, 10:00», «lun 19 oct, 09:00» (para listas).
    static func momento(_ dia: LocalDate, hora: String?, hoy: LocalDate) -> String {
        let d = dia == hoy ? "hoy" : (dia == hoy.adding(days: -1) ? "ayer" : FormatoFicha.fechaConDia(dia, hoy: hoy))
        return hora.map { "\(d), \($0)" } ?? d
    }

    /// Las funciones que sacan algo fuera de la empresa (enviar, publicar, emitir o facturar, escribir a clientes):
    /// en la ficha salen bloqueadas en «Siempre con tu OK» (SISTEMAS §6.2, regla 4; PLAN §5.2 paso 10).
    static let funcionesQueSalenFuera: Set<String> = [
        "VEN-06", "VEN-08", "VEN-12", "VEN-13", "FIN-02", "FIN-04", "FIN-10", "ENT-08", "ENT-11", "MAR-04", "MAR-05",
    ]

    static func saleFuera(_ c: CapacidadStd?, codigo: String) -> Bool {
        if funcionesQueSalenFuera.contains(codigo.uppercased()) { return true }
        guard let c else { return false }
        return FuncionDeSistema.esSensible(c.nombre + " " + (c.produce ?? ""))
    }
}
