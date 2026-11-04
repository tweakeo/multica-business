import Foundation
import TLSCore

/// Una entrada de auditoría del servidor de herramientas (conexiones rechazadas, tokens no válidos, lecturas de lo
/// privado respondidas con «no encontrado», acciones denegadas). Las decisiones del `Autorizador` las audita él
/// mismo (`estado.sqlite.auditoria`); esto es lo que solo ve el transporte.
public struct EventoDeAuditoria: Sendable, Hashable {
    public var fecha: Date
    public var ejecucion: String?
    public var asistente: String?
    /// `conexion`, `saludo`, `leer`, `herramienta:<nombre>`…
    public var accion: String
    public var ruta: String?
    /// `rechazado`, `no_encontrado`, `denegado`, `permitido`, `aprobacion_requerida`…
    public var veredicto: String
    public var motivo: String?

    public init(fecha: Date = Date(), ejecucion: String? = nil, asistente: String? = nil, accion: String,
                ruta: String? = nil, veredicto: String, motivo: String? = nil) {
        self.fecha = fecha; self.ejecucion = ejecucion; self.asistente = asistente; self.accion = accion
        self.ruta = ruta; self.veredicto = veredicto; self.motivo = motivo
    }
}

/// Dónde se guarda la auditoría. La integración lo conecta con la del gobierno (`estado.sqlite.auditoria`).
public protocol RegistroDeAuditoria: Sendable {
    func registrar(_ evento: EventoDeAuditoria)
}

/// Auditoría en memoria (pruebas y mientras no haya otra).
public final class AuditoriaEnMemoria: RegistroDeAuditoria, @unchecked Sendable {
    private let lock = NSLock()
    private var _eventos: [EventoDeAuditoria] = []

    public init() {}

    public func registrar(_ evento: EventoDeAuditoria) {
        lock.withLock { _eventos.append(evento) }
    }

    public var eventos: [EventoDeAuditoria] { lock.withLock { _eventos } }
}
