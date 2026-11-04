import Foundation

/// Importes exactos en céntimos (`Int`): ni `Double` ni redondeos al sumar.
///
/// Lee los importes como los escriben los registros (`108.90`, `-663.00`) y los extractos de banco
/// (`-1.234,56`, `1,234.56`, `181,50 €`), y los escribe como los registros (`-663.00`), como la gestoría
/// (`-663,00`) o para leer (`-663,00 €`). Lo que no es un importe da `nil`: nunca se toma como 0.
public enum DineroExacto {
    /// Tope de cifras de un importe (céntimos incluidos): por encima no es un importe de banco.
    static let maxCifras = 15

    /// Importe de un registro (punto decimal). Acepta también la coma decimal si no hay punto
    /// (`108,90`), el signo delante o detrás (`-5`, `5-`), «−», «+», espacios y «€».
    public static func centimos(_ texto: String) -> Int? {
        let t = limpiar(texto)
        // Con los dos separadores, el decimal es el último («1.234,56», «1,234.56»).
        if let ultimo = t.last(where: { $0 == "." || $0 == "," }) { return centimos(texto, decimal: ultimo) }
        return centimos(texto, decimal: ".")
    }

    /// Importe con el separador decimal dado; el otro separador se toma como separador de miles
    /// (`1.234,56` con `,`; `1,234.56` con `.`). Más de dos decimales solo si sobran ceros (`1,500`).
    public static func centimos(_ texto: String, decimal: Character) -> Int? {
        var t = limpiar(texto)
        guard !t.isEmpty else { return nil }
        var negativo = false
        if let f = t.first, f == "-" || f == "+" {
            negativo = f == "-"
            t.removeFirst()
        } else if t.last == "-" {
            negativo = true
            t.removeLast()
        }
        if t.hasPrefix("(") && t.hasSuffix(")") {
            negativo = true
            t = String(t.dropFirst().dropLast())
        }
        let miles: Character = decimal == "," ? "." : ","
        let partes = t.split(separator: decimal, omittingEmptySubsequences: false)
        guard partes.count <= 2 else { return nil }
        let entera = partes[0].filter { $0 != miles && $0 != "'" }
        var fraccion = partes.count == 2 ? String(partes[1]) : ""
        guard !entera.isEmpty || !fraccion.isEmpty,
              entera.allSatisfy({ $0.isASCII && $0.isNumber }),
              fraccion.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        // Los separadores de miles van de tres en tres («1.234.567»).
        if partes[0].contains(miles) {
            let grupos = partes[0].split(separator: miles, omittingEmptySubsequences: false)
            guard let primero = grupos.first, (1...3).contains(primero.count),
                  grupos.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        while fraccion.count > 2, fraccion.last == "0" { fraccion.removeLast() }
        guard fraccion.count <= 2 else { return nil }
        while fraccion.count < 2 { fraccion += "0" }
        let cifras = (entera.isEmpty ? "0" : entera) + fraccion
        let sinCeros = cifras.drop(while: { $0 == "0" })
        guard sinCeros.count <= maxCifras, let valor = Int(cifras) else { return nil }
        return negativo ? -valor : valor
    }

    /// Quita espacios (también los de no separación), «€», «EUR» y cambia «−» por «-».
    static func limpiar(_ texto: String) -> String {
        var t = texto.replacingOccurrences(of: "\u{2212}", with: "-")
        t = t.replacingOccurrences(of: "EUR", with: "", options: .caseInsensitive)
        return String(t.unicodeScalars.filter { s in
            !(CharacterSet.whitespacesAndNewlines.contains(s) || s == "\u{00A0}" || s == "\u{202F}" || s == "€")
        }.map(Character.init))
    }

    /// Como lo escriben los registros: `-663.00`.
    public static func csv(_ c: Int) -> String {
        texto(c, decimal: ".", miles: nil)
    }

    /// Como lo lee una hoja de cálculo en español: `-663,00` (sin separador de miles).
    public static func coma(_ c: Int) -> String {
        texto(c, decimal: ",", miles: nil)
    }

    /// Para leer: `-1.234,56 €`.
    public static func euros(_ c: Int) -> String {
        texto(c, decimal: ",", miles: ".") + " €"
    }

    static func texto(_ c: Int, decimal: String, miles: String?) -> String {
        let negativo = c < 0
        let a = c.magnitude
        var entera = String(a / 100)
        if let miles, entera.count > 3 {
            var grupos: [String] = []
            while entera.count > 3 {
                grupos.insert(String(entera.suffix(3)), at: 0)
                entera.removeLast(3)
            }
            grupos.insert(entera, at: 0)
            entera = grupos.joined(separator: miles)
        }
        let cent = a % 100
        return (negativo ? "-" : "") + entera + decimal + (cent < 10 ? "0" : "") + String(cent)
    }
}
