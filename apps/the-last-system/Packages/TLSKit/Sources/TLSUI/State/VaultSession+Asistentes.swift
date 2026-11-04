import Foundation
import TLSAgents
import TLSCore
import TLSDesign

// F4 · integración. Lo que la app (target `TLSIntegracion`) necesita de una empresa abierta para montar sus asistentes:
// el motor (`AgentHost`), el servidor de herramientas (`tls-mcp`) y el chat de Mika. Todo sale de la sesión: el mismo
// índice, el mismo escritor, el mismo `CommandBus` y **el mismo** `Autorizador` (PLAN §5.2: uno por carpeta), con sus
// `Aprobaciones` y su `EscrituraDeAsistente`. La sesión avisa a la integración cuando su escritor queda listo, cuando
// cambia la carpeta y antes de soltar el escritor (al cerrar o al pasar a solo lectura): así el motor se para antes de
// que el escritor se cierre.

/// Las piezas de una empresa abierta con escritor que usan los asistentes.
public struct PiezasDeLaEmpresa: Sendable {
    public let entry: VaultEntry
    public let root: URL
    public let service: VaultService
    public let bus: CommandBus
    /// `<ASUP>/<vault-id>` (el `stateDirectory` del escritor): `estado.sqlite`, `agentes/`, `ejecuciones/`.
    public let estadoDeCarpeta: URL
    /// El motor del dominio (eventos y reglas), el mismo que usa la persona.
    public let motorDominio: MotorDeDominio?
    public let autorizador: Autorizador
    public let aprobaciones: Aprobaciones
    public let escritura: EscrituraDeAsistente
    public let persona: String
    /// El día que fija la carpeta (`hoy:` de `.tls/config.yaml`; Ribera vive el 19 de octubre), si fija uno.
    public let hoyCarpeta: LocalDate?

    /// El ejemplo (Asesoría Ribera): los asistentes trabajan simulados.
    public var esEjemplo: Bool { entry.clase == .demo }

    /// Foto de la carpeta **con** lo privado (para filtrarlo) y sin lo que se dejó fuera de la copia.
    public var foto: @Sendable () async -> VaultSnapshot {
        let root = root, layout = service.layout
        let excluidas = entry.exclusionesCopia.map { VaultPath($0) }
        return { VaultSnapshot.read(root: root, layout: layout, excluded: excluidas) }
    }
}

/// La integración de los asistentes vista desde la sesión (la pone la app; en pruebas, una de prueba).
@MainActor
public protocol IntegracionDeEmpresas: AnyObject {
    /// El escritor de la empresa quedó listo (al abrir o al volver a permitir cambios).
    func escritorListo(_ sesion: VaultSession) async
    /// Antes de soltar el escritor (al cerrar la empresa o al pasarla a solo lectura): parar lo que dependa de él.
    func escritorSeVa(_ sesion: VaultSession) async
    /// La carpeta cambió (de fuera o por la app): rutas del lote (vacío = puede haber cambiado todo).
    func carpetaCambio(_ sesion: VaultSession, rutas: [VaultPath]) async
}

public extension AppModel {
    /// La integración de los asistentes de la app (la pone `TLSIntegracion` al arrancar). Cada sesión que abre este
    /// modelo la usa; `nil` (pruebas que no la usan): sin asistentes.
    var integracionDeAsistentes: (any IntegracionDeEmpresas)? {
        get { IntegracionDelModelo.de(self) }
        set { IntegracionDelModelo.poner(newValue, en: self) }
    }
}

public extension VaultSession {

    /// Las piezas para los asistentes, o `nil` sin escritor (solo lectura, la carpeta real o abriéndose).
    func piezasParaLosAsistentes() -> PiezasDeLaEmpresa? {
        guard let root, let service, let bus, let writer else { return nil }
        let a = AsistentesDeLaEmpresa.de(self)
        guard let autorizador = a.autorizador, let aprobaciones = a.aprobaciones, let escritura = a.escritura else { return nil }
        return PiezasDeLaEmpresa(entry: entry, root: root, service: service, bus: bus, estadoDeCarpeta: writer.stateDirectory,
                                 motorDominio: DominioEmpresa.motor(de: self), autorizador: autorizador,
                                 aprobaciones: aprobaciones, escritura: escritura, persona: persona, hoyCarpeta: hoyCarpeta)
    }

    /// Un aviso de los asistentes en la ventana (y, si la persona encendió los avisos del Mac y es rojo o espera su OK,
    /// también fuera de ella). Lo usa la integración para los avisos del motor y de `tls_avisar`.
    func avisoDeLosAsistentes(_ texto: String, estado: TLSEstadoAviso = .atencion, alMac: Bool = false, id: String? = nil) {
        aviso = Aviso(texto, estado: estado.estado)
        guard alMac else { return }
        let p = PreferenciasPresencia.compartidas
        guard p.avisos else { return }
        p.notificador.avisar(id: id ?? "asistentes:\(texto.hashValue)", titulo: "\(entry.nombre) · Asistentes", texto: texto,
                             empresa: entry.id)
    }

    /// F5 · integración: escribe un plan **de la persona** (tarjetas de Calendario, conexiones) como cualquier cambio de
    /// la app: dominio, Actividad, aviso y «Deshacer». Lanza si la carpeta no escribe o el plan no es de una persona.
    @discardableResult
    func escribirComoPersona(_ plan: WritePlan, aviso: String? = nil) async throws -> WriteResult {
        guard plan.autor.esPersona else { throw WriteError.soloLectura }
        return try await escribir(plan: plan, aviso: aviso)
    }

    /// Avisa a la integración de que el escritor ya está (tras `conectarEscritor`).
    internal func integracionEscritorListo() {
        guard let i = integracion, writer != nil else { return }
        Task { await i.escritorListo(self) }
    }
}

/// Cómo se pinta un aviso de los asistentes (sin exponer los tipos de diseño a la integración).
public enum TLSEstadoAviso: Sendable {
    case bien, atencion, mal, informativo

    var estado: TLSEstado {
        switch self {
        case .bien: .bien
        case .atencion: .atencion
        case .mal: .mal
        case .informativo: .sinDato
        }
    }
}

/// La integración de cada `AppModel` (sin retenerla).
@MainActor
private enum IntegracionDelModelo {
    private final class Debil { weak var valor: (any IntegracionDeEmpresas)?; init(_ v: (any IntegracionDeEmpresas)?) { valor = v } }
    private static var porModelo: [ObjectIdentifier: Debil] = [:]

    static func de(_ m: AppModel) -> (any IntegracionDeEmpresas)? { porModelo[ObjectIdentifier(m)]?.valor }

    static func poner(_ i: (any IntegracionDeEmpresas)?, en m: AppModel) {
        porModelo = porModelo.filter { $0.value.valor != nil }
        porModelo[ObjectIdentifier(m)] = i.map { Debil($0) }
    }
}
