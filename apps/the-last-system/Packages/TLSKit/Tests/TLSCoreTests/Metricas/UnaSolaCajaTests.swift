import Foundation
import Testing
@testable import TLSCore

/// Integración F2 («una sola caja»): los números clave de la caja (FIN-CASH, FIN-RUNWAY, FIN-AR y FIN-UNREC) salen igual de
/// `KPIEvaluador` (Control, Hoy y las áreas) y de `Tesoreria` (Finanzas › Caja y el Banco), con Ribera en varios días:
/// misma caja, mismos meses de caja (solo meses que los movimientos del banco cubren enteros), mismo vencido y lo mismo
/// sin conciliar.
@Suite("Métricas · una sola caja (KPIEvaluador y Tesoreria dan lo mismo)")
struct UnaSolaCajaTests {
    @Test(arguments: ["2026-10-05", "2026-10-19", "2026-11-02"])
    func mismaCaja(_ dia: String) throws {
        let foto = VaultSnapshot.read(root: MetricasApoyo.riberaRepo)
        let reloj = MetricasApoyo.reloj(dia)
        let evaluador = KPIEvaluador(foto: FotoMetricas(snapshot: foto, hoy: reloj.hoy), metas: MetasDocumento.leer(foto))
        let tesoreria = Tesoreria(snapshot: foto, reloj: reloj)

        let caja = try #require(evaluador.cajaDisponible().total)
        let saldo = try #require(tesoreria.saldo.total)
        #expect(Int((caja * 100).rounded()) == saldo, "Caja el \(dia)")

        let runway = evaluador.evaluar("FIN-RUNWAY").medida.numero
        #expect(runway == tesoreria.runway.meses, "Meses de caja el \(dia)")
        if let media = evaluador.salidaMensual()?.media, let salida = tesoreria.runway.salidaMedia {
            #expect(Int((media * 100).rounded()) == salida, "Salida media el \(dia)")
        }

        if let vencido = evaluador.evaluar("FIN-AR").medida.numero {
            #expect(Int((vencido * 100).rounded()) == tesoreria.totalVencido, "Cobros vencidos el \(dia)")
        }
        if let sinConciliar = evaluador.evaluar("FIN-UNREC").medida.numero {
            #expect(Int(sinConciliar) == tesoreria.sinConciliar, "Sin conciliar el \(dia)")
        }
    }

    @Test("Ribera a 2/11: el extracto acaba el 17/10, así que octubre no cuenta (7,9 meses, no 11,0)")
    func extractoAtrasado() {
        let foto = VaultSnapshot.read(root: MetricasApoyo.riberaRepo)
        let tesoreria = Tesoreria(snapshot: foto, reloj: MetricasApoyo.reloj("2026-11-02"))
        #expect(tesoreria.runway.mesesUsados == ["2026-07", "2026-08", "2026-09"])
        #expect(tesoreria.runway.meses == 7.9)
    }
}
