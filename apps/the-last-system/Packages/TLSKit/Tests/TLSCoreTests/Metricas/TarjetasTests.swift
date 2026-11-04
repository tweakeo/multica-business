import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · tarjetas: las cinco preguntas, un solo foco y el tope de 5 al día")
struct TarjetasTests {
    @Test("Ribera: el foco es el objetivo de ventas (43,6 puntos), con sus cinco respuestas y su botón")
    func focoRibera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        let f = p.foco
        // Puntos (pesos de tarjetas.js): urgencia 9 (crítico) + impacto × 1,2 (faltan los 6.000 €: VEN-WON cuenta el día
        // del cobro confirmado y en octubre aún no hay ninguno) + plazo 0 (quedan 73 días) + riesgo 7 × 1,3 + estrategia 9
        // + responsabilidad 7 × 0,8 = 43,6.
        #expect(f.tipo == .riesgo)
        #expect(f.puntos == 43.6)
        #expect(f.prioridad == .critico)
        #expect(f.titulo == "6.000 € de ventas cobradas al mes: vas al 0\u{00A0}% de lo previsto")
        #expect(f.quePasa == "0 € de 1.239,13 € esperados a estas alturas.")
        #expect(f.porQueImporta == "Quedan 73 días y faltan 6.000 €.")
        #expect(f.siNo == "El periodo se cierra por debajo y arrastra al siguiente.")
        // 6.000 € en 11 semanas (73 días): 545,45 € por semana.
        #expect(f.recomendacion == "Hacen falta 545,45 € por semana durante 11 semanas.")
        #expect(f.queHago == "Decidir el plan")
        #expect(f.boton.accion == .decidirPlan(VaultPath("1 · Dirección/Objetivos/6-000-de-ventas-cobradas-al-mes.md")))
        #expect(f.area == .ventas)
    }

    @Test("Ribera: 9 tarjetas vivas, 6 rojas; Hoy tiene exactamente un foco")
    func mazoRibera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        let m = p.mazo
        // Riesgo (43,6) · cuello Ventas (39,3) · seguimiento Amparo y Sergio (36,7) · cuello Marca (36,3) ·
        // seguimiento Javier (36,0) · tres números sin umbral (12,0).
        #expect(m.tarjetas.map(\.puntos) == [43.6, 39.3, 36.7, 36.7, 36.3, 36.0, 12.0, 12.0, 12.0])
        #expect(m.rojas == 6)
        #expect(m.mostradas.count == 9 && m.fueraDelTope == 0)
        #expect(m.tarjetas.filter { $0.tipo == .seguimiento }.map(\.titulo)
            == ["Retomar a Amparo Ribera · Frutas Ribera SC", "Retomar a Sergio Nexo · Arquitectura Nexo SLP", "Retomar a Javier Ortega"])
        #expect(m.tarjetas.filter { $0.tipo == .decidir }.map(\.titulo)
            == ["Previsión ponderada no tiene umbral", "Cartera abierta no tiene umbral", "Proyectos activos no tiene umbral"])
        // Un solo foco: el primero de los que se enseñan, y solo aparece una vez.
        #expect(m.foco.id == m.mostradas.first?.id)
        #expect(m.mostradas.filter { $0.id == m.foco.id }.count == 1)
        // Cada tarjeta contesta las cinco preguntas y trae botón.
        for t in m.tarjetas {
            #expect(!t.quePasa.isEmpty && !t.porQueImporta.isEmpty && !t.queHago.isEmpty && !t.siNo.isEmpty && !t.recomendacion.isEmpty)
        }
    }

    @Test("Posponer o descartar el foco hace foco a la siguiente; sigue habiendo exactamente uno")
    func posponer() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let primero = c.panel().foco
        let pospuesto = c.panel(estados: [EstadoTarjeta(id: primero.id, pospuestaHasta: MetricasApoyo.dia("2026-10-20"))])
        #expect(pospuesto.foco.id != primero.id)
        #expect(pospuesto.foco.titulo == "Ventas está frenando al resto")
        // Pospuesta hasta hoy: ya vuelve.
        let vuelve = c.panel(estados: [EstadoTarjeta(id: primero.id, pospuestaHasta: MetricasApoyo.dia("2026-10-19"))])
        #expect(vuelve.foco.id == primero.id)
        let descartadas = c.panel(estados: c.panel().mazo.tarjetas.map { EstadoTarjeta(id: $0.id, descartada: true) })
        #expect(descartadas.mazo.tarjetas.isEmpty)
        #expect(descartadas.foco.tipo == .planificar)
        #expect(descartadas.foco.titulo == "Nada urgente: reparte la semana")
    }

    @Test("Una carpeta vacía también tiene exactamente un foco")
    func vacia() {
        let c = MetricasApoyo.vacia()
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.mazo.tarjetas.isEmpty)
        #expect(p.foco.tipo == .planificar)
        #expect(p.foco.queHago == "Ver tu semana")
    }

    @Test("Tope diario: como mucho 5 tarjetas que no son rojas (o las de avisos.tope_tarjetas_dia); las rojas siempre")
    func tope() {
        var ficheros: [String: String] = [:]
        for n in 1...8 { ficheros[MetricasApoyo.ruta(tarea: n)] = MetricasApoyo.tarea(n, "Tarea \(n)", planificada: "2026-10-19") }
        // Una vencida con prioridad urgente y valor: roja.
        ficheros[MetricasApoyo.ruta(tarea: 9)] = MetricasApoyo.tarea(9, "Urgente", vence: "2026-10-12", extra: "prioridad: Urgente\n")
        let c = MetricasApoyo.vacia(ficheros: ficheros)
        defer { c.limpiar() }
        let m = c.panel().mazo
        // Cada tarea de hoy: urgencia 1 + plazo 9 × 1,1 + responsabilidad 6 × 0,8 = 15,7 (normal).
        #expect(m.tarjetas.filter { $0.puntos == 15.7 }.count == 8)
        // La vencida: urgencia 8 + plazo 10 × 1,1 + riesgo 7 × 1,3 + responsabilidad 4,8 = 32,9 (atención: no es roja).
        #expect(m.tarjetas.first?.puntos == 32.9)
        #expect(m.mostradas.count == 5)
        #expect(m.fueraDelTope == 4)
        #expect(m.foco.titulo == "Urgente")
        #expect(m.foco.siNo == "Ya está vencida desde hace 7 días.")

        let c2 = MetricasApoyo.vacia(config: "avisos: {tope_tarjetas_dia: 2}\n", ficheros: ficheros)
        defer { c2.limpiar() }
        #expect(c2.panel().mazo.mostradas.count == 2)
    }

    @Test("CRITERIO: la misma decisión 3 veces propone convertirla en regla")
    func aprender() {
        let c = MetricasApoyo.vacia()
        defer { c.limpiar() }
        let h = Array(repeating: DecisionTarjeta(patron: "seguimiento-oportunidad-Propuesta", accion: "posponer"), count: 3)
        let p = c.panel(historial: h)
        let t = p.mazo.tarjetas.first { $0.tipo == .criterio }
        #expect(t?.titulo == "Has resuelto «seguimiento-oportunidad-Propuesta» con «posponer» 3 veces")
        #expect(t?.queHago == "Convertir en regla")
        #expect(c.panel(historial: Array(h.prefix(2))).mazo.tarjetas.isEmpty)
    }

    @Test("Escalas de tarjetas.js: impacto en euros y plazo")
    func escalas() {
        #expect(TarjetaBuilder.impacto(nil) == 0)
        #expect(TarjetaBuilder.impacto(1_000_000) == 10)
        #expect(abs(TarjetaBuilder.impacto(150) - 5.2226) < 0.001)
        #expect(TarjetaBuilder.plazo(-3) == 10)
        #expect(TarjetaBuilder.plazo(0) == 9)
        #expect(TarjetaBuilder.plazo(3) == 5)
        #expect(TarjetaBuilder.plazo(20) == 0)
        #expect(FactoresTarjeta(riesgo: 8).prioridad == .riesgoEmpresarial)
    }
}
