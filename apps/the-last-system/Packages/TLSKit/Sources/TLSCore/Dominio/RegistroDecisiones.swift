import Foundation

// `1 · Dirección/Decisiones.md` (PLAN §4.4, PLANTILLAS §2.1, SISTEMAS DI1): una línea por decisión y solo se añade.
//
//     - 2026-10-21 · Oferta v1.0 aprobada · cerrar el bloque comercial · Ventas · MANU-16 <!-- tls:decision {"id":"…","origen":"texto"} -->
//
// Corregir es añadir una línea nueva y marcar la vieja «(sustituida)»; nunca se borra. Las líneas escritas a mano
// sin marcador reciben el suyo (`marcarSinMarcador`). Fuera de esos dos añadidos, ningún byte de la nota cambia.

/// Una línea de decisión leída de `Decisiones.md`.
public struct LineaDecision: Sendable, Hashable, Identifiable {
    /// `id` del marcador (`nil` en una línea escrita a mano que aún no lo tiene).
    public let id: String?
    public let fecha: LocalDate?
    /// Qué se decide.
    public let decision: String
    public let porque: String?
    public let area: String?
    /// Fuente: la ficha de la decisión, la tarea 1-3-1 o el documento que cambia.
    public let origen: String?
    /// Marcada «(sustituida)».
    public let sustituida: Bool
    /// Datos del marcador `tls:decision` (`origen`, `sustituye`…).
    public let marcador: [String: String]
    /// Línea tal cual (sin el salto).
    public let texto: String
    /// Número de línea (desde 1) en la nota.
    public let numeroDeLinea: Int
    /// Desplazamiento en bytes UTF-8 (sin BOM) del principio de la línea y del final del texto (sin el salto).
    let inicio: Int
    let fin: Int
    /// Final (en bytes) del campo «qué se decide»: ahí va «(sustituida)».
    let finDecision: Int

    /// `id` de la decisión que esta línea sustituye, si lo dice el marcador.
    public var sustituye: String? { marcador["sustituye"] }
    public var tieneMarcador: Bool { id != nil }
}

/// Una decisión que se va a registrar.
public struct NuevaDecision: Sendable, Hashable {
    public var fecha: LocalDate
    public var decision: String
    public var porque: String?
    /// Área en palabras (`Ventas`, `Dirección`).
    public var area: String?
    /// Fuente (enlace a la ficha de la decisión, a la tarea 1-3-1…).
    public var origen: String?

    public init(fecha: LocalDate, decision: String, porque: String? = nil, area: String? = nil, origen: String? = nil) {
        self.fecha = fecha; self.decision = decision; self.porque = porque; self.area = area; self.origen = origen
    }
}

public enum DecisionError: Error, LocalizedError, Sendable, Equatable {
    case sinTexto
    case noEncontrada(String)
    case yaSustituida(String)
    case sinRegistro

    public var errorDescription: String? {
        switch self {
        case .sinTexto: "La decisión necesita una frase: qué se decide."
        case .noEncontrada: "No encuentro esa decisión en el registro. Puede que alguien la haya cambiado fuera de la app."
        case .yaSustituida: "Esa decisión ya está sustituida por otra."
        case .sinRegistro: "No encuentro el registro de decisiones."
        }
    }
}

/// Lectura y escritura de `Decisiones.md`.
public struct RegistroDecisiones: Sendable {
    public let lineas: [LineaDecision]

    static let separador = " · "
    static let prefijoMarcador = "<!-- tls:decision"

    /// Dónde vive el registro: `1 · Dirección/Decisiones.md` (con la carpeta de Dirección de la estructura).
    public static func ruta(_ layout: VaultLayout) -> VaultPath {
        layout.areaFolder(.direccion).appending("Decisiones.md")
    }

    // MARK: Leer

    /// Lee las líneas de decisión (`- AAAA-MM-DD · …`), fuera de bloques de código y de citas.
    public static func leer(_ texto: String) -> RegistroDecisiones {
        let text = TextDecoding.strippingBOM(texto)
        var out: [LineaDecision] = []
        var fence: CodeFence?
        var enFrontmatter = false
        for (n, r) in text.lineRanges().enumerated() {
            let linea = String(text[r.content])
            let trimmed = linea.drop(while: { $0 == " " })
            if n == 0, linea.trimmingCharacters(in: .whitespaces) == "---" { enFrontmatter = true; continue }
            if enFrontmatter {
                let t = linea.trimmingCharacters(in: .whitespaces)
                if t == "---" || t == "..." { enFrontmatter = false }
                continue
            }
            if let f = fence { if f.closes(trimmed) { fence = nil }; continue }
            if let f = CodeFence.opening(trimmed) { fence = f; continue }
            let inicio = text.utf8.distance(from: text.startIndex, to: r.content.lowerBound)
            if let d = parsear(linea, numero: n + 1, inicio: inicio) { out.append(d) }
        }
        return RegistroDecisiones(lineas: out)
    }

    static let patronLinea = try! NSRegularExpression(pattern: #"^- (\d{4}-\d{2}-\d{2})(?: · |\s*$)"#)
    static let patronMarcador = try! NSRegularExpression(pattern: #"\s*<!--\s*tls:decision\s*(\{.*?\})?\s*-->\s*$"#)

    static func parsear(_ linea: String, numero: Int, inicio: Int) -> LineaDecision? {
        let ns = linea as NSString
        guard let m = patronLinea.firstMatch(in: linea, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let fechaTexto = ns.substring(with: m.range(at: 1))
        // Marcador al final.
        var cuerpo = linea
        var marcador: [String: String] = [:]
        var tieneMarcador = false
        if let mm = patronMarcador.firstMatch(in: linea, range: NSRange(location: 0, length: ns.length)) {
            tieneMarcador = true
            if mm.range(at: 1).location != NSNotFound,
               let obj = try? JSONSerialization.jsonObject(with: Data(ns.substring(with: mm.range(at: 1)).utf8)) as? [String: Any] {
                for (k, v) in obj {
                    if let s = v as? String { marcador[k] = s } else if let n = v as? NSNumber { marcador[k] = n.stringValue }
                }
            }
            cuerpo = ns.substring(to: mm.range.location)
        }
        let resto = String(cuerpo.dropFirst(2 + fechaTexto.count))
        let tras = resto.hasPrefix(separador) ? String(resto.dropFirst(separador.count)) : resto.trimmingCharacters(in: .whitespaces)
        let campos = tras.components(separatedBy: separador)
        func campo(_ i: Int) -> String? {
            guard i < campos.count else { return nil }
            let t = campos[i].trimmingCharacters(in: .whitespaces)
            return t.isEmpty || t == "—" ? nil : t
        }
        let decisionCruda = campos.first ?? ""
        let sustituida = TextFolding.fold(cuerpo).contains("(sustituida)")
        var decision = decisionCruda.trimmingCharacters(in: .whitespaces)
        if let r = decision.range(of: "(sustituida)", options: [.caseInsensitive, .diacriticInsensitive]) {
            decision.removeSubrange(r)
            decision = decision.trimmingCharacters(in: .whitespaces)
        }
        // Final del campo «qué se decide» en bytes (sin los espacios de detrás).
        let prefijo = "- " + fechaTexto + (resto.hasPrefix(separador) ? separador : "")
        let campoSinEspacios = decisionCruda.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        let finDecision = inicio + prefijo.utf8.count + campoSinEspacios.utf8.count
        let origen = campos.count > 3 ? campos[3...].joined(separator: separador).trimmingCharacters(in: .whitespaces) : nil
        return LineaDecision(id: tieneMarcador ? marcador["id"] : nil, fecha: LocalDate(parsing: fechaTexto), decision: decision,
                             porque: campo(1), area: campo(2), origen: origen?.isEmpty == false ? origen : nil,
                             sustituida: sustituida, marcador: marcador, texto: linea, numeroDeLinea: numero,
                             inicio: inicio, fin: inicio + linea.utf8.count, finDecision: finDecision)
    }

    public func linea(id: String) -> LineaDecision? {
        let k = id.lowercased()
        return lineas.first { $0.id?.lowercased() == k }
    }

    /// Las vigentes (sin las sustituidas), de la más reciente a la más antigua.
    public var vigentes: [LineaDecision] {
        lineas.filter { !$0.sustituida }.sorted { ($0.fecha ?? LocalDate(year: 1, month: 1, day: 1)!) > ($1.fecha ?? LocalDate(year: 1, month: 1, day: 1)!) }
    }

    // MARK: Escribir

    /// Texto de un campo: sin saltos ni separadores que partan la línea, sin comentarios.
    static func limpio(_ s: String?) -> String? {
        guard var t = s?.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ") else { return nil }
        t = t.replacingOccurrences(of: separador, with: ", ").replacingOccurrences(of: "<!--", with: "‹!--")
            .replacingOccurrences(of: "-->", with: "--›").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    /// `<!-- tls:decision {…} -->`, escapado para que no cierre el comentario.
    public static func marcador(_ campos: [String: String]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: campos, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "-->", with: "--\\u003e").replacingOccurrences(of: "<!--", with: "\\u003c!--")
        return "\(prefijoMarcador) \(json) -->"
    }

    /// La línea completa de una decisión nueva.
    public static func textoDeLinea(_ d: NuevaDecision, id: String, origen: String = "app", sustituye: String? = nil) throws -> String {
        guard let decision = limpio(d.decision) else { throw DecisionError.sinTexto }
        var campos = [decision, limpio(d.porque), limpio(d.area), limpio(d.origen)]
        while campos.count > 1, campos.last! == nil { campos.removeLast() }
        var datos = ["id": id, "origen": origen]
        if let s = sustituye { datos["sustituye"] = s }
        return "- \(d.fecha) · " + campos.map { $0 ?? "—" }.joined(separator: separador) + " " + marcador(datos)
    }

    /// Plan que añade una decisión al registro (en la sección de su año, si el registro las usa). Si el registro
    /// no existe, lo crea con la plantilla. Devuelve el plan y el `id` de la línea.
    public static func anadir(_ d: NuevaDecision, en snapshot: VaultSnapshot, autor: Autor = .persona("Manu"),
                              sustituye: String? = nil, id: String = UUID().uuidString.lowercased()) throws -> (plan: WritePlan, id: String) {
        let linea = try textoDeLinea(d, id: id, sustituye: sustituye)
        let ruta = snapshot.existing(ruta(snapshot.layout)) ?? ruta(snapshot.layout)
        let descripcion = "Registrar la decisión «\(Self.corto(d.decision))»"
        guard let texto = snapshot.text(ruta) else {
            if snapshot.existing(ruta) != nil { throw DecisionError.sinRegistro }
            return (WritePlan(autor: autor, descripcion: descripcion, ops: try crearRegistro(con: linea, fecha: d.fecha, snapshot: snapshot, autor: autor)), id)
        }
        return (WritePlan(autor: autor, descripcion: descripcion, ops: [opAnadir(linea, fecha: d.fecha, ruta: ruta, texto: texto)]), id)
    }

    /// Corrige una decisión: añade la nueva (que dice a cuál sustituye) y marca la vieja «(sustituida)». Todo o nada.
    public static func sustituir(_ idVieja: String, por d: NuevaDecision, en snapshot: VaultSnapshot, autor: Autor = .persona("Manu"),
                                 id: String = UUID().uuidString.lowercased()) throws -> (plan: WritePlan, id: String) {
        let ruta = snapshot.existing(ruta(snapshot.layout)) ?? ruta(snapshot.layout)
        guard let texto = snapshot.text(ruta), let data = snapshot.data(ruta) else { throw DecisionError.sinRegistro }
        let registro = leer(texto)
        guard let vieja = registro.linea(id: idVieja) else { throw DecisionError.noEncontrada(idVieja) }
        guard !vieja.sustituida else { throw DecisionError.yaSustituida(idVieja) }
        let linea = try textoDeLinea(d, id: id, sustituye: idVieja)
        let marca = TextEdit(offset: vieja.finDecision, length: 0, replacement: " (sustituida)")
        let ops: [WriteOp] = [
            .editRanges(ruta, edits: [marca], baseHash: ContentHash.of(data)),
            opAnadir(linea, fecha: d.fecha, ruta: ruta, texto: texto),
        ]
        return (WritePlan(autor: autor, descripcion: "Sustituir la decisión «\(Self.corto(vieja.decision))»", ops: ops), id)
    }

    /// Pone su marcador a las líneas escritas a mano que no lo tienen (`"origen":"texto"`). `nil` si no falta ninguno.
    public static func marcarSinMarcador(en snapshot: VaultSnapshot, autor: Autor = .sistema) -> WritePlan? {
        let ruta = snapshot.existing(ruta(snapshot.layout)) ?? ruta(snapshot.layout)
        guard let texto = snapshot.text(ruta), let data = snapshot.data(ruta) else { return nil }
        let sin = leer(texto).lineas.filter { !$0.tieneMarcador }
        guard !sin.isEmpty else { return nil }
        let edits = sin.map { l in
            TextEdit(offset: l.fin, length: 0,
                     replacement: (l.texto.hasSuffix(" ") ? "" : " ") + marcador(["id": UUID().uuidString.lowercased(), "origen": "texto"]))
        }
        return WritePlan(autor: autor, descripcion: "Poner su marca a " + Plural.de(sin.count, "decisión", "decisiones"),
                         ops: [.editRanges(ruta, edits: edits, baseHash: ContentHash.of(data))])
    }

    /// Añadir la línea: en `## <año>` si el registro tiene secciones por año; si no, tras la última línea con texto.
    static func opAnadir(_ linea: String, fecha: LocalDate, ruta: VaultPath, texto: String) -> WriteOp {
        let cuerpo = NoteDocument(text: texto).body
        let titulos = MarkdownSections.titles(in: cuerpo)
        let porAño = titulos.contains { $0.range(of: #"^\d{4}$"#, options: .regularExpression) != nil }
        if porAño {
            return .appendToSection(ruta, section: String(fecha.year), text: linea, blankLine: false)
        }
        return .appendLine(ruta, line: linea)
    }

    /// Crear el registro con la plantilla (`registro-de-decisiones`) y la primera línea dentro.
    static func crearRegistro(con linea: String, fecha: LocalDate, snapshot: VaultSnapshot, autor: Autor) throws -> [WriteOp] {
        let motor = PlantillaMotor(snapshot: snapshot, opciones: .init(yo: autor.etiqueta))
        let nota = try motor.preparar(.init(plantilla: "registro-de-decisiones", area: .direccion, autor: autor))
        var ops: [WriteOp] = []
        for op in nota.plan.ops {
            guard case .create(let p, let data) = op, Invariantes.misma(p, nota.ruta), let e = EditableText(data: data) else {
                ops.append(op); continue
            }
            var doc = FrontmatterDocument(text: e.text)
            let año = String(fecha.year)
            let cuerpo = (try? MarkdownSections.append(to: año, in: doc.body, text: linea, blankLine: false, create: true, eol: "\n"))
                ?? doc.body + linea + "\n"
            doc.replaceBody(cuerpo)
            ops.append(.create(p, text: doc.text))
        }
        return ops
    }

    static func corto(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.count > 60 ? String(t.prefix(57)) + "…" : t
    }
}
