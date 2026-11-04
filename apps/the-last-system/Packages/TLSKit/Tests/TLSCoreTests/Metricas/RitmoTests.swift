import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · ritmo de objetivos y de áreas, y cambios de fecha")
struct RitmoTests {
    func objetivo(_ p: PanelMetricas, _ medido: String) -> RitmoObjetivo? {
        p.objetivos.first { $0.objetivo.medidoPor == medido }
    }

    @Test("Ribera: cada objetivo en su periodo (T4: 92 días, han pasado 19)")
    func objetivosRibera() throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.objetivos.count == 6)
        // 6.000 € acumulados en el trimestre: esperado 6000 × 19/92 = 1.239,13; real 0 € (VEN-WON cuenta el día del cobro
        // confirmado; los de las seis Ganadas son de mayo a septiembre) → 0 %, crítico (< 55 %).
        let ventas = try #require(objetivo(p, "VEN-WON"))
        #expect(ventas.diasTotal == 92 && ventas.diasPasados == 19 && ventas.diasRestantes == 73)
        #expect(ventas.esperado == 1239.13 && ventas.real == 0)
        #expect(ventas.pct == 0)
        #expect(ventas.estado == .critico)
        #expect(ventas.falta == 6000)
        // 8 conversaciones acumuladas: esperado 1,65; real 2 → 121 %, adelantado.
        let conv = try #require(objetivo(p, "MAR-QCONV"))
        #expect(conv.esperado == 1.65 && conv.real == 2 && conv.pct == 121)
        #expect(conv.estado == .adelantado)
        // 3 meses de caja, de nivel (no acumulado): 7,9 ≥ 3 → adelantado.
        let caja = try #require(objetivo(p, "FIN-RUNWAY"))
        #expect(caja.real == 7.9 && caja.esperado == 3)
        #expect(caja.estado == .adelantado)
        // Sin dato: entregas a tiempo y roles con ocupante. Sin número: el de los trimestrales presentados.
        #expect(objetivo(p, "ENT-ONTIME")?.estado == .sinDato)
        #expect(objetivo(p, "EQU-ROLES")?.estado == .sinDato)
        let trimestrales = try #require(p.objetivos.first { $0.objetivo.medidoPor == nil })
        #expect(trimestrales.estado == .sinMeta)
        // Ritmo de la empresa: media capada a 100 de 0, 121 y 263 → (0 + 100 + 100) / 3 = 66,7 → 67; hay uno crítico.
        #expect(p.ritmoEmpresa.pct == 67)
        #expect(p.ritmoEmpresa.estado == .critico)
        #expect(p.ritmoEmpresa.enRiesgo == 1)
        #expect(p.ritmoEmpresa.sinDato == 2)
    }

    @Test("Ribera: cada área toma el ritmo de su número más atrasado")
    func areasRibera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        func r(_ a: AreaCode) -> RitmoArea { p.ritmo(a)! }
        // Dirección: DIR-OBJ en atención (67 % frente a meta 80 %).
        #expect(r(.direccion).estado == .atencion)
        #expect(r(.direccion).marca == "DIR-OBJ")
        // Ventas: VEN-WON va al 0 % de lo que toca en el mes (en octubre aún no se ha confirmado ningún cobro).
        #expect(r(.ventas).estado == .enAlerta)
        #expect(r(.ventas).marca == "VEN-WON")
        #expect(r(.ventas).pct == 0)
        #expect(r(.ventas).frase == "Ventas cobradas del mes: 0 € (meta 6.000 €)")
        // Entrega: ningún número tiene dato. Equipo está en reposo (desde F4, como en la maqueta de Ribera).
        #expect(r(.entrega).estado == .sinDato)
        #expect(r(.equipo).estado == .enReposo)
        // Finanzas: el margen del mes está en alerta.
        #expect(r(.finanzas).estado == .enAlerta)
        #expect(r(.finanzas).marca == "FIN-MARGIN")
        // Marca: conversaciones al 41 % del ritmo del mes.
        #expect(r(.marca).estado == .enAlerta)
        #expect(r(.marca).pct == 41)
        #expect(r(.marca).estado.etiqueta == "En alerta")
    }

    @Test("Cambio de fecha a 2026-10-05: lo que aún no había pasado no cuenta")
    func antes() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel("2026-10-05")
        func n(_ codigo: String) -> Double? { p.evaluador.evaluar(codigo).medida.numero }
        #expect(p.hoy == MetricasApoyo.dia("2026-10-05"))
        // Las ganadas se cerraron el 19/10: del 1 al 5 de octubre no hay ninguna (hay oportunidades: es 0 de verdad).
        #expect(n("VEN-WON") == 0)
        // Solo existía la de Javier Ortega (creada el 19/09): 90 € abiertos.
        #expect(n("VEN-PIPE") == 90)
        // Caja a 5/10: 19.483,15 (corriente, saldo del 5/10) + 7.000 (ahorro).
        #expect(n("FIN-CASH") == 26_483.15)
        // La transferencia del 17/10 aún no había llegado.
        #expect(n("FIN-UNREC") == 0)
        // 26.483,15 / 3.393,52 = 7,80.
        #expect(n("FIN-RUNWAY") == 7.8)
        // Ni conversaciones ni piezas publicadas antes del 19/10.
        #expect(n("MAR-QCONV") == 0)
        #expect(n("MAR-PUB") == 0)
        // El objetivo de ventas va 0 de 6000 × 5/92 = 326,09 → crítico.
        #expect(objetivo(p, "VEN-WON")?.esperado == 326.09)
        #expect(objetivo(p, "VEN-WON")?.estado == .critico)
    }

    @Test("Cambio de fecha a 2026-11-02: noviembre empieza de cero y octubre (sin cubrir entero) no entra en la media")
    func despues() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel("2026-11-02")
        func n(_ codigo: String) -> Double? { p.evaluador.evaluar(codigo).medida.numero }
        #expect(n("VEN-WON") == 0)
        #expect(n("MAR-QCONV") == 0)
        // FIN-MARGIN de noviembre: sin ingresos facturados todavía → sin dato, no 0 %.
        #expect(n("FIN-MARGIN") == nil)
        #expect(p.evaluador.evaluar("FIN-MARGIN").medida.motivoSinDato == "Sin ingresos facturados este mes")
        // El extracto acaba el 17/10: octubre no está entero. La media sigue siendo julio–septiembre.
        #expect(p.evaluador.salidaMensual()?.media == 3393.52)
        #expect(n("FIN-RUNWAY") == 7.9)
        // F-2026-0007 venció el 30/10 y su cobro sigue sin confirmar: 181,50 € vencidos.
        #expect(n("FIN-AR") == 181.5)
        #expect(p.evaluador.evaluar("FIN-AR").estado == .atencion)
        // Las decisiones del 19/10 llevan 14 días: DIR-DEC14 = 2.
        #expect(n("DIR-DEC14") == 2)
        // Javier lleva 44 días, Amparo y Sergio 26: tres quietas de más de 14 días.
        #expect(n("VEN-STALE") == 3)
    }

    @Test("Un objetivo que mide «menos es mejor» va en ritmo si no pasa de lo esperado")
    func menosEsMejor() throws {
        let c = MetricasApoyo.vacia(ficheros: [
            "1 · Dirección/Objetivos/sin-vencidas.md": """
            ---
            tls_type: objective
            titulo: Ninguna tarea de entrega vencida
            area: entrega
            desde: 2026-10-01
            hasta: 2026-12-31
            meta: 2
            acumulado: false
            medido_por: ENT-OVERDUE
            estado: En curso
            ---
            # Ninguna tarea de entrega vencida
            """,
            MetricasApoyo.ruta(tarea: 1, area: "3 · Entrega"): MetricasApoyo.tarea(1, "Entregar la renta", vence: "2026-10-10"),
        ])
        defer { c.limpiar() }
        let p = c.panel()
        let o = try #require(p.objetivos.first)
        #expect(o.real == 1)
        #expect(o.estado == .enRitmo)
        c.escribir(MetricasApoyo.ruta(tarea: 2, area: "3 · Entrega"), MetricasApoyo.tarea(2, "Otra", vence: "2026-10-11"))
        c.escribir(MetricasApoyo.ruta(tarea: 3, area: "3 · Entrega"), MetricasApoyo.tarea(3, "Y otra", vence: "2026-10-12"))
        c.escribir(MetricasApoyo.ruta(tarea: 4, area: "3 · Entrega"), MetricasApoyo.tarea(4, "Y una más", vence: "2026-10-13"))
        let p2 = c.panel()
        let o2 = try #require(p2.objetivos.first)
        #expect(o2.real == 4)
        #expect(o2.estado != .enRitmo && o2.estado.retraso >= 3)
        #expect(o2.falta == 2)
    }
}
