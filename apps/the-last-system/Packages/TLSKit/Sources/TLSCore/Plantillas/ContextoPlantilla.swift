import Foundation

/// Una ficha relacionada con la nota que se crea (la empresa, el contacto, la oportunidad…).
public struct NotaDeContexto: Sendable, Hashable {
    public let ruta: VaultPath
    /// `tls_type` (o el tipo que se deduce de su carpeta).
    public let tipo: String
    public let propiedades: Frontmatter
    /// Nombre que se ve: `nombre`, `titulo`, H1 o el nombre del fichero.
    public let nombre: String

    /// Nombre corto para nombres de fichero: el del fichero, o el de su carpeta si es `Proyecto.md`, `Cuenta.md`…
    public var slug: String {
        let genericos: Set<String> = ["proyecto", "cuenta", "portal", "logo", "área", "area", "cierre", "antecedentes"]
        if genericos.contains(TextFolding.nameKey(ruta.stem)), let parent = ruta.parent, !parent.isRoot { return parent.name }
        return ruta.stem
    }

    /// Carpeta de la ficha (la del proyecto para `Proyecto.md`).
    public var carpeta: VaultPath { ruta.parent ?? .root }

    public func valor(_ clave: String) -> String? {
        guard let p = propiedades.properties.first(where: { $0.key == clave }) else { return nil }
        let t = p.value.displayText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}

/// Las fichas relacionadas con la nota que se crea, por papel (`empresa`, `contacto`…).
///
/// Se construye desde la ficha en la que se pulsa «Nueva…»: esa ficha va con su papel y se siguen
/// sus relaciones (enlaces en propiedades y `*_id` heredados) hasta dos saltos, sin pisar lo ya puesto.
public struct ContextoPlantilla: Sendable {
    public private(set) var notas: [String: NotaDeContexto] = [:]
    /// Papel de la ficha desde la que se crea (si la hay).
    public private(set) var origen: String?

    public init() {}

    public subscript(_ rol: String) -> NotaDeContexto? { notas[rol] }

    /// Papel de cada tipo de ficha.
    public static let papeles: [String: String] = [
        "contact": "contacto", "organization": "empresa", "opportunity": "oportunidad", "project": "proyecto",
        "service": "servicio", "offer": "oferta", "invoice": "factura", "meeting": "reunion", "system": "sistema",
        "role": "rol", "task": "tarea", "incident": "incidencia", "delivery_template": "plan", "objective": "objetivo",
        "routine": "rutina", "content": "contenido", "conversation": "conversacion", "diagnosis": "diagnostico",
        "receipt": "recibo", "proposal": "propuesta", "quote": "presupuesto", "asset": "activo", "account": "cuenta",
        "company": "mi_empresa", "brand": "marca",
    ]

    /// Propiedades que relacionan con otra ficha y su papel. Las `*_id` son las heredadas.
    public static let relaciones: [String: String] = [
        "empresa": "empresa", "contacto": "contacto", "oportunidad": "oportunidad", "proyecto": "proyecto",
        "servicio": "servicio", "oferta_version": "oferta", "factura": "factura", "reunion": "reunion",
        "sistema": "sistema", "rol": "rol", "tarea": "tarea", "plan": "plan", "objetivo": "objetivo",
        "contenido": "contenido", "conversacion": "conversacion", "rutina": "rutina", "incidencia": "incidencia",
        "empresa_id": "empresa", "contacto_id": "contacto", "oportunidad_id": "oportunidad", "proyecto_id": "proyecto",
        "producto_id": "servicio", "objetivo_id": "objetivo", "plantilla_id": "plan", "tarea_id": "tarea",
    ]

    /// Contexto desde una ficha (y otras fichas puestas a mano por papel).
    public static func construir(desde: VaultPath?, extra: [String: VaultPath] = [:], snapshot: VaultSnapshot) -> ContextoPlantilla {
        var ctx = ContextoPlantilla()
        let resolver = snapshot.resolver
        var ids: [String: VaultPath]?
        func lookupID(_ id: String) -> VaultPath? {
            if ids == nil { ids = snapshot.idIndex() }
            return ids?[id.lowercased()]
        }
        var queue: [(VaultPath, Int)] = []
        for (rol, ruta) in extra.sorted(by: { $0.key < $1.key }) {
            if let n = nota(ruta, snapshot: snapshot) { ctx.notas[rol] = n; queue.append((n.ruta, 1)) }
        }
        if let d = desde, let n = nota(d, snapshot: snapshot) {
            let rol = papeles[n.tipo] ?? n.tipo
            ctx.origen = rol
            if ctx.notas[rol] == nil { ctx.notas[rol] = n }
            queue.insert((n.ruta, 0), at: 0)
        }
        var visited = Set<VaultPath>()
        while !queue.isEmpty {
            let (ruta, depth) = queue.removeFirst()
            guard depth < 2, visited.insert(ruta).inserted, let n = nota(ruta, snapshot: snapshot) else { continue }
            for prop in n.propiedades.properties {
                guard let rol = relaciones[prop.key], ctx.notas[rol] == nil else { continue }
                let valor: String
                switch prop.value {
                case .text(let t): valor = t
                case .list(let l) where l.count == 1: valor = l[0]
                default: continue
                }
                guard let destino = resolve(valor, from: ruta, resolver: resolver, ids: lookupID),
                      let dn = nota(destino, snapshot: snapshot) else { continue }
                ctx.notas[rol] = dn
                queue.append((destino, depth + 1))
            }
        }
        return ctx
    }

    /// Destino de un valor de relación: enlace (`[[x|X]]`, `[X](ruta)`), id heredado o nombre.
    static func resolve(_ valor: String, from: VaultPath, resolver: LinkResolver, ids: (String) -> VaultPath?) -> VaultPath? {
        let v = valor.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, !v.contains("{{") else { return nil }
        if let link = LinkScanner.scan(v).first {
            return resolver.resolve(link.link.resolvable, from: from)
        }
        if let p = ids(v) { return p }
        return resolver.resolve("[[\(v)]]", from: from)
    }

    /// Ficha leída de la foto. `nil` si no es una nota con texto.
    static func nota(_ ruta: VaultPath, snapshot: VaultSnapshot) -> NotaDeContexto? {
        guard let real = snapshot.existing(ruta) ?? snapshot.existing(VaultPath(ruta.raw + ".md")),
              let text = snapshot.text(real) else { return nil }
        let doc = NoteDocument(text: text)
        let fm = doc.frontmatter
        let tipo = fm.text("tls_type")
            ?? NoteKindResolver.kind(of: real, frontmatter: fm, layout: snapshot.layout).rawValue
        let nombre = fm.properties.first(where: { $0.key == "nombre" })?.value.displayText.nilIfEmpty
            ?? fm.properties.first(where: { $0.key == "titulo" })?.value.displayText.nilIfEmpty
            ?? doc.title(fileStem: real.stem)
        return NotaDeContexto(ruta: real, tipo: tipo, propiedades: fm, nombre: nombre)
    }

    public mutating func poner(_ rol: String, _ nota: NotaDeContexto) { notas[rol] = nota }
}

extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
