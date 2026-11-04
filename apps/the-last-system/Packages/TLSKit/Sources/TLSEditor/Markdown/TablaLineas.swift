import Foundation
import Markdown

/// Las líneas de un texto con su posición en UTF-16 (la de `NSString` y TextKit) y en UTF-8 (la de
/// swift-markdown). Las líneas se cortan como en CommonMark: en «\r\n», «\n» y «\r».
struct TablaLineas: Sendable {
    struct Linea: Sendable {
        /// Desplazamiento UTF-16 del principio.
        let inicio: Int
        /// Longitud UTF-16 sin el salto.
        let longitud: Int
        /// Longitud del salto (0, 1 o 2).
        let salto: Int
        /// Bytes UTF-8 de la línea (sin el salto), para convertir columnas de swift-markdown.
        let bytes: ArraySlice<UInt8>
    }

    let lineas: [Linea]
    let longitud: Int

    init(_ texto: String) {
        let bytes = Array(texto.utf8)
        var lineas: [Linea] = []
        lineas.reserveCapacity(bytes.count / 40 + 1)
        var inicioLinea = 0
        var desplazamiento = 0
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            guard b == 0x0A || b == 0x0D else { i += 1; continue }
            let linea = bytes[inicioLinea..<i]
            let salto = (b == 0x0D && i + 1 < bytes.count && bytes[i + 1] == 0x0A) ? 2 : 1
            let n = Self.unidadesUTF16(linea)
            lineas.append(Linea(inicio: desplazamiento, longitud: n, salto: salto, bytes: linea))
            desplazamiento += n + salto
            i += salto
            inicioLinea = i
        }
        let ultima = bytes[inicioLinea..<bytes.count]
        lineas.append(Linea(inicio: desplazamiento, longitud: Self.unidadesUTF16(ultima), salto: 0, bytes: ultima))
        self.lineas = lineas
        self.longitud = texto.utf16.count
    }

    /// Unidades UTF-16 de un trozo de UTF-8 válido: 1 por escalar, 2 fuera del plano básico.
    static func unidadesUTF16(_ bytes: ArraySlice<UInt8>) -> Int {
        var n = 0
        for b in bytes where b & 0xC0 != 0x80 { n += b >= 0xF0 ? 2 : 1 }
        return n
    }

    /// Posición UTF-16 de una posición de swift-markdown (línea y columna en bytes, desde 1).
    func desplazamiento(_ p: SourceLocation) -> Int {
        let li = p.line - 1
        guard li >= 0 else { return 0 }
        guard li < lineas.count else { return longitud }
        let l = lineas[li]
        let columna = max(0, p.column - 1)
        if columna >= l.bytes.count {
            return min(l.inicio + l.longitud + (columna > l.bytes.count ? min(1, l.salto) : 0), longitud)
        }
        return min(l.inicio + Self.unidadesUTF16(l.bytes.prefix(columna)), longitud)
    }

    func rango(_ r: SourceRange?) -> NSRange? {
        guard let r else { return nil }
        let a = desplazamiento(r.lowerBound)
        let b = max(a, desplazamiento(r.upperBound))
        return NSRange(location: a, length: b - a)
    }

    /// Índices de línea (desde 0) de un rango de swift-markdown.
    func lineas(de r: SourceRange?) -> ClosedRange<Int>? {
        guard let r else { return nil }
        let a = max(0, min(r.lowerBound.line - 1, lineas.count - 1))
        var b = max(a, min(r.upperBound.line - 1, lineas.count - 1))
        // Un rango que acaba en la columna 1 de una línea no la ocupa (salvo que empiece ahí).
        if b > a, r.upperBound.column <= 1 { b -= 1 }
        return a...b
    }

    /// Línea que contiene una posición UTF-16.
    func indice(de posicion: Int) -> Int {
        var lo = 0, hi = lineas.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineas[mid].inicio <= posicion { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
