import Foundation

/// Una entrada de la línea de tiempo de una ficha (pestaña Actividad, §3.2).
public struct EntradaActividad: Sendable, Hashable, Identifiable {
    public enum Tipo: String, Sendable, Hashable, CaseIterable {
        /// Un cambio de estado o de propiedades.
        case cambio
        /// Un comentario o una nota de una persona.
        case comentario
        /// Lo que hizo un asistente.
        case asistente
    }

    public var id: String { "\(linea)·\(texto.prefix(24))" }
    public let fecha: LocalDate?
    /// «09:05» si la entrada la lleva.
    public let hora: String?
    public let autor: String?
    public let texto: String
    public let tipo: Tipo
    /// Línea (desde 1) donde empieza, para ordenar las de un mismo día.
    public let linea: Int
}

/// Lee la actividad escrita en una nota: las entradas de `## Actividad` (`### AAAA-MM-DD HH:MM · autor`), las
/// líneas con fecha de `## Historial` y de `## Notas` (`- 2026-10-15 · Emitida como F-2026-0007`) y la línea
/// «Fuente: … · fecha» de lo importado. Lo más reciente primero. Nunca escribe.
public enum ActividadDeFicha {
    public static func leer(_ texto: String) -> [EntradaActividad] {
        let lineas = texto.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var out: [EntradaActividad] = []
        var seccion = ""
        var enFrontmatter = false
        var i = 0
        var actual: (fecha: LocalDate?, hora: String?, autor: String?, linea: Int, cuerpo: [String], tipo: String?)?
        func cerrar() {
            guard let a = actual else { return }
            let cuerpo = a.cuerpo.map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("<!--") && !$0.hasPrefix("> Guía:") }
                .joined(separator: "\n")
            let autor = a.autor
            let tipo: EntradaActividad.Tipo
            if autor?.lowercased().hasPrefix("agente:") == true { tipo = .asistente }
            else if a.tipo == "estado" || cuerpo.hasPrefix("Estado:") { tipo = .cambio }
            else { tipo = .comentario }
            out.append(EntradaActividad(fecha: a.fecha, hora: a.hora, autor: autor.map(Responsables.nombre(de:)),
                                        texto: cuerpo.isEmpty ? "Sin texto" : cuerpo, tipo: tipo, linea: a.linea))
            actual = nil
        }
        var fence: CodeFence?
        while i < lineas.count {
            let l = lineas[i]
            let t = l.trimmingCharacters(in: .whitespaces)
            defer { i += 1 }
            if i == 0, t == "---" { enFrontmatter = true; continue }
            if enFrontmatter { if t == "---" || t == "..." { enFrontmatter = false }; continue }
            if let f = fence { if f.closes(Substring(t)) { fence = nil }; continue }
            if let f = CodeFence.opening(Substring(t)) { fence = f; continue }
            if let h = MarkdownSections.heading(l), h.level <= 2 {
                cerrar()
                seccion = TextFolding.fold(h.title)
                continue
            }
            if seccion == "actividad" {
                if t.hasPrefix("### "), let e = encabezado(String(t.dropFirst(4))) {
                    cerrar()
                    actual = (e.fecha, e.hora, e.autor, i + 1, [], nil)
                    continue
                }
                if t.hasPrefix("<!-- tls:evento"), actual != nil {
                    if t.contains("\"tipo\":\"estado\"") || t.contains("\"tipo\": \"estado\"") { actual?.tipo = "estado" }
                    continue
                }
                if actual != nil { actual?.cuerpo.append(l) }
                continue
            }
            if seccion == "historial" || seccion == "notas" || seccion == "seguimiento" {
                if let e = lineaConFecha(t) {
                    out.append(EntradaActividad(fecha: e.fecha, hora: nil, autor: nil, texto: e.texto,
                                                tipo: seccion == "historial" ? .cambio : .comentario, linea: i + 1))
                }
            }
            if t.hasPrefix("Fuente:"), let r = t.range(of: #"\d{4}-\d{2}-\d{2}\s*$"#, options: .regularExpression),
               let d = LocalDate(parsing: String(t[r]).trimmingCharacters(in: .whitespaces)) {
                let que = t.dropFirst("Fuente:".count).trimmingCharacters(in: .whitespaces)
                let sinFecha = que.replacingOccurrences(of: #"\s*·\s*\d{4}-\d{2}-\d{2}\s*$"#, with: "", options: .regularExpression)
                out.append(EntradaActividad(fecha: d, hora: nil, autor: nil, texto: "Llegó a la carpeta: \(sinFecha)",
                                            tipo: .cambio, linea: i + 1))
            }
        }
        cerrar()
        return out.sorted { a, b in
            switch (a.fecha, b.fecha) {
            case (let x?, let y?) where x != y: return x > y
            case (nil, _?): return false
            case (_?, nil): return true
            default:
                if (a.hora ?? "") != (b.hora ?? "") { return (a.hora ?? "") > (b.hora ?? "") }
                return a.linea > b.linea
            }
        }
    }

    /// `2026-10-22 09:05 · Manu` → fecha, hora y autor.
    static func encabezado(_ s: String) -> (fecha: LocalDate?, hora: String?, autor: String?)? {
        let partes = s.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let primera = partes.first else { return nil }
        let trozos = primera.split(separator: " ").map(String.init)
        guard let f = trozos.first, let fecha = LocalDate(parsing: f) else { return nil }
        let hora = trozos.count > 1 ? trozos[1] : nil
        let autor = partes.count > 1 ? partes.dropFirst().joined(separator: " · ") : nil
        return (fecha, hora, autor)
    }

    /// `- 2026-10-15 · Emitida como F-2026-0007` → fecha y texto.
    static func lineaConFecha(_ t: String) -> (fecha: LocalDate, texto: String)? {
        var s = Substring(t)
        if s.hasPrefix("- ") || s.hasPrefix("* ") { s = s.dropFirst(2) }
        guard s.count >= 10, let d = LocalDate(parsing: String(s.prefix(10))) else { return nil }
        let resto = s.dropFirst(10).trimmingCharacters(in: CharacterSet(charactersIn: " ·-—:"))
        return resto.isEmpty ? nil : (d, resto)
    }
}

/// Quién hace algo: `responsable` se guarda con un identificador estable que no se renombra (`lucia`,
/// `agente:implementador`, SISTEMAS §1.6) y la app enseña el nombre.
public enum Responsables {
    /// «agente:implementador» → «Implementador (asistente)»; «lucia» → «Lucia»; «Manu» → «Manu».
    public static func nombre(de identificador: String) -> String {
        let t = identificador.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("agente:") {
            let slug = t.dropFirst("agente:".count).replacingOccurrences(of: "-", with: " ")
            return slug.prefix(1).uppercased() + slug.dropFirst() + " (asistente)"
        }
        guard let primera = t.first else { return t }
        return primera.isLowercase ? t.prefix(1).uppercased() + t.dropFirst() : t
    }

    /// Identificador de una persona (su nombre en minúscula, sin tildes ni espacios): «Lucía Andreu» → «lucia-andreu».
    public static func identificador(persona: String) -> String {
        NombresDeFicha.slug(persona)
    }

    /// Quién puede llevar algo: tú, las personas y asistentes que ya aparecen como responsables y un asistente
    /// por cada rol de Equipo. Sin repetidos, tú primero.
    public static func opciones(grafo: GrafoRelaciones, persona: String) -> [(id: String, nombre: String)] {
        var ids: [String] = [persona]
        for f in grafo.fichas.values.sorted(by: { $0.ruta < $1.ruta }) {
            if let r = f.texto("responsable"), !r.contains("{{") { ids.append(r) }
        }
        for f in grafo.fichas(de: [.role]) { ids.append("agente:" + NombresDeFicha.slug(f.nombre)) }
        var vistos = Set<String>()
        return ids.filter { vistos.insert(TextFolding.fold($0)).inserted }.map { ($0, nombre(de: $0)) }
    }
}
