import CryptoKit
import Foundation

/// Huella SHA-256 en hexadecimal: la del diario, la de `hash_app` y la del índice.
public enum ContentHash {
    public static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Huella de un texto (UTF-8, sin añadir nada).
    public static func of(_ text: String) -> String {
        of(Data(text.utf8))
    }
}

/// Texto UTF-8 de un fichero con el BOM aparte, para reescribirlo byte a byte.
///
/// Solo se editan ficheros UTF-8 válidos: lo demás (UTF-16, Windows-1252) se puede leer,
/// mover y retirar, pero no se cambia por dentro.
struct EditableText: Sendable, Hashable {
    var bom: Bool
    var text: String

    static let bomBytes: [UInt8] = [0xEF, 0xBB, 0xBF]

    init(bom: Bool = false, text: String) {
        self.bom = bom; self.text = text
    }

    /// `nil` si no es UTF-8 válido.
    init?(data: Data) {
        let hasBOM = data.starts(with: Self.bomBytes)
        let payload = hasBOM ? data.dropFirst(3) : data[...]
        guard let s = String(bytes: payload, encoding: .utf8) else { return nil }
        // `String(bytes:encoding:)` es exacto para UTF-8 válido: se comprueba igualmente.
        guard s.utf8.count == payload.count else { return nil }
        self.bom = hasBOM
        self.text = s
    }

    var data: Data {
        var d = Data()
        if bom { d.append(contentsOf: Self.bomBytes) }
        d.append(contentsOf: text.utf8)
        return d
    }

    /// Salto de línea del fichero: el primero que aparece; `\n` si no hay ninguno.
    var eol: String { TextLines.dominantEOL(text) }
}

/// Líneas con su salto exacto (`\n`, `\r\n` o `\r`), para reconstruir el texto sin cambiar un byte.
struct TextLine: Sendable, Hashable {
    var content: String
    var eol: String

    var full: String { content + eol }
    var isBlank: Bool { content.allSatisfy { $0 == " " || $0 == "\t" } }
}

enum TextLines {
    static func isEOL(_ c: Character) -> Bool {
        c == "\n" || c == "\r\n" || c == "\r"
    }

    static func split(_ text: String) -> [TextLine] {
        var out: [TextLine] = []
        var current = ""
        for c in text {
            if isEOL(c) {
                out.append(TextLine(content: current, eol: String(c)))
                current = ""
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { out.append(TextLine(content: current, eol: "")) }
        return out
    }

    static func join(_ lines: [TextLine]) -> String {
        var s = ""
        for l in lines { s += l.content; s += l.eol }
        return s
    }

    static func dominantEOL(_ text: String) -> String {
        for c in text where isEOL(c) { return String(c) }
        return "\n"
    }

    /// Normaliza los saltos de `text` al salto del fichero.
    static func normalized(_ text: String, eol: String) -> String {
        var s = ""
        for c in text {
            if isEOL(c) { s += eol } else { s.append(c) }
        }
        return s
    }

    /// `text` terminado en salto de línea (normalizado a `eol`).
    static func terminated(_ text: String, eol: String) -> String {
        let n = normalized(text, eol: eol)
        if n.isEmpty { return n }
        return n.last.map(isEOL) == true ? n : n + eol
    }
}
