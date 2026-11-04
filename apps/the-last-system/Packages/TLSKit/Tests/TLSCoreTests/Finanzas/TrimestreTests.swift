import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: trimestre, modelos estimados y lectura de originales")
struct TrimestreTests {
    typealias A = FinanzasApoyo

    static func d(_ s: String) -> LocalDate { LocalDate(parsing: s)! }

    @Test func plazosDelTrimestre() throws {
        let t3 = try #require(PeriodoTrimestre(anio: 2026, numero: 3))
        #expect(t3.desde == Self.d("2026-07-01"))
        #expect(t3.hasta == Self.d("2026-09-30"))
        #expect(t3.precierre == Self.d("2026-10-05"))
        #expect(t3.domiciliacion == Self.d("2026-10-15"))
        #expect(t3.plazo == Self.d("2026-10-20"))
        #expect(t3.titulo == "T3 2026")
        let t4 = try #require(PeriodoTrimestre(anio: 2026, numero: 4))
        #expect(t4.hasta == Self.d("2026-12-31"))
        #expect(t4.plazo == Self.d("2027-01-30"))
        #expect(t4.domiciliacion == Self.d("2027-01-25"))
        #expect(PeriodoTrimestre(anio: 2026, numero: 1)!.hasta == Self.d("2026-03-31"))
        #expect(PeriodoTrimestre(anio: 2026, numero: 2)!.hasta == Self.d("2026-06-30"))
        #expect(PeriodoTrimestre(anio: 2026, numero: 5) == nil)
        #expect(PeriodoTrimestre.aPresentar(hoy: Self.d("2026-10-19")) == t3)
        #expect(PeriodoTrimestre.aPresentar(hoy: Self.d("2026-10-20")) == t3)
        #expect(PeriodoTrimestre.aPresentar(hoy: Self.d("2026-10-21")) == t4)
        #expect(PeriodoTrimestre.aPresentar(hoy: Self.d("2027-01-30")) == t4)
        #expect(t4.siguiente.id == "2027-T1")
        #expect(PeriodoTrimestre(contiene: Self.d("2027-02-01")).anterior == t4)
    }

    @Test func trimestreTresDeRibera() throws {
        let t = TrimestreFiscal(snapshot: VaultSnapshot.read(root: RutasRepo.ribera), reloj: A.relojRibera)
        #expect(t.forma == .sociedad)
        #expect(t.aPresentar.titulo == "T3 2026")
        let r = t.resumen(t.aPresentar)
        #expect(r.diasHastaPlazo == 1)
        // Como el paquete T3 de Ribera: ingresos 390,00 + 81,90; gastos 2.505,00 + 526,05 − 370,50.
        #expect(r.ingresos == TotalesLibro(documentos: 3, base: 39_000, iva: 8190, retencion: 0, total: 47_190))
        #expect(r.gastos == TotalesLibro(documentos: 9, base: 250_500, iva: 52_605, retencion: 37_050, total: 266_055))
        #expect(r.modelo303.resultado == -44_415)
        #expect(r.modelo303.lineas.map(\.importe) == [8190, 52_605])
        #expect(r.modelo303.faltan.isEmpty)
        #expect(r.modelo130.aplica == .no("Las sociedades no presentan el 130."))
        // Tres nóminas sin su retención en los registros: el 111 queda sin dato (nunca 0).
        #expect(r.modelo111.aplica == .si)
        #expect(r.modelo111.resultado == nil)
        #expect(r.modelo111.parcial == 0)
        #expect(r.modelo111.faltan.count == 3)
        #expect(r.modelo115.resultado == 37_050)
    }

    @Test func autonomoConElCientoTreinta() throws {
        let env = A.empresa([
            ".tls/config.yaml": "version: 1\nclase: copia\nfiscal:\n  forma: autonomo\n",
            "4 · Finanzas/Registros/emitidas.csv": "id,fecha_documento,tercero,numero_documento,moneda,total_documento,documento,ambito,proyecto_id,estado_revision,fuente,base,iva,retencion\n"
                + "F1,2026-02-01,Uno,F1,EUR,1210.00,,,,,,1000.00,210.00,0.00\n"
                + "F2,2026-05-01,Dos,F2,EUR,1950.00,,,,,,2000.00,420.00,300.00\n"
                + "F3,2026-05-02,Tres,F3,EUR,121.00,,,,,,,,\n",
            "4 · Finanzas/Registros/recibidas.csv": A.cabRecibidas
                + "R1,2026-02-10,Proveedor,P1,EUR,121.00,,,,,,100.00,21.00,0.00,Software,\n"
                + "R2,2026-05-10,Gasolinera,G1,EUR,60.50,,,,,,50.00,10.50,0.00,Transporte,\n",
        ])
        defer { env.limpiar() }
        // Tipo fiscal de la gasolina: la mitad del IVA.
        env.escribir("4 · Finanzas/Registros/recibidas.csv", env.texto("4 · Finanzas/Registros/recibidas.csv")!
            .replacingOccurrences(of: "naturaleza\n", with: "naturaleza,tipo_fiscal\n")
            .replacingOccurrences(of: "Transporte,\n", with: "Transporte,,gasolina\n"))
        let t = TrimestreFiscal(snapshot: env.foto(), reloj: relojDePrueba(2026, 7, 1))
        #expect(t.forma == .autonomo)
        let t1 = t.modelo130(PeriodoTrimestre(anio: 2026, numero: 1)!)
        // T1: (1.000 − 100) × 20 % = 180.
        #expect(t1.resultado == 18_000)
        let t2 = t.modelo130(PeriodoTrimestre(anio: 2026, numero: 2)!)
        // F3 no dice su base: el T2 queda sin dato, con lo que sí se sabe aparte.
        #expect(t2.resultado == nil)
        #expect(t2.faltan.map(\.id) == ["F3"])
        // Acumulado: (3.000 − 150) × 20 % = 570 − 300 de retenciones − 180 del T1 = 90.
        #expect(t2.parcial == 9000)
        let iva2 = t.modelo303(PeriodoTrimestre(anio: 2026, numero: 2)!)
        #expect(iva2.resultado == nil)
        #expect(iva2.parcial == 42_000 - 525)
        #expect(iva2.faltan.map(\.tipo) == ["ingreso sin IVA conocido"])
        let iva1 = t.modelo303(PeriodoTrimestre(anio: 2026, numero: 1)!)
        #expect(iva1.resultado == 21_000 - 2100)
        // Sin facturas: sin dato (ni en el 303 ni en los totales del libro).
        let vacio = t.modelo303(PeriodoTrimestre(anio: 2026, numero: 3)!)
        #expect(vacio.resultado == nil)
        #expect(vacio.parcial == nil)
        let r3 = t.resumen(PeriodoTrimestre(anio: 2026, numero: 3)!)
        #expect(r3.ingresos == TotalesLibro(documentos: 0, base: nil, iva: nil, retencion: nil, total: nil))
    }

    @Test func formaJuridicaDesdeLaCarpeta() {
        func forma(_ config: String) -> FormaJuridica? {
            let env = A.empresa([".tls/config.yaml": config])
            defer { env.limpiar() }
            return FormaJuridica.deCarpeta(env.foto())
        }
        #expect(forma("facturacion:\n  nif: 12345678Z\n") == .autonomo)
        #expect(forma("facturacion:\n  nif: X1234567L\n") == .autonomo)
        #expect(forma("facturacion:\n  nif: B12345678\n") == .sociedad)
        #expect(forma("fiscal:\n  forma: sociedad\nfacturacion:\n  nif: 12345678Z\n") == .sociedad)
        #expect(forma("version: 1\n") == nil)
    }

    @Test func intracomunitarioYExtranjero() {
        let env = A.empresa([
            "4 · Finanzas/Registros/recibidas.csv": "id,fecha_documento,tercero,numero_documento,moneda,total_documento,documento,ambito,proyecto_id,estado_revision,fuente,base,iva,retencion,categoria,naturaleza,tipo_fiscal\n"
                + "R1,2026-10-01,Herramienta EEUU,I1,EUR,20.00,,,,,,20.00,,,,,extranjero\n"
                + "R2,2026-10-02,Proveedor UE,U1,EUR,100.00,,,,,,100.00,,,,,intracomunitario\n",
        ])
        defer { env.limpiar() }
        let m = TrimestreFiscal(snapshot: env.foto(), reloj: relojDePrueba()).modelo303(PeriodoTrimestre(anio: 2026, numero: 4)!)
        // El extranjero no entra; el intracomunitario va a las dos casillas y el neto es 0 (dato real, no relleno).
        #expect(m.resultado == 0)
        #expect(m.lineas.map(\.importe) == [2100, 2100])
        #expect(m.faltan.isEmpty)
    }

    @Test func leerOriginalesPorSuNombre() {
        let f = LectorFiscal.fecha("2026-06-30 F260007 Clara Ibáñez 480,00€", anioCarpeta: nil)
        #expect(f?.fecha == Self.d("2026-06-30"))
        #expect(f?.formato == "iso")
        #expect(LectorFiscal.fecha("2026-03 Cuota autónomos", anioCarpeta: nil)?.mesEntero == true)
        #expect(LectorFiscal.fecha("Amazon 17.06.25", anioCarpeta: nil)?.fecha == Self.d("2025-06-17"))
        #expect(LectorFiscal.fecha("Urba gestores mayo25", anioCarpeta: nil)?.fecha == Self.d("2025-05-01"))
        #expect(LectorFiscal.fecha("Urba gestores septiembre", anioCarpeta: 2025)?.fecha == Self.d("2025-09-01"))
        #expect(LectorFiscal.fecha("sin fecha", anioCarpeta: nil) == nil)
        #expect(LectorFiscal.importe("2026-06-30 F260007 Clara Ibáñez 480,00€") == 48_000)
        #expect(LectorFiscal.importe("Ordenador 4.560€") == 456_000)
        #expect(LectorFiscal.importe("Abono -572,40€") == -57_240)
        #expect(LectorFiscal.trimestre(de: Self.d("2026-08-14")) == "2026-T3")

        let ing = LectorFiscal.leerIngreso(VaultPath("Fiscal/2026/T2/Ingresos/2026-06-30 F260007 Clara Ibáñez 480,00€.pdf"), anioCarpeta: 2026)
        #expect(ing.numero == "F260007")
        #expect(ing.tercero == "Clara Ibáñez")
        #expect(ing.importe == 48_000)
        #expect(ing.tipoFiscal == "ingreso")
        #expect(ing.falta.isEmpty)

        let gasto = LectorFiscal.leerGasto(VaultPath("Fiscal/2026/T3/Gastos/2026-07-01 Anthropic Claude Pro 21,78€.pdf"),
                                           subcarpeta: nil, anioCarpeta: 2026)
        #expect(gasto.tercero == "Anthropic Claude")
        #expect(gasto.terceroSupuesto)
        #expect(gasto.importe == -2178)
        #expect(gasto.tipoFiscal == "extranjero")
        #expect(gasto.categoria == "Herramientas/Software")

        let ribera = LectorFiscal.leerGasto(
            VaultPath("Fiscal/2026/T3/Gastos/movil-levante/2026-07-10 Movil Levante ML-07-2026 78,65€.pdf"),
            subcarpeta: "movil-levante", anioCarpeta: 2026)
        #expect(ribera.tercero == "movil-levante")
        #expect(!ribera.terceroSupuesto)
        #expect(ribera.fecha == Self.d("2026-07-10"))
        #expect(ribera.importe == -7865)
        // Lo que el nombre no dice, no se dice: sin tipo fiscal, con su motivo.
        #expect(ribera.tipoFiscal == nil)
        #expect(ribera.falta == ["no se puede saber el tipo fiscal del nombre"])
        #expect(LectorFiscal.tipoFiscal(nombre: "2026-05-01 CN260004 Abono", proveedor: nil, importe: nil) == "rectificativa")
        #expect(LectorFiscal.tipoFiscal(nombre: "Repsol 40€", proveedor: nil, importe: 4000) == "gasolina")
    }
}
