import Foundation

// F3 · rol motor. El entrevistador (PLAN §6.7): si una respuesta es vaga, repregunta **una vez**. Sin asistente, con
// una lista fija de reglas; con Claude Code (opcional y con consentimiento), con `claude -p --json-schema
// --no-session-persistence` dentro del sandbox (`LanzadorEntrevista`, que da TLSOnboarding con TLSAgents). Al
// asistente solo le llegan la pregunta y lo que escribió la persona; nunca nada privado. Si falla, decide la lista fija.

/// Lo que se le pregunta al asistente.
public struct ConsultaEntrevista: Codable, Sendable, Hashable {
    public let pregunta: String
    public let respuesta: String
    /// Qué se espera de una buena respuesta.
    public let criterio: String
    /// La repregunta de serie (el asistente la puede mejorar).
    public let repregunta: String
}

/// Lo que contesta el asistente (forma fija: `InterviewEngine.esquemaJSON`).
public struct ValoracionEntrevista: Codable, Sendable, Hashable {
    public let vaga: Bool
    public let repregunta: String?
}

/// Lanza una consulta con salida JSON (en la app: Claude Code en el sandbox; en pruebas: un ejecutable falso).
public protocol LanzadorEntrevista: Sendable {
    /// Devuelve el JSON que da el asistente (con la forma de `esquema`).
    func pedir(_ mensaje: String, esquema: String) async throws -> String
}

public enum ResultadoEntrevista: Sendable, Hashable {
    case aceptar
    case repreguntar(String)
}

public struct InterviewEngine: Sendable {
    /// `nil`: sin asistente (solo la lista fija).
    public var lanzador: (any LanzadorEntrevista)?

    public init(lanzador: (any LanzadorEntrevista)? = nil) { self.lanzador = lanzador }

    /// Forma de la respuesta del asistente (`--json-schema`).
    public static let esquemaJSON = #"{"type":"object","properties":{"vaga":{"type":"boolean"},"repregunta":{"type":"string"}},"required":["vaga"],"additionalProperties":false}"#

    /// Valora una respuesta. Solo se llama una vez por pregunta (lo controla el motor con `repreguntada`).
    public func valorar(_ p: Pregunta, respuesta: String, conAsistente: Bool, privado: [String] = []) async -> ResultadoEntrevista {
        guard let repregunta = p.repregunta else { return .aceptar }
        let fija = Self.determinista(p, respuesta: respuesta)
        // Lo privado nunca sale: si la respuesta nombra una carpeta privada, decide la lista fija.
        let nombraPrivado = privado.contains { !$0.isEmpty && TextFolding.fold(respuesta).contains(TextFolding.fold($0)) }
        guard conAsistente, !nombraPrivado, let lanzador else { return fija }
        let consulta = ConsultaEntrevista(pregunta: p.texto, respuesta: respuesta, criterio: Self.criterio(p),
                                          repregunta: repregunta)
        guard let mensaje = Self.mensaje(consulta),
              let texto = try? await lanzador.pedir(mensaje, esquema: Self.esquemaJSON),
              let v = Self.leer(texto) else { return fija }
        guard v.vaga else { return .aceptar }
        let r = v.repregunta?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .repreguntar(r.isEmpty ? repregunta : r)
    }

    static func criterio(_ p: Pregunta) -> String {
        if p.id == .destino { return "Una frase concreta con al menos un número (dinero, horas, clientes o fecha)." }
        if case .textoLibre = p.tipo { return "Un ejemplo concreto, con lo que pasó y cuándo; no una palabra suelta." }
        return "Concreto y específico: a quién, qué o cuánto. Nada de «de todo», «bien» o «depende»."
    }

    static func mensaje(_ c: ConsultaEntrevista) -> String? {
        guard let json = try? String(data: JSONEncoder().encode(c), encoding: .utf8) else { return nil }
        return """
        Eres el entrevistador de la puesta en marcha de una pequeña empresa. Valora si la respuesta es vaga según el \
        criterio. Si lo es, escribe una sola repregunta corta, amable y en español de España, sin tecnicismos. \
        Contesta solo con el JSON pedido.
        \(json)
        """
    }

    /// Lee la salida del asistente (el JSON tal cual o dentro de un texto).
    static func leer(_ texto: String) -> ValoracionEntrevista? {
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if let d = t.data(using: .utf8), let v = try? JSONDecoder().decode(ValoracionEntrevista.self, from: d) { return v }
        guard let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b,
              let d = String(t[a...b]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ValoracionEntrevista.self, from: d)
    }

    // MARK: Lista fija

    /// Palabras que no dicen nada por sí solas.
    static let vacias: Set<String> = [
        "no se", "nose", "ns", "depende", "varios", "varias", "de todo", "todo", "nada", "bien", "mal", "regular",
        "normal", "lo normal", "mejorar", "crecer", "mas", "muchos", "mucho", "poco", "algo", "cosas", "etc",
        "lo que sea", "cualquiera", "gente", "clientes", "empresas", "dinero", "x", "-", "?", "ok", "vale", "si", "no",
        "lo de siempre", "lo mismo", "ganar dinero", "mas clientes", "mas dinero", "ser mejores", "ir bien",
    ]

    static let numerosEscritos: Set<String> = [
        "uno", "una", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve", "diez", "veinte", "treinta",
        "cuarenta", "cincuenta", "cien", "mil", "doble", "triple", "mitad",
    ]

    /// Vaga si es demasiado corta, si solo dice palabras vacías o, en la frase destino, si no lleva un número.
    public static func determinista(_ p: Pregunta, respuesta: String) -> ResultadoEntrevista {
        guard let repregunta = p.repregunta else { return .aceptar }
        let t = TextFolding.fold(respuesta).trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:¡!¿?«»\"' "))
        let palabras = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let minimo = p.tipo.esTextoLibre ? 4 : 2
        var vaga = palabras.count < minimo || vacias.contains(t)
        if !vaga, palabras.allSatisfy({ vacias.contains($0) || $0.count <= 2 }) { vaga = true }
        if !vaga, p.id == .destino {
            let conNumero = t.contains(where: \.isNumber) || palabras.contains(where: numerosEscritos.contains)
            if !conNumero { vaga = true }
        }
        return vaga ? .repreguntar(repregunta) : .aceptar
    }
}
