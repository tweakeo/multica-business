// Procedencia: port reescrito de Programa v0.5 (Manu), core/tiempo.js (`agenda`: todo lo que tiene fecha en un solo
// eje, el día juzgado por lo que cabe en él frente al tope; lo atrasado vive aparte). El tope sale de
// `.tls/config.yaml` (`agenda.tope_horas_dia`, 4 por defecto) y ENT-04 (nunca sábado ni domingo) de PLAN §4.2.
// Ver docs/PROCEDENCIA.md.
import Foundation

/// Algo del Calendario del Mac (lo inyecta quien lo lea; la carpeta no lo guarda).
public struct EventoAgenda: Sendable, Hashable {
    public let titulo: String
    public let dia: LocalDate
    public let hora: String?
    /// `nil`: sin duración conocida (no suma horas).
    public let horas: Double?

    public init(titulo: String, dia: LocalDate, hora: String? = nil, horas: Double? = nil) {
        self.titulo = titulo; self.dia = dia; self.hora = hora; self.horas = horas
    }
}

/// Un día de la semana con lo que tiene y su carga frente al tope.
public struct DiaAgenda: Sendable, Hashable, Identifiable {
    public var id: LocalDate { dia }
    public let dia: LocalDate
    public let esHoy: Bool
    public let finDeSemana: Bool
    /// Horas que caben: el tope en laborables; 0 en sábado y domingo (ENT-04).
    public let tope: Double
    /// Tareas abiertas planificadas ese día.
    public let tareas: [FotoMetricas.TareaMedida]
    /// Tareas abiertas que vencen ese día (otro reloj: el límite real).
    public let vencimientos: [FotoMetricas.TareaMedida]
    public let reuniones: [FotoMetricas.Reunion]
    public let rutinas: [FotoMetricas.Rutina]
    public let eventos: [EventoAgenda]
    /// Facturas pendientes que vencen ese día (cobros previstos).
    public let cobros: [FotoMetricas.Factura]
    /// Horas planificadas (solo lo que tiene estimación o duración).
    public let horas: Double
    /// Cosas planificadas sin estimación ni duración (no se suman: no se inventan horas).
    public let sinEstimar: Int
    public let pasaDelTope: Bool
    /// Aviso con texto (el color nunca va solo).
    public let aviso: String?

    /// «2,5 h de 4».
    public var textoCarga: String {
        "\(FormatoBase.cifra(horas, decimales: horas == horas.rounded() ? 0 : 1)) h de \(FormatoBase.cifra(tope))"
    }

    public var vacio: Bool { tareas.isEmpty && reuniones.isEmpty && rutinas.isEmpty && eventos.isEmpty }
}

/// La semana de lunes a domingo frente al tope de horas.
public struct SemanaAgenda: Sendable, Hashable {
    public let lunes: LocalDate
    public let hoy: LocalDate
    public let dias: [DiaAgenda]
    public let tope: Double
    /// Tareas abiertas planificadas antes de hoy: lo atrasado no se mezcla con el lunes.
    public let atrasadas: [FotoMetricas.TareaMedida]

    /// «Semana del 19 al 25 de octubre».
    public var titulo: String { FormatoBase.semana(lunes) }
    public var totalHoras: Double { (dias.map(\.horas).reduce(0, +) * 10).rounded() / 10 }
    /// Horas que caben en la semana (cinco días laborables).
    public var capacidad: Double { tope * Double(dias.filter { !$0.finDeSemana }.count) }
    public var diasPasados: [DiaAgenda] { dias.filter(\.pasaDelTope) }
    public var diaDeHoy: DiaAgenda? { dias.first(where: \.esHoy) }

    /// «Hoy tienes 2,5 h de 4», «Hoy no tienes nada planificado», «Hoy tienes 2 tareas sin estimar».
    public var fraseHoy: String {
        guard let d = diaDeHoy else { return "Hoy no tienes nada planificado" }
        if d.finDeSemana { return d.vacio ? "Hoy es fin de semana: nada planificado" : "Hoy es fin de semana y tienes cosas planificadas" }
        if d.horas > 0 {
            var s = "Hoy tienes \(d.textoCarga)"
            if d.sinEstimar > 0 { s += d.sinEstimar == 1 ? " y 1 cosa sin estimar" : " y \(d.sinEstimar) cosas sin estimar" }
            return s
        }
        if d.sinEstimar > 0 { return d.sinEstimar == 1 ? "Hoy tienes 1 cosa sin estimar" : "Hoy tienes \(d.sinEstimar) cosas sin estimar" }
        return "Hoy no tienes nada planificado"
    }
}

/// Lo que hay por delante, día a día, con su carga.
public struct Agenda: Sendable {
    public let foto: FotoMetricas
    public let eventos: [EventoAgenda]

    public init(foto: FotoMetricas, eventos: [EventoAgenda] = []) {
        self.foto = foto; self.eventos = eventos
    }

    public var tope: Double { foto.config.topeHorasDia }

    /// La semana (de lunes a domingo) que contiene `dia` (por defecto, hoy).
    public func semana(de dia: LocalDate? = nil) -> SemanaAgenda {
        let hoy = foto.hoy
        let lunes = FormatoBase.lunes(de: dia ?? hoy)
        let abiertas = foto.tareas.filter { t in
            guard t.abierta, !t.esDecision else { return false }
            return t.tarea.creada.map { $0 <= hoy } ?? true
        }
        let dias = (0..<7).map { i -> DiaAgenda in
            let d = lunes.adding(days: i)
            return self.dia(d, hoy: hoy, abiertas: abiertas)
        }
        let atrasadas = abiertas.filter { $0.tarea.planificada.map { $0 < hoy } ?? false }
            .sorted { ($0.tarea.planificada!, $0.tarea.ruta) < ($1.tarea.planificada!, $1.tarea.ruta) }
        return SemanaAgenda(lunes: lunes, hoy: hoy, dias: dias, tope: tope, atrasadas: atrasadas)
    }

    func dia(_ d: LocalDate, hoy: LocalDate, abiertas: [FotoMetricas.TareaMedida]) -> DiaAgenda {
        let finde = d.isWeekend
        let tareas = abiertas.filter { $0.tarea.planificada == d }
        let vencen = foto.tareas.filter { $0.abierta && !$0.esDecision && $0.tarea.vence == d }
        let reuniones = foto.reuniones.filter { $0.fecha == d }
        let rutinas = foto.rutinas.filter { $0.activa && Self.toca($0, en: d) }
        let eventos = self.eventos.filter { $0.dia == d }
        let cobros = foto.facturas.filter { f in f.vence == d && (KPIEvaluador(foto: foto, metas: nil).pendiente(f) ?? 0) > 0 }
        var horas = 0.0, sinEstimar = 0
        for t in tareas { if let h = t.estimacionH, h > 0 { horas += h } else { sinEstimar += 1 } }
        for r in reuniones { if let m = r.duracionMin, m > 0 { horas += m / 60 } else { sinEstimar += 1 } }
        for r in rutinas { if let m = r.duracionMin, m > 0 { horas += m / 60 } else { sinEstimar += 1 } }
        for e in eventos { if let h = e.horas, h > 0 { horas += h } else { sinEstimar += 1 } }
        horas = (horas * 10).rounded() / 10
        let tope = finde ? 0 : self.tope
        let pasa = finde ? !tareas.isEmpty : (tope > 0 && horas > tope)
        var aviso: String?
        if finde, !tareas.isEmpty {
            aviso = tareas.count == 1 ? "1 tarea planificada en fin de semana: se pasa al lunes"
                : "\(tareas.count) tareas planificadas en fin de semana: se pasan al lunes"
        } else if pasa {
            aviso = "Pasa del tope: \(KPIEvaluador.formatear(horas, unidad: "h")) de \(FormatoBase.cifra(tope))"
        }
        return DiaAgenda(dia: d, esHoy: d == hoy, finDeSemana: finde, tope: tope, tareas: tareas, vencimientos: vencen,
                         reuniones: reuniones, rutinas: rutinas, eventos: eventos, cobros: cobros, horas: horas,
                         sinEstimar: sinEstimar, pasaDelTope: pasa, aviso: aviso)
    }

    /// Una rutina toca ese día: semanal por su día de la semana; mensual por su día del mes.
    static func toca(_ r: FotoMetricas.Rutina, en d: LocalDate) -> Bool {
        guard let dia = r.dia?.trimmingCharacters(in: .whitespaces), !dia.isEmpty else { return false }
        let cad = TextFolding.fold(r.cadencia ?? "semanal")
        if cad.hasPrefix("mensual") { return Int(dia) == d.day }
        if cad.hasPrefix("trimestral") { return Int(dia) == d.day && [1, 4, 7, 10].contains(d.month) }
        let nombres = ["lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo"]
        let cortos = ["lun", "mar", "mie", "jue", "vie", "sab", "dom"]
        let f = TextFolding.fold(dia)
        if let i = nombres.firstIndex(of: f) ?? cortos.firstIndex(of: f) { return i + 1 == d.weekday }
        return false
    }

    /// ENT-04: la fecha planificada nunca cae en sábado ni domingo (se pasa al lunes).
    public static func laborable(_ d: LocalDate) -> LocalDate { Tarea.laborable(d) }
}
