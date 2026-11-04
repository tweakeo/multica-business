import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// Revisión adversarial de F4 (rol revisión-seguridad): la cola del motor. Sin Claude: un runtime que solo cuenta y el
/// `claude` falso de `MotorApoyo`. Los fallos se corrigieron en el corrector final de F4: las pruebas quedan como regresión.
@Suite("Revisión F4 · motor", .serialized)
struct RevisionF4MotorTests {
    /// Runtime que no lanza nada: apunta cuántas veces se le pidió lanzar.
    final class RuntimeQueCuenta: AgentRuntime, @unchecked Sendable {
        let simulado = false
        private let lock = NSLock()
        private var _llamadas = 0
        var llamadas: Int { lock.withLock { _llamadas } }

        func ejecutar(_ p: PeticionDeEjecucion, alEvento: @escaping @Sendable (AgentEvent) -> Void,
                      alArrancar: @escaping @Sendable (Int32) -> Void) async -> ResultadoDeEjecucion {
            lock.withLock { _llamadas += 1 }
            return ResultadoDeEjecucion(estado: .completada, resumen: "Hecho.", finalizo: true)
        }
    }

    /// Para la preparación de un trabajo (el «¿hace falta?» de antes de lanzar) hasta que la prueba la suelte.
    final class Compuerta: @unchecked Sendable {
        private let lock = NSLock()
        private var _dentro = false
        private var abierta = false
        private var continuacion: CheckedContinuation<Void, Never>?
        var dentro: Bool { lock.withLock { _dentro } }

        func esperar() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                let ya = lock.withLock { () -> Bool in
                    _dentro = true
                    if abierta { return true }
                    continuacion = c
                    return false
                }
                if ya { c.resume() }
            }
        }

        func abrir() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                abierta = true
                defer { continuacion = nil }
                return continuacion
            }
            c?.resume()
        }
    }

    static func cola(_ e: EntornoMotor, runtime: any AgentRuntime, compuerta: Compuerta) throws -> ColaDeEjecuciones {
        ColaDeEjecuciones(.init(
            estadoDeCarpeta: e.estadoDir, raiz: e.raiz, estado: try e.estado(), runtime: runtime, servidor: e.puerta,
            registro: e.registro, ajustes: AjustesConCierre { e.ajustes }, catalogo: EntornoMotor.catalogo, reloj: e.reloj,
            foto: e.foto, antesDeLanzar: { _, _ in
                await compuerta.esperar()
                return .lanzar([:])
            }, empresa: "Empresa Ejemplo", tiempoMaximo: 60))
    }

    // MARK: R5 · Apagar o cerrar mientras se prepara un trabajo

    /// `cancelarEnCurso` solo para lo que ya está en `enCurso`, que se rellena **después** de preparar (¿hace falta?,
    /// foto, brief, token). Si la persona apaga el interruptor (o cierra la empresa, o sale) en ese hueco, el trabajo se
    /// lanza igual, con un token nuevo emitido después de `revocarTodos()`, y nadie lo para: ni en ≤ 5 s ni al salir.
    @Test("R5 · Apagar el interruptor mientras se prepara un trabajo no impide que se lance")
    func apagarMientrasSePrepara() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let runtime = RuntimeQueCuenta()
        let compuerta = Compuerta()
        let cola = try Self.cola(e, runtime: runtime, compuerta: compuerta)
        _ = try #require(try await cola.encolar(Disparo.accion(agente: "comercial", instruccion: "Prepara el seguimiento.")))
        let proceso = Task { await cola.procesar() }
        #expect(await esperarA(5) { compuerta.dentro })

        // Lo que hace `AgentHost.ajustesCambiaron()` al apagar: no sale nada más y se para lo que esté en marcha.
        e.ajustes = AjustesDeAsistentes.leer(yaml: EntornoMotor.configBase
            .replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado"))
        await cola.cancelarEnCurso(nota: "Asistentes en pausa.")
        compuerta.abrir()
        await proceso.value

        // Corregido (corrector final F4): R5: cancelarEnCurso no ve el trabajo que se está preparando y ejecutar no vuelve a mirar el interruptor
        do {
            #expect(runtime.llamadas == 0, "se lanzó con el interruptor apagado")
            #expect(e.puerta.abiertas.isEmpty, "se emitió un token después de apagar")
        }
    }

    @Test("R5 · Cerrar la carpeta (detener, cancelar, esperar) mientras se prepara: el trabajo se lanza después")
    func pararMientrasSePrepara() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let runtime = RuntimeQueCuenta()
        let compuerta = Compuerta()
        let cola = try Self.cola(e, runtime: runtime, compuerta: compuerta)
        _ = try #require(try await cola.encolar(Disparo.accion(agente: "comercial", instruccion: "Prepara el seguimiento.")))
        let proceso = Task { await cola.procesar() }
        #expect(await esperarA(5) { compuerta.dentro })

        // La secuencia de `AgentHost.parar()` (con una espera corta en vez de 15 s).
        await cola.detener()
        await cola.cancelarEnCurso(nota: "Se cerró la carpeta.")
        await cola.esperarEnCurso(maximo: 0.3)
        let lanzadasAlCerrar = runtime.llamadas
        compuerta.abrir()
        await proceso.value

        #expect(lanzadasAlCerrar == 0)
        // Corregido (corrector final F4): R5: tras «parar», el trabajo que se preparaba se lanza igual (proceso vivo al salir)
        do {
            #expect(runtime.llamadas == 0, "se lanzó después de cerrar la carpeta")
        }
    }

    // MARK: R10 · `recuperar()` y los pid reutilizados

    final class PidCaja: @unchecked Sendable {
        private let lock = NSLock()
        private var _valor: Int32?
        var valor: Int32? { lock.withLock { _valor } }
        func poner(_ p: Int32) { lock.withLock { _valor = p } }
    }

    /// Al arrancar, lo que quedó «en curso» con un pid se para si el ejecutable de ese pid acaba en `/claude` (o tiene
    /// `/claude/` en la ruta, como `~/.local/share/claude/versions/…`). No se mira cuándo empezó ese proceso: si la app
    /// se cerró de golpe y el número lo reutilizó después una sesión de Claude Code de la persona, se para su grupo.
    @Test("R10 · recuperar() para un «claude» que empezó después del trabajo apuntado (pid reutilizado)")
    func recuperarConPidReutilizado() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let dir = Apoyo.tempDir("rev-pid")
        defer { Apoyo.limpiar(dir) }
        // Un programa propio de la prueba que se llama `claude` (no es Claude: duerme 30 s).
        let ajeno = dir.appendingPathComponent("claude")
        let cc = try await ProcessRunner.run(ProcessSpec(
            executable: "/usr/bin/cc", arguments: ["-x", "c", "-", "-o", ajeno.path],
            stdin: Data("#include <unistd.h>\nint main(void){sleep(30);return 0;}\n".utf8), timeout: 60))
        try #require(cc.status == 0 && FileManager.default.isExecutableFile(atPath: ajeno.path))
        let caja = PidCaja()
        let proceso = Task {
            try await ProcessRunner.run(ProcessSpec(executable: ajeno.path, timeout: 40, grace: 1, alArrancar: { caja.poner($0) }))
        }
        #expect(await esperarA(5) { caja.valor != nil })
        let pid = try #require(caja.valor)

        // Una ejecución de hace dos días que quedó «en curso» con ese número de proceso.
        let estado = try e.estado()
        let hace2 = EntornoMotor.lunes9.addingTimeInterval(-2 * 86_400)
        var ej = try #require(try estado.encolar(Disparo.accion(agente: "comercial", instruccion: "x"), ahora: hace2, simulado: false))
        ej.estado = .enCurso
        ej.pid = pid
        ej.empezada = hace2
        try estado.guardar(ej)
        let cola = try e.cola(runtime: RuntimeQueCuenta(), estado: estado)
        await cola.recuperar()
        let sigueVivo = ProcessRunner.groupAlive(pid)
        // Corregido (corrector final F4): R10: esNuestro mira solo la ruta del ejecutable, no si el proceso empezó con ese trabajo
        do {
            #expect(sigueVivo, "recuperar() paró un proceso que no era de ese trabajo")
        }
        proceso.cancel()
        _ = try? await proceso.value
    }

    // MARK: R6 · El tope de uso con reintentos y trabajos sin `result`

    /// Cada intento recibe `--max-budget-usd` entero (no lo que queda del trabajo) y lo que gasta un intento que acaba sin
    /// `result` (sin resultado, tiempo agotado, cancelado) no se apunta en el uso del mes: el tope mensual no lo ve.
    @Test("R6 · Dos reintentos sin resultado: 3 × el tope del trabajo y nada apuntado en el mes")
    func topeConReintentos() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(), Flujo.texto("Empiezo y me quedo a medias…")])  // sin `result`
        e.claude.marcar("salida", "1")
        let cola = try e.cola(esperas: [0, 0])
        let ej = try #require(try await cola.encolar(Disparo.accion(agente: "comercial", instruccion: "Repasa el embudo.")))
        await cola.procesar()
        let fin = try #require(try e.estado().ejecucion(ej.id))
        #expect(fin.estado == .fallida && fin.motivo == .sinResultado)
        // Corregido: el primer intento contestó y no dijo cuánto gastó, así que cuenta su tope entero; no queda tope
        // del trabajo para reintentar (antes se lanzaba 3 veces con 0,5 USD cada una).
        #expect(e.claude.llamadas == 1)
        let topes = (1...e.claude.llamadas).compactMap { e.claude.valor("--max-budget-usd", llamada: $0).flatMap(Double.init) }
        let total = topes.reduce(0, +)
        let ledger = CostLedger(estado: try e.estado(), reloj: e.reloj, zona: e.zona)
        // Corregido (corrector final F4): R6: los reintentos no comparten el tope del trabajo y lo gastado sin `result` no cuenta en el mes
        do {
            #expect(total <= 0.5 + 1e-9, "topes por intento: \(topes)")
            #expect(ledger.usado(agente: "comercial") > 0, "tres procesos lanzados y el mes sigue a 0")
        }
    }
}
