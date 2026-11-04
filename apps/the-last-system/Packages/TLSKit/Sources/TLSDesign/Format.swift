import Foundation
import SwiftUI

/// Formatos visibles en español de España.
public enum TLSFormat {
    /// Entero con punto de millares también en 4 cifras: 1034 → «1.034» (como en el plan).
    public static func entero(_ n: Int) -> String {
        let negativo = n < 0
        let digitos = String(n.magnitude)
        var grupos: [Substring] = []
        var fin = digitos.endIndex
        while fin > digitos.startIndex {
            let inicio = digitos.index(fin, offsetBy: -3, limitedBy: digitos.startIndex) ?? digitos.startIndex
            grupos.insert(digitos[inicio..<fin], at: 0)
            fin = inicio
        }
        return (negativo ? "-" : "") + grupos.joined(separator: ".")
    }

    /// «340 de 1.034» o «340» si no se conoce el total.
    public static func progreso(_ hechos: Int, de total: Int?) -> String {
        guard let total else { return entero(hechos) }
        return "\(entero(hechos)) de \(entero(total))"
    }

    /// «21/10» si es de este año; «21/10/2025» si no.
    public static func fechaCorta(_ date: Date, now: Date = Date(), calendar: Calendar = .tlsGregoriano) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let anio = calendar.component(.year, from: now)
        let base = String(format: "%02d/%02d", c.day ?? 0, c.month ?? 0)
        return c.year == anio ? base : base + "/\(c.year ?? 0)"
    }

    /// «21/10/2026».
    public static func fecha(_ date: Date, calendar: Calendar = .tlsGregoriano) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", c.day ?? 0, c.month ?? 0, c.year ?? 0)
    }

    /// Tamaño legible («1,2 MB»).
    public static func tamano(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "es_ES")))
    }

    /// Plural sencillo: `cuenta(1, "archivo", "archivos")` → «1 archivo».
    public static func cuenta(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(entero(n)) \(n == 1 ? singular : plural)"
    }

    /// Ruta con `~` en lugar de la carpeta personal.
    public static func rutaCorta(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // iCloud Drive, como lo llama el Finder (no su carpeta técnica).
        let icloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if path == icloud { return "iCloud Drive" }
        if path.hasPrefix(icloud + "/") { return "iCloud Drive" + path.dropFirst(icloud.count) }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

public extension Calendar {
    /// Gregoriano en la zona horaria local.
    static var tlsGregoriano: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "es_ES")
        return c
    }
}

/// Fragmentos de búsqueda: los términos encontrados llegan entre «‹» y «›» y se muestran en negrita.
public enum Snippet {
    public static let abre: Character = "‹"
    public static let cierra: Character = "›"

    /// Partes del fragmento: (texto, ¿coincidencia?).
    public static func partes(_ s: String) -> [(text: String, match: Bool)] {
        var out: [(String, Bool)] = []
        var actual = ""
        var dentro = false
        for ch in s {
            if ch == abre && !dentro {
                if !actual.isEmpty { out.append((actual, false)) }
                actual = ""; dentro = true
            } else if ch == cierra && dentro {
                if !actual.isEmpty { out.append((actual, true)) }
                actual = ""; dentro = false
            } else {
                actual.append(ch)
            }
        }
        // Una marca sin cerrar se trata como texto normal.
        if !actual.isEmpty { out.append((dentro ? String(abre) + actual : actual, false)) }
        return out.map { (text: $0.0, match: $0.1) }
    }

    /// Fragmento en una sola línea: saltos y espacios repetidos pasan a un espacio.
    public static func compacto(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Texto sin marcas.
    public static func plain(_ s: String) -> String {
        partes(s).map(\.text).joined()
    }

    /// Texto con las coincidencias en negrita.
    public static func attributed(_ s: String) -> AttributedString {
        var result = AttributedString()
        for parte in partes(s) {
            var a = AttributedString(parte.text)
            if parte.match { a.inlinePresentationIntent = .stronglyEmphasized }
            result += a
        }
        return result
    }
}

/// Texto de un fragmento de búsqueda con las coincidencias en negrita.
public struct SnippetText: View {
    let snippet: String
    public init(_ snippet: String) { self.snippet = snippet }
    public var body: some View {
        Text(Snippet.attributed(Snippet.compacto(snippet)))
            .accessibilityLabel(Snippet.plain(Snippet.compacto(snippet)))
    }
}
