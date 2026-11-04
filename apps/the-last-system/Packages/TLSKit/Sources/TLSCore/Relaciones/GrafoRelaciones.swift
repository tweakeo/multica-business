import Foundation

/// Una ficha vista por las relaciones: tipo, nombre visible y propiedades tal como están escritas.
public struct FichaGrafo: Sendable, Hashable, Identifiable {
    public var id: VaultPath { ruta }
    public let ruta: VaultPath
    public let tipo: NoteKind
    /// Nombre que se enseña (`nombre`, `titulo` o el título de la nota). Nunca el nombre del fichero si hay otro.
    public let nombre: String
    public let propiedades: Frontmatter
    /// Ruta privada: no sale en listas, selectores ni vistas previas.
    public let privada: Bool

    public init(ruta: VaultPath, tipo: NoteKind, nombre: String, propiedades: Frontmatter, privada: Bool) {
        self.ruta = ruta; self.tipo = tipo; self.nombre = nombre; self.propiedades = propiedades; self.privada = privada
    }

    /// Texto de una propiedad tal como se llama (sin alias), `nil` si está vacía.
    public func texto(_ clave: String) -> String? {
        let k = clave.precomposedStringWithCanonicalMapping
        guard let p = propiedades.properties.first(where: { $0.key.precomposedStringWithCanonicalMapping == k }) else { return nil }
        let s = p.value.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    public var estado: String? { texto("estado") }
    /// Número visible (T-0042, F-2026-0007), si lo tiene.
    public var numero: String? { texto("numero") }
}

/// Una relación escrita en las propiedades de una ficha (`empresa: "[[x|X]]"`), ya resuelta.
public struct EnlaceTipado: Sendable, Hashable {
    /// La ficha que la guarda.
    public let origen: VaultPath
    /// Clave tal como está escrita (`empresa`, `empresa_id`, `personas`).
    public let clave: String
    /// Clave canónica (`empresa_id` → `empresa`).
    public let propiedad: String
    public let destino: VaultPath
    /// Valor escrito (`[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]`).
    public let valor: String
    /// Posición en la lista, si la propiedad es una lista.
    public let posicion: Int?
}

/// Un enlace escrito en el texto de otra nota («Enlazan aquí» del inspector).
public struct EnlaceEnTexto: Sendable, Hashable {
    public let origen: VaultPath
    /// Línea (desde 1) de la nota que enlaza.
    public let linea: Int
    /// La línea entera, para enseñarla.
    public let extracto: String
}

/// Algo relacionado con una ficha, con el camino por el que lo está.
public struct Relacionado: Sendable, Hashable, Identifiable {
    public enum Via: Sendable, Hashable {
        /// La otra ficha guarda `propiedad` apuntando aquí (se edita escribiendo en la otra).
        case directa(propiedad: String)
        /// Vive en la carpeta de este proyecto (`…/Proyectos/x/Tareas/`) aunque no lo diga en sus propiedades.
        case porCarpeta
        /// Cuelga de algo que cuelga de aquí: la factura de la oportunidad de Jorge.
        case indirecta(por: VaultPath, propiedad: String)
    }

    public var id: VaultPath { ficha.ruta }
    public let ficha: FichaGrafo
    public let via: Via

    /// La relación se guarda en la otra ficha y se puede quitar desde aquí escribiendo allí.
    public var esDirecta: Bool { if case .directa = via { return true }; return false }
}

/// Las relaciones tipadas de toda la carpeta en los dos sentidos (DISEÑO §5.1): cada una la guarda una sola
/// ficha y la otra la calcula de aquí. También «Enlazan aquí» desde el texto. Se construye de una foto de la
/// carpeta (`VaultSnapshot`); nunca escribe.
public struct GrafoRelaciones: Sendable {
    public let fichas: [VaultPath: FichaGrafo]
    public let salientes: [VaultPath: [EnlaceTipado]]
    public let entrantes: [VaultPath: [EnlaceTipado]]
    let enTexto: [VaultPath: [EnlaceEnTexto]]
    /// Números de documento con un cobro confirmado en `pagos.csv` (`verificacion: confirmado`).
    let cobrosConfirmados: Set<String>
    /// Carpeta de proyectos de la estructura (`Proyectos`).
    let carpetaProyectos: String

    /// Tipos que agrupan a otros: lo que cuelga de ellos también cuelga de quien los tiene.
    static let contenedores: Set<NoteKind> = [.opportunity, .project]

    public init(snapshot: VaultSnapshot) {
        let layout = snapshot.layout
        let resolver = snapshot.resolver
        var ids: [String: VaultPath]?
        func lookupID(_ id: String) -> VaultPath? {
            if ids == nil { ids = snapshot.idIndex() }
            return ids?[id.lowercased()]
        }
        var fichas: [VaultPath: FichaGrafo] = [:]
        var salientes: [VaultPath: [EnlaceTipado]] = [:]
        var entrantes: [VaultPath: [EnlaceTipado]] = [:]
        var enTexto: [VaultPath: [EnlaceEnTexto]] = [:]
        let notas = snapshot.notes.filter { !VaultSnapshot.isTemplatePath($0) && !layout.isArchived($0) }
        var documentos: [(VaultPath, NoteDocument)] = []
        for ruta in notas {
            guard let text = snapshot.text(ruta) else { continue }
            let doc = NoteDocument(text: text)
            let fm = doc.frontmatter
            let tipo = NoteKindResolver.kind(of: ruta, frontmatter: fm, layout: layout)
            let nombre = Self.nombre(fm, doc: doc, ruta: ruta)
            fichas[ruta] = FichaGrafo(ruta: ruta, tipo: tipo, nombre: nombre, propiedades: fm, privada: layout.isPrivate(ruta))
            documentos.append((ruta, doc))
        }
        for (ruta, doc) in documentos {
            guard let ficha = fichas[ruta] else { continue }
            var propias: [EnlaceTipado] = []
            for p in ficha.propiedades.properties where !Self.noSonRelaciones.contains(p.key) {
                let valores: [(String, Int?)]
                switch p.value {
                case .text(let t): valores = [(t, nil)]
                case .list(let l): valores = l.enumerated().map { ($0.element, $0.offset) }
                default: continue
                }
                let conocida = EsquemaRelaciones.clavesDeRelacion.contains(p.key)
                for (v, i) in valores {
                    let t = v.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, !t.contains("{{") else { continue }
                    let tieneEnlace = t.contains("[[") || t.contains("](")
                    guard tieneEnlace || conocida else { continue }
                    guard let destino = ContextoPlantilla.resolve(t, from: ruta, resolver: resolver, ids: lookupID),
                          destino != ruta, fichas[destino] != nil else { continue }
                    let e = EnlaceTipado(origen: ruta, clave: p.key, propiedad: EsquemaRelaciones.canonica(p.key, tipo: ficha.tipo),
                                         destino: destino, valor: t, posicion: i)
                    propias.append(e)
                    entrantes[destino, default: []].append(e)
                }
            }
            if !propias.isEmpty { salientes[ruta] = propias }
            // Enlaces desde el texto (el cuerpo): «Enlazan aquí» del inspector.
            var vistos = Set<VaultPath>()
            let lineas = doc.text.components(separatedBy: "\n")
            for occ in LinkScanner.scan(doc.text) where occ.lugar == .cuerpo && !occ.link.isExternal {
                guard let destino = resolver.resolve(occ.link.resolvable, from: ruta), destino != ruta,
                      fichas[destino] != nil, vistos.insert(destino).inserted else { continue }
                let linea = occ.line >= 1 && occ.line <= lineas.count ? lineas[occ.line - 1] : ""
                enTexto[destino, default: []].append(EnlaceEnTexto(origen: ruta, linea: occ.line,
                                                                   extracto: linea.trimmingCharacters(in: .whitespaces)))
            }
        }
        self.fichas = fichas
        self.salientes = salientes
        self.entrantes = entrantes
        self.enTexto = enTexto
        self.cobrosConfirmados = Self.leerCobros(snapshot)
        self.carpetaProyectos = layout.proyectos
    }

    /// Propiedades que nunca son relaciones aunque lleven corchetes.
    static let noSonRelaciones: Set<String> = ["aliases", "alias", "tags", "tls_type", "tls_schema", "id", "plantilla",
                                                "nombre", "titulo", "título", "name", "title"]

    static func nombre(_ fm: Frontmatter, doc: NoteDocument, ruta: VaultPath) -> String {
        for k in ["nombre", "titulo", "título"] {
            if let v = fm.properties.first(where: { $0.key == k })?.value.displayText.trimmingCharacters(in: .whitespaces),
               !v.isEmpty, !v.contains("{{") { return v }
        }
        return doc.title(fileStem: ruta.stem)
    }

    static func leerCobros(_ snapshot: VaultSnapshot) -> Set<String> {
        var out = Set<String>()
        for p in snapshot.textPaths where TextFolding.nameKey(p.name) == "pagos.csv" {
            guard let t = snapshot.text(p) else { continue }
            let tabla = CSVTable.parse(t)
            guard let doc = tabla.header.firstIndex(of: "documento_id"),
                  let ver = tabla.header.firstIndex(of: "verificacion") else { continue }
            let dir = tabla.header.firstIndex(of: "direccion")
            for fila in tabla.rows where fila.count > max(doc, ver) {
                if let dir, fila.count > dir, TextFolding.fold(fila[dir]) != "cobro" { continue }
                if TextFolding.fold(fila[ver]) == "confirmado" { out.insert(fila[doc].trimmingCharacters(in: .whitespaces)) }
            }
        }
        return out
    }

    // MARK: Lectura

    public func ficha(_ ruta: VaultPath) -> FichaGrafo? { fichas[ruta] }

    /// Fichas de unos tipos, sin las privadas, por nombre.
    public func fichas(de tipos: Set<NoteKind>) -> [FichaGrafo] {
        fichas.values.filter { tipos.contains($0.tipo) && !$0.privada }
            .sorted { $0.nombre.localizedStandardCompare($1.nombre) == .orderedAscending }
    }

    /// Destinos de una propiedad de una ficha (canónica: `empresa` también lee `empresa_id`), en orden.
    public func destinos(de ruta: VaultPath, propiedad: String) -> [VaultPath] {
        (salientes[ruta] ?? []).filter { $0.propiedad == propiedad }.map(\.destino)
    }

    /// Las relaciones que guarda esta ficha, en el orden en que están escritas.
    public func relacionesGuardadas(por ruta: VaultPath) -> [EnlaceTipado] {
        salientes[ruta] ?? []
    }

    /// Notas que enlazan aquí desde su texto (no desde sus propiedades), sin las privadas.
    public func enlazanDesdeTexto(_ ruta: VaultPath) -> [EnlaceEnTexto] {
        (enTexto[ruta] ?? []).filter { fichas[$0.origen]?.privada != true }
    }

    /// Lo que cuelga de una ficha: lo que la enlaza en sus propiedades (directo), lo que vive en la carpeta
    /// de un proyecto y lo que cuelga de sus oportunidades y proyectos (indirecto). Sin privadas ni repetidos.
    public func relacionados(de ruta: VaultPath) -> [Relacionado] {
        guard let yo = fichas[ruta] else { return [] }
        var out: [Relacionado] = []
        var vistos: Set<VaultPath> = [ruta]
        func anadir(_ f: FichaGrafo, _ via: Relacionado.Via) {
            guard !f.privada, vistos.insert(f.ruta).inserted else { return }
            out.append(Relacionado(ficha: f, via: via))
        }
        // 1. Directo: lo que guarda una propiedad que apunta aquí.
        var contenedores: [VaultPath] = []
        for e in entrantes[ruta] ?? [] {
            guard let f = fichas[e.origen] else { continue }
            anadir(f, .directa(propiedad: e.propiedad))
            if Self.contenedores.contains(f.tipo) { contenedores.append(f.ruta) }
        }
        // 2. Por carpeta: lo que vive dentro de la carpeta de un proyecto.
        if yo.tipo == .project, let carpeta = ruta.parent {
            for f in fichas.values.filter({ $0.ruta.isDescendant(of: carpeta) }).sorted(by: { $0.ruta < $1.ruta })
            where f.ruta != ruta && f.tipo != .project {
                anadir(f, .porCarpeta)
            }
        }
        // 3. Indirecto: lo que cuelga de sus oportunidades y proyectos (y de lo que cuelga de ellos).
        // Un proyecto también reúne las facturas y cobros de su oportunidad.
        if yo.tipo == .project {
            for d in destinos(de: ruta, propiedad: "oportunidad") {
                for e in entrantes[d] ?? [] {
                    guard let f = fichas[e.origen], [.invoice, .receipt].contains(f.tipo) else { continue }
                    anadir(f, .indirecta(por: d, propiedad: e.propiedad))
                }
            }
        }
        var cola = contenedores
        var expandidos: Set<VaultPath> = [ruta]
        while !cola.isEmpty {
            let c = cola.removeFirst()
            guard expandidos.insert(c).inserted else { continue }
            for e in entrantes[c] ?? [] {
                guard let f = fichas[e.origen], f.ruta != ruta else { continue }
                anadir(f, .indirecta(por: c, propiedad: e.propiedad))
                if Self.contenedores.contains(f.tipo) { cola.append(f.ruta) }
            }
            // Lo que vive en la carpeta de un proyecto que cuelga de aquí.
            if fichas[c]?.tipo == .project, let carpeta = c.parent {
                for f in fichas.values.filter({ $0.ruta.isDescendant(of: carpeta) }).sorted(by: { $0.ruta < $1.ruta })
                where f.ruta != c && f.ruta != ruta && f.tipo != .project {
                    anadir(f, .indirecta(por: c, propiedad: "carpeta"))
                }
            }
        }
        return out
    }

    /// Las fichas de un tipo que guardan `propiedad` apuntando a `destino` (para la regla de «única»).
    public func origenes(de destino: VaultPath, propiedad: String, tipo: NoteKind? = nil) -> [VaultPath] {
        (entrantes[destino] ?? []).filter { e in
            e.propiedad == propiedad && (tipo == nil || fichas[e.origen]?.tipo == tipo)
        }.map(\.origen)
    }

    // MARK: Cobro confirmado (regla de Ganada)

    /// Si la oportunidad tiene un cobro confirmado por una persona (GUION-MAQUETAS §5): una factura suya con un
    /// recibo confirmado por una persona o con el cobro confirmado en `pagos.csv` (lo mismo que VEN-07 en
    /// `Invariantes`). Si no, el motivo en palabras.
    public func cobroConfirmado(oportunidad: VaultPath) -> (confirmado: Bool, motivo: String) {
        let facturas = origenes(de: oportunidad, propiedad: "oportunidad", tipo: .invoice).compactMap { fichas[$0] }
        let base = "Ganada necesita un cobro confirmado por una persona."
        guard !facturas.isEmpty else { return (false, base + " Esta oportunidad aún no tiene factura.") }
        for f in facturas {
            let recibos = origenes(de: f.ruta, propiedad: "factura", tipo: .receipt).compactMap { fichas[$0] }
            let porPersona = recibos.contains { r in
                guard let quien = r.texto("confirmado_por") else { return false }
                return !quien.lowercased().hasPrefix("agente:")
            }
            let enPagos = f.numero.map { cobrosConfirmados.contains($0) } ?? false
            // Como VEN-07 del dominio (integración F2): solo cuenta lo que confirmó una persona (su recibo o la fila
            // de `pagos.csv`); una factura que dice «Cobrada» sin nada de eso no basta.
            if porPersona || enPagos { return (true, "") }
        }
        let f = facturas[0]
        let nombre = f.numero.map { "La factura \($0)" } ?? "Su factura"
        let estado = (f.estado ?? "sin estado").lowercased()
        return (false, base + " \(nombre) está \(estado) y su cobro aún no se ha confirmado.")
    }
}
