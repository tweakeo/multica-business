import Foundation

// Borradores de asistente (PLAN §4.3 `draft`): `N · Área/Borradores/<slug>.md`, sin fecha en el nombre (se
// regeneran). Lo que prepara un asistente para que salga de la empresa (un correo, un mensaje a un cliente, una
// publicación, una factura, un pago) nunca sale solo: queda aquí y pide tu aprobación concreta. Su `estado` es un
// espejo: la autoridad es `ApprovalStore`.

/// Estado de un borrador tal como lo refleja la app.
public enum EstadoBorrador: String, Sendable, Hashable, CaseIterable, Codable {
    case borrador = "Borrador"
    case pendiente = "Pendiente de tu OK"
    case aprobado = "Aprobado"
    case listoParaEnviar = "Listo para enviar"
    /// F5 · mail: la redacción de Mail está abierta con lo aprobado; falta que pulses Enviar.
    case abiertoEnMail = "Abierto en Mail"
    case enviado = "Enviado"
    case descartado = "Descartado"
    case caducado = "Caducado"

    public init?(leyendo texto: String) {
        let t = TextFolding.fold(texto.trimmingCharacters(in: .whitespaces))
        guard let e = Self.allCases.first(where: { TextFolding.fold($0.rawValue) == t }) else { return nil }
        self = e
    }
}

/// Un borrador leído de la carpeta.
public struct Borrador: Sendable, Hashable {
    public let ruta: VaultPath
    public let id: String?
    /// `correo`, `mensaje`, `publicacion`, `factura`, `pago`.
    public let tipo: String?
    public let accion: AccionExterna?
    public let para: [String]
    public let asunto: String?
    /// `message://…` del correo al que responde.
    public let enRespuestaA: String?
    public let tarea: String?
    public let oportunidad: String?
    public let creadoPor: String?
    public let ejecucion: String?
    public let aprobacion: String?
    public let estado: EstadoBorrador?
    /// Lo que saldría: la sección «Mensaje» (o el cuerpo sin «Para ti»).
    public let cuerpo: String
    /// Importe en céntimos (facturas y pagos), si lo dice.
    public let importe: Int?
    /// Adjuntos (rutas de la carpeta).
    public let adjuntos: [VaultPath]
    /// Huella de la ficha sin lo que refleja la app (`estado`, `aprobacion`): cambia si alguien la edita.
    public let version: String

    /// Lee un borrador (`tls_type: draft` o una nota de una carpeta `Borradores/`). `nil` si no lo es.
    public static func leer(_ ruta: VaultPath, texto: String, layout: VaultLayout) -> Borrador? {
        let doc = NoteDocument(text: texto)
        let fm = doc.frontmatter
        let tipoFicha = fm.text("tls_type").map { $0.lowercased() }
        // Una factura en borrador es lo que se aprueba (SISTEMAS: «la propia factura es lo que apruebas»).
        if tipoFicha == "invoice" { return factura(ruta, texto: texto, doc: doc) }
        guard tipoFicha == "draft" || (tipoFicha == nil && Borradores.esRutaDeBorrador(ruta, layout: layout)) else { return nil }
        func t(_ k: String) -> String? {
            fm.text(k).map { LinkParser.plainText($0).trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        func lista(_ k: String) -> [String] {
            guard let p = fm.properties.first(where: { $0.key == k }) else { return [] }
            switch p.value {
            case .list(let l): return l.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            case .empty: return []
            default:
                return p.value.displayText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0 != "[]" }
            }
        }
        let accion = t("accion").flatMap(AccionExterna.init(leyendo:)) ?? t("tipo").flatMap(Self.accionDeTipo)
        let importe = (t("importe") ?? t("total")).flatMap(FormatosPlantilla.centimos)
        return Borrador(ruta: ruta, id: t("id"), tipo: t("tipo"), accion: accion, para: lista("para"), asunto: t("asunto"),
                        enRespuestaA: t("en_respuesta_a"), tarea: t("tarea") ?? t("tarea_id"),
                        oportunidad: t("oportunidad") ?? t("oportunidad_id"), creadoPor: t("creado_por"),
                        ejecucion: t("ejecucion"), aprobacion: t("aprobacion"),
                        estado: t("estado").flatMap(EstadoBorrador.init(leyendo:)), cuerpo: Self.cuerpo(doc.body),
                        importe: importe, adjuntos: lista("adjuntos").map { VaultPath(LinkParser.plainText($0)) },
                        version: Self.version(texto))
    }

    /// Una factura (`tls_type: invoice`) vista como lo que se aprueba al emitirla: a quién, por cuánto y sus líneas.
    static func factura(_ ruta: VaultPath, texto: String, doc: NoteDocument) -> Borrador {
        let fm = doc.frontmatter
        func t(_ k: String) -> String? {
            fm.text(k).map { LinkParser.plainText($0).trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        let partes = ["Conceptos", "Totales"].compactMap { s in
            MarkdownSections.content(of: s, in: doc.body, level: 2).map { "## \(s)\n" + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let numero = t("numero")
        return Borrador(ruta: ruta, id: t("id"), tipo: "factura", accion: .emitirFactura,
                        para: [t("empresa"), t("contacto")].compactMap { $0 }, asunto: "Factura " + (numero ?? ruta.stem),
                        enRespuestaA: nil, tarea: nil, oportunidad: t("oportunidad"), creadoPor: t("creado_por"),
                        ejecucion: t("ejecucion"), aprobacion: t("aprobacion"),
                        estado: nil, cuerpo: partes.joined(separator: "\n\n"),
                        importe: t("total").flatMap(FormatosPlantilla.centimos), adjuntos: [], version: version(texto))
    }

    static func accionDeTipo(_ tipo: String) -> AccionExterna? {
        switch TextFolding.fold(tipo) {
        case "correo": .enviarCorreo
        case "mensaje": .escribirCliente
        case "publicacion": .publicar
        case "factura": .emitirFactura
        case "pago": .pagar
        default: nil
        }
    }

    /// Lo que sale: la sección «Mensaje» si la hay; si no, el cuerpo sin la sección «Para ti» (que nunca sale).
    static func cuerpo(_ body: String) -> String {
        if let m = MarkdownSections.content(of: "Mensaje", in: body, level: 2) {
            return m.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var lines = TextLines.split(body)
        if let s = MarkdownSections.find("Para ti", in: lines, level: 2) {
            lines.removeSubrange(s.headingLine..<s.contentLines.upperBound)
        }
        return TextLines.join(lines).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Huella del texto sin las líneas que escribe la app como espejo.
    public static func version(_ texto: String) -> String {
        var doc = FrontmatterDocument(text: texto)
        doc.merge(set: [], unset: Borradores.propiedadesEspejo)
        return ContentHash.of(doc.text)
    }

    /// Nombre del asistente que lo preparó (`agente:comercial` → `comercial`), si lo hizo uno.
    public var asistente: String? {
        guard let c = creadoPor, c.lowercased().hasPrefix("agente:") else { return nil }
        return ConfigAgentes.slug(c)
    }
}

/// Lo nuevo que prepara un asistente.
public struct NuevoBorrador: Sendable, Hashable {
    public var accion: AccionExterna
    public var area: AreaCode
    public var asunto: String
    public var cuerpo: String
    public var para: [String]
    /// Lo que no sale: por qué este mensaje, qué datos cita y qué falta.
    public var paraTi: String?
    public var enRespuestaA: String?
    public var tarea: VaultPath?
    public var oportunidad: VaultPath?
    public var ejecucion: String?
    /// Nombre (sin fecha); por defecto, el del asunto.
    public var slug: String?
    public var importe: Int?

    public init(accion: AccionExterna, area: AreaCode, asunto: String, cuerpo: String, para: [String] = [],
                paraTi: String? = nil, enRespuestaA: String? = nil, tarea: VaultPath? = nil, oportunidad: VaultPath? = nil,
                ejecucion: String? = nil, slug: String? = nil, importe: Int? = nil) {
        self.accion = accion; self.area = area; self.asunto = asunto; self.cuerpo = cuerpo; self.para = para
        self.paraTi = paraTi; self.enRespuestaA = enRespuestaA; self.tarea = tarea; self.oportunidad = oportunidad
        self.ejecucion = ejecucion; self.slug = slug; self.importe = importe
    }
}

public enum Borradores {
    /// Lo que la app refleja en la ficha (no cuenta como un cambio del contenido).
    public static let propiedadesEspejo = ["estado", "aprobacion"]
    public static let carpeta = "Borradores"

    /// `N · Área/Borradores/`.
    public static func carpeta(_ area: AreaCode, layout: VaultLayout) -> VaultPath {
        layout.areaFolder(area).appending(carpeta)
    }

    /// `N · Área/Borradores/<slug>.md` (sin fecha).
    public static func ruta(slug: String, area: AreaCode, layout: VaultLayout) -> VaultPath {
        carpeta(area, layout: layout).appending(NombresDeFicha.slug(slug, maximo: 60) + ".md")
    }

    /// Una nota dentro de una carpeta `Borradores/` de un área (también `Fiscal/Borradores/`).
    public static func esRutaDeBorrador(_ p: VaultPath, layout: VaultLayout) -> Bool {
        guard p.ext == "md", let parent = p.parent, TextFolding.nameKey(parent.name) == TextFolding.nameKey(carpeta),
              layout.area(of: p) != nil, !layout.isArchived(p) else { return false }
        return !VaultSnapshot.isTemplatePath(p)
    }

    /// Texto de un borrador nuevo (con la forma de la plantilla «Borrador de mensaje»).
    public static func texto(_ b: NuevoBorrador, id: String = UUID().uuidString.lowercased(), creadoPor: Autor,
                             estado: EstadoBorrador = .borrador) -> String {
        let tipo: String = switch b.accion {
        case .enviarCorreo: "correo"
        case .escribirCliente: "mensaje"
        case .publicar: "publicacion"
        case .emitirFactura: "factura"
        case .pagar: "pago"
        case .externa: "externa"
        }
        func esc(_ s: String) -> String { TextoPuesta.escalarYAML(s) }
        var fm = ["---", "tls_type: draft", "tls_schema: 1", "id: \(esc(id))", "tipo: \(tipo)", "accion: \(b.accion.rawValue)",
                  "estado: \(esc(estado.rawValue))"]
        fm.append(b.para.isEmpty ? "para: []" : "para: [" + b.para.map(esc).joined(separator: ", ") + "]")
        fm.append("asunto: \(esc(b.asunto))")
        if let r = b.enRespuestaA { fm.append("en_respuesta_a: \(esc(r))") }
        if let t = b.tarea { fm.append("tarea: \(esc("[[\(t.stem)]]"))") }
        if let o = b.oportunidad { fm.append("oportunidad: \(esc("[[\(o.stem)]]"))") }
        if let i = b.importe { fm.append("importe: \(Euros.escrito(i))") }
        fm.append("creado_por: \(esc(creadoPor.etiqueta))")
        if let e = b.ejecucion { fm.append("ejecucion: \(esc(e))") }
        fm.append("plantilla: \"Borrador de mensaje v1\"")
        fm.append("---")
        var cuerpo = ["# \(b.asunto)", "", "## Mensaje", b.cuerpo.trimmingCharacters(in: .whitespacesAndNewlines), "",
                      "## Para ti"]
        cuerpo.append(b.paraTi?.trimmingCharacters(in: .whitespacesAndNewlines).nilSiVacioGobierno
                      ?? "> Esto no sale. Salir siempre pide tu OK.")
        return (fm + cuerpo).joined(separator: "\n") + "\n"
    }

    /// Plan para crear el borrador (como el asistente: preparar borradores es del suelo).
    public static func plan(_ b: NuevoBorrador, layout: VaultLayout, autor: Autor) -> (ruta: VaultPath, plan: WritePlan) {
        let ruta = ruta(slug: b.slug ?? b.asunto, area: b.area, layout: layout)
        let plan = WritePlan(autor: autor, descripcion: "Preparar el borrador «\(b.asunto)»",
                             ops: [.create(ruta, text: texto(b, creadoPor: autor))])
        return (ruta, plan)
    }

    /// Plan del espejo: `estado` (y `aprobacion`) como los deja el registro de aprobaciones. Lo escribe la app.
    public static func planEspejo(_ ruta: VaultPath, estado: EstadoBorrador, aprobacion: String?) -> WritePlan {
        var poner = [Property(key: "estado", value: .text(estado.rawValue))]
        if let a = aprobacion { poner.append(Property(key: "aprobacion", value: .text(a))) }
        return WritePlan(autor: .sistema, descripcion: "«\(ruta.stem)»: \(estado.rawValue)",
                         ops: [.mergeFrontmatter(ruta, set: poner, unset: [])])
    }
}

extension String {
    var nilSiVacioGobierno: String? { isEmpty ? nil : self }
}
