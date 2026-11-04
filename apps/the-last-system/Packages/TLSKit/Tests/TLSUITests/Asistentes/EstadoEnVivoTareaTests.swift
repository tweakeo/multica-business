import Foundation
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSUI

/// El estado en vivo del asistente en la ficha de tarea (PLAN §6.4): en cola, trabajando («Leyendo…»), esperando tu
/// respuesta o terminado; «Empezar ahora» la pasa a Por hacer con el día de hoy; asignada en Sin programar, explica que
/// empezará cuando pase a Por hacer.
@Suite("Asistentes · estado en vivo en la ficha de tarea", .serialized)
@MainActor
struct EstadoEnVivoTareaTests {
    func tarea(_ a: ApoyoAsistentes, _ ruta: VaultPath) throws -> Tarea {
        try #require(TaskStore(snapshot: VaultSnapshot.read(root: a.carpeta)).tarea(ruta))
    }

    func crear(_ a: ApoyoAsistentes, _ titulo: String, responsable: String?, planificada: LocalDate? = nil) async throws -> VaultPath {
        let r = try await NuevaTareaHoja.crear(titulo: titulo, area: .ventas, proyecto: nil, responsable: responsable,
                                               planificada: planificada, sesion: a.sesion)
        await SesionEscrituraTests().esperar({ a.sesion.resumen(de: r) != nil })
        return r
    }

    func poner(_ a: ApoyoAsistentes, _ ruta: VaultPath, _ clave: String, _ valor: String) async throws {
        let antes = a.sesion.revision
        try await a.sesion.escribir(.cambiarPropiedades(ruta, poner: [Property(key: clave, value: .text(valor))], quitar: []), aviso: "")
        await a.esperarRevision(antes)
    }

    @Test("Sin programar: explica que empezará al pasarla a Por hacer; «Empezar ahora» la pone en Por hacer con el día de hoy")
    func sinProgramarYEmpezarAhora() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        let hoy = try #require(LocalDate(parsing: "2026-10-19"))
        let ruta = try await crear(a, "Preparar la llamada con Amparo Ribera", responsable: "agente:comercial")
        var t = try tarea(a, ruta)
        #expect(t.estado == nil || t.estado == .sinProgramar)
        var e = try #require(EstadoVivoTarea.de(t, hoy: hoy, vivo: nil, interruptorEncendido: true, conectado: false))
        #expect(e.palabra == "Sin empezar")
        #expect(e.frase == "Comercial (asistente) no la coge mientras esté «Sin programar». Empezará cuando la pases a Por hacer.")

        let modelo = ModeloTarea(ruta: ruta, sesion: a.sesion)
        await modelo.cargar()
        let antes = a.sesion.revision
        await modelo.empezarAhora()
        await a.esperarRevision(antes)
        t = try tarea(a, ruta)
        #expect(t.estado == .porHacer && t.planificada == hoy)
        e = try #require(EstadoVivoTarea.de(t, hoy: hoy, vivo: nil, interruptorEncendido: true, conectado: false))
        #expect(e.palabra == "En cola" && e.detalle == "Empezará cuando los asistentes estén en marcha en este Mac.")
        e = try #require(EstadoVivoTarea.de(t, hoy: hoy, vivo: nil, interruptorEncendido: true, conectado: true))
        #expect(e.palabra == "En cola" && e.detalle == nil)
        // Con los asistentes en pausa, lo dice.
        e = try #require(EstadoVivoTarea.de(t, hoy: hoy, vivo: nil, interruptorEncendido: false, conectado: true))
        #expect(e.palabra == "En pausa" && e.frase.contains("cuando los enciendas"))
    }

    @Test("En vivo: trabajando con su frase, en cola y esperando tu respuesta; después, terminado")
    func enVivo() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        let hoy = try #require(LocalDate(parsing: "2026-10-19"))
        let ruta = try await crear(a, "Revisar el embudo de octubre", responsable: "agente:comercial", planificada: hoy)
        let t = try tarea(a, ruta)
        var vivo = TrabajoEnVivo(ejecucion: "r-1", agente: "comercial", tarea: ruta, fase: .trabajando, frase: "Leyendo…",
                                 desde: Date(), simulado: true)
        var e = try #require(EstadoVivoTarea.de(t, hoy: hoy, vivo: vivo, interruptorEncendido: true, conectado: true))
        #expect(e.palabra == "Trabajando" && e.detalle == "Leyendo…" && e.simulado)
        #expect(e.frase == "Comercial (asistente) está trabajando en ella.")
        vivo.frase = "Creando tarea…"
        e = try #require(EstadoVivoTarea.de(t, hoy: hoy, vivo: vivo, interruptorEncendido: true, conectado: true))
        #expect(e.detalle == "Creando tarea…")
        vivo.fase = .enCola
        #expect(EstadoVivoTarea.de(t, hoy: hoy, vivo: vivo, interruptorEncendido: true, conectado: true)?.palabra == "En cola")
        vivo.fase = .esperandoRespuesta
        #expect(EstadoVivoTarea.de(t, hoy: hoy, vivo: vivo, interruptorEncendido: true, conectado: true)?.palabra == "Esperando tu respuesta")

        // El motor la deja en revisión al terminar: «Terminado», revisa lo que dejó.
        try await poner(a, ruta, "estado", "En revisión")
        e = try #require(EstadoVivoTarea.de(try tarea(a, ruta), hoy: hoy, vivo: nil, interruptorEncendido: true, conectado: true))
        #expect(e.palabra == "Terminado" && e.frase.contains("terminó su parte"))
        // Una pregunta en revisión espera tu respuesta.
        try await poner(a, ruta, "tipo", "pregunta")
        e = try #require(EstadoVivoTarea.de(try tarea(a, ruta), hoy: hoy, vivo: nil, interruptorEncendido: true, conectado: true))
        #expect(e.palabra == "Esperando tu respuesta")
        try await poner(a, ruta, "estado", "Hecha")
        #expect(EstadoVivoTarea.de(try tarea(a, ruta), hoy: hoy, vivo: nil, interruptorEncendido: true, conectado: true)?.palabra == "Terminado")
    }

    @Test("Una tarea de una persona no enseña estado de asistente")
    func dePersona() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        let ruta = try await crear(a, "Llamar a la gestoría", responsable: "Manu")
        #expect(EstadoVivoTarea.de(try tarea(a, ruta), hoy: try #require(LocalDate(parsing: "2026-10-19")), vivo: nil,
                                   interruptorEncendido: true, conectado: true) == nil)
    }
}

/// La ficha de un asistente se entra desde Asistentes y sale en las migas.
@Suite("Asistentes · navegación", .serialized)
@MainActor
struct NavegacionAsistentesTests {
    @Test("`Destino.asistente`: un nivel (no raíz), con su nombre en las migas y que se guarda al cerrar")
    func destino() async throws {
        let d = Destino.asistente("contable")
        #expect(d.identidad == "asistente:contable" && !d.puedeSerRaiz && d.simbolo == "sparkle")
        let datos = try JSONEncoder().encode(d)
        #expect(try JSONDecoder().decode(Destino.self, from: datos) == d)

        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        #expect(a.sesion.nombre(de: d) == "Contable")
        #expect(a.sesion.nombre(de: .asistente("mika")) == "Mika")
        let nav = Navegacion(raiz: .asistentes)
        nav.entrar(.asistente("contable"))
        #expect(a.sesion.migas(de: nav).map(\.nombre) == ["Asistentes", "Contable"])
    }
}
