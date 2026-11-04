import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Finanzas › Operación y el Banco con Ribera (F2 · rol areas-b): la caja, los cobros, las propuestas y el trimestre
/// que se enseñan; importar dos veces el extracto da «0 nuevos» (criterio F2-4); ninguna conciliación se confirma sin
/// el clic de una persona (F2-4) y, con ese clic, el dominio deja la oportunidad Ganada con un solo proyecto (F2-3);
/// los movimientos heredados quedan en preparación sin ninguna fila confirmada (F2-7). Todo se deshace; en solo
/// lectura nada se escribe; lo privado no aparece; sin datos, «Sin dato», nunca 0.
@Suite("Finanzas · operación, banco y trimestre", .serialized)
@MainActor
struct FinanzasOperacionTests {
    let apoyo = ApoyoAreasB()
    typealias A = ApoyoAreasB

    @Test("Ribera a 19/10: caja, meses de caja, cobros, propuesta de Talleres Martín y T3 estimado")
    func riberaSeLee() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(l.hoy.description == "2026-10-19")
        #expect(l.saldo.total == 2_666_465)
        #expect(TextoFinanzas.euros(l.saldo.total) == "26.664,65 €")
        #expect(TextoFinanzas.meses(l.runway.meses) == "7,9 meses")
        #expect(l.cuentas.count == 2)
        // Cobros: F-2026-0007 por cobrar (vence el 30), nada vencido. El 0 € es de verdad: hay facturas emitidas.
        #expect(l.hayEmitidas)
        #expect(l.totalVencido == 0)
        #expect(l.cobrosPendientes.map(\.factura.id) == ["F-2026-0007"])
        #expect(l.cobrosVencidos.isEmpty)
        // Banco: una propuesta exacta (la transferencia de Talleres Martín) y nada más abierto.
        #expect(l.sinConciliar == 1)
        #expect(l.propuestas.count == 1)
        let p = try #require(l.propuestas.first)
        #expect(p.factura.id == "F-2026-0007" && p.exacta && p.movimiento.importe == 18_150)
        #expect(l.abiertos.isEmpty)
        #expect(l.heredados == nil)
        // Trimestre: el T3 se presenta mañana; 303 a compensar y 115; el 111 «Sin dato»; el paquete ya está.
        #expect(l.periodo.titulo == "T3 2026")
        #expect(l.trimestre.diasHastaPlazo == 1)
        #expect(l.trimestre.modelo303.resultado == -44_415)
        #expect(l.trimestre.modelo115.resultado == 37_050)
        #expect(l.trimestre.modelo111.resultado == nil)
        #expect(l.paquete.yaExiste)
        // Gráfica: hoy es el último punto, con el saldo de la caja; lo que no se sabe es un hueco, nunca 0.
        let serie = try #require(l.series[.trimestre])
        #expect(serie.last?.fecha == l.hoy && serie.last?.saldo == 2_666_465)
        #expect(!serie.contains { $0.saldo == 0 })
        let tramos = TramoCajaFinanzas.de(serie)
        #expect(!tramos.isEmpty && tramos.allSatisfy { $0.puntos.count >= 1 })
        let v = try #require(VariacionCajaFinanzas(serie))
        #expect(v.hasta.saldo == 2_666_465)
        #expect(v.frase(.trimestre).hasPrefix("La caja"))
        // Otro trimestre se pide y se lee.
        await modelo.elegirPeriodo(l.periodo.anterior)
        #expect(modelo.lectura?.periodo.titulo == "T2 2026")
        #expect(modelo.lectura?.paquete.yaExiste == false)
    }

    @Test("Criterio F2-4: importar dos veces el extracto de Ribera da «0 nuevos»; con dos filas nuevas, solo esas; Deshacer")
    func importarDosVeces() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let original = try Data(contentsOf: e.carpeta.appendingPathComponent(A.extracto))
        let antes = apoyo.huella(e.carpeta)

        // El mismo extracto otra vez: elige la cuenta corriente sola y no hay nada nuevo.
        await modelo.previsualizar(datos: original, nombre: "cuenta-corriente-2026-07-a-10.csv")
        let vista = try #require(modelo.vista)
        #expect(vista.cuenta.carpeta.raw == A.corriente)
        #expect(vista.resumen == "29 movimientos · 0 nuevos · 29 ya importados")
        #expect(vista.originalYaGuardado)
        #expect(await modelo.importar(deshacer: nil) == false)
        #expect(modelo.hecho?.hasPrefix("Nada nuevo") == true)
        #expect(apoyo.huella(e.carpeta) == antes)

        // Con dos movimientos nuevos: solo esos dos se escriben (y el original en Extractos).
        let nuevo = String(decoding: original, as: UTF8.self)
            + "19/10/2026;19/10/2026;RECIBO MODELO 111 AEAT;-120,00;19544,65\n"
            + "19/10/2026;19/10/2026;TRANSFERENCIA DE CLIENTE NUEVO;300,00;19844,65\n"
        await modelo.previsualizar(datos: Data(nuevo.utf8), nombre: "cuenta-corriente-hasta-19-oct.csv")
        let vista2 = try #require(modelo.vista)
        #expect(vista2.resumen == "31 movimientos · 2 nuevos · 29 ya importados")
        let um = A.undo()
        um.beginUndoGrouping()
        let rev = sesion.revision
        #expect(await modelo.importar(deshacer: um))
        um.endUndoGrouping()
        #expect(modelo.hecho == "Importé 2 movimientos nuevos en Cuenta corriente Banco Demo.")
        let despues = apoyo.huella(e.carpeta)
        #expect(apoyo.cambiados(antes, despues) == [A.corriente + "/Extractos/2026-10-19 cuenta-corriente-hasta-19-oct.csv",
                                                    A.corriente + "/movimientos.csv"])
        // Ninguna conciliación ni cobro sin clic: pagos.csv igual y la transferencia sigue propuesta.
        #expect(despues[A.pagos] == antes[A.pagos])
        let movs = try #require(apoyo.texto(e, A.corriente + "/movimientos.csv"))
        #expect(movs.contains("MOV-11e4d44973fd,2026-10-17") && movs.contains(",propuesta,"))
        #expect(!movs.contains("TRANSFERENCIA DE CLIENTE NUEVO,300.00,19844.65,ingreso,,,,,conciliado"))

        // Otra vez el mismo fichero: «0 nuevos».
        await apoyo.esperarRevision(sesion, despuesDe: rev)
        await modelo.previsualizar(datos: Data(nuevo.utf8), nombre: "cuenta-corriente-hasta-19-oct.csv")
        #expect(modelo.vista?.resumen == "31 movimientos · 0 nuevos · 31 ya importados")
        #expect(await modelo.importar(deshacer: nil) == false)
        #expect(apoyo.huella(e.carpeta) == despues)

        // Deshacer deja la carpeta como estaba; nunca se borra: el original guardado pasa a Archivo.
        um.undo()
        await apoyo.esperar { self.apoyo.huella(e.carpeta)[A.corriente + "/movimientos.csv"] == antes[A.corriente + "/movimientos.csv"] }
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta))
                == ["Archivo/" + A.corriente + "/Extractos/2026-10-19 cuenta-corriente-hasta-19-oct.csv"])
    }

    @Test("Un extracto que no se entiende no escribe nada y lo dice; «Leer sin el formato de la cuenta» lo intenta otra vez")
    func extractoIlegible() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion, cuenta: VaultPath(A.corriente))
        await modelo.cargar()
        let antes = apoyo.huella(e.carpeta)
        // Columnas que no son las del formato de la cuenta.
        let otro = "Fecha operación,Concepto,Importe,Saldo\n2026-10-19,RECIBO LUZ,-50.00,19614.65\n"
        await modelo.previsualizar(datos: Data(otro.utf8), nombre: "otro-banco.csv")
        #expect(modelo.vista == nil)
        #expect(modelo.errorImportacion?.contains("formato") == true)
        await modelo.leerAdivinando()
        let v = try #require(modelo.vista)
        #expect(v.resumen == "1 movimiento · 1 nuevo · 0 ya importados")
        #expect(v.guardaFormato)
        modelo.cancelarImportacion()
        #expect(modelo.vista == nil && modelo.extracto == nil)
        #expect(apoyo.huella(e.carpeta) == antes)
    }

    @Test("Criterios F2-4 y F2-3: la propuesta solo se confirma con el clic; entonces Ganada y un proyecto; repetir no cambia nada")
    func confirmarSoloConClic() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let antes = apoyo.huella(e.carpeta)
        // Abrir, leer y esperar no confirma nada.
        try await Task.sleep(for: .milliseconds(300))
        await modelo.cargar(forzar: true)
        #expect(apoyo.huella(e.carpeta) == antes)
        let p = try #require(modelo.lectura?.propuestas.first)

        // El clic de la persona (lo que hace «Confirmar»).
        let um = A.undo()
        um.beginUndoGrouping()
        #expect(await modelo.confirmar(p, deshacer: um))
        um.endUndoGrouping()
        #expect(modelo.error == nil)
        #expect(modelo.hecho == "Confirmado: 181,50 € de F-2026-0007.")
        let pagos = try #require(apoyo.texto(e, A.pagos))
        #expect(pagos.contains("PAG-20261017-001,2026-10-17,cobro,181.50,EUR,F-2026-0007,"))
        #expect(pagos.contains("movimientos.csv#MOV-11e4d44973fd,confirmado"))
        let movs = try #require(apoyo.texto(e, A.corriente + "/movimientos.csv"))
        #expect(movs.contains("F-2026-0007,PAG-20261017-001,conciliado"))
        // El dominio (VEN-07): la oportunidad pasa a Ganada y nace un solo proyecto de entrega.
        let oportunidad = try #require(apoyo.texto(e, "2 · Ventas/Oportunidades/jorge-martin-trimestrales.md"))
        #expect(oportunidad.contains("estado: Ganada"))
        let proyectos = apoyo.huella(e.carpeta).filter { String(decoding: $0.value, as: UTF8.self).contains("tls_type: project") }
        #expect(proyectos.count == 1)
        // Ya no queda nada que confirmar.
        #expect(modelo.lectura?.propuestas.isEmpty == true)
        #expect(await modelo.confirmarLasExactas(deshacer: nil) == false)
        #expect(modelo.error == "No hay conciliaciones exactas que confirmar.")
        // Repetir la misma propuesta (vieja) no escribe otro cobro.
        let dos = apoyo.huella(e.carpeta)
        #expect(await modelo.confirmar(p, deshacer: nil) == false)
        #expect(apoyo.huella(e.carpeta) == dos)
    }

    @Test("«Confirmar las exactas» confirma el cobro y el pago en un solo cambio; un pago solo (sin reglas) se deshace de una vez")
    func confirmarLasExactas() async throws {
        // Un recibo de octubre en el banco y su factura recibida, aún sin conciliar (solo en la copia).
        let recibidas = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(A.recibidas), encoding: .utf8)
            + "REC-20261010-001,2026-10-10,Movil Levante SL,ML-10-2026,EUR,78.65,,Asesoría Ribera (DEMO),,,,65.00,13.65,0.00,Telefonía,\n"
        let movs = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(A.corriente + "/movimientos.csv"), encoding: .utf8)
            + "MOV-bbbbbbbbbbbb,2026-10-10,2026-10-10,RECIBO MOVIL LEVANTE SL,-78.65,19404.50,gasto,,,,,pendiente,,bbbbbbbbbbbb,prueba,\n"
        let preparar: [String: String?] = [A.recibidas: recibidas, A.corriente + "/movimientos.csv": movs]

        // Las dos exactas a la vez.
        do {
            let (e, sesion) = try await apoyo.abrir(preparar: preparar)
            defer { sesion.close(); e.limpiar() }
            let modelo = ModeloFinanzas(sesion: sesion)
            await modelo.cargar()
            #expect(modelo.lectura?.exactas.count == 2)
            #expect(await modelo.confirmarLasExactas(deshacer: nil))
            #expect(modelo.hecho == "Confirmadas 2 conciliaciones.")
            let pagos = try #require(apoyo.texto(e, A.pagos))
            #expect(pagos.contains("PAG-20261010-001,2026-10-10,pago,78.65,EUR,REC-20261010-001,"))
            #expect(pagos.contains("PAG-20261017-001,2026-10-17,cobro,181.50,EUR,F-2026-0007,"))
            #expect(modelo.lectura?.propuestas.isEmpty == true)
        }
        // Solo el pago (no dispara reglas): un Deshacer deja los mismos bytes.
        do {
            let (e, sesion) = try await apoyo.abrir(preparar: preparar)
            defer { sesion.close(); e.limpiar() }
            let modelo = ModeloFinanzas(sesion: sesion)
            await modelo.cargar()
            let p = try #require(modelo.lectura?.propuestas.first { $0.factura.id == "REC-20261010-001" })
            let antes = apoyo.huella(e.carpeta)
            let um = A.undo()
            um.beginUndoGrouping()
            #expect(await modelo.confirmar(p, deshacer: um))
            um.endUndoGrouping()
            #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [A.corriente + "/movimientos.csv", A.pagos])
            await apoyo.deshacer(um, e, hasta: antes)
            #expect(apoyo.huella(e.carpeta) == antes)
        }
    }

    @Test("Sin FIN-RUNWAY en Metas.md, «Medirlo en Control» añade su fila sin meta (propuesta 3 y 1); Deshacer")
    func runwayEnControl() async throws {
        let metas = "1 · Dirección/Metas.md"
        let sin = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(metas), encoding: .utf8)
            .replacingOccurrences(of: "| FIN-RUNWAY | Meses de caja | 3 meses | 2 meses |  |\n", with: "")
        #expect(!sin.contains("| FIN-RUNWAY |"))
        let (e, sesion) = try await apoyo.abrir(preparar: [metas: sin])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        #expect(modelo.lectura?.metas?.raw == metas)
        let antes = apoyo.huella(e.carpeta)
        let um = A.undo()
        um.beginUndoGrouping()
        #expect(await modelo.anadirRunwayAMetas(deshacer: um))
        um.endUndoGrouping()
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [metas])
        let t = try #require(apoyo.texto(e, metas))
        #expect(t.contains("| FIN-RUNWAY | Meses de caja |  |  | Propuesta: meta 3 meses, alerta 1 mes |"))
        // En Control sale sin meta decidida: el valor sigue oculto hasta que la fijes.
        let area = ModeloArea(area: .finanzas, sesion: sesion)
        await area.cargar()
        let fila = try #require(area.datos?.control.first { $0.codigo == "FIN-RUNWAY" })
        #expect(!fila.metaDecidida && !fila.valorVisible)
        // Ya está: no se repite.
        #expect(await modelo.anadirRunwayAMetas(deshacer: nil) == false)
        await apoyo.deshacer(um, e, hasta: antes)
        #expect(apoyo.huella(e.carpeta) == antes)
    }

    @Test("Ignorar un movimiento sin factura escribe su motivo y lo saca de lo abierto; Deshacer")
    func ignorar() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let mov = try #require(modelo.lectura?.propuestas.first?.movimiento)
        let antes = apoyo.huella(e.carpeta)
        let um = A.undo()
        um.beginUndoGrouping()
        #expect(await modelo.ignorar(mov, motivo: "Sin factura: otro gasto", deshacer: um))
        um.endUndoGrouping()
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [A.corriente + "/movimientos.csv"])
        #expect(apoyo.texto(e, A.corriente + "/movimientos.csv")?.contains("ignorado,Sin factura: otro gasto") == true)
        #expect(modelo.lectura?.sinConciliar == 0)
        await apoyo.deshacer(um, e, hasta: antes)
        #expect(apoyo.huella(e.carpeta) == antes)
    }

    @Test("Criterio F2-7: los 71 movimientos heredados quedan en preparación sin ninguna fila confirmada; otra vez, 0 nuevos")
    func heredados() async throws {
        let (e, sesion) = try await apoyo.abrir(preparar: Self.heredadosSinteticos())
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let prep = try #require(modelo.lectura?.heredados)
        #expect(prep.resumen == "71 movimientos heredados · 71 nuevos · 0 ya cargados")
        let antes = apoyo.huella(e.carpeta)
        let confirmadasAntes = Self.confirmadas(apoyo.texto(e, A.pagos))
        let um = A.undo()
        um.beginUndoGrouping()
        #expect(await modelo.cargarHeredados(deshacer: um))
        um.endUndoGrouping()
        #expect(modelo.hecho == "Cargué 71 movimientos heredados en preparación. Ninguno cuenta como cobrado hasta que lo revises.")
        // Solo cambian los tres registros: ni el banco ni ninguna regla (modo importación).
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [A.emitidas, A.pagos, A.recibidas])
        #expect(Self.confirmadas(apoyo.texto(e, A.pagos)) == confirmadasAntes)
        let l = try #require(modelo.lectura)
        #expect(l.sinRevisar == 35)
        #expect(l.heredados?.resumen == "71 movimientos heredados · 0 nuevos · 71 ya cargados")
        // Los ingresos sin revisar no son cobros pendientes.
        #expect(l.cobrosPendientes.map(\.factura.id) == ["F-2026-0007"])
        #expect(l.movimientos.count == 30)
        // Otra vez: nada.
        #expect(await modelo.cargarHeredados(deshacer: nil) == false)
        await apoyo.deshacer(um, e, hasta: antes)
        #expect(apoyo.huella(e.carpeta) == antes)
    }

    @Test("En solo lectura no se importa, no se confirma ni se prepara nada")
    func soloLectura() async throws {
        let (e, sesion) = try await apoyo.abrir(clase: .copia, escritura: .bloqueada)
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        #expect(modelo.motivoSoloLectura != nil)
        let antes = apoyo.huella(e.carpeta)
        let p = try #require(modelo.lectura?.propuestas.first)
        #expect(await modelo.confirmar(p, deshacer: nil) == false)
        #expect(modelo.error?.hasPrefix("No se puede escribir") == true)
        #expect(await modelo.confirmarLasExactas(deshacer: nil) == false)
        await modelo.elegirPeriodo(modelo.lectura?.periodo.anterior)
        #expect(await modelo.prepararPaquete(deshacer: nil) == false)
        #expect(apoyo.huella(e.carpeta) == antes)
    }

    @Test("Lo privado no aparece: ni su cuenta, ni sus movimientos, ni sus propuestas")
    func privado() async throws {
        let privada = "4 · Finanzas/Trámites/Expediente privado"
        let config = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
            .replacingOccurrences(of: "privado: []", with: "privado:\n  - \"\(privada)\"")
        let cuenta = """
        ---
        tls_type: account
        tls_schema: 1
        id: 00000000-0000-0000-0000-00000000ab01
        nombre: Cuenta reservada
        saldo_inicial: 1000.00
        fecha_saldo_inicial: 2026-06-30
        ---
        # Cuenta reservada
        """
        let movs = "id,fecha,fecha_valor,concepto,importe,saldo,naturaleza,categoria,proyecto_id,documento_id,pago_id,estado_conciliacion,motivo,import_hash,lote,verificacion\n"
            + "MOV-aaaaaaaaaaaa,2026-10-17,2026-10-17,TRANSFERENCIA DE TALLERES MARTIN E HIJOS SL,181.50,1181.50,ingreso,,,,,,,aaaaaaaaaaaa,x,\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [
            ".tls/config.yaml": config,
            privada + "/Bancos/reservada/Cuenta.md": cuenta,
            privada + "/Bancos/reservada/movimientos.csv": movs,
        ])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(l.cuentas.count == 2)
        #expect(!l.cuentas.contains { $0.nombre == "Cuenta reservada" })
        #expect(l.movimientos.count == 30)
        #expect(l.propuestas.count == 1 && l.propuestas[0].cuenta.carpeta.raw == A.corriente)
        #expect(l.saldo.total == 2_666_465)
    }

    @Test("Sin datos del banco ni facturas: «Sin dato», nunca 0")
    func sinDatos() async throws {
        let cab = "id,fecha,fecha_valor,concepto,importe,saldo,naturaleza,categoria,proyecto_id,documento_id,pago_id,estado_conciliacion,motivo,import_hash,lote,verificacion\n"
        func sinSaldo(_ ruta: String) throws -> String {
            try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(ruta), encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.hasPrefix("saldo_inicial") && !$0.hasPrefix("fecha_saldo_inicial") }.joined(separator: "\n")
        }
        let ahorro = "4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo"
        let (e, sesion) = try await apoyo.abrir(preparar: [
            A.corriente + "/movimientos.csv": cab, ahorro + "/movimientos.csv": cab,
            A.corriente + "/Cuenta.md": try sinSaldo(A.corriente + "/Cuenta.md"), ahorro + "/Cuenta.md": try sinSaldo(ahorro + "/Cuenta.md"),
            A.emitidas: nil, A.pagos: nil, A.recibidas: nil,
        ])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(!l.hayDatosBanco)
        #expect(l.saldo.total == nil && TextoFinanzas.euros(l.saldo.total) == "Sin dato")
        #expect(l.runway.meses == nil && l.runway.motivo != nil)
        #expect(TextoFinanzas.meses(l.runway.meses) == "Sin dato")
        #expect(!l.hayEmitidas && l.totalVencido == nil)
        #expect(l.sinConciliar == nil)
        #expect(l.series.values.allSatisfy { $0.allSatisfy { $0.saldo == nil } })
        #expect(VariacionCajaFinanzas(l.series[.mes] ?? []) == nil)
        #expect(l.trimestre.modelo303.resultado == nil)
    }

    // MARK: Ayudas

    static func confirmadas(_ pagos: String?) -> Int {
        (pagos ?? "").split(separator: "\n").filter { $0.hasSuffix(",confirmado") }.count
    }

    /// 71 movimientos sintéticos en tres ficheros (nunca datos reales), como los del rol de banco.
    static func heredadosSinteticos() -> [String: String?] {
        let importar = "4 · Finanzas/Registros/importar/"
        var t1 = "Concepto;Importe;Tipo;Fecha Cobro/Pago;Fecha Factura;IVA;Retención IRPF;Número Factura;Categoría;Tipo Fiscal;Cobrado/Pagado\n"
        for i in 1...20 {
            let dia = String(format: "%02d", (i % 27) + 1)
            t1 += "Servicio cliente \(i);100,00;Ingreso;2026-02-\(dia);2026-02-\(dia);21,00;;F2600\(String(format: "%02d", i));Servicios;ingreso;Yes\n"
        }
        for i in 1...10 {
            t1 += "Herramienta \(i);10,00;Gasto;2026-03-\(String(format: "%02d", i));2026-03-\(String(format: "%02d", i));2,10;;;Software;estandar;No\n"
        }
        t1 += "Cuota autónomos marzo;294,00;Gasto;2026-03-31;;;;;Seguridad Social;reta;Yes\n"
        var t2 = "fecha,concepto,tercero,total,tipo,numero_factura,cobrado\n"
        for i in 1...15 {
            t2 += "2026-05-\(String(format: "%02d", i)),Consultoría,Cliente \(i),242.00,ingreso,F2601\(String(format: "%02d", i)),no\n"
        }
        for i in 1...10 {
            t2 += "2026-06-\(String(format: "%02d", i)),Material,Proveedor \(i),-36.30,gasto,,sí\n"
        }
        var t3 = "Fecha,Concepto,Proveedor,Importe,Tipo,Categoría\n"
        for i in 1...12 {
            t3 += "\(String(format: "%02d", i))/08/2026,Alquiler,Inmobiliaria Sintética,-500.00,Gasto,\n"
        }
        t3 += "20/07/2026,Pago fraccionado,AEAT,-120.00,Gasto,Impuestos\n"
        t3 += "21/07/2026,Taxi,Taxis Uno,-12.00,Gasto,\n"
        t3 += "21/07/2026,Taxi,Taxis Uno,-12.00,Gasto,\n"
        return [importar + "2026 T1 movimientos.csv": t1, importar + "2026 T2 movimientos.csv": t2,
                importar + "2026 T3 movimientos.csv": t3]
    }
}
