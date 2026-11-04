import Foundation
import Testing
@testable import TLSCore

/// PLAN §9 F2, criterio 5: Hoy tiene exactamente un foco y las alertas solo existen si hay algo en rojo.
@Suite("Métricas · alertas solo con algo en rojo (Ribera alternando datos) y la línea de Mika", .serialized)
struct AlertasTests {
    static let abiertas = ["amparo-ribera-trimestrales", "carlos-gil-renta", "irene-lucuma-trimestrales", "javier-ortega-renta",
                           "jorge-martin-trimestrales", "nerea-blasco-renta", "sergio-nexo-trimestrales"]
    static let particulares = ["andres-vidal", "carlos-gil", "javier-ortega", "lucia-ferrer", "marta-soler", "nerea-blasco", "pablo-ruiz"]

    @Test("Ribera tal cual: 3 números en alerta y 2 reglas duras rotas")
    func ribera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.alertas.map(\.origen) == ["numero:FIN-MARGIN", "numero:MAR-QCONV", "numero:VEN-WON", "regla:VEN-03", "regla:VEN-01"])
        #expect(p.alertas[2].texto == "2 · Ventas · Ventas cobradas del mes: 0 € (alerta en 3.000 €)")
        #expect(p.alertas[3].texto == "2 · Ventas · Oportunidades sin valor, estado, servicio o responsable: 7 casos")
        #expect(p.lineaMika() == "Revisé a las 8:45: 5 cosas en rojo (Finanzas, Marca y Ventas).")
        // Exactamente un foco, aunque haya rojos.
        #expect(p.mazo.mostradas.filter { $0.id == p.foco.id }.count == 1)
    }

    @Test("Ribera alternando datos: sin rojo no hay sección de alertas; una tarea vencida la hace aparecer; resolverla la quita")
    func alternando() async throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        // 1. Arreglar lo que está en rojo: responsable en las oportunidades abiertas, empresa en los particulares y,
        //    como persona y por el bus, sin alerta los tres números que la pasaban.
        for o in Self.abiertas {
            c.cambiar("2 · Ventas/Oportunidades/\(o).md", "\norigen: importacion", "\nresponsable: Manu\norigen: importacion")
        }
        for p in Self.particulares {
            c.cambiar("2 · Ventas/Contactos/\(p).md", "\norigen: importacion", "\nempresa: \"[[\(p)]]\"\norigen: importacion")
        }
        let metas = try #require(MetasDocumento.leer(c.foto()))
        let bus = try await c.bus()
        for (codigo, meta) in [("FIN-MARGIN", "30"), ("MAR-QCONV", "8"), ("VEN-WON", "6000")] {
            try await MetasEscritor.fijar(codigo: codigo, meta: meta, alerta: "", en: metas, bus: bus, autor: .persona("Manu"))
        }
        let sinRojo = c.panel()
        #expect(sinRojo.alertas.isEmpty)
        #expect(!sinRojo.hayRojo)
        #expect(sinRojo.lineaMika() == "Revisé a las 8:45: nada en rojo.")
        #expect(sinRojo.mazo.mostradas.filter { $0.id == sinRojo.foco.id }.count == 1)

        // 2. Una tarea que venció el viernes: rojo.
        let ruta = MetricasApoyo.ruta(tarea: 3, area: "3 · Entrega")
        c.escribir(ruta, MetricasApoyo.tarea(3, "Presentar la renta de Lucía", vence: "2026-10-16", estimacion: 1))
        let conRojo = c.panel()
        #expect(conRojo.alertas.map(\.origen) == ["regla:CHQ-2"])
        #expect(conRojo.alertas.first?.texto == "3 · Entrega · Tareas vencidas: 1 caso")
        #expect(conRojo.lineaMika() == "Revisé a las 8:45: 1 cosa en rojo (Entrega).")
        // ENT-OVERDUE ya tiene dato (1) y queda por debajo de la alerta (5): atención, no rojo.
        #expect(conRojo.evaluador.evaluar("ENT-OVERDUE").medida.numero == 1)
        #expect(conRojo.evaluador.evaluar("ENT-OVERDUE").estado == .atencion)

        // 3. Se hizo a tiempo (cerrada el 16): vuelve a no haber alertas y ENT-ONTIME tiene su primer dato, 100 %.
        c.cambiar(ruta, "estado: Por hacer", "estado: Hecha\ncerrada: 2026-10-16")
        let otraVez = c.panel()
        #expect(otraVez.alertas.isEmpty)
        #expect(otraVez.evaluador.evaluar("ENT-ONTIME").medida == .cifra(100))
        #expect(otraVez.objetivos.first { $0.objetivo.medidoPor == "ENT-ONTIME" }?.estado == .adelantado)

        // 4. Cerrada tarde (el 19, venció el 16): 0 % a tiempo, un dato real y no inventado, y en alerta (75 %).
        //    Su objetivo (90 %) pasa a crítico: con dato quedan 4 objetivos y 2 en trayectoria, DIR-OBJ = 50 %, que
        //    es justo su alerta.
        c.cambiar(ruta, "cerrada: 2026-10-16", "cerrada: 2026-10-19")
        let tarde = c.panel()
        #expect(tarde.evaluador.evaluar("ENT-ONTIME").medida == .cifra(0))
        #expect(tarde.evaluador.evaluar("DIR-OBJ").medida == .cifra(50))
        #expect(tarde.alertas.map(\.origen) == ["numero:DIR-OBJ", "numero:ENT-ONTIME"])
    }

    @Test("En fin de semana Mika no revisa")
    func finDeSemana() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        #expect(c.panel("2026-10-24").lineaMika() == "Los fines de semana no reviso: el lunes a las 8:45 vuelvo a mirar.")
    }
}
