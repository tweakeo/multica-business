import Foundation
import Testing
@testable import TLSCore

/// Los números de Ribera a día 2026-10-19 (lunes), calculados a mano a partir de sus fichas y CSV.
@Suite("Métricas · números clave de Ribera, calculados a mano")
struct KPIRiberaTests {
    let panel: PanelMetricas
    let c: MetricasApoyo.Carpeta

    init() {
        c = MetricasApoyo.ribera()
        panel = c.panel()
    }

    func k(_ codigo: String) -> ValorKPI { panel.evaluador.evaluar(codigo) }

    func cifra(_ codigo: String) -> Double? { k(codigo).medida.numero }

    @Test("El reloj es el de la carpeta: hoy 2026-10-19 y el estándar cargado")
    func reloj() {
        defer { c.limpiar() }
        #expect(panel.hoy == MetricasApoyo.dia("2026-10-19"))
        #expect(panel.kpis.count == 21)
        #expect(panel.kpis.map(\.codigo) == panel.metas?.codigos)
    }

    @Test("Dirección: 0 aprobaciones, 2 decisiones abiertas, 67 % de objetivos en trayectoria")
    func direccion() {
        defer { c.limpiar() }
        // DIR-APR: no hay borradores; las dos tareas «En revisión» son decisiones (van en DIR-DEC), así que 0.
        #expect(cifra("DIR-APR") == 0)
        #expect(k("DIR-APR").estado == .bien)          // menos es mejor, meta 3
        // DIR-DEC: T-0001 y T-0002, tipo decision y abiertas.
        #expect(cifra("DIR-DEC") == 2)
        #expect(k("DIR-DEC").estado == .bien)          // meta 3, alerta 8
        // DIR-DEC14: las dos se crearon el 19/10: ninguna lleva 14 días.
        #expect(cifra("DIR-DEC14") == 0)
        // DIR-OBJ: con número y dato hay 3 objetivos (ventas crítico, conversaciones adelantado, caja adelantado);
        // entregas y roles no tienen dato y el de trimestrales no tiene número. 2 de 3 = 66,7 %.
        #expect(cifra("DIR-OBJ") == 66.7)
        #expect(k("DIR-OBJ").estado == .atencion)      // meta 80 %, alerta 50 %
        #expect(k("DIR-OBJ").textoValor == "67 %")
    }

    @Test("Entrega y Equipo: sin fichas de proyecto, sin tareas de Entrega ni ocupantes → «Sin dato»; el uso sale de la Bitácora")
    func sinDatoEntregaEquipo() {
        defer { c.limpiar() }
        for codigo in ["ENT-ACTIVE", "ENT-ONTIME", "ENT-OVERDUE", "EQU-HEALTH", "EQU-ROLES"] {
            #expect(k(codigo).medida.numero == nil, "\(codigo) no debería tener cifra")
            #expect(k(codigo).estado == .sinDato)
            #expect(k(codigo).textoValor == "Sin dato")
        }
        #expect(k("ENT-ACTIVE").medida.motivoSinDato == "Aún no hay fichas de proyecto")
        // EQU-ROLES mide los roles de las personas (las fichas de los asistentes de F4 siempre dicen su ocupante).
        #expect(k("EQU-ROLES").medida.motivoSinDato == "Ningún rol dice quién lo ocupa: escríbelo en «ocupante»")
        // EQU-COST (F4): la Bitácora de octubre de Ribera (simulada) suma 0,38 USD de uso; sin meta en Metas.md.
        #expect(cifra("EQU-COST") == 0.38)
        #expect(k("EQU-COST").estado == .sinMeta)
        #expect(k("EQU-COST").fuente == "Sale de la bitácora de los asistentes")
        #expect(k("ENT-ACTIVE").textoMeta == "Sin meta")
    }

    @Test("Finanzas: 0 € vencidos, 26.664,65 € de caja, margen −413,3 %, 7,9 meses y 1 movimiento sin conciliar")
    func finanzas() {
        defer { c.limpiar() }
        // FIN-AR: F-0001…0006 cobradas (pagos.csv confirmados); F-0007 vence el 30/10: nada vencido.
        #expect(cifra("FIN-AR") == 0)
        #expect(k("FIN-AR").estado == .bien)
        // FIN-CASH: último saldo del banco de cada cuenta: 19.664,65 (corriente, 17/10) + 7.000,00 (ahorro, 14/08).
        #expect(cifra("FIN-CASH") == 26_664.65)
        #expect(k("FIN-CASH").estado == .sinMeta)
        #expect(k("FIN-CASH").textoValor == "26.664,65 €")
        // FIN-MARGIN (octubre, por base): ingresos F-0007 150 €; gastos alquiler 650 € + software 120 € = 770 €.
        // (150 − 770) / 150 = −413,3 %.
        #expect(cifra("FIN-MARGIN") == -413.3)
        #expect(k("FIN-MARGIN").estado == .mal)
        // FIN-RUNWAY: salida media de julio, agosto y septiembre sin el traspaso de 2.000 €:
        // jul 3.746,85 + ago 2.816,85 + sep 3.616,85 = 10.180,55 → 3.393,52 al mes. 26.664,65 / 3.393,52 = 7,86 → 7,9.
        #expect(cifra("FIN-RUNWAY") == 7.9)
        #expect(k("FIN-RUNWAY").estado == .bien)
        #expect(k("FIN-RUNWAY").textoValor == "7,9 meses")
        let salida = panel.evaluador.salidaMensual()
        #expect(salida?.media == 3393.52 && salida?.meses == 3)
        // FIN-UNREC: solo la transferencia de Talleres Martín (17/10) está «propuesta»; lo demás, conciliado o ignorado.
        #expect(cifra("FIN-UNREC") == 1)
        #expect(k("FIN-UNREC").estado == .atencion)    // meta 0, alerta 10
    }

    @Test("Marca: 3 piezas publicadas con evidencia y 2 conversaciones cualificadas en octubre")
    func marca() {
        defer { c.limpiar() }
        #expect(cifra("MAR-PUB") == 3)
        #expect(k("MAR-PUB").estado == .atencion)      // meta 6, alerta 2
        #expect(cifra("MAR-QCONV") == 2)
        #expect(k("MAR-QCONV").estado == .mal)         // alerta 3: llegar a la alerta ya es alerta
        // Ritmo del mes: han pasado 19 de 31 días. Esperadas 8 × 19/31 = 4,90 → 2 / 4,90 = 41 %, crítico.
        #expect(k("MAR-QCONV").ritmo.pct == 41)
        #expect(k("MAR-QCONV").ritmo.estado == .critico)
        // Publicadas: 6 × 19/31 = 3,68 esperadas → 3 / 3,68 = 82 %, atención.
        #expect(k("MAR-PUB").ritmo.pct == 82)
        #expect(k("MAR-PUB").ritmo.estado == .atencion)
    }

    @Test("Ventas: 70 % de conversión, 325,50 € ponderados, 870 € abiertos, 1 quieta y 0 € cobrados en octubre")
    func ventas() {
        defer { c.limpiar() }
        // VEN-CONV: con propuesta 10 (Andrés, Ana, Javier, Jorge, Lola, Lucía, Marta, Pablo, Rafael, Sergio);
        // aceptadas o ganadas 7 (todas menos Javier, Lola y Sergio). 7/10.
        #expect(cifra("VEN-CONV") == 70)
        #expect(k("VEN-CONV").estado == .bien)
        // VEN-FCST: 150×30 % + 90×15 % + 150×5 % + 90×50 % + 150×90 % + 90×5 % + 150×50 % = 325,50 €.
        #expect(cifra("VEN-FCST") == 325.5)
        #expect(k("VEN-FCST").textoValor == "325,50 €")
        // VEN-PIPE: las 7 abiertas: 150 + 90 + 150 + 90 + 150 + 90 + 150.
        #expect(cifra("VEN-PIPE") == 870)
        #expect(k("VEN-PIPE").textoValor == "870 €")
        // VEN-STALE: solo Javier Ortega (creada el 19/09, 30 días). Amparo y Sergio llevan 12.
        #expect(cifra("VEN-STALE") == 1)
        #expect(k("VEN-STALE").estado == .atencion)    // meta 0, alerta 3
        #expect(cifra("VEN-STALE7") == 3)
        // VEN-WON cuenta el día del cobro confirmado (revisión final de F2): las seis Ganadas (Andrés 90 + Ana 150 +
        // Lucía 90 + Marta 90 + Pablo 90 + Rafael 150 = 660 €) se cobraron de mayo a septiembre; en octubre, 0 €.
        #expect(cifra("VEN-WON") == 0)
        #expect(k("VEN-WON").estado == .mal)           // alerta 3000 €
        // Ritmo: 6000 × 19/31 = 3677,42 esperados → 0 %.
        #expect(k("VEN-WON").ritmo.pct == 0)
        #expect(k("VEN-WON").ritmo.estado == .critico)
    }

    @Test("Los que la app aún no puede sacar dicen «Sin dato» y de dónde saldrán")
    func noCalculables() {
        defer { c.limpiar() }
        for codigo in ["BUZ-PEND", "FIN-FISCAL", "ENT-INC", "ENT-ARR48", "VEN-REF", "EQU-RUT", "EQU-HEALTH"] {
            #expect(k(codigo).medida.numero == nil)
        }
        #expect(k("BUZ-PEND").fuente.hasPrefix("Saldrá de"))
        #expect(k("NO-EXISTE").medida.motivoSinDato == "La app no sabe calcular este número")
    }
}
