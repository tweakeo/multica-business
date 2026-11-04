import Foundation

// Quién guarda cada relación entre fichas (SISTEMAS.md §3.6, DISEÑO-MOSAICO-V2 §5.1). Cada relación vive en
// **una sola** ficha (la que lleva la propiedad); la otra la calcula del índice y nunca se escribe.

/// Cuántas fichas admite una relación.
public enum Cardinalidad: Sendable, Hashable {
    /// Una sola: `empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"`.
    case una
    /// Una lista: `personas: ["[[sergio-nexo|Sergio Nexo]]", "[[lucia-andreu|Lucía Andreu]]"]`.
    case varias
}

/// Cuándo una relación no se puede dejar vacía (§5.4: las obligatorias no tienen «Quitar», solo «Cambiar…»).
public enum CondicionRelacion: Sendable, Hashable {
    /// Siempre.
    case siempre
    /// Cuando el estado de la ficha que la guarda es uno de estos (la oportunidad, desde Propuesta).
    case enEstados([String])
    /// Cuando la ficha lleva esa propiedad con ese valor (un proyecto de entrega: `clase: entrega`).
    case conPropiedad(String, String)
}

public enum ReglaRelacion: Sendable, Hashable {
    case opcional
    /// Obligatoria, con el motivo que se enseña junto al «Quitar» desactivado.
    case obligatoria(motivo: String, cuando: CondicionRelacion = .siempre)
}

/// Una relación tipada: qué ficha la guarda, en qué propiedad, a qué apunta y con qué reglas.
public struct DefinicionRelacion: Sendable, Hashable, Identifiable {
    public var id: String { guarda.map(\.rawValue).sorted().joined(separator: ",") + "·" + propiedad }
    /// Tipos de ficha que llevan la propiedad.
    public let guarda: Set<NoteKind>
    public let propiedad: String
    /// Nombres heredados que se aceptan al leer (`empresa_id`). Al escribir, solo `propiedad`.
    public let alias: [String]
    /// Tipos a los que puede apuntar (lo dice el diccionario).
    public let apuntaA: Set<NoteKind>
    public let cardinalidad: Cardinalidad
    public let regla: ReglaRelacion
    /// La ficha de destino admite como mucho una ficha de este tipo con esta relación (una oportunidad
    /// tiene como mucho un proyecto de entrega).
    public let unicaEnDestino: Bool
    /// Nombre en la ficha que la guarda («Empresa», «Recomendado por»).
    public let etiqueta: String
    /// Nombre en la otra ficha («Personas», «Recomendó a»).
    public let etiquetaInversa: String

    public init(guarda: Set<NoteKind>, propiedad: String, alias: [String] = [], apuntaA: Set<NoteKind>,
                cardinalidad: Cardinalidad = .una, regla: ReglaRelacion = .opcional, unicaEnDestino: Bool = false,
                etiqueta: String, etiquetaInversa: String) {
        self.guarda = guarda; self.propiedad = propiedad; self.alias = alias; self.apuntaA = apuntaA
        self.cardinalidad = cardinalidad; self.regla = regla; self.unicaEnDestino = unicaEnDestino
        self.etiqueta = etiqueta; self.etiquetaInversa = etiquetaInversa
    }

    /// Todas las claves con las que se puede leer.
    public var claves: [String] { [propiedad] + alias }

    /// Motivo por el que no se puede quitar en una ficha con estas propiedades (`nil` = se puede quitar).
    public func motivoObligatoria(_ propiedades: Frontmatter) -> String? {
        guard case .obligatoria(let motivo, let cuando) = regla else { return nil }
        switch cuando {
        case .siempre:
            return motivo
        case .enEstados(let estados):
            guard let e = propiedades.text("estado") else { return nil }
            let k = TextFolding.fold(e)
            return estados.contains { TextFolding.fold($0) == k } ? motivo : nil
        case .conPropiedad(let clave, let valor):
            guard let v = propiedades.text(clave) else { return nil }
            return TextFolding.fold(v) == TextFolding.fold(valor) ? motivo : nil
        }
    }
}

/// La tabla de relaciones de la app (§5.1). Se amplía, no se cambia.
public enum EsquemaRelaciones {
    static let documentos: Set<NoteKind> = [.proposal, .quote, .agreement]

    public static let todas: [DefinicionRelacion] = [
        // Contacto
        DefinicionRelacion(guarda: [.contact], propiedad: "empresa", alias: ["empresa_id"], apuntaA: [.organization],
                           etiqueta: "Empresa", etiquetaInversa: "Personas"),
        DefinicionRelacion(guarda: [.contact], propiedad: "referido_por", apuntaA: [.contact],
                           etiqueta: "Recomendado por", etiquetaInversa: "Recomendó a"),
        DefinicionRelacion(guarda: [.contact], propiedad: "conversacion", apuntaA: [.conversation],
                           etiqueta: "Conversación de origen", etiquetaInversa: "Contactos"),
        // Oportunidad
        DefinicionRelacion(guarda: [.opportunity], propiedad: "empresa", alias: ["empresa_id"], apuntaA: [.organization],
                           regla: .obligatoria(motivo: "Una oportunidad siempre tiene empresa: se cambia, no se quita."),
                           etiqueta: "Empresa", etiquetaInversa: "Oportunidades"),
        DefinicionRelacion(guarda: [.opportunity], propiedad: "contacto", alias: ["contacto_id"], apuntaA: [.contact],
                           regla: .obligatoria(motivo: "Una oportunidad siempre tiene contacto: se cambia, no se quita."),
                           etiqueta: "Contacto", etiquetaInversa: "Oportunidades"),
        DefinicionRelacion(guarda: [.opportunity], propiedad: "servicio", alias: ["producto_id"], apuntaA: [.service],
                           regla: .obligatoria(motivo: "Desde Propuesta, una oportunidad siempre tiene servicio: se cambia, no se quita.",
                                               cuando: .enEstados(["Propuesta", "Aceptada", "Ganada"])),
                           etiqueta: "Servicio", etiquetaInversa: "Oportunidades"),
        DefinicionRelacion(guarda: [.opportunity], propiedad: "oferta_version", apuntaA: [.offer],
                           regla: .obligatoria(motivo: "Desde Propuesta, el precio sale de una versión de la oferta: se cambia, no se quita.",
                                               cuando: .enEstados(["Propuesta", "Aceptada", "Ganada"])),
                           etiqueta: "Versión de oferta", etiquetaInversa: "Oportunidades"),
        DefinicionRelacion(guarda: [.opportunity], propiedad: "conversacion", apuntaA: [.conversation],
                           etiqueta: "Conversación", etiquetaInversa: "Oportunidades"),
        DefinicionRelacion(guarda: [.opportunity], propiedad: "referido_por", apuntaA: [.contact],
                           etiqueta: "Recomendado por", etiquetaInversa: "Oportunidades que trajo"),
        // Documentos de la oportunidad
        DefinicionRelacion(guarda: documentos, propiedad: "oportunidad", alias: ["oportunidad_id"], apuntaA: [.opportunity],
                           regla: .obligatoria(motivo: "Un documento siempre cuelga de una oportunidad: se cambia, no se quita."),
                           etiqueta: "Oportunidad", etiquetaInversa: "Propuestas"),
        DefinicionRelacion(guarda: [.proposal], propiedad: "reunion", apuntaA: [.meeting],
                           etiqueta: "Reunión", etiquetaInversa: "Propuestas"),
        // Proyecto
        DefinicionRelacion(guarda: [.project], propiedad: "oportunidad", alias: ["oportunidad_id"], apuntaA: [.opportunity],
                           regla: .obligatoria(motivo: "Un proyecto de entrega siempre nace de una oportunidad: se cambia, no se quita.",
                                               cuando: .conPropiedad("clase", "entrega")),
                           unicaEnDestino: true, etiqueta: "Oportunidad", etiquetaInversa: "Proyectos"),
        DefinicionRelacion(guarda: [.project], propiedad: "empresa", alias: ["empresa_id"], apuntaA: [.organization],
                           regla: .obligatoria(motivo: "Un proyecto de entrega siempre tiene empresa: se cambia, no se quita.",
                                               cuando: .conPropiedad("clase", "entrega")),
                           etiqueta: "Empresa", etiquetaInversa: "Proyectos"),
        DefinicionRelacion(guarda: [.project], propiedad: "contacto", alias: ["contacto_id"], apuntaA: [.contact],
                           etiqueta: "Contacto", etiquetaInversa: "Proyectos"),
        DefinicionRelacion(guarda: [.project], propiedad: "servicio", apuntaA: [.service],
                           etiqueta: "Servicio", etiquetaInversa: "Proyectos"),
        DefinicionRelacion(guarda: [.project], propiedad: "plan", alias: ["plantilla_id"], apuntaA: [.deliveryTemplate],
                           etiqueta: "Plan de entrega", etiquetaInversa: "Proyectos"),
        DefinicionRelacion(guarda: [.project], propiedad: "objetivo", alias: ["objetivo_id"], apuntaA: [.objective],
                           etiqueta: "Objetivo", etiquetaInversa: "Proyectos"),
        DefinicionRelacion(guarda: [.deliveryTemplate], propiedad: "servicio", apuntaA: [.service],
                           regla: .obligatoria(motivo: "Un plan de entrega siempre es de un servicio."),
                           etiqueta: "Servicio", etiquetaInversa: "Planes de entrega"),
        DefinicionRelacion(guarda: [.offer], propiedad: "servicio", apuntaA: [.service],
                           regla: .obligatoria(motivo: "Una versión de la oferta siempre es de un servicio."),
                           etiqueta: "Servicio", etiquetaInversa: "Versiones"),
        // Tarea
        DefinicionRelacion(guarda: [.task], propiedad: "proyecto", alias: ["proyecto_id"], apuntaA: [.project],
                           etiqueta: "Proyecto", etiquetaInversa: "Tareas"),
        DefinicionRelacion(guarda: [.task], propiedad: "oportunidad", alias: ["oportunidad_id"], apuntaA: [.opportunity],
                           etiqueta: "Oportunidad", etiquetaInversa: "Tareas"),
        DefinicionRelacion(guarda: [.task], propiedad: "empresa", alias: ["empresa_id"], apuntaA: [.organization],
                           etiqueta: "Empresa", etiquetaInversa: "Tareas"),
        DefinicionRelacion(guarda: [.task], propiedad: "padre", alias: ["padre_id"], apuntaA: [.task],
                           etiqueta: "Tarea madre", etiquetaInversa: "Subtareas"),
        DefinicionRelacion(guarda: [.task], propiedad: "bloqueada_por", apuntaA: [.task], cardinalidad: .varias,
                           etiqueta: "Bloqueada por", etiquetaInversa: "Bloquea a"),
        // Reunión
        DefinicionRelacion(guarda: [.meeting], propiedad: "proyecto", alias: ["proyecto_id"], apuntaA: [.project],
                           etiqueta: "Proyecto", etiquetaInversa: "Reuniones"),
        DefinicionRelacion(guarda: [.meeting], propiedad: "oportunidad", alias: ["oportunidad_id"], apuntaA: [.opportunity],
                           etiqueta: "Oportunidad", etiquetaInversa: "Reuniones"),
        DefinicionRelacion(guarda: [.meeting], propiedad: "empresa", alias: ["empresa_id"], apuntaA: [.organization],
                           etiqueta: "Empresa", etiquetaInversa: "Reuniones"),
        DefinicionRelacion(guarda: [.meeting], propiedad: "personas", alias: ["asistentes", "people"], apuntaA: [.contact],
                           cardinalidad: .varias, etiqueta: "Personas", etiquetaInversa: "Reuniones"),
        DefinicionRelacion(guarda: [.meeting], propiedad: "servicio", apuntaA: [.service],
                           etiqueta: "Servicio", etiquetaInversa: "Reuniones"),
        // Incidencia
        DefinicionRelacion(guarda: [.incident], propiedad: "proyecto", alias: ["proyecto_id"], apuntaA: [.project],
                           regla: .obligatoria(motivo: "Una incidencia siempre es de un proyecto: se cambia, no se quita."),
                           etiqueta: "Proyecto", etiquetaInversa: "Incidencias"),
        DefinicionRelacion(guarda: [.incident], propiedad: "tarea", alias: ["tarea_id"], apuntaA: [.task],
                           etiqueta: "Tarea", etiquetaInversa: "Incidencias"),
        // Borrador
        DefinicionRelacion(guarda: [.draft], propiedad: "tarea", apuntaA: [.task], etiqueta: "Tarea", etiquetaInversa: "Borradores"),
        DefinicionRelacion(guarda: [.draft], propiedad: "oportunidad", apuntaA: [.opportunity], etiqueta: "Oportunidad", etiquetaInversa: "Borradores"),
        DefinicionRelacion(guarda: [.draft], propiedad: "proyecto", apuntaA: [.project], etiqueta: "Proyecto", etiquetaInversa: "Borradores"),
        DefinicionRelacion(guarda: [.draft], propiedad: "para", apuntaA: [.contact], etiqueta: "Para", etiquetaInversa: "Borradores"),
        // Factura y recibo
        DefinicionRelacion(guarda: [.invoice], propiedad: "empresa", alias: ["empresa_id"], apuntaA: [.organization],
                           regla: .obligatoria(motivo: "Una factura siempre tiene empresa: se cambia, no se quita."),
                           etiqueta: "Empresa", etiquetaInversa: "Facturas"),
        DefinicionRelacion(guarda: [.invoice], propiedad: "contacto", alias: ["contacto_id"], apuntaA: [.contact],
                           etiqueta: "Contacto", etiquetaInversa: "Facturas"),
        DefinicionRelacion(guarda: [.invoice], propiedad: "oportunidad", alias: ["oportunidad_id"], apuntaA: [.opportunity],
                           etiqueta: "Oportunidad", etiquetaInversa: "Facturas"),
        DefinicionRelacion(guarda: [.invoice], propiedad: "proyecto", alias: ["proyecto_id"], apuntaA: [.project],
                           etiqueta: "Proyecto", etiquetaInversa: "Facturas"),
        DefinicionRelacion(guarda: [.invoice], propiedad: "rectifica", alias: ["rectifica_id"], apuntaA: [.invoice],
                           etiqueta: "Rectifica", etiquetaInversa: "Rectificada por"),
        DefinicionRelacion(guarda: [.invoice], propiedad: "servicio", alias: ["producto_id"], apuntaA: [.service],
                           etiqueta: "Servicio", etiquetaInversa: "Facturas"),
        DefinicionRelacion(guarda: [.invoice], propiedad: "oferta_version", apuntaA: [.offer],
                           etiqueta: "Versión de oferta", etiquetaInversa: "Facturas"),
        DefinicionRelacion(guarda: [.receipt], propiedad: "factura", apuntaA: [.invoice],
                           regla: .obligatoria(motivo: "Un recibo siempre es de una factura."),
                           etiqueta: "Factura", etiquetaInversa: "Cobros"),
        // Marca
        DefinicionRelacion(guarda: [.conversation], propiedad: "contacto", apuntaA: [.contact],
                           etiqueta: "Contacto", etiquetaInversa: "Conversaciones"),
        DefinicionRelacion(guarda: [.conversation], propiedad: "contenido", apuntaA: [.content],
                           etiqueta: "Contenido", etiquetaInversa: "Conversaciones que trajo"),
        DefinicionRelacion(guarda: [.content], propiedad: "derivado_de", apuntaA: [.content],
                           etiqueta: "Derivado de", etiquetaInversa: "Derivados"),
        DefinicionRelacion(guarda: [.content], propiedad: "servicio", apuntaA: [.service], etiqueta: "Servicio", etiquetaInversa: "Contenidos"),
        DefinicionRelacion(guarda: [.content], propiedad: "proyecto", apuntaA: [.project], etiqueta: "Caso", etiquetaInversa: "Contenidos"),
        // Dirección y equipo
        DefinicionRelacion(guarda: [.decision], propiedad: "sustituye", alias: ["sustituye_id"], apuntaA: [.decision],
                           etiqueta: "Sustituye a", etiquetaInversa: "Sustituida por"),
        DefinicionRelacion(guarda: [.system], propiedad: "rol", apuntaA: [.role],
                           regla: .obligatoria(motivo: "Un sistema siempre tiene un rol que responde de él."),
                           etiqueta: "Rol", etiquetaInversa: "Sistemas"),
        DefinicionRelacion(guarda: [.system], propiedad: "conexiones", apuntaA: [.connection], cardinalidad: .varias,
                           etiqueta: "Conexiones", etiquetaInversa: "Sistemas que la usan"),
        DefinicionRelacion(guarda: [.procedure, .asset], propiedad: "sistema", apuntaA: [.system],
                           regla: .obligatoria(motivo: "Siempre cuelga de un sistema: se cambia, no se quita."),
                           etiqueta: "Sistema", etiquetaInversa: "Procedimientos y activos"),
        DefinicionRelacion(guarda: [.collaboration], propiedad: "contacto", apuntaA: [.contact],
                           regla: .obligatoria(motivo: "Un acuerdo de colaboración siempre es con alguien."),
                           etiqueta: "Contacto", etiquetaInversa: "Colaboraciones"),
        DefinicionRelacion(guarda: [.collaboration], propiedad: "proyecto", apuntaA: [.project],
                           regla: .obligatoria(motivo: "Un acuerdo de colaboración siempre es para un proyecto."),
                           etiqueta: "Proyecto", etiquetaInversa: "Colaboradores"),
    ]

    /// Todas las claves que son relaciones (para leer también lo escrito sin enlace: `empresa: Talleres`).
    public static let clavesDeRelacion: Set<String> = Set(todas.flatMap(\.claves))

    /// La relación que guarda una ficha de `tipo` en `propiedad` (o en uno de sus alias).
    public static func definicion(tipo: NoteKind, propiedad: String) -> DefinicionRelacion? {
        let k = propiedad.precomposedStringWithCanonicalMapping
        return todas.first { $0.guarda.contains(tipo) && $0.claves.contains(k) }
    }

    /// Las relaciones que guarda una ficha de `tipo`, en el orden de la tabla.
    public static func guardadas(por tipo: NoteKind) -> [DefinicionRelacion] {
        todas.filter { $0.guarda.contains(tipo) }
    }

    /// Para añadir desde el lado que **no** la guarda: la relación que lleva una ficha de tipo `otro`
    /// apuntando a una de tipo `desde` («Añadir existente…» de Tareas en un proyecto → `tarea.proyecto`).
    /// Si hay varias, la primera de la tabla (la natural).
    public static func quienGuarda(apuntandoA desde: NoteKind, desde otro: NoteKind) -> DefinicionRelacion? {
        todas.first { $0.guarda.contains(otro) && $0.apuntaA.contains(desde) }
    }

    /// Clave canónica de una clave leída (`empresa_id` → `empresa`).
    public static func canonica(_ clave: String, tipo: NoteKind?) -> String {
        if let tipo, let d = definicion(tipo: tipo, propiedad: clave) { return d.propiedad }
        if let d = todas.first(where: { $0.alias.contains(clave) }) { return d.propiedad }
        return clave
    }
}
