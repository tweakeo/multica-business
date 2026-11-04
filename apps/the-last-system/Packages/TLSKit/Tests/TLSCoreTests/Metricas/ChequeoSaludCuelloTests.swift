import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · los 7 chequeos, las 15 comprobaciones, la salud y el cuello")
struct ChequeoSaludCuelloTests {
    func n(_ p: PanelMetricas, _ codigo: String) -> Int { p.chequeos.first { $0.codigo == codigo }?.n ?? -1 }

    @Test("Ribera: 7 chequeos + 15 comprobaciones, con los casos contados a mano")
    func chequeosRibera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.chequeos.filter { $0.familia == .chequeo }.count == 7)
        #expect(p.chequeos.filter { $0.familia == .comprobacion }.count == 15)
        // Las 7 oportunidades abiertas no dicen responsable.
        #expect(n(p, "CHQ-5") == 7)
        #expect(n(p, "VEN-03") == 7)
        // F-2026-0007 (181,50 €) vence el 30/10 y su cobro no está confirmado: cobro previsto a 60 días.
        #expect(n(p, "CHQ-6") == 1)
        #expect(p.chequeos.first { $0.codigo == "CHQ-6" }?.casos.first?.detalle == "F-2026-0007 · Talleres Martín e Hijos SL · 181,50 € · vence 30 oct")
        // Siete contactos particulares sin empresa (Andrés, Carlos, Javier, Lucía, Marta, Nerea y Pablo).
        #expect(n(p, "VEN-01") == 7)
        // Javier Ortega, 30 días sin contacto.
        #expect(n(p, "VEN-08") == 1)
        #expect(p.chequeos.first { $0.codigo == "VEN-08" }?.casos.first?.detalle == "Javier Ortega · 30 días")
        // Los 6 objetivos vivos sin ningún proyecto; las 6 áreas sin dueño distinto de ti; 5 números sin umbral.
        #expect(n(p, "DIR-03b") == 6)
        #expect(n(p, "EQU-01") == 6)
        #expect(n(p, "DIR-09") == 5)
        for codigo in ["CHQ-1", "CHQ-2", "CHQ-3", "CHQ-4", "CHQ-7", "DIR-03", "VEN-11", "ENT-01", "ENT-03", "ENT-07", "FIN-01",
                       "FIN-06", "ORG-01", "ORG-02"] {
            #expect(n(p, codigo) == 0, "\(codigo)")
        }
        // Orden: primero lo que tiene casos, los graves delante y, dentro, los de más casos.
        #expect(p.chequeos.prefix(2).map(\.codigo) == ["VEN-03", "VEN-01"])
        #expect(p.chequeos.filter(\.esRojo).map(\.codigo) == ["VEN-03", "VEN-01"])
    }

    @Test("DIR-03 es atención (no rechazo) y ofrece «Colgar de un objetivo» o «Seguir sin objetivo»")
    func proyectoSinObjetivo() {
        let proyecto = """
        ---
        tls_type: project
        nombre: Web nueva
        clase: interno
        estado: En curso
        fin: 2026-10-10
        ---
        # Web nueva
        """
        let c = MetricasApoyo.vacia(ficheros: ["1 · Dirección/Proyectos/web-nueva/Proyecto.md": proyecto])
        defer { c.limpiar() }
        let p = c.panel()
        let dir03 = p.chequeos.first { $0.codigo == "DIR-03" }!
        #expect(dir03.n == 1 && dir03.nivel == .flojo && !dir03.esRojo)
        #expect(dir03.acciones == ["Colgar de un objetivo", "Seguir sin objetivo"])
        // Terminaba el 10/10: fuera de fecha (regla dura) y sin nada pendiente.
        #expect(n(p, "ENT-03") == 1)
        #expect(n(p, "CHQ-3") == 1)
        // «Seguir sin objetivo» lo deja de señalar.
        c.cambiar("1 · Dirección/Proyectos/web-nueva/Proyecto.md", "estado: En curso", "estado: En curso\nsin_objetivo: true")
        #expect(n(c.panel(), "DIR-03") == 0)
    }

    @Test("Tareas: vencidas, en fin de semana y arrastrando; carga por encima del tope")
    func tareas() {
        let c = MetricasApoyo.vacia(ficheros: [
            MetricasApoyo.ruta(tarea: 1): MetricasApoyo.tarea(1, "Vencida", vence: "2026-10-16"),
            MetricasApoyo.ruta(tarea: 2): MetricasApoyo.tarea(2, "En sábado", planificada: "2026-10-24"),
            MetricasApoyo.ruta(tarea: 3): MetricasApoyo.tarea(3, "Aparcada", planificada: "2026-10-05"),
            MetricasApoyo.ruta(tarea: 4): MetricasApoyo.tarea(4, "Larga", planificada: "2026-10-20", estimacion: 5),
            MetricasApoyo.ruta(tarea: 5): MetricasApoyo.tarea(5, "Hecha y vencida", estado: "Hecha", vence: "2026-10-01"),
            MetricasApoyo.ruta(tarea: 6): MetricasApoyo.tarea(6, "¿Decidimos?", estado: "En revisión", tipo: "decision", vence: "2026-10-01"),
        ])
        defer { c.limpiar() }
        let p = c.panel()
        #expect(n(p, "CHQ-2") == 1)                    // solo la abierta que no es decisión
        #expect(p.chequeos.first { $0.codigo == "CHQ-2" }?.casos.first?.detalle == "T-0001 · Vencida · venció hace 3 días")
        #expect(n(p, "ORG-01") == 1)
        #expect(n(p, "ORG-02") == 1)                    // planificada hace 14 días
        #expect(n(p, "CHQ-1") == 4)                     // cuatro tareas abiertas sueltas
        // Martes 20: 5 h > 4; sábado 24: una tarea en fin de semana.
        #expect(n(p, "CHQ-7") == 2)
        #expect(p.hayRojo)
    }

    @Test("Ribera: salud por área con sus señales, calculada a mano")
    func saludRibera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        func s(_ a: AreaCode, _ d: SenalSalud.Dimension) -> SenalSalud? { p.salud(a).first { $0.dimension == d } }
        // Ventas: su objetivo va en riesgo, al 0 % del ritmo del mes, regla dura rota y 1 quieta.
        #expect(s(.ventas, .resultado)?.estado == .mal)
        #expect(s(.ventas, .resultado)?.detalle == "su objetivo va en riesgo")
        #expect(s(.ventas, .ritmo)?.detalle == "al 0 % del ritmo que necesita para llegar")
        #expect(s(.ventas, .datos)?.detalle == "oportunidades sin valor, estado, servicio o responsable · 7 casos")
        #expect(s(.ventas, .pipeline)?.estado == .atencion)
        #expect(s(.ventas, .pipeline)?.detalle == "1 oportunidad lleva más de dos semanas sin contacto")
        // Nada declarado: la señal dice que falta el dato, no inventa un «bien».
        #expect(s(.ventas, .automatizaciones)?.estado == .atencion)
        #expect(s(.ventas, .automatizaciones)?.porFaltaDeDato == true)
        // Finanzas: el margen del mes en alerta; el ritmo (caja, 263 %) bien; sin facturas vencidas.
        #expect(s(.finanzas, .resultado)?.detalle == "margen de gestión del mes en alerta")
        #expect(s(.finanzas, .ritmo)?.estado == .bien)
        #expect(s(.finanzas, .pipeline)?.estado == .bien)
        // Entrega y Equipo: su objetivo aún no tiene dato.
        #expect(s(.entrega, .resultado)?.detalle == "su objetivo aún no tiene dato")
        #expect(s(.entrega, .pipeline) == nil)             // sin proyectos no se juzga el flujo
        // Equipo está en reposo desde F4 (como en la maqueta): no se juzga.
        #expect(s(.equipo, .pipeline) == nil)
        // Dirección: sus números con meta van bien; el flujo tiene 6 objetivos vivos.
        #expect(s(.direccion, .resultado)?.estado == .bien)
        #expect(s(.direccion, .ritmo) == nil)
        #expect(s(.direccion, .pipeline)?.estado == .bien)
        // Marca: conversaciones en alerta y al 41 % del ritmo; publica (3 piezas en 30 días).
        #expect(s(.marca, .ritmo)?.detalle == "al 41 % del ritmo que necesita para llegar")
        #expect(s(.marca, .pipeline)?.estado == .bien)
    }

    @Test("Ribera: el cuello es Ventas (presión 195) y el mapa lo dice en texto")
    func cuelloRibera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        // Presión = (100 − ritmo) + mal × 25 + atención × 10 + a mano × 3.
        // Ventas: (100 − 0) + 3 × 25 + 2 × 10 = 195. Marca: (100 − 41) + 2 × 25 + 1 × 10 = 119.
        // Finanzas: 1 × 25 + 1 × 10 = 35. Dirección y Entrega: 2 × 10 = 20. Equipo está en reposo (F4): no cuenta.
        let pres = Dictionary(uniqueKeysWithValues: p.mapa.presiones.map { ($0.area, $0.presion) })
        #expect(pres == [.ventas: 195, .marca: 119, .finanzas: 35, .direccion: 20, .entrega: 20])
        #expect(p.mapa.presiones.map(\.area).prefix(2) == [.ventas, .marca])
        #expect(p.mapa.cuello?.area == .ventas)
        #expect(p.mapa.textoCuello == "El cuello es 2 · Ventas: su objetivo va en riesgo.")
        #expect(p.mapa.marcada(.ventas, etapa: 1) && !p.mapa.marcada(.ventas, etapa: 2))
        // El camino empieza por el cuello.
        #expect(p.mapa.camino.first?.area == .ventas)
        #expect(p.mapa.camino.first?.porque == "Es el cuello: su objetivo va en riesgo")
        #expect(p.mapa.camino.first?.entrada == "Hoy hay 7 oportunidades abiertas por 870 €, y 1 lleva más de dos semanas sin contacto.")
        #expect(p.mapa.camino.count == 5)             // sin Equipo, en reposo
        #expect(p.mapa.veredicto.hasPrefix("La empresa está en la etapa 1"))
        #expect(p.mapa.veredicto.hasSuffix("Y 2 reglas básicas se incumplen (14 casos): las tienes en las Alertas de Hoy."))
    }

    @Test("Sin nada que frene, no hay cuello: «Ningún área da señales de bloqueo ahora mismo.»")
    func sinCuello() {
        #expect(CuelloCalculador.textoCuello(nil) == "Ningún área da señales de bloqueo ahora mismo.")
    }
}
