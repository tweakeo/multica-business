import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · la semana de lunes a domingo frente al tope de horas")
struct AgendaTests {
    static let ficheros: [String: String] = [
        // Lunes 19 (hoy): 2,5 h + 1 h.
        MetricasApoyo.ruta(tarea: 1): MetricasApoyo.tarea(1, "Preparar el cierre", planificada: "2026-10-19", estimacion: 2.5),
        MetricasApoyo.ruta(tarea: 2): MetricasApoyo.tarea(2, "Llamar a la gestoría", planificada: "2026-10-19", estimacion: 1),
        // Martes 20: 3 h + 2 h = 5 h, más la rutina semanal de 30 min.
        MetricasApoyo.ruta(tarea: 3): MetricasApoyo.tarea(3, "Revisar contratos", planificada: "2026-10-20", estimacion: 3),
        MetricasApoyo.ruta(tarea: 4): MetricasApoyo.tarea(4, "Ordenar facturas", planificada: "2026-10-20", estimacion: 2),
        // Miércoles 21: sin estimar (no se inventan horas).
        MetricasApoyo.ruta(tarea: 5): MetricasApoyo.tarea(5, "Pensar la oferta", planificada: "2026-10-21"),
        // Sábado 24: nunca en fin de semana.
        MetricasApoyo.ruta(tarea: 6): MetricasApoyo.tarea(6, "Repasar el mes", planificada: "2026-10-24", estimacion: 1),
        // Atrasada (planificada el 14) y una hecha y una decisión que no cuentan.
        MetricasApoyo.ruta(tarea: 7): MetricasApoyo.tarea(7, "Enviar el resumen", planificada: "2026-10-14", estimacion: 1),
        MetricasApoyo.ruta(tarea: 8): MetricasApoyo.tarea(8, "Ya hecha", estado: "Hecha", planificada: "2026-10-19", estimacion: 3),
        MetricasApoyo.ruta(tarea: 9): MetricasApoyo.tarea(9, "¿Subimos precio?", estado: "En revisión", tipo: "decision", planificada: "2026-10-19"),
        // Vence el jueves (otro reloj: no suma horas).
        MetricasApoyo.ruta(tarea: 10): MetricasApoyo.tarea(10, "Presentar el 303", planificada: "2026-10-26", vence: "2026-10-22", estimacion: 1),
        "1 · Dirección/Rutinas/revision-semanal.md": """
        ---
        tls_type: routine
        nombre: Revisión de la semana
        cadencia: semanal
        dia: martes
        hora: "10:00"
        duracion_min: 30
        activa: true
        ---
        # Revisión de la semana
        """,
        "2 · Ventas/Reuniones/visita-cliente.md": """
        ---
        tls_type: meeting
        titulo: Visita a un cliente
        fecha: 2026-10-22
        duracion_min: 90
        ---
        # Visita a un cliente
        """,
    ]

    @Test("Ribera no tiene nada planificado esta semana: 0 h y ninguna inventada")
    func riberaVacia() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let s = c.panel().semana
        #expect(s.lunes == MetricasApoyo.dia("2026-10-19"))
        #expect(s.titulo == "Semana del 19 al 25 de octubre")
        #expect(s.dias.count == 7 && s.totalHoras == 0)
        #expect(s.fraseHoy == "Hoy no tienes nada planificado")
        #expect(s.capacidad == 20)
    }

    @Test("Horas por día frente al tope de 4 h; fin de semana con tope 0; lo atrasado aparte")
    func semana() {
        let c = MetricasApoyo.vacia(ficheros: Self.ficheros)
        defer { c.limpiar() }
        let s = c.panel().semana
        func d(_ n: Int) -> DiaAgenda { s.dias[n] }
        #expect(s.tope == 4)
        #expect(d(0).esHoy && d(0).horas == 3.5 && !d(0).pasaDelTope)
        #expect(d(0).tareas.count == 2)
        #expect(d(0).textoCarga == "3,5 h de 4")
        #expect(s.fraseHoy == "Hoy tienes 3,5 h de 4")
        // Martes: 3 + 2 + 0,5 de la rutina = 5,5 h.
        #expect(d(1).horas == 5.5 && d(1).pasaDelTope)
        #expect(d(1).aviso == "Pasa del tope: 5,5 h de 4")
        #expect(d(1).rutinas.count == 1)
        // Miércoles: una cosa sin estimar.
        #expect(d(2).horas == 0 && d(2).sinEstimar == 1)
        // Jueves: la reunión de 90 min y un vencimiento (que no suma horas).
        #expect(d(3).horas == 1.5 && d(3).vencimientos.count == 1)
        // Sábado: tope 0 y aviso con texto (ENT-04).
        #expect(d(5).finDeSemana && d(5).tope == 0 && d(5).pasaDelTope)
        #expect(d(5).aviso == "1 tarea planificada en fin de semana: se pasa al lunes")
        #expect(s.atrasadas.map(\.tarea.titulo) == ["Enviar el resumen"])
        #expect(s.diasPasados.count == 2)
        #expect(s.totalHoras == 11.5)                 // 3,5 + 5,5 + 1,5 + 1 (sábado)
        #expect(Agenda.laborable(MetricasApoyo.dia("2026-10-24")) == MetricasApoyo.dia("2026-10-26"))
    }

    @Test("El tope sale de agenda.tope_horas_dia")
    func topeDeConfig() {
        let c = MetricasApoyo.vacia(config: "agenda: {tope_horas_dia: 3, zona: Europe/Madrid}\n", ficheros: Self.ficheros)
        defer { c.limpiar() }
        let s = c.panel().semana
        #expect(s.tope == 3 && s.capacidad == 15)
        #expect(s.dias[0].pasaDelTope)
        #expect(s.dias[0].textoCarga == "3,5 h de 3")
    }

    @Test("Cabecera de Hoy: decisiones y horas en una frase")
    func frase() {
        let c = MetricasApoyo.vacia(ficheros: Self.ficheros)
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.frase() == "1 cosa pide tu decisión. Hoy tienes 3,5 h de 4.")
        #expect(p.frase(decisiones: 0) == "Nada pide tu decisión. Hoy tienes 3,5 h de 4.")
        let r = MetricasApoyo.ribera()
        defer { r.limpiar() }
        #expect(r.panel().frase() == "2 cosas piden tu decisión. Hoy no tienes nada planificado.")
    }

    @Test("Eventos del Calendario: con duración suman; sin duración, «sin estimar»")
    func eventos() {
        let c = MetricasApoyo.vacia()
        defer { c.limpiar() }
        let foto = FotoMetricas(snapshot: c.foto(), hoy: MetricasApoyo.dia("2026-10-19"))
        let s = Agenda(foto: foto, eventos: [
            EventoAgenda(titulo: "Médico", dia: MetricasApoyo.dia("2026-10-19"), hora: "9:00", horas: 1),
            EventoAgenda(titulo: "Comida", dia: MetricasApoyo.dia("2026-10-19")),
        ]).semana()
        #expect(s.dias[0].horas == 1 && s.dias[0].sinEstimar == 1)
        #expect(s.fraseHoy == "Hoy tienes 1 h de 4 y 1 cosa sin estimar")
    }
}
