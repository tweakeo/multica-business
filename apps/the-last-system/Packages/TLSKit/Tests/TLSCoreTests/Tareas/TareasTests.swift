import Foundation
import Testing
@testable import TLSCore

@Suite("Tareas: fichas")
struct TaskStoreTests {
    @Test func estadosConSusAlias() {
        #expect(EstadoTarea(leyendo: "Pendiente") == .porHacer)
        #expect(EstadoTarea(leyendo: "por revisar") == .enRevision)
        #expect(EstadoTarea(leyendo: "En progreso") == .enCurso)
        #expect(EstadoTarea(leyendo: "Bloqueado") == .bloqueada)
        #expect(EstadoTarea(leyendo: "Hecho") == .hecha)
        #expect(EstadoTarea(leyendo: "in_review") == .enRevision)
        #expect(EstadoTarea(leyendo: "En revision") == .enRevision)
        #expect(EstadoTarea(leyendo: "otra cosa") == nil)
        #expect(EstadoTarea.enRevision.multica == "in_review")
    }

    @Test func nombresDeFichero() {
        #expect(TareaArchivo.numero(deNombre: "t-0042-preparar.md") == 42)
        #expect(TareaArchivo.numero(deNombre: "t-12345-x.md") == 12345)
        #expect(TareaArchivo.numero(deNombre: "t-42-x.md") == nil)
        #expect(TareaArchivo.numero(deNombre: "Tareas.md") == nil)
        #expect(TareaArchivo.slug(deNombre: "t-0042-preparar-propuesta.md") == "preparar-propuesta")
        #expect(TareaArchivo.nombre(numero: 7, slug: String(repeating: "palabra-", count: 12)).count <= 63)
    }

    @Test func leeLasFichasDeLaFixture() {
        let store = TaskStore(snapshot: VaultSnapshot.read(root: Apoyo.empresaMinima), reloj: relojDePrueba())
        #expect(store.tareas.count == 1)
        let t = store.tareas[0]
        #expect(t.numero == "T-0001")
        #expect(t.estado == .porHacer)
        #expect(t.area == .entrega)
        #expect(t.proyectoPorRuta?.raw == "3 · Entrega/Proyectos/web-ferreteria/Proyecto.md")
        #expect(t.planificada?.description == "2026-10-27")
        #expect(!t.esListaParaAgente(hoy: relojDePrueba().hoy))
        #expect(store.siguienteNumero() == 2)
    }

    @Test func listaParaUnAsistente() {
        let hoy = LocalDate(year: 2026, month: 10, day: 22)!
        func tarea(_ r: String?, _ e: EstadoTarea, _ p: LocalDate?) -> Tarea {
            Tarea(ruta: VaultPath("x/Tareas/t-0001.md"), uid: nil, numero: nil, numeroEntero: 1, titulo: "x", estado: e, estadoTexto: e.rawValue,
                  prioridad: nil, tipo: nil, responsable: r, planificada: p, vence: nil, despertar: nil, area: nil, proyecto: nil,
                  proyectoPorRuta: nil, oportunidad: nil, empresa: nil, creada: nil, cerrada: nil, origen: nil)
        }
        #expect(tarea("agente:comercial", .porHacer, nil).esListaParaAgente(hoy: hoy))
        #expect(tarea("agente:comercial", .porHacer, hoy).esListaParaAgente(hoy: hoy))
        #expect(!tarea("agente:comercial", .porHacer, hoy.adding(days: 1)).esListaParaAgente(hoy: hoy))
        #expect(!tarea("agente:comercial", .sinProgramar, nil).esListaParaAgente(hoy: hoy))
        #expect(!tarea("Manu", .porHacer, nil).esListaParaAgente(hoy: hoy))
        #expect(Tarea.laborable(LocalDate(year: 2026, month: 10, day: 24)!).description == "2026-10-26")
    }

    @Test func crearEnUnProyecto() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let store = TaskStore(snapshot: env.foto(), reloj: relojDePrueba())
        let nota = try store.crear(NuevaTarea(titulo: "Revisar textos de la web", proyecto: VaultPath("3 · Entrega/Proyectos/web-ferreteria/Proyecto.md"),
                                              responsable: "agente:implementador", estado: .porHacer,
                                              planificada: LocalDate(year: 2026, month: 10, day: 24)!, descripcion: "Leer y corregir."))
        #expect(nota.ruta.raw == "3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0002-revisar-textos-de-la-web.md")
        let fm = NoteDocument(text: nota.texto).frontmatter
        #expect(fm.text("estado") == "Por hacer")
        #expect(fm.text("responsable") == "agente:implementador")
        // Nunca en sábado: se corre al lunes.
        #expect(fm.text("planificada") == "2026-10-26")
        #expect(fm.text("proyecto") == "[[Proyecto|Web de Ferretería Ejemplo]]" || fm.text("proyecto")?.contains("web-ferreteria/Proyecto") == true)
        #expect(fm.text("area") == "entrega")
        #expect(nota.texto.contains("## Descripción\nLeer y corregir.\n"))
        let antes = env.huella()
        _ = try await (try await env.bus()).ejecutar(nota.plan)
        let cambiados = Set(env.huella().filter { antes[$0.key] != $0.value }.keys)
        #expect(cambiados == [nota.ruta.raw, ".tls/secuencias.json"])
        let releida = try #require(TaskStore(snapshot: env.foto()).tarea(nota.ruta))
        #expect(releida.proyecto?.raw == "3 · Entrega/Proyectos/web-ferreteria/Proyecto.md")
        #expect(releida.esListaParaAgente(hoy: LocalDate(year: 2026, month: 10, day: 26)!))
    }

    @Test func cambiarEstadoNoMueveYApuntaActividad() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let ruta = "3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md"
        let store = TaskStore(snapshot: env.foto(), reloj: relojDePrueba())
        let t = try #require(store.tarea(VaultPath(ruta)))
        let plan = try store.cambiarEstado(t, a: .hecha, autor: .persona("Manu"))
        _ = try await (try await env.bus()).ejecutar(plan)
        let texto = env.texto(ruta)!
        #expect(texto.hasPrefix("---\ntls_type: task\nnumero: T-0001\ntitulo: Preparar la reunión de arranque\nestado: Hecha\nplanificada: 2026-10-27\ncerrada: 2026-10-22\n---\n"))
        #expect(texto.contains("## Actividad\n\n### 2026-10-22 09:05 · Manu\nEstado: Por hacer → Hecha.\n<!-- tls:evento {\"a\":\"Hecha\",\"de\":\"Por hacer\",\"id\":\"ev-"))
        #expect(env.existe(ruta))
        // Un asistente no cierra tareas.
        #expect(throws: TareaError.noPermitidoAgente("Hecha")) { try store.cambiarEstado(t, a: .hecha, autor: .agente("comercial")) }
    }

    @Test func soloEstadoAlArrastrar() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let ruta = "3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md"
        let antes = env.texto(ruta)!
        let store = TaskStore(snapshot: env.foto(), reloj: relojDePrueba())
        let plan = try store.cambiarEstado(try #require(store.tarea(VaultPath(ruta))), a: .enCurso, autor: .persona("Manu"), soloEstado: true)
        _ = try await (try await env.bus()).ejecutar(plan)
        #expect(env.texto(ruta) == antes.replacingOccurrences(of: "estado: Por hacer", with: "estado: En curso"))
    }

    @Test func comentarioEscritoEnObsidianSinEncabezado() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        let ruta = "1 · Dirección/Tareas/t-0003-algo.md"
        env.escribir(ruta, """
        ---
        tls_type: task
        numero: T-0003
        titulo: Algo
        estado: En revisión
        ---
        # Algo

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        ### 2026-10-21 10:32 · agente:comercial
        Preparé el borrador.
        <!-- tls:evento {"id":"ev-1","tipo":"ejecucion"} -->

        Me parece bien, pero baja el alcance.

        """)
        let store = TaskStore(snapshot: env.foto(), reloj: relojDePrueba())
        let t = try #require(store.tarea(VaultPath(ruta)))
        let plan = try store.anadirActividad(t, autor: .agente("comercial"), texto: "Bajo el alcance a la fase 1.")
        _ = try await (try await env.bus()).ejecutar(plan)
        let texto = env.texto(ruta)!
        #expect(texto.contains("<!-- tls:evento {\"id\":\"ev-1\",\"tipo\":\"ejecucion\"} -->\n\n### 2026-10-22 09:05 · Manu\nMe parece bien, pero baja el alcance.\n\n### 2026-10-22 09:05 · agente:comercial\nBajo el alcance a la fase 1.\n<!-- tls:evento {\"id\":\"ev-"))
        // Sin texto suelto, solo se añade.
        #expect(TaskStore.comentarioSinEncabezado(texto) == nil)
    }

    @Test func comentarioSinEntradasPrevias() {
        let texto = "# X\n\n## Actividad\n> Guía: solo se añade.\nPrimer comentario a mano.\n"
        let off = TaskStore.comentarioSinEncabezado(texto)
        #expect(off == texto.utf8.count - "Primer comentario a mano.\n".utf8.count)
        #expect(TaskStore.comentarioSinEncabezado("# X\n\n## Actividad\n### 2026-10-21 10:00 · Manu\nHola\n") == nil)
    }

    @Test func eventoNoCierraElComentario() {
        let c = TaskStore.comentarioEvento(["tipo": "nota", "texto": "a --> b"])
        #expect(c.hasPrefix("<!-- tls:evento {"))
        #expect(c.hasSuffix(" -->"))
        #expect(c.dropLast(4).range(of: "-->") == nil)
    }

    @Test func numerosRepetidosSeRenumeranYRenombran() async throws {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        env.escribir(".tls/secuencias.json", "{\"tarea\":5}\n")
        env.escribir("1 · Dirección/Tareas/t-0005-primera.md", "---\ntls_type: task\nnumero: T-0005\ntitulo: Primera\ncreada: 2026-10-01\n---\n# Primera\n")
        env.escribir("2 · Ventas/Tareas/t-0005-segunda.md", "---\ntls_type: task\nnumero: T-0005\ntitulo: Segunda\ncreada: 2026-10-02\n---\n# Segunda\n")
        env.escribir("1 · Dirección/Notas.md", "Ver [[t-0005-segunda]] y [la segunda](../2%20·%20Ventas/Tareas/t-0005-segunda.md).\n")
        let hash0 = env.hashArbol()
        let store = TaskStore(snapshot: env.foto(), reloj: relojDePrueba())
        #expect(store.duplicados().map { $0.map(\.ruta.name) } == [["t-0005-primera.md", "t-0005-segunda.md"]])
        let preview = try #require(try store.resolverDuplicados())
        #expect(preview.esSeguro)
        let bus = try await env.bus()
        try await LinkRefactor.aplicar(preview, con: bus)
        #expect(env.existe("2 · Ventas/Tareas/t-0006-segunda.md"))
        #expect(!env.existe("2 · Ventas/Tareas/t-0005-segunda.md"))
        #expect(env.texto("2 · Ventas/Tareas/t-0006-segunda.md")!.contains("numero: T-0006\n"))
        #expect(env.texto("1 · Dirección/Notas.md") == "Ver [[t-0006-segunda]] y [la segunda](../2%20·%20Ventas/Tareas/t-0006-segunda.md).\n")
        #expect(env.texto(".tls/secuencias.json") == "{\"tarea\":6}\n")
        #expect(TaskStore(snapshot: env.foto()).duplicados().isEmpty)
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(env.hashArbol() == hash0)
    }

    @Test func elContadorSeAjustaAlMayorVisto() {
        let env = EntornoCarpeta(vacia: true)
        defer { env.limpiar() }
        env.escribir(".tls/secuencias.json", "{\"tarea\":2}\n")
        env.escribir("1 · Dirección/Tareas/t-0009-a.md", "---\ntls_type: task\nnumero: T-0009\n---\n")
        #expect(TaskStore(snapshot: env.foto()).siguienteNumero() == 10)
        env.escribir(".tls/secuencias.json", "{\"tarea\":40}\n")
        #expect(TaskStore(snapshot: env.foto()).siguienteNumero() == 41)
    }

    @Test func laRutaMandaSobreElProyecto() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Tareas/t-0002-movida.md", "---\ntls_type: task\nnumero: T-0002\nproyecto: \"[[Proyecto|Web]]\"\n---\n# Movida\n")
        let store = TaskStore(snapshot: env.foto(), reloj: relojDePrueba())
        let correcciones = store.correccionesDeUbicacion()
        // La de la fixture vive en el proyecto y no lo dice; la movida ya no está en ningún proyecto.
        #expect(correcciones.count == 2)
        let enProyecto = try #require(correcciones.first { $0.proyecto != nil })
        #expect(enProyecto.poner.first?.key == "proyecto")
        let fuera = try #require(correcciones.first { $0.proyecto == nil })
        #expect(fuera.quitar == ["proyecto"])
        _ = try await (try await env.bus()).ejecutar(try #require(store.corregir(correcciones)))
        #expect(TaskStore(snapshot: env.foto()).correccionesDeUbicacion().isEmpty)
    }
}

@Suite("Tareas: Tareas.md heredados")
struct TareasHeredadasTests {
    @Test func gramaticaTOKFINAL() {
        let lineas = ChecklistParser.parse("""
        # Tareas
        - [ ] Pinturas Fran — Panel A/B/IVA · 2026-10-27 · vence 2026-10-30 · Urgente · 2h · +0.5h · @area:VEN · @est:En progreso · @resp:ana · @op:pinturas-fran · #t1
        - [x] GHL · 12 · Activar flujos · Semana · #t2
        - [ ] Llamar a la gestoría · @area:finanzas · responsable Ana López
        - [ ] Sin tokens
        ## Notas

        ### t1
        Cuerpo de la primera.
        - [ ] esto es un paso, no una tarea

        ### Objetivo
        sigue siendo de t1

        ### t2
        """)
        #expect(lineas.count == 4)
        let a = lineas[0]
        #expect(a.titulo == "Pinturas Fran — Panel A/B/IVA")
        #expect(a.fecha == "2026-10-27" && a.vence == "2026-10-30" && a.prioridad == "Urgente")
        #expect(a.horas == 2 && a.invertidas == 0.5)
        #expect(a.area == .ventas && a.estado == "En progreso" && a.responsable == "ana" && a.oportunidad == "pinturas-fran")
        #expect(a.token == "t1")
        #expect(a.notas == "Cuerpo de la primera.\n- [ ] esto es un paso, no una tarea\n\n### Objetivo\nsigue siendo de t1")
        let b = lineas[1]
        #expect(b.hecho && b.titulo == "GHL · 12 · Activar flujos" && b.horizonte == "Semana" && b.notas == nil)
        // `@area:` con la clave en minúsculas (G1 lo dejaba pegado al título) y `responsable` de G3.
        #expect(lineas[2].titulo == "Llamar a la gestoría" && lineas[2].area == .finanzas && lineas[2].responsable == "Ana López")
        #expect(lineas[3].titulo == "Sin tokens" && lineas[3].token == nil)
    }

    @Test func migrarATareasYRetirar() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("2 · Ventas/Tareas.md", """
        # Tareas de Ventas
        - [ ] Llamar a Lucía · 2026-10-24 · vence 2026-10-30 · Urgente · @op:web-ferreteria-ejemplo · #a1
        - [x] Enviar propuesta · #a2
        - [ ] Revisar objeciones · @est:Esperando respuesta · responsable Ana
        ## Notas
        ### a1
        Preguntar por el plazo.
        """)
        let migrador = LegacyTasksMigrator(snapshot: env.foto(), reloj: relojDePrueba())
        #expect(migrador.encontrar().map(\.raw) == ["2 · Ventas/Tareas.md"])
        let m = try migrador.proponer(VaultPath("2 · Ventas/Tareas.md"))
        #expect(m.fichas.map(\.ruta.raw) == ["2 · Ventas/Tareas/t-0002-llamar-a-lucia.md", "2 · Ventas/Tareas/t-0003-enviar-propuesta.md",
                                             "2 · Ventas/Tareas/t-0004-revisar-objeciones.md"])
        #expect(m.resumen == "Pasar 3 tareas de «2 · Ventas/Tareas.md» a fichas y retirar el fichero al Archivo.")
        _ = try await (try await env.bus()).ejecutar(m.plan)
        #expect(!env.existe("2 · Ventas/Tareas.md"))
        #expect(env.existe("Archivo/2 · Ventas/Tareas.md"))
        let store = TaskStore(snapshot: env.foto())
        let a = try #require(store.tarea(VaultPath("2 · Ventas/Tareas/t-0002-llamar-a-lucia.md")))
        #expect(a.estado == .porHacer && a.prioridad == "Urgente" && a.planificada?.description == "2026-10-26" && a.vence?.description == "2026-10-30")
        #expect(a.oportunidad?.raw == "2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md")
        #expect(a.origen == "importacion")
        let ta = env.texto("2 · Ventas/Tareas/t-0002-llamar-a-lucia.md")!
        #expect(ta.contains("## Descripción\nPreguntar por el plazo.\n"))
        #expect(ta.contains("fecha_corte: 2026-10-22"))
        #expect(ta.contains("Importada de «2 · Ventas/Tareas.md» (línea 2)."))
        #expect(store.tarea(VaultPath("2 · Ventas/Tareas/t-0003-enviar-propuesta.md"))?.estado == .hecha)
        let c = try #require(store.tarea(VaultPath("2 · Ventas/Tareas/t-0004-revisar-objeciones.md")))
        #expect(c.estado == .bloqueada && c.responsable == "Ana")
        #expect(env.texto(".tls/secuencias.json") == "{\"tarea\":4}\n")
    }

    @Test func vacioSoloSeRetira() throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("1 · Dirección/Tareas.md", "# Tareas\n\nNada pendiente.\n")
        let m = try LegacyTasksMigrator(snapshot: env.foto()).proponer(VaultPath("1 · Dirección/Tareas.md"))
        #expect(m.fichas.isEmpty)
        #expect(m.plan.ops == [.retire(VaultPath("1 · Dirección/Tareas.md"))])
    }
}
