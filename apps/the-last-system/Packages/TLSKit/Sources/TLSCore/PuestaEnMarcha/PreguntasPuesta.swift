import Foundation

// F3 · rol motor. Las preguntas de la puesta en marcha (PLAN §6.7) con sus textos en español llano. Cada pregunta
// admite «No lo sé» (se escribe PENDIENTE), salvo las tres de la bienvenida que deciden por dónde se va y la de las
// carpetas privadas, que es obligatoria (§6.7, paso 0).

/// Identificador estable de una pregunta (`conocer.VEN.funciona`). Es la clave en `onboarding.json`.
public struct PreguntaID: RawRepresentable, Codable, Sendable, Hashable, Comparable, ExpressibleByStringLiteral,
    CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ s: String) { rawValue = s }
    public init(stringLiteral s: String) { rawValue = s }
    public var description: String { rawValue }
    public static func < (a: PreguntaID, b: PreguntaID) -> Bool { a.rawValue < b.rawValue }

    // Bienvenida (0)
    public static let como: PreguntaID = "bienvenida.como"
    public static let origen: PreguntaID = "bienvenida.origen"
    public static let modo: PreguntaID = "bienvenida.modo"
    public static let privadas: PreguntaID = "bienvenida.privadas"
    public static let privadasCuales: PreguntaID = "bienvenida.privadas.cuales"
    public static let nombreEmpresa: PreguntaID = "bienvenida.nombre"
    public static let yo: PreguntaID = "bienvenida.yo"
    public static let sector: PreguntaID = "bienvenida.sector"
    public static let ciudad: PreguntaID = "bienvenida.ciudad"
    public static let personas: PreguntaID = "bienvenida.personas"
    // Alcance (0b)
    public static let alcance: PreguntaID = "alcance.cual"
    public static let alcanceArea: PreguntaID = "alcance.area"
    public static let alcanceProceso: PreguntaID = "alcance.proceso"
    public static let asistente: PreguntaID = "alcance.asistente"
    // Conocer (1)
    public static let camino: PreguntaID = "conocer.camino"
    public static let metaGeneral: PreguntaID = "conocer.meta"
    public static let fraseCliente: PreguntaID = "conocer.frase.cliente"
    public static let fraseResultado: PreguntaID = "conocer.frase.resultado"
    public static let frasePlazo: PreguntaID = "conocer.frase.plazo"
    public static let fraseMetodo: PreguntaID = "conocer.frase.metodo"
    public static let fraseDolor: PreguntaID = "conocer.frase.dolor"
    public static let destino: PreguntaID = "conocer.destino"
    public static var huecosDeLaFrase: [PreguntaID] { [fraseCliente, fraseResultado, frasePlazo, fraseMetodo, fraseDolor] }
    public static func funciona(_ a: AreaCode) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).funciona") }
    public static func depende(_ a: AreaCode) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).depende") }
    public static func dolor(_ a: AreaCode) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).dolor") }
    public static func metaArea(_ a: AreaCode) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).meta") }
    public static func etapaPregunta(_ a: AreaCode, _ n: Int) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).etapa.\(n)") }
    /// La etapa elegida directamente (en el resumen de una carpeta organizada).
    public static func etapa(_ a: AreaCode) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).etapa") }
    public static func cita(_ a: AreaCode) -> PreguntaID { PreguntaID("conocer.\(a.rawValue).cita") }
    // Organizar (3)
    public static func estadoArea(_ a: AreaCode) -> PreguntaID { PreguntaID("organizar.\(a.rawValue).estado") }
    public static func ocupante(_ a: AreaCode) -> PreguntaID { PreguntaID("organizar.\(a.rawValue).ocupante") }
    public static func sistema(_ codigo: String) -> PreguntaID { PreguntaID("organizar.sistema.\(codigo)") }
    public static func ofertaNombre(_ n: Int) -> PreguntaID { PreguntaID("organizar.oferta.\(n).nombre") }
    public static func ofertaPrecio(_ n: Int) -> PreguntaID { PreguntaID("organizar.oferta.\(n).precio") }
    public static let embudo: PreguntaID = "organizar.embudo"
    public static let embudoEtapas: PreguntaID = "organizar.embudo.etapas"
    public static let planEntrega: PreguntaID = "organizar.entrega.plan"
    public static let logo: PreguntaID = "organizar.logo"
    public static let logoFichero: PreguntaID = "organizar.logo.fichero"
    public static let logoWeb: PreguntaID = "organizar.logo.web"
    public static func vocabulario(_ termino: String) -> PreguntaID { PreguntaID("organizar.vocabulario.\(termino)") }
    // Qué funciona sin ti (4), por sistema de los de Organizar (`SistemaCatalogo`: «FI1»). Si está montado lo dice
    // Organizar (`sistema`); `montado` queda solo para leer respuestas de antes.
    public static func montado(_ sistema: String) -> PreguntaID { PreguntaID("sinti.\(sistema).montado") }
    public static func sinTi(_ sistema: String) -> PreguntaID { PreguntaID("sinti.\(sistema).sinti") }
    public static func automatizar(_ sistema: String) -> PreguntaID { PreguntaID("sinti.\(sistema).automatizar") }
    // Tu día a día (5)
    public static let rutinaDia: PreguntaID = "dia.rutina.dia"
    public static let rutinaHora: PreguntaID = "dia.rutina.hora"
    public static let rutinaDuracion: PreguntaID = "dia.rutina.duracion"
    public static let topeHoras: PreguntaID = "dia.tope"
    // Tus números (6)
    public static func numeroClave(_ a: AreaCode) -> PreguntaID { PreguntaID("numeros.\(a.rawValue).codigo") }
    public static func meta(_ a: AreaCode) -> PreguntaID { PreguntaID("numeros.\(a.rawValue).meta") }
    public static func alerta(_ a: AreaCode) -> PreguntaID { PreguntaID("numeros.\(a.rawValue).alerta") }
    public static let objetivo: PreguntaID = "numeros.objetivo"
    public static let objetivoCifra: PreguntaID = "numeros.objetivo.cifra"
    // Conectar (7)
    public static func conexion(_ c: ConexionPuesta) -> PreguntaID { PreguntaID("conectar.\(c.rawValue)") }
    // Primer recorrido (8)
    public static let recorrido: PreguntaID = "recorrido.empezar"
}

/// Una opción de una pregunta de elección.
public struct OpcionPregunta: Sendable, Hashable, Identifiable {
    public let id: String
    public let texto: String
    public let detalle: String?

    public init(_ id: String, _ texto: String, detalle: String? = nil) {
        self.id = id; self.texto = texto; self.detalle = detalle
    }
}

/// Cómo se contesta.
public enum TipoPregunta: Sendable, Hashable {
    case eleccion([OpcionPregunta])
    case escala(minimo: Int, maximo: Int, bajo: String, alto: String)
    case siNo
    case textoCorto(ejemplo: String?)
    /// Texto libre: va en una pantalla propia (PLAN §6.7, normas).
    case textoLibre(ejemplo: String?)
    /// Una cifra con su unidad («€», «meses»…). Con `sinMeta`, también «Sin meta».
    case cifra(unidad: String, sinMeta: Bool)
    case hora
    /// Ficheros o carpetas (los elige la persona con el panel del sistema).
    case rutas(carpetas: Bool, varias: Bool)

    public var esTextoLibre: Bool {
        if case .textoLibre = self { return true }
        return false
    }

    public var opciones: [OpcionPregunta] {
        if case .eleccion(let o) = self { return o }
        return []
    }
}

/// Una pregunta tal como la enseña la pantalla.
public struct Pregunta: Sendable, Hashable, Identifiable {
    public let id: PreguntaID
    public let paso: PasoPuesta
    public let area: AreaCode?
    /// La pregunta, corta.
    public let texto: String
    /// Una línea de ayuda, si hace falta.
    public let ayuda: String?
    public let tipo: TipoPregunta
    /// Siempre `true` salvo en las elecciones de la bienvenida y en las carpetas privadas.
    public let admiteNoLoSe: Bool
    /// Hay que contestarla para seguir (las carpetas privadas).
    public let obligatoria: Bool
    /// Qué le falta si es vaga (el entrevistador repregunta una vez con esto). `nil`: no se repregunta.
    public let repregunta: String?
    /// Lo que la app propone, con su origen («Lo saqué de Rumbo.md»).
    public var premarcada: Respuesta?
    /// Texto de la carpeta para comparar (lo que pone ahora el fichero).
    public var referencia: String?

    public init(id: PreguntaID, paso: PasoPuesta, area: AreaCode? = nil, texto: String, ayuda: String? = nil,
                tipo: TipoPregunta, admiteNoLoSe: Bool = true, obligatoria: Bool = false, repregunta: String? = nil,
                premarcada: Respuesta? = nil, referencia: String? = nil) {
        self.id = id; self.paso = paso; self.area = area; self.texto = texto; self.ayuda = ayuda; self.tipo = tipo
        self.admiteNoLoSe = admiteNoLoSe; self.obligatoria = obligatoria; self.repregunta = repregunta
        self.premarcada = premarcada; self.referencia = referencia
    }
}

/// Las conexiones del paso 7 (cada fila con «Ahora no»).
public enum ConexionPuesta: String, Codable, Sendable, Hashable, CaseIterable {
    case claude, mail, calendario, banco, otros, avisos
    case ventanaCerrada = "ventana-cerrada"

    public var titulo: String {
        switch self {
        case .claude: "Claude Code"
        case .mail: "Mail"
        case .calendario: "Calendario"
        case .banco: "Banco"
        case .otros: "Otros programas"
        case .avisos: "Avisos"
        case .ventanaCerrada: "Trabajar con la ventana cerrada"
        }
    }

    public var detalle: String {
        switch self {
        case .claude: "Los asistentes trabajan con tu Claude Code. Lo pruebo antes de usarlo."
        case .mail: "Leo el correo que tú elijas para ordenar el Buzón. Nada sale sin tu OK."
        case .calendario: "Pongo tu rutina y tus citas en el Calendario del Mac."
        case .banco: "Importas el extracto de tu banco y la app concilia contigo."
        case .otros: "Conectas otros programas que ya usas."
        case .avisos: "Te aviso solo de lo rojo y de lo que decidas."
        case .ventanaCerrada: "La app sigue en la barra de menús al cerrar la ventana. Apagado de serie."
        }
    }
}

// MARK: - Textos del catálogo

/// Los textos de las preguntas (sin jerga: «función», no «capacidad»; «número clave», no «KPI»).
public enum TextosPuesta {
    /// Pasa a palabras llanas los nombres del estándar que llevan jerga (los datos de Programa no se tocan).
    public static func llano(_ s: String) -> String {
        var t = s
        for (de, a) in [("Onboarding de cliente", "Arranque del cliente"), ("Onboarding de equipo", "Incorporación al equipo"),
                        ("Onboarding", "Arranque"), ("agentes", "asistentes"), ("agente", "asistente"),
                        ("Agentes", "Asistentes"), ("Agente", "Asistente"), ("KPI", "número clave"), ("runway", "meses de caja")] {
            t = t.replacingOccurrences(of: de, with: a)
        }
        return t
    }

    /// «las ventas», «la entrega»…
    public static func nombreComun(_ a: AreaCode) -> String {
        switch a {
        case .direccion: "la dirección"
        case .ventas: "las ventas"
        case .entrega: "la entrega"
        case .finanzas: "las finanzas"
        case .marca: "la marca"
        case .equipo: "el equipo"
        }
    }

    /// Título de una pantalla con varias áreas: «Ventas», «Dirección y Ventas», «Dirección, Ventas y Entrega» o, con las
    /// seis, «Tus seis áreas».
    public static func listaDeAreas(_ areas: [AreaCode]) -> String {
        let nombres = areas.map(\.nombre)
        if nombres.count == AreaCode.allCases.count { return "Tus seis áreas" }
        guard nombres.count > 1 else { return nombres.first ?? "Tus áreas" }
        return nombres.dropLast().joined(separator: ", ") + " y " + nombres.last!
    }

    /// «funciona» o «funcionan», según el nombre común del área («¿Cómo funcionan hoy las ventas?»).
    public static func funciona(_ a: AreaCode) -> String {
        let n = nombreComun(a)
        return n.hasPrefix("las ") || n.hasPrefix("los ") ? "funcionan" : "funciona"
    }

    static func mayuscula(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// Las seis preguntas de etapa de un área: se paran en el primer «no» (la etapa es esa).
    public static func preguntaDeEtapa(_ a: AreaCode, _ n: Int) -> String {
        let x = nombreComun(a)
        switch n {
        case 1: return "¿\(mayuscula(x)) ya funciona con clientes reales, aunque sea a tu manera?"
        case 2: return "¿Lo que haces en \(x) está escrito (oferta, guion, pasos) y sale igual cada vez?"
        case 3: return "¿Cada cosa escrita de \(x) tiene quién la hace y cuándo se revisa?"
        case 4: return "¿Lo que en \(x) se decide siempre igual ya va solo, sin hacerlo tú a mano?"
        case 5: return "¿Alguien que no eres tú lleva \(x) y decide en el día a día?"
        default: return "¿\(mayuscula(x)) se dirige con números y criterios escritos, sin que tengas que estar?"
        }
    }

    /// Los tres dolores de cada área (el síntoma del Diagnóstico).
    public static func dolores(_ a: AreaCode) -> [OpcionPregunta] {
        let t: [String]
        switch a {
        case .direccion: t = ["Decido tarde o a ojo", "No sé si vamos bien hasta fin de mes", "Todo pasa por mí"]
        case .ventas: t = ["Los clientes llegan a rachas", "Se me escapan oportunidades sin seguimiento", "Cada precio es distinto"]
        case .entrega: t = ["Cada encargo sale distinto", "Me retraso con lo prometido", "Solo yo sé cómo se hace"]
        case .finanzas: t = ["No sé cuánta caja tengo", "Cobro tarde o se me olvida facturar", "No sé qué margen me deja cada cliente"]
        case .marca: t = ["No me conocen los que importan", "Publico sin constancia", "No sé qué me trae clientes"]
        case .equipo: t = ["Si paro, todo para", "Delego tareas pero lo decido todo yo", "No hay roles escritos"]
        }
        return t.enumerated().map { OpcionPregunta("d\($0.offset + 1)", $0.element) }
    }

    /// Las tres metas de cada área (la pieza que falta del Diagnóstico).
    public static func metas(_ a: AreaCode) -> [OpcionPregunta] {
        let t: [String]
        switch a {
        case .direccion: t = ["Saber cada semana si vamos bien", "Decidir con números y no a ojo", "Un rumbo escrito para el trimestre"]
        case .ventas: t = ["Una oferta escrita con su precio", "Un embudo con seguimiento", "Clientes que llegan sin depender de mí"]
        case .entrega: t = ["Un plan de entrega por servicio", "Cumplir plazos sin apagar fuegos", "Que otro pueda entregar igual"]
        case .finanzas: t = ["Ver la caja de un vistazo", "Facturar y cobrar a tiempo", "Conocer el margen de cada servicio"]
        case .marca: t = ["Una identidad clara: logo y tono", "Publicar con constancia", "Que las conversaciones acaben en clientes"]
        case .equipo: t = ["Roles escritos con su dueño", "Delegar con criterios claros", "Que el equipo funcione sin mí"]
        }
        return t.enumerated().map { OpcionPregunta("m\($0.offset + 1)", $0.element) }
    }

    public static let caminos: [OpcionPregunta] = [
        OpcionPregunta("ordenar", "Ordenar lo que ya funciona"),
        OpcionPregunta("crecer", "Crecer sin trabajar más horas"),
        OpcionPregunta("soltar", "Dejar de ser imprescindible"),
    ]

    public static let metasGenerales: [OpcionPregunta] = [
        OpcionPregunta("dinero", "Ganar más dinero"),
        OpcionPregunta("tiempo", "Tener más tiempo"),
        OpcionPregunta("sin-mi", "Que funcione sin mí"),
    ]

    public static let estadosArea: [OpcionPregunta] = EstadoAreaPuesta.allCases.map {
        OpcionPregunta($0.rawValue, $0.titulo, detalle: detalleEstado($0))
    }

    static func detalleEstado(_ e: EstadoAreaPuesta) -> String {
        switch e {
        case .activa: "Trabajas en ella cada semana."
        case .preparada: "Está escrita, pero aún no le dedicas tiempo."
        case .reposo: "Por ahora no toca."
        }
    }

    public static let estadosSistema: [OpcionPregunta] = [
        OpcionPregunta("montado", "Montado"),
        OpcionPregunta("a medias", "A medias"),
        OpcionPregunta("falta", "Falta"),
    ]

    public static let dias: [OpcionPregunta] = [
        OpcionPregunta("lunes", "Lunes"), OpcionPregunta("martes", "Martes"), OpcionPregunta("miercoles", "Miércoles"),
        OpcionPregunta("jueves", "Jueves"), OpcionPregunta("viernes", "Viernes"),
    ]

    /// Términos de «¿Cómo llamas tú a…?» (el vocabulario de `config.yaml`).
    public static let terminosVocabulario: [(clave: String, texto: String, ejemplo: String)] = [
        ("cliente", "un cliente", "paciente, alumno…"),
        ("oportunidad", "una oportunidad de venta", "caso, presupuesto…"),
        ("proyecto", "un proyecto", "encargo, expediente…"),
        ("servicio", "un servicio", "tratamiento, curso…"),
    ]
}

/// Uno de los 19 sistemas de la propuesta v2 (SISTEMAS §2.5): los que instala el paso 3.
public struct SistemaCatalogo: Sendable, Hashable, Identifiable {
    public var id: String { codigo }
    public let codigo: String
    /// `nil` para el Buzón (CO1), que vive en la raíz.
    public let area: AreaCode?
    public let nombre: String
    /// Nombres que tenía en G3 (se reconoce también por ellos).
    public let alias: [String]
    /// De serie (cualquier empresa) o base (si el área está activa o preparada): se instala aunque falte.
    public let seInstala: Bool
    public let pregunta: String
    public let numeroClave: String?

    /// Los 19, en el orden de la tabla.
    public static let todos: [SistemaCatalogo] = [
        .init(codigo: "CO1", area: nil, nombre: "Correspondencia", alias: [], seInstala: true,
              pregunta: "¿Qué ha llegado y adónde va?", numeroClave: "BUZ-PEND"),
        .init(codigo: "DI1", area: .direccion, nombre: "Decisiones", alias: ["Registro de decisiones"], seInstala: true,
              pregunta: "¿Por qué decidimos lo que decidimos?", numeroClave: "DIR-DEC14"),
        .init(codigo: "DI2", area: .direccion, nombre: "Revisión y replanificación", alias: [], seInstala: true,
              pregunta: "¿Qué toca esta semana y qué se queda fuera?", numeroClave: nil),
        .init(codigo: "DI3", area: .direccion, nombre: "Rumbo y mapa", alias: ["Plan del estudio"], seInstala: true,
              pregunta: "¿Adónde vamos y dónde está el cuello?", numeroClave: nil),
        .init(codigo: "VE1", area: .ventas, nombre: "Oferta", alias: [], seInstala: true,
              pregunta: "¿Qué vendemos, a quién y a qué precio?", numeroClave: nil),
        .init(codigo: "VE2", area: .ventas, nombre: "Embudo", alias: [], seInstala: true,
              pregunta: "¿Por dónde entra y por dónde se cae?", numeroClave: "VEN-STALE7"),
        .init(codigo: "VE3", area: .ventas, nombre: "Referidos y continuidad", alias: ["Upsell y fidelización"],
              seInstala: false, pregunta: "¿Quién vuelve y quién nos recomienda?", numeroClave: "VEN-REF"),
        .init(codigo: "EN1", area: .entrega, nombre: "Arranque del cliente", alias: ["Onboarding"], seInstala: true,
              pregunta: "¿Qué pasa el primer día después de cobrar?", numeroClave: "ENT-ARR48"),
        .init(codigo: "EN2", area: .entrega, nombre: "Gestionar encargo", alias: ["Seguimiento de proyectos"],
              seInstala: true, pregunta: "¿Se entrega igual cada vez?", numeroClave: "ENT-ONTIME"),
        .init(codigo: "EN3", area: .entrega, nombre: "Cierre e incidencias", alias: [], seInstala: true,
              pregunta: "¿Cómo acaba un encargo y qué hacemos si algo sale mal?", numeroClave: "ENT-INC"),
        .init(codigo: "FI1", area: .finanzas, nombre: "Facturación y cobros", alias: [], seInstala: true,
              pregunta: "¿Se factura a tiempo y se cobra?", numeroClave: "FIN-AR"),
        .init(codigo: "FI2", area: .finanzas, nombre: "Tesorería", alias: [], seInstala: true,
              pregunta: "¿Cuántos meses aguanta la caja?", numeroClave: "FIN-RUNWAY"),
        .init(codigo: "FI3", area: .finanzas, nombre: "Control económico", alias: ["Gastos del mes"], seInstala: true,
              pregunta: "¿Qué margen deja cada cosa y llega el trimestre sin sustos?", numeroClave: "FIN-MARGIN"),
        .init(codigo: "MA1", area: .marca, nombre: "Identidad", alias: ["Manual de marca"], seInstala: true,
              pregunta: "¿Se nos reconoce sin ver el logo?", numeroClave: nil),
        .init(codigo: "MA2", area: .marca, nombre: "Contenido", alias: [], seInstala: false,
              pregunta: "¿Qué publicamos y cuándo?", numeroClave: "MAR-PUB"),
        .init(codigo: "MA3", area: .marca, nombre: "Conversaciones y casos", alias: [], seInstala: false,
              pregunta: "¿Qué conversación acaba en cliente?", numeroClave: "MAR-QCONV"),
        .init(codigo: "EQ1", area: .equipo, nombre: "Roles", alias: [], seInstala: true,
              pregunta: "¿Qué decide cada rol y con qué número?", numeroClave: "EQU-ROLES"),
        .init(codigo: "EQ2", area: .equipo, nombre: "Asistentes", alias: ["Agentes de IA"], seInstala: true,
              pregunta: "¿Qué hace cada asistente y con qué permiso?", numeroClave: "EQU-HEALTH"),
        .init(codigo: "EQ3", area: .equipo, nombre: "Acordar colaboración", alias: ["Colaboradores"], seInstala: false,
              pregunta: "¿Cómo trabajamos con alguien de fuera?", numeroClave: "EQU-RUT"),
    ]

    public static func de(_ a: AreaCode) -> [SistemaCatalogo] { todos.filter { $0.area == a } }
    public static func codigo(_ c: String) -> SistemaCatalogo? { todos.first { $0.codigo == c } }

    /// Los sistemas del estándar (`sistemas-std.json`) que cubre cada uno: de ahí salen las funciones que declara
    /// «Qué funciona sin ti». Así los pasos 3 y 4 hablan de los mismos sistemas, con los mismos nombres. Correspondencia,
    /// Referidos y Asistentes no tienen funciones en el estándar: no se preguntan en el paso 4.
    public static let mapaEstandar: [String: [String]] = [
        "DI1": ["DIR-3"], "DI2": ["DIR-4", "DIR-2"], "DI3": ["DIR-1"],
        "VE1": ["VEN-1", "VEN-4"], "VE2": ["VEN-2", "VEN-3"],
        "EN1": ["ENT-2"], "EN2": ["ENT-1"], "EN3": ["ENT-3", "ENT-4"],
        "FI1": ["FIN-1"], "FI2": ["FIN-2"], "FI3": ["FIN-3", "FIN-4"],
        "MA1": ["MAR-1"], "MA2": ["MAR-2", "MAR-3"], "MA3": ["MAR-4"],
        "EQ1": ["EQU-1", "EQU-4"], "EQ3": ["EQU-2", "EQU-3"],
    ]

    /// Códigos del estándar que cubre (`[]` si ninguno).
    public var estandar: [String] { Self.mapaEstandar[codigo] ?? [] }

    /// El sistema (de los 19) que cubre uno del estándar.
    public static func deEstandar(_ std: String) -> SistemaCatalogo? {
        todos.first { $0.estandar.contains(std) }
    }
}

/// El número clave que propone el paso 6 para cada área (el de `numero_clave` de `Área.md` manda si está).
public enum NumerosDeSerie {
    public static func porDefecto(_ a: AreaCode) -> String {
        switch a {
        case .direccion: "DIR-DEC14"
        case .ventas: "VEN-WON"
        case .entrega: "ENT-ONTIME"
        case .finanzas: "FIN-RUNWAY"
        case .marca: "MAR-PUB"
        case .equipo: "EQU-ROLES"
        }
    }

    /// Los que se pueden elegir en cada área (calculables o con fila en la plantilla de Metas).
    public static func opciones(_ a: AreaCode) -> [String] {
        switch a {
        case .direccion: ["DIR-DEC14", "DIR-DEC", "DIR-OBJ"]
        case .ventas: ["VEN-WON", "VEN-STALE7", "VEN-PIPE"]
        case .entrega: ["ENT-ONTIME", "ENT-OVERDUE", "ENT-INC"]
        case .finanzas: ["FIN-RUNWAY", "FIN-AR", "FIN-MARGIN"]
        case .marca: ["MAR-PUB", "MAR-QCONV"]
        case .equipo: ["EQU-ROLES", "EQU-COST"]
        }
    }
}
