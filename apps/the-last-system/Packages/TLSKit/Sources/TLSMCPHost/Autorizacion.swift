import Foundation
import TLSCore

/// Qué tipo de acción pide una herramienta (PLAN §5.2).
public enum ClaseDeAccion: Sendable, Hashable {
    /// Leer (por `AgentView`).
    case lectura
    /// Suelo fijo (`PermisoBase`): vale en cualquier modo salvo `off`.
    case suelo
    /// Acción de dominio gobernada por el modo de su capacidad.
    case dominio(capacidad: String)
    /// Pregunta, propuesta o registro de una decisión ya tomada por la persona.
    case decision
    /// Acción externa (enviar, publicar, emitir o facturar, pagar, escribir a clientes): **aprobación siempre**.
    case externa(String)
}

/// Lo que se pide al `Autorizador` antes de hacer nada.
public struct PeticionDeAccion: Sendable {
    public var autor: Autor
    public var ejecucion: String
    /// `tarea.crear`, `tarea.estado`, `comentario`, `borrador.preparar`, `buzon.mover`, `contacto.registrar`…
    public var accion: String
    public var clase: ClaseDeAccion
    /// Rutas que toca o lee (ya normalizadas).
    public var rutas: [VaultPath]
    public var area: AreaCode?
    /// Profundidad de delegación que resultaría (solo `delegar`).
    public var profundidad: Int?
    /// Plan que se escribiría (si lo hay): el `Autorizador` decide **ese** plan.
    public var plan: WritePlan?
    /// `chat:<msg>` o `pregunta:<id>` (registrar una decisión tuya).
    public var origen: String?
    /// Profundidad de delegación de la ejecución que pide (0 si la lanzó un disparador o una persona).
    public var profundidadDeLaEjecucion: Int

    public init(autor: Autor, ejecucion: String, accion: String, clase: ClaseDeAccion, rutas: [VaultPath] = [],
                area: AreaCode? = nil, profundidad: Int? = nil, plan: WritePlan? = nil, origen: String? = nil,
                profundidadDeLaEjecucion: Int = 0) {
        self.autor = autor; self.ejecucion = ejecucion; self.accion = accion; self.clase = clase; self.rutas = rutas
        self.area = area; self.profundidad = profundidad; self.plan = plan; self.origen = origen
        self.profundidadDeLaEjecucion = profundidadDeLaEjecucion
    }

    /// `aviso`, `enviar_correo`… si es una acción externa.
    public var externa: String? {
        if case .externa(let e) = clase { return e }
        return nil
    }
}

/// Qué decide el `Autorizador`.
public enum VeredictoDeAccion: Sendable, Hashable {
    case permitido
    /// No se hace; el motivo se le dice al asistente (sin jerga).
    case denegado(String)
    /// Ruta privada: se responde «no encontrado» (y queda auditado).
    case noEncontrado
    /// Acción externa: la decide Manu en Decisiones.
    case requiereAprobacion
    /// Modo `manual`: en vez de hacerlo, se deja una tarea para una persona.
    case tareaParaPersona
    /// Modo `asistido`: en vez de hacerlo, se convierte en propuesta (tarjeta).
    case propuesta
}

/// El único `Autorizador` (PLAN §5.2) visto desde el servidor de herramientas. Lo implementa el del gobierno
/// (TLSCore/Gobierno) con un adaptador; mientras no exista, `AutorizadorBasico`.
public protocol AutorizadorDeHerramientas: Sendable {
    func autorizar(_ peticion: PeticionDeAccion) async -> VeredictoDeAccion
    /// De una lista (búsqueda, carpeta, tareas), lo que este asistente puede ver, sin apuntar cada ruta.
    func visibles(_ rutas: [VaultPath], asistente: String) async -> [VaultPath]
}

extension AutorizadorDeHerramientas {
    public func visibles(_ rutas: [VaultPath], asistente: String) async -> [VaultPath] { rutas }
}

/// Lo mínimo que se comprueba siempre, también si el `Autorizador` del gobierno se equivocara (doble cerrojo en el
/// servidor de herramientas). Sirve de `Autorizador` en pruebas: suelo permitido, externas con aprobación, dominio
/// según `modos` (por defecto `modoPorDefecto`) e interruptor.
public struct AutorizadorBasico: AutorizadorDeHerramientas {
    public var interruptor: @Sendable () -> Bool
    public var modos: [String: ModoCapacidad]
    public var modoPorDefecto: ModoCapacidad

    public init(interruptor: @escaping @Sendable () -> Bool = { true }, modos: [String: ModoCapacidad] = [:],
                modoPorDefecto: ModoCapacidad = .asistido) {
        self.interruptor = interruptor; self.modos = modos; self.modoPorDefecto = modoPorDefecto
    }

    public func autorizar(_ p: PeticionDeAccion) async -> VeredictoDeAccion {
        guard interruptor() else { return .denegado("Los asistentes están apagados.") }
        if let v = VetosFijos.comprobar(p) { return v }
        switch p.clase {
        case .lectura, .suelo, .decision: return .permitido
        case .externa: return .requiereAprobacion
        case .dominio(let capacidad):
            switch modos[capacidad.uppercased()] ?? modoPorDefecto {
            case .off: return .denegado("Esta función está apagada.")
            case .manual: return .tareaParaPersona
            case .asistido: return .propuesta
            case .supervisado, .autonomo: return .permitido
            }
        }
    }
}

/// Vetos que no dependen de nada (PLAN §5.2, paso 5, y decisión 6). El servidor de herramientas los aplica **antes**
/// de preguntar al `Autorizador`.
public enum VetosFijos {
    /// Acciones que ningún asistente puede pedir.
    public static let accionesVetadas: Set<String> = [
        "config", "capacidad.declarar", "metas.fijar", "aprobacion.decidir", "ajustes.escribir", "roles.escribir",
        "agents.escribir", "empresa.escribir", "vence.mover", "tarea.cerrar", "oportunidad.ganar", "cobro.confirmar",
        "conciliacion.confirmar",
    ]

    /// `.tls/`, `6 · Equipo/Roles/`, `AGENTS.md`, `Empresa.md` (y `config.yaml` dondequiera que esté).
    public static func rutaVetada(_ p: VaultPath, layout: VaultLayout? = nil) -> Bool {
        let c = p.components
        if c.contains(where: { $0.hasPrefix(".") }) { return true }
        let nombre = TextFolding.nameKey(p.name)
        if ["agents.md", "empresa.md", "config.yaml"].contains(nombre) { return true }
        // `6 · Equipo/Roles/…` (con la carpeta de Equipo que diga la estructura, o cualquiera que acabe en «Equipo»).
        guard c.count >= 2, TextFolding.nameKey(c[1]) == "roles" else { return false }
        if let l = layout { return l.area(of: p) == .equipo }
        return TextFolding.fold(c[0]).hasSuffix("equipo")
    }

    static func comprobar(_ p: PeticionDeAccion) -> VeredictoDeAccion? {
        if accionesVetadas.contains(p.accion) { return .denegado("Un asistente no puede hacer esto: lo decides tú.") }
        if case .lectura = p.clase { return nil }
        if p.rutas.contains(where: { rutaVetada($0) }) { return .denegado("Un asistente no puede cambiar este fichero.") }
        if let d = p.profundidad, d > ContextoDelAsistente.profundidadMaxima {
            return .denegado("No se puede delegar más de \(ContextoDelAsistente.profundidadMaxima) niveles.")
        }
        return nil
    }
}

/// Qué pasó con una acción de dominio.
public enum DesenlaceDeDominio: Sendable {
    case hecho(WriteResult)
    /// Modo asistido: tarjeta 1-3-1 para la persona (ruta) y el id de la propuesta guardada.
    case propuesta(VaultPath, String)
    /// Modo manual: tarea para la persona.
    case tareaParaPersona(VaultPath)
    case denegado(String)
    case noEncontrado
}

/// Quién escribe las acciones de dominio de un asistente: el gobierno (`DominioDelGobierno`) o, sin él, el propio
/// servidor de herramientas con su `Autorizador`.
public protocol EscrituraDeDominio: Sendable {
    func escribir(_ plan: WritePlan, peticion: PeticionDeAccion) async throws -> DesenlaceDeDominio
}
