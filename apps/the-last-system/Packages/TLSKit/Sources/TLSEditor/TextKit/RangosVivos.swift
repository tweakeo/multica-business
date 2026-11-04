import Foundation

/// Rangos del texto que siguen a las ediciones: lo escrito desde el último análisis y la línea que se pintó
/// como «del cursor». Cuando llega el análisis nuevo, esas líneas se repintan aunque su estructura no cambie.
struct RangosVivos: Sendable, Equatable {
    private(set) var rangos: [NSRange] = []

    var isEmpty: Bool { rangos.isEmpty }

    mutating func anadir(_ r: NSRange) {
        rangos.append(r)
    }

    mutating func vaciar() { rangos.removeAll(keepingCapacity: true) }

    /// Una edición: `editado` es el rango nuevo (ya en el texto) y `delta` lo que cambió la longitud.
    /// Lo que va detrás se desplaza; lo que se solapa crece hasta cubrir lo nuevo. Lo editado se apunta.
    mutating func editar(_ editado: NSRange, delta: Int) {
        let viejoInicio = editado.location
        let viejoFin = editado.location + editado.length - delta
        rangos = rangos.map { r in
            let fin = NSMaxRange(r)
            if fin < viejoInicio { return r }
            if r.location > viejoFin { return NSRange(location: r.location + delta, length: r.length) }
            let inicio = min(r.location, editado.location)
            let nuevoFin = max(fin + delta, NSMaxRange(editado))
            return NSRange(location: inicio, length: max(0, nuevoFin - inicio))
        }
        rangos.append(editado)
        if rangos.count > 64 {
            // Muchas ediciones sueltas: basta con su envoltura.
            let a = rangos.map(\.location).min() ?? 0
            let b = rangos.map { NSMaxRange($0) }.max() ?? 0
            rangos = [NSRange(location: a, length: b - a)]
        }
    }
}
