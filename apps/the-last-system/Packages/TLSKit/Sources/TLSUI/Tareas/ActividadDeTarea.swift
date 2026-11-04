import Foundation
import TLSCore

// F2 · rol tareas. La Actividad de una ficha de tarea leída como línea de tiempo (PLAN §4.2, DISENO §3.4): cada
// entrada `### AAAA-MM-DD HH:MM · autor` con su texto y su evento `tls:evento` traducido a palabras; los cambios de
// estado en una línea, los comentarios con autor y hora, los trabajos de un asistente como tarjeta con resumen, uso
// y «Detalle técnico», y lo escrito en Obsidian sin encabezado como comentario de una persona. Nunca escribe.

/// Una entrada de la Actividad de una tarea, lista para enseñar.
struct EntradaDeTarea: Identifiable, Hashable, Sendable {
    enum Clase: String, Sendable, Hashable {
        /// Cambio de estado o de propiedades: una línea compacta.
        case cambio
        /// Comentario de una persona.
        case comentario
        /// Lo que hizo un asistente: tarjeta con resumen, uso y detalle técnico.
        case asistente
        /// Lo que hizo la app sola (reglas, importación).
        case sistema
    }

    /// Línea (desde 1) donde empieza.
    let id: Int
    let fecha: LocalDate?
    let hora: String?
    /// Como está escrito (`Manu`, `agente:comercial`, `sistema`); `nil` si se escribió sin encabezado.
    let autorEscrito: String?
    /// Como se enseña («Manu», «Comercial (asistente)», «La app»).
    let autor: String
    let clase: Clase
    /// El texto de la entrada, sin la sintaxis de los enlaces y con las menciones con su nombre.
    let texto: String
    /// El evento en una frase («Estado: Por hacer → En revisión», «Trabajo terminado»), si lo hay.
    let resumen: String?
    /// «Usó el 1 % de tu tope del mes» o «Simulado: no gasta de tu tope» (nunca dólares: esos van a «Detalle técnico»).
    let uso: String?
    /// Lo hizo la simulación del ejemplo (`"simulado":"si"` en su evento o el texto «Simulado: …»).
    var simulado: Bool = false
    /// Pares para «Detalle técnico» (ejecución, aprobación, función…).
    let detalle: [Par]
    /// Asistentes mencionados (`agente:comercial`), en el texto o guardados en el evento.
    let menciones: [String]
    /// Espera una aprobación en Decisiones.
    let pideAprobacion: Bool
    /// Escrito en Obsidian debajo de la última entrada, sin encabezado (cuenta como comentario de una persona).
    let sinEncabezado: Bool

    struct Par: Hashable, Sendable {
        let etiqueta: String
        let valor: String
    }
}

enum ActividadDeTarea {
    /// Las entradas de `## Actividad`, de la más antigua a la más reciente (como se escriben).
    /// `topes`: el tope de uso del mes de cada asistente (`comercial` → 15), para decir el uso como parte del tope.
    static func leer(_ texto: String, alias: [String: String] = [:], topes: [String: Double] = [:]) -> [EntradaDeTarea] {
        let lineas = texto.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var out: [EntradaDeTarea] = []
        var enFrontmatter = false
        var enActividad = false
        var fence: String?
        var actual: (linea: Int, encabezado: (fecha: LocalDate?, hora: String?, autor: String?)?, cuerpo: [String], eventos: [[String: Any]])?

        func cerrar() {
            guard let a = actual else { return }
            actual = nil
            let cuerpo = a.cuerpo.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("<!--") && !$0.hasPrefix("> Guía:") }
            if a.encabezado == nil, cuerpo.isEmpty { return }
            out.append(entrada(linea: a.linea, encabezado: a.encabezado, cuerpo: cuerpo, eventos: a.eventos, alias: alias,
                               topes: topes))
        }

        for (i, l) in lineas.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            if i == 0, t == "---" { enFrontmatter = true; continue }
            if enFrontmatter { if t == "---" || t == "..." { enFrontmatter = false }; continue }
            if let f = fence {
                if t.hasPrefix(f) { fence = nil }
                if enActividad, actual != nil { actual?.cuerpo.append(l) }
                continue
            }
            if let f = valla(t) {
                fence = f
                if enActividad, actual != nil { actual?.cuerpo.append(l) }
                continue
            }
            if let h = titulo(l), h.nivel <= 2 {
                cerrar()
                enActividad = h.nivel == 2 && TextFolding.fold(h.texto) == "actividad"
                continue
            }
            guard enActividad else { continue }
            if t.hasPrefix("### "), let e = encabezado(String(t.dropFirst(4))) {
                cerrar()
                actual = (i + 1, e, [], [])
                continue
            }
            if t.hasPrefix("<!-- tls:evento") {
                if let ev = evento(t) {
                    if actual == nil { actual = (i + 1, nil, [], []) }
                    actual?.eventos.append(ev)
                }
                continue
            }
            if t.hasPrefix("<!--") || t.hasPrefix("> Guía:") { continue }
            if actual == nil {
                if t.isEmpty { continue }
                // Texto sin encabezado (escrito en Obsidian): un comentario de una persona.
                actual = (i + 1, nil, [], [])
            } else if actual?.encabezado != nil, !(actual?.eventos.isEmpty ?? true), !t.isEmpty {
                // Tras el evento de una entrada, lo que sigue sin encabezado es otro comentario (Obsidian).
                cerrar()
                actual = (i + 1, nil, [], [])
            }
            actual?.cuerpo.append(l)
        }
        cerrar()
        return out
    }

    /// Apertura de un bloque de código (```` ``` ```` o `~~~`): la marca que lo cierra.
    static func valla(_ t: String) -> String? {
        for m in ["```", "~~~"] where t.hasPrefix(m) { return m }
        return nil
    }

    /// `## Título` → nivel y texto (solo encabezados ATX de 1 a 6 almohadillas seguidas de espacio).
    static func titulo(_ l: String) -> (nivel: Int, texto: String)? {
        let t = l.trimmingCharacters(in: .whitespaces)
        let almohadillas = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(almohadillas) else { return nil }
        let resto = t.dropFirst(almohadillas)
        guard resto.isEmpty || resto.first == " " else { return nil }
        return (almohadillas, resto.trimmingCharacters(in: CharacterSet(charactersIn: " #")))
    }

    /// `2026-10-21 10:32 · agente:comercial` → fecha, hora y autor.
    static func encabezado(_ s: String) -> (fecha: LocalDate?, hora: String?, autor: String?)? {
        let partes = s.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let primera = partes.first else { return nil }
        let trozos = primera.split(separator: " ").map(String.init)
        guard let f = trozos.first, let fecha = LocalDate(parsing: f) else { return nil }
        let hora = trozos.count > 1 ? trozos[1] : nil
        let autor = partes.count > 1 ? partes.dropFirst().joined(separator: " · ") : nil
        return (fecha, hora, autor)
    }

    /// `<!-- tls:evento {…} -->` → el objeto (con los escapes de `decisionLine` deshechos por el propio JSON).
    static func evento(_ linea: String) -> [String: Any]? {
        guard let a = linea.firstIndex(of: "{"), let b = linea.lastIndex(of: "}"), a < b else { return nil }
        let json = String(linea[a...b])
        return (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    /// Quién, como se enseña: `agente:comercial` → «Comercial (asistente)», `sistema` → «La app».
    static func nombre(_ autor: String?) -> String {
        guard let a = autor?.trimmingCharacters(in: .whitespaces), !a.isEmpty else { return "Escrito en Obsidian" }
        if TextFolding.fold(a) == "sistema" { return "La app" }
        if a.lowercased().hasPrefix("regla:") { return "La app (regla)" }
        return Responsables.nombre(de: a)
    }

    /// Menciones del texto: `@agente:comercial` y `@Comercial` (si `alias` lo conoce: «comercial» → «agente:comercial»).
    static func menciones(_ texto: String, alias: [String: String]) -> [String] {
        var out: [String] = []
        let re = try? NSRegularExpression(pattern: #"@([A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_:-]+)"#)
        let ns = texto as NSString
        for m in re?.matches(in: texto, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let palabra = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: CharacterSet(charactersIn: ":-"))
            let id: String?
            if palabra.lowercased().hasPrefix("agente:") { id = palabra.lowercased() }
            else { id = alias[TextFolding.fold(palabra)] }
            if let id, !out.contains(id) { out.append(id) }
        }
        return out
    }

    /// El texto como se lee: enlaces sin su sintaxis y `@agente:comercial` como «@Comercial (asistente)».
    static func legible(_ texto: String) -> String {
        var t = LinkParser.plainText(texto)
        if let re = try? NSRegularExpression(pattern: #"@agente:([A-Za-z0-9_-]+)"#) {
            let ns = t as NSString
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)).reversed() {
                let slug = ns.substring(with: m.range(at: 1))
                t = (t as NSString).replacingCharacters(in: m.range, with: "@" + Responsables.nombre(de: "agente:" + slug))
            }
        }
        return t
    }

    static func entrada(linea: Int, encabezado: (fecha: LocalDate?, hora: String?, autor: String?)?, cuerpo: [String],
                        eventos: [[String: Any]], alias: [String: String], topes: [String: Double] = [:]) -> EntradaDeTarea {
        let autor = encabezado?.autor
        var texto = cuerpo.map(legible).joined(separator: "\n")
        let ev = eventos.last ?? [:]
        func s(_ k: String) -> String? {
            switch ev[k] {
            case let v as String: return v.isEmpty ? nil : v
            case let v as NSNumber: return v.stringValue
            default: return nil
            }
        }
        let tipo = s("tipo")
        var resumen: String?
        var detalle: [EntradaDeTarea.Par] = []
        var uso: String?
        if let de = s("de"), let a = s("a") { resumen = "Estado: \(de) → \(a)" }
        switch tipo {
        case "ejecucion":
            resumen = "Trabajo terminado" + (resumen.map { " · " + $0.replacingOccurrences(of: "Estado: ", with: "") } ?? "")
        case "importacion":
            resumen = "Llegó de otro sitio" + (s("fichero").map { ": «\($0)»" } ?? "")
        case "aprobacion":
            resumen = "Aprobación" + (s("resultado").map { ": \($0)" } ?? "")
        case "comentario", "estado", "regla", nil:
            break
        default:
            if resumen == nil, let t = tipo { resumen = FormatoFicha.capital(t.replacingOccurrences(of: "_", with: " ")) }
        }
        // F4 · corrector (revisión de experiencia, P2): el uso como parte del tope del mes, con la marca «Simulado»;
        // los dólares, solo en «Detalle técnico».
        let simulado = TextFolding.fold(s("simulado") ?? "") == "si" || TextFolding.fold(cuerpo.first ?? "").hasPrefix("simulado")
        if let c = ev["coste_usd"] as? NSNumber ?? s("coste_usd").flatMap({ Double($0) }).map({ NSNumber(value: $0) }) {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            detalle.append(.init(etiqueta: "Uso", valor: (f.string(from: c) ?? c.stringValue) + " USD"))
            if simulado {
                uso = "Simulado: no gasta de tu tope"
            } else {
                let slug = autor.map { $0.lowercased().hasPrefix("agente:") ? String($0.dropFirst("agente:".count)) : $0 }
                    .map(ConfigAgentes.slug)
                let tope = slug.flatMap { topes[$0] } ?? 15
                uso = "Usó " + UsoDelMes.parte(c.doubleValue, de: tope) + " del mes"
            }
        } else if simulado, tipo == "ejecucion" {
            uso = "Simulado: no gasta de tu tope"
        }
        let etiquetas: [(String, String)] = [("run", "Ejecución"), ("ejecucion", "Ejecución"), ("aprobacion", "Aprobación"),
                                              ("capacidad", "Función"), ("borrador", "Borrador"), ("modo", "Modo"),
                                              ("token", "Marca de la lista"), ("desde", "Desde"), ("id", "Apunte")]
        for (k, e) in etiquetas { if let v = s(k), !detalle.contains(where: { $0.etiqueta == e }) { detalle.append(.init(etiqueta: e, valor: v)) } }
        var menciones = Self.menciones(cuerpo.joined(separator: " "), alias: alias)
        if let guardadas = s("menciones") {
            for m in guardadas.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !menciones.contains(m) { menciones.append(m) }
        }
        let esAsistente = autor?.lowercased().hasPrefix("agente:") == true
        let esSistema = autor.map { TextFolding.fold($0) == "sistema" || $0.lowercased().hasPrefix("regla:") } ?? false
        let clase: EntradaDeTarea.Clase
        if esAsistente { clase = .asistente }
        else if esSistema { clase = .sistema }
        else if tipo == "estado" || (tipo == nil && texto.hasPrefix("Estado:")) || (tipo != nil && tipo != "comentario" && texto.isEmpty) { clase = .cambio }
        else { clase = .comentario }
        // Un cambio de estado de una persona ya dice el cambio en su texto («Estado: … → …»): no se repite.
        if clase == .cambio, let r = resumen, texto.hasPrefix(r) { resumen = nil }
        // F4 · corrector (P3): el trabajo de un asistente lo dice en el resumen («Trabajo terminado · X → Y»): el texto
        // no lo repite.
        if tipo == "ejecucion", resumen?.contains("→") == true, texto.hasPrefix("Estado: "),
           let fin = texto.range(of: ". ") ?? texto.range(of: ".\n") {
            texto = String(texto[fin.upperBound...])
        }
        return EntradaDeTarea(id: linea, fecha: encabezado?.fecha, hora: encabezado?.hora, autorEscrito: autor,
                              autor: encabezado == nil ? "Escrito en Obsidian" : nombre(autor), clase: clase,
                              texto: texto, resumen: resumen, uso: uso, simulado: simulado, detalle: detalle, menciones: menciones,
                              pideAprobacion: s("aprobacion") != nil && tipo != "aprobacion", sinEncabezado: encabezado == nil)
    }
}
