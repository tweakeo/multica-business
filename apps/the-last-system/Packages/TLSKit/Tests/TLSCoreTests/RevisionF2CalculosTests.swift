import Foundation
import Testing
@testable import TLSCore

/// Revisión adversarial de cálculos y datos de F2 (núcleo). Cada prueba reprodujo un fallo encontrado en la revisión;
/// desde la revisión final están arreglados y las pruebas quedan como regresión. Siempre sobre copias temporales de
/// Ribera o carpetas sintéticas; nunca datos reales.
@Suite("Revisión F2 · cálculos y datos del núcleo", .serialized)
struct RevisionF2CalculosTests {
    typealias A = FinanzasApoyo

    // MARK: Conciliación con una foto vieja

    /// Dos clics seguidos en «Confirmar» (o dos ventanas): cada confirmación se prepara con la misma foto y las dos
    /// toman `PAG-20261017-001`. Antes, `guardarFila` actualizaba por `id` y la segunda **pisaba** el cobro de Talleres.
    /// Ahora la fila de `pagos.csv` se añade con `insertCSVRows`, que nunca pisa: la segunda no se escribe (todo o
    /// nada) y, preparada otra vez con la foto de después, toma `PAG-20261017-002`.
    @Test("Banco · dos cobros del mismo día confirmados con la misma foto: la segunda no pisa la primera en pagos.csv")
    func conciliacionesConFotoViejaPisanPagos() async throws {
        let env = A.ribera()
        defer { env.limpiar() }
        let emitidas = A.fin + "/Registros/emitidas.csv"
        let movimientos = A.corriente + "/movimientos.csv"
        let pagos = A.fin + "/Registros/pagos.csv"
        // Una segunda factura cobrada el mismo 17 de octubre (sintética).
        env.escribir(emitidas, try #require(env.texto(emitidas))
                     + "F-2026-0008,2026-10-16,Bar La Plaza SL,F-2026-0008,EUR,108.90,,Asesoría Ribera (DEMO),,,\n")
        env.escribir(movimientos, try #require(env.texto(movimientos))
                     + A.mov("MOV-revision0001", "2026-10-17", "TRANSFERENCIA DE BAR LA PLAZA F-2026-0008", "108.90"))
        let bus = try await env.bus()
        let c = Conciliador(snapshot: env.foto(), reloj: A.relojRibera)
        let talleres = try #require(c.propuestas.first { $0.factura.id == "F-2026-0007" })
        let bar = try #require(c.propuestas.first { $0.factura.id == "F-2026-0008" })
        let primera = try c.confirmar(talleres, autor: A.manu)
        let segunda = try c.confirmar(bar, autor: A.manu)
        // Las dos se numeran con la misma foto: el mismo PAG.
        #expect(primera.pagos.map(\.id) == ["PAG-20261017-001"])
        #expect(segunda.pagos.map(\.id) == ["PAG-20261017-001"])
        #expect(try await bus.ejecutar(primera.plan).hecho)
        await #expect(throws: WriteError.filaYaExiste("PAG-20261017-001")) { _ = try await bus.ejecutar(segunda.plan) }
        let filas = A.filas(env, pagos).filter { ($0["id"] ?? "").hasPrefix("PAG-20261017-") }
        let registros = RegistrosFinanzas(snapshot: env.foto())
        let f7 = try #require(registros.factura(id: "F-2026-0007"))
        let movTalleres = try #require(A.filas(env, movimientos).first { $0["id"] == "MOV-11e4d44973fd" })
        #expect(filas.count == 1)
        #expect(registros.pendiente(de: f7) == 0)
        #expect(filas.first { $0["id"] == movTalleres["pago_id"] }?["documento_id"] == "F-2026-0007")
        // La segunda no dejó nada a medias: su movimiento sigue abierto.
        #expect((A.filas(env, movimientos).first { $0["id"] == "MOV-revision0001" }?["pago_id"] ?? "") == "")
        // Preparada otra vez con la foto de después, toma el número siguiente y se escribe.
        let c2 = Conciliador(snapshot: env.foto(), reloj: A.relojRibera)
        let otra = try c2.confirmar(try #require(c2.propuestas.first { $0.factura.id == "F-2026-0008" }), autor: A.manu)
        #expect(otra.pagos.map(\.id) == ["PAG-20261017-002"])
        #expect(try await bus.ejecutar(otra.plan).hecho)
        #expect(A.filas(env, pagos).filter { ($0["id"] ?? "").hasPrefix("PAG-20261017-") }.count == 2)
    }

    // MARK: Importar dos veces con la misma vista previa

    /// Antes, con más de 50 filas nuevas el plan escribía una sola `anadirLinea` (sin clave): la misma vista previa
    /// importada dos veces (doble clic, dos ventanas) dejaba los 60 movimientos dos veces y un segundo original «(2)»
    /// en `Extractos/`. Ahora las filas van con `insertCSVRows`, que nunca repite un `id`: el segundo plan entero no se
    /// escribe (tampoco el original).
    @Test("Banco · la misma vista previa de 60 filas importada dos veces no duplica los movimientos ni el original")
    func importarDosVecesConVistaViejaDuplica() async throws {
        let cuentaMd = "4 · Finanzas/Registros/Bancos/caja/Cuenta.md"
        let movimientos = "4 · Finanzas/Registros/Bancos/caja/movimientos.csv"
        let env = A.empresa([
            cuentaMd: A.cuenta(id: "cta-rev", nombre: "Caja", saldoInicial: "1000.00", fecha: "2026-09-30"),
            movimientos: A.cabMovs,
        ])
        defer { env.limpiar() }
        let bus = try await env.bus()
        var extracto = "Fecha;Concepto;Importe\n"
        for i in 1...60 { extracto += "01/10/2026;COMPRA \(i);-1,00\n" }
        let imp = ImportadorExtracto(snapshot: env.foto(), reloj: relojDePrueba(2026, 10, 2))
        let cuenta = try #require(imp.registros.cuentas.first)
        let vista = try imp.vistaPrevia(Data(extracto.utf8), nombre: "octubre.csv", cuenta: cuenta)
        #expect(vista.resumen == "60 movimientos · 60 nuevos · 0 ya importados")
        // Primer clic.
        #expect(try await bus.ejecutar(try #require(vista.plan(autor: A.manu))).hecho)
        // Segundo clic con la vista que seguía en pantalla: no se escribe nada.
        let plan2 = try #require(vista.plan(autor: A.manu))
        await #expect(throws: WriteError.self) { _ = try await bus.ejecutar(plan2) }
        let ids = A.filas(env, movimientos).map { $0["id"] ?? "" }
        let originales = (try? FileManager.default.contentsOfDirectory(atPath: env.url("4 · Finanzas/Registros/Bancos/caja/Extractos").path)) ?? []
        #expect(ids.count == 60)
        #expect(Set(ids).count == ids.count)
        #expect(originales.count == 1)
    }

    // MARK: ENT-INC y el reloj

    /// Contrato de números: «todo es determinista y con reloj inyectable». ENT-INC tomaba la hora del reloj de pared
    /// (`Date()`); ahora la del `Reloj` que se pasa a `PanelMetricas.calcular` (`FotoMetricas.ahora`): una grave
    /// recibida el viernes 16/10 a las 12:00 vence el lunes 19/10 a las 12:00; a las 0:30 del 19 no está fuera de
    /// plazo y a las 23:30 sí.
    @Test("Números · ENT-INC usa el reloj inyectado: 0 a las 0:30 y 1 a las 23:30 del día del plazo")
    func entIncIgnoraElRelojInyectado() throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let carpeta = "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026"
        c.escribir(carpeta + "/Proyecto.md", """
            ---
            tls_type: project
            tls_schema: 1
            id: revision-proyecto-talleres
            nombre: Talleres Martín · Trimestrales 2026
            clase: entrega
            estado: En curso
            oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
            inicio: 2026-10-19
            ---
            # Talleres Martín · Trimestrales 2026

            """)
        c.escribir(carpeta + "/Incidencias.md", """
            ---
            tls_type: log
            tls_schema: 1
            id: revision-incidencias-talleres
            registro: incidencias
            ---
            # Incidencias

            | ID | Fecha | Quién reporta | Email | Tipo | Severidad | Estado | Descripción | Responsable | Resolución |
            |---|---|---|---|---|---|---|---|---|---|
            | INC-001 | 2026-10-16 12:00 | Jorge Martín |  | Accesos | Grave | Recibida | No puede entrar. | Manu |  |

            """)
        let madrid = MetricasApoyo.madrid
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        func reloj(_ h: Int, _ m: Int) -> Reloj {
            Reloj(hoy: MetricasApoyo.dia("2026-10-19"),
                  ahora: cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: h, minute: m))!, zona: madrid)
        }
        let temprano = PanelMetricas.calcular(snapshot: c.foto(), reloj: reloj(0, 30)).evaluador.evaluar("ENT-INC")
        let tarde = PanelMetricas.calcular(snapshot: c.foto(), reloj: reloj(23, 30)).evaluador.evaluar("ENT-INC")
        // La cuenta atrás, con su hora, sí lo distingue.
        let registro = try #require(FotoMetricas(snapshot: c.foto(), hoy: MetricasApoyo.dia("2026-10-19")).incidencias.first)
        #expect(registro.fueraDePlazo(ahora: reloj(0, 30).ahora, zona: madrid).isEmpty)
        #expect(registro.fueraDePlazo(ahora: reloj(23, 30).ahora, zona: madrid).count == 1)
        #expect(temprano.medida == .cifra(0))
        #expect(tarde.medida == .cifra(1))
    }

    // MARK: VEN-WON a mano con Ribera

    /// VEN-WON («Ventas cobradas del mes», «Σ valor de oportunidades ganadas (cobro confirmado) en el mes») sumaba el
    /// `valor` de las Ganadas por su `cerrada`. En Ribera las seis Ganadas llevan `cerrada: 2026-10-19` (el día de la
    /// conversión), pero sus cobros confirmados en `pagos.csv` son del 6/05 al 18/09: a mano, lo cobrado en octubre
    /// por oportunidades ganadas es 0 €, no 660 €. Revisión final: cuenta el día del cobro confirmado
    /// (`FotoMetricas.Oportunidad.cobrada`); con VEN-07 es el mismo día que `cerrada`, así que en lo nuevo no cambia.
    @Test("Números · VEN-WON de octubre en Ribera cuenta el día del cobro confirmado: 0 €, no los 660 € de la conversión")
    func venWonCuentaCobrosDeOtrosMeses() throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let hoy = MetricasApoyo.dia("2026-10-19")
        let p = c.panel("2026-10-19")
        let won = try #require(p.kpis.first { $0.codigo == "VEN-WON" })
        let lectura = LecturaDominio(snapshot: c.foto(), reloj: MetricasApoyo.reloj("2026-10-19"))
        let octubre = RangoFechas.mes(de: hoy, hasta: hoy)
        let ganadas = p.foto.oportunidades.filter { $0.estado == .ganada }
        #expect(ganadas.count == 6)
        var cobradoEnOctubre = 0.0
        for o in ganadas {
            let cobros = lectura.cobrosConfirmados(de: o.ruta)
            #expect(!cobros.isEmpty, "\(o.nombre) debería tener su cobro confirmado en pagos.csv")
            #expect(cobros.allSatisfy { ($0.fecha ?? hoy) < octubre.desde }, "\(o.nombre): \(cobros.map { $0.fecha?.description ?? "-" })")
            if cobros.contains(where: { $0.fecha.map(octubre.contiene) ?? false }) { cobradoEnOctubre += o.valor ?? 0 }
        }
        #expect(won.medida == .cifra(cobradoEnOctubre))
        #expect(won.medida == .cifra(0))
        // Cada Ganada sabe el día de su cobro.
        #expect(ganadas.allSatisfy { $0.cobrada.map { $0 < octubre.desde } ?? false })
    }

    // MARK: Decisiones.md: solo se añade

    /// Comprobación que pasa (no es un fallo): con BOM y saltos CRLF, registrar y sustituir una decisión solo añade la
    /// línea nueva y « (sustituida)»; el resto de los bytes es el mismo.
    @Test("Decisiones.md con BOM y CRLF: añadir y sustituir no cambian ningún otro byte")
    func decisionesConBOMyCRLF() async throws {
        let env = A.ribera()
        defer { env.limpiar() }
        let ruta = "1 · Dirección/Decisiones.md"
        let original = "\u{FEFF}" + (try #require(env.texto(ruta))).replacingOccurrences(of: "\n", with: "\r\n")
        env.escribir(ruta, original)
        let bus = try await env.bus()
        let hoy = MetricasApoyo.dia("2026-10-19")
        let (plan, id) = try RegistroDecisiones.anadir(NuevaDecision(fecha: hoy, decision: "Probar la revisión", porque: "Ver bytes",
                                                                     area: "Dirección"), en: env.foto(), autor: A.manu)
        #expect(try await bus.ejecutar(plan).hecho)
        let tras = String(decoding: try Data(contentsOf: env.url(ruta)), as: UTF8.self)
        let lineas = tras.components(separatedBy: "\r\n")
        let nueva = try #require(lineas.first { $0.contains(id) })
        #expect(lineas.filter { $0 != nueva }.joined(separator: "\r\n") == original)
        #expect(!tras.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        let vieja = "05803184-b15d-4a8f-99aa-58247c3c806e"
        let (plan2, id2) = try RegistroDecisiones.sustituir(vieja, por: NuevaDecision(fecha: hoy, decision: "Renta a 95 €"), en: env.foto(),
                                                            autor: A.manu)
        #expect(try await bus.ejecutar(plan2).hecho)
        let fin = String(decoding: try Data(contentsOf: env.url(ruta)), as: UTF8.self)
        let sinNueva = fin.components(separatedBy: "\r\n").filter { !$0.contains(id2) }.joined(separator: "\r\n")
        #expect(sinNueva.replacingOccurrences(of: " (sustituida)", with: "") == tras)
        #expect(fin.hasPrefix("\u{FEFF}"))
    }

    // MARK: Una sola caja

    /// «Una sola caja» (integración): `Tesoreria` y `KPIEvaluador` deben dar la misma caja. Con un día anterior a la
    /// fecha del saldo inicial (una ficha de cuenta nueva con su saldo de mañana, o mirar Ribera antes del 30/06),
    /// `Tesoreria` enseñaba el saldo inicial **del futuro** como saldo de hoy; ahora dice «Sin dato», como `KPIEvaluador`.
    @Test("Caja · antes de la fecha del saldo inicial: Tesoreria y KPIEvaluador dicen «Sin dato»")
    func cajaAntesDelSaldoInicial() throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let reloj = MetricasApoyo.reloj("2026-06-15")
        let t = Tesoreria(snapshot: c.foto(), reloj: reloj)
        let k = c.panel("2026-06-15").evaluador.evaluar("FIN-CASH")
        #expect(k.medida.numero == nil)
        #expect(t.saldo.total == nil)
        #expect(t.saldo.cuentas.allSatisfy { ($0.fecha ?? reloj.hoy) <= reloj.hoy })
    }
}
