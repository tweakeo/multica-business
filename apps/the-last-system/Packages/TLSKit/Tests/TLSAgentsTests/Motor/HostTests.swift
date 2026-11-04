import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// El host de una carpeta: arrancar, trabajar en segundo plano, apagar el interruptor y parar.
@Suite("Motor · host de la carpeta", .serialized)
struct HostTests {
    @Test("Arranca la puerta y el bucle, trabaja solo y al parar no deja procesos vivos (criterio 9)")
    func cicloDeVida() async throws {
        let e = EntornoMotor(inicio: DisparosTests.fecha(20, 16))
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let host = try e.host(leerEventos: false)
        try await host.arrancar()
        #expect(e.puerta.arrancada)
        let t = e.tarea(1, titulo: "Llamar")
        await host.carpetaCambio()
        #expect(await esperarA(15) { e.registro.cierres.contains { $0.tarea == t && $0.estado == .completada } })
        // Un trabajo largo en marcha al cerrar: se para y no queda nada vivo.
        e.claude.stream([Flujo.inicio(), Flujo.texto("…")])
        e.claude.marcar("colgar")
        e.tarea(2, titulo: "Otra")
        await host.carpetaCambio()
        #expect(await esperarA(15) { e.claude.llamadas == 2 && (try? e.estado().ejecuciones(estados: [.enCurso]).first?.pid) != nil })
        let pid = try #require(try e.estado().ejecuciones(estados: [.enCurso]).first?.pid)
        let inicio = Date()
        await host.parar()
        #expect(Date().timeIntervalSince(inicio) <= 6)
        #expect(e.puerta.parada)
        #expect(!ProcessRunner.groupAlive(pid))
        #expect(try e.estado().ejecuciones(estados: [.enCurso]).isEmpty)
    }

    @Test("Apagar el interruptor con un trabajo en marcha lo para en 5 s o menos y no sale nada más (criterio 4)")
    func apagarInterruptor() async throws {
        let e = EntornoMotor(inicio: DisparosTests.fecha(20, 16))
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(), Flujo.texto("…")])
        e.claude.marcar("colgar")
        e.tarea(1, titulo: "Una")
        e.tarea(2, titulo: "Dos")
        let host = try e.host(leerEventos: false)
        try await host.arrancar()
        // Que el `claude` falso esté ya corriendo (no solo lanzado) antes de apagar.
        #expect(await esperarA(15) { e.claude.llamadas == 1 && (try? e.estado().ejecuciones(estados: [.enCurso]).first?.pid) != nil })
        let enCurso = try #require(try e.estado().ejecuciones(estados: [.enCurso]).first)
        var a = e.ajustes
        a.interruptor = false
        e.ajustes = a
        let inicio = Date()
        await host.ajustesCambiaron()
        #expect(await esperarA(5) { (try? e.estado().ejecucion(enCurso.id))?.estado == .cancelada })
        #expect(Date().timeIntervalSince(inicio) <= 5)
        #expect(e.puerta.revocadas.contains(enCurso.id))
        #expect(!ProcessRunner.groupAlive(try #require(enCurso.pid)))
        await host.avisar()
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(e.claude.llamadas == 1)
        #expect(try e.estado().ejecuciones(estados: [.pendiente, .enCola]).count == 1)
        await host.parar()
    }

    @Test("Pedir a un asistente (acción rápida) y contestar su pregunta por la ficha de la pregunta")
    func pedirYContestarEnLaFicha() async throws {
        let e = EntornoMotor(inicio: DisparosTests.fecha(20, 16))
        defer { e.limpiar() }
        let pregunta = e.tarea(9, titulo: "Pregunta precio", responsable: "Manu", estado: "En revisión")
        e.claude.stream([Flujo.inicio(), Flujo.herramienta("tls_preguntar", id: "p"),
                         Flujo.resultadoHerramienta(id: "p", texto: "{\"ruta\":\"\(pregunta.raw)\"}"), Flujo.resultado("Pregunto.")],
                        llamada: 1)
        e.claude.stream(Flujo.exito("Seguí con tu respuesta."), llamada: 2)
        let host = try e.host(leerEventos: false)
        await host.revisar()
        let ej = try #require(try await host.pedir(a: "comercial", instruccion: "Prepara la propuesta para Cliente Ejemplo", pantalla: "Ventas"))
        await host.cola.procesar()
        #expect(try e.estado().ejecucion(ej.id)?.estado == .esperandoRespuesta)
        #expect(e.claude.texto("stdin-1.txt").contains("Prepara la propuesta para Cliente Ejemplo"))
        // Manu contesta escribiendo en la ficha de la pregunta (en Obsidian).
        e.escribir(pregunta.raw, e.leer(pregunta.raw) + "\n150 € y sin descuento.\n")
        let nuevas = await host.revisar()
        #expect(nuevas.map(\.disparo.tipo) == [.respuesta])
        await host.cola.procesar()
        #expect(e.claude.texto("stdin-2.txt").contains("150 € y sin descuento."))
        #expect(e.claude.valor("--resume", llamada: 2) == e.claude.valor("--session-id", llamada: 1))
        #expect(await host.revisar().isEmpty)
    }
}
