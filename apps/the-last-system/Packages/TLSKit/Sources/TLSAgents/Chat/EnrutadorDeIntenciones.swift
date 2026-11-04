import Foundation
import TLSCore

// ⌘J sin Claude (PLAN §5.3 «ClaudeLocator» 4): el enrutador determinista de 14 intenciones, portado de
// `PROG/core/hablar.js` (Programa v0.5, autor Manu; ver `docs/PROCEDENCIA.md`). Dos decisiones de allí se mantienen:
// 1. **Enruta, no contesta**: elige la consulta que responde y los datos los pone el núcleo (nunca una cifra inventada;
//    sin dato, «Sin dato»).
// 2. **No escribe: propone**. Lo que cambia algo («apunta…», «mueve…») vuelve como propuesta con su botón; lo
//    confirma la persona.

/// Las 14 intenciones de Programa.
public enum Intencion: String, Sendable, Hashable, CaseIterable {
    case hoy, semana, atrasado, cliente, pipeline, dinero, ritmo, cuello, proyectos, equipo, contenido
    case crearTarea = "crear_tarea", mover, buscar

    /// Cómo se dice en el menú de ayuda.
    public var dice: String {
        switch self {
        case .hoy: "Qué tengo hoy"
        case .semana: "Cómo viene la semana"
        case .atrasado: "Qué llevo atrasado"
        case .cliente: "Cómo va un cliente"
        case .pipeline: "Cómo van las ventas"
        case .dinero: "Cómo estamos de dinero"
        case .ritmo: "Vamos a llegar a los objetivos"
        case .cuello: "Qué me está frenando"
        case .proyectos: "Cómo van las entregas"
        case .equipo: "Quién hace qué"
        case .contenido: "Qué toca publicar"
        case .crearTarea: "Apuntar una tarea"
        case .mover: "Mover algo de fecha"
        case .buscar: "Buscar cualquier cosa"
        }
    }

    /// Las que cambian algo (vuelven como propuesta, nunca escriben).
    public var escribe: Bool { self == .crearTarea || self == .mover }

    /// Adónde lleva la respuesta (`hoy`, `area:VEN`…).
    public var ir: String? {
        switch self {
        case .hoy: "hoy"
        case .semana, .atrasado: "tareas"
        case .pipeline: "area:VEN"
        case .dinero: "area:FIN"
        case .ritmo, .cuello: "area:DIR"
        case .proyectos: "area:ENT"
        case .equipo: "area:EQU"
        case .contenido: "area:MAR"
        default: nil
        }
    }
}

/// Lo que se ha entendido: intención y argumentos (`quien`, `termino`, `titulo`, `que`, `cuando`).
public struct IntencionReconocida: Sendable, Hashable {
    public var intencion: Intencion
    public var argumentos: [String: String]
}

public enum EnrutadorDeIntenciones {
    /// Patrones de Programa (sin distinguir mayúsculas; `\b` de Unicode).
    static let patrones: [Intencion: NSRegularExpression] = {
        func r(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
        return [
            .hoy: r(#"\b(hoy|el d[ií]a|ahora mismo|qu[eé] hago)\b"#),
            .semana: r(#"\b(semana|pr[oó]ximos d[ií]as|viene)\b"#),
            .atrasado: r(#"\b(atrasad|retras|vencid|arrastr|pendiente de ayer)\w*"#),
            .cliente: r(#"\b(c[oó]mo va|qu[eé] hay de|estado de|cu[eé]ntame de)\b\s+(.+)"#),
            .pipeline: r(#"\b(pipeline|ventas|oportunidad|oportunidades|embudo|leads?)\b"#),
            .dinero: r(#"\b(dinero|caja|saldo|facturad|ingres|gast|cobr|banco|runway)\w*"#),
            .ritmo: r(#"\b(ritmo|objetivo|meta|vamos a llegar|trimestre)\w*"#),
            .cuello: r(#"\b(cuello|frena|bloque|atasc|diagn[oó]stic|etapa|qu[eé] va mal)\w*"#),
            .proyectos: r(#"\b(proyecto|entrega|cliente[s]? activ|obra)\w*"#),
            .equipo: r(#"\b(equipo|qui[eé]n|carga de|agentes?|asistentes?)\b"#),
            .contenido: r(#"\b(contenido|publicar|instagram|reel|marca)\w*"#),
            .crearTarea: r(#"^(?:crea|apunta|a[ñn]ade|nueva tarea|recu[eé]rdame|tengo que)\b[:\s]*(.+)"#),
            .mover: r(#"\b(mueve|aplaza|pasa|retrasa)\b\s+(.+?)\s+(?:a|para)\s+(ma[ñn]ana|hoy|el lunes|la semana que viene|\d{4}-\d{2}-\d{2})"#),
            .buscar: r(#"\b(busca|encuentra|d[oó]nde est[aá]|qui[eé]n es)\b\s+(.+)"#),
        ]
    }()

    /// El orden importa (como en Programa): las que escriben ganan («crea una tarea de seguimiento del cliente X»
    /// también casa con «cliente»), y `cliente` va la última porque recoge todo lo que sobra («cómo va el pipeline»
    /// y «cómo va Espacius» empiezan igual).
    public static let orden: [Intencion] = [.crearTarea, .mover, .buscar, .hoy, .semana, .atrasado, .pipeline, .dinero,
                                            .ritmo, .cuello, .proyectos, .equipo, .contenido, .cliente]

    /// La intención de un mensaje, o `nil` si ninguna encaja.
    public static func reconocer(_ texto: String) -> IntencionReconocida? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let ns = t as NSString
        for i in orden {
            guard let p = patrones[i], let m = p.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) else { continue }
            func g(_ n: Int) -> String? {
                guard n < m.numberOfRanges, m.range(at: n).location != NSNotFound else { return nil }
                return ns.substring(with: m.range(at: n)).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            }
            var args: [String: String] = [:]
            switch i {
            case .cliente: args["quien"] = g(2)
            case .crearTarea: args["titulo"] = g(1)
            case .mover: args["que"] = g(2); args["cuando"] = g(3)
            case .buscar: args["termino"] = g(2)
            default: break
            }
            return IntencionReconocida(intencion: i, argumentos: args)
        }
        return nil
    }
}

/// Una fila de una respuesta (tipo · texto · valor), con su ficha si la hay.
public struct FilaDeRespuesta: Sendable, Hashable {
    public var tipo: String
    public var texto: String
    public var valor: String?
    /// En rojo (con icono y texto, nunca solo color).
    public var mal: Bool
    public var ruta: VaultPath?

    public init(tipo: String, texto: String, valor: String? = nil, mal: Bool = false, ruta: VaultPath? = nil) {
        self.tipo = tipo; self.texto = texto; self.valor = valor; self.mal = mal; self.ruta = ruta
    }
}

/// Lo que una respuesta propone (la persona confirma; el chat nunca escribe).
public struct PropuestaDeChat: Sendable, Hashable {
    public enum Accion: Sendable, Hashable {
        /// Tarea nueva para la persona, planificada ese día.
        case crearTarea(titulo: String, planificada: LocalDate)
        /// Cambia solo `planificada` (nunca `vence`); ENT-04 la corre al lunes si cae en fin de semana.
        case moverPlanificada(tarea: VaultPath, a: LocalDate)
    }

    public var etiqueta: String
    public var aviso: String
    public var accion: Accion
}

/// Respuesta del chat.
public struct RespuestaDeChat: Sendable, Hashable {
    public enum Modo: String, Sendable, Hashable {
        /// Sin Claude: el enrutador de 14 intenciones.
        case sinClaude
        /// Con Claude (Mika).
        case claude
    }

    public var texto: String
    public var filas: [FilaDeRespuesta]
    public var intencion: Intencion?
    /// Adónde lleva («Ver en Ventas»).
    public var ir: String?
    public var propuesta: PropuestaDeChat?
    public var modo: Modo
    public var simulado: Bool

    public init(texto: String, filas: [FilaDeRespuesta] = [], intencion: Intencion? = nil, ir: String? = nil,
                propuesta: PropuestaDeChat? = nil, modo: Modo = .sinClaude, simulado: Bool = false) {
        self.texto = texto; self.filas = filas; self.intencion = intencion; self.ir = ir; self.propuesta = propuesta
        self.modo = modo; self.simulado = simulado
    }
}

/// Las respuestas de cada intención con los datos del núcleo (métricas, tareas, dominio). Determinista; lo privado,
/// lo retirado a `Archivo/` y las plantillas no salen.
public struct RespuestasSinClaude: Sendable {
    public let snapshot: VaultSnapshot
    public let reloj: Reloj

    public init(snapshot: VaultSnapshot, reloj: Reloj) { self.snapshot = snapshot; self.reloj = reloj }

    /// Responde a un mensaje (o enseña lo que sabe mirar si no encaja ninguna).
    public func responder(_ texto: String) -> RespuestaDeChat {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return RespuestaDeChat(texto: "Dime algo.") }
        guard let r = EnrutadorDeIntenciones.reconocer(t) else {
            return RespuestaDeChat(texto: "No sé contestar a eso todavía. Esto es lo que sí sé mirar:",
                                   filas: Intencion.allCases.map { FilaDeRespuesta(tipo: $0.escribe ? "Propone" : "Consulta", texto: $0.dice) })
        }
        var respuesta = responder(r)
        respuesta.intencion = r.intencion
        if respuesta.ir == nil { respuesta.ir = r.intencion.ir }
        return respuesta
    }

    var panel: PanelMetricas { PanelMetricas.calcular(snapshot: snapshot, reloj: reloj) }

    static func euros(_ v: Double?) -> String {
        guard let v else { return "Sin dato" }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.minimumGroupingDigits = 1
        return (f.string(from: NSNumber(value: v)) ?? "\(Int(v))") + " €"
    }

    static func horas(_ h: Double) -> String {
        let r = (h * 10).rounded() / 10
        return (r == r.rounded() ? "\(Int(r))" : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")) + " h"
    }

    func visible(_ p: VaultPath) -> Bool {
        !snapshot.layout.isPrivate(p) && p.components.first != "Archivo" && !VaultSnapshot.isTemplatePath(p)
    }

    func responder(_ r: IntencionReconocida) -> RespuestaDeChat {
        switch r.intencion {
        case .hoy: return hoy()
        case .semana: return semana()
        case .atrasado: return atrasado()
        case .cliente: return cliente(r.argumentos["quien"] ?? "")
        case .pipeline: return pipeline()
        case .dinero: return dinero()
        case .ritmo: return ritmo()
        case .cuello: return cuello()
        case .proyectos: return proyectos()
        case .equipo: return equipo()
        case .contenido: return contenido()
        case .crearTarea: return crearTarea(r.argumentos["titulo"] ?? "")
        case .mover: return mover(r.argumentos["que"] ?? "", cuando: r.argumentos["cuando"] ?? "")
        case .buscar: return buscar(r.argumentos["termino"] ?? "")
        }
    }

    func hoy() -> RespuestaDeChat {
        let p = panel
        guard let dia = p.semana.diaDeHoy else { return RespuestaDeChat(texto: p.frase()) }
        var texto = "\(dia.tareas.count) \(dia.tareas.count == 1 ? "tarea planificada" : "tareas planificadas") (\(dia.textoCarga)), "
        texto += "\(dia.reuniones.count) \(dia.reuniones.count == 1 ? "reunión" : "reuniones") y \(p.semana.atrasadas.count) "
        texto += p.semana.atrasadas.count == 1 ? "cosa atrasada. " : "cosas atrasadas. "
        texto += p.alertas.first.map { "Lo primero: \($0.texto)." } ?? "Nada en rojo."
        var filas = dia.tareas.filter { visible($0.tarea.ruta) }.map {
            FilaDeRespuesta(tipo: "Tarea", texto: $0.tarea.titulo, valor: $0.estimacionH.map(Self.horas), ruta: $0.tarea.ruta)
        }
        filas += dia.reuniones.map { FilaDeRespuesta(tipo: "Reunión", texto: $0.titulo, valor: $0.hora) }
        filas += p.alertas.prefix(3).map { FilaDeRespuesta(tipo: "En rojo", texto: $0.texto, mal: true, ruta: $0.ruta) }
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func semana() -> RespuestaDeChat {
        let s = panel.semana
        let pasados = s.diasPasados.count
        var texto = "\(Self.horas(s.totalHoras)) planificadas esta semana, con un tope de \(Self.horas(s.tope)) al día. "
        texto += pasados == 0 ? "Ningún día se pasa del tope." : "Te pasas del tope \(pasados) \(pasados == 1 ? "día" : "días")."
        let dias = ["lun", "mar", "mié", "jue", "vie", "sáb", "dom"]
        let filas = s.dias.filter { !$0.finDeSemana }.map { d in
            FilaDeRespuesta(tipo: "\(dias[d.dia.weekday - 1]) \(d.dia.day)",
                            texto: "\(d.tareas.count) tareas · \(d.reuniones.count) reuniones", valor: d.textoCarga, mal: d.pasaDelTope)
        }
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func atrasado() -> RespuestaDeChat {
        let p = panel
        let atrasadas = p.semana.atrasadas.filter { visible($0.tarea.ruta) }
        let vencidas = p.foto.facturas.filter { f in
            guard let v = f.vence, v < p.hoy, let pend = p.evaluador.pendiente(f) else { return false }
            return pend > 0.004
        }
        var texto = "\(atrasadas.count) \(atrasadas.count == 1 ? "tarea pasada" : "tareas pasadas") de fecha"
        if vencidas.isEmpty {
            texto += ". Ninguna factura vencida."
        } else {
            let total = vencidas.compactMap { p.evaluador.pendiente($0) }.reduce(0, +)
            texto += " y \(vencidas.count) \(vencidas.count == 1 ? "factura vencida" : "facturas vencidas") sin cobrar (\(Self.euros(total)))."
        }
        var filas = atrasadas.prefix(10).map { t -> FilaDeRespuesta in
            let dias = (t.tarea.planificada ?? t.tarea.vence).map { RangoFechas.diasEntre($0, p.hoy) } ?? 0
            return FilaDeRespuesta(tipo: "\(dias) días", texto: t.tarea.titulo, valor: t.tarea.area?.nombre, mal: dias > 7,
                                   ruta: t.tarea.ruta)
        }
        filas += vencidas.map { FilaDeRespuesta(tipo: "Factura", texto: "\($0.tercero) · \($0.numero)",
                                                valor: Self.euros(p.evaluador.pendiente($0)), mal: true, ruta: $0.ficha) }
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func cliente(_ quien: String) -> RespuestaDeChat {
        let lectura = LecturaDominio(snapshot: snapshot, reloj: reloj)
        let q = TextFolding.fold(quien)
        let empresas = lectura.fichas(.organization).filter { !$0.privada && visible($0.ruta) }
        guard !q.isEmpty, let e = empresas.filter({ TextFolding.fold($0.nombre).contains(q) }).min(by: { $0.nombre.count < $1.nombre.count }),
              let x = Expediente.de(e.ruta, en: lectura) else {
            return RespuestaDeChat(texto: "No encuentro ninguna empresa que se parezca a «\(quien)».")
        }
        let n = x.numeros
        func cent(_ c: Int?) -> String { c.map { Self.euros(Double($0) / 100) } ?? "Sin dato" }
        var texto = "\(e.nombre): \(n.entregados) proyectos entregados, \(n.proyectosActivos) activos, "
        texto += "\(cent(n.facturado)) facturados y \(cent(n.pendiente)) pendientes de cobro."
        if let d = n.diasSinContacto { texto += " Último movimiento hace \(d) días." }
        var filas = x.alertas.map { FilaDeRespuesta(tipo: "Alerta", texto: $0.texto, valor: $0.que, mal: $0.nivel == .mal, ruta: $0.ruta) }
        filas += x.oportunidades.prefix(5).map { FilaDeRespuesta(tipo: "Oportunidad", texto: $0.nombre, ruta: $0.ruta) }
        filas += x.proyectos.prefix(5).map { FilaDeRespuesta(tipo: "Proyecto", texto: $0.nombre, ruta: $0.ruta) }
        return RespuestaDeChat(texto: texto, filas: filas, ir: "ruta:" + e.ruta.raw)
    }

    func pipeline() -> RespuestaDeChat {
        let p = panel
        let abiertas = p.foto.oportunidades.filter { !($0.estado?.cerrada ?? false) && $0.estado != .pausada && visible($0.ruta) }
        let conValor = abiertas.compactMap(\.valor)
        var texto = "\(abiertas.count) \(abiertas.count == 1 ? "oportunidad abierta" : "oportunidades abiertas")"
        texto += conValor.isEmpty ? " (sin valor escrito)." : " por \(Self.euros(conValor.reduce(0, +)))"
        if !conValor.isEmpty, conValor.count < abiertas.count { texto += " (\(abiertas.count - conValor.count) sin valor)." }
        else if !conValor.isEmpty { texto += "." }
        let quietas = p.evaluador.evaluar("VEN-STALE7")
        if case .cifra = quietas.medida { texto += " Quietas una semana o más: \(quietas.textoValor)." }
        let filas = abiertas.sorted { ($0.valor ?? -1) > ($1.valor ?? -1) }.prefix(10).map {
            FilaDeRespuesta(tipo: $0.estado?.rawValue ?? "Sin estado", texto: $0.nombre, valor: $0.valor.map(Self.euros) ?? "Sin dato",
                            ruta: $0.ruta)
        }
        return RespuestaDeChat(texto: texto, filas: Array(filas))
    }

    func dinero() -> RespuestaDeChat {
        let ev = panel.evaluador
        let caja = ev.evaluar("FIN-CASH"), meses = ev.evaluar("FIN-RUNWAY"), deben = ev.evaluar("FIN-AR")
        let texto = "Caja: \(caja.textoValor). Meses de caja: \(meses.textoValor). Te deben: \(deben.textoValor)."
        let filas = [caja, meses, deben, ev.evaluar("FIN-MARGIN")].map {
            FilaDeRespuesta(tipo: $0.codigo, texto: $0.indicador, valor: $0.textoValor, mal: $0.estado == .mal)
        }
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func ritmo() -> RespuestaDeChat {
        let p = panel
        let r = p.ritmoEmpresa
        let texto = "Ritmo global \(r.pct.map { "\($0) %" } ?? "sin dato") sobre lo que tocaría a estas alturas, con \(r.enRiesgo) "
            + "\(r.enRiesgo == 1 ? "objetivo" : "objetivos") en riesgo de \(r.objetivos)."
        let filas = p.objetivos.filter { visible($0.objetivo.ruta) }.map { o in
            FilaDeRespuesta(tipo: o.pct.map { "\($0) %" } ?? "Sin dato", texto: o.objetivo.titulo,
                            valor: "\(o.real.map { FormatoBase.cifra($0) } ?? "Sin dato") de \(o.objetivo.meta.map { FormatoBase.cifra($0) } ?? "Sin meta") \(o.unidad)",
                            mal: !(o.estado.enTrayectoria), ruta: o.objetivo.ruta)
        }
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func cuello() -> RespuestaDeChat {
        let p = panel
        var filas: [FilaDeRespuesta] = []
        if !p.mapa.textoCuello.isEmpty { filas.append(FilaDeRespuesta(tipo: "Cuello", texto: p.mapa.textoCuello, mal: true)) }
        filas += p.chequeos.filter { $0.n > 0 }.prefix(6).map {
            FilaDeRespuesta(tipo: $0.esRojo ? "Regla rota" : "Revisar", texto: $0.titulo, valor: "\($0.n)", mal: $0.esRojo)
        }
        return RespuestaDeChat(texto: p.mapa.veredicto, filas: filas)
    }

    func proyectos() -> RespuestaDeChat {
        let p = panel
        let vivos = p.foto.proyectos.filter { ($0.estado == .enCurso || $0.estado == .sinEmpezar) && visible($0.ruta) }
        let tarde = vivos.filter { ($0.fin.map { $0 < p.hoy }) ?? false }
        let texto = "\(vivos.count) \(vivos.count == 1 ? "proyecto" : "proyectos") en marcha"
            + (tarde.isEmpty ? ", ninguno fuera de fecha." : ", \(tarde.count) fuera de fecha.")
        let filas = vivos.sorted { ($0.fin ?? .init(year: 9999, month: 1, day: 1)!) < ($1.fin ?? .init(year: 9999, month: 1, day: 1)!) }.map { pr in
            FilaDeRespuesta(tipo: pr.estado?.rawValue ?? "Sin estado", texto: pr.nombre, valor: pr.fin.map(FormatoBase.fechaConDia) ?? "sin fecha",
                            mal: tarde.contains(pr), ruta: pr.ruta)
        }
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func equipo() -> RespuestaDeChat {
        let abiertas = panel.foto.tareas.filter { $0.abierta && visible($0.tarea.ruta) }
        var porQuien: [String: (n: Int, h: Double)] = [:]
        for t in abiertas {
            var quien = t.tarea.responsable ?? "Sin responsable"
            if quien.hasPrefix("agente:") { quien = String(quien.dropFirst("agente:".count)).capitalized + " (asistente)" }
            var v = porQuien[quien] ?? (0, 0)
            v.n += 1
            v.h += t.estimacionH ?? 0
            porQuien[quien] = v
        }
        let filas = porQuien.sorted { $0.value.h > $1.value.h || ($0.value.h == $1.value.h && $0.key < $1.key) }.map {
            FilaDeRespuesta(tipo: $0.key, texto: "\($0.value.n) \($0.value.n == 1 ? "tarea abierta" : "tareas abiertas")",
                            valor: Self.horas($0.value.h))
        }
        let texto = "\(porQuien.count) \(porQuien.count == 1 ? "persona o asistente" : "personas o asistentes") con trabajo asignado."
        return RespuestaDeChat(texto: texto, filas: filas)
    }

    func contenido() -> RespuestaDeChat {
        let piezas = panel.foto.contenidos.filter { visible($0.ruta) }
        let sin = piezas.filter { !$0.esPublicado }
        let filas = piezas.sorted { ($0.publicado ?? .init(year: 1, month: 1, day: 1)!) > ($1.publicado ?? .init(year: 1, month: 1, day: 1)!) }
            .prefix(15).map { FilaDeRespuesta(tipo: $0.estado ?? "Sin estado", texto: $0.titulo, valor: $0.publicado.map(FormatoBase.fechaConDia) ?? "sin fecha", ruta: $0.ruta) }
        return RespuestaDeChat(texto: "\(sin.count) \(sin.count == 1 ? "pieza" : "piezas") sin publicar en el calendario.", filas: Array(filas))
    }

    func crearTarea(_ titulo: String) -> RespuestaDeChat {
        var t = titulo
        for patron in [#"^(una|un|la|el)\s+"#, #"^(tarea|nota|recordatorio)\s+(de|para|:)?\s*"#, #"^que\s+"#] {
            t = t.replacingOccurrences(of: patron, with: "", options: [.regularExpression, .caseInsensitive])
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return RespuestaDeChat(texto: "Dime qué hay que hacer y la apunto.") }
        let dia = Tarea.laborable(reloj.hoy)
        return RespuestaDeChat(
            texto: "Preparada: «\(t)». La creo para el \(FormatoBase.fechaConDia(dia)) si me lo confirmas.",
            propuesta: PropuestaDeChat(etiqueta: "Crear la tarea", aviso: "Se apunta en tus tareas; puedes deshacerlo.",
                                       accion: .crearTarea(titulo: t, planificada: dia)))
    }

    func mover(_ que: String, cuando: String) -> RespuestaDeChat {
        let q = TextFolding.fold(que)
        let abiertas = TaskStore(snapshot: snapshot, reloj: reloj).tareas.filter {
            !($0.estado?.cerrada ?? false) && visible($0.ruta) && TextFolding.fold($0.titulo).contains(q)
        }
        guard !q.isEmpty, let t = abiertas.min(by: { ($0.planificada ?? .init(year: 9999, month: 1, day: 1)!) < ($1.planificada ?? .init(year: 9999, month: 1, day: 1)!) }) else {
            return RespuestaDeChat(texto: "No encuentro ninguna tarea abierta que se parezca a «\(que)».")
        }
        let c = TextFolding.fold(cuando)
        var dia = reloj.hoy
        if c.contains("manana") { dia = dia.adding(days: 1) }
        else if c.contains("semana que viene") { dia = dia.adding(days: 7) }
        else if c.contains("lunes") { dia = dia.adding(days: (8 - dia.weekday) % 7 == 0 ? 7 : (8 - dia.weekday) % 7) }
        else if let d = LocalDate(parsing: cuando) { dia = d }
        let final = Tarea.laborable(dia)
        var texto = "«\(t.titulo)» pasaría al \(FormatoBase.fechaConDia(final))."
        if final != dia { texto += " Caía en fin de semana: la corro al lunes." }
        return RespuestaDeChat(
            texto: texto, filas: [FilaDeRespuesta(tipo: "Tarea", texto: t.titulo, valor: t.planificada.map(FormatoBase.fechaConDia), ruta: t.ruta)],
            propuesta: PropuestaDeChat(etiqueta: "Mover al \(FormatoBase.fechaConDia(final))", aviso: "Solo cambia el día planificado, nunca la fecha límite.",
                                       accion: .moverPlanificada(tarea: t.ruta, a: final)))
    }

    func buscar(_ termino: String) -> RespuestaDeChat {
        let q = TextFolding.fold(termino.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return RespuestaDeChat(texto: "Dime qué busco.") }
        let notas = snapshot.files.filter { $0.ext == "md" && visible($0) && !$0.components.contains(".tls") }
            .filter { TextFolding.fold($0.stem).contains(q) }.prefix(20)
        let filas = notas.map { FilaDeRespuesta(tipo: $0.components.first ?? "", texto: $0.stem, ruta: $0) }
        return RespuestaDeChat(texto: filas.isEmpty ? "Nada que se parezca a «\(termino)»." : "\(filas.count) resultados para «\(termino)».",
                               filas: Array(filas))
    }
}
