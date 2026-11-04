import Foundation

/// Lo que se está escribiendo como enlace: `[[consulta` o `[texto](consulta`, en la línea del cursor.
public struct DisparoEnlace: Sendable, Hashable {
    public let disparador: DisparadorEnlace
    /// Lo escrito tras el disparador hasta el cursor.
    public let consulta: String
    /// Desde dónde se sustituye: el primer `[` de `[[`, o justo tras `(`.
    public let inicio: Int
    /// Texto entre corchetes de `[texto](` (solo en `.markdown`).
    public let textoVisible: String?

    /// Lo que hay que sustituir al elegir una sugerencia con el cursor en `cursor`: desde `inicio` hasta el
    /// cursor, más el cierre que ya estuviera escrito justo detrás (`]]` o `)`).
    public func rangoSustitucion(en texto: NSString, cursor: Int) -> NSRange {
        var fin = cursor
        switch disparador {
        case .wiki:
            if fin + 2 <= texto.length, texto.substring(with: NSRange(location: fin, length: 2)) == "]]" { fin += 2 }
        case .markdown:
            if fin + 1 <= texto.length, texto.character(at: fin) == 0x29 { fin += 1 }
        }
        return NSRange(location: inicio, length: fin - inicio)
    }

    /// Busca un disparo en la línea del cursor (como mucho 200 caracteres hacia atrás).
    public static func detectar(en texto: NSString, cursor: Int) -> DisparoEnlace? {
        guard cursor > 0, cursor <= texto.length else { return nil }
        let linea = texto.lineRange(for: NSRange(location: cursor, length: 0))
        let desde = max(linea.location, cursor - 200)
        guard cursor > desde else { return nil }
        let antes = texto.substring(with: NSRange(location: desde, length: cursor - desde)) as NSString

        // `[[consulta` sin cerrar.
        let abre = antes.range(of: "[[", options: .backwards)
        if abre.location != NSNotFound {
            let tras = antes.substring(from: NSMaxRange(abre))
            if !tras.contains("]]"), !tras.contains("[["), !tras.contains("\n"), !tras.contains("|"), tras.count <= 120 {
                // `![[` también vale (incrustar).
                return DisparoEnlace(disparador: .wiki, consulta: tras, inicio: desde + abre.location, textoVisible: nil)
            }
        }
        // `[texto](consulta` sin cerrar.
        let parentesis = antes.range(of: "](", options: .backwards)
        if parentesis.location != NSNotFound {
            let tras = antes.substring(from: NSMaxRange(parentesis))
            guard !tras.contains(")"), !tras.contains(" "), !tras.contains("\n"), tras.count <= 120 else { return nil }
            let delante = antes.substring(to: parentesis.location) as NSString
            let corchete = delante.range(of: "[", options: .backwards)
            guard corchete.location != NSNotFound else { return nil }
            let visible = delante.substring(from: NSMaxRange(corchete))
            guard !visible.contains("]") else { return nil }
            return DisparoEnlace(disparador: .markdown, consulta: tras.removingPercentEncoding ?? tras,
                                 inicio: desde + NSMaxRange(parentesis), textoVisible: visible)
        }
        return nil
    }
}
