import Foundation
import TLSCore

// Qué sabe el motor de cada asistente que no está en `config.yaml`: quién es, su pregunta fija, sus instrucciones de
// rol y a qué eventos responde. Lo pone el rol «roles» en `Sources/TLSAgents/Roles/` (instrucciones reescritas con el
// patrón Qué haces · Qué no haces nunca · Escalado · Entrega, PLAN §5.1). El motor solo lo consume.

/// Un asistente tal como lo describe su rol (PLAN §5.1).
public struct RolDeAsistente: Sendable, Hashable {
    /// `mika`, `comercial`… (igual que en `config.yaml › agentes`).
    public var slug: String
    /// Cómo se llama en pantalla: «Mika», «Comercial».
    public var nombre: String
    /// Área propia por defecto (la de `config.yaml` manda si la hay).
    public var area: AreaCode?
    public var coordinador: Bool
    /// La pregunta que se hace siempre («¿Hay algo en rojo que te tenga que contar?»).
    public var preguntaFija: String
    /// Quién es, en una o dos frases («Eres Mika, la asistente de Dirección…»). Sin ella, la monta el brief.
    public var identidad: String?
    /// Instrucciones del rol en Markdown: Qué haces · Qué no haces nunca · Escalado · Entrega.
    public var instrucciones: String
    /// Herramientas `tls_*` que usa (para listarlas en el brief). Vacío = las de lectura y suelo de serie.
    public var herramientas: [String]
    /// Tipos de evento del dominio que le hacen trabajar (`contacto.creado`, `extracto.importado`…).
    public var eventos: [String]
    /// Qué hacer con cada evento (va en el primer mensaje); sin entrada, «Ha pasado: <tipo>».
    public var instruccionesPorEvento: [String: String]
    /// Rutinas de serie (si `config.yaml` no trae ninguna para este asistente).
    public var rutinasDeSerie: [RutinaDeAsistente]
    /// Lo que nunca hace (se repite en el brief, además de lo que ya prohíbe el núcleo).
    public var nunca: [String]

    public init(slug: String, nombre: String, area: AreaCode? = nil, coordinador: Bool = false, preguntaFija: String,
                identidad: String? = nil, instrucciones: String, herramientas: [String] = [], eventos: [String] = [],
                instruccionesPorEvento: [String: String] = [:], rutinasDeSerie: [RutinaDeAsistente] = [],
                nunca: [String] = []) {
        self.slug = slug; self.nombre = nombre; self.area = area; self.coordinador = coordinador
        self.preguntaFija = preguntaFija; self.identidad = identidad; self.instrucciones = instrucciones
        self.herramientas = herramientas; self.eventos = eventos; self.instruccionesPorEvento = instruccionesPorEvento
        self.rutinasDeSerie = rutinasDeSerie; self.nunca = nunca
    }
}

/// Catálogo de asistentes que consume el motor. Lo implementa el rol «roles» (`Sources/TLSAgents/Roles/`).
public protocol CatalogoDeAsistentes: Sendable {
    /// Todos los que conoce, en el orden en que se enseñan.
    var roles: [RolDeAsistente] { get }
}

extension CatalogoDeAsistentes {
    public func rol(_ slug: String) -> RolDeAsistente? { roles.first { $0.slug == slug } }

    /// Asistentes que responden a un tipo de evento.
    public func atienden(evento tipo: String) -> [RolDeAsistente] { roles.filter { $0.eventos.contains(tipo) } }

    /// `@Comercial`, `@agente:comercial`, `@mika` → slug (sin acentos ni mayúsculas).
    public func slug(deMencion texto: String) -> String? {
        var t = texto.hasPrefix("@") ? String(texto.dropFirst()) : texto
        if t.hasPrefix("agente:") { t = String(t.dropFirst("agente:".count)) }
        let f = TextFolding.fold(t)
        return roles.first { $0.slug == f || TextFolding.fold($0.nombre) == f }?.slug
    }

    /// Nombre para la persona: «Comercial (asistente)».
    public func nombreVisible(_ slug: String) -> String {
        "\(rol(slug)?.nombre ?? slug.capitalized) (asistente)"
    }
}

/// Catálogo hecho a mano (pruebas, y hasta que esté el de serie).
public struct CatalogoFijo: CatalogoDeAsistentes {
    public var roles: [RolDeAsistente]
    public init(_ roles: [RolDeAsistente]) { self.roles = roles }
}
