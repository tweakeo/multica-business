import Foundation
import TLSCore

// Lo que el servidor de herramientas pide fuera de la carpeta: al motor (cola de ejecuciones) y al gobierno
// (aprobaciones y propuestas en `estado.sqlite`). La integración conecta cada protocolo con lo suyo; las versiones
// «en memoria» sirven para las pruebas y como reserva.

/// `tls_delegar`: el coordinador encarga algo a otro asistente.
public struct Delegacion: Sendable, Hashable {
    public var de: String
    public var a: String
    /// Ficha de tarea creada para el encargo (`responsable: agente:<a>`, `Por hacer`).
    public var tarea: VaultPath
    /// Profundidad que tendrá la ejecución delegada (≤ 2).
    public var profundidad: Int
    public var ejecucion: String
}

/// `tls_preguntar`: la ejecución queda «esperando respuesta» hasta que contestes la pregunta.
public struct EsperaDeRespuesta: Sendable, Hashable {
    public var ejecucion: String
    public var asistente: String
    public var pregunta: VaultPath
    public var preguntaID: String
}

/// `tls_finalizar`: cierre obligatorio. El motor (`ActivityWriter`) escribe la Actividad y la Bitácora con esto.
public struct FinDeEjecucion: Sendable, Hashable {
    public var ejecucion: String
    public var asistente: String
    public var resumen: String
    /// Estado en que propone dejar su tarea (`En revisión` por defecto; nunca Hecha ni Cancelada).
    public var estadoTarea: EstadoTarea
    public var tarea: VaultPath?
}

/// `tls_avisar`: aviso para ti (cuenta para el presupuesto de interrupciones).
public struct AvisoDeAsistente: Sendable, Hashable {
    public enum Nivel: String, Sendable, Hashable, CaseIterable { case info, atencion, rojo }
    public var ejecucion: String
    public var asistente: String
    public var texto: String
    public var nivel: Nivel
    public var ruta: VaultPath?
}

/// El motor de ejecuciones (TLSAgents) visto desde las herramientas.
public protocol ServiciosDeEjecucion: Sendable {
    func delegar(_ d: Delegacion) async
    func esperarRespuesta(_ e: EsperaDeRespuesta) async
    func finalizar(_ f: FinDeEjecucion) async
    /// Devuelve `true` si el aviso sale ya; `false` si va al resumen (presupuesto agotado).
    func avisar(_ a: AvisoDeAsistente) async -> Bool
}

/// Petición de aprobación de una acción externa sobre un borrador.
public struct SolicitudDeAccion: Sendable, Hashable {
    public var accion: String
    public var borrador: VaultPath
    public var borradorID: String
    public var autor: Autor
    public var ejecucion: String
    /// F5 · pasarela: `ext_<servidor>_<herramienta>` cuando lo que se pide es usar otro programa (entra en la huella).
    public var herramienta: String? = nil
}

/// El `ApprovalStore` del gobierno visto desde las herramientas: registra la petición (atada al hash del borrador)
/// y devuelve su id. **Nunca ejecuta nada**: al aprobar, ejecuta la app.
public protocol SolicitudesDeAprobacion: Sendable {
    func solicitar(_ s: SolicitudDeAccion) async throws -> String
}

/// Propuesta de cambio de un asistente (`tls_proponer`, o una acción de dominio en modo asistido): una tarjeta 1-3-1 y
/// el plan que se aplicará **como persona** si eliges esa opción (`estado.sqlite.propuestas`).
public struct PropuestaDeAsistente: Sendable {
    public var tarjeta: VaultPath
    public var plan: WritePlan?
    public var autor: Autor
    public var ejecucion: String
    public var resumen: String
    /// Función que gobierna lo propuesto (modo asistido), si la hay.
    public var capacidad: String?

    public init(tarjeta: VaultPath, plan: WritePlan?, autor: Autor, ejecucion: String, resumen: String, capacidad: String? = nil) {
        self.tarjeta = tarjeta; self.plan = plan; self.autor = autor; self.ejecucion = ejecucion; self.resumen = resumen
        self.capacidad = capacidad
    }
}

public protocol AlmacenDePropuestas: Sendable {
    func guardar(_ p: PropuestaDeAsistente) async throws -> String
    /// Tarjeta de una propuesta aún sin decidir cuyo plan lleva este `origen` (para no proponer dos veces lo mismo).
    func pendiente(conOrigen origen: String) async -> VaultPath?
}

extension WritePlan {
    /// `true` si alguna ficha que crea o cambia el plan lleva `origen` (como texto o como propiedad).
    func llevaOrigen(_ origen: String) -> Bool {
        ops.contains { op in
            switch op {
            case .create(_, let data): String(decoding: data, as: UTF8.self).contains(origen)
            case .mergeFrontmatter(_, let set, _): set.contains { $0.value.displayText == origen }
            case .insertCSVRows(_, let rows, _): rows.contains { $0.values.contains(origen) }
            case .appendToSection(_, _, let t, _), .appendLine(_, let t): t.contains(origen)
            default: false
            }
        }
    }
}

// MARK: En memoria

/// Motor de mentira: apunta lo que le piden.
public final class ServiciosEnMemoria: ServiciosDeEjecucion, @unchecked Sendable {
    private let lock = NSLock()
    private var _delegaciones: [Delegacion] = []
    private var _esperas: [EsperaDeRespuesta] = []
    private var _fines: [FinDeEjecucion] = []
    private var _avisos: [AvisoDeAsistente] = []

    public init() {}

    public func delegar(_ d: Delegacion) async { lock.withLock { _delegaciones.append(d) } }
    public func esperarRespuesta(_ e: EsperaDeRespuesta) async { lock.withLock { _esperas.append(e) } }
    public func finalizar(_ f: FinDeEjecucion) async { lock.withLock { _fines.append(f) } }
    public func avisar(_ a: AvisoDeAsistente) async -> Bool { lock.withLock { _avisos.append(a) }; return true }

    public var delegaciones: [Delegacion] { lock.withLock { _delegaciones } }
    public var esperas: [EsperaDeRespuesta] { lock.withLock { _esperas } }
    public var fines: [FinDeEjecucion] { lock.withLock { _fines } }
    public var avisos: [AvisoDeAsistente] { lock.withLock { _avisos } }
}

/// Aprobaciones en memoria (una por borrador: la nueva sustituye a la anterior).
public final class AprobacionesEnMemoria: SolicitudesDeAprobacion, @unchecked Sendable {
    private let lock = NSLock()
    private var _solicitudes: [String: SolicitudDeAccion] = [:]

    public init() {}

    public func solicitar(_ s: SolicitudDeAccion) async throws -> String {
        let id = "apr-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8))
        lock.withLock {
            _solicitudes = _solicitudes.filter { $0.value.borradorID != s.borradorID }
            _solicitudes[id] = s
        }
        return id
    }

    public var solicitudes: [String: SolicitudDeAccion] { lock.withLock { _solicitudes } }
}

/// Propuestas en memoria.
public final class PropuestasEnMemoria: AlmacenDePropuestas, @unchecked Sendable {
    private let lock = NSLock()
    private var _propuestas: [String: PropuestaDeAsistente] = [:]

    public init() {}

    public func guardar(_ p: PropuestaDeAsistente) async throws -> String {
        let id = "prop-" + String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8))
        lock.withLock { _propuestas[id] = p }
        return id
    }

    public var propuestas: [String: PropuestaDeAsistente] { lock.withLock { _propuestas } }

    public func pendiente(conOrigen origen: String) async -> VaultPath? {
        lock.withLock { _propuestas.values.first { $0.plan?.llevaOrigen(origen) == true }?.tarjeta }
    }
}
