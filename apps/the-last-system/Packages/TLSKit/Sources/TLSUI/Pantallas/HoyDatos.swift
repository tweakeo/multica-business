import Foundation
import TLSCore
import TLSDesign

// Lo que enseña Hoy (PLAN §6.2, DISENO §6, maqueta M2-Hoy), calculado de una vez con la foto de la carpeta y fuera
// del hilo principal: el foco y los números salen de `PanelMetricas` (rol de números), «Pide tu decisión» de la bandeja
// del dominio (`BandejaDeDecisiones`) y los módulos de `DatosModulos`. Determinista: sin asistentes (llegan en F4).

/// Las secciones de Hoy, en orden. Alertas **solo** si hay algo en rojo.
enum SeccionHoy: String, Sendable, Hashable, CaseIterable {
    case cabecera, foco, revisar, decisiones, alertas, inicio, mika
}

/// Todo lo de Hoy. Puro y `Sendable`.
struct DatosHoy: Sendable {
    let hoy: LocalDate
    /// Hora de ahora en la zona de la carpeta («9:05»), para la línea «Ahora» de lo que cabe hoy.
    let hora: String
    let minutosAhora: Int
    let panel: PanelMetricas
    let bandeja: BandejaDeDecisiones
    /// Lo que pide tu decisión hoy (la bandeja sin lo que pospusiste): el número de la insignia.
    let decisiones: [TarjetaDecision]
    /// El detalle 1-3-1 de cada tarjeta de la bandeja (también de las pospuestas), por su `id`.
    let detalles: [String: DetalleDecision]
    let modulos: DatosModulos

    /// El foco de hoy: siempre exactamente uno.
    var foco: Tarjeta { panel.foco }
    var pendientes: Int { decisiones.count }
    /// «2 cosas piden tu decisión. Hoy tienes 3 h de 4.»
    var frase: String { panel.frase(decisiones: pendientes) }
    var alertas: [AlertaHoy] { panel.alertas }
    var hayRojo: Bool { !alertas.isEmpty }
    /// «Revisé a las 8:45: nada en rojo.» (sin asistente: sale de los chequeos).
    var lineaMika: String { panel.lineaMika(hora: "8:45") }
    var semana: SemanaAgenda { panel.semana }
    var cabe: [ElementoDia] { modulos.cabe }

    /// Las de la bandeja que pospusiste (vuelven el día que dijiste).
    var pospuestas: [TarjetaDecision] {
        let vistas = Set(decisiones.map(\.id))
        return bandeja.visibles.filter { !vistas.contains($0.id) }
    }

    /// «Tu día»: «2,5 h de 4», «Nada planificado» o «Fin de semana».
    var textoDia: String {
        guard let d = semana.diaDeHoy else { return "Nada planificado" }
        if d.finDeSemana { return "Fin de semana" }
        if d.horas > 0 { return d.textoCarga }
        return d.sinEstimar > 0 ? (d.sinEstimar == 1 ? "1 sin estimar" : "\(d.sinEstimar) sin estimar") : "Nada planificado"
    }

    /// Qué secciones hay hoy.
    func secciones(hayQueRevisar: Bool) -> [SeccionHoy] {
        var s: [SeccionHoy] = [.cabecera, .foco]
        if hayQueRevisar { s.append(.revisar) }
        s.append(.decisiones)
        if hayRojo { s.append(.alertas) }
        s += [.inicio, .mika]
        return s
    }

    /// Las áreas con algo en rojo, en orden y sin repetir («1 · Ventas» en la cabecera).
    var areasEnRojo: [AreaCode] {
        var out: [AreaCode] = []
        for a in alertas { if let x = a.area, !out.contains(x) { out.append(x) } }
        return out
    }

    // MARK: Calcular

    /// - Parameters:
    ///   - foto: la foto de la carpeta (`AlmacenRelaciones`); lo privado se queda fuera aquí dentro.
    ///   - conflictos: las tarjetas de «Revisar» de la sesión (archivos en conflicto y repetidos).
    ///   - estados, historial: lo que decidiste sobre las tarjetas (guardado fuera de la carpeta).
    ///   - pospuestas: decisiones pospuestas hasta un día (fuera de la carpeta).
    ///   - gobierno: F4 · el Autorizador de la carpeta: la bandeja suma lo de los asistentes (aprobaciones, preguntas,
    ///     propuestas de mejora, CRITERIO y permisos cambiados fuera de la app; `BandejaDeDecisiones.consultar(…gobierno:)`).
    ///   - eventos: F5 · lo ocupado de los otros calendarios del Mac («Ocupado», sin títulos), para «Lo que cabe hoy»,
    ///     «Hoy tienes 3 h de 4» y la semana frente al tope (`CalendarioEnHoy`).
    static func calcular(foto: VaultSnapshot, conflictos: [ConflictRecord] = [], persona: String? = nil,
                         estados: [EstadoTarjeta] = [], historial: [DecisionTarjeta] = [],
                         pospuestas: [String: LocalDate] = [:], reloj: Reloj? = nil, gobierno: Autorizador? = nil,
                         eventos: [EventoAgenda] = []) -> DatosHoy {
        let config = ConfigMetricas.leer(foto.text(VaultPath(".tls/config.yaml")))
        let zona = TimeZone(identifier: config.zona) ?? TimeZone(identifier: "Europe/Madrid") ?? .current
        let r = reloj ?? Reloj.deCarpeta(foto, zona: zona)
        let panel = PanelMetricas.calcular(snapshot: foto, reloj: r, eventos: eventos, estados: estados, historial: historial)
        let lectura = LecturaDominio(snapshot: foto, reloj: r)
        let bandeja = gobierno.map { a in
            BandejaDeDecisiones.consultar(lectura, conflictos: conflictos, persona: persona, gobierno: .de(a), estado: a.estado)
        } ?? BandejaDeDecisiones.consultar(lectura, conflictos: conflictos, persona: persona)
        let decisiones = bandeja.visibles.filter { t in pospuestas[t.id].map { $0 <= r.hoy } ?? true }
        let modulos = DatosModulos.calcular(foto: foto, panel: panel, pendientes: decisiones.count, reloj: r)
        var detalles: [String: DetalleDecision] = [:]
        if !bandeja.tarjetas.isEmpty {
            let tareas = TaskStore(snapshot: foto, reloj: r)
            let resolver = foto.resolver
            for t in bandeja.tarjetas {
                detalles[t.id] = DetalleDecision.de(t, foto: foto, hoy: r.hoy, tareas: tareas, resolver: resolver)
            }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = r.zona
        let c = cal.dateComponents([.hour, .minute], from: r.ahora)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return DatosHoy(hoy: r.hoy, hora: String(format: "%d:%02d", h, m), minutosAhora: h * 60 + m, panel: panel,
                        bandeja: bandeja, decisiones: decisiones, detalles: detalles, modulos: modulos)
    }
}

/// Lo que decides en Hoy y en Decisiones que no va a la carpeta: tarjetas pospuestas, descartadas o resueltas, el
/// rastro de decisiones (para aprender, CRITERIO) y las decisiones pospuestas. Se guarda por empresa en `hoy.json`
/// de su estado (Application Support).
struct EstadoHoy: Sendable, Hashable, Codable {
    var version = 1
    var tarjetas: [EstadoTarjeta] = []
    var historial: [DecisionTarjeta] = []
    /// Decisión (`TarjetaDecision.id`) → día hasta el que se pospone (AAAA-MM-DD).
    var pospuestas: [String: String] = [:]

    var fechasPospuestas: [String: LocalDate] {
        var out: [String: LocalDate] = [:]
        for (k, v) in pospuestas { if let d = LocalDate(parsing: v) { out[k] = d } }
        return out
    }

    func estado(_ id: String) -> EstadoTarjeta? { tarjetas.first { $0.id == id } }

    mutating func poner(_ e: EstadoTarjeta) {
        tarjetas.removeAll { $0.id == e.id }
        tarjetas.append(e)
    }

    mutating func quitar(_ id: String) { tarjetas.removeAll { $0.id == id } }

    /// Olvida lo que ya no sirve (pospuestas que ya pasaron hace más de 30 días), para que el fichero no crezca.
    mutating func podar(hoy: LocalDate) {
        let limite = hoy.adding(days: -30)
        tarjetas.removeAll { e in
            guard !e.descartada, !e.resuelta, let p = e.pospuestaHasta else { return false }
            return p < limite
        }
        pospuestas = pospuestas.filter { LocalDate(parsing: $0.value).map { $0 >= limite } ?? false }
        if historial.count > 500 { historial = Array(historial.suffix(500)) }
    }
}

extension LocalDate {
    /// El siguiente día laborable (para «Posponer a mañana» un viernes: el lunes).
    var siguienteLaborable: LocalDate {
        var d = adding(days: 1)
        while d.isWeekend { d = d.adding(days: 1) }
        return d
    }
}
