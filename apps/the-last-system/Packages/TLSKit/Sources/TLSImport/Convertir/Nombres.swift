import CryptoKit
import Foundation
import TLSCore

/// Nombres de fichero, enlaces e identificadores de la carpeta v2 (SISTEMAS.md §1.6 y §1.7).
enum Nombres {
    /// Kebab ASCII («Talleres Martín e Hijos» → `talleres-martin-e-hijos`), 60 caracteres como máximo,
    /// cortando por un guion cuando se puede.
    static func kebab(_ texto: String, maximo: Int = 60) -> String {
        let plegado = texto.precomposedStringWithCanonicalMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "es_ES"))
            .lowercased()
        var out = ""
        var guion = false
        for u in plegado.unicodeScalars {
            if u.isASCII, CharacterSet.alphanumerics.contains(u) {
                out.unicodeScalars.append(u); guion = false
            } else if !out.isEmpty, !guion {
                out.append("-"); guion = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return recortar(out, maximo: maximo)
    }

    static func recortar(_ slug: String, maximo: Int) -> String {
        guard slug.count > maximo else { return slug }
        let corto = String(slug.prefix(maximo))
        if let guion = corto.lastIndex(of: "-"), corto.distance(from: corto.startIndex, to: guion) >= maximo / 2 {
            return String(corto[..<guion])
        }
        return corto.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Quita la huella que G2 añade al nombre del fichero (`jorge-martin--bcceae65` → `jorge-martin`).
    static func sinHuellaG2(_ stem: String) -> String {
        guard let r = stem.range(of: #"--[0-9a-f]{8}$"#, options: .regularExpression) else { return stem }
        let limpio = String(stem[..<r.lowerBound])
        return limpio.isEmpty ? stem : limpio
    }

    /// Formas jurídicas que no forman parte del nombre corto de una empresa.
    static let formasJuridicas: Set<String> = ["sl", "slp", "slu", "sll", "sa", "sau", "sc", "scp", "cb", "sccl", "coop"]

    /// `talleres-martin-e-hijos-sl` → `talleres-martin-e-hijos` (nunca deja el nombre vacío).
    static func sinFormaJuridica(slug: String) -> String {
        var partes = slug.split(separator: "-").map(String.init)
        while partes.count > 1, let ultima = partes.last, formasJuridicas.contains(ultima) { partes.removeLast() }
        return partes.joined(separator: "-")
    }

    /// «Inmobiliaria Centro SL» → «Inmobiliaria Centro».
    static func sinFormaJuridica(nombre: String) -> String {
        var palabras = nombre.split(separator: " ").map(String.init)
        while palabras.count > 1, let ultima = palabras.last,
              formasJuridicas.contains(ultima.lowercased().replacingOccurrences(of: ".", with: "")) {
            palabras.removeLast()
        }
        return palabras.joined(separator: " ")
    }

    /// Nombre de fichero seguro (sin barras ni dos puntos) conservando tildes y espacios.
    static func nombreDeFichero(_ texto: String) -> String {
        let prohibidos = CharacterSet(charactersIn: "/:\\\n\r\t")
        let limpio = texto.unicodeScalars.map { prohibidos.contains($0) ? " " : String($0) }.joined()
        return limpio.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
    }

    /// Enlace Markdown relativo al estilo de G3: `../Empresas/talleres-martin-e-hijos.md`, con `%20`.
    static func rutaRelativa(desde origen: VaultPath, a destino: VaultPath) -> String {
        let base = origen.parent?.components ?? []
        let dest = destino.components
        var comunes = 0
        while comunes < min(base.count, dest.count - 1), base[comunes] == dest[comunes] { comunes += 1 }
        let subir = Array(repeating: "..", count: base.count - comunes)
        let partes = subir + dest[comunes...].map(codificar)
        return partes.joined(separator: "/")
    }

    /// Codifica lo que rompe un enlace Markdown (espacios, paréntesis, `%`, `<`, `>`, `#`).
    static func codificar(_ componente: String) -> String {
        var out = ""
        for c in componente {
            switch c {
            case " ": out += "%20"
            case "%": out += "%25"
            case "(": out += "%28"
            case ")": out += "%29"
            case "<": out += "%3C"
            case ">": out += "%3E"
            case "#": out += "%23"
            default: out.append(c)
            }
        }
        return out
    }

    /// `[Texto](ruta relativa)`.
    static func enlaceMarkdown(_ texto: String, desde origen: VaultPath, a destino: VaultPath) -> String {
        let visible = texto.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
        return "[\(visible)](\(rutaRelativa(desde: origen, a: destino)))"
    }

    /// Texto visible de un wikilink (sin `|` ni corchetes que lo rompan).
    static func textoDeWikilink(_ texto: String) -> String {
        texto.replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }
}

/// Identificadores estables para las notas nuevas: UUID v5 a partir de una semilla (misma semilla, mismo id).
enum IDsDerivados {
    /// Espacio de nombres propio de la conversión G2 → v2.
    static let espacio = UUID(uuidString: "6f2b4c1e-8f2a-5b8e-9c3d-1a7e5f0b2c44")!

    static func id(_ semilla: String) -> String {
        var bytes = withUnsafeBytes(of: espacio.uuid) { Array($0) }
        bytes += Array(semilla.precomposedStringWithCanonicalMapping.utf8)
        var h = Array(Insecure.SHA1.hash(data: bytes)).prefix(16).map { $0 }
        h[6] = (h[6] & 0x0F) | 0x50
        h[8] = (h[8] & 0x3F) | 0x80
        let u = UUID(uuid: (h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9], h[10], h[11], h[12], h[13], h[14], h[15]))
        return u.uuidString.lowercased()
    }
}

/// Importes en céntimos escritos como pide el diccionario (euros con punto) o para leer (`181,50 €`).
enum Dinero {
    /// `15000` → `150.00`; `-66300` → `-663.00`.
    static func texto(_ centimos: Int) -> String {
        let signo = centimos < 0 ? "-" : ""
        let a = abs(centimos)
        return "\(signo)\(a / 100).\(String(format: "%02d", a % 100))"
    }

    /// `1840000` → `18.400,00 €`.
    static func legible(_ centimos: Int, simbolo: String = "€") -> String {
        let signo = centimos < 0 ? "-" : ""
        let a = abs(centimos)
        var entero = String(a / 100)
        if entero.count > 3 {
            var grupos: [String] = []
            while entero.count > 3 {
                grupos.insert(String(entero.suffix(3)), at: 0)
                entero = String(entero.dropLast(3))
            }
            grupos.insert(entero, at: 0)
            entero = grupos.joined(separator: ".")
        }
        return "\(signo)\(entero),\(String(format: "%02d", a % 100)) \(simbolo)"
    }

    /// `181,50` (como en el nombre de los PDF).
    static func coma(_ centimos: Int) -> String {
        let signo = centimos < 0 ? "-" : ""
        let a = abs(centimos)
        return "\(signo)\(a / 100),\(String(format: "%02d", a % 100))"
    }

    /// Puntos básicos a porcentaje: `2100` → `21`, `1050` → `10.5`.
    static func porcentaje(puntosBasicos bp: Int) -> String {
        if bp % 100 == 0 { return String(bp / 100) }
        if bp % 10 == 0 { return "\(bp / 100).\(abs(bp % 100) / 10)" }
        return "\(bp / 100).\(String(format: "%02d", abs(bp % 100)))"
    }

    /// Porcentaje exacto `parte / base` con dos decimales como mucho; `nil` si no es exacto.
    static func porcentaje(parte: Int, base: Int) -> String? {
        guard base != 0 else { return nil }
        let bp10000 = parte * 10_000
        guard bp10000 % base == 0 else { return nil }
        return porcentaje(puntosBasicos: bp10000 / base)
    }
}
