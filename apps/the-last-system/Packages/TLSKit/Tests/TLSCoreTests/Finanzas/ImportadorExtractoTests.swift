import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: importar extractos sin duplicar")
struct ImportadorExtractoTests {
    typealias A = FinanzasApoyo

    /// Contrato del PLAN §4.6: la huella de los 30 movimientos de Ribera (las dos cuentas) sale igual.
    @Test func reproduceLosTreintaImportHashDeRibera() throws {
        let registros = RegistrosFinanzas(snapshot: VaultSnapshot.read(root: RutasRepo.ribera))
        #expect(registros.cuentas.count == 2)
        #expect(registros.movimientos.count == 30)
        var iguales = 0
        for m in registros.movimientos {
            let h = ImportadorExtracto.huella(cuentaID: m.cuentaID, fecha: m.fecha, importe: m.importe, concepto: m.concepto, saldo: m.saldo)
            #expect(h == m.importHash, "\(m.id)")
            #expect(ImportadorExtracto.movimientoID(huella: h) == m.id)
            if h == m.importHash { iguales += 1 }
        }
        #expect(iguales == 30)
        // El texto de la huella, tal cual (primer movimiento).
        let f = try #require(LocalDate(parsing: "2026-07-01"))
        #expect(ImportadorExtracto.textoHuella(cuentaID: A.idCorriente, fecha: f, importe: -66300,
                                               concepto: "RECIBO INMOBILIARIA CENTRO SL ALQUILER", saldo: 1_773_700)
                == "893a2ade-f982-40fb-ba96-eb6d8435e201|2026-07-01|-66300|recibo inmobiliaria centro sl alquiler|1773700")
    }

    @Test func importarElExtractoDeRiberaDaCeroNuevos() throws {
        let snap = VaultSnapshot.read(root: RutasRepo.ribera)
        let imp = ImportadorExtracto(snapshot: snap, reloj: A.relojRibera)
        let cuenta = try #require(imp.registros.cuentas.first { $0.id == A.idCorriente })
        let vista = try imp.vistaPrevia(A.datosRibera(A.extractoRibera), nombre: "cuenta-corriente-2026-07-a-10.csv", cuenta: cuenta)
        #expect(vista.filas.count == 29)
        #expect(vista.nuevas.isEmpty)
        #expect(vista.resumen == "29 movimientos · 0 nuevos · 29 ya importados")
        #expect(vista.plan(autor: A.manu) == nil)
        #expect(vista.evento(autor: A.manu) == nil)
        #expect(vista.originalYaGuardado)
        #expect(vista.lote == "2026-10-19 cuenta-corriente-2026-07-a-10.csv")
        // La cuenta de ahorro: su único movimiento, desde un extracto sintético.
        let ahorro = try #require(imp.registros.cuentas.first { $0.id == A.idAhorro })
        let extracto = "fecha;fecha_valor;concepto;importe;saldo\n14/08/2026;14/08/2026;TRASPASO DESDE CUENTA CORRIENTE;2000,00;7000,00\n"
        let v2 = try imp.vistaPrevia(Data(extracto.utf8), nombre: "ahorro.csv", cuenta: ahorro)
        #expect(v2.filas.map(\.movimientoID) == ["MOV-ac01229be87c"])
        #expect(v2.nuevas.isEmpty)
    }

    /// Con `movimientos.csv` vacío: importar escribe los 29 con las mismas huellas; repetir da «0 nuevos».
    @Test func importarDosVecesDaCeroNuevos() async throws {
        let env = A.ribera()
        defer { env.limpiar() }
        let movs = A.corriente + "/movimientos.csv"
        let original = try #require(env.texto(movs))
        let cabecera = String(original.prefix(while: { $0 != "\n" })) + "\n"
        env.escribir(movs, cabecera)
        let bus = try await env.bus()
        let antes = env.huella()

        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: A.relojRibera)
        let cuenta = try #require(imp.registros.cuentas.first { $0.id == A.idCorriente })
        let datos = A.datosRibera(A.extractoRibera)
        let vista = try imp.vistaPrevia(datos, nombre: "cuenta-corriente-2026-07-a-10.csv", cuenta: cuenta)
        #expect(vista.nuevas.count == 29)
        #expect(vista.resumen == "29 movimientos · 29 nuevos · 0 ya importados")
        #expect(vista.originalYaGuardado)
        let evento = try #require(vista.evento(autor: A.manu))
        #expect(evento.tipo == .extractoImportado)
        // La misma clave que da el EventDeriver del dominio al ver el original en Extractos/.
        #expect(evento.clave == "extracto.importado:ruta:" + TextFolding.pathKey(A.extractoRibera))
        #expect(evento.datos["lote"] == "2026-10-19 cuenta-corriente-2026-07-a-10.csv")
        #expect(evento.datos["nuevos"] == "29")
        let plan = try #require(vista.plan(autor: A.manu))
        let r = try await bus.ejecutar(plan)
        #expect(r.hecho)
        // Solo cambia movimientos.csv (el original ya estaba guardado con esos bytes).
        #expect(A.cambiados(antes, env.huella()) == [movs])
        let filas = A.filas(env, movs)
        let ribera = RegistrosFinanzas(snapshot: VaultSnapshot.read(root: RutasRepo.ribera)).movimientos.filter { $0.cuentaID == A.idCorriente }
        #expect(filas.map { $0["id"] ?? "" } == ribera.map(\.id))
        #expect(filas.map { $0["import_hash"] } == ribera.map(\.importHash))
        #expect(Set(filas.map { $0["lote"] }) == ["2026-10-19 cuenta-corriente-2026-07-a-10.csv"])
        #expect(Set(filas.map { $0["estado_conciliacion"] }) == ["pendiente"])
        #expect(filas[0]["importe"] == "-663.00")
        #expect(filas[0]["saldo"] == "17737.00")
        #expect(filas[0]["naturaleza"] == "gasto")
        #expect(filas[1]["naturaleza"] == "ingreso")

        // Segunda vez: 0 nuevos y nada que escribir.
        let otra = ImportadorExtracto(snapshot: env.foto(), reloj: A.relojRibera)
        let v2 = try otra.vistaPrevia(datos, nombre: "cuenta-corriente-2026-07-a-10.csv",
                                      cuenta: try #require(otra.registros.cuentas.first { $0.id == A.idCorriente }))
        #expect(v2.nuevas.isEmpty)
        #expect(v2.plan(autor: A.manu) == nil)

        // Deshacer deja los bytes de antes.
        _ = try await bus.deshacer(autor: A.manu)
        #expect(env.huella() == antes)
    }

    @Test func filasIgualesSinSaldoLlevanSuNumero() async throws {
        let env = A.empresa([
            "4 · Finanzas/Registros/Bancos/caja/Cuenta.md": A.cuenta(id: "cta-1", nombre: "Caja", saldoInicial: "100.00", fecha: "2026-09-30"),
            "4 · Finanzas/Registros/Bancos/caja/movimientos.csv": A.cabMovs,
        ])
        defer { env.limpiar() }
        let bus = try await env.bus()
        let extracto = "Fecha;Concepto;Importe\n01/10/2026;CAFE;-1,50\n01/10/2026;CAFE;-1,50\n01/10/2026;CAFE;-1,50\n"
        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba(2026, 10, 2))
        let cuenta = try #require(imp.registros.cuentas.first)
        let vista = try imp.vistaPrevia(Data(extracto.utf8), nombre: "octubre.csv", cuenta: cuenta)
        let f = try #require(LocalDate(parsing: "2026-10-01"))
        let base = ImportadorExtracto.textoHuella(cuentaID: "cta-1", fecha: f, importe: -150, concepto: "CAFE", saldo: nil)
        #expect(base == "cta-1|2026-10-01|-150|cafe|")
        #expect(vista.filas.map(\.huella) == [ContentHash.of(base), ContentHash.of(base + "|#2"), ContentHash.of(base + "|#3")])
        #expect(vista.nuevas.count == 3)
        #expect(vista.guardaFormato)
        _ = try await bus.ejecutar(try #require(vista.plan(autor: A.manu)))
        // El original se guardó con la fecha de hoy y el formato quedó en la ficha.
        #expect(env.texto("4 · Finanzas/Registros/Bancos/caja/Extractos/2026-10-02 octubre.csv") == extracto)
        let formato = try #require(FormatoExtracto.leer(deFicha: env.texto("4 · Finanzas/Registros/Bancos/caja/Cuenta.md")!))
        #expect(formato.columnas.importe == "Importe")
        // Otra vez: 0 nuevos. Y un extracto con una sola de esas filas también.
        let otra = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba(2026, 10, 3))
        let c2 = try #require(otra.registros.cuentas.first)
        #expect(c2.formato == formato)
        #expect(try otra.vistaPrevia(Data(extracto.utf8), nombre: "octubre.csv", cuenta: c2).nuevas.isEmpty)
        #expect(try otra.vistaPrevia(Data("Fecha;Concepto;Importe\n01/10/2026;CAFE;-1,50\n".utf8), nombre: "x.csv", cuenta: c2).nuevas.isEmpty)
        // Un nombre ocupado con otros bytes lleva « (2)».
        let v3 = try otra.vistaPrevia(Data("Fecha;Concepto;Importe\n02/10/2026;TE;-2,00\n".utf8), nombre: "octubre.csv", cuenta: c2)
        #expect(v3.original.name == "2026-10-03 octubre.csv")
        let hoy2 = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba(2026, 10, 2))
        let v4 = try hoy2.vistaPrevia(Data("Fecha;Concepto;Importe\n02/10/2026;TE;-2,00\n".utf8), nombre: "octubre.csv", cuenta: c2)
        #expect(v4.original.name == "2026-10-02 octubre (2).csv")
        #expect(v4.lote == "2026-10-02 octubre (2).csv")
    }

    /// La ficha nueva trae el formato vacío (plantilla «Cuenta bancaria»): se rellena con el adivinado, sin tocar lo demás;
    /// si el banco cambia de formato, se puede volver a adivinar.
    @Test func formatoDeLaPlantillaSeRellenaYSeCambia() async throws {
        let ficha = "4 · Finanzas/Registros/Bancos/caja/Cuenta.md"
        let texto = """
        ---
        tls_type: account
        tls_schema: 1
        id: cta-9
        nombre: Caja
        iban_ultimos4:                  # nunca el número completo
        moneda: EUR
        formato_extracto:               # lo rellena la app la primera vez que importas un extracto
          separador: ";"
          decimal: ","
          formato_fecha: DD/MM/AAAA
          columnas:
            fecha:
            concepto:
            importe:
        plantilla: "Cuenta bancaria v1"
        ---
        # Caja

        """
        let env = A.empresa([ficha: texto])
        defer { env.limpiar() }
        let bus = try await env.bus()
        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba())
        let cuenta = try #require(imp.registros.cuentas.first)
        #expect(cuenta.formato == nil)
        let vista = try imp.vistaPrevia(Data("F. Operación;Concepto;Importe\n01/10/2026;X;-1,00\n".utf8), nombre: "a.csv", cuenta: cuenta)
        #expect(vista.guardaFormato)
        _ = try await bus.ejecutar(try #require(vista.plan(autor: A.manu)))
        let nuevo = try #require(env.texto(ficha))
        #expect(nuevo.hasPrefix("---\ntls_type: account\ntls_schema: 1\nid: cta-9\nnombre: Caja\niban_ultimos4:                  # nunca el número completo\nmoneda: EUR\nformato_extracto:"))
        #expect(nuevo.contains("F. Operación"))
        #expect(nuevo.hasSuffix("plantilla: \"Cuenta bancaria v1\"\n---\n# Caja\n"))
        let c2 = try #require(RegistrosFinanzas(snapshot: env.foto()).cuentas.first)
        #expect(c2.formato?.columnas.fecha == "F. Operación")
        // El banco cambia las columnas: con el formato guardado no se lee; adivinando, sí, y se guarda el nuevo.
        let otro = Data("Fecha;Descripción;Importe;Saldo\n02/10/2026;Y;-2,00;7,00\n".utf8)
        let imp2 = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba())
        #expect(throws: ErrorImportacion.extracto(.sinColumna("F. Operación"))) {
            try imp2.vistaPrevia(otro, nombre: "b.csv", cuenta: c2)
        }
        let v2 = try imp2.vistaPrevia(otro, nombre: "b.csv", cuenta: c2, adivinarFormato: true)
        #expect(v2.guardaFormato)
        #expect(v2.extracto.formato.columnas.saldo == "Saldo")
    }

    @Test func filasRepetidasConSaldoSeEscribenUnaVez() throws {
        let env = A.empresa([
            "4 · Finanzas/Registros/Bancos/caja/Cuenta.md": A.cuenta(id: "cta-1", nombre: "Caja"),
        ])
        defer { env.limpiar() }
        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba())
        let cuenta = try #require(imp.registros.cuentas.first)
        let extracto = "fecha;concepto;importe;saldo\n01/10/2026;X;-1,00;9,00\n01/10/2026;X;-1,00;9,00\n"
        let vista = try imp.vistaPrevia(Data(extracto.utf8), nombre: "a.csv", cuenta: cuenta)
        #expect(vista.filas.count == 2)
        #expect(vista.nuevas.count == 1)
        #expect(vista.filas[1].repetidaEnElFichero)
    }

    @Test func cuentaSinMovimientosCreaElFicheroConSuCabecera() async throws {
        let env = A.empresa([
            "4 · Finanzas/Registros/Bancos/caja/Cuenta.md": A.cuenta(id: "cta-1", nombre: "Caja"),
        ])
        defer { env.limpiar() }
        let bus = try await env.bus()
        let antes = env.huella()
        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba())
        let cuenta = try #require(imp.registros.cuentas.first)
        let vista = try imp.vistaPrevia(Data("fecha;concepto;importe;saldo\n01/10/2026;\"Pago, con coma\";-1,00;9,00\n".utf8),
                                        nombre: "a.csv", cuenta: cuenta)
        _ = try await bus.ejecutar(try #require(vista.plan(autor: .sistema)))
        let base = "4 · Finanzas/Registros/Bancos/caja/"
        #expect(A.cambiados(antes, env.huella()) == [base + "Cuenta.md", base + "movimientos.csv", base + "Extractos/2026-10-22 a.csv"])
        let texto = try #require(env.texto(base + "movimientos.csv"))
        #expect(texto.hasPrefix(A.cabMovs))
        #expect(texto.contains(",\"Pago, con coma\",-1.00,9.00,gasto,"))
        #expect(RegistrosFinanzas(snapshot: env.foto()).movimientos.first?.concepto == "Pago, con coma")
    }

    @Test func dosCuentasConElMismoIdNoSeUsan() {
        let env = A.empresa([
            "4 · Finanzas/Registros/Bancos/a/Cuenta.md": A.cuenta(id: "igual", nombre: "A"),
            "4 · Finanzas/Registros/Bancos/b/Cuenta.md": A.cuenta(id: "igual", nombre: "B"),
            "4 · Finanzas/Registros/Bancos/c/Cuenta.md": A.cuenta(id: "otra", nombre: "C"),
        ])
        defer { env.limpiar() }
        let r = RegistrosFinanzas(snapshot: env.foto())
        #expect(r.cuentas.map(\.id) == ["otra"])
        #expect(r.avisos == ["Las cuentas «a» y «b» tienen el mismo identificador (igual): cambia uno antes de importar."])
    }

    /// Con muchas filas nuevas se añaden de una vez (no fila a fila), con el BOM y los saltos del fichero.
    @Test func unExtractoGrandeEnUnSoloPlan() async throws {
        let movs = "4 · Finanzas/Registros/Bancos/caja/movimientos.csv"
        let env = A.empresa([
            "4 · Finanzas/Registros/Bancos/caja/Cuenta.md": A.cuenta(id: "cta-1", nombre: "Caja"),
            movs: "\u{FEFF}" + A.cabMovs.replacingOccurrences(of: "\n", with: "\r\n"),
        ])
        defer { env.limpiar() }
        let bus = try await env.bus()
        var extracto = "fecha;concepto;importe;saldo\n"
        var saldo = 1_000_000
        for i in 0..<600 {
            let f = LocalDate(year: 2026, month: 1, day: 1)!.adding(days: i % 290)
            saldo -= 100
            extracto += String(format: "%02d/%02d/%04d;RECIBO %d;-1,00;%@\n", f.day, f.month, f.year, i, DineroExacto.coma(saldo))
        }
        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba())
        let vista = try imp.vistaPrevia(Data(extracto.utf8), nombre: "anual.csv", cuenta: try #require(imp.registros.cuentas.first))
        #expect(vista.nuevas.count == 600)
        let inicio = Date()
        _ = try await bus.ejecutar(try #require(vista.plan(autor: A.manu)))
        #expect(Date().timeIntervalSince(inicio) < 5)
        #expect(RegistrosFinanzas(snapshot: env.foto()).movimientos.count == 600)
        let datos = try Data(contentsOf: env.url(movs))
        #expect(datos.starts(with: [0xEF, 0xBB, 0xBF]))
        let texto = try #require(String(data: datos.dropFirst(3), encoding: .utf8))
        #expect(texto.components(separatedBy: "\r\n").count == 602)
        #expect(!texto.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(texto.contains("\r\n" + vista.nuevas[0].movimientoID + ",2026-01-01,,RECIBO 0,-1.00,9999.00,gasto,,,,,pendiente,,"))
    }

    @Test func sinCuentaNoSeImporta() throws {
        let env = A.empresa(["4 · Finanzas/Registros/Bancos/caja/movimientos.csv": A.cabMovs])
        defer { env.limpiar() }
        let registros = RegistrosFinanzas(snapshot: env.foto())
        #expect(registros.cuentas.isEmpty)
        #expect(registros.avisos.contains { $0.contains("no tiene ficha") })
    }
}
