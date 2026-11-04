import Foundation
import OSLog
import TLSAgents
import TLSCore
import TLSMCPHost

// F4 · integración. Lo que el servidor de herramientas (`tls-mcp`) pide al motor de la carpeta (`AgentHost`):
// `tls_delegar`, `tls_preguntar`, `tls_finalizar` y `tls_avisar`. El motor también se entera por el stream; esto es
// para que lo sepa en el momento. `tls_avisar` pasa por el presupuesto de interrupciones del gobierno: lo rojo, como
// mucho 2 al día por asistente; lo demás, solo dentro del tope del día (`avisos.tope_notificaciones_no_rojas_dia`, 3);
// si no, al resumen.

/// `ServiciosDeEjecucion` sobre el `AgentHost` de la carpeta. El host se pone después de crearlo (el host necesita la
/// puerta, la puerta el servidor y el servidor estos servicios).
public final class ServiciosDelMotor: ServiciosDeEjecucion, @unchecked Sendable {
    private let lock = NSLock()
    private var _host: AgentHost?
    let estado: EstadoGobierno?
    let tope: @Sendable () -> Int
    let hoy: @Sendable () -> LocalDate
    /// Lo que sale ya (texto, rojo): la ventana de la empresa y, si la persona lo quiere, un aviso del Mac.
    let alAvisar: @Sendable (AvisoDeAsistente) -> Void

    public init(estado: EstadoGobierno?, tope: @escaping @Sendable () -> Int = { AvisosConfig().topeNotificacionesNoRojasDia },
                hoy: @escaping @Sendable () -> LocalDate = { LocalDate.today() },
                alAvisar: @escaping @Sendable (AvisoDeAsistente) -> Void = { _ in }) {
        self.estado = estado; self.tope = tope; self.hoy = hoy; self.alAvisar = alAvisar
    }

    public var host: AgentHost? {
        get { lock.withLock { _host } }
        set { lock.withLock { _host = newValue } }
    }

    public func delegar(_ d: Delegacion) async {
        await host?.delegar(tarea: d.tarea, profundidad: d.profundidad)
    }

    public func esperarRespuesta(_ e: EsperaDeRespuesta) async {
        await host?.esperarRespuesta(ejecucion: e.ejecucion, pregunta: e.pregunta.raw)
    }

    public func finalizar(_ f: FinDeEjecucion) async {
        await host?.finalizar(ejecucion: f.ejecucion, resumen: f.resumen)
    }

    /// F4 · corrector (R12): avisos «rojos» de un mismo asistente que salen al día. El nivel lo elige el asistente (o
    /// un texto inyectado que se lo pida): sin tope, bastaría decir «rojo» para saltarse el presupuesto de
    /// interrupciones. Los que pasan del tope van al resumen, como los demás.
    public static let topeRojosPorAsistenteDia = 2

    public func avisar(_ a: AvisoDeAsistente) async -> Bool {
        let rojo = a.nivel == .rojo
        let prefijo = "aviso:\(a.asistente):"
        let id = prefijo + "\(a.ejecucion):\(ContentHash.of(Data(a.texto.utf8)).prefix(12))"
        if let estado {
            if (try? estado.yaNotificada(id)) == true { return true }
            let dia = hoy()
            if rojo {
                if ((try? estado.notificadasRojas(dia, prefijo: prefijo)) ?? 0) >= Self.topeRojosPorAsistenteDia { return false }
            } else if ((try? estado.notificadasNoRojas(dia)) ?? 0) >= tope() {
                return false
            }
            _ = try? estado.marcarNotificada(id, roja: rojo, hoy: dia)
        } else if rojo {
            // Sin estado no se puede contar: lo rojo de un asistente no sale como rojo.
            return false
        }
        alAvisar(a)
        return true
    }
}

/// La auditoría de `tls-mcp` en la app: cada llamada (también las denegadas y lo «no encontrado») queda en el registro
/// del sistema, sin contenido ni rutas privadas, y las últimas en memoria. La auditoría de las decisiones es la del
/// `Autorizador` (`estado.sqlite.auditoria`).
public final class AuditoriaDeLaApp: RegistroDeAuditoria, @unchecked Sendable {
    private let lock = NSLock()
    private var _eventos: [EventoDeAuditoria] = []
    private let maximo: Int
    private static let log = Logger(subsystem: "es.thelast.system", category: "tls-mcp")

    public init(maximo: Int = 500) { self.maximo = maximo }

    public func registrar(_ e: EventoDeAuditoria) {
        lock.withLock {
            _eventos.append(e)
            if _eventos.count > maximo { _eventos.removeFirst(_eventos.count - maximo) }
        }
        Self.log.info("\(e.asistente ?? "?", privacy: .public) \(e.accion, privacy: .public) → \(e.veredicto, privacy: .public)")
    }

    public var eventos: [EventoDeAuditoria] { lock.withLock { _eventos } }
}
