import Foundation
import Observation
import TLSAgents
import TLSCore

// F4 · rol asistentes (PLAN §6.4, §6.5, §6.1). Lo que las pantallas de asistentes necesitan de la app y que solo la
// integración puede dar: el motor de la carpeta (`AgentHost`), su estado en vivo (`EstadoEnVivo`) y cómo abrir ⌘J con
// un asistente. Sin conexión (antes de la integración, en solo lectura o sin Claude), las pantallas leen lo que hay en
// disco —configuración, Bitácora y el estado del motor— y lo dicen; nunca inventan un estado.

/// Los asistentes de una empresa abierta, tal como los conecta la app. Una por `VaultSession`.
@MainActor
public final class ConexionAsistentes {
    /// El motor de esta carpeta (`nil` sin escritor o sin Claude; en la demo, el de `SimulatedRuntime`).
    public let host: AgentHost?
    /// Lo que pasa ahora (en cola, «Leyendo…», esperando tu respuesta). El mismo objeto que recibe el motor.
    public let enVivo: EstadoEnVivo
    /// Abre ⌘J con un asistente y el contexto de la pantalla (lo pone ⌘J). `nil`: la ficha ofrece «Pedir algo» en una
    /// hoja que encola la petición en el motor.
    public var abrirChat: (@MainActor (_ asistente: String, _ contexto: String?) -> Void)?
    /// Tras cambiar la configuración desde estas pantallas (interruptor, pausa por área, ficha de un asistente), además
    /// de `host.ajustesCambiaron()`: lo que la integración necesite (al apagar, revocar los permisos de `tls-mcp`).
    public var alCambiarAjustes: (@MainActor (_ interruptorApagado: Bool) async -> Void)?
    /// F4 · integración: por qué no hay motor en esta empresa (Claude Code no está, o no tiene la sesión iniciada), en
    /// palabras de persona y con lo que hay que hacer. `nil` si hay motor (o si es el ejemplo, que va simulado).
    public var sinMotor: String?
    /// F4 · integración: vuelve a buscar Claude Code y, si ya está, monta el motor de esta empresa.
    public var reintentar: (@MainActor () async -> Void)?

    public init(host: AgentHost? = nil, enVivo: EstadoEnVivo? = nil,
                abrirChat: (@MainActor (_ asistente: String, _ contexto: String?) -> Void)? = nil,
                alCambiarAjustes: (@MainActor (_ interruptorApagado: Bool) async -> Void)? = nil,
                sinMotor: String? = nil, reintentar: (@MainActor () async -> Void)? = nil) {
        self.host = host
        self.enVivo = enVivo ?? EstadoEnVivo()
        self.abrirChat = abrirChat
        self.alCambiarAjustes = alCambiarAjustes
        self.sinMotor = sinMotor
        self.reintentar = reintentar
    }

    /// Avisa al motor de que cambió la configuración (y a la integración).
    func ajustesCambiaron(interruptorApagado: Bool) async {
        await host?.ajustesCambiaron()
        await alCambiarAjustes?(interruptorApagado)
    }
}

/// Las conexiones de las empresas abiertas. Es observable: si la integración conecta una empresa cuando sus
/// pantallas ya están a la vista, se enteran solas.
///
/// Uso (integración, al abrir una empresa con escritor): `RegistroDeAsistentes.compartido.conectar(ConexionAsistentes(
/// host: host, enVivo: enVivo), a: sesion)`; al cerrarla, `desconectar(sesion)`.
@MainActor
@Observable
public final class RegistroDeAsistentes {
    public static let compartido = RegistroDeAsistentes()

    private final class Entrada {
        weak var sesion: VaultSession?
        let conexion: ConexionAsistentes
        init(_ sesion: VaultSession, _ conexion: ConexionAsistentes) { self.sesion = sesion; self.conexion = conexion }
    }

    private var entradas: [ObjectIdentifier: Entrada] = [:]

    public init() {}

    public func conectar(_ conexion: ConexionAsistentes, a sesion: VaultSession) {
        entradas = entradas.filter { $0.value.sesion != nil }
        entradas[ObjectIdentifier(sesion)] = Entrada(sesion, conexion)
    }

    public func desconectar(_ sesion: VaultSession) {
        entradas[ObjectIdentifier(sesion)] = nil
    }

    /// La conexión de la empresa, si la integración la puso.
    public func conexion(de sesion: VaultSession) -> ConexionAsistentes? {
        guard let e = entradas[ObjectIdentifier(sesion)], e.sesion === sesion else { return nil }
        return e.conexion
    }
}
