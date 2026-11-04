import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// Rutinas, disparadores y el host (PLAN §5.3 «Disparadores», §9 F4 criterios 7 y 10).
@Suite("Motor · rutinas, disparos y host", .serialized)
struct DisparosTests {
    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    static func fecha(_ d: Int, _ h: Int, _ m: Int = 0, mes: Int = 10) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = mes; c.day = d; c.hour = h; c.minute = m
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        return cal.date(from: c)!
    }

    // MARK: Planificador

    @Test("config.yaml: rutinas, topes, interruptor y pausa")
    func leerAjustes() throws {
        let texto = EntornoMotor.configBase.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado")
            .replacingOccurrences(of: "pausa_areas: []", with: "pausa_areas: [ventas]")
        let a = AjustesDeAsistentes.leer(yaml: texto)
        #expect(!a.interruptor)
        #expect(a.pausaAreas == [.ventas])
        let mika = try #require(a.agente("mika"))
        #expect(mika.activo && mika.coordinador && mika.areas == [.direccion] && mika.leeAreas.count == 6)
        #expect(mika.modelo == "haiku" && mika.esfuerzo == "low")
        let r = try #require(mika.rutina("algo-rojo"))
        #expect(r.hora == 8 && r.minuto == 45 && r.dias == DiaSemana.laborables && r.ventanaPerdidaH == 6 && r.soloSiHayRojo)
        let mensual = AjustesDeAsistentes.leer(yaml: """
            agentes:
              contable:
                activo: si
                rutinas:
                  - {id: cobros, dia_mes: 5, hora: "09:00"}
                  - {id: gestoria, dia_mes: 1, meses: [1, 4, 7, 10], hora: 9}
            """).agente("contable")
        #expect(mensual?.rutinas.map(\.diaDelMes) == [5, 1])
        #expect(mensual?.rutinas.last?.meses == [1, 4, 7, 10])
        #expect(AjustesDeAsistentes.leer(yaml: "no: [es: yaml").agentes.isEmpty)
    }

    @Test("De las perdidas solo cuenta la última dentro de su ventana")
    func perdidas() {
        let p = RoutineScheduler(zona: Self.madrid)
        let r = TLSAgents.RutinaDeAsistente(id: "algo-rojo", hora: 8, minuto: 45, ventanaPerdidaH: 6)
        // Lunes 19 a las 9:00: el de hoy.
        #expect(p.ultimoHueco(r, ahora: Self.fecha(19, 9)) == Self.fecha(19, 8, 45))
        // El Mac durmió del sábado al miércoles a las 10:00: solo el del miércoles.
        #expect(p.ultimoHueco(r, ahora: Self.fecha(21, 10)) == Self.fecha(21, 8, 45))
        // Miércoles a las 15:00: ya pasó la ventana de 6 h: ninguno.
        #expect(p.ultimoHueco(r, ahora: Self.fecha(21, 15)) == nil)
        // Antes de la hora: el de ayer ya está fuera de ventana.
        #expect(p.ultimoHueco(r, ahora: Self.fecha(21, 8)) == nil)
        // Sábado: no toca.
        #expect(p.ultimoHueco(r, ahora: Self.fecha(24, 9)) == nil)
        #expect(p.siguienteHueco(r, despues: Self.fecha(23, 9)) == Self.fecha(26, 8, 45))
        let mensual = TLSAgents.RutinaDeAsistente(id: "cobros", diaDelMes: 5, hora: 9, ventanaPerdidaH: 24)
        #expect(p.ultimoHueco(mensual, ahora: Self.fecha(5, 18, mes: 11)) == Self.fecha(5, 9, mes: 11))
        #expect(p.siguienteHueco(mensual, despues: Self.fecha(19, 9)) == Self.fecha(5, 9, mes: 11))
    }

    @Test("Dos disparos del mismo hueco dan una ejecución (criterio 7)")
    func mismoHueco() async throws {
        let e = EntornoMotor(inicio: Self.fecha(19, 8, 50))
        defer { e.limpiar() }
        let host = try e.host(leerEventos: false)
        let a = await host.revisar()
        e.reloj.avanzar(5 * 60)
        let b = await host.revisar()
        #expect(a.filter { $0.disparo.tipo == .rutina }.count == 1)
        #expect(b.filter { $0.disparo.tipo == .rutina }.isEmpty)
        let rutinas = try e.estado().ejecuciones().filter { $0.disparo.tipo == .rutina }
        #expect(rutinas.count == 1)
        #expect(rutinas.first?.disparo.clave == "rutina:mika.algo-rojo:2026-10-19T08:45")
        // El repaso del embudo del lunes a las 10:00 aún no tocaba.
        #expect(rutinas.first?.agente == "mika")
    }

    @Test("Con el interruptor apagado no dispara rutinas; al encenderlo cuenta la última dentro de su ventana")
    func rutinasConInterruptor() async throws {
        let e = EntornoMotor(inicio: Self.fecha(19, 8, 50))
        defer { e.limpiar() }
        e.ajustes.interruptor = false
        let host = try e.host(leerEventos: false)
        #expect(await host.revisar().filter { $0.disparo.tipo == .rutina }.isEmpty)
        e.reloj.fijar(Self.fecha(19, 12))
        e.ajustes.interruptor = true
        let r = await host.revisar().filter { $0.disparo.tipo == .rutina }
        #expect(Set(r.map(\.disparo.clave)) == ["rutina:mika.algo-rojo:2026-10-19T08:45", "rutina:comercial.pipeline:2026-10-19T10:00"])
    }

    @Test("Autopausa: 5 ejecuciones en 7 días con ≥90 % de fallos pausan la rutina hasta reanudarla")
    func autopausa() async throws {
        let e = EntornoMotor(inicio: Self.fecha(19, 8, 50))
        defer { e.limpiar() }
        // Una simulación sin grabación falla siempre (y ese fallo no se reintenta).
        let vacio = Apoyo.tempDir("tls-sin-grabaciones")
        defer { Apoyo.limpiar(vacio) }
        let host = try e.host(runtime: SimulatedRuntime(grabaciones: vacio), leerEventos: false)
        var a = e.ajustes
        a.agentes["mika"]?.rutinas = [TLSAgents.RutinaDeAsistente(id: "algo-rojo", nombre: "¿Algo rojo?", dias: Set(DiaSemana.allCases),
                                                                hora: 8, minuto: 45, ventanaPerdidaH: 6)]
        e.ajustes = a
        for dia in 0..<5 {
            e.reloj.fijar(Self.fecha(19 + dia, 8, 50))
            await host.revisar()
            await host.cola.procesar()
        }
        let pausadas = await host.rutinasPausadas()
        #expect(pausadas.map(\.rutina) == ["mika.algo-rojo"])
        #expect(e.avisos.lista.contains { if case .rutinaPausada = $0 { true } else { false } })
        e.reloj.fijar(Self.fecha(24, 8, 50))
        #expect(await host.revisar().filter { $0.disparo.tipo == .rutina }.isEmpty)
        try await host.reanudarRutina("mika.algo-rojo")
        #expect(await host.revisar().filter { $0.disparo.tipo == .rutina }.count == 1)
    }

    // MARK: Tareas, menciones y despertares

    @Test("Tarea lista: dispara una vez; la Actividad que escribe el cierre no cambia su huella")
    func tareaLista() async throws {
        let e = EntornoMotor(inicio: Self.fecha(20, 16))
        defer { e.limpiar() }
        let host = try e.host(leerEventos: false)
        let t = e.tarea(1, titulo: "Llamar")
        e.tarea(2, titulo: "Sin programar", estado: "Sin programar")
        e.tarea(3, titulo: "De Manu", responsable: "Manu")
        e.tarea(4, titulo: "De Marca", area: .marca, responsable: "agente:marca")
        e.escribir("4 · Finanzas/Privado/Tareas/t-0005-secreta.md", "---\ntls_type: task\ntitulo: Secreta\nestado: Por hacer\nresponsable: agente:contable\n---\n# Secreta\n")
        let nuevas = await host.revisar()
        #expect(nuevas.map(\.disparo.tipo) == [.tarea])
        #expect(nuevas.first?.tarea == t)
        // Se añade una entrada de Actividad (como el cierre): misma huella, ningún disparo nuevo.
        let detector = DetectorDeDisparos(catalogo: EntornoMotor.catalogo)
        let reloj = Reloj(hoy: LocalDate(year: 2026, month: 10, day: 20)!, ahora: e.reloj.ahora(), zona: Self.madrid)
        let antes = detector.tareasListas(VaultSnapshot.read(root: e.raiz), reloj: reloj, ajustes: e.ajustes).map(\.clave)
        let texto = e.leer(t.raw) + "\n### 2026-10-19 12:00 · agente:comercial\nHecho.\n<!-- tls:evento {\"tipo\":\"ejecucion\"} -->\n"
        e.escribir(t.raw, texto)
        #expect(detector.tareasListas(VaultSnapshot.read(root: e.raiz), reloj: reloj, ajustes: e.ajustes).map(\.clave) == antes)
        #expect(await host.revisar().isEmpty)
        // Si Manu cambia la descripción, es otra versión de la tarea (pero sigue ocupada por su trabajo abierto).
        e.escribir(t.raw, e.leer(t.raw).replacingOccurrences(of: "Algo que hacer.", with: "Algo distinto que hacer."))
        #expect(detector.tareasListas(VaultSnapshot.read(root: e.raiz), reloj: reloj, ajustes: e.ajustes).map(\.clave) != antes)
        #expect(await host.revisar().isEmpty)
    }

    @Test("Menciones: solo comentarios humanos nuevos; la primera pasada apunta las de antes como vistas")
    func menciones() async throws {
        let e = EntornoMotor(inicio: Self.fecha(20, 16))
        defer { e.limpiar() }
        let vieja = """

            ### 2026-10-18 10:00 · Manu
            Mira esto @Comercial
            <!-- tls:evento {"id":"ev-1","tipo":"comentario","menciones":"agente:comercial"} -->

            """
        let t = e.tarea(1, titulo: "Revisar", responsable: "Manu", estado: "En curso", actividad: vieja)
        let host = try e.host(leerEventos: false)
        #expect(await host.revisar().isEmpty)
        // Comentario de un asistente con mención: no cuenta.
        e.escribir(t.raw, e.leer(t.raw) + "\n### 2026-10-19 11:00 · agente:mika\nAvisado @Comercial\n<!-- tls:evento {\"tipo\":\"comentario\"} -->\n")
        #expect(await host.revisar().isEmpty)
        // Comentario de Manu escrito en Obsidian, sin encabezado: sí.
        e.escribir(t.raw, e.leer(t.raw) + "\nOK, pero baja el alcance. @agente:comercial\n")
        let nuevas = await host.revisar()
        #expect(nuevas.count == 1)
        #expect(nuevas.first?.disparo.tipo == .mencion)
        #expect(nuevas.first?.agente == "comercial")
        #expect(nuevas.first?.disparo.datos["comentario"]?.contains("baja el alcance") == true)
        #expect(await host.revisar().isEmpty)
    }

    @Test("Comentarios de la Actividad: humanos, de asistentes y escritos en Obsidian")
    func comentarios() {
        let texto = """
            # T
            ## Actividad
            <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

            ### 2026-10-21 10:32 · agente:comercial
            Estado: Por hacer → En revisión.
            <!-- tls:evento {"tipo":"ejecucion"} -->

            ### 2026-10-21 11:02 · Manu
            OK, pero baja el alcance de la fase 2. @agente:comercial
            <!-- tls:evento {"tipo":"comentario","menciones":"agente:comercial"} -->

            Y otra cosa escrita a mano.
            ## Otra sección
            nada
            """
        let c = DetectorDeDisparos.comentarios(texto)
        #expect(c.map(\.autor) == ["agente:comercial", "Manu", "Escrito en Obsidian"])
        #expect(c.map(\.esHumano) == [false, true, true])
        #expect(c[1].menciones == ["agente:comercial"])
        #expect(c[2].texto == "Y otra cosa escrita a mano.")
        let d = DetectorDeDisparos(catalogo: EntornoMotor.catalogo)
        #expect(d.menciones(en: "Hola @Comercial y @mika, y @desconocido") == ["comercial", "mika"])
    }

    @Test("Despertar: la tarea vuelve al asistente el día que toca, una vez")
    func despertar() async throws {
        let e = EntornoMotor(inicio: Self.fecha(19, 16))
        defer { e.limpiar() }
        let t = e.tarea(1, titulo: "Seguimiento", estado: "En revisión")
        e.escribir(t.raw, e.leer(t.raw).replacingOccurrences(of: "creada: 2026-10-15", with: "creada: 2026-10-15\ndespertar: 2026-10-20"))
        let host = try e.host(leerEventos: false)
        #expect(await host.revisar().isEmpty)
        e.reloj.fijar(Self.fecha(20, 16))
        let n = await host.revisar()
        #expect(n.map(\.disparo.clave) == ["despertar:00000000-0000-4000-8000-000000000001:2026-10-20"])
        #expect(await host.revisar().isEmpty)
    }

    @Test("Eventos del dominio: solo los posteriores a la primera pasada y para quien los atiende")
    func eventos() async throws {
        let e = EntornoMotor(inicio: Self.fecha(20, 16))
        defer { e.limpiar() }
        let dominio = try EstadoDominio(directory: e.estadoDir)
        defer { dominio.cerrar() }
        let antes = Date().addingTimeInterval(-60)
        try dominio.encolar(EventoDominio(tipo: .contactoCreado, entidad: "c-viejo", ruta: VaultPath("2 · Ventas/Contactos/Viejo.md"),
                                          autor: .persona("Manu")), ahora: antes)
        let host = try e.host()
        #expect(await host.revisar().isEmpty)
        try dominio.encolar(EventoDominio(tipo: .contactoCreado, entidad: "c-nuevo", ruta: VaultPath("2 · Ventas/Contactos/Nuevo.md"),
                                          carga: ["nombre": "Contacto Nuevo"], autor: .persona("Manu")), ahora: Date().addingTimeInterval(1))
        try dominio.encolar(EventoDominio(tipo: .proyectoCerrado, entidad: "p-1", ruta: VaultPath("3 · Entrega/Proyectos/x/Proyecto.md"),
                                          autor: .persona("Manu")), ahora: Date().addingTimeInterval(2))
        let n = await host.revisar()
        #expect(n.count == 1)
        #expect(n.first?.agente == "comercial")
        #expect(n.first?.disparo.clave.hasPrefix("evento:contacto.creado:c-nuevo:") == true)
        #expect(n.first?.disparo.instruccion == "Prepara el diagnóstico del contacto nuevo.")
        #expect(await host.revisar().isEmpty)
    }

    @Test("El host no lanza a nadie de un área preparada o en reposo (criterio 10)")
    func hostAreaEnReposo() async throws {
        let e = EntornoMotor(inicio: Self.fecha(20, 16))
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        e.tarea(1, titulo: "Pieza", area: .marca, responsable: "agente:marca")
        e.tarea(2, titulo: "Kit", area: .entrega, responsable: "agente:implementador")
        let host = try e.host(leerEventos: false)
        #expect(await host.revisar().isEmpty)
        await host.cola.procesar()
        #expect(e.claude.llamadas == 0)
        #expect(try await host.pedir(a: "marca", instruccion: "Genera un borrador de pieza") == nil)
        // Al activar el área, su tarea sale.
        e.escribir("5 · Marca/Área.md", "# Marca\n\n**Estado:** activa · **La lleva:** Manu\n")
        #expect(await host.revisar().map(\.agente) == ["marca"])
    }

    @Test("¿Algo rojo?: sin rojo no se lanza a Mika y queda la línea «Revisé a las 8:45: nada en rojo»")
    func algoRojoSinRojo() async throws {
        let e = EntornoMotor(inicio: Self.fecha(19, 8, 50))
        defer { e.limpiar() }
        let host = try e.host(leerEventos: false)
        await host.revisar()
        await host.cola.procesar()
        #expect(e.claude.llamadas == 0)
        let r = try #require(await host.ultimaRevision("mika.algo-rojo"))
        #expect(r.resumen == "Revisé a las 8:45: nada en rojo.")
        #expect(e.registro.cierres.isEmpty)
    }

    @Test("¿Algo rojo?: con rojo se lanza a Mika con lo rojo como dato")
    func algoRojoConRojo() async throws {
        let e = EntornoMotor(inicio: Self.fecha(19, 8, 50))
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito("Te dejé una tarjeta 1-3-1."))
        // Una tarea vencida es una regla dura rota (CHQ-2).
        let t = e.tarea(1, titulo: "Vencida", responsable: "Manu")
        e.escribir(t.raw, e.leer(t.raw).replacingOccurrences(of: "creada: 2026-10-15", with: "creada: 2026-10-01\nvence: 2026-10-10"))
        let host = try e.host(leerEventos: false)
        await host.revisar()
        await host.cola.procesar()
        #expect(e.claude.llamadas == 1)
        let stdin = e.claude.texto("stdin-1.txt")
        #expect(stdin.contains("en_rojo:"))
        #expect(stdin.contains("<<<DATOS"))
    }
}
