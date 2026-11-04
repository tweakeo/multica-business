import Foundation

/// Qué líneas de un texto son nuevas o cambiaron respecto a otro (pestaña Fichero: «líneas cambiadas hoy,
/// marcadas»). Subsecuencia común más larga, línea a línea; para textos muy largos, comparación directa.
public enum DiferenciaDeLineas {
    /// Índices (desde 0) de las líneas de `despues` que no están en `antes` en el mismo orden.
    public static func cambiadas(antes: String, despues: String) -> Set<Int> {
        let a = antes.components(separatedBy: "\n")
        let b = despues.components(separatedBy: "\n")
        if a == b { return [] }
        let n = a.count, m = b.count
        guard n * m <= 4_000_000 else {
            return Set((0..<m).filter { $0 >= n || a[$0] != b[$0] })
        }
        // Tabla de la subsecuencia común más larga (desde el final).
        var t = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var i = 0, j = 0
        var comunes = Set<Int>()
        while i < n, j < m {
            if a[i] == b[j] { comunes.insert(j); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return Set((0..<m).filter { !comunes.contains($0) })
    }
}
