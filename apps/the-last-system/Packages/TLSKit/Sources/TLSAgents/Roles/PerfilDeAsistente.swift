import Foundation
import TLSCore

// F4 · rol «roles» (PLAN §5.1, SISTEMAS §6). Lo que la app sabe de cada asistente de serie además de lo que dice
// `config.yaml`: quién es, qué sistemas lleva, qué herramientas de `tls-mcp` puede usar, sus rutinas y disparadores,
// sus alertas, lo que nunca hace y sus valores por defecto. Es un dato fijo (no lee la carpeta) y no da permisos: los
// permisos de verdad los aplica el `Autorizador` con la configuración confirmada.
//
// Procedencia: misiones, preguntas fijas y prohibiciones reescritas de PROG `core/sql/02-semillas.sql` (roles y
// miembros agénticos) y `core/agentes.js` (Manu), con el reparto de PLAN §5.1 y SISTEMAS §6.1. Ver docs/PROCEDENCIA.md.

/// Una herramienta del catálogo de `tls-mcp` (PLAN §5.4). El nombre es el que ve el asistente sin el prefijo
/// `mcp__tls__`.
public enum HerramientaDeAsistente: String, Sendable, Hashable, CaseIterable, Codable {
    // Lectura (por `AgentView`: sin lo privado ni `.tls/`).
    case estado = "tls_estado"
    case buscar = "tls_buscar"
    case leer = "tls_leer"
    case listar = "tls_listar"
    case leerSistema = "tls_leer_sistema"
    case tareas = "tls_tareas"
    case agenda = "tls_agenda"
    case diagnostico = "tls_diagnostico"
    case expediente = "tls_expediente"
    case bitacora = "tls_bitacora"
    case correoPendiente = "tls_correo_pendiente"
    case movimientos = "tls_movimientos"
    // Suelo (sin OK).
    case crearTarea = "tls_crear_tarea"
    case actualizarTarea = "tls_actualizar_tarea"
    case comentar = "tls_comentar"
    case prepararBorrador = "tls_preparar_borrador"
    case moverArchivo = "tls_mover_archivo"
    /// F5 · mail: la sección del día en el registro del correo del Buzón (solo el Cartero).
    case anotarCorreo = "tls_anotar_correo"
    case proponerConciliacion = "tls_proponer_conciliacion"
    case avisar = "tls_avisar"
    case programarSeguimiento = "tls_programar_seguimiento"
    case delegar = "tls_delegar"
    case finalizar = "tls_finalizar"
    // Dominio (gobernadas por el modo de la función).
    case registrarContacto = "tls_registrar_contacto"
    case registrarOportunidad = "tls_registrar_oportunidad"
    case registrarMetricasContenido = "tls_registrar_metricas_contenido"
    case registrarCobroExterno = "tls_registrar_cobro_externo"
    // Decisión.
    case preguntar = "tls_preguntar"
    case proponer = "tls_proponer"
    case registrarDecision = "tls_registrar_decision"
    // Sensibles: siempre «aprobación requerida».
    case solicitarAccion = "tls_solicitar_accion"

    public enum Grupo: String, Sendable, Hashable, CaseIterable {
        case lectura, suelo, dominio, decision, sensible
    }

    public var grupo: Grupo {
        switch self {
        case .estado, .buscar, .leer, .listar, .leerSistema, .tareas, .agenda, .diagnostico, .expediente, .bitacora,
             .correoPendiente, .movimientos:
            .lectura
        case .crearTarea, .actualizarTarea, .comentar, .prepararBorrador, .moverArchivo, .anotarCorreo, .proponerConciliacion,
             .avisar, .programarSeguimiento, .delegar, .finalizar:
            .suelo
        case .registrarContacto, .registrarOportunidad, .registrarMetricasContenido, .registrarCobroExterno:
            .dominio
        case .preguntar, .proponer, .registrarDecision:
            .decision
        case .solicitarAccion:
            .sensible
        }
    }

    /// Nombre tal como lo anuncia Claude Code (`mcp__tls__tls_leer`).
    public var nombreCompleto: String { "mcp__tls__" + rawValue }

    /// Quién es el único que puede tenerla (PLAN §5.4): delegar, el coordinador; el correo, el Cartero; los
    /// movimientos del banco, el Contable. `nil`: cualquiera a quien se la dé su perfil.
    public var exclusivaDe: String? {
        switch self {
        case .delegar: "coordinador"
        case .correoPendiente, .anotarCorreo: "cartero"
        case .movimientos: "contable"
        default: nil
        }
    }

    /// Lee `tls_leer` o `mcp__tls__tls_leer`.
    public init?(nombre: String) {
        let n = nombre.hasPrefix("mcp__tls__") ? String(nombre.dropFirst("mcp__tls__".count)) : nombre
        self.init(rawValue: n)
    }

    /// Las de lectura que tiene todo asistente que trabaja dentro de la carpeta.
    public static let lecturaComun: [HerramientaDeAsistente] =
        [.estado, .buscar, .leer, .listar, .leerSistema, .tareas, .agenda, .diagnostico, .expediente, .bitacora]
}

/// Cuándo está activo un asistente en una empresa recién configurada (PLAN §5.1 y §6.1 · «Estado en la copia»).
public enum ActivacionDeSerie: String, Sendable, Hashable, CaseIterable {
    /// Siempre (Mika, que coordina; el Ordenador, que solo ordena la carpeta).
    case siempre
    /// Solo si su área está activa (Comercial, Implementador, Contable).
    case siSuAreaEstaActiva
    /// En reposo hasta que lo actives tú (Marca, Equipo).
    case enReposo
    /// Hasta que conectes Mail (Cartero, F5).
    case alConectarMail

    /// Para la persona.
    public var explicacion: String {
        switch self {
        case .siempre: "Trabaja desde el primer día."
        case .siSuAreaEstaActiva: "Trabaja cuando su área está activa."
        case .enReposo: "Empieza cuando lo actives tú."
        case .alConectarMail: "Empieza cuando conectes Mail."
        }
    }
}

/// Un aviso que da el asistente cuando un número o un plazo se tuerce.
public struct AlertaDePerfil: Sendable, Hashable {
    /// Qué la dispara, en palabras («Oportunidad quieta 7 días o más»).
    public var cuando: String
    /// Número clave que la mide, si lo hay (`VEN-STALE7`).
    public var numero: String?

    public init(_ cuando: String, numero: String? = nil) {
        self.cuando = cuando; self.numero = numero
    }
}

/// Algo que se le puede pedir con un botón (la cabecera del área, PLAN §6.5): «Preparar seguimiento».
public struct AccionRapidaDeAsistente: Sendable, Hashable, Identifiable {
    public var id: String
    /// Texto del botón.
    public var titulo: String
    /// Qué se le pide (primer mensaje del trabajo).
    public var peticion: String

    public init(id: String, titulo: String, peticion: String) {
        self.id = id; self.titulo = titulo; self.peticion = peticion
    }
}

/// Un disparador de serie que no es una rutina de calendario: un evento del dominio, un plazo relativo
/// (seguimientos, kit antes de una sesión) o la acción de otro asistente.
public struct DisparadorDePerfil: Sendable, Hashable {
    public enum Tipo: String, Sendable, Hashable {
        /// Un evento del dominio (`contacto.creado`): el motor lo recibe del outbox.
        case evento
        /// Un plazo contado desde una ficha (`despertar:` o `tls_programar_seguimiento`).
        case plazo
        /// Lo dispara la app al detectar algo (aprobaciones repetidas, un asistente que falla).
        case deteccion
    }

    public var tipo: Tipo
    /// Para `evento`, el tipo (`contacto.creado`); para los demás, un identificador estable.
    public var clave: String
    /// Qué hace, contado a la persona (la ficha de rol y la pantalla del asistente).
    public var resumen: String
    /// Qué hace cuando salta, dicho al asistente (va en el primer mensaje del trabajo).
    public var instruccion: String
    /// Solo en `plazo`: horas desde la referencia (el último movimiento de la oportunidad, la sesión…). Negativo:
    /// antes (el kit, 24 h antes de la sesión).
    public var plazoHoras: Int?

    public init(_ tipo: Tipo, _ clave: String, resumen: String, _ instruccion: String, plazoHoras: Int? = nil) {
        self.tipo = tipo; self.clave = clave; self.resumen = resumen; self.instruccion = instruccion
        self.plazoHoras = plazoHoras
    }
}

/// Modelo, esfuerzo y topes por defecto (PLAN §4.5). El uso se guarda en USD (lo que informa Claude Code); en
/// pantalla se enseña como «% de tu tope».
public struct AjustesDeSerie: Sendable, Hashable {
    public var modelo: String
    public var esfuerzo: String
    public var maxTareasPorEjecucion: Int
    public var presupuestoEjecucionUSD: Double
    public var presupuestoMesUSD: Double

    public init(modelo: String = "sonnet", esfuerzo: String = "medium", maxTareasPorEjecucion: Int = 10,
                presupuestoEjecucionUSD: Double = 0.5, presupuestoMesUSD: Double = 15) {
        self.modelo = modelo; self.esfuerzo = esfuerzo; self.maxTareasPorEjecucion = maxTareasPorEjecucion
        self.presupuestoEjecucionUSD = presupuestoEjecucionUSD; self.presupuestoMesUSD = presupuestoMesUSD
    }

    public static let porDefecto = AjustesDeSerie()
}

/// Todo lo que describe a un asistente de serie.
public struct PerfilDeAsistente: Sendable, Hashable, Identifiable {
    public var id: String { slug }
    /// `mika`, `comercial`… (igual que en `config.yaml › agentes`).
    public var slug: String
    /// «Mika», «Comercial».
    public var nombre: String
    /// «tu asistente de Dirección».
    public var descripcion: String
    /// Área propia; `nil` para los asistentes del sistema (Cartero y Ordenador), que trabajan en el Buzón.
    public var area: AreaCode?
    /// Asistente del sistema (no lleva un área: el Buzón y el orden de la carpeta).
    public var esDelSistema: Bool
    public var coordinador: Bool
    /// Áreas que lee además de la suya (`todas` para el coordinador y el Ordenador).
    public var leeAreas: [AreaCode]
    public var leeTodas: Bool
    /// La pregunta que se hace siempre.
    public var pregunta: String
    /// Una frase.
    public var mision: String
    /// Códigos de los sistemas que lleva (SISTEMAS §2.5: `DI1`, `VE2`…).
    public var sistemas: [String]
    /// Funciones del estándar que cubre (`capacidades.yaml`).
    public var capacidades: [String]
    /// Números clave que miran su trabajo (`Metas.md`).
    public var numeros: [String]
    public var herramientas: [HerramientaDeAsistente]
    public var rutinas: [RutinaDeAsistente]
    public var disparadores: [DisparadorDePerfil]
    public var accionesRapidas: [AccionRapidaDeAsistente]
    public var alertas: [AlertaDePerfil]
    /// Lo que decide sin preguntar (dentro del suelo fijo).
    public var decideSolo: [String]
    /// Lo que hace solo.
    public var puedeSolo: [String]
    /// Lo que prepara y sale solo con tu OK.
    public var puedeConTuOK: [String]
    /// Lo que nunca hace.
    public var nunca: [String]
    /// A quién pasa lo que no puede resolver.
    public var escalado: String
    /// Qué entrega y en qué forma.
    public var entrega: String
    public var activacion: ActivacionDeSerie
    public var ajustes: AjustesDeSerie

    public init(slug: String, nombre: String, descripcion: String, area: AreaCode?, esDelSistema: Bool = false,
                coordinador: Bool = false, leeAreas: [AreaCode] = [], leeTodas: Bool = false, pregunta: String,
                mision: String, sistemas: [String], capacidades: [String], numeros: [String],
                herramientas: [HerramientaDeAsistente], rutinas: [RutinaDeAsistente] = [],
                disparadores: [DisparadorDePerfil] = [], accionesRapidas: [AccionRapidaDeAsistente] = [],
                alertas: [AlertaDePerfil] = [], decideSolo: [String] = [], puedeSolo: [String] = [],
                puedeConTuOK: [String] = [], nunca: [String], escalado: String, entrega: String,
                activacion: ActivacionDeSerie, ajustes: AjustesDeSerie = .porDefecto) {
        self.slug = slug; self.nombre = nombre; self.descripcion = descripcion; self.area = area
        self.esDelSistema = esDelSistema; self.coordinador = coordinador; self.leeAreas = leeAreas
        self.leeTodas = leeTodas; self.pregunta = pregunta; self.mision = mision; self.sistemas = sistemas
        self.capacidades = capacidades; self.numeros = numeros; self.herramientas = herramientas
        self.rutinas = rutinas; self.disparadores = disparadores; self.accionesRapidas = accionesRapidas
        self.alertas = alertas; self.decideSolo = decideSolo; self.puedeSolo = puedeSolo
        self.puedeConTuOK = puedeConTuOK; self.nunca = nunca; self.escalado = escalado; self.entrega = entrega
        self.activacion = activacion; self.ajustes = ajustes
    }

    /// «Comercial (asistente)», como se enseña en la Actividad (PLAN §4.2).
    public var nombreVisible: String { "\(nombre) (asistente)" }

    /// `agente:comercial`, como se escribe en `responsable` y en la Actividad.
    public var autor: String { "agente:\(slug)" }

    /// `areas:` de `config.yaml`: su área, o `buzon` para los del sistema.
    public var clavesDeArea: [String] { area.map { [$0.layoutKey] } ?? ["buzon"] }

    /// `lee_areas:` de `config.yaml`.
    public var clavesQueLee: [String] { leeTodas ? ["todas"] : leeAreas.map(\.layoutKey) }

    /// Tipos de evento del dominio que le hacen trabajar.
    public var eventos: [String] { disparadores.filter { $0.tipo == .evento }.map(\.clave) }

    /// ¿Está activo de serie con estos estados de área? (`config.yaml` recién creado.)
    public func activoDeSerie(estados: [AreaCode: AreaStatus], mailConectado: Bool = false) -> Bool {
        switch activacion {
        case .siempre: true
        case .siSuAreaEstaActiva: area.map { estados[$0] == .activa } ?? false
        case .enReposo: false
        case .alConectarMail: mailConectado
        }
    }

    /// Lo que consume el motor (`CatalogoDeAsistentes`), con sus instrucciones de rol.
    public func rol(instrucciones: String) -> RolDeAsistente {
        var porEvento: [String: String] = [:]
        for d in disparadores where d.tipo == .evento { porEvento[d.clave] = d.instruccion }
        return RolDeAsistente(
            slug: slug, nombre: nombre, area: area, coordinador: coordinador, preguntaFija: pregunta,
            identidad: "Eres \(nombre), \(descripcion) en The Last System. \(mision)",
            instrucciones: instrucciones, herramientas: herramientas.map(\.rawValue), eventos: eventos,
            instruccionesPorEvento: porEvento, rutinasDeSerie: rutinas, nunca: nunca)
    }
}
