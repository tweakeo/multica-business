import Foundation

// Qué pide un asistente y qué decide el Autorizador (PLAN §5.2). Todo se nombra con texto estable (`tarea.crear`,
// `metas.fijar`…), que es lo que queda en `estado.sqlite.auditoria`.

/// Acción que sale de la empresa (decisión 6): nunca la hace un asistente; siempre pide tu aprobación concreta.
public enum AccionExterna: String, Sendable, Hashable, Codable, CaseIterable {
    case enviarCorreo = "enviar_correo"
    case escribirCliente = "escribir_cliente"
    case publicar
    case emitirFactura = "emitir_factura"
    case pagar
    /// Herramienta de otro programa que no es de solo lectura (`ext_<servidor>_<herramienta>`, F5).
    case externa

    /// En pantalla: «Enviar un correo»…
    public var titulo: String {
        switch self {
        // F5 · corrector (P2-9): la app nunca envía: el correo lo envías tú.
        case .enviarCorreo: "Correo para que lo envíes tú"
        case .escribirCliente: "Mensaje a un cliente para que lo envíes tú"
        case .publicar: "Publicar"
        case .emitirFactura: "Emitir una factura"
        case .pagar: "Preparar un pago"
        case .externa: "Usar otro programa"
        }
    }

    /// Dentro de una frase («lo que prepara Comercial para enviar un correo»).
    public var enFrase: String {
        switch self {
        case .enviarCorreo: "enviar un correo"
        case .escribirCliente: "escribir a un cliente"
        case .publicar: "publicar"
        case .emitirFactura: "emitir una factura"
        case .pagar: "preparar un pago"
        case .externa: "usar otro programa"
        }
    }

    /// Lee `enviar_correo`, `escribir_cliente`, `publicar`, `emitir_factura`, `pagar` (y `facturar`, `enviar`).
    public init?(leyendo texto: String) {
        let t = TextFolding.fold(texto).replacingOccurrences(of: " ", with: "_")
        switch t {
        case "enviar_correo", "enviar", "correo": self = .enviarCorreo
        case "escribir_cliente", "escribir_a_cliente", "mensaje": self = .escribirCliente
        case "publicar", "publicacion": self = .publicar
        case "emitir_factura", "facturar", "emitir": self = .emitirFactura
        case "pagar", "pago": self = .pagar
        case "externa": self = .externa
        default: return nil
        }
    }
}

/// Tipo de acción, con su nombre estable.
public enum TipoDeAccion: String, Sendable, Hashable, Codable, CaseIterable {
    // Lectura
    case leer, buscar, listar
    // Suelo (PermisoBase)
    case tareaCrear = "tarea.crear"
    case tareaMover = "tarea.mover"
    case comentar
    case avisar
    case preguntar
    case proponer
    case borradorPreparar = "borrador.preparar"
    case conciliacionProponer = "conciliacion.proponer"
    case buzonMover = "buzon.mover"
    case buzonRegistrar = "buzon.registrar"
    case seguimientoProgramar = "seguimiento.programar"
    case delegar
    case bitacoraRegistrar = "bitacora.registrar"
    case finalizar
    // Dominio (gobernadas por el modo de su función)
    case contactoRegistrar = "contacto.registrar"
    case oportunidadRegistrar = "oportunidad.registrar"
    case oportunidadEtapa = "oportunidad.etapa"
    case metricasRegistrar = "metricas.registrar"
    case plantillaAjustar = "plantilla.ajustar"
    case cobroExternoRegistrar = "cobro_externo.registrar"
    case fichaEditar = "ficha.editar"
    // Decisión
    case decisionRegistrar = "decision.registrar"
    // Vetadas a los asistentes (paso 5)
    case config
    case capacidadDeclarar = "capacidad.declarar"
    case metasFijar = "metas.fijar"
    case aprobacionDecidir = "aprobacion.decidir"
    case ajustesEscribir = "ajustes.escribir"
    case rolesEscribir = "roles.escribir"
    case agentsEscribir = "agents.escribir"
    case empresaEscribir = "empresa.escribir"
    case venceMover = "vence.mover"
    case tareaCerrar = "tarea.cerrar"
    case oportunidadGanar = "oportunidad.ganar"
    case cobroConfirmar = "cobro.confirmar"
    case conciliacionConfirmar = "conciliacion.confirmar"
    // Externa (paso 10)
    case externa

    public enum Clase: String, Sendable, Hashable {
        case lectura, suelo, dominio, decision, vetada, externa
    }

    public var clase: Clase {
        switch self {
        case .leer, .buscar, .listar: .lectura
        case .tareaCrear, .tareaMover, .comentar, .avisar, .preguntar, .proponer, .borradorPreparar, .conciliacionProponer,
             .buzonMover, .buzonRegistrar, .seguimientoProgramar, .delegar, .bitacoraRegistrar, .finalizar: .suelo
        case .contactoRegistrar, .oportunidadRegistrar, .oportunidadEtapa, .metricasRegistrar, .plantillaAjustar,
             .cobroExternoRegistrar, .fichaEditar: .dominio
        case .decisionRegistrar: .decision
        case .config, .capacidadDeclarar, .metasFijar, .aprobacionDecidir, .ajustesEscribir, .rolesEscribir, .agentsEscribir,
             .empresaEscribir, .venceMover, .tareaCerrar, .oportunidadGanar, .cobroConfirmar, .conciliacionConfirmar: .vetada
        case .externa: .externa
        }
    }

    /// Cambia algo en la carpeta (o fuera de ella).
    public var escribe: Bool { clase != .lectura }

    /// Función de serie de las acciones de dominio cuando quien pide no la dice (PLAN §5.4, capacidades.yaml).
    public var capacidadPorDefecto: String? {
        switch self {
        case .contactoRegistrar: "VEN-02"
        case .oportunidadRegistrar, .oportunidadEtapa: "VEN-03"
        case .metricasRegistrar: "MAR-08"
        case .plantillaAjustar: "ENT-02"
        case .cobroExternoRegistrar: "FIN-04"
        case .conciliacionProponer: "FIN-07"
        case .decisionRegistrar: "DIR-01"
        default: nil
        }
    }
}

/// La ejecución en curso de un asistente (para los topes).
public struct ContextoEjecucion: Sendable, Hashable {
    /// `r-7f3a…`.
    public let id: String
    /// Profundidad de delegación de esta ejecución (Mika = 0; lo que delega, 1…).
    public let profundidad: Int

    public init(id: String, profundidad: Int = 0) {
        self.id = id; self.profundidad = profundidad
    }
}

/// Lo que se pregunta al Autorizador.
public struct SolicitudAutorizacion: Sendable, Hashable {
    public var autor: Autor
    public var tipo: TipoDeAccion
    /// Fichas o ficheros que toca (de la carpeta, relativos).
    public var rutas: [VaultPath]
    /// Función (`VEN-08`) si la hay.
    public var capacidad: String?
    /// Acción externa (paso 10). Si no es `nil`, siempre pide aprobación.
    public var externa: AccionExterna?
    /// `ext_<servidor>_<herramienta>` para las de otros programas.
    public var herramienta: String?
    public var ejecucion: ContextoEjecucion?
    /// Tamaño del texto que se escribe (bytes), si se sabe.
    public var tamano: Int?
    /// `chat:<msg>` o `pregunta:<id>` para registrar una decisión que tomó una persona.
    public var origen: String?
    /// Profundidad a la que se delega (`tls_delegar`).
    public var profundidadDelegacion: Int?
    /// Plan al que pertenece (lo apunta la auditoría).
    public var plan: UUID?

    public init(autor: Autor, tipo: TipoDeAccion, rutas: [VaultPath] = [], capacidad: String? = nil,
                externa: AccionExterna? = nil, herramienta: String? = nil, ejecucion: ContextoEjecucion? = nil,
                tamano: Int? = nil, origen: String? = nil, profundidadDelegacion: Int? = nil, plan: UUID? = nil) {
        self.autor = autor; self.tipo = tipo; self.rutas = rutas; self.capacidad = capacidad?.uppercased()
        self.externa = externa ?? (tipo == .externa ? .externa : nil); self.herramienta = herramienta
        self.ejecucion = ejecucion; self.tamano = tamano; self.origen = origen
        self.profundidadDelegacion = profundidadDelegacion; self.plan = plan
    }

    /// La función que gobierna esta acción (la dicha o la de serie).
    public var capacidadEfectiva: String? { capacidad ?? tipo.capacidadPorDefecto }
}

/// Lo que decide el Autorizador.
public struct DecisionAutorizacion: Sendable, Hashable {
    public enum Resultado: String, Sendable, Hashable, Codable {
        /// Adelante.
        case permitido
        /// No hay escritor: la carpeta solo se lee (la intención queda apuntada).
        case soloLectura = "solo_lectura"
        /// No.
        case denegado
        /// Lo privado y `.tls/`: para un asistente, no existe.
        case noEncontrado = "no_encontrado"
        /// Acción externa: siempre con tu aprobación concreta.
        case requiereAprobacion = "aprobacion_requerida"
        /// Modo `manual`: se crea una tarea para una persona.
        case tareaParaPersona = "tarea_para_persona"
        /// Modo `asistido`: se convierte en propuesta (tarjeta).
        case propuesta
    }

    public let resultado: Resultado
    /// Paso del orden de §5.2 que decidió (1–12).
    public let paso: Int
    /// Por qué, en palabras de persona.
    public let motivo: String
    /// Modo `supervisado`: se hizo y sale en el resumen semanal.
    public let alResumenSemanal: Bool
    public let solicitud: SolicitudAutorizacion

    public init(resultado: Resultado, paso: Int, motivo: String, alResumenSemanal: Bool = false,
                solicitud: SolicitudAutorizacion) {
        self.resultado = resultado; self.paso = paso; self.motivo = motivo; self.alResumenSemanal = alResumenSemanal
        self.solicitud = solicitud
    }

    public var permitido: Bool { resultado == .permitido }

    /// Lo que ve el asistente (`tls-mcp`): lo privado, siempre «no encontrado».
    public var respuestaParaAsistente: String {
        switch resultado {
        case .permitido: "permitido"
        case .noEncontrado: "no encontrado"
        case .requiereAprobacion: "aprobación requerida"
        case .soloLectura: "solo lectura: " + motivo
        case .denegado: "denegado: " + motivo
        case .tareaParaPersona: "lo hará una persona: " + motivo
        case .propuesta: "queda como propuesta: " + motivo
        }
    }
}

/// El suelo fijo (decisión 6): lo que cualquier asistente activo puede hacer sin pedir permiso, en cualquier modo
/// salvo `off`, con el interruptor encendido, su área sin pausa y fuera de lo privado.
public enum PermisoBase {
    /// Leer, buscar, comentar, avisar, preguntar y proponer; crear y mover tareas internas (estado, `planificada` y
    /// responsable; nunca `vence`, Hecha ni Cancelada); preparar borradores; proponer conciliaciones; mover desde
    /// `Buzón/` con deshacer; programar seguimientos, delegar (el coordinador), apuntar en la Bitácora y cerrar su
    /// trabajo.
    public static func incluye(_ tipo: TipoDeAccion) -> Bool {
        tipo.clase == .lectura || tipo.clase == .suelo
    }

    /// Propiedades de una tarea que un asistente puede cambiar sin pedir permiso («mover» una tarea).
    public static let propiedadesDeTarea: Set<String> = [
        "estado", "planificada", "responsable", "prioridad", "despertar", "bloqueada_por", "dedicadas_h", "estimacion_h",
    ]

    /// Profundidad máxima de delegación.
    public static let profundidadMaxima = 2

    /// Tamaño máximo de lo que escribe un asistente de una vez.
    public static let tamanoMaximo = 256 * 1024

    /// Ficheros que nunca ve un asistente (además de lo privado y `.tls/`).
    public static func esFicheroVetado(_ p: VaultPath) -> Bool {
        let n = TextFolding.nameKey(p.name)
        if ["secrets.env", "cookies.txt", "escritor.json"].contains(n) { return true }
        return [".env", ".p12", ".key"].contains { n.hasSuffix($0) }
    }
}

extension Autor {
    /// `agente:<slug>`.
    public var esAgente: Bool {
        if case .agente = self { return true }
        return false
    }

    /// El slug del asistente (`nil` si no es un asistente).
    public var asistente: String? {
        if case .agente(let s) = self { return ConfigAgentes.slug(s) }
        return nil
    }
}

/// `CommandBus` no escribe un plan de un asistente que el Autorizador no permite.
public struct AutorizacionDenegada: Error, LocalizedError, Sendable, Equatable {
    public let decision: DecisionAutorizacion

    public init(decision: DecisionAutorizacion) { self.decision = decision }

    public var errorDescription: String? {
        switch decision.resultado {
        case .noEncontrado: "No encontrado."
        case .requiereAprobacion: "Esto sale de la empresa: necesita tu aprobación."
        case .propuesta: "Esto lo propone el asistente y decides tú."
        case .tareaParaPersona: "Esta función la haces tú."
        default: decision.motivo
        }
    }
}
