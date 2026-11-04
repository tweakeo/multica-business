import Darwin
import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// La cola de trabajos con un `claude` falso (PLAN §5.3 «Cola», §9 F4 criterios 4, 5, 6, 7 y 10).
@Suite("Motor · cola, reintentos, presupuesto, cancelación y reinicio", .serialized)
struct ColaTests {
    func disparoDeTarea(_ e: EntornoMotor, _ ruta: VaultPath, agente: String = "comercial") -> Disparo {
        Disparo.tareaLista(id: ruta.raw, ruta: ruta, hash: Disparo.huella(ruta.raw + "\(UUID())"), agente: agente, titulo: ruta.stem)
    }

    @Test("Idempotencia: el mismo disparo dos veces da una sola ejecución")
    func idempotencia() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let cola = try e.cola()
        let r = TLSAgents.RutinaDeAsistente(id: "algo-rojo", hora: 8, minuto: 45)
        let hueco = EntornoMotor.lunes9.addingTimeInterval(-15 * 60)
        let uno = try await cola.encolar(Disparo.rutina(r, agente: "mika", hueco: hueco, zona: e.zona))
        let dos = try await cola.encolar(Disparo.rutina(r, agente: "mika", hueco: hueco, zona: e.zona))
        #expect(uno != nil)
        #expect(dos == nil)
        #expect(try e.estado().ejecuciones().count == 1)
        #expect(uno?.disparo.clave == "rutina:mika.algo-rojo:2026-10-19T08:45")
    }

    @Test("Un trabajo que termina bien: completado, uso apuntado, token revocado y cierre apuntado una vez")
    func completado() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito("Dejé el seguimiento preparado.", coste: 0.04))
        let t = e.tarea(1, titulo: "Llamar a cliente")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, t)))
        await cola.procesar()
        let fin = try #require(try e.estado().ejecucion(ej.id))
        #expect(fin.estado == .completada)
        #expect(fin.resumen == "Dejé el seguimiento preparado.")
        #expect(abs(fin.costeUSD - 0.04) < 0.0001)
        #expect(e.claude.llamadas == 1)
        #expect(e.puerta.abiertas.map(\.ejecucion) == [ej.id])
        #expect(e.puerta.revocadas == [ej.id])
        #expect(e.registro.cierres.count == 1)
        #expect(e.registro.cierres.first?.estado == .completada)
        #expect(e.registro.cierres.first?.tarea == t)
        let usado = CostLedger(estado: try e.estado(), reloj: e.reloj, zona: e.zona).usado(agente: "comercial")
        #expect(abs(usado - 0.04) < 0.0001)
        // El crudo queda en stream.jsonl.
        let stream = try String(contentsOf: try AgentPaths(vaultState: e.estadoDir, slug: "comercial", runID: ej.id).stream, encoding: .utf8)
        #expect(stream.contains("tls_finalizar"))
    }

    @Test("Reintentos: salida sin result → 2 reintentos, a 1 y a 5 minutos, y después fallida")
    func reintentos() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        // Sin `result` y sin que el modelo llegara a contestar (se cortó al empezar): no gastó, así que se reintenta con
        // el tope del trabajo entero. Si hubiera contestado, contaría su tope y no habría reintento
        // (`RevisionF4MotorTests.topeConReintentos`).
        e.claude.stream([Flujo.inicio()])
        e.claude.marcar("salida", "1")
        let t = e.tarea(1, titulo: "Preparar algo")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, t)))
        await cola.procesar()
        var x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .pendiente)
        #expect(x.intento == 1)
        #expect(x.motivo == .sinResultado)
        #expect(x.noAntes == e.reloj.ahora().addingTimeInterval(60))
        #expect(x.sesionIniciada)
        // Antes del minuto no sale nada.
        e.reloj.avanzar(30)
        await cola.procesar()
        #expect(e.claude.llamadas == 1)
        e.reloj.avanzar(31)
        await cola.procesar()
        #expect(e.claude.llamadas == 2)
        x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.intento == 2)
        #expect(x.noAntes == e.reloj.ahora().addingTimeInterval(300))
        // El reintento reanuda la sesión que ya existía.
        #expect(e.claude.valor("--resume", llamada: 2) == x.sesion?.uuidString.lowercased())
        e.reloj.avanzar(301)
        await cola.procesar()
        #expect(e.claude.llamadas == 3)
        x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .fallida)
        #expect(x.motivo == .sinResultado)
        // No hay un cuarto intento.
        e.reloj.avanzar(3600)
        await cola.procesar()
        #expect(e.claude.llamadas == 3)
        #expect(e.registro.cierres.count == 1)
        #expect(e.registro.cierres.first?.motivo == .sinResultado)
    }

    @Test("Límite de uso: el reintento espera a que se libere")
    func limiteDeUso() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let libre = e.reloj.ahora().addingTimeInterval(2 * 3600)
        e.claude.stream([Flujo.inicio(), Flujo.limite(rechazado: true, hasta: libre),
                         Flujo.resultado("You've hit your usage limit", error: true, coste: 0, estadoAPI: 429)])
        let t = e.tarea(1, titulo: "Algo")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, t)))
        await cola.procesar()
        let x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .pendiente)
        #expect(x.motivo == .limiteUso)
        #expect(abs((x.noAntes ?? .distantPast).timeIntervalSince(libre)) < 1)
    }

    @Test("Presupuesto de la ejecución agotado: fallida(.presupuesto) sin reintentos (criterio 5)")
    func presupuestoDeEjecucion() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(), Flujo.resultado("", subtipo: "error_max_budget_usd", error: true, coste: 0.5)])
        let t = e.tarea(1, titulo: "Algo")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, t)))
        await cola.procesar()
        e.reloj.avanzar(3600)
        await cola.procesar()
        let x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .fallida)
        #expect(x.motivo == .presupuesto)
        #expect(x.intento == 0)
        #expect(e.claude.llamadas == 1)
    }

    @Test("Mes agotado: no se lanza, fallida(.presupuesto) y aviso; `--max-budget-usd` = min(ejecución, resto)")
    func mesAgotado() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let estado = try e.estado()
        let ledger = CostLedger(estado: estado, reloj: e.reloj, zona: e.zona)
        // Quedan 0,30 de 10: el tope de esta ejecución es 0,30 (no 0,50).
        try ledger.apuntar(ejecucion: "previa-1", agente: "comercial", usd: 9.7, simulado: false)
        let cola = try e.cola(estado: estado)
        let t1 = e.tarea(1, titulo: "Uno")
        _ = try await cola.encolar(disparoDeTarea(e, t1))
        await cola.procesar()
        #expect(e.claude.valor("--max-budget-usd", llamada: 1) == "0.3000")
        #expect(ledger.frase(try #require(e.ajustes.agente("comercial"))) == "uso del mes: 97 % de tu tope")
        // Ya no queda nada: no se lanza.
        try ledger.apuntar(ejecucion: "previa-2", agente: "comercial", usd: 1, simulado: false)
        let t2 = e.tarea(2, titulo: "Dos")
        let ej2 = try #require(try await cola.encolar(disparoDeTarea(e, t2)))
        await cola.procesar()
        let x = try #require(try estado.ejecucion(ej2.id))
        #expect(x.estado == .fallida && x.motivo == .presupuesto && x.intento == 0)
        #expect(e.claude.llamadas == 1)
        #expect(e.avisos.lista.contains(.mesAgotado(agente: "comercial")))
    }

    @Test("Guardia: una herramienta de más en el init para el trabajo (fallida(.guardia), sin reintentos y con aviso)")
    func guardia() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(herramientas: ["Bash", "mcp__tls__tls_leer"]), Flujo.resultado()])
        e.claude.marcar("colgar")
        let t = e.tarea(1, titulo: "Algo")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, t)))
        let inicio = Date()
        await cola.procesar()
        #expect(Date().timeIntervalSince(inicio) < 10)
        let x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .fallida && x.motivo == .guardia)
        #expect(e.claude.llamadas == 1)
        #expect(e.avisos.lista.contains { if case .guardia = $0 { true } else { false } })
    }

    @Test("Sin sesión de Claude: fallida(.sinSesion) sin reintentos")
    func sinSesion() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(), Flujo.resultado("Invalid API key · Please run /login", error: true, coste: 0, estadoAPI: 401)])
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Algo"))))
        await cola.procesar()
        e.reloj.avanzar(600)
        await cola.procesar()
        let x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .fallida && x.motivo == .sinSesion)
        #expect(e.claude.llamadas == 1)
    }

    @Test("Cancelar un trabajo en marcha: termina en 5 s o menos, cancelado y con el token revocado (criterio 4)")
    func cancelar() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(), Flujo.texto("Pensando mucho…")])
        e.claude.marcar("colgar")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Algo"))))
        let trabajo = Task { await cola.procesar() }
        #expect(await esperarA(10) { e.claude.llamadas == 1 && (try? e.estado().ejecucion(ej.id))?.pid != nil })
        let pid = try #require(try e.estado().ejecucion(ej.id)?.pid)
        let inicio = Date()
        await cola.cancelar(ej.id, nota: "Cancelado por Manu.")
        #expect(e.puerta.revocadas.contains(ej.id))
        await trabajo.value
        let duracion = Date().timeIntervalSince(inicio)
        #expect(duracion <= 5, "tardó \(duracion) s")
        let x = try #require(try e.estado().ejecucion(ej.id))
        #expect(x.estado == .cancelada)
        #expect(!ProcessRunner.groupAlive(pid))
        #expect(e.registro.cierres.last?.estado == .cancelada)
    }

    @Test("Cancelar a uno que ignora SIGTERM: SIGKILL a los 5 s")
    func cancelarTerco() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio()])
        e.claude.marcar("colgar")
        e.claude.marcar("terco")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Algo"))))
        let trabajo = Task { await cola.procesar() }
        #expect(await esperarA(10) { e.claude.llamadas == 1 && (try? e.estado().ejecucion(ej.id))?.pid != nil })
        try await Task.sleep(nanoseconds: 300_000_000)
        let pid = try #require(try e.estado().ejecucion(ej.id)?.pid)
        let inicio = Date()
        await cola.cancelar(ej.id)
        await trabajo.value
        let duracion = Date().timeIntervalSince(inicio)
        // SIGKILL a los 5 s; con todo el paquete en paralelo puede tardar algo más en recogerse.
        #expect(duracion >= 4.5 && duracion < 12, "tardó \(duracion) s")
        #expect(!ProcessRunner.groupAlive(pid))
        #expect(try e.estado().ejecucion(ej.id)?.estado == .cancelada)
    }

    @Test("Interruptor apagado: no sale nada de la cola; al encenderlo, sí (criterio 4)")
    func interruptor() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        e.ajustes.interruptor = false
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Algo"))))
        await cola.procesar()
        e.reloj.avanzar(3600)
        await cola.procesar()
        #expect(e.claude.llamadas == 0)
        #expect(try e.estado().ejecucion(ej.id)?.estado == .pendiente)
        e.ajustes.interruptor = true
        await cola.procesar()
        #expect(e.claude.llamadas == 1)
        #expect(try e.estado().ejecucion(ej.id)?.estado == .completada)
    }

    @Test("Área preparada o en reposo, o asistente inactivo: no se lanza (criterio 10)")
    func areaEnReposo() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let cola = try e.cola()
        let deMarca = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Pieza", area: .marca,
                                                                                   responsable: "agente:marca"), agente: "marca")))
        let deEntrega = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(2, titulo: "Kit", area: .entrega,
                                                                                     responsable: "agente:implementador"),
                                                                           agente: "implementador")))
        var a = e.ajustes
        a.agentes["contable"]?.activo = false
        e.ajustes = a
        let deContable = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(3, titulo: "Cuadrar", area: .finanzas,
                                                                                      responsable: "agente:contable"), agente: "contable")))
        await cola.procesar()
        #expect(e.claude.llamadas == 0)
        let estado = try e.estado()
        #expect(try estado.ejecucion(deMarca.id)?.estado == .cancelada)
        #expect(try estado.ejecucion(deMarca.id)?.nota == "Su área está en reposo.")
        #expect(try estado.ejecucion(deEntrega.id)?.estado == .cancelada)
        #expect(try estado.ejecucion(deContable.id)?.estado == .cancelada)
    }

    @Test("Área en pausa: lo suyo espera en la cola sin cancelarse")
    func pausaAreas() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        var a = e.ajustes
        a.pausaAreas = [.ventas]
        e.ajustes = a
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Algo"))))
        await cola.procesar()
        #expect(e.claude.llamadas == 0)
        #expect(try e.estado().ejecucion(ej.id)?.estado == .pendiente)
        a.pausaAreas = []
        e.ajustes = a
        await cola.procesar()
        #expect(try e.estado().ejecucion(ej.id)?.estado == .completada)
    }

    @Test("Una ejecución a la vez: tres en cola salen de una en una y en orden")
    func unaAlaVez() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let cola = try e.cola()
        var ids: [String] = []
        for n in 1...3 { ids.append(try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(n, titulo: "T\(n)")))).id) }
        await cola.procesar()
        #expect(e.claude.llamadas == 3)
        let estado = try e.estado()
        let empezadas = try ids.map { try #require(try estado.ejecucion($0)?.empezada) }
        let terminadas = try ids.map { try #require(try estado.ejecucion($0)?.terminada) }
        #expect(empezadas == empezadas.sorted())
        for i in 1..<3 { #expect(empezadas[i] >= terminadas[i - 1]) }
        // Al terminar, la tarea admite otro trabajo (con otra versión).
        #expect(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "T1"))) != nil)
    }

    @Test("Una tarea con un trabajo abierto no recibe otro")
    func tareaOcupada() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let cola = try e.cola()
        let t = e.tarea(1, titulo: "Algo")
        #expect(try await cola.encolar(disparoDeTarea(e, t)) != nil)
        #expect(try await cola.encolar(disparoDeTarea(e, t)) == nil)
    }

    @Test("Reiniciar con la cola llena no pierde ni duplica: lo en curso pasa a interrumpida (criterio 7)")
    func reinicioConColaLlena() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        var ids: [String] = []
        do {
            let cola = try e.cola()
            for n in 1...4 { ids.append(try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(n, titulo: "T\(n)")))).id) }
            // La primera quedó «en curso» con un proceso que ya no existe (la app se cerró de golpe).
            let estado = try e.estado()
            var x = try #require(try estado.ejecucion(ids[0]))
            x.estado = .enCurso
            x.pid = 999_999
            x.empezada = e.reloj.ahora()
            try estado.guardar(x)
        }
        // «Reinicio»: estado y cola nuevos sobre el mismo `estado.sqlite`.
        let estado = try e.estado()
        let cola = try e.cola(estado: estado)
        await cola.recuperar()
        let interrumpida = try #require(try estado.ejecucion(ids[0]))
        #expect(interrumpida.estado == .fallida && interrumpida.motivo == .interrumpida)
        #expect(e.registro.cierres.first?.motivo == .interrumpida)
        #expect(try estado.enEspera().map(\.id) == Array(ids.dropFirst()))
        await cola.procesar()
        #expect(e.claude.llamadas == 3)
        #expect(try ids.dropFirst().allSatisfy { try estado.ejecucion($0)?.estado == .completada })
        // Volver a recuperar y procesar no repite nada.
        await cola.recuperar()
        await cola.procesar()
        #expect(e.claude.llamadas == 3)
        #expect(try estado.ejecuciones().count == 4)
    }

    @Test("Terminado sin apuntar (la app se cerró justo después): se apunta al arrancar")
    func sinRegistrar() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let estado = try e.estado()
        let cola = try e.cola(estado: estado)
        let ej = try #require(try await cola.encolar(disparoDeTarea(e, e.tarea(1, titulo: "Algo"))))
        var x = ej
        x.estado = .completada
        x.resumen = "Hecho antes de cerrar."
        x.terminada = e.reloj.ahora()
        try estado.guardar(x)
        await cola.recuperar()
        #expect(e.registro.cierres.map(\.ejecucion) == [ej.id])
        #expect(try estado.ejecucion(ej.id)?.registrada == true)
    }
}
