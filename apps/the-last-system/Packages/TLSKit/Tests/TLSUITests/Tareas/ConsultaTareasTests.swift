import Foundation
import Testing
@testable import TLSCore
@testable import TLSUI

/// Lo puro de la pantalla Tareas: filtros (área, proyecto u oportunidad, responsable, estado, fecha, «Lo mío» y
/// búsqueda), agrupación, columnas del tablero, ⌘← ⌘→, la Actividad leída con sus eventos traducidos y el estado
/// del asistente. Sin interfaz ni carpeta.
@Suite("Tareas · filtros, tablero y actividad")
@MainActor
struct ConsultaTareasTests {
    static let hoy = LocalDate(year: 2026, month: 10, day: 21)! // miércoles

    static func fila(_ n: Int, _ titulo: String, estado: EstadoTarea? = .porHacer, area: AreaCode? = .ventas,
                     responsable: String? = "Manu", planificada: LocalDate? = nil, vence: LocalDate? = nil,
                     proyecto: String? = nil, estimacion: Double? = nil) -> FilaTarea {
        let ruta = VaultPath("\(area.map { "\($0.numero) · \($0.nombre)" } ?? "X")/Tareas/t-\(String(format: "%04d", n))-x.md")
        let t = Tarea(ruta: ruta, uid: nil, numero: String(format: "T-%04d", n), numeroEntero: n, titulo: titulo, estado: estado,
                      estadoTexto: estado?.rawValue, prioridad: nil, tipo: "tarea", responsable: responsable, planificada: planificada,
                      vence: vence, despertar: nil, area: area, proyecto: proyecto.map { VaultPath($0) }, proyectoPorRuta: nil,
                      oportunidad: nil, empresa: nil, creada: nil, cerrada: nil, origen: nil)
        return FilaTarea(tarea: t, estado: estado ?? .sinProgramar, estimacionH: estimacion,
                         contenedor: proyecto.map { VaultPath($0) }, contenedorNombre: proyecto.map { _ in "Trimestrales 2026" },
                         contenedorEsProyecto: proyecto != nil)
    }

    static var filas: [FilaTarea] {
        let h = hoy
        return [
            fila(1, "Llamar a Jorge", planificada: h, vence: h.adding(days: 2), estimacion: 0.5),
            fila(2, "Preparar propuesta", estado: .enCurso, responsable: "agente:comercial", planificada: h.adding(days: 1), vence: h.adding(days: -3)),
            fila(3, "Pedir documentación", estado: .enRevision, area: .entrega, responsable: "lucia", proyecto: "3 · Entrega/Proyectos/trim/Proyecto.md"),
            fila(4, "Cerrar el trimestre", estado: .hecha, area: .finanzas, vence: h.adding(days: -10)),
            fila(5, "Idea suelta", estado: .sinProgramar, area: .marca, responsable: nil),
            fila(6, "Lo que ya no", estado: .cancelada, area: .marca),
            fila(7, "Revisar el viernes", vence: LocalDate(year: 2026, month: 10, day: 23)!),
        ]
    }

    @Test("Fecha: Hoy, Semana, Vencidas y Sin programar; y Cancelada oculta salvo con el interruptor")
    func fechas() {
        var c = ConsultaTareas()
        let todas = c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!)
        #expect(!todas.contains(6))
        #expect(todas.count == 6)
        c.verCanceladas = true
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").count == 7)
        c.verCanceladas = false
        c.fecha = .hoy
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [1])
        c.fecha = .vencidas
        // La hecha que venció no cuenta: solo las abiertas.
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [2])
        c.fecha = .semana
        #expect(Set(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!)) == [1, 2, 7])
        c.fecha = .sinProgramar
        #expect(Set(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!)) == [3, 5, 7])
    }

    @Test("«Lo mío», responsable, área, proyecto, estado y búsqueda (todas las palabras, sin tildes)")
    func filtros() {
        var c = ConsultaTareas()
        c.loMio = true
        #expect(Set(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!)) == [1, 4, 7])
        // El identificador estable de la persona también es suyo («Lucía Andreu» → «lucia-andreu»; «lucia» no).
        #expect(Self.fila(9, "x", responsable: "manu").esDe("Manu"))
        c = ConsultaTareas()
        c.responsable = "agente:comercial"
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [2])
        c.responsable = ConsultaTareas.sinResponsable
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [5])
        c = ConsultaTareas()
        c.area = .entrega
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [3])
        c = ConsultaTareas()
        c.contenedor = VaultPath("3 · Entrega/Proyectos/trim/Proyecto.md")
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [3])
        c = ConsultaTareas()
        c.estado = .cancelada
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [6])
        c = ConsultaTareas()
        c.busqueda = "documentacion trimestrales"
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [3])
        c.busqueda = "T-0007"
        #expect(c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu").map(\.tarea.numeroEntero!) == [7])
        #expect(c.filtrando)
        c.quitarFiltros()
        #expect(!c.filtrando)
    }

    @Test("Lo urgente primero y agrupación por estado, área, proyecto y responsable")
    func ordenYGrupos() {
        let c = ConsultaTareas()
        let lista = c.filtrar(Self.filas, hoy: Self.hoy, persona: "Manu")
        #expect(lista.first?.tarea.numeroEntero == 2) // vencida
        let porEstado = c.grupos(lista, persona: "Manu")
        #expect(porEstado.map(\.titulo) == ["Sin programar", "Por hacer", "En curso", "En revisión", "Hecha"])
        var g = c
        g.agrupar = .responsable
        let porQuien = g.grupos(lista, persona: "Manu")
        #expect(porQuien.first?.titulo == "Manu")
        #expect(porQuien.last?.titulo == "Sin responsable")
        g.agrupar = .contenedor
        #expect(g.grupos(lista, persona: "Manu").map(\.titulo) == ["Trimestrales 2026", "Sin proyecto"])
        g.agrupar = .area
        #expect(g.grupos(lista, persona: "Manu").map(\.titulo) == ["2 · Ventas", "3 · Entrega", "4 · Finanzas", "5 · Marca"])
    }

    @Test("La consulta vuelve igual del recuerdo de la pestaña")
    func recuerdo() {
        var c = ConsultaTareas()
        c.vista = .tablero; c.area = .ventas; c.fecha = .vencidas; c.loMio = true; c.busqueda = "jorge"
        c.verCanceladas = true; c.agrupar = .area; c.estado = .enCurso; c.responsable = "agente:comercial"
        c.contenedor = VaultPath("2 · Ventas/Oportunidades/x.md")
        var r = RecuerdoPantalla()
        c.guardar(en: &r)
        #expect(ConsultaTareas(recuerdo: r) == c)
        #expect(ConsultaTareas(recuerdo: RecuerdoPantalla()) == ConsultaTareas())
    }

    @Test("Tablero: seis columnas (Cancelada con el interruptor) y ⌘← ⌘→ a la de al lado")
    func columnas() {
        #expect(ColumnasTablero.estados(verCanceladas: false).map(\.rawValue)
            == ["Sin programar", "Por hacer", "En curso", "En revisión", "Bloqueada", "Hecha"])
        #expect(ColumnasTablero.estados(verCanceladas: true).last == .cancelada)
        #expect(ColumnasTablero.vecina(de: .porHacer, paso: 1, verCanceladas: false) == .enCurso)
        #expect(ColumnasTablero.vecina(de: .porHacer, paso: -1, verCanceladas: false) == .sinProgramar)
        #expect(ColumnasTablero.vecina(de: .sinProgramar, paso: -1, verCanceladas: false) == nil)
        #expect(ColumnasTablero.vecina(de: .hecha, paso: 1, verCanceladas: false) == nil)
        #expect(ColumnasTablero.vecina(de: .hecha, paso: 1, verCanceladas: true) == .cancelada)
        let cols = ColumnasTablero.columnas(Self.filas, verCanceladas: false)
        #expect(cols.count == 6)
        #expect(cols.first { $0.estado == .porHacer }?.filas.count == 2)
    }

    @Test("Cabecera: para hoy, vencidas y en revisión; sin abiertas lo dice")
    func resumen() {
        let r = ResumenTareas(Self.filas, hoy: Self.hoy)
        #expect(r.paraHoy == 1)
        #expect(r.vencidas == 1)
        #expect(r.enRevision == 1)
        #expect(r.frase == "1 para hoy · 1 vencida · 1 espera tu revisión · 5 abiertas en total.")
        #expect(ResumenTareas([], hoy: Self.hoy).frase == "No hay tareas abiertas.")
    }

    @Test("Actividad: encabezados, eventos traducidos, asistente con uso y detalle, mención y texto de Obsidian")
    func actividad() {
        let texto = """
        ---
        tls_type: task
        numero: T-0042
        ---
        # Preparar propuesta

        ## Descripción
        Hacer la propuesta.

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        ### 2026-10-21 10:32 · agente:comercial
        Estado: Por hacer → En revisión. Preparé el seguimiento: [borrador](../Borradores/seguimiento-nexo-d7.md). Pendiente de tu OK en Decisiones.
        <!-- tls:evento {"id":"ev-1","tipo":"ejecucion","de":"Por hacer","a":"En revisión","run":"r-7f3a","coste_usd":0.04,"aprobacion":"apr-91c2"} -->

        ### 2026-10-21 11:02 · Manu
        OK, pero baja el alcance de la fase 2. @agente:comercial
        <!-- tls:evento {"id":"ev-2","tipo":"comentario"} -->

        ### 2026-10-21 11:05 · Manu
        Estado: En revisión → En curso.
        <!-- tls:evento {"a":"En curso","de":"En revisión","id":"ev-3","tipo":"estado"} -->

        ### 2026-10-21 11:06 · sistema
        Creó las tareas del plan.
        <!-- tls:evento {"id":"ev-4","tipo":"regla"} -->

        Me parece bien, pero díselo a @Comercial.

        """
        let e = ActividadDeTarea.leer(texto, alias: ["comercial": "agente:comercial"])
        #expect(e.count == 5)
        #expect(e[0].clase == .asistente)
        #expect(e[0].autor == "Comercial (asistente)")
        #expect(e[0].resumen == "Trabajo terminado · Por hacer → En revisión")
        // F4 · corrector: el uso como parte del tope del mes (15 de serie); los dólares, en «Detalle técnico».
        #expect(e[0].uso == "Usó menos del 1 % de tu tope del mes")
        #expect(e[0].detalle.contains(.init(etiqueta: "Uso", valor: "0,04 USD")))
        #expect(e[0].detalle.contains(.init(etiqueta: "Ejecución", valor: "r-7f3a")))
        #expect(e[0].pideAprobacion)
        #expect(e[0].texto.contains("Preparé el seguimiento: borrador."))
        #expect(e[1].clase == .comentario)
        #expect(e[1].texto == "OK, pero baja el alcance de la fase 2. @Comercial (asistente)")
        #expect(e[1].menciones == ["agente:comercial"])
        #expect(e[2].clase == .cambio)
        #expect(e[2].resumen == nil) // el texto ya dice el cambio
        #expect(e[3].clase == .sistema)
        #expect(e[3].autor == "La app")
        #expect(e[4].sinEncabezado)
        #expect(e[4].clase == .comentario)
        #expect(e[4].autor == "Escrito en Obsidian")
        #expect(e[4].menciones == ["agente:comercial"])
        // Las menciones guardadas en el evento cuentan aunque el texto no las nombre.
        let guardada = ActividadDeTarea.leer("## Actividad\n\n### 2026-10-21 12:00 · Manu\nMíralo.\n<!-- tls:evento {\"tipo\":\"comentario\",\"menciones\":\"agente:contable\"} -->\n")
        #expect(guardada.first?.menciones == ["agente:contable"])
        // Sin sección Actividad, nada.
        #expect(ActividadDeTarea.leer("# Nota\n\nTexto.\n").isEmpty)
    }

    @Test("Estado del asistente: sin empezar, espera su día, en cola, espera tu respuesta y terminado")
    func estadoAsistente() {
        let hoy = Self.hoy
        func t(_ e: EstadoTarea?, _ r: String? = "agente:comercial", planificada: LocalDate? = nil) -> Tarea {
            Self.fila(1, "x", estado: e, responsable: r, planificada: planificada).tarea
        }
        #expect(EstadoAsistenteTarea.de(t(.porHacer, "Manu"), hoy: hoy) == nil)
        #expect(EstadoAsistenteTarea.de(t(.sinProgramar), hoy: hoy) == .sinEmpezar)
        #expect(EstadoAsistenteTarea.de(t(.porHacer), hoy: hoy) == .enCola)
        #expect(EstadoAsistenteTarea.de(t(.porHacer, planificada: hoy.adding(days: 2)), hoy: hoy) == .esperaSuDia(hoy.adding(days: 2)))
        #expect(EstadoAsistenteTarea.de(t(.enRevision), hoy: hoy) == .esperaTuRespuesta)
        #expect(EstadoAsistenteTarea.de(t(.hecha), hoy: hoy) == .terminado)
        #expect(EstadoAsistenteTarea.de(t(.porHacer), hoy: hoy, enMarcha: true) == .trabajando)
        #expect(EstadoAsistenteTarea.sinEmpezar.frase(asistente: "Comercial (asistente)", hoy: hoy).contains("Empezará cuando la pases a Por hacer"))
    }

    @Test("Los textos de la pantalla Tareas no usan jerga")
    func glosario() {
        var textos = [ResumenTareas(Self.filas, hoy: Self.hoy).frase]
        textos += FiltroFecha.allCases.map(\.rawValue) + AgrupacionTareas.allCases.map(\.rawValue)
        textos += EstadoTarea.allCases.map(ColumnasTablero.vacio)
        textos += [EstadoAsistenteTarea.sinEmpezar, .enCola, .esperaTuRespuesta, .bloqueada, .terminado, .trabajando,
                   .esperaSuDia(Self.hoy)].flatMap { [$0.palabra, $0.frase(asistente: "Comercial (asistente)", hoy: Self.hoy)] }
        textos += Self.filas.map { FilaDeTarea.etiquetaAccesible($0, hoy: Self.hoy) }
        textos += FiltroFecha.allCases.map { f in var c = ConsultaTareas(); c.fecha = f; return TareasPantalla.porQueVacio(c) }
        for t in textos { #expect(GlosarioTests.jerga(t).isEmpty, "Jerga en «\(t)»") }
    }
}
