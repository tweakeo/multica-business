import Foundation

// F3 · rol motor. Puesta en marcha (PLAN §6.7): los tipos que comparten el motor, las pantallas y el estado guardado
// en `onboarding.json` (fuera de la carpeta). Nada de aquí escribe en la carpeta de la empresa.

/// Los pasos de la tabla de PLAN §6.7 (0, 0b y 1 a 8).
public enum PasoPuesta: String, Codable, CaseIterable, Sendable, Hashable, Comparable {
    case bienvenida
    case alcance
    case conocer
    case ordenar
    case organizar
    case sinTi = "sin-ti"
    case diaADia = "dia-a-dia"
    case numeros
    case conectar
    case recorrido

    /// Número en la tabla del PLAN («0», «0b», «1»…).
    public var numeroTabla: String {
        switch self {
        case .bienvenida: "0"
        case .alcance: "0b"
        case .conocer: "1"
        case .ordenar: "2"
        case .organizar: "3"
        case .sinTi: "4"
        case .diaADia: "5"
        case .numeros: "6"
        case .conectar: "7"
        case .recorrido: "8"
        }
    }

    /// Lo que se ve («Conocer tu negocio»).
    public var titulo: String {
        switch self {
        case .bienvenida: "Bienvenida"
        case .alcance: "Por dónde empezamos"
        case .conocer: "Conocer tu negocio"
        case .ordenar: "Ordenar lo que tienes"
        case .organizar: "Organizar"
        case .sinTi: "Qué funciona sin ti"
        case .diaADia: "Tu día a día"
        case .numeros: "Tus números"
        case .conectar: "Conectar"
        case .recorrido: "Primer recorrido"
        }
    }

    /// Paso al que pertenece en el contador «paso N de M» (la elección del alcance cuenta con la bienvenida).
    var grupoVisible: PasoPuesta { self == .alcance ? .bienvenida : self }

    /// Escribe en la carpeta al aplicar (los demás solo guardan en `onboarding.json`).
    public var escribeEnLaCarpeta: Bool {
        switch self {
        case .alcance, .conectar, .recorrido: false
        default: true
        }
    }

    var orden: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (a: PasoPuesta, b: PasoPuesta) -> Bool { a.orden < b.orden }
}

/// Las rutas de la puesta en marcha (PLAN §6.7, «Rutas y tope de pantallas»).
public enum RutaPuesta: String, Codable, Sendable, Hashable, CaseIterable {
    /// La copia de una carpeta ya organizada (G3): casi todo llega premarcado para confirmar.
    case copiaG3 = "copia-g3"
    /// Una carpeta propia sin la estructura de la app: hay que ordenarla.
    case carpetaPorOrdenar = "carpeta-por-ordenar"
    /// Sin carpeta: la app la crea.
    case empresaNueva = "empresa-nueva"
    /// Asesoría Ribera, con la puesta en marcha ya hecha.
    case ejemplo

    /// Pantallas como máximo (criterio F3-2). `nil` en el ejemplo (no tiene preguntas).
    public var topePantallas: Int? {
        switch self {
        case .copiaG3: 15
        case .carpetaPorOrdenar, .empresaNueva: 40
        case .ejemplo: nil
        }
    }

    public var titulo: String {
        switch self {
        case .copiaG3: "Tu carpeta ya está organizada"
        case .carpetaPorOrdenar: "Tu carpeta, por ordenar"
        case .empresaNueva: "Empresa nueva"
        case .ejemplo: "Ver un ejemplo"
        }
    }

    /// Hay una carpeta de la persona detrás.
    public var conCarpeta: Bool { self == .copiaG3 || self == .carpetaPorOrdenar }
}

/// Cuánto abarca esta puesta en marcha (paso 0b). Decide cuántos pasos siguen.
public enum AlcancePuesta: String, Codable, Sendable, Hashable, CaseIterable {
    case proceso, area, todo

    public var titulo: String {
        switch self {
        case .proceso: "Un proceso"
        case .area: "Un área"
        case .todo: "Todo"
        }
    }
}

/// Estado de un área (lo que se escribe en `Área.md`).
public enum EstadoAreaPuesta: String, Codable, Sendable, Hashable, CaseIterable {
    case activa, preparada
    case reposo = "en reposo"

    public var titulo: String {
        switch self {
        case .activa: "Activa"
        case .preparada: "Preparada"
        case .reposo: "En reposo"
        }
    }

    init?(_ s: AreaStatus) {
        switch s {
        case .activa: self = .activa
        case .preparada: self = .preparada
        case .reposo: self = .reposo
        case .desconocido: return nil
        }
    }
}

// MARK: - Respuestas

/// Lo que contesta la persona a una pregunta.
public enum ValorRespuesta: Codable, Sendable, Hashable {
    case texto(String)
    /// Identificador de la opción elegida.
    case opcion(String)
    case opciones([String])
    /// 1 a 5.
    case escala(Int)
    case siNo(Bool)
    case numero(Double)
    /// Fichero o carpeta elegidos (ruta absoluta o relativa a la carpeta).
    case rutas([String])
    /// «No lo sé»: se escribe PENDIENTE en la carpeta.
    case noLoSe

    public var esNoLoSe: Bool { self == .noLoSe }

    public var texto: String? {
        if case .texto(let t) = self { return t }
        return nil
    }

    public var opcion: String? {
        if case .opcion(let o) = self { return o }
        return nil
    }

    public var escala: Int? {
        if case .escala(let n) = self { return n }
        return nil
    }

    public var siNo: Bool? {
        if case .siNo(let b) = self { return b }
        return nil
    }

    public var numero: Double? {
        if case .numero(let n) = self { return n }
        return nil
    }

    public var opciones: [String]? {
        if case .opciones(let o) = self { return o }
        return nil
    }

    public var rutas: [String]? {
        if case .rutas(let r) = self { return r }
        return nil
    }
}

/// De dónde sale una respuesta. Lo premarcado lleva su fuente («Lo saqué de Rumbo.md»).
public struct OrigenRespuesta: Codable, Sendable, Hashable {
    public enum Clase: String, Codable, Sendable, Hashable {
        /// La escribió o la eligió la persona.
        case persona
        /// Sale de un fichero de la carpeta.
        case carpeta
        /// Lo propone la app (una cuenta, una recomendación).
        case propuesta
        /// Lo propone el asistente (solo con consentimiento).
        case asistente
    }

    public let clase: Clase
    /// Fichero de la carpeta del que sale (si sale de uno).
    public let fuente: VaultPath?
    /// Texto para la pantalla.
    public let texto: String

    public init(clase: Clase, fuente: VaultPath? = nil, texto: String) {
        self.clase = clase; self.fuente = fuente; self.texto = texto
    }

    public static let persona = OrigenRespuesta(clase: .persona, texto: "Lo dijiste tú")

    /// «Lo saqué de Rumbo.md».
    public static func carpeta(_ ruta: VaultPath) -> OrigenRespuesta {
        OrigenRespuesta(clase: .carpeta, fuente: ruta, texto: "Lo saqué de \(ruta.name)")
    }

    public static func propuesta(_ texto: String) -> OrigenRespuesta {
        OrigenRespuesta(clase: .propuesta, texto: texto)
    }
}

/// Una respuesta guardada.
public struct Respuesta: Codable, Sendable, Hashable {
    public var valor: ValorRespuesta
    public var origen: OrigenRespuesta
    /// La persona ya la vio y la dio por buena (lo premarcado no cuenta hasta que se confirma).
    public var confirmada: Bool
    /// Ya se repreguntó una vez (el entrevistador no vuelve a hacerlo).
    public var repreguntada: Bool
    public var fecha: Date

    public init(valor: ValorRespuesta, origen: OrigenRespuesta = .persona, confirmada: Bool = true,
                repreguntada: Bool = false, fecha: Date = Date()) {
        self.valor = valor; self.origen = origen; self.confirmada = confirmada
        self.repreguntada = repreguntada; self.fecha = fecha
    }

    enum CodingKeys: String, CodingKey { case valor, origen, confirmada, repreguntada, fecha }

    /// Solo `valor` es obligatorio: a una respuesta de otra versión le pueden faltar (o sobrar) claves.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        valor = try c.decode(ValorRespuesta.self, forKey: .valor)
        origen = (try? c.decodeIfPresent(OrigenRespuesta.self, forKey: .origen)) ?? .persona
        confirmada = (try? c.decodeIfPresent(Bool.self, forKey: .confirmada)) ?? true
        repreguntada = (try? c.decodeIfPresent(Bool.self, forKey: .repreguntada)) ?? false
        fecha = (try? c.decodeIfPresent(Date.self, forKey: .fecha)) ?? Date()
    }

    /// Premarcada desde la carpeta y sin tocar: no se vuelve a escribir donde ya estaba.
    public var vieneSinCambiosDeLaCarpeta: Bool { origen.clase == .carpeta }
}

// MARK: - Estado guardado

/// Cómo va cada paso.
public struct EstadoPaso: Codable, Sendable, Hashable {
    public enum Fase: String, Codable, Sendable, Hashable {
        case pendiente, aplicado, omitido
    }

    public var fase: Fase
    /// Plan escrito al aplicar (para «Deshacer»).
    public var plan: UUID?
    public var aplicado: Date?
    /// Resumen de lo que se hizo («Creé 9 ficheros y cambié 2»).
    public var resumen: String?

    public init(fase: Fase = .pendiente, plan: UUID? = nil, aplicado: Date? = nil, resumen: String? = nil) {
        self.fase = fase; self.plan = plan; self.aplicado = aplicado; self.resumen = resumen
    }
}

/// Lo que deja el paso 2 (lo lleva el importador): para el resumen, el contador de pantallas y «Deshacer».
public struct ResumenOrdenar: Codable, Sendable, Hashable {
    /// Pantallas que tiene el paso 2 en esta carpeta (las cuenta el importador).
    public var pantallas: Int
    public var titulos: [String]
    public var movidos: Int
    public var completadas: Int
    public var archivados: Int
    public var verificados: Int
    public var planes: [UUID]
    public var texto: String
    /// La explicación de dos o tres líneas de cada pantalla (la cabecera de la puesta en marcha la enseña). `nil` en
    /// los `onboarding.json` de antes: se toma la de su título (`explicacion(_:)`).
    public var explicaciones: [String]?

    public init(pantallas: Int, titulos: [String] = [], movidos: Int = 0, completadas: Int = 0, archivados: Int = 0,
                verificados: Int = 0, planes: [UUID] = [], texto: String = "", explicaciones: [String]? = nil) {
        self.pantallas = pantallas; self.titulos = titulos; self.movidos = movidos; self.completadas = completadas
        self.archivados = archivados; self.verificados = verificados; self.planes = planes; self.texto = texto
        self.explicaciones = explicaciones
    }

    /// La explicación de una pantalla del paso 2 por su título (las mismas que enseña «Ordenar lo que tienes»).
    public static func explicacion(_ titulo: String) -> String? { explicacionesPorTitulo[titulo] }

    public static let explicacionesPorTitulo: [String: String] = [
        "Lo que hay": "Miro lo que tienes sin cambiar nada. Lo que solo está en iCloud no lo descargo: lo miro por su nombre. Lo privado ni lo miro.",
        "Preparar": "Propongo un sitio para cada bloque y te digo por qué. Cámbialo si no te cuadra, márcalo como privado o déjalo fuera. Nada se mueve hasta «Aplicar».",
        "Por programa": "De cada programa, elige qué traes: todo, solo lo activo (lo anterior va al Archivo como antecedente) o nada.",
        "Repetidos": "Ficheros iguales en dos sitios: me quedo con uno y aparto los demás al Archivo. Los que solo se parecen en el nombre no se tocan hasta que elijas.",
        "Vista previa": "Esto es lo que haré. Nada se borra: lo que retiro va al Archivo. Si algo no te cuadra, vuelve atrás; después se deshace de una vez.",
        "Comprobación": "He comprobado cada fichero, uno a uno: están todos y cada uno es idéntico por su huella digital. Puedes deshacerlo todo hasta que apliques «Organizar».",
        "Calidad": "Lo que conviene revisar: documentos sin fecha, fichas sin tipo, repetidos y enlaces rotos. Crea una tarea para luego o ignóralo.",
        "Completar las fichas": "Tu carpeta ya está en su sitio: no muevo nada. Solo completo las fichas a las que les falta su tipo, para que la app las reconozca.",
        "Movimientos del banco": "Los movimientos que ya tenías se cargan en preparación: ninguno cuenta como cobrado ni se concilia hasta que lo revises.",
    ]
}

/// Los cinco hitos del «Primer recorrido» (paso 8) sobre la empresa de la persona.
public enum HitoRecorrido: String, Codable, Sendable, Hashable, CaseIterable {
    case hoy
    case areaDelCuello = "area-del-cuello"
    case aprobarPropuesta = "aprobar-propuesta"
    case editarFicha = "editar-ficha"
    case verEnFinder = "ver-en-finder"

    public var titulo: String {
        switch self {
        case .hoy: "Mira Hoy"
        case .areaDelCuello: "Entra en el área del cuello"
        case .aprobarPropuesta: "Aprueba la primera propuesta de Mika, tu asistente de Dirección"
        case .editarFicha: "Edita una ficha"
        case .verEnFinder: "Mírala en Finder"
        }
    }

    /// Hasta F3, aprobar la propuesta de Mika «llegaba con los asistentes». Desde F4 (0.5) se hace de verdad.
    public var llegaConLosAsistentes: Bool { false }
}

/// Todo lo que se guarda en `onboarding.json` tras cada respuesta (criterio F3-3).
public struct EstadoPuestaEnMarcha: Codable, Sendable, Hashable {
    public static let versionActual = 1

    public var version: Int
    /// Carpeta de la empresa (la de `vaults.json`). En «Empiezo de cero» se elige antes de que exista la carpeta.
    public var vaultID: UUID
    /// La ruta, una vez se sabe (si no, sale de las respuestas).
    public var ruta: RutaPuesta?
    /// Quién contesta (el autor de los planes).
    public var persona: String
    /// Pantalla en la que se quedó.
    public var pantalla: String?
    public var respuestas: [String: Respuesta]
    public var pasos: [String: EstadoPaso]
    public var ordenar: ResumenOrdenar?
    public var recorrido: [String: Date]
    /// Consentimiento para usar Claude Code en esta puesta en marcha (`nil`: aún no se ha preguntado).
    public var usarAsistente: Bool?
    /// «Seguir más tarde».
    public var enPausa: Bool
    /// macOS no dejó leer la carpeta elegida: sale la pantalla de recuperación.
    public var permisoDenegado: Bool
    public var creado: Date
    public var actualizado: Date
    public var terminado: Date?
    /// «Quedan ~N min» al guardar (con la carpeta): Hoy y el arranque lo leen sin ella y dicen lo mismo que la ventana.
    public var quedan: Int?

    public init(vaultID: UUID = UUID(), ruta: RutaPuesta? = nil, persona: String = "Manu", ahora: Date = Date()) {
        version = Self.versionActual; self.vaultID = vaultID; self.ruta = ruta; self.persona = persona
        pantalla = nil; respuestas = [:]; pasos = [:]; ordenar = nil; recorrido = [:]; usarAsistente = nil
        enPausa = false; permisoDenegado = false; creado = ahora; actualizado = ahora; terminado = nil; quedan = nil
    }

    enum CodingKeys: String, CodingKey {
        case version, vaultID = "vault_id", ruta, persona, pantalla, respuestas, pasos, ordenar, recorrido
        case usarAsistente = "usar_asistente", enPausa = "en_pausa", permisoDenegado = "permiso_denegado"
        case creado, actualizado, terminado
        case quedan = "quedan_minutos"
    }

    /// Lee también un fichero al que le falten claves (las que añada una versión posterior se ignoran). Respuesta a
    /// respuesta y paso a paso: lo que no se entiende (de otra versión) se salta y no se lleva lo demás por delante
    /// (criterio F3-3). Solo el identificador de la carpeta es obligatorio.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? Self.versionActual
        vaultID = try c.decode(UUID.self, forKey: .vaultID)
        ruta = try? c.decodeIfPresent(RutaPuesta.self, forKey: .ruta)
        persona = (try? c.decodeIfPresent(String.self, forKey: .persona)) ?? "Manu"
        pantalla = try? c.decodeIfPresent(String.self, forKey: .pantalla)
        respuestas = ((try? c.decodeIfPresent([String: Tolerante<Respuesta>].self, forKey: .respuestas)) ?? [:]).compactMapValues(\.valor)
        pasos = ((try? c.decodeIfPresent([String: Tolerante<EstadoPaso>].self, forKey: .pasos)) ?? [:]).compactMapValues(\.valor)
        ordenar = try? c.decodeIfPresent(ResumenOrdenar.self, forKey: .ordenar)
        recorrido = ((try? c.decodeIfPresent([String: Tolerante<Date>].self, forKey: .recorrido)) ?? [:]).compactMapValues(\.valor)
        usarAsistente = try? c.decodeIfPresent(Bool.self, forKey: .usarAsistente)
        enPausa = (try? c.decodeIfPresent(Bool.self, forKey: .enPausa)) ?? false
        permisoDenegado = (try? c.decodeIfPresent(Bool.self, forKey: .permisoDenegado)) ?? false
        creado = (try? c.decodeIfPresent(Date.self, forKey: .creado)) ?? Date()
        actualizado = (try? c.decodeIfPresent(Date.self, forKey: .actualizado)) ?? creado
        terminado = try? c.decodeIfPresent(Date.self, forKey: .terminado)
        quedan = try? c.decodeIfPresent(Int.self, forKey: .quedan)
    }

    public func paso(_ p: PasoPuesta) -> EstadoPaso { pasos[p.rawValue] ?? EstadoPaso() }

    public mutating func ponerPaso(_ p: PasoPuesta, _ e: EstadoPaso) { pasos[p.rawValue] = e }

    public func respuesta(_ id: PreguntaID) -> Respuesta? { respuestas[id.rawValue] }

    public var terminada: Bool { terminado != nil }

    /// Se abrió y se cerró en la bienvenida sin contestar ni aplicar nada: no hay nada que seguir.
    public var sinEmpezar: Bool {
        respuestas.isEmpty && ordenar == nil && pasos.values.allSatisfy { $0.fase == .pendiente }
            && (pantalla.map { $0.hasPrefix(PasoPuesta.bienvenida.rawValue + ".") } ?? true)
    }
}

/// Un valor que, si no se entiende, se queda en `nil` en vez de hacer fallar todo lo que lo contiene.
struct Tolerante<T: Decodable>: Decodable {
    let valor: T?
    /// Por el contenedor (no con `T(from:)`): así las fechas usan la estrategia del decodificador (ISO 8601).
    init(from decoder: Decoder) throws { valor = try? decoder.singleValueContainer().decode(T.self) }
}
