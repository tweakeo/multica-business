import Foundation
import TLSAgents

/// Lo que devuelve `osascript -l JavaScript`.
public struct ResultadoJXA: Sendable, Hashable {
    public var salida: String
    public var errores: String
    public var estado: Int32
    public var tiempoAgotado: Bool

    public init(salida: String, errores: String = "", estado: Int32 = 0, tiempoAgotado: Bool = false) {
        self.salida = salida; self.errores = errores; self.estado = estado; self.tiempoAgotado = tiempoAgotado
    }

    /// macOS no deja a la app mandar Apple Events a Mail (Automatización denegada, -1743).
    public var automatizacionDenegada: Bool {
        estado != 0 && (errores.contains("-1743") || errores.localizedCaseInsensitiveContains("not authorized to send apple events")
                        || errores.localizedCaseInsensitiveContains("no está autorizado"))
    }

    /// Pide un permiso que aún no se ha dado (-1744): la app tiene que explicar y pedir antes.
    public var faltaConsentimiento: Bool { estado != 0 && errores.contains("-1744") }
}

/// Quien lanza los guiones JXA. **Solo la app** (fuera del sandbox de los asistentes, que niega `osascript`). En
/// pruebas, un doble que devuelve JSON sintético: nunca se automatiza Mail de verdad.
public protocol EjecutorJXA: Sendable {
    /// Lanza `guion` (JavaScript for Automation) con `argumentos` en `run(argv)` y espera como mucho `tope` segundos.
    func ejecutar(_ guion: String, argumentos: [String], tope: TimeInterval) async throws -> ResultadoJXA
}

/// Lo real: `/usr/bin/osascript -l JavaScript - <argumentos>` con el guion por la entrada estándar (los datos van como
/// argumentos, nunca pegados dentro del guion) y un tope de tiempo con parada del grupo de procesos.
public struct EjecutorJXAOsascript: EjecutorJXA {
    public static let osascript = "/usr/bin/osascript"

    public init() {}

    public func ejecutar(_ guion: String, argumentos: [String], tope: TimeInterval) async throws -> ResultadoJXA {
        let entorno = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "es_ES.UTF-8",
                       "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        let out = try await ProcessRunner.run(ProcessSpec(
            executable: Self.osascript, arguments: ["-l", "JavaScript", "-"] + argumentos, environment: entorno,
            directory: "/", stdin: Data(guion.utf8), timeout: tope, grace: 2, maxCapture: 2 << 20))
        return ResultadoJXA(salida: out.stdoutText, errores: out.stderrText, estado: out.status, tiempoAgotado: out.timedOut)
    }
}
