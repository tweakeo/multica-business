import Foundation

/// Valla de un bloque de código (CommonMark): se abre con tres o más «`» o «~» y solo se cierra
/// con una línea de al menos tantos del mismo carácter y nada más que espacios detrás. Así un
/// bloque de cuatro comillas puede enseñar otro de tres (y «```js» dentro de un bloque no lo cierra).
struct CodeFence: Sendable, Equatable {
    let char: Character
    let count: Int

    /// Valla que abre `line` (ya sin la sangría), o `nil`.
    static func opening<S: StringProtocol>(_ line: S) -> CodeFence? {
        guard let c = line.first, c == "`" || c == "~" else { return nil }
        let n = line.prefix(while: { $0 == c }).count
        guard n >= 3 else { return nil }
        // El texto informativo de una valla de «`» no puede llevar «`» (sería código en línea).
        if c == "`", line.dropFirst(n).contains("`") { return nil }
        return CodeFence(char: c, count: n)
    }

    /// `true` si `line` (sin la sangría) cierra esta valla.
    func closes<S: StringProtocol>(_ line: S) -> Bool {
        let n = line.prefix(while: { $0 == char }).count
        return n >= count && line.dropFirst(n).allSatisfy { $0 == " " || $0 == "\t" }
    }
}
