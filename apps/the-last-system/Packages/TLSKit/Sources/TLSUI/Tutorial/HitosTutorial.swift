import Foundation
import TLSCore
import TLSDesign

// Tutorial (PLAN §6.8, F3 · rol tutorial). Los hitos se marcan con la acción real: lo que la persona hace en la
// app (escribir, navegar, pulsar dentro del sitio señalado) llega como un `TutorialEvent`. Nada se marca por
// pulsar «Siguiente».

/// Lo que acaba de pasar en la app y cuenta para el tutorial.
///
/// Los derivan el tutorial (de lo escrito en la carpeta, de la navegación y de las anclas) y cualquier pantalla
/// puede mandarlos con `TutorialEventos.registrar(_:empresa:)`.
public enum TutorialEvent: Hashable, Sendable {
    /// Pulsó en el foco de Hoy (su botón, «Ver detalle», «Posponer»…).
    case focoDeHoy
    /// Aprobó, respondió o cambió una decisión (una tarea de tipo decisión o pregunta cambió de estado).
    case decisionResuelta(VaultPath?)
    /// Una oportunidad cambió de etapa.
    case oportunidadMovida(VaultPath?)
    /// Una tarea nueva con responsable (o una que pasó a tenerlo).
    case tareaCreadaYAsignada(VaultPath?)
    /// Cambió una ficha o una nota.
    case fichaEditada(VaultPath?)
    /// «Mostrar en Finder».
    case vistaEnFinder(VaultPath?)
    /// Una línea nueva en el registro de decisiones.
    case decisionRegistrada
    /// Un extracto del banco importado.
    case extractoImportado
    /// Vio el mapa de las seis áreas, con su cuello.
    case mapaVisto
    /// Entró en un área.
    case areaVista(AreaCode)
    /// ⌘J: el asistente de la pantalla (F4).
    case asistenteAbierto
    /// Pausó los asistentes (F4).
    case asistentesPausados
    /// Los reanudó (F4).
    case asistentesReanudados
    /// Aprobó una propuesta de un asistente en Decisiones (F4).
    case propuestaAprobada

    /// La parte de un hito que cumple (un hito puede pedir dos: editar y ver en Finder).
    public var parte: String {
        switch self {
        case .focoDeHoy: "foco"
        case .decisionResuelta: "decision"
        case .oportunidadMovida: "oportunidad"
        case .tareaCreadaYAsignada: "tarea"
        case .fichaEditada: "editar"
        case .vistaEnFinder: "finder"
        case .decisionRegistrada: "registro"
        case .extractoImportado: "extracto"
        case .mapaVisto: "mapa"
        case .areaVista(let a): "area:\(a.rawValue)"
        case .asistenteAbierto: "asistente"
        case .asistentesPausados: "pausar"
        case .asistentesReanudados: "reanudar"
        case .propuestaAprobada: "propuesta"
        }
    }

    /// La ficha que tocó, si la hay (para «Mostrar en Finder»).
    public var ruta: VaultPath? {
        switch self {
        case .decisionResuelta(let r), .oportunidadMovida(let r), .tareaCreadaYAsignada(let r), .fichaEditada(let r),
             .vistaEnFinder(let r): r
        default: nil
        }
    }
}

/// Los diez hitos de «Conoce la app con un ejemplo» (PLAN §6.8).
public enum HitoTutorial: String, CaseIterable, Codable, Sendable, Hashable {
    case focoDeHoy = "foco-de-hoy"
    case aprobarOModificar = "aprobar-o-modificar"
    case moverOportunidad = "mover-oportunidad"
    case crearYAsignarTarea = "crear-y-asignar-tarea"
    case editarYVerEnFinder = "editar-y-ver-en-finder"
    case registrarDecision = "registrar-decision"
    case importarExtracto = "importar-extracto"
    case mapaYCuello = "mapa-y-cuello"
    case abrirAsistente = "abrir-asistente"
    case pausarAsistentes = "pausar-y-reanudar-asistentes"

    public var titulo: String {
        switch self {
        case .focoDeHoy: "Mira tu foco de hoy"
        case .aprobarOModificar: "Aprueba o cambia una decisión"
        case .moverOportunidad: "Mueve una oportunidad"
        case .crearYAsignarTarea: "Crea una tarea y dásela a alguien"
        case .editarYVerEnFinder: "Edita una ficha y mírala en Finder"
        case .registrarDecision: "Apunta una decisión"
        case .importarExtracto: "Importa un extracto del banco"
        case .mapaYCuello: "Mira el mapa y el cuello"
        case .abrirAsistente: "Pregunta al asistente con ⌘J"
        case .pausarAsistentes: "Pausa y reanuda los asistentes"
        }
    }

    /// Las partes que hacen falta (todas).
    public var partes: [String] {
        switch self {
        case .focoDeHoy: ["foco"]
        case .aprobarOModificar: ["decision"]
        case .moverOportunidad: ["oportunidad"]
        case .crearYAsignarTarea: ["tarea"]
        case .editarYVerEnFinder: ["editar", "finder"]
        case .registrarDecision: ["registro"]
        case .importarExtracto: ["extracto"]
        case .mapaYCuello: ["mapa"]
        case .abrirAsistente: ["asistente"]
        case .pausarAsistentes: ["pausar", "reanudar"]
        }
    }

    /// Hasta F3, ⌘J y pausar «llegaban con los asistentes». Desde F4 (0.5) se hacen todos de verdad.
    public var llegaConLosAsistentes: Bool { false }

    /// Los que se pueden hacer ya (todos, desde F4).
    public static var disponibles: [HitoTutorial] { allCases.filter { !$0.llegaConLosAsistentes } }
}

/// Los dos recorridos.
public enum TipoRecorrido: String, Codable, Sendable, Hashable, CaseIterable {
    /// «Conoce la app con un ejemplo», sobre Asesoría Ribera.
    case ejemplo
    /// «Recorrido con tu empresa» (paso 8 de la puesta en marcha).
    case tuEmpresa = "tu-empresa"

    public var titulo: String {
        switch self {
        case .ejemplo: "Conoce la app con un ejemplo"
        case .tuEmpresa: "Recorrido con tu empresa"
        }
    }

    /// Rótulo corto de la burbuja.
    var rotulo: String {
        switch self {
        case .ejemplo: "Conoce la app"
        case .tuEmpresa: "Primer recorrido"
        }
    }
}

/// Anclas que señala el tutorial (una línea `.tutorialAnchor(...)` en cada pantalla).
public extension TutorialAnclaID {
    static let hoyFoco: TutorialAnclaID = "hoy.foco"
    static let decisionesGrupo: TutorialAnclaID = "decisiones.grupo"
    static let ventasCRM: TutorialAnclaID = "ventas.crm"
    static let tareasNueva: TutorialAnclaID = "tareas.nueva"
    static let ficha: TutorialAnclaID = "ficha"
    static let direccionRegistrarDecision: TutorialAnclaID = "direccion.registrarDecision"
    static let direccionMapa: TutorialAnclaID = "direccion.mapa"
    static let bancoImportar: TutorialAnclaID = "banco.importar"
    static let areaPestanas: TutorialAnclaID = "area.pestanas"
}
