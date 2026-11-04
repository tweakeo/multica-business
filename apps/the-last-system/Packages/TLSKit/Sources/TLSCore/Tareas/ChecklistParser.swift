// Procedencia: gramática TOK_FINAL y lectura de `## Notas` portadas a Swift desde PROG `core/vault.js`
// (líneas 340–407, `leerTareasChecklist` y `leerNotasTareas`; autor: Manuel Trigo). Sin código copiado.
// Añadidos: `responsable X` de G3 y `@area:` corregido (acepta código, clave o nombre del área).

import Foundation

/// Una línea de tarea de un `Tareas.md` heredado (`- [ ] Título · 2026-10-27 · vence 2026-10-30 · #id`).
public struct LineaChecklist: Sendable, Hashable {
    public var hecho: Bool
    /// Lo que queda tras pelar los tokens conocidos por el final (los títulos pueden llevar « · »).
    public var titulo: String
    /// `#id` del final: identidad de la tarea en G1.
    public var token: String?
    /// Planificación (`AAAA-MM-DD` suelto).
    public var fecha: String?
    public var vence: String?
    /// `Urgente` o `Avance`.
    public var prioridad: String?
    /// `Semana`, `Mes` o `Trimestre` (el «tipo» de G1).
    public var horizonte: String?
    public var responsable: String?
    public var oportunidad: String?
    public var area: AreaCode?
    /// `@area:` tal como estaba escrito.
    public var areaTexto: String?
    /// `@est:` (En progreso, Esperando respuesta, Objeción, Revisar, Bloqueado).
    public var estado: String?
    public var horas: Double?
    public var invertidas: Double?
    /// Línea (desde 1) en el fichero.
    public var linea: Int
    /// Cuerpo de la tarea en `## Notas` (`### id`).
    public var notas: String?
}

/// Lee las casillas de un `Tareas.md` heredado (gramática G1 TOK_FINAL más `responsable X` de G3).
public enum ChecklistParser {
    /// Tokens por el final, en el orden en que se prueban (cada vez que uno se pela, se vuelve a empezar).
    static let tokens: [(String, NSRegularExpression)] = [
        ("id", #"(?:^| · )#(\S+)\s*$"#),
        ("resp", #"(?:^| · )@resp:(\S+)\s*$"#),
        ("op", #"(?:^| · )@op:(\S+)\s*$"#),
        ("inv", #"(?:^| · )\+(\d+(?:\.\d+)?)h\s*$"#),
        ("horas", #"(?:^| · )(\d+(?:\.\d+)?)h\s*$"#),
        ("tipo", #"(?:^| · )(Semana|Mes|Trimestre)\s*$"#),
        ("prio", #"(?:^| · )(Urgente|Avance)\s*$"#),
        ("vence", #"(?:^| · )vence (\d{4}-\d{2}-\d{2})\s*$"#),
        ("fecha", #"(?:^| · )(\d{4}-\d{2}-\d{2})\s*$"#),
        ("est", #"(?:^| · )@est:(En progreso|Esperando respuesta|Objeción|Revisar|Bloqueado)\s*$"#),
        // G1 solo aceptaba `[A-Z]{3}`: un `@area:ventas` se quedaba pegado al título.
        ("area", #"(?:^| · )@area:(\S+)\s*$"#),
        // G3: `· responsable Ana`.
        ("resp3", #"(?:^| · )responsable ([^·]+?)\s*$"#),
    ].map { ($0.0, try! NSRegularExpression(pattern: $0.1)) }

    static let casilla = try! NSRegularExpression(pattern: #"^-\s+\[([ xX])\]\s+(.+)$"#)

    public static func parse(_ cuerpo: String) -> [LineaChecklist] {
        let lines = cuerpo.lines.map(String.init)
        // Solo hasta `## Notas`: los cuerpos traen sus propias casillas.
        let corte = lines.firstIndex { $0.range(of: #"^## Notas\s*$"#, options: .regularExpression) != nil } ?? lines.count
        var out: [LineaChecklist] = []
        for (i, line) in lines.prefix(corte).enumerated() {
            let ns = NSRange(line.startIndex..., in: line)
            guard let m = casilla.firstMatch(in: line, range: ns),
                  let marca = Range(m.range(at: 1), in: line), let resto = Range(m.range(at: 2), in: line) else { continue }
            var rest = String(line[resto]).trimmingCharacters(in: .whitespaces)
            var got: [String: String] = [:]
            var avanza = true
            while avanza {
                avanza = false
                for (k, re) in tokens where got[k] == nil {
                    guard let t = re.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                          let whole = Range(t.range, in: rest), let v = Range(t.range(at: 1), in: rest) else { continue }
                    got[k] = String(rest[v]).trimmingCharacters(in: .whitespaces)
                    rest = String(rest[..<whole.lowerBound]).trimmingCharacters(in: .whitespaces)
                    if rest.hasSuffix(" ·") { rest = String(rest.dropLast(2)).trimmingCharacters(in: .whitespaces) }
                    avanza = true
                    break
                }
            }
            out.append(LineaChecklist(hecho: !line[marca].trimmingCharacters(in: .whitespaces).isEmpty, titulo: rest,
                                      token: got["id"], fecha: got["fecha"], vence: got["vence"], prioridad: got["prio"],
                                      horizonte: got["tipo"], responsable: got["resp"] ?? got["resp3"], oportunidad: got["op"],
                                      area: got["area"].flatMap(area), areaTexto: got["area"], estado: got["est"],
                                      horas: got["horas"].flatMap(Double.init), invertidas: got["inv"].flatMap(Double.init),
                                      linea: i + 1, notas: nil))
        }
        // Cuerpos en `## Notas`, partidos solo por los `### id` de la lista.
        let ids = Set(out.compactMap(\.token))
        if corte < lines.count, !ids.isEmpty {
            var actual: String?
            var bloques: [String: [String]] = [:]
            for line in lines[(corte + 1)...] {
                if line.hasPrefix("###"), let id = Optional(line.dropFirst(3).trimmingCharacters(in: .whitespaces)), ids.contains(id) {
                    actual = id
                    if bloques[id] == nil { bloques[id] = [] }
                    continue
                }
                if let a = actual { bloques[a, default: []].append(line) }
            }
            for i in out.indices {
                guard let t = out[i].token, let b = bloques[t] else { continue }
                let texto = b.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                out[i].notas = texto.isEmpty ? nil : texto
            }
        }
        return out
    }

    /// `@area:` por código (`VEN`), clave (`ventas`) o nombre (`Ventas`, `2 · Ventas`).
    static func area(_ texto: String) -> AreaCode? {
        let t = TextFolding.fold(texto)
        return AreaCode.allCases.first { a in
            t == TextFolding.fold(a.rawValue) || t == a.layoutKey || t == TextFolding.fold(a.nombre)
                || t == TextFolding.fold("\(a.numero) · \(a.nombre)") || t == String(a.numero)
        }
    }
}
