import Foundation

/// Lo que propone «Adoptar» para una carpeta G3 (PLAN §4.7 y SISTEMAS.md §1.6 y §1.8). Nada se
/// aplica solo: cada parte es un plan que se ejecuta con tu OK.
public struct PropuestaAdopcion: Sendable {
    /// Ficha sin `id`: lo único que se le añade.
    public struct Identidad: Sendable, Hashable {
        public let ruta: VaultPath
        public let tipo: String
        public let anadir: [Property]
    }

    /// Relación deducida, escrita como enlace legible (`empresa: "[[slug|Nombre]]"`).
    public struct Relacion: Sendable, Hashable {
        public enum Fuente: Sendable, Hashable {
            /// Un enlace del cuerpo a una ficha de ese tipo (el único).
            case enlaceDelCuerpo
            /// El `*_id` heredado (que se quita al escribir el enlace).
            case idHeredado(String)
            /// La carpeta donde vive (una tarea dentro de `Proyectos/<slug>/Tareas/`).
            case ruta
        }

        public let ruta: VaultPath
        public let clave: String
        public let destino: VaultPath
        public let valor: String
        /// Clave heredada que se quita (`empresa_id`), si la había.
        public let quitar: [String]
        public let fuente: Fuente
    }

    /// Varias fichas posibles para una relación: no se propone ninguna.
    public struct Ambigua: Sendable, Hashable {
        public let ruta: VaultPath
        public let clave: String
        public let candidatos: [VaultPath]
    }

    public let identidades: [Identidad]
    public let relaciones: [Relacion]
    public let ambiguas: [Ambigua]
    /// `Tareas.md` heredados que pasan a fichas (o se retiran si están vacíos).
    public let tareasHeredadas: [VaultPath]

    /// Añadir `tls_type`, `tls_schema` e `id` (y `clase` en `Proyecto.md`). Solo eso.
    public func planIdentidad(autor: Autor = .persona("Manu")) -> WritePlan? {
        guard !identidades.isEmpty else { return nil }
        return WritePlan(autor: autor, descripcion: "Adoptar " + Plural.de(identidades.count, "ficha", "fichas"),
                         ops: identidades.map { .mergeFrontmatter($0.ruta, set: $0.anadir, unset: []) })
    }

    /// Las relaciones aceptadas (por defecto, todas) en una sola tarjeta y un solo plan.
    public func planRelaciones(_ aceptadas: [Relacion]? = nil, autor: Autor = .persona("Manu")) -> WritePlan? {
        let lista = aceptadas ?? relaciones
        guard !lista.isEmpty else { return nil }
        var porNota: [VaultPath: (set: [Property], unset: [String])] = [:]
        for r in lista {
            porNota[r.ruta, default: ([], [])].set.append(Property(key: r.clave, value: .text(r.valor)))
            porNota[r.ruta, default: ([], [])].unset += r.quitar
        }
        let ops = porNota.sorted { $0.key < $1.key }.map { WriteOp.mergeFrontmatter($0.key, set: $0.value.set, unset: $0.value.unset) }
        return WritePlan(autor: autor, descripcion: "Enlazar " + Plural.de(lista.count, "relación", "relaciones"), ops: ops)
    }

    public var resumen: String {
        var partes: [String] = []
        if !identidades.isEmpty { partes.append(Plural.de(identidades.count, "ficha por identificar", "fichas por identificar")) }
        if !relaciones.isEmpty { partes.append(Plural.de(relaciones.count, "relación por enlazar", "relaciones por enlazar")) }
        if !tareasHeredadas.isEmpty { partes.append(Plural.de(tareasHeredadas.count, "Tareas.md heredado", "Tareas.md heredados")) }
        guard !partes.isEmpty else { return "La carpeta ya está adoptada." }
        let texto = Plural.lista(partes)
        return texto.prefix(1).uppercased() + String(texto.dropFirst()) + "."
    }
}

/// «Adoptar» una carpeta G3 sin migrarla: identidad mínima de cada ficha y relaciones deducidas.
public struct Adopter: Sendable {
    public let snapshot: VaultSnapshot

    public init(snapshot: VaultSnapshot) { self.snapshot = snapshot }

    /// Tipos que son fichas (se les da `id`).
    static let tiposDeFicha: Set<String> = [
        "contact", "organization", "opportunity", "service", "offer", "project", "task", "objective", "routine",
        "decision", "role", "content", "conversation", "meeting", "asset", "draft", "account", "delivery_template",
        "proposal", "quote", "agreement", "invoice", "receipt", "incident", "connection", "collaboration",
    ]

    /// Carpetas de la v2 que el preset aún no conoce.
    static let carpetasV2: [String: String] = [
        "planes de entrega": "delivery_template", "reuniones": "meeting", "activos": "asset", "borradores": "draft",
        "conexiones": "connection", "colaboraciones": "collaboration",
    ]

    /// Relaciones que se deducen por tipo de ficha: clave → tipo de la ficha a la que apunta.
    static let relacionesPorTipo: [String: [(String, String)]] = [
        "contact": [("empresa", "organization")],
        "opportunity": [("empresa", "organization"), ("contacto", "contact"), ("servicio", "service")],
        "project": [("oportunidad", "opportunity"), ("empresa", "organization"), ("plan", "delivery_template"), ("objetivo", "objective")],
        "task": [("oportunidad", "opportunity"), ("empresa", "organization")],
        "meeting": [("oportunidad", "opportunity"), ("proyecto", "project"), ("empresa", "organization"), ("servicio", "service")],
        "invoice": [("empresa", "organization"), ("oportunidad", "opportunity"), ("proyecto", "project")],
        "proposal": [("oportunidad", "opportunity"), ("empresa", "organization"), ("contacto", "contact"), ("servicio", "service")],
        "quote": [("oportunidad", "opportunity"), ("empresa", "organization"), ("contacto", "contact")],
        "agreement": [("oportunidad", "opportunity"), ("empresa", "organization"), ("contacto", "contact")],
        "delivery_template": [("servicio", "service")],
        "offer": [("servicio", "service")],
        "asset": [("sistema", "system")],
        "conversation": [("contacto", "contact"), ("contenido", "content")],
        "content": [("servicio", "service"), ("proyecto", "project")],
        "receipt": [("factura", "invoice")],
        "draft": [("tarea", "task"), ("oportunidad", "opportunity"), ("proyecto", "project"), ("empresa", "organization")],
    ]

    /// Claves heredadas de cada relación.
    static let heredadas: [String: [String]] = [
        "empresa": ["empresa_id"], "contacto": ["contacto_id"], "oportunidad": ["oportunidad_id"],
        "proyecto": ["proyecto_id"], "servicio": ["producto_id", "servicio_id"], "objetivo": ["objetivo_id"],
        "plan": ["plantilla_id"], "tarea": ["tarea_id"], "factura": ["factura_id"], "sistema": ["sistema_id"],
        "contenido": ["contenido_id"],
    ]

    /// Tipo de una nota para adoptarla (`nil` si no es una ficha).
    func tipo(_ p: VaultPath, _ fm: Frontmatter) -> String? {
        if let t = fm.text("tls_type") { return t }
        let layout = snapshot.layout
        guard layout.isRecordNote(p) || TextFolding.nameKey(p.stem) == "proyecto" || TextFolding.nameKey(p.stem) == "cuenta" else { return nil }
        let kind = NoteKindResolver.kind(of: p, frontmatter: fm, layout: layout).rawValue
        if Self.tiposDeFicha.contains(kind) { return kind }
        if let parent = p.parent, let t = Self.carpetasV2[TextFolding.nameKey(parent.name)], layout.area(of: p) != nil { return t }
        if let d = layout.dir(for: "delivery_template"), p.parent == d { return "delivery_template" }
        return nil
    }

    public func proponer() -> PropuestaAdopcion {
        let layout = snapshot.layout
        let resolver = snapshot.resolver
        let ids = snapshot.idIndex()
        var tipos: [VaultPath: String] = [:]
        var identidades: [PropuestaAdopcion.Identidad] = []
        let candidatas = snapshot.notes.filter {
            !VaultSnapshot.isTemplatePath($0) && !layout.isArchived($0) && !layout.isPrivate($0)
                && TextFolding.nameKey($0.name) != TextFolding.nameKey(layout.tareas + ".md")
        }
        for p in candidatas {
            let fm = snapshot.frontmatter(p)
            guard fm.isValid, let t = tipo(p, fm) else { continue }
            tipos[p] = t
            guard fm.text("id") == nil else { continue }
            var anadir: [Property] = []
            if fm.text("tls_type") == nil { anadir.append(Property(key: "tls_type", value: .text(t))) }
            if fm.text("tls_schema") == nil { anadir.append(Property(key: "tls_schema", value: .number("1"))) }
            anadir.append(Property(key: "id", value: .text(UUID().uuidString.lowercased())))
            if t == "project", fm.text("clase") == nil {
                anadir.append(Property(key: "clase", value: .text(layout.area(of: p) == .entrega ? "entrega" : "interno")))
            }
            identidades.append(.init(ruta: p, tipo: t, anadir: anadir))
        }
        // Relaciones.
        func tipoDe(_ destino: VaultPath) -> String? {
            if let t = tipos[destino] { return t }
            guard snapshot.text(destino) != nil else { return nil }
            return tipo(destino, snapshot.frontmatter(destino))
        }
        var relaciones: [PropuestaAdopcion.Relacion] = []
        var ambiguas: [PropuestaAdopcion.Ambigua] = []
        for (p, t) in tipos.sorted(by: { $0.key < $1.key }) {
            guard let text = snapshot.text(p) else { continue }
            let fm = NoteDocument(text: text).frontmatter
            func valor(_ k: String) -> String? { fm.properties.first(where: { $0.key == k })?.value.displayText.nilIfEmpty }
            func presente(_ k: String) -> Bool { fm.properties.contains { $0.key == k } }
            var claves = Self.relacionesPorTipo[t] ?? []
            if t == "task" { claves.insert(("proyecto", "project"), at: 0) }
            // Destinos de los enlaces del cuerpo, por tipo.
            var porTipo: [String: [VaultPath]] = [:]
            for occ in LinkScanner.scan(text) where occ.lugar == .cuerpo && !occ.link.isExternal {
                guard let d = resolver.resolve(occ.link.resolvable, from: p), d != p, let dt = tipoDe(d) else { continue }
                if !(porTipo[dt]?.contains(d) ?? false) { porTipo[dt, default: []].append(d) }
            }
            for (clave, destinoTipo) in claves {
                guard valor(clave) == nil else { continue }
                let legado = (Self.heredadas[clave] ?? []).filter(presente)
                var destino: VaultPath?
                var fuente = PropuestaAdopcion.Relacion.Fuente.enlaceDelCuerpo
                // 1) `*_id` heredado con valor.
                for k in legado {
                    guard let v = valor(k), let d = ContextoPlantilla.resolve(v, from: p, resolver: resolver, ids: { ids[$0.lowercased()] })
                    else { continue }
                    destino = d; fuente = .idHeredado(k); break
                }
                // 2) La carpeta (tareas de un proyecto).
                if destino == nil, clave == "proyecto", t == "task", let d = TaskStore.proyectoDeCarpeta(p, snapshot: snapshot) {
                    destino = d; fuente = .ruta
                }
                // 3) Un único enlace del cuerpo a una ficha de ese tipo.
                if destino == nil, let lista = porTipo[destinoTipo] {
                    if lista.count == 1 { destino = lista[0] } else {
                        ambiguas.append(.init(ruta: p, clave: clave, candidatos: lista.sorted()))
                    }
                }
                guard let d = destino, let nota = ContextoPlantilla.nota(d, snapshot: snapshot) else { continue }
                relaciones.append(.init(ruta: p, clave: clave, destino: d,
                                        valor: NombresDeFicha.wikilink(d, nombre: nota.nombre, en: snapshot),
                                        quitar: legado, fuente: fuente))
            }
        }
        let tareasMd = LegacyTasksMigrator(snapshot: snapshot).encontrar()
        return PropuestaAdopcion(identidades: identidades, relaciones: relaciones, ambiguas: ambiguas, tareasHeredadas: tareasMd)
    }
}
