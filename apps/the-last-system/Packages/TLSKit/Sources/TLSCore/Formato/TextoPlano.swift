import Foundation

/// Decodificación de ficheros de texto de la carpeta y normalización para comparar.
public enum TextDecoding {
    /// UTF-8 (con o sin BOM), UTF-16 con BOM y, como último recurso, Windows-1252
    /// (extractos de banco antiguos). El BOM no forma parte del texto devuelto.
    public static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .windowsCP1252)
    }

    /// Quita un BOM (U+FEFF) inicial si lo hay.
    public static func strippingBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }
}

/// Texto plegado para buscar: NFC, sin tildes y en minúsculas («Núñez» → «nunez»).
public enum TextFolding {
    public static func fold(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
    }

    /// Clave de nombre para resolver enlaces: NFC y sin distinguir mayúsculas (conserva tildes).
    public static func nameKey(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// Clave para comparar rutas como las compara APFS: NFC y sin distinguir mayúsculas.
    public static func pathKey(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }
}

extension String {
    /// Líneas con sus rangos (respeta `\r\n`, `\n` y `\r`). `content` excluye el salto; `enclosing` lo incluye.
    func lineRanges() -> [(content: Range<String.Index>, enclosing: Range<String.Index>)] {
        var out: [(Range<String.Index>, Range<String.Index>)] = []
        var lineStart = startIndex
        var i = startIndex
        while i < endIndex {
            let c = self[i]
            if c.isNewline {
                let next = index(after: i)
                out.append((lineStart..<i, lineStart..<next))
                lineStart = next
                i = next
            } else {
                i = index(after: i)
            }
        }
        if lineStart < endIndex {
            out.append((lineStart..<endIndex, lineStart..<endIndex))
        }
        return out
    }

    /// Líneas sin el salto final.
    var lines: [Substring] {
        split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }
}
