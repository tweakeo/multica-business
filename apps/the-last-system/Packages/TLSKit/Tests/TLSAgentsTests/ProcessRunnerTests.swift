import Darwin
import Foundation
import Testing
@testable import TLSAgents

@Suite struct ProcessRunnerTests {
    @Test func entornoExactoYLineas() async throws {
        let lineas = Lineas()
        let out = try await ProcessRunner.run(ProcessSpec(
            executable: "/usr/bin/env", environment: ["A": "1", "PATH": "/usr/bin:/bin"], timeout: 10)) {
            lineas.add($0); return .seguir
        }
        #expect(out.status == 0)
        #expect(Set(lineas.all) == ["A=1", "PATH=/usr/bin:/bin"])
        #expect(!out.timedOut && !out.stoppedByCaller)
    }

    @Test func stdinSeEscribeYSeCierra() async throws {
        let out = try await ProcessRunner.run(ProcessSpec(executable: "/bin/cat", stdin: Data("hola\nadiós".utf8), timeout: 10))
        #expect(out.stdoutText == "hola\nadiós")
    }

    /// Parar desde el lector termina el grupo entero, también los hijos (como `tls-mcp`).
    @Test func pararDesdeElLectorMataAlGrupo() async throws {
        let inicio = Date()
        let out = try await ProcessRunner.run(ProcessSpec(
            executable: "/bin/sh", arguments: ["-c", "/bin/sleep 60 & echo uno; echo dos; wait"],
            environment: ["PATH": "/usr/bin:/bin"], timeout: 30, grace: 1)) { linea in
            String(decoding: linea, as: UTF8.self) == "uno" ? .terminar : .seguir
        }
        #expect(out.stoppedByCaller)
        #expect(out.signal == SIGTERM)
        // Solo tarda décimas; con todo el paquete en paralelo se ha visto en 10,06 s. Lo que importa es que no
        // espera al `sleep 60` ni al tiempo máximo (30 s).
        #expect(Date().timeIntervalSince(inicio) < 20)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!ProcessRunner.groupAlive(out.pid), "el sleep hijo debe haber muerto")
    }

    @Test func topeDeTiempo() async throws {
        let out = try await ProcessRunner.run(ProcessSpec(executable: "/bin/sleep", arguments: ["30"], timeout: 0.5, grace: 1))
        #expect(out.timedOut)
        #expect(out.status == 128 + SIGTERM)
    }

    /// Cancelar la tarea para el grupo (PLAN: «Cancelar. SIGTERM al grupo, SIGKILL a los 5 s»).
    @Test func cancelarParaElGrupo() async throws {
        let inicio = Date()
        let tarea = Task {
            try await ProcessRunner.run(ProcessSpec(
                executable: "/bin/sh", arguments: ["-c", "/bin/sleep 60 & /bin/sleep 60; wait"],
                environment: ["PATH": "/usr/bin:/bin"], timeout: 30, grace: 1))
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        tarea.cancel()
        let out = try await tarea.value
        #expect(out.cancelled && !out.timedOut && !out.stoppedByCaller)
        // Igual que arriba: bajo carga se ha visto en 10,9 s y 18 s; lo que importa es no llegar a los 30 ni a los 60.
        #expect(Date().timeIntervalSince(inicio) < 25)
        #expect(!ProcessRunner.groupAlive(out.pid))
    }

    /// Un hijo que ignora SIGTERM y sigue tras salir el principal acaba con SIGKILL.
    @Test func huerfanoTerco() async throws {
        let inicio = Date()
        let out = try await ProcessRunner.run(ProcessSpec(
            executable: "/bin/sh", arguments: ["-c", "(trap '' TERM; exec /bin/sleep 60) >/dev/null 2>&1 & echo listo"],
            environment: ["PATH": "/usr/bin:/bin"], timeout: 30, grace: 1))
        #expect(out.status == 0 && out.stdoutText == "listo\n")
        #expect(!ProcessRunner.groupAlive(out.pid))
        // Solo, tarda décimas; con todo el paquete en paralelo se ha visto en 5,6 s. Lo que importa es que no
        // espera al `sleep 60` del hijo ni al tiempo máximo (30 s).
        #expect(Date().timeIntervalSince(inicio) < 20)
    }

    @Test func ejecutableInexistente() async {
        await #expect(throws: ProcessError.self) {
            try await ProcessRunner.run(ProcessSpec(executable: "/no/existe", timeout: 5))
        }
    }

    final class Lineas: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []
        func add(_ d: Data) { lock.withLock { items.append(String(decoding: d, as: UTF8.self)) } }
        var all: [String] { lock.withLock { items } }
    }
}
