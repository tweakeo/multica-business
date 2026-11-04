import Foundation

/// Contadores de la carpeta (`.tls/secuencias.json`): tareas, presupuestos, recibos, incidencias.
///
/// Al escanear, cada contador se ajusta a `max(contador, mayor número visto)` (PLAN §4.2). La
/// escritura cambia solo el número de esa clave: el resto del fichero queda byte a byte.
public enum Secuencias {
    public static let ruta = VaultPath(".tls/secuencias.json")

    /// Valores guardados (vacío si no hay fichero o no se entiende).
    public static func leer(_ snapshot: VaultSnapshot) -> [String: Int] {
        guard let data = snapshot.data(ruta),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (k, v) in obj { if let n = v as? Int { out[k] = n } else if let n = (v as? NSNumber)?.intValue { out[k] = n } }
        return out
    }

    /// Clave de una serie (las que van por año llevan el año: `presupuesto-2026`).
    public static func clave(_ serie: String, año: Int) -> String {
        switch serie {
        case "presupuesto", "recibo": "\(serie)-\(año)"
        default: serie
        }
    }

    /// Número visible: `T-0042`, `P-2026-0003`, `CB-2026-0001`, `INC-007`.
    public static func formatear(_ serie: String, _ n: Int, año: Int) -> String {
        switch serie {
        case "tarea": String(format: "T-%04d", n)
        case "presupuesto": String(format: "P-%04d-%04d", año, n)
        case "recibo": String(format: "CB-%04d-%04d", año, n)
        case "incidencia": String(format: "INC-%03d", n)
        default: "\(serie.uppercased())-\(n)"
        }
    }

    /// Mayor número de la serie que ya está escrito en la carpeta.
    public static func mayorVisto(_ serie: String, año: Int, en snapshot: VaultSnapshot) -> Int {
        let patron: String
        switch serie {
        case "tarea": patron = #"^T-(\d+)$"#
        case "presupuesto": patron = "^P-\(año)-(\\d+)$"
        case "recibo": patron = "^CB-\(año)-(\\d+)$"
        case "incidencia": patron = #"^INC-(\d+)$"#
        default: return 0
        }
        var best = 0
        for p in snapshot.files where !VaultSnapshot.isTemplatePath(p) {
            if serie == "tarea", let n = TareaArchivo.numero(deNombre: p.name) { best = max(best, n) }
            guard p.ext == "md", let t = snapshot.text(p), t.contains("numero:") || serie == "incidencia" || serie == "recibo" else { continue }
            if let num = snapshot.frontmatter(p).text("numero"), let n = captura(num, patron) { best = max(best, n) }
            // Incidencias y recibos llevan el número en el nombre (`INC-007.md`, `CB-2026-0001.md`).
            if serie == "incidencia" || serie == "recibo", let n = captura(p.stem, patron) { best = max(best, n) }
        }
        return best
    }

    static func captura(_ s: String, _ patron: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: patron),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return Int(s[r])
    }

    /// Siguiente número libre de una serie.
    public static func siguiente(_ serie: String, año: Int, en snapshot: VaultSnapshot) -> Int {
        max(leer(snapshot)[clave(serie, año: año)] ?? 0, mayorVisto(serie, año: año, en: snapshot)) + 1
    }

    /// Operación que deja esos valores en `.tls/secuencias.json` (crea el fichero si no existe).
    /// Solo cambia los números de esas claves; si una clave no estaba, se añade al final del objeto.
    public static func op(_ valores: [String: Int], en snapshot: VaultSnapshot) -> WriteOp? {
        guard !valores.isEmpty else { return nil }
        guard let data = snapshot.data(ruta), let text = snapshot.text(ruta) else {
            let cuerpo = valores.keys.sorted().map { "\"\($0)\":\(valores[$0]!)" }.joined(separator: ",")
            return .create(ruta, text: "{\(cuerpo)}\n")
        }
        let b = Array(text.utf8)
        var edits: [TextEdit] = []
        var missing: [String] = []
        for key in valores.keys.sorted() {
            let value = valores[key]!
            let pattern = "\"" + NSRegularExpression.escapedPattern(for: key) + #""\s*:\s*(-?\d+)"#
            if let re = try? NSRegularExpression(pattern: pattern),
               let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) {
                let start = text.utf8.distance(from: text.startIndex, to: r.lowerBound)
                let len = text.utf8.distance(from: r.lowerBound, to: r.upperBound)
                edits.append(TextEdit(offset: start, length: len, replacement: String(value)))
            } else {
                missing.append(key)
            }
        }
        if !missing.isEmpty {
            // Delante de la última llave: `,"clave":N` (o sin coma si el objeto estaba vacío).
            guard let close = b.lastIndex(of: UInt8(ascii: "}")) else {
                return WriteOp.replaceText(ruta, base: data, text: "{" + missing.map { "\"\($0)\":\(valores[$0]!)" }.joined(separator: ",") + "}\n")
            }
            var k = close - 1
            while k >= 0, b[k] == 0x20 || b[k] == 0x0A || b[k] == 0x0D || b[k] == 0x09 { k -= 1 }
            let empty = k >= 0 && b[k] == UInt8(ascii: "{")
            let insert = (empty ? "" : ",") + missing.map { "\"\($0)\":\(valores[$0]!)" }.joined(separator: ",")
            edits.append(TextEdit(offset: k + 1, length: 0, replacement: insert))
        }
        return .editRanges(ruta, edits: edits, baseHash: ContentHash.of(data))
    }
}
