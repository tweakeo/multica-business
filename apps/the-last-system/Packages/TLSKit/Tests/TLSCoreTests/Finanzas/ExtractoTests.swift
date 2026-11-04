import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: importes y extractos del banco")
struct ExtractoTests {
    @Test func importesExactos() {
        #expect(DineroExacto.centimos("108.90") == 10890)
        #expect(DineroExacto.centimos("-663.00") == -66300)
        #expect(DineroExacto.centimos("181,50 €") == 18150)
        #expect(DineroExacto.centimos("1.234,56") == 123456)
        #expect(DineroExacto.centimos("1,234.56") == 123456)
        #expect(DineroExacto.centimos("−12,5") == -1250)
        #expect(DineroExacto.centimos("5-") == -500)
        #expect(DineroExacto.centimos("+7") == 700)
        #expect(DineroExacto.centimos("0") == 0)
        #expect(DineroExacto.centimos("") == nil)
        #expect(DineroExacto.centimos("abc") == nil)
        #expect(DineroExacto.centimos("12,345", decimal: ",") == nil)
        #expect(DineroExacto.centimos("1,500", decimal: ",") == 150)
        #expect(DineroExacto.centimos("1.234.567,89", decimal: ",") == 123_456_789)
        #expect(DineroExacto.centimos("12.34,5", decimal: ",") == nil)
        #expect(DineroExacto.csv(-66300) == "-663.00")
        #expect(DineroExacto.csv(5) == "0.05")
        #expect(DineroExacto.coma(1_966_465) == "19664,65")
        #expect(DineroExacto.euros(1_966_465) == "19.664,65 €")
        #expect(DineroExacto.euros(-5) == "-0,05 €")
        #expect(DineroExacto.euros(123_456_789) == "1.234.567,89 €")
    }

    @Test func extractoDeRiberaConElFormatoDeSuCuenta() throws {
        let snap = VaultSnapshot.read(root: RutasRepo.ribera)
        let registros = RegistrosFinanzas(snapshot: snap)
        let cuenta = try #require(registros.cuentas.first { $0.id == FinanzasApoyo.idCorriente })
        let formato = try #require(cuenta.formato)
        #expect(formato.separador == ";")
        #expect(formato.decimal == ",")
        #expect(formato.formatoFecha == .ddmmaaaa)
        #expect(formato.columnas.saldo == "saldo")
        let leido = try BankStatementParser.leer(FinanzasApoyo.datosRibera(FinanzasApoyo.extractoRibera), formato: formato)
        #expect(leido.filas.count == 29)
        #expect(leido.avisos.isEmpty)
        #expect(!leido.formatoAdivinado)
        let primera = leido.filas[0]
        #expect(primera.fecha.description == "2026-07-01")
        #expect(primera.concepto == "RECIBO INMOBILIARIA CENTRO SL ALQUILER")
        #expect(primera.importe == -66300)
        #expect(primera.saldo == 1_773_700)
        #expect(primera.fila == 2)
        // Sin formato se adivina lo mismo.
        let adivinado = try BankStatementParser.leer(FinanzasApoyo.datosRibera(FinanzasApoyo.extractoRibera))
        #expect(adivinado.formatoAdivinado)
        #expect(adivinado.filas == leido.filas)
        #expect(adivinado.formato.separador == ";")
        #expect(adivinado.formato.decimal == ",")
        #expect(adivinado.formato.columnas.fechaValor == "fecha_valor")
    }

    @Test func comaConCabeceraDelBancoBOMYSaltosDeWindows() throws {
        let texto = "\u{FEFF}Cuenta: ES00 **** 1234\r\nTitular: Estudio Ejemplo\r\n\r\n"
            + "Fecha operación,Fecha valor,Concepto,Importe (EUR),Saldo (EUR)\r\n"
            + "2026-09-01,2026-09-02,\"Transferencia de Luz, S.L.\",\"1,234.56\",\"5,234.56\"\r\n"
            + "2026-09-03,2026-09-03,Recibo Peña,-34.10,5200.46\r\n"
            + "Saldo final,,,,5200.46\r\n"
        let leido = try BankStatementParser.leer(Data(texto.utf8))
        #expect(leido.formato.separador == ",")
        #expect(leido.formato.decimal == ".")
        #expect(leido.formato.formatoFecha == .iso)
        #expect(leido.formato.columnas.fecha == "Fecha operación")
        #expect(leido.filas.count == 2)
        #expect(leido.filas[0].concepto == "Transferencia de Luz, S.L.")
        #expect(leido.filas[0].importe == 123_456)
        #expect(leido.filas[0].fechaValor?.description == "2026-09-02")
        #expect(leido.filas[1].importe == -3410)
        #expect(leido.filas[1].saldo == 520_046)
        #expect(leido.avisos.count == 1)
        #expect(leido.avisos[0].motivo.contains("fecha"))
    }

    @Test func cargosYAbonosYWindows1252() throws {
        // «Peña» en Windows-1252 (0xF1), como los extractos antiguos.
        var datos = Data("Fecha;Concepto;Cargo;Abono;Saldo\n05/10/2026;Recibo Pe".utf8)
        datos.append(0xF1)
        datos.append(contentsOf: Array("a;12,00;;988,00\n06/10/2026;Ingreso cliente;;100,00;1.088,00\n".utf8))
        let leido = try BankStatementParser.leer(datos)
        #expect(leido.filas.count == 2)
        #expect(leido.filas[0].concepto == "Recibo Peña")
        #expect(leido.filas[0].importe == -1200)
        #expect(leido.filas[1].importe == 10000)
        #expect(leido.filas[1].saldo == 108_800)
        #expect(leido.formato.columnas.cargo == "Cargo")
    }

    @Test func formatoDeLaCuentaQueYaNoCuadra() {
        let formato = FormatoExtracto(separador: ";", decimal: ",", formatoFecha: .ddmmaaaa,
                                      columnas: .init(fecha: "Fecha operación", concepto: "Concepto", importe: "Importe"))
        #expect(throws: ErrorExtracto.sinColumna("Fecha operación")) {
            try BankStatementParser.leer(texto: "fecha;concepto;importe\n01/10/2026;x;1,00\n", formato: formato)
        }
        #expect(throws: ErrorExtracto.sinCabecera) { try BankStatementParser.leer(texto: "a;b;c\n1;2;3\n") }
        #expect(throws: ErrorExtracto.vacio) { try BankStatementParser.leer(texto: "  \n") }
    }

    @Test func formatoDeFichaIdaYVuelta() throws {
        let f = FormatoExtracto(separador: ";", decimal: ",", formatoFecha: .ddmmaaaa,
                                columnas: .init(fecha: "Fecha operación", fechaValor: "F. valor", concepto: "Concepto",
                                                importe: "Importe: €", saldo: "Saldo"))
        var doc = FrontmatterDocument(text: FinanzasApoyo.cuenta(id: "c1", nombre: "Cuenta"))
        doc.merge(set: [f.propiedad], unset: [])
        #expect(FormatoExtracto.leer(deFicha: doc.text) == f)
        // La plantilla trae las columnas vacías: no hay formato.
        let plantilla = FinanzasApoyo.cuenta(id: "c2", nombre: "Otra", formato: """
        formato_extracto:
          separador: ";"
          decimal: ","
          formato_fecha: DD/MM/AAAA
          columnas:
            fecha:
            concepto:
            importe:

        """)
        #expect(FormatoExtracto.leer(deFicha: plantilla) == nil)
        #expect(FormatoExtracto.FormatoFecha(escrito: "dd/mm/yyyy") == .ddmmaaaa)
        #expect(FormatoExtracto.FormatoFecha.ddmmaa.leer("05/10/26")?.description == "2026-10-05")
        #expect(FormatoExtracto.FormatoFecha.ddmmaaaa.leer("31/02/2026") == nil)
    }
}
