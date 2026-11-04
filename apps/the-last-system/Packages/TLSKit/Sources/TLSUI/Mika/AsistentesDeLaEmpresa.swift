import Foundation
import Observation
import OSLog
import TLSAgents
import TLSCore
import TLSDesign

// F4 · rol mika. Lo de los asistentes de cada empresa abierta, para las pantallas (⌘J, Decisiones, Hoy, la barra de
// herramientas y la barra de menús). Uno por sesión, como `DominioEmpresa` y `AlmacenHoy`.
//
// - **Gobierno** (TLSCore): el `Autorizador` es **uno por carpeta** (PLAN §5.2). Si el bus ya tiene uno (lo puso la
//   integración), se usa ese; si no, se crea con el escritor y se le da al bus, para que todos (Decisiones, `tls-mcp`,
//   la cola y las reglas) usen el mismo. Con él, `Aprobaciones` y `EscrituraDeAsistente` (dos actores, uno por carpeta).
//   Sin escritor (solo lectura o la carpeta real) no hay gobierno: Decisiones enseña lo de F2 y no se aprueba nada.
// - **Motor** (TLSAgents): lo conecta la integración en `RegistroDeAsistentes` (rol asistentes: `AgentHost` y
//   `EstadoEnVivo`) y, para ⌘J, cómo se habla con Mika (`conectarChatDeMika`: Claude Code o la simulación de la demo).
//   Sin él, ⌘J contesta con el enrutador determinista (y lo dice) y «Responder» deja la respuesta en la ficha de la
//   pregunta, que el motor recoge al arrancar (un comentario tuyo en una pregunta que espera respuesta es la respuesta).
// - El interruptor es el del rol asistentes (`InterruptorGeneralAsistentes`); aquí solo se lee para los textos.

/// Cómo se habla con Mika: `SesionDeChat` (TLSAgents) o, en pruebas, uno falso. Nunca escribe en la carpeta: lo que
/// hace Mika con sus herramientas pasa por `tls-mcp` y el Autorizador.
public protocol CanalDeMika: Sendable {
    /// `chat-…`: las ejecuciones de este chat (y su auditoría) empiezan así.
    var id: String { get }
    func enviar(_ texto: String, pantalla: String?) async -> RespuestaDeChat
    func cerrar() async
}

extension SesionDeChat: CanalDeMika {}

/// Cómo se habla con Mika en una empresa: un chat nuevo cada vez que hace falta (Claude Code o la demo).
public typealias FabricaDeChatMika = @MainActor () -> any CanalDeMika

public extension VaultSession {
    /// F4 · integración: cómo se habla con Mika en esta empresa (`SesionDeChat` con Claude Code o, en la demo, con
    /// `simulacion`). `nil`: el enrutador de la app, sin Claude.
    func conectarChatDeMika(_ fabrica: FabricaDeChatMika?) {
        AsistentesDeLaEmpresa.de(self).fabricaDeChat = fabrica
    }

    /// F4 · El Autorizador único de esta carpeta (el del bus; si no tiene, lo crea y se lo da). `nil` sin escritor.
    func autorizadorDeLaCarpeta() -> Autorizador? {
        AsistentesDeLaEmpresa.de(self).autorizador
    }
}

/// Los asistentes de una empresa abierta: gobierno, motor y el interruptor.
@MainActor
@Observable
final class AsistentesDeLaEmpresa {
    /// `true` encendido, `false` en pausa, `nil` sin saber (sin escritor o aún leyendo).
    private(set) var encendidos: Bool?
    /// Cuántos asistentes trabajan (activos en la configuración que vale).
    private(set) var activos: [String] = []
    /// Cambia cada vez que se decide algo del gobierno (aprobar, confirmar permisos…), para refrescar lo que dependa.
    private(set) var revision = 0

    /// Cómo se habla con Mika (lo conecta la integración; `nil`: el enrutador, sin Claude).
    var fabricaDeChat: FabricaDeChatMika? {
        didSet { revision += 1; versionDelChat += 1 }
    }
    /// F4 · corrector: cambia cada vez que la integración conecta (o desconecta) el chat: ⌘J deja el que tenía y abre otro.
    private(set) var versionDelChat = 0

    @ObservationIgnored private weak var sesion: VaultSession?
    @ObservationIgnored private var gobierno: (bus: ObjectIdentifier, autorizador: Autorizador, aprobaciones: Aprobaciones,
                                               escritura: EscrituraDeAsistente)?
    private static let log = Logger(subsystem: "es.thelast.system", category: "Asistentes")

    private final class Entrada {
        weak var sesion: VaultSession?
        let valor: AsistentesDeLaEmpresa
        init(_ s: VaultSession, _ v: AsistentesDeLaEmpresa) { sesion = s; valor = v }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    static func de(_ sesion: VaultSession) -> AsistentesDeLaEmpresa {
        porSesion = porSesion.filter { $0.value.sesion != nil }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.valor }
        let v = AsistentesDeLaEmpresa(sesion: sesion)
        porSesion[k] = Entrada(sesion, v)
        return v
    }

    init(sesion: VaultSession?) { self.sesion = sesion }

    /// El motor de la carpeta y su estado en vivo (los conecta la integración en `RegistroDeAsistentes`).
    var host: AgentHost? { sesion.flatMap { RegistroDeAsistentes.compartido.conexion(de: $0)?.host } }
    var enVivo: EstadoEnVivo? { sesion.flatMap { RegistroDeAsistentes.compartido.conexion(de: $0)?.enVivo } }

    // MARK: Gobierno

    /// El Autorizador de la carpeta (uno solo: el del bus). `nil` sin escritor.
    var autorizador: Autorizador? { gobiernoActual()?.autorizador }
    var aprobaciones: Aprobaciones? { gobiernoActual()?.aprobaciones }
    var escritura: EscrituraDeAsistente? { gobiernoActual()?.escritura }

    private func gobiernoActual() -> (bus: ObjectIdentifier, autorizador: Autorizador, aprobaciones: Aprobaciones,
                                      escritura: EscrituraDeAsistente)? {
        guard let sesion, let bus = sesion.bus, let writer = sesion.writer else {
            gobierno = nil
            return nil
        }
        // El mismo bus y el mismo Autorizador que tiene el bus (si la integración pone otro, se usa ese: uno solo).
        if let g = gobierno, g.bus == ObjectIdentifier(bus), bus.autorizador.map({ $0 === g.autorizador }) ?? true { return g }
        let a: Autorizador
        if let ya = bus.autorizador {
            a = ya
        } else {
            let privado = sesion.service?.options.privado ?? []
            do {
                a = try Autorizador(writer: writer, opciones: .init(privado: privado))
            } catch {
                Self.log.error("No se pudo preparar el gobierno de los asistentes: \(error.localizedDescription, privacy: .public)")
                return nil
            }
            bus.establecerAutorizador(a)
        }
        let persona = sesion.persona
        // F5 · buzon-relevo: el correo y los otros programas de esta empresa (los conecta la integración en marcha).
        let ejecutor = ConexionesEnDecisiones.de(sesion).huecos.ejecutor
        let g = (ObjectIdentifier(bus), a, Aprobaciones(bus: bus, autorizador: a, ejecutor: ejecutor),
                 EscrituraDeAsistente(bus: bus, autorizador: a, persona: persona))
        gobierno = g
        return g
    }

    // MARK: Interruptor

    /// Vuelve a leer el interruptor y quién trabaja (la configuración que vale ahora: lo confirmado y, si es más
    /// estricto, lo de fuera).
    func actualizar() async {
        guard let a = autorizador else {
            encendidos = nil
            activos = []
            return
        }
        let efectiva = await Task.detached(priority: .utility) { a.estadoDeConfig().efectiva }.value
        encendidos = efectiva.encendido
        activos = efectiva.activos.map(\.slug).sorted()
    }

    /// Algo del gobierno cambió (se aprobó, se confirmaron permisos…): Hoy, Decisiones y la insignia, al momento.
    func cambio() async {
        revision += 1
        guard let sesion else { return }
        AlmacenRelaciones.de(sesion).invalidar()
        await AlmacenHoy.de(sesion).actualizar(forzar: true)
        await actualizar()
    }
}
