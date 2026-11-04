import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Revisión adversarial de cálculos y datos de F2 (caminos de la interfaz). Cada prueba reprodujo un fallo encontrado
/// en la revisión; desde la revisión final están arreglados y las pruebas quedan como regresión. Ribera copiada a un
/// temporal (nunca el ejemplo del repositorio) con una sesión con escritura y el dominio conectado, como en la integración.
@Suite("Revisión F2 · datos por los caminos de la interfaz", .serialized)
@MainActor
struct RevisionF2DatosTests {
    typealias A = ApoyoAreasB
    let apoyo = ApoyoAreasB()

    static let opoJorge = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
    static let facturaTalleres = "4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md"

    func base(_ id: String, _ sesion: VaultSession, nav: Navegacion = Navegacion(raiz: .todasLasBases)) async throws -> BaseModelo {
        let c = try #require(CatalogoBases.coleccion(id))
        let m = BaseModelo(coleccion: c, sesion: sesion, destino: .base(id), contexto: nil, vista: nil)
        m.nav = nav
        await m.cargar()
        return m
    }

    func riberaTexto(_ ruta: String) throws -> String {
        try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(ruta), encoding: .utf8)
    }

    // MARK: VEN-07 por las bases

    /// La ficha de una factura no deja elegir «Cobrada» a mano («La emisión y el cobro se confirman con su acción»);
    /// la celda Estado de la base Facturas (y su tablero) lo dejaba. Ahora tampoco: el estado de una factura no se elige
    /// a mano en la base (`EdicionCelda.motivoSoloLectura`).
    @Test("VEN-07 · la base Facturas no deja poner «Cobrada» a mano, como su ficha")
    func facturaCobradaAMano() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let facturas = try await base("facturas", sesion)
        let f7 = try #require(facturas.datos?.filas.first { $0.ruta.raw == Self.facturaTalleres })
        let estado = try #require(facturas.coleccion.columna("estado"))
        let antes = apoyo.texto(e, Self.facturaTalleres)
        let error = await facturas.guardar(f7, estado, texto: "Cobrada")
        #expect(error != nil)
        #expect(apoyo.texto(e, Self.facturaTalleres) == antes)
    }

    /// `ReglaGanada` (lo que mira la base Oportunidades antes de soltar en Ganada) aceptaba una factura que solo dice
    /// «Cobrada», y `escribirYAtender` no miraba VEN-07. Ahora `ReglaGanada` cuenta solo lo que confirmó una persona
    /// (como `LecturaDominio.tieneCobroConfirmado`) y el motor bloquea Ganada sin cobro también por este camino.
    @Test("VEN-07 · con su factura en «Cobrada» (escrita a mano), el tablero de Oportunidades no la pasa a Ganada")
    func ganadaPorLaBaseSinCobro() async throws {
        let cobrada = try riberaTexto(Self.facturaTalleres).replacingOccurrences(of: "estado: Emitida", with: "estado: Cobrada")
        let (e, sesion) = try await apoyo.abrir(preparar: [Self.facturaTalleres: cobrada])
        defer { sesion.close(); e.limpiar() }
        // El dominio no lo deja: no hay ningún cobro confirmado de F-2026-0007 en pagos.csv ni recibo.
        let foto = VaultSnapshot.read(root: e.carpeta)
        let lectura = LecturaDominio(snapshot: foto)
        #expect(!lectura.tieneCobroConfirmado(Self.opoJorge))
        let inv = Invariantes(lectura: lectura).comprobar(.propiedades(Self.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []),
                                                         autor: sesion.autor)
        #expect(!inv.puedeGuardar)
        #expect(inv.bloqueos.first?.codigo == "VEN-07")

        let ops = try await base("oportunidades", sesion)
        let jorge = try #require(ops.datos?.filas.first { $0.ruta == Self.opoJorge })
        let antes = apoyo.texto(e, Self.opoJorge.raw)
        await ops.mover(jorge, a: "Ganada")
        #expect(ops.bloqueo?.fila == jorge.id)
        #expect(apoyo.texto(e, Self.opoJorge.raw) == antes)
        // Aunque una pantalla no lo mirara, el motor no lo escribe (VEN-07 también en `escribirYAtender`).
        await #expect(throws: DominioError.self) {
            try await sesion.escribir(.cambiarPropiedades(Self.opoJorge, poner: [Property(key: "estado", value: .text("Ganada"))], quitar: []))
        }
        #expect(apoyo.texto(e, Self.opoJorge.raw) == antes)
    }

    // MARK: ENT-04 por las bases

    /// ENT-04: lo planificado en sábado o domingo pasa al lunes. La celda «Planificada» de la base Tareas (y la de
    /// inicio/fin de Proyectos, «Fecha del siguiente paso» de Oportunidades y las propiedades de la ficha de F1) escribe
    /// por `sesion.escribir`; desde la revisión final, `escribirYAtender` corrige esas fechas leyendo solo la ficha.
    @Test("ENT-04 · la celda «Planificada» de la base Tareas corre el sábado al lunes")
    func planificadaEnSabadoPorLaBase() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let tareas = try await base("tareas", sesion)
        let t1 = try #require(tareas.datos?.filas.first { $0.ruta.raw == HoyApoyo.t1 })
        let col = try #require(tareas.coleccion.columna("planificada"))
        #expect(await tareas.guardar(t1, col, texto: "2026-10-24") == nil)   // sábado
        let texto = try #require(apoyo.texto(e, HoyApoyo.t1))
        // Lo que haría el dominio con el mismo cambio.
        let inv = Invariantes(snapshot: VaultSnapshot.read(root: e.carpeta))
            .comprobar(.propiedades(VaultPath(HoyApoyo.t1), poner: [Property(key: "planificada", value: .text("2026-10-24"))], quitar: []))
        #expect(inv.ajustes.map(\.propiedad.value) == [.text("2026-10-26")])
        #expect(texto.contains("planificada: 2026-10-26"))
        #expect(!texto.contains("planificada: 2026-10-24"))
    }

    // MARK: ENT-ONTIME y el tablero

    /// Criterio F2-2: el tablero cambia solo `estado` (sin `cerrada`). ENT-ONTIME solo contaba las cerradas con
    /// `cerrada`; ahora, si falta, toma el día de la entrada de Actividad que la cerró. Aquí, dos tareas de Entrega
    /// cerradas el 19/10 antes de vencer: una desde su ficha (`TaskStore.cambiarEstado`) y otra en el tablero.
    @Test("ENT-ONTIME · una tarea de Entrega cerrada en el tablero cuenta con el día de su Actividad")
    func entOntimeIgnoraLoCerradoEnElTablero() async throws {
        func tarea(_ n: Int, _ titulo: String) -> String {
            """
            ---
            tls_type: task
            tls_schema: 1
            id: revision-tarea-\(n)
            numero: T-000\(n)
            titulo: \(titulo)
            estado: En curso
            tipo: tarea
            vence: 2026-10-20
            creada: 2026-10-01
            ---
            # \(titulo)

            ## Descripción

            ## Actividad

            """
        }
        let ficha = "3 · Entrega/Tareas/t-0005-preparar-el-kit-de-la-sesion.md"
        let tablero = "3 · Entrega/Tareas/t-0006-revisar-los-extractos.md"
        let (e, sesion) = try await apoyo.abrir(preparar: [ficha: tarea(5, "Preparar el kit de la sesión"),
                                                          tablero: tarea(6, "Revisar los extractos")])
        defer { sesion.close(); e.limpiar() }
        // Desde la ficha (como «Marcar como hecha»): `estado` y `cerrada`.
        let foto = VaultSnapshot.read(root: e.carpeta)
        let store = TaskStore(snapshot: foto, reloj: Reloj(hoy: ApoyoAreasA.hoy))
        let t5 = try #require(store.tarea(VaultPath(ficha)))
        _ = try await sesion.escribir(plan: try store.cambiarEstado(t5, a: .hecha, autor: sesion.autor, persona: "Manu"))
        // En el tablero de Tareas (arrastrar o ⌘→): solo `estado` y su entrada de Actividad.
        let modelo = ModeloTareas(sesion: sesion)
        modelo.consulta.vista = .tablero
        await modelo.cargar()
        #expect(await modelo.mover(VaultPath(tablero), a: .hecha))
        let texto6 = try #require(apoyo.texto(e, tablero))
        #expect(texto6.contains("estado: Hecha") && !texto6.contains("cerrada:"))
        let metricas = FotoMetricas(snapshot: VaultSnapshot.read(root: e.carpeta), hoy: ApoyoAreasA.hoy)
        let ontime = KPIEvaluador(foto: metricas, metas: nil).evaluar("ENT-ONTIME")
        #expect(ontime.fuente == "Sale de 2 tareas cerradas")
    }

    // MARK: Dobles clics en Finanzas

    /// `ModeloFinanzas.importar` no se protegía de dos llamadas a la vez y el plan era una `anadirLinea`: dos clics
    /// seguidos dejaban cada movimiento dos veces. Ahora las escrituras van en cola (`trabajando` desde el clic) y la
    /// segunda ya no tiene vista previa; además `insertCSVRows` nunca repite un `id`.
    @Test("Banco · dos clics seguidos en «Importar» con 60 movimientos nuevos los escriben una sola vez")
    func importarConDobleClic() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion, cuenta: VaultPath(A.corriente))
        await modelo.cargar()
        var extracto = "fecha;fecha_valor;concepto;importe;saldo\n"
        var saldo = 1_966_465
        for i in 1...60 {
            saldo -= 100
            extracto += "18/10/2026;18/10/2026;COMPRA CON TARJETA \(i);-1,00;\(saldo / 100),\(String(format: "%02d", saldo % 100))\n"
        }
        await modelo.previsualizar(datos: Data(extracto.utf8), nombre: "tarjeta-octubre.csv")
        #expect(modelo.vista?.resumen == "60 movimientos · 60 nuevos · 0 ya importados")
        async let uno = modelo.importar(deshacer: nil)
        async let dos = modelo.importar(deshacer: nil)
        _ = await (uno, dos)
        let ids = CSVTable.parse(apoyo.texto(e, A.corriente + "/movimientos.csv") ?? "").rows.map { $0.first ?? "" }
        #expect(ids.count == 29 + 60)
        #expect(Set(ids).count == ids.count)
    }

    /// Dos «Confirmar» seguidos (dos propuestas del mismo día): antes se preparaban con la misma foto y la segunda
    /// pisaba en `pagos.csv` el cobro de la primera. Ahora la segunda espera a la primera y se prepara con la foto de
    /// después: `PAG-20261017-001` y `PAG-20261017-002`.
    @Test("Banco · dos «Confirmar» seguidos de cobros del mismo día: dos filas PAG, ninguna pisada")
    func confirmarConDobleClic() async throws {
        let emitidas = try riberaTexto(A.emitidas)
            + "F-2026-0008,2026-10-16,Bar La Plaza SL,F-2026-0008,EUR,108.90,,Asesoría Ribera (DEMO),,,\n"
        let movs = try riberaTexto(A.corriente + "/movimientos.csv")
            + "MOV-revision0001,2026-10-17,2026-10-17,TRANSFERENCIA DE BAR LA PLAZA F-2026-0008,108.90,,ingreso,,,,,pendiente,,,,\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [A.emitidas: emitidas, A.corriente + "/movimientos.csv": movs])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let ps = modelo.lectura?.propuestas ?? []
        let talleres = try #require(ps.first { $0.factura.id == "F-2026-0007" })
        let bar = try #require(ps.first { $0.factura.id == "F-2026-0008" })
        async let uno = modelo.confirmar(talleres, deshacer: nil)
        async let dos = modelo.confirmar(bar, deshacer: nil)
        _ = await (uno, dos)
        let filas = CSVTable.parse(apoyo.texto(e, A.pagos) ?? "").rows.filter { ($0.first ?? "").hasPrefix("PAG-20261017-") }
        #expect(filas.count == 2)
    }
}
