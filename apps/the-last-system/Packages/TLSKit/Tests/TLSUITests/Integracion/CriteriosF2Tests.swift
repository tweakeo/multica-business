import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Integración de F2: los 8 criterios de aceptación de PLAN §9 F2, uno por prueba, con Asesoría Ribera copiada a una
/// carpeta temporal y una sesión con escritura **con el dominio conectado** (cada plan de la persona deja sus eventos y
/// las reglas los atienden como sistema), y el escenario «una semana en la copia» hasta donde llega F2.
/// Las pruebas de cada rol miran el detalle; estas miran que todo junto funciona igual. Nunca se toca el ejemplo del
/// repositorio; lo privado usa nombres neutros.
@Suite("Integración F2 · los 8 criterios de PLAN §9 y una semana en la copia", .serialized)
@MainActor
struct CriteriosF2Tests {
    typealias A = ApoyoAreasB
    let apoyo = ApoyoAreasB()

    static let opoJorge = "2 · Ventas/Oportunidades/jorge-martin-trimestrales.md"
    static let proyectosEntrega = "3 · Entrega/Proyectos/"

    /// Fichas de proyecto vivas (fuera de `Archivo/`).
    func proyectos(_ e: SesionEscrituraTests.Entorno) -> [String] {
        apoyo.huella(e.carpeta).filter { k, v in
            !k.hasPrefix("Archivo/") && String(decoding: v, as: UTF8.self).contains("tls_type: project")
        }.keys.sorted()
    }

    /// La huella sin lo que el Deshacer manda al Archivo (nunca se borra: lo creado se retira allí).
    func fueraDelArchivo(_ h: [String: Data]) -> [String: Data] { h.filter { !$0.key.hasPrefix("Archivo/") } }

    // MARK: F2-1

    @Test("F2-1 · ⌘N, título y ⏎ crean …/Tareas/t-NNNN-slug.md con el orden de §4.2 y solo cambia además secuencias.json")
    func criterio1() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        // Con escritor, la sesión tiene su motor del dominio (eventos y reglas tras cada plan de la persona).
        #expect(DominioEmpresa.motor(de: sesion) != nil)
        let antes = apoyo.huella(e.carpeta)
        let ruta = try await NuevaTareaHoja.crear(titulo: "Revisar cobros de octubre", area: .finanzas, proyecto: nil,
                                                  responsable: "Manu", planificada: nil, sesion: sesion)
        #expect(ruta.raw == "4 · Finanzas/Tareas/t-0003-revisar-cobros-de-octubre.md")
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [".tls/secuencias.json", ruta.raw])
        let texto = try #require(apoyo.texto(e, ruta.raw))
        let claves = CriteriosF2TareasTests.claves(texto)
        let orden = ["tls_type", "tls_schema", "id", "numero", "titulo", "estado", "prioridad", "tipo", "responsable", "planificada",
                     "vence", "estimacion_h", "dedicadas_h", "area", "proyecto", "oportunidad", "empresa", "padre", "bloqueada_por",
                     "capacidad", "despertar", "origen", "creada", "creada_por", "cerrada", "fecha_corte", "plantilla"]
        #expect(claves == orden.filter { claves.contains($0) }, "Orden escrito: \(claves)")
        #expect(Array(claves.prefix(6)) == ["tls_type", "tls_schema", "id", "numero", "titulo", "estado"])
        // Ninguna regla escribe por una tarea nueva: el plan de la persona es lo único.
        #expect(sesion.aviso?.accion != nil)
    }

    // MARK: F2-2

    @Test("F2-2 · ⌘→ en el tablero cambia solo `estado` (y su Actividad); un número repetido se renumera y se renombra")
    func criterio2() async throws {
        let repetida = "2 · Ventas/Tareas/t-0001-revisar-precios-de-la-competencia.md"
        let (e, sesion) = try await apoyo.abrir(preparar: [repetida: """
            ---
            tls_type: task
            tls_schema: 1
            id: 7c1d2e3f-0000-4000-8000-0000000000aa
            numero: T-0001
            titulo: Revisar precios de la competencia
            estado: Por hacer
            creada: 2026-10-20
            ---
            # Revisar precios de la competencia

            ## Descripción

            ## Actividad

            """])
        defer { sesion.close(); e.limpiar() }
        let ruta = VaultPath(HoyApoyo.t2)
        let antes = try #require(apoyo.texto(e, ruta.raw))
        let huella = apoyo.huella(e.carpeta)
        let modelo = ModeloTareas(sesion: sesion)
        modelo.consulta.vista = .tablero
        await modelo.cargar()
        modelo.elegida = ruta
        #expect(await modelo.moverAlLado(ruta, paso: 1))   // En revisión → Bloqueada
        #expect(apoyo.cambiados(huella, apoyo.huella(e.carpeta)) == [ruta.raw])
        let despues = try #require(apoyo.texto(e, ruta.raw))
        let fmAntes = antes.components(separatedBy: "\n---\n")[0], fmDespues = despues.components(separatedBy: "\n---\n")[0]
        #expect(ApoyoAreasA.lineasCambiadas(fmAntes, fmDespues) == ["estado: Bloqueada"])
        #expect(!despues.contains("cerrada:"))
        #expect(despues.contains("\"desde\":\"tablero\""))
        // El número repetido: la más nueva pasa a T-0003 y su fichero se renombra en la misma operación.
        #expect(modelo.revision.duplicados.count == 1)
        await modelo.renumerarRepetidas()
        #expect(apoyo.texto(e, "2 · Ventas/Tareas/t-0003-revisar-precios-de-la-competencia.md")?.contains("numero: T-0003") == true)
        #expect(apoyo.texto(e, repetida) == nil)
        #expect(apoyo.texto(e, HoyApoyo.t1) != nil)
    }

    // MARK: F2-3

    @Test("F2-3 · VEN-07: Ganada sin cobro se bloquea en castellano; confirmar la conciliación deja Ganada y 1 proyecto; repetir, 1; deshacer la cadena y volver a confirmar, 1")
    func criterio3() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let opo = VaultPath(Self.opoJorge)
        let antesOpo = try #require(apoyo.texto(e, opo.raw))

        // Soltar en Ganada en el CRM (lo que pregunta antes de escribir) y escribirlo igualmente por el dominio: bloqueado.
        let foto = VaultSnapshot.read(root: e.carpeta)
        let metricas = FotoMetricas(snapshot: foto, hoy: ApoyoAreasA.hoy)
        let tablero = TableroCRM.de(metricas.oportunidades, hoy: ApoyoAreasA.hoy)
        let tarjeta = try #require(tablero.tarjeta(opo))
        guard case .bloqueado(let mensaje, let alternativa) = TableroCRM.soltar(tarjeta, en: .ganada, invariantes: Invariantes(snapshot: foto),
                                                                              autor: sesion.autor) else {
            Issue.record("Soltar en Ganada sin cobro debía bloquearse")
            return
        }
        #expect(mensaje.hasPrefix("Ganada necesita un cobro confirmado por una persona."))
        #expect(alternativa?.titulo == "Dejarla en Aceptada")
        await #expect(throws: DominioError.self) {
            try await sesion.escribirConDominio(.cambiarPropiedades(opo, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []))
        }
        #expect(apoyo.texto(e, opo.raw) == antesOpo)
        #expect(sesion.aviso?.texto.hasPrefix("Ganada necesita un cobro confirmado por una persona.") == true)

        // La conciliación de la emitida pagada (F-2026-0007), con el clic: Ganada y un solo proyecto, con sus tareas.
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let antes = apoyo.huella(e.carpeta)
        let p = try #require(modelo.lectura?.propuestas.first { $0.factura.id == "F-2026-0007" })
        let um = A.undo()
        um.beginUndoGrouping()
        #expect(await modelo.confirmar(p, deshacer: um))
        um.endUndoGrouping()
        #expect(apoyo.texto(e, opo.raw)?.contains("estado: Ganada") == true)
        #expect(proyectos(e).count == 1)
        #expect(proyectos(e).first?.hasPrefix(Self.proyectosEntrega) == true)

        // Repetirlo (la misma propuesta) no escribe nada: sigue 1.
        let dos = apoyo.huella(e.carpeta)
        #expect(await modelo.confirmar(p, deshacer: nil) == false)
        #expect(apoyo.huella(e.carpeta) == dos)
        #expect(proyectos(e).count == 1)

        // Deshacer quita la cadena entera (lo de las reglas y luego el cobro): todo vuelve, lo creado va al Archivo.
        um.undo()
        await apoyo.esperar({ self.fueraDelArchivo(self.apoyo.huella(e.carpeta)) == self.fueraDelArchivo(antes) }, segundos: 15)
        #expect(fueraDelArchivo(apoyo.huella(e.carpeta)) == fueraDelArchivo(antes))
        #expect(proyectos(e).isEmpty)
        await apoyo.esperar { sesion.aviso?.texto == "Deshecho, también lo que hicieron las reglas" }
        #expect(sesion.aviso?.texto == "Deshecho, también lo que hicieron las reglas")

        // Y si se vuelve a confirmar, las reglas lo atienden otra vez: Ganada y 1 proyecto (no 0, no 2).
        await modelo.cargar(forzar: true)
        let p2 = try #require(modelo.lectura?.propuestas.first { $0.factura.id == "F-2026-0007" })
        #expect(await modelo.confirmar(p2, deshacer: nil))
        #expect(apoyo.texto(e, opo.raw)?.contains("estado: Ganada") == true)
        #expect(proyectos(e).count == 1)
    }

    // MARK: F2-4

    @Test("F2-4 · importar dos veces el extracto de Ribera da «0 nuevos»; los 30 import_hash coinciden; nada se confirma sin tu clic")
    func criterio4() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        // Los 30 movimientos de las dos cuentas: su huella sale igual que el `import_hash` escrito.
        let registros = RegistrosFinanzas(snapshot: VaultSnapshot.read(root: e.carpeta))
        #expect(registros.movimientos.count == 30)
        #expect(registros.movimientos.filter {
            ImportadorExtracto.huella(cuentaID: $0.cuentaID, fecha: $0.fecha, importe: $0.importe, concepto: $0.concepto, saldo: $0.saldo)
                == $0.importHash
        }.count == 30)

        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let original = try Data(contentsOf: e.carpeta.appendingPathComponent(A.extracto))
        let antes = apoyo.huella(e.carpeta)
        for _ in 0..<2 {
            await modelo.previsualizar(datos: original, nombre: "cuenta-corriente-2026-07-a-10.csv")
            #expect(modelo.vista?.resumen == "29 movimientos · 0 nuevos · 29 ya importados")
            #expect(await modelo.importar(deshacer: nil) == false)
        }
        // Abrir Hoy, el Banco y dejar que el motor termine lo pendiente no confirma nada.
        _ = await DominioEmpresa.motor(de: sesion)?.procesarPendientes()
        await AlmacenHoy.de(sesion).actualizar(forzar: true)
        #expect(AlmacenHoy.de(sesion).datos != nil)
        #expect(apoyo.huella(e.carpeta) == antes)
        #expect(modelo.lectura?.propuestas.isEmpty == false)
    }

    // MARK: F2-5

    @Test("F2-5 · Hoy: exactamente un foco; Alertas solo con algo en rojo (Ribera alternando); con los CSV vacíos, «Sin dato», nunca 0")
    func criterio5() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let d = c.hoy()
        #expect(d.secciones(hayQueRevisar: false).filter { $0 == .foco }.count == 1)
        #expect(d.hayRojo && d.secciones(hayQueRevisar: false).contains(.alertas))
        // Sin nada en rojo, la sección no existe; al volver los datos, vuelve.
        let metas = c.texto("1 · Dirección/Metas.md")
        try await HoyApoyo.quitarRojos(c)
        let sinRojo = c.hoy()
        #expect(sinRojo.alertas.isEmpty)
        #expect(!sinRojo.secciones(hayQueRevisar: false).contains(.alertas))
        #expect(sinRojo.secciones(hayQueRevisar: false).contains(.foco))
        c.escribir("1 · Dirección/Metas.md", metas)
        let otraVez = c.hoy()
        #expect(otraVez.secciones(hayQueRevisar: false).contains(.alertas))
        // Con los registros vacíos: «Sin dato…», nunca un 0 inventado.
        HoyApoyo.vaciarRegistros(c)
        let vacio = c.hoy()
        let cifras = HoyApoyo.cifras(vacio.modulos)
        #expect(!cifras.isEmpty)
        for t in cifras { #expect(t != "0" && t != "0 €" && t != "0,00 €", "Cifra inventada: «\(t)»") }
        #expect(vacio.modulos.caja.runwayTexto == nil)
        #expect(vacio.secciones(hayQueRevisar: false).filter { $0 == .foco }.count == 1)
    }

    // MARK: F2-6

    @Test("F2-6 · un proyecto en curso sin objetivo se guarda y queda en atención con «Colgar de un objetivo / Seguir sin objetivo»")
    func criterio6() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let ruta = VaultPath("6 · Equipo/Proyectos/manual-del-implementador/Proyecto.md")
        let r = try await sesion.escribirConDominio(.crear(ruta, texto: ApoyoAreasA.proyecto("Manual del implementador", clase: "interno",
                                                                                             estado: "En curso", extra: "inicio: 2026-10-05\n")))
        #expect(r.escritura.hecho)
        #expect(apoyo.texto(e, ruta.raw) != nil)
        let aviso = try #require(r.invariantes.atenciones.first { $0.codigo == "DIR-03" })
        #expect(aviso.alternativas.map(\.titulo) == ["Colgar de un objetivo", "Seguir sin objetivo"])
        // Queda en atención (también para el cronograma de Dirección) hasta que la persona elige.
        let inv = Invariantes(snapshot: VaultSnapshot.read(root: e.carpeta))
        #expect(inv.atenciones().contains { $0.codigo == "DIR-03" && $0.ruta == ruta })
        try await sesion.escribirConDominio(.cambiarPropiedades(ruta, poner: [Property(key: "sin_objetivo", value: .bool(true))], quitar: []))
        #expect(!Invariantes(snapshot: VaultSnapshot.read(root: e.carpeta)).atenciones().contains { $0.ruta == ruta })
    }

    // MARK: F2-7

    @Test("F2-7 · los 71 movimientos heredados quedan en preparación sin ninguna fila confirmada y sin disparar reglas")
    func criterio7() async throws {
        let (e, sesion) = try await apoyo.abrir(preparar: FinanzasOperacionTests.heredadosSinteticos())
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        #expect(modelo.lectura?.heredados?.resumen == "71 movimientos heredados · 71 nuevos · 0 ya cargados")
        let antes = apoyo.huella(e.carpeta)
        let confirmadas = FinanzasOperacionTests.confirmadas(apoyo.texto(e, A.pagos))
        #expect(await modelo.cargarHeredados(deshacer: nil))
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [A.emitidas, A.pagos, A.recibidas])
        #expect(FinanzasOperacionTests.confirmadas(apoyo.texto(e, A.pagos)) == confirmadas)
        // Ni una regla: todo lo que dejó la carga queda «omitido» en la bandeja de salida del dominio.
        let motor = try #require(DominioEmpresa.motor(de: sesion))
        let eventos = try motor.estado.eventos()
        #expect(eventos.allSatisfy { $0.estado != .pendiente })
        #expect(try motor.estado.reglasAplicadas().isEmpty)
    }

    // MARK: F2-8

    @Test("F2-8 · la vista del cliente del portal no tiene notas, responsable, resolución, correos ni kit; una grave cuenta 24 h hábiles")
    func criterio8() throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try ApoyoAreasA.preparar(carpeta)
        let madrid = ApoyoAreasA.madrid
        let portal = PortalDocumento.leer(try ApoyoAreasA.texto(ApoyoAreasA.portalTalleres, en: carpeta), ruta: ApoyoAreasA.portalTalleres)
        let incidencias = RegistroIncidencias.leer(try ApoyoAreasA.texto(ApoyoAreasA.incidenciasTalleres, en: carpeta),
                                                   ruta: ApoyoAreasA.incidenciasTalleres, zona: madrid)
        let cliente = PortalCliente(portal: portal, incidencias: incidencias.filas).textoCompleto
        for s in portal.sesiones { if let n = s.notaInterna { #expect(!cliente.contains(n)) } }
        #expect(!cliente.contains("@"))
        #expect(!cliente.contains("Manu"))
        for i in incidencias.filas { if let r = i.resolucion { #expect(!cliente.contains(r)) } }
        #expect(cliente.range(of: #"\bkits?\b"#, options: [.regularExpression, .caseInsensitive]) == nil)
        // La grave del viernes a las 10:00 vence el lunes a las 10:00: a las 9:00 queda 1 h hábil; a las 13:00, fuera.
        let grave = try #require(incidencias.filas.first { $0.id == "INC-001" })
        #expect(grave.cuentaAtras(ahora: ApoyoAreasA.instante(16, 10), zona: madrid)?.texto == "Quedan 24 h hábiles")
        #expect(grave.cuentaAtras(ahora: ApoyoAreasA.instante(19, 13), zona: madrid)?.fueraDePlazo == true)
        // Integración: ENT-INC ya sale de los registros de incidencias también en Control y Hoy (antes, «Sin dato»).
        let foto = ApoyoAreasA.foto(carpeta)
        let metricas = FotoMetricas(snapshot: foto, hoy: ApoyoAreasA.hoy)
        #expect(metricas.incidencias.count == 1)
        let entInc = KPIEvaluador(foto: metricas, metas: MetasDocumento.leer(foto)).evaluar("ENT-INC")
        #expect(entInc.medida.numero != nil)
        #expect(entInc.fuente == "Sale de 1 registro de incidencias")
    }

    // MARK: R1 (requisito adicional de F2)

    @Test("R1 · ⌘K encuentra el texto de dentro de los PDF ya descargados, nunca el de un PDF privado; la miniatura tampoco lo pinta")
    func textoDePDFyMiniaturas() async throws {
        let privado = "4 · Finanzas/Trámites/Expediente privado/recibo-reservado.pdf"
        let movil = "4 · Finanzas/Fiscal/2026/T3/Gastos/movil-levante/2026-07-10 Movil Levante ML-07-2026 78,65€.pdf"
        let config = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
            .replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Trámites/Expediente privado\"]")
        let datosPDF = try Data(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(movil))
        let (e, sesion) = try await apoyo.abrir(preparar: [".tls/config.yaml": config])
        defer { sesion.close(); e.limpiar() }
        // El PDF privado se copia con el mismo texto («Telefonía e internet»), antes de que la cola lo pudiera ver.
        let u = e.carpeta.appendingPathComponent(privado)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try datosPDF.write(to: u)
        var hits: [SearchHit] = []
        let fin = Date().addingTimeInterval(20)
        while Date() < fin {
            hits = await sesion.buscar("internet", limite: 20)
            if hits.contains(where: { $0.note.path.raw == movil }) { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        // «internet» solo está dentro de los PDF de Móvil Levante (ninguna nota lo dice).
        #expect(hits.contains { $0.note.path.raw == movil && $0.snippet.contains("‹") })
        #expect(hits.allSatisfy { $0.note.path.ext.lowercased() == "pdf" })
        #expect(!hits.contains { $0.note.path.raw == privado })
        #expect(sesion.destino(para: VaultPath(movil)) == .fichero(VaultPath(movil)))
        // Miniaturas: la del gasto sí; la del privado, nunca.
        #expect(MiniaturasEmpresa.sePuedeEnsenar(VaultPath(movil), sesion: sesion))
        #expect(!MiniaturasEmpresa.sePuedeEnsenar(VaultPath(privado), sesion: sesion))
        // El texto solo vive en el índice: la carpeta no gana ningún fichero.
        #expect(!apoyo.huella(e.carpeta).keys.contains { $0.hasSuffix(".txt") })
    }

    // MARK: Una semana en la copia

    @Test("Una semana en la copia: extracto → propuesta → cobro con tu clic → Ganada y 1 proyecto → tareas en laborables → Hoy cambia su foco → decisión registrada")
    func unaSemanaEnLaCopia() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let hoy = AlmacenHoy.de(sesion)
        await hoy.actualizar(forzar: true)
        let antes = try #require(hoy.datos)
        let focoAntes = antes.foco
        let pendientesAntes = antes.pendientes

        // 1. Importar el extracto con dos movimientos nuevos.
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let original = try Data(contentsOf: e.carpeta.appendingPathComponent(A.extracto))
        let nuevo = String(decoding: original, as: UTF8.self)
            + "19/10/2026;19/10/2026;RECIBO MODELO 111 AEAT;-120,00;19544,65\n"
            + "19/10/2026;19/10/2026;TRANSFERENCIA DE CLIENTE NUEVO;300,00;19844,65\n"
        await modelo.previsualizar(datos: Data(nuevo.utf8), nombre: "cuenta-corriente-hasta-19-oct.csv")
        #expect(modelo.vista?.resumen == "31 movimientos · 2 nuevos · 29 ya importados")
        let pagosAntes = apoyo.texto(e, A.pagos)
        #expect(await modelo.importar(deshacer: nil))
        #expect(apoyo.texto(e, A.pagos) == pagosAntes)   // importar no confirma nada

        // 2. La propuesta de conciliación del cobro de Jorge (sin el clic, nada).
        await modelo.cargar(forzar: true)
        let p = try #require(modelo.lectura?.propuestas.first { $0.factura.id == "F-2026-0007" })
        #expect(p.exacta)

        // 3. Confirmar el cobro (el clic): Ganada y un solo proyecto de entrega.
        #expect(await modelo.confirmar(p, deshacer: nil))
        #expect(apoyo.texto(e, Self.opoJorge)?.contains("estado: Ganada") == true)
        let lista = proyectos(e)
        #expect(lista.count == 1)
        let proyecto = try #require(lista.first)

        // 4. Las tareas de la plantilla del proyecto, todas en días laborables y numeradas seguidas.
        let carpetaTareas = (VaultPath(proyecto).parent ?? .root).appending("Tareas").raw + "/"
        let tareas = apoyo.huella(e.carpeta).keys.filter { $0.hasPrefix(carpetaTareas) }.sorted()
        #expect(!tareas.isEmpty)
        for t in tareas {
            let fm = NoteDocument(text: apoyo.texto(e, t) ?? "").frontmatter
            if let texto = fm.text("planificada"), let dia = LocalDate(parsing: texto) {
                #expect(dia.weekday >= 1 && dia.weekday <= 5, "\(t) cae en fin de semana: \(dia)")
            }
        }

        // 5. Hoy cambia: otro foco (o el mismo con otra cifra) y ya no hay cobros por confirmar.
        await hoy.actualizar(forzar: true)
        let despues = try #require(hoy.datos)
        #expect(despues.foco.id != focoAntes.id || despues.foco.quePasa != focoAntes.quePasa)
        #expect(despues.secciones(hayQueRevisar: false).filter { $0 == .foco }.count == 1)

        // 6. Decidir algo: una línea en Decisiones.md con su origen, y la tarea cerrada; la insignia baja.
        let tarjeta = try #require(despues.decisiones.first { $0.ruta?.raw == HoyApoyo.t1 })
        let registroAntes = apoyo.texto(e, HoyApoyo.registro) ?? ""
        #expect(await Decidir.decidir(tarjeta, opcion: nil, texto: "Subir Trimestrales a 165 € desde T1 2027",
                                      porque: "Clínica y Panadería valoran el trato", sesion: sesion))
        let registro = try #require(apoyo.texto(e, HoyApoyo.registro))
        let nuevas = registro.components(separatedBy: "\n").filter { !registroAntes.components(separatedBy: "\n").contains($0) }
        #expect(nuevas.count == 1)
        #expect(nuevas.first?.contains("Subir Trimestrales a 165 € desde T1 2027") == true)
        #expect(nuevas.first?.contains("(T-0001)") == true)
        #expect(apoyo.texto(e, HoyApoyo.t1)?.contains("estado: Hecha") == true)
        await hoy.actualizar(forzar: true)
        #expect((hoy.datos?.pendientes ?? 0) == pendientesAntes - 1)
    }
}
