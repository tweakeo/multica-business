import Foundation
import TLSCore

// F4 · rol «roles». Las grabaciones de los asistentes de Ribera (`Simulado/Grabaciones/`, PLAN §6.8): `stream-json`
// como el de Claude Code 2.1.307, con llamadas a las herramientas `tls_*` que `SimulatedRuntime` ejecuta de verdad.
// `indice.json` dice qué cuenta cada una y, para el chat (⌘J), qué palabras la eligen. Todo lo que producen se
// enseña con la marca «Simulado».

/// Una grabación del índice.
public struct GrabacionDeEjemplo: Sendable, Hashable, Codable, Identifiable {
    public var id: String { nombre }
    /// Fichero sin extensión (`mika-algo-rojo` → `mika-algo-rojo.jsonl`).
    public let nombre: String
    /// Slug del asistente (vacío en la genérica).
    public let asistente: String
    /// `rutina`, `evento`, `respuesta`, `chat`… (`TipoDeDisparo`); vacío en la genérica.
    public let disparo: String
    /// La rutina, el tipo de evento, el tema del chat o la grabación a la que responde.
    public let clave: String
    public let titulo: String
    /// Solo en el chat: palabras (sin tildes ni mayúsculas) que la eligen.
    public let palabras: [String]?
    /// Qué deja en la carpeta, en palabras.
    public let deja: [String]
}

/// `indice.json`.
public struct IndiceDeGrabaciones: Sendable, Hashable, Codable {
    public let version: Int
    public let empresa: String
    public let hoy: String
    public let nota: String
    public let grabaciones: [GrabacionDeEjemplo]

    public func grabacion(_ nombre: String) -> GrabacionDeEjemplo? { grabaciones.first { $0.nombre == nombre } }
}

public enum GrabacionesDeEjemplo {
    /// La carpeta de las grabaciones dentro del paquete (`Bundle.module`).
    public static var carpeta: URL? {
        Bundle.module.url(forResource: "Grabaciones", withExtension: nil)
    }

    public static func indice(en carpeta: URL) throws -> IndiceDeGrabaciones {
        try JSONDecoder().decode(IndiceDeGrabaciones.self, from: Data(contentsOf: carpeta.appendingPathComponent("indice.json")))
    }

    /// El índice de las grabaciones del paquete.
    public static func indice() -> IndiceDeGrabaciones? {
        carpeta.flatMap { try? indice(en: $0) }
    }

    /// Nombres de grabación que tocan a un disparo, de la más concreta a la más general (`PeticionDeEjecucion.grabaciones`;
    /// `SimulatedRuntime` añade `generica` al final).
    /// - Parameters:
    ///   - clave: la rutina (`algo-rojo`), el tipo de evento (`extracto.importado`), la acción rápida o el plazo.
    ///   - texto: en el chat, lo que escribió la persona (elige por palabras con el índice).
    public static func nombres(agente: String, disparo: TipoDeDisparo, clave: String? = nil, texto: String? = nil,
                               indice: IndiceDeGrabaciones? = nil) -> [String] {
        let s = ConfigAgentes.slug(agente)
        var out: [String] = []
        if disparo == .chat, let texto, let elegido = paraChat(texto, agente: s, indice: indice ?? self.indice()) {
            out.append(elegido)
        }
        if let c = clave?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            out.append("\(s)-\(c.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: ":", with: "-"))")
        }
        out += ["\(s)-\(disparo.rawValue)", s]
        var vistos = Set<String>()
        return out.filter { vistos.insert($0).inserted }
    }

    /// La grabación de chat de ese asistente cuyas palabras aparecen más en el texto (`nil` si ninguna).
    public static func paraChat(_ texto: String, agente: String = "mika", indice: IndiceDeGrabaciones?) -> String? {
        guard let indice else { return nil }
        let palabras = Set(TextFolding.fold(texto).split { !$0.isLetter && !$0.isNumber }.map(String.init))
        var mejor: (String, Int)?
        for g in indice.grabaciones where g.disparo == TipoDeDisparo.chat.rawValue && g.asistente == agente {
            let n = (g.palabras ?? []).filter { palabras.contains(TextFolding.fold($0)) }.count
            if n > 0, n > (mejor?.1 ?? 0) { mejor = (g.nombre, n) }
        }
        return mejor?.0
    }
}
