import Foundation
import TLSCore

/// Valor de una propiedad que se escribe en una nota nueva.
enum ValorYAML: Sendable, Hashable {
    /// Texto: se entrecomilla solo si hace falta.
    case texto(String)
    /// Número, fecha `AAAA-MM-DD` o importe: se escribe tal cual.
    case literal(String)
    case bool(Bool)
    /// `"[[destino|Nombre]]"` (siempre entre comillas).
    case enlace(String)
    case lista([ValorYAML])
    /// Mapa en bloque (solo para `.tls/config.yaml` y el formato del extracto).
    case mapa([Propiedad])

    var vacio: Bool {
        switch self {
        case .texto(let s), .literal(let s), .enlace(let s): return s.isEmpty
        case .bool: return false
        case .lista: return false
        case .mapa(let m): return m.isEmpty
        }
    }
}

/// `clave: valor` en el orden en que se escribirá.
struct Propiedad: Sendable, Hashable {
    let clave: String
    let valor: ValorYAML
}

/// Frontmatter de una nota nueva. Las claves vacías no se escriben (SISTEMAS.md §1.5).
struct FrontmatterNuevo: Sendable {
    private(set) var propiedades: [Propiedad] = []

    init(tipo: String, id: String) {
        propiedades = [Propiedad(clave: "tls_type", valor: .texto(tipo)),
                       Propiedad(clave: "tls_schema", valor: .literal("1")),
                       Propiedad(clave: "id", valor: .texto(id))]
    }

    init(propiedades: [Propiedad]) { self.propiedades = propiedades }

    mutating func poner(_ clave: String, _ valor: ValorYAML?) {
        guard let valor, !valor.vacio else { return }
        precondition(!propiedades.contains { $0.clave == clave }, "Clave repetida: \(clave)")
        propiedades.append(Propiedad(clave: clave, valor: valor))
    }

    mutating func texto(_ clave: String, _ s: String?) {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        poner(clave, .texto(s))
    }

    mutating func literal(_ clave: String, _ s: String?) {
        guard let s, !s.isEmpty else { return }
        poner(clave, .literal(s))
    }

    var yaml: String {
        propiedades.map { EscrituraYAML.linea($0, sangria: 0) }.joined(separator: "\n")
    }
}

enum EscrituraYAML {
    static func linea(_ p: Propiedad, sangria: Int) -> String {
        let pad = String(repeating: " ", count: sangria)
        switch p.valor {
        case .mapa(let hijos):
            if hijos.isEmpty { return "\(pad)\(p.clave): {}" }
            return "\(pad)\(p.clave):\n" + hijos.map { linea($0, sangria: sangria + 2) }.joined(separator: "\n")
        default:
            return "\(pad)\(p.clave): \(escalar(p.valor))"
        }
    }

    static func escalar(_ v: ValorYAML) -> String {
        switch v {
        case .texto(let s): return texto(s)
        case .literal(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .enlace(let s): return comillas(s)
        case .lista(let items): return "[" + items.map(elementoDeLista).joined(separator: ", ") + "]"
        case .mapa: return "{}"
        }
    }

    static func elementoDeLista(_ v: ValorYAML) -> String {
        switch v {
        case .texto(let s):
            return esSeguroEnLista(s) ? s : comillas(s)
        default:
            return escalar(v)
        }
    }

    /// Palabras que YAML (1.1 o 1.2) leería como booleano o nulo.
    static let reservadas: Set<String> = ["true", "false", "yes", "no", "on", "off", "y", "n", "null", "~"]

    /// Texto plano si YAML lo lee igual; si no, entre comillas dobles.
    static func texto(_ s: String) -> String {
        esSeguroPlano(s) ? s : comillas(s)
    }

    static func esSeguroPlano(_ s: String) -> Bool {
        guard let primero = s.first, let ultimo = s.last else { return false }
        if primero.isWhitespace || ultimo.isWhitespace { return false }
        if "-?:,[]{}#&*!|>'\"%@`".contains(primero) { return false }
        if pareceOtroTipo(s) { return false }
        if reservadas.contains(s.lowercased()) { return false }
        if s.contains(": ") || s.contains(" #") || ultimo == ":" { return false }
        if s.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0 == "\u{FEFF}" }) { return false }
        if s.contains("{{") { return false }
        return true
    }

    /// `true` si YAML (1.1 o 1.2) leería el texto como número, fecha u hora: `150`, `1e3`, `0x1F`,
    /// `.inf`, `2026-10-19`, `10:30`. Un identificador como `79f8cc54-0e5c-…` es texto.
    static func pareceOtroTipo(_ s: String) -> Bool {
        let patrones = [
            #"^[-+]?[0-9][0-9_]*(\.[0-9_]*)?([eE][-+]?[0-9]+)?$"#,
            #"^[-+]?\.[0-9]+([eE][-+]?[0-9]+)?$"#,
            #"^0[xX][0-9a-fA-F_]+$"#, #"^0[oO]?[0-7_]+$"#, #"^0[bB][01_]+$"#,
            #"^[-+]?\.(inf|Inf|INF)$"#, #"^\.(nan|NaN|NAN)$"#,
            #"^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}"#,
            #"^[-+]?[0-9][0-9_]*(:[0-5]?[0-9])+(\.[0-9_]*)?$"#,
        ]
        return patrones.contains { s.range(of: $0, options: .regularExpression) != nil }
    }

    /// En una lista en línea, además, sin comas ni corchetes.
    static func esSeguroEnLista(_ s: String) -> Bool {
        esSeguroPlano(s) && !s.contains(",") && !s.contains("[") && !s.contains("]") && !s.contains("{") && !s.contains("}")
    }

    static func comillas(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if u.properties.generalCategory == .control || u == "\u{FEFF}" {
                    out += String(format: "\\u%04X", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        return out + "\""
    }
}

/// Una nota v2: propiedades, `# Título`, línea de resumen `> …` y secciones `##` en orden fijo.
struct NotaNueva: Sendable {
    var frontmatter: FrontmatterNuevo?
    var titulo: String?
    /// Tramos de la línea de resumen; los vacíos desaparecen con su separador.
    var resumen: [String?] = []
    /// Texto libre entre el resumen y la primera sección.
    var entradilla: String?
    var secciones: [(titulo: String, contenido: String?)] = []
    /// Texto al final (`Fuente: …`).
    var pie: String?
    /// Cuerpo completo ya escrito (sustituye a título, resumen y secciones).
    var cuerpoLiteral: String?

    mutating func seccion(_ titulo: String, _ contenido: String? = nil) {
        secciones.append((titulo, contenido?.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    var texto: String {
        var out = ""
        if let fm = frontmatter {
            out += "---\n" + fm.yaml + "\n---\n"
        }
        if let literal = cuerpoLiteral {
            return out + literal
        }
        var bloques: [String] = []
        var cabecera: [String] = []
        if let titulo { cabecera.append("# " + titulo) }
        let tramos = resumen.compactMap { t -> String? in
            guard let t = t?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
            return t
        }
        if !tramos.isEmpty { cabecera.append("> " + tramos.joined(separator: " · ")) }
        if !cabecera.isEmpty { bloques.append(cabecera.joined(separator: "\n")) }
        if let e = entradilla?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { bloques.append(e) }
        for s in secciones {
            if let c = s.contenido, !c.isEmpty {
                bloques.append("## \(s.titulo)\n\(c)")
            } else {
                bloques.append("## \(s.titulo)")
            }
        }
        if let pie = pie?.trimmingCharacters(in: .whitespacesAndNewlines), !pie.isEmpty { bloques.append(pie) }
        return out + bloques.joined(separator: "\n\n") + "\n"
    }
}

/// CSV con coma, `\n` y comillas solo donde hacen falta (RFC 4180).
enum EscrituraCSV {
    static func texto(cabecera: [String], filas: [[String]]) -> String {
        ([cabecera] + filas).map { $0.map(campo).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    static func campo(_ s: String) -> String {
        // Por escalares: en Swift «\r\n» es un solo carácter y `contains("\n")` no lo ve.
        let necesita = s.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            || s.first == " " || s.last == " "
        guard necesita else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Tablas Markdown (con `|` escapado dentro de las celdas).
enum TablaMarkdown {
    static func texto(_ cabecera: [String], _ filas: [[String]]) -> String {
        var lineas = [fila(cabecera), "|" + cabecera.map { _ in "---" }.joined(separator: "|") + "|"]
        lineas += filas.map(fila)
        return lineas.joined(separator: "\n")
    }

    static func fila(_ celdas: [String]) -> String {
        "| " + celdas.map {
            $0.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        }
            .joined(separator: " | ") + " |"
    }
}
