import Foundation
import TLSCore

// Manual (PLAN §6.8, F3 · rol tutorial): el manual corto propio y «De dónde salen las ideas», en Markdown dentro
// de la app (`App/Recursos/Manual/`). Cada sección `## Título {#id}` se puede abrir desde «Saber más». El manual
// largo del método (MANUAL-TLB.md) viaja en la app como fuente, pero no se enseña en la v1 (PLAN §12).

/// Un trozo de una sección, listo para pintar.
enum BloqueManual: Hashable, Sendable {
    case subtitulo(String)
    case parrafo(String)
    case lista([String], numerada: Bool)
    case cita(String)
}

/// Una sección del manual (lo que abre «Saber más»).
struct SeccionManual: Hashable, Sendable, Identifiable {
    let id: String
    let titulo: String
    let documento: String
    /// El Markdown de la sección (sin su encabezado).
    let texto: String
    let bloques: [BloqueManual]
    /// Texto plegado para buscar (título y contenido).
    let plegado: String
}

/// Un documento del manual.
struct DocumentoManual: Hashable, Sendable, Identifiable {
    let id: String
    let titulo: String
    let entradilla: String
    let secciones: [SeccionManual]
}

/// Un resultado de búsqueda: la sección y un trozo con lo encontrado.
struct ResultadoManual: Hashable, Sendable, Identifiable {
    let seccion: SeccionManual
    let extracto: String
    var id: String { seccion.id }
}

/// Los documentos del manual leídos de su carpeta.
struct ManualBiblioteca: Sendable {
    /// Ficheros que se enseñan, en este orden.
    static let ficheros: [(id: String, nombre: String)] = [
        ("manual-corto", "Manual corto.md"),
        ("de-donde-salen-las-ideas", "De dónde salen las ideas.md"),
    ]
    /// Viaja en la app como fuente del manual corto; fuera de la v1 en pantalla (PLAN §12).
    static let ficheroMetodo = "MANUAL-TLB.md"

    let documentos: [DocumentoManual]

    /// La carpeta del manual dentro de la app.
    static var carpetaDeLaApp: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Recursos/Manual", isDirectory: true)
    }

    /// La de la app (se lee una vez).
    @MainActor
    static var deLaApp: ManualBiblioteca {
        if let c = CacheManual.biblioteca { return c }
        let b = carpetaDeLaApp.map(cargar) ?? ManualBiblioteca(documentos: [])
        CacheManual.biblioteca = b
        return b
    }

    static func cargar(_ carpeta: URL) -> ManualBiblioteca {
        let docs = ficheros.compactMap { f -> DocumentoManual? in
            guard let texto = try? String(contentsOf: carpeta.appendingPathComponent(f.nombre), encoding: .utf8) else { return nil }
            return leer(texto, id: f.id)
        }
        return ManualBiblioteca(documentos: docs)
    }

    var secciones: [SeccionManual] { documentos.flatMap(\.secciones) }

    func seccion(_ id: String) -> SeccionManual? { secciones.first { $0.id == id } }

    /// Secciones con todas las palabras buscadas (sin tildes ni mayúsculas); primero las que lo tienen en el título.
    func buscar(_ consulta: String) -> [ResultadoManual] {
        let palabras = TextFolding.fold(consulta).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !palabras.isEmpty else { return [] }
        let encontradas = secciones.filter { s in palabras.allSatisfy { s.plegado.contains($0) } }
        let enTitulo = { (s: SeccionManual) in palabras.allSatisfy { TextFolding.fold(s.titulo).contains($0) } }
        return (encontradas.filter(enTitulo) + encontradas.filter { !enTitulo($0) })
            .map { ResultadoManual(seccion: $0, extracto: Self.extracto($0, palabra: palabras[0])) }
    }

    /// Unas 20 palabras alrededor de lo encontrado.
    static func extracto(_ s: SeccionManual, palabra: String) -> String {
        let limpio = s.bloques.map { b -> String in
            switch b {
            case .subtitulo(let t), .parrafo(let t), .cita(let t): t
            case .lista(let l, _): l.joined(separator: " · ")
            }
        }.joined(separator: " ").replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "*", with: "")
        let palabras = limpio.split(separator: " ")
        guard let i = palabras.firstIndex(where: { TextFolding.fold(String($0)).contains(palabra) }) else {
            return palabras.prefix(20).joined(separator: " ") + (palabras.count > 20 ? "…" : "")
        }
        let desde = max(0, i - 6)
        let hasta = min(palabras.count, desde + 20)
        return (desde > 0 ? "…" : "") + palabras[desde..<hasta].joined(separator: " ") + (hasta < palabras.count ? "…" : "")
    }

    // MARK: Leer el Markdown

    /// `# Título`, una entradilla y secciones `## Título {#id}`.
    static func leer(_ texto: String, id: String) -> DocumentoManual {
        var titulo = id
        var entradilla: [String] = []
        var secciones: [SeccionManual] = []
        var actual: (id: String, titulo: String, lineas: [String])?
        func cerrar() {
            guard let a = actual else { return }
            let cuerpo = a.lineas.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            secciones.append(SeccionManual(id: a.id, titulo: a.titulo, documento: id, texto: cuerpo, bloques: bloques(cuerpo),
                                           plegado: TextFolding.fold(a.titulo + "\n" + cuerpo)))
            actual = nil
        }
        for linea in texto.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if linea.hasPrefix("# ") {
                titulo = String(linea.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if linea.hasPrefix("## ") {
                cerrar()
                let (t, ancla) = encabezado(String(linea.dropFirst(3)))
                actual = (ancla ?? slug(t), t, [])
            } else if actual != nil {
                actual?.lineas.append(linea)
            } else if !linea.trimmingCharacters(in: .whitespaces).isEmpty {
                entradilla.append(linea.trimmingCharacters(in: .whitespaces))
            }
        }
        cerrar()
        return DocumentoManual(id: id, titulo: titulo, entradilla: entradilla.joined(separator: " "), secciones: secciones)
    }

    /// «Título {#id}» → («Título», «id»).
    static func encabezado(_ s: String) -> (String, String?) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasSuffix("}"), let r = t.range(of: "{#", options: .backwards) else { return (t, nil) }
        let id = String(t[r.upperBound..<t.index(before: t.endIndex)])
        return (String(t[..<r.lowerBound]).trimmingCharacters(in: .whitespaces), id.isEmpty ? nil : id)
    }

    static func slug(_ s: String) -> String {
        TextFolding.fold(s).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    /// Párrafos, subtítulos (`###`), listas (`- ` y `1. `) y citas (`> `).
    static func bloques(_ texto: String) -> [BloqueManual] {
        var out: [BloqueManual] = []
        var parrafo: [String] = []
        var lista: (items: [String], numerada: Bool)?
        var cita: [String] = []
        func vaciar() {
            if !parrafo.isEmpty { out.append(.parrafo(parrafo.joined(separator: " "))); parrafo = [] }
            if let l = lista { out.append(.lista(l.items, numerada: l.numerada)); lista = nil }
            if !cita.isEmpty { out.append(.cita(cita.joined(separator: " "))); cita = [] }
        }
        for bruta in texto.components(separatedBy: "\n") {
            let l = bruta.trimmingCharacters(in: .whitespaces)
            if l.isEmpty { vaciar(); continue }
            if l.hasPrefix("### ") { vaciar(); out.append(.subtitulo(String(l.dropFirst(4)))); continue }
            if l.hasPrefix("> ") || l == ">" {
                if !parrafo.isEmpty || lista != nil { vaciar() }
                cita.append(String(l.dropFirst(min(2, l.count))))
                continue
            }
            if l.hasPrefix("- ") || l.hasPrefix("* ") {
                if !parrafo.isEmpty || !cita.isEmpty || lista?.numerada == true { vaciar() }
                lista = (items: (lista?.items ?? []) + [String(l.dropFirst(2))], numerada: false)
                continue
            }
            if let r = l.range(of: #"^\d+\. "#, options: .regularExpression) {
                if !parrafo.isEmpty || !cita.isEmpty || lista?.numerada == false { vaciar() }
                lista = (items: (lista?.items ?? []) + [String(l[r.upperBound...])], numerada: true)
                continue
            }
            if let l0 = lista, bruta.hasPrefix("  ") {
                // Continuación de un elemento de la lista.
                var items = l0.items
                items[items.count - 1] += " " + l
                lista = (items, l0.numerada)
                continue
            }
            if lista != nil || !cita.isEmpty { vaciar() }
            parrafo.append(l)
        }
        vaciar()
        return out
    }
}

@MainActor
private enum CacheManual {
    static var biblioteca: ManualBiblioteca?
}
