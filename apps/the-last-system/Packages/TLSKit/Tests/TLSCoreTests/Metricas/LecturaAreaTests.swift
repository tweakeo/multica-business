import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · lectura de cada área sin asistente y sus números de análisis")
struct LecturaAreaTests {
    @Test("Ventas es el cuello: lo dice el titular, el texto lo explica y la recomendación es una")
    func ventas() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        let l = LecturaArea.de(.ventas, panel: p)
        #expect(l.titular == "Es el cuello de botella de la empresa")
        #expect(l.texto == "Ventas está en la etapa 1 de 5, con el 0 % de lo esencial encendido. "
            + "De los 4 sistemas que necesita, 0 están montados y 4 no existen todavía. "
            + "Lo que está mal ahora: su objetivo va en riesgo; al 0 % del ritmo que necesita para llegar; "
            + "oportunidades sin valor, estado, servicio o responsable · 7 casos. "
            + "Y va al 0 % del ritmo que necesitaría para llegar a su meta. "
            + "Es además lo que más frena al resto: su objetivo va en riesgo.")
        #expect(l.recomendacion == "Arreglar primero lo que está mal: su objetivo va en riesgo. Lo demás puede esperar una semana.")
        // La firma cambia si cambian los datos (y no si no cambian).
        #expect(LecturaArea.de(.ventas, panel: c.panel()).firma == l.firma)
        // Un cobro confirmado en octubre mueve el ritmo de Ventas: la firma cambia.
        let pagos = "4 · Finanzas/Registros/pagos.csv"
        let fila = c.texto(pagos).split(separator: "\n").first { $0.contains("cobro") && $0.contains("confirmado") }.map(String.init) ?? ""
        let mover = fila.replacingOccurrences(of: #"20\d\d-\d\d-\d\d"#, with: "2026-10-15", options: .regularExpression)
        #expect(!fila.isEmpty && mover != fila)
        c.cambiar(pagos, fila, mover)
        #expect(LecturaArea.de(.ventas, panel: c.panel()).firma != l.firma)
    }

    @Test("Entrega, sin nada roto: le falta encender lo esencial")
    func entrega() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let l = LecturaArea.de(.entrega, panel: c.panel())
        #expect(l.titular == "Le falta encender lo esencial")
        #expect(l.recomendacion.hasPrefix("Encender las funciones esenciales que faltan."))
        #expect(l.texto.contains("Lo que pide atención: su objetivo aún no tiene dato; nada declarado todavía en esta área."))
    }

    @Test("Análisis de Ventas, Finanzas, Dirección y Entrega en Ribera")
    func analisis() throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        func cifras(_ a: AreaCode, _ periodo: PeriodoArea) -> [String: CifraArea] {
            Dictionary(uniqueKeysWithValues: AnalisisArea.cifras(a, periodo: periodo, panel: p).map { ($0.nombre, $0) })
        }
        let ven = cifras(.ventas, .mes)
        #expect(ven["Oportunidades abiertas"]?.medida == .cifra(7))
        #expect(ven["Oportunidades abiertas"]?.pie == "870 € en juego")
        #expect(ven["Ganadas en el periodo"]?.medida == .cifra(6))
        #expect(ven["Ganadas en el periodo"]?.pie == "660 € cerrados")
        // Lola Plaza, perdida (sin fecha de cierre: cuenta la de creación, 19/10). Cierre: 6 de 7 = 86 %.
        #expect(ven["Perdidas en el periodo"]?.medida == .cifra(1))
        #expect(ven["Cierre"]?.textoValor == "86 %")
        let fin = cifras(.finanzas, .mes)
        #expect(fin["Caja hoy"]?.textoValor == "26.664,65 €")
        #expect(fin["Cobros pendientes"]?.medida == .cifra(181.5))
        #expect(fin["Cobros pendientes"]?.pie == "1 factura sin cobrar")
        // En octubre no hay ningún cobro confirmado (el de Talleres Martín está por confirmar): 0 € de verdad.
        #expect(fin["Cobrado en el periodo"]?.medida == .cifra(0))
        // Alquiler 663 € + software 145,20 €.
        #expect(fin["Pagado en el periodo"]?.medida == .cifra(808.2))
        #expect(fin["Meses de caja"]?.textoValor == "7,9 meses")
        let dir = cifras(.direccion, .todo)
        #expect(dir["Decisiones registradas"]?.medida == .cifra(2))
        #expect(dir["Números con umbral fijado"]?.medida == .cifra(16))
        #expect(dir["Números con umbral fijado"]?.pie == "de 21")
        #expect(dir["Ritmo global"]?.textoValor == "67 %")
        #expect(dir["Objetivos en riesgo"]?.medida == .cifra(1))
        // Sin fichas de proyecto, Entrega no inventa ceros.
        let ent = cifras(.entrega, .mes)
        #expect(ent.values.allSatisfy { $0.medida.numero == nil })
        #expect(PeriodoArea.semana.rango(hoy: MetricasApoyo.dia("2026-10-21")) ==
                RangoFechas(desde: MetricasApoyo.dia("2026-10-19"), hasta: MetricasApoyo.dia("2026-10-25")))
    }
}
