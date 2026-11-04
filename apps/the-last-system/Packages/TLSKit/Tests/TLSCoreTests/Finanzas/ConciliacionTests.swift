import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: conciliación propuesta y confirmada por una persona")
struct ConciliacionTests {
    typealias A = FinanzasApoyo

    @Test func riberaProponeSoloElCobroDeTalleresMartin() throws {
        let registros = RegistrosFinanzas(snapshot: VaultSnapshot.read(root: RutasRepo.ribera))
        let ps = ConciliationMatcher(registros: registros).proponer()
        #expect(ps.count == 1)
        let p = try #require(ps.first)
        #expect(p.movimiento.id == "MOV-11e4d44973fd")
        #expect(p.factura.id == "F-2026-0007")
        #expect(p.coincidencia == .contraparte)
        #expect(p.motivo == "Importe exacto, contraparte coincidente y fecha más próxima")
        #expect(p.exacta)
        #expect(p.dias == 2)
        #expect(p.pendiente == 18150)
        // Lo ya cobrado no queda pendiente.
        #expect(registros.pendiente(de: try #require(registros.factura(id: "F-2026-0004"))) == 0)
    }

    @Test func confirmarEsDeUnaPersona() throws {
        let c = Conciliador(snapshot: VaultSnapshot.read(root: RutasRepo.ribera), reloj: A.relojRibera)
        let p = try #require(c.propuestas.first)
        #expect(throws: ErrorConciliacion.soloUnaPersona) { try c.confirmar(p, autor: .agente("contable")) }
        #expect(throws: ErrorConciliacion.soloUnaPersona) { try c.confirmar(p, autor: .sistema) }
        #expect(throws: ErrorConciliacion.soloUnaPersona) { try c.confirmarLasExactas(autor: .agente("contable")) }
    }

    @Test func confirmarEnRiberaEscribeConciliadoPagoYEvento() async throws {
        let env = A.ribera()
        defer { env.limpiar() }
        let bus = try await env.bus()
        let antes = env.huella()
        let c = Conciliador(snapshot: env.foto(), reloj: A.relojRibera)
        let p = try #require(c.propuestas.first)
        let conf = try c.confirmar(p, autor: A.manu)
        #expect(conf.pagos.map(\.id) == ["PAG-20261017-001"])
        let ev = try #require(conf.eventos.first)
        #expect(conf.eventos.count == 1)
        #expect(ev.tipo == .cobroConfirmado)
        #expect(ev.clave == "cobro.confirmado:PAG-20261017-001")
        #expect(ev.autor == "Manu")
        #expect(ev.datos["documento_id"] == "F-2026-0007")
        #expect(ev.datos["movimiento_id"] == "MOV-11e4d44973fd")
        #expect(ev.datos["importe"] == "181.50")
        #expect(ev.datos["factura"] == "4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
        #expect(ev.datos["oportunidad"] == "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]")
        let r = try await bus.ejecutar(conf.plan)
        #expect(r.hecho)
        let movs = A.corriente + "/movimientos.csv"
        let pagos = A.fin + "/Registros/pagos.csv"
        #expect(A.cambiados(antes, env.huella()) == [movs, pagos])
        let fila = try #require(A.filas(env, movs).first { $0["id"] == "MOV-11e4d44973fd" })
        #expect(fila["estado_conciliacion"] == "conciliado")
        #expect(fila["pago_id"] == "PAG-20261017-001")
        #expect(fila["documento_id"] == "F-2026-0007")
        #expect(env.texto(pagos)!.hasSuffix(
            "PAG-20261017-001,2026-10-17,cobro,181.50,EUR,F-2026-0007,,Talleres Martín e Hijos SL,transferencia,"
                + "Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv#MOV-11e4d44973fd,confirmado\n"))
        // Ya no hay nada que proponer ni que cobrar, y repetir con la propuesta vieja no hace nada.
        let despues = Conciliador(snapshot: env.foto(), reloj: A.relojRibera)
        #expect(despues.propuestas.isEmpty)
        #expect(throws: ErrorConciliacion.yaConciliado("MOV-11e4d44973fd")) { try despues.confirmar(p, autor: A.manu) }
        let tes = Tesoreria(registros: despues.registros, hoy: A.relojRibera.hoy)
        #expect(tes.cobrosPendientes.isEmpty)
        #expect(tes.sinConciliar == 0)
        _ = try await bus.deshacer(autor: A.manu)
        #expect(env.huella() == antes)
    }

    /// Empresa sintética: varias facturas y movimientos para las reglas de la especificación.
    static func empresa() -> EntornoCarpeta {
        let banco = "4 · Finanzas/Registros/Bancos/banco"
        return A.empresa([
            banco + "/Cuenta.md": A.cuenta(id: "cta-1", nombre: "Banco", saldoInicial: "1000.00", fecha: "2026-08-31"),
            banco + "/movimientos.csv": A.cabMovs
                + A.mov("MOV-a1", "2026-09-10", "TRANSFERENCIA ESTUDIO NORTE FRA F-2026-0011", "242.00")
                + A.mov("MOV-a2", "2026-09-12", "TRANSFERENCIA ESTUDIO NORTE", "242.00")
                + A.mov("MOV-a3", "2026-09-01", "TRANSF LIBRERIA SUR", "60.50")
                + A.mov("MOV-a4", "2026-09-20", "RECIBO PAPELERIA CENTRO", "-30.25")
                + A.mov("MOV-a5", "2026-09-21", "INGRESO DESCONOCIDO", "500.00")
                + A.mov("MOV-a6", "2026-09-22", "TRANSFERENCIA DE ACME", "100.00")
                + A.mov("MOV-a7", "2026-09-23", "AEAT MODELO 303", "-90.00", estado: "ignorado"),
            "4 · Finanzas/Registros/emitidas.csv": A.cabEmitidas
                + "F-2026-0010,2026-09-01,Estudio Norte SL,F-2026-0010,EUR,242.00,,,,,\n"
                + "F-2026-0011,2026-09-05,Estudio Norte SL,F-2026-0011,EUR,242.00,,,,,\n"
                + "F-2026-0012,2026-09-05,Librería Sur,F-2026-0012,EUR,60.50,,,,,\n"
                + "F-2026-0013,2026-09-10,Acme Uno SL,F-2026-0013,EUR,100.00,,,,,\n"
                + "F-2026-0014,2026-09-10,Acme Dos SL,F-2026-0014,EUR,100.00,,,,,\n"
                + "F-2026-0015,2026-09-01,Cliente Parcial SL,F-2026-0015,EUR,300.00,,,,,\n",
            "4 · Finanzas/Registros/recibidas.csv": A.cabRecibidas
                + "REC-20260915-001,2026-09-15,Papelería Centro SL,PC-77,EUR,30.25,,,,,,25.00,5.25,,Material,\n",
            "4 · Finanzas/Registros/pagos.csv": A.cabPagos
                + "PAG-20260920-001,2026-09-20,cobro,50.00,EUR,F-2026-0015,,Cliente Parcial SL,,,confirmado\n"
                + "PAG-20260921-001,2026-09-21,cobro,250.00,EUR,F-2026-0015,,Cliente Parcial SL,,,\n",
        ])
    }

    @Test func reglasDelEmparejamiento() throws {
        let env = Self.empresa()
        defer { env.limpiar() }
        let registros = RegistrosFinanzas(snapshot: env.foto())
        // Solo los pagos confirmados descuentan: a F-0015 le quedan 250,00 (el de 250 sin confirmar no cuenta).
        #expect(registros.pendiente(de: try #require(registros.factura(id: "F-2026-0015"))) == 25000)
        let ps = Dictionary(uniqueKeysWithValues: ConciliationMatcher(registros: registros).proponer().map { ($0.movimiento.id, $0) })
        // El número de factura pesa más que la contraparte: MOV-a1 lleva F-2026-0011 aunque F-0010 sea igual de importe.
        #expect(ps["MOV-a1"]?.factura.id == "F-2026-0011")
        #expect(ps["MOV-a1"]?.coincidencia == .numeroFactura)
        #expect(ps["MOV-a1"]?.motivo == ConciliationMatcher.motivoNumero)
        // Una factura por movimiento: MOV-a2 se queda con F-0010 (la otra ya está cogida).
        #expect(ps["MOV-a2"]?.factura.id == "F-2026-0010")
        #expect(ps["MOV-a2"]?.coincidencia == .contraparte)
        // Hasta 3 días antes de la factura: MOV-a3 (1 sep) con F-0012 (5 sep) son 4 días: no.
        #expect(ps["MOV-a3"] == nil)
        // Gasto: sale dinero por una recibida.
        #expect(ps["MOV-a4"]?.factura.id == "REC-20260915-001")
        // Sin número ni contraparte no se propone.
        #expect(ps["MOV-a5"] == nil)
        // «ACME» casa con dos facturas iguales: se propone una, pero no es exacta.
        let acme = try #require(ps["MOV-a6"])
        #expect(!acme.exacta)
        #expect(acme.factura.id == "F-2026-0013")
        #expect(acme.motivo.contains("revísala"))
        // Ignorado no entra.
        #expect(ps["MOV-a7"] == nil)
        #expect(ps.count == 4)
    }

    @Test func confirmarLasExactasEnLoteConUnDeshacer() async throws {
        let env = Self.empresa()
        defer { env.limpiar() }
        // Dos movimientos el mismo día para ver la numeración.
        let banco = "4 · Finanzas/Registros/Bancos/banco/movimientos.csv"
        env.escribir(banco, env.texto(banco)!.replacingOccurrences(of: "MOV-a2,2026-09-12,2026-09-12", with: "MOV-a2,2026-09-10,2026-09-10"))
        let bus = try await env.bus()
        let antes = env.huella()
        let c = Conciliador(snapshot: env.foto(), reloj: relojDePrueba())
        let conf = try c.confirmarLasExactas(autor: A.manu)
        #expect(conf.propuestas.map(\.movimiento.id).sorted() == ["MOV-a1", "MOV-a2", "MOV-a4"])
        #expect(conf.pagos.map(\.id).sorted() == ["PAG-20260910-001", "PAG-20260910-002", "PAG-20260920-002"])
        #expect(conf.eventos.count == 2)
        #expect(conf.resumen == "Confirmar 3 conciliaciones")
        let pagoGasto = try #require(conf.pagos.first { $0.fila["documento_id"] == "REC-20260915-001" })
        #expect(pagoGasto.fila["direccion"] == "pago")
        #expect(pagoGasto.fila["importe"] == "30.25")
        #expect(pagoGasto.fila["metodo"] == "domiciliación")
        _ = try await bus.ejecutar(conf.plan)
        let despues = RegistrosFinanzas(snapshot: env.foto())
        #expect(despues.movimientos.filter { $0.estado == .conciliado }.count == 3)
        #expect(despues.pagos.filter(\.confirmado).count == 4)
        // Lo que queda: la ambigua de Acme, que se revisa a mano.
        #expect(Conciliador(registros: despues, reloj: relojDePrueba()).propuestas.map(\.movimiento.id) == ["MOV-a6"])
        #expect(throws: ErrorConciliacion.nadaQueConfirmar) {
            try Conciliador(registros: despues, reloj: relojDePrueba()).confirmarLasExactas(autor: A.manu)
        }
        _ = try await bus.deshacer(autor: A.manu)
        #expect(env.huella() == antes)
    }

    @Test func proponerEIgnorarNoConfirman() async throws {
        let env = Self.empresa()
        defer { env.limpiar() }
        let bus = try await env.bus()
        let c = Conciliador(snapshot: env.foto(), reloj: relojDePrueba())
        let plan = try #require(c.planProponer(c.propuestas, autor: .agente("contable")))
        _ = try await bus.ejecutar(plan)
        let r = RegistrosFinanzas(snapshot: env.foto())
        #expect(r.movimientos.filter { $0.estado == .propuesta }.count == 4)
        #expect(r.movimientos.filter { $0.estado == .conciliado }.isEmpty)
        #expect(r.pagos.count == 2)
        // Volver a proponer lo mismo no escribe nada.
        let c2 = Conciliador(registros: r, reloj: relojDePrueba())
        #expect(c2.planProponer(c2.propuestas, autor: .agente("contable")) == nil)
        // Ignorar un ingreso sin factura.
        let mov = try #require(r.movimientos.first { $0.id == "MOV-a5" })
        _ = try await bus.ejecutar(try c2.planIgnorar(mov, motivo: "Aportación del socio", autor: A.manu))
        let r2 = RegistrosFinanzas(snapshot: env.foto())
        #expect(r2.movimientos.first { $0.id == "MOV-a5" }?.estado == .ignorado)
        #expect(r2.movimientos.first { $0.id == "MOV-a5" }?.motivo == "Aportación del socio")
        #expect(throws: ErrorConciliacion.yaConciliado("MOV-a5")) {
            try Conciliador(registros: r2, reloj: relojDePrueba()).planIgnorar(mov, motivo: "x", autor: A.manu)
        }
    }

    @Test func rectificativaSeDevuelveComoPago() async throws {
        let env = A.empresa([
            "4 · Finanzas/Registros/Bancos/banco/Cuenta.md": A.cuenta(id: "cta-1", nombre: "Banco"),
            "4 · Finanzas/Registros/Bancos/banco/movimientos.csv": A.cabMovs
                + A.mov("MOV-r1", "2026-10-02", "DEVOLUCION A CLIENTE NORTE R-2026-0001", "-50.00"),
            "4 · Finanzas/Registros/emitidas.csv": A.cabEmitidas
                + "R-2026-0001,2026-10-01,Cliente Norte SL,R-2026-0001,EUR,-50.00,,,,,\n",
        ])
        defer { env.limpiar() }
        let bus = try await env.bus()
        let c = Conciliador(snapshot: env.foto(), reloj: relojDePrueba())
        let p = try #require(c.propuestas.first)
        #expect(p.factura.id == "R-2026-0001")
        #expect(p.coincidencia == .numeroFactura)
        let conf = try c.confirmar(p, autor: A.manu)
        #expect(conf.pagos.first?.fila["direccion"] == "pago")
        #expect(conf.pagos.first?.fila["importe"] == "50.00")
        // Devolver dinero no es un cobro: no hay cobro.confirmado.
        #expect(conf.eventos.isEmpty)
        _ = try await bus.ejecutar(conf.plan)
        let r = RegistrosFinanzas(snapshot: env.foto())
        #expect(r.pendiente(de: try #require(r.factura(id: "R-2026-0001"))) == 0)
        #expect(ConciliationMatcher(registros: r).proponer().isEmpty)
    }

    @Test func comparaNumerosYContrapartes() {
        let c = ConciliationMatcher.palabras("TRANSF. DE PANADERÍA HORNO SOL FRAF-2026-0004/2")
        #expect(ConciliationMatcher.contieneNumero(c, "F-2026-0004"))
        #expect(!ConciliationMatcher.contieneNumero(ConciliationMatcher.palabras("F-2026-00045"), "F-2026-0004"))
        #expect(!ConciliationMatcher.contieneNumero(ConciliationMatcher.palabras("REF 12026-2359"), "2026-2359"))
        #expect(ConciliationMatcher.contieneNumero(ConciliationMatcher.palabras("PAGO 2026-2359"), "2026-2359"))
        #expect(ConciliationMatcher.primeraPalabra("La Clínica Dental Sonrisa SLP") == "clinica")
        #expect(ConciliationMatcher.primeraPalabra("SL") == nil)
        #expect(Conciliador.metodo("TRANSFERENCIA DE X") == "transferencia")
        #expect(Conciliador.metodo("RECIBO MOVIL LEVANTE SL") == "domiciliación")
        #expect(Conciliador.metodo("REMESA CUOTAS") == "")
    }
}
