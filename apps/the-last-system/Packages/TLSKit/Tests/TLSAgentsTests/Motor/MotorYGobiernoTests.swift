import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// El motor enchufado al gobierno: configuración confirmada, `puedeLanzar` y limpieza del estado.
@Suite("Motor · con el gobierno", .serialized)
struct MotorYGobiernoTests {
    @Test("Ajustes de gobierno: un cambio hecho fuera de la app no da más permisos hasta confirmarlo")
    func ajustesConfirmados() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let a = try Autorizador(root: e.raiz, stateDirectory: e.estadoDir)
        let fuente = AjustesDeGobierno(autorizador: a)
        // Primera lectura: lo que hay queda confirmado.
        var ajustes = await fuente.ajustes()
        #expect(ajustes.agente("comercial")?.activo == true)
        #expect(ajustes.agente("mika")?.rutina("algo-rojo")?.hora == 8)
        // Fuera de la app (Obsidian) se activa Equipo y se sube el tope de Comercial: no vale todavía.
        let texto = e.leer(".tls/config.yaml")
            .replacingOccurrences(of: "presupuesto_mes_usd: 10", with: "presupuesto_mes_usd: 100")
            + "  equipo:\n    activo: true\n    areas: [equipo]\n"
        e.escribir(".tls/config.yaml", texto)
        ajustes = await fuente.ajustes()
        #expect(ajustes.agente("equipo")?.activo != true)
        #expect(ajustes.agente("comercial")?.presupuestoMesUSD == 10)
        // Apagar fuera de la app sí vale al momento (es más restrictivo).
        e.escribir(".tls/config.yaml", texto.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado"))
        ajustes = await fuente.ajustes()
        #expect(!ajustes.interruptor)
    }

    @Test("puedeLanzar del Autorizador: con el interruptor apagado el trabajo espera en la cola")
    func permisoDeLanzamiento() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let az = try Autorizador(root: e.raiz, stateDirectory: e.estadoDir)
        _ = az.estadoDeConfig()
        let avisos = e.avisos
        let cola = ColaDeEjecuciones(.init(
            estadoDeCarpeta: e.estadoDir, raiz: e.raiz, estado: try e.estado(), runtime: e.runtime(), servidor: e.puerta,
            registro: e.registro, ajustes: AjustesFijos(e.ajustes), catalogo: EntornoMotor.catalogo, reloj: e.reloj,
            foto: e.foto, permisoDeLanzamiento: { az.permisoDeLanzamiento($0) }, alAvisar: { avisos.apuntar($0) }))
        let t = e.tarea(1, titulo: "Algo")
        let ej = try #require(try await cola.encolar(Disparo.tareaLista(id: "x", ruta: t, hash: "h", agente: "comercial", titulo: "Algo")))
        // El gobierno lee el interruptor del fichero (y apagar vale al momento, aunque no esté confirmado).
        let config = e.leer(".tls/config.yaml")
        e.escribir(".tls/config.yaml", config.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado"))
        await cola.procesar()
        #expect(e.claude.llamadas == 0)
        let x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .pendiente)
        #expect(x.nota == "Los asistentes están apagados.")
        e.escribir(".tls/config.yaml", config)
        await cola.olvidarDenegaciones()
        await cola.procesar()
        #expect(e.claude.llamadas == 1)
        #expect(try e.estado().ejecucion(ej.id)?.estado == .completada)
    }

    @Test("Las carpetas de ejecución de hace más de 90 días se quitan; las recientes y las abiertas, no")
    func limpieza() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let host = try e.host(leerEventos: false)
        let base = e.estadoDir.appendingPathComponent("ejecuciones")
        let vieja = base.appendingPathComponent("20260101-000000-aaaaaa")
        let nueva = base.appendingPathComponent("20261019-070000-bbbbbb")
        for d in [vieja, nueva] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            Apoyo.escribir("{}\n", en: d.appendingPathComponent("stream.jsonl"))
        }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-100 * 86_400)], ofItemAtPath: vieja.path)
        #expect(host.limpiarEjecucionesViejas() == 1)
        #expect(!FileManager.default.fileExists(atPath: vieja.path))
        #expect(FileManager.default.fileExists(atPath: nueva.path))
    }

    @Test("El chat queda en la historia del asistente (fuera de la cola) y la cola no lo lanza")
    func chatEnLaHistoria() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let estado = try e.estado()
        let d = Disparo(clave: "chat:c1", tipo: .chat, agente: "mika", instruccion: "Chat")
        try estado.apuntarFueraDeCola(d, id: "chat-1", estado: .enCurso, ahora: e.reloj.ahora())
        #expect(try estado.enEspera().isEmpty)
        #expect(try estado.ejecucion("chat-1")?.estado == .enCurso)
        // Si la app se cierra con el chat abierto, al volver queda interrumpido, sin escribir en la carpeta.
        let cola = try e.cola(estado: estado)
        await cola.recuperar()
        #expect(try estado.ejecucion("chat-1")?.motivo == .interrumpida)
        #expect(e.registro.cierres.isEmpty)
    }
}
