import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: caja, meses de caja y cobros")
struct TesoreriaTests {
    typealias A = FinanzasApoyo

    static func d(_ s: String) -> LocalDate { LocalDate(parsing: s)! }

    @Test func cajaDeRibera() throws {
        let tes = Tesoreria(snapshot: VaultSnapshot.read(root: RutasRepo.ribera), reloj: A.relojRibera)
        let saldo = tes.saldo
        #expect(saldo.total == 2_666_465)
        #expect(!saldo.estimado)
        #expect(saldo.fecha == Self.d("2026-10-17"))
        #expect(saldo.cuentas.map(\.fuente) == [.banco, .banco])
        #expect(Set(saldo.cuentas.compactMap(\.saldo)) == [700_000, 1_966_465])
        // Salida media de julio, agosto y septiembre sin el traspaso al ahorro: 10.180,55 / 3.
        let r = tes.runway
        #expect(r.mesesUsados == ["2026-07", "2026-08", "2026-09"])
        #expect(r.salidaMedia == 339_352)
        #expect(r.meses == 7.9)
        #expect(r.motivo == nil)
        #expect(tes.traspasos == ["MOV-a4488cb6db95", "MOV-ac01229be87c"])
        // Cobros: F-2026-0007 está por cobrar y vence el 30.
        #expect(tes.cobrosPendientes.map(\.factura.id) == ["F-2026-0007"])
        #expect(tes.cobrosPendientes.first?.vence == Self.d("2026-10-30"))
        #expect(tes.cobrosVencidos.isEmpty)
        #expect(tes.totalVencido == 0)
        #expect(tes.sinConciliar == 1)
    }

    @Test func graficaDeRibera() throws {
        let tes = Tesoreria(snapshot: VaultSnapshot.read(root: RutasRepo.ribera), reloj: A.relojRibera)
        let semana = tes.serie(.semana)
        #expect(semana.count == 7)
        #expect(semana.first?.fecha == Self.d("2026-10-13"))
        #expect(semana.last?.fecha == Self.d("2026-10-19"))
        #expect(semana.map(\.saldo) == [2_648_315, 2_648_315, 2_648_315, 2_648_315, 2_666_465, 2_666_465, 2_666_465])
        #expect(semana.allSatisfy { !$0.estimado })
        let todo = tes.serie(.todo)
        #expect(todo.first?.fecha == Self.d("2026-06-30"))
        #expect(todo.first?.saldo == 2_340_000)
        #expect(todo.count == 112)
        // El 14 de agosto el traspaso no cambia la caja.
        let p13 = todo.first { $0.fecha == Self.d("2026-08-13") }?.saldo
        let p14 = todo.first { $0.fecha == Self.d("2026-08-14") }?.saldo
        #expect(p13 == p14)
        #expect(tes.serie(.mes).count == 30)
        #expect(tes.serie(.trimestre).count == 91)
        #expect(tes.serie(.anio).count == 112)
    }

    @Test func sinDatosNuncaCero() {
        let env = A.empresa([:])
        defer { env.limpiar() }
        let tes = Tesoreria(snapshot: env.foto(), reloj: relojDePrueba())
        #expect(tes.saldo.total == nil)
        #expect(tes.runway.meses == nil)
        #expect(tes.runway.motivo == "Sin datos del banco: importa un extracto")
        #expect(tes.serie(.todo).isEmpty)
        #expect(tes.totalVencido == nil)
        #expect(tes.sinConciliar == nil)
    }

    @Test func saldoEstimadoYDesconocido() {
        let bancos = "4 · Finanzas/Registros/Bancos/"
        let env = A.empresa([
            bancos + "a/Cuenta.md": A.cuenta(id: "a", nombre: "A", saldoInicial: "1000.00", fecha: "2026-08-31"),
            bancos + "a/movimientos.csv": A.cabMovs + A.mov("MOV-1", "2026-09-05", "RECIBO LUZ", "-100.00")
                + A.mov("MOV-0", "2026-08-20", "ANTES DEL SALDO INICIAL", "-5.00"),
            bancos + "b/Cuenta.md": A.cuenta(id: "b", nombre: "B"),
            bancos + "b/movimientos.csv": A.cabMovs + A.mov("MOV-2", "2026-09-06", "X", "-1.00"),
        ])
        defer { env.limpiar() }
        let tes = Tesoreria(snapshot: env.foto(), reloj: relojDePrueba())
        let s = tes.saldo
        let a = s.cuentas.first { $0.cuenta.id == "a" }!
        #expect(a.saldo == 90_000)
        #expect(a.fuente == .estimado)
        let b = s.cuentas.first { $0.cuenta.id == "b" }!
        #expect(b.saldo == nil)
        #expect(b.fuente == .desconocido)
        #expect(s.total == nil)
        #expect(s.conocido == 90_000)
        #expect(s.estimado)
        #expect(s.cuentasSinDato.map(\.id) == ["b"])
        #expect(tes.runway.meses == nil)
        #expect(tes.runway.motivo == "Falta el saldo de alguna cuenta")
        // La gráfica no baja a 0: sin el saldo de B no hay total.
        #expect(tes.serie(.semana).allSatisfy { $0.saldo == nil })
    }

    @Test func traspasosSinDeclararYMesIncompleto() {
        let bancos = "4 · Finanzas/Registros/Bancos/"
        let env = A.empresa([
            bancos + "a/Cuenta.md": A.cuenta(id: "a", nombre: "A"),
            bancos + "a/movimientos.csv": A.cabMovs
                + A.mov("MOV-1", "2026-09-10", "PASO A AHORRO", "-500.00", saldo: "1500.00")
                + A.mov("MOV-2", "2026-09-15", "ALQUILER", "-300.00", saldo: "1200.00"),
            bancos + "b/Cuenta.md": A.cuenta(id: "b", nombre: "B"),
            bancos + "b/movimientos.csv": A.cabMovs + A.mov("MOV-3", "2026-09-11", "DESDE CORRIENTE", "500.00", saldo: "500.00"),
        ])
        defer { env.limpiar() }
        let tes = Tesoreria(snapshot: env.foto(), reloj: relojDePrueba())
        #expect(tes.traspasos == ["MOV-1", "MOV-3"])
        #expect(tes.saldo.total == 170_000)
        // Los datos empiezan el 9 de septiembre: no hay ningún mes completo.
        #expect(tes.runway.meses == nil)
        #expect(tes.runway.motivo == "Hace falta al menos un mes completo de movimientos del banco")
        // En noviembre o diciembre, octubre y noviembre no cuentan: los movimientos acaban el 15 de septiembre y un mes
        // sin datos no es un mes sin gastos (integración F2: solo meses cubiertos enteros, como `KPIEvaluador`).
        let nov = Tesoreria(snapshot: env.foto(), reloj: relojDePrueba(2026, 11, 3))
        #expect(nov.runway.mesesUsados.isEmpty)
        #expect(nov.runway.motivo == "Hace falta al menos un mes completo de movimientos del banco")
        let dic = Tesoreria(snapshot: env.foto(), reloj: relojDePrueba(2026, 12, 3))
        #expect(dic.runway.mesesUsados.isEmpty)
        // Con un movimiento del 2 de diciembre, octubre y noviembre ya están cubiertos (sin salidas).
        let env2 = A.empresa([
            bancos + "a/Cuenta.md": A.cuenta(id: "a", nombre: "A"),
            bancos + "a/movimientos.csv": A.cabMovs
                + A.mov("MOV-1", "2026-09-10", "PASO A AHORRO", "-500.00", saldo: "1500.00")
                + A.mov("MOV-2", "2026-09-15", "ALQUILER", "-300.00", saldo: "1200.00")
                + A.mov("MOV-4", "2026-12-02", "INTERESES", "1.00", saldo: "1201.00"),
            bancos + "b/Cuenta.md": A.cuenta(id: "b", nombre: "B"),
            bancos + "b/movimientos.csv": A.cabMovs + A.mov("MOV-3", "2026-09-11", "DESDE CORRIENTE", "500.00", saldo: "500.00"),
        ])
        defer { env2.limpiar() }
        let dic2 = Tesoreria(snapshot: env2.foto(), reloj: relojDePrueba(2026, 12, 3))
        #expect(dic2.runway.mesesUsados == ["2026-10", "2026-11"])
        #expect(dic2.runway.motivo == "No hubo salidas de dinero en esos meses")
    }

    @Test func cobrosVencidos() {
        let env = A.empresa([
            "4 · Finanzas/Registros/emitidas.csv": A.cabEmitidas
                + "F-1,2026-09-01,Cliente Uno,F-1,EUR,121.00,Fiscal/2026/T3/Ingresos/f-1.md,,,,\n"
                + "F-2,2026-09-20,Cliente Dos,F-2,EUR,50.00,Fiscal/2026/T3/Ingresos/f-2.md,,,,\n"
                + "F-3,2026-09-21,Cliente Tres,F-3,EUR,70.00,,,,,\n"
                + "EMI-1,2026-01-10,Heredada,,EUR,10.00,,,,pendiente,importacion\n",
            "4 · Finanzas/Fiscal/2026/T3/Ingresos/f-1.md": "---\ntls_type: invoice\nnumero: F-1\nvence: 2026-09-08\ntotal: 121.00\n---\n# F-1\n",
            "4 · Finanzas/Fiscal/2026/T3/Ingresos/f-2.md": "---\ntls_type: invoice\nnumero: F-2\nvence: 2026-10-30\n---\n# F-2\n",
            "4 · Finanzas/Registros/pagos.csv": A.cabPagos + "PAG-20260910-001,2026-09-10,cobro,21.00,EUR,F-1,,Cliente Uno,,,confirmado\n",
        ])
        defer { env.limpiar() }
        let tes = Tesoreria(snapshot: env.foto(), reloj: relojDePrueba())
        #expect(tes.cobrosPendientes.map(\.factura.id) == ["F-1", "F-3", "F-2"])
        #expect(tes.cobrosVencidos.map(\.factura.id) == ["F-1"])
        #expect(tes.cobrosVencidos.first?.pendiente == 10_000)
        #expect(tes.cobrosVencidos.first?.diasVencida == 44)
        #expect(tes.totalVencido == 10_000)
        #expect(tes.sinRevisar == 1)
    }
}
