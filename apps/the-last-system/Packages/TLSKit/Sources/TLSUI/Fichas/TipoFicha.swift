import Foundation
import TLSCore

/// Qué va dentro de una pestaña de la ficha.
enum ContenidoPestana: Hashable, Sendable {
    case resumen
    case notas
    case actividad
    case fichero
    /// Lo relacionado de esos tipos, en lista (o tabla).
    case relacionados(Set<NoteKind>)
    /// Las tareas del proyecto en tablero, con el panel de la tarea elegida.
    case tareasProyecto
    /// Las subtareas de una tarea.
    case subtareas
    /// Los ficheros de la carpeta del proyecto (`Materiales/`).
    case materiales
    /// Una sección de la nota, editable en el sitio (ficha de sistema: Pasos, Aprendido…).
    case seccion(String)
    /// Ejecuciones de un sistema: tareas y documentos que salieron de él (calculado).
    case ejecuciones
}

/// Una pestaña de la ficha: el nombre visible (es el que guardan las migas) y su contenido.
struct DefPestana: Hashable, Sendable, Identifiable {
    var id: String { titulo }
    let titulo: String
    let contenido: ContenidoPestana
    /// Sale aunque esté vacía (tiene un «+ Nuevo» propio del momento); si no, vacía va a «Más».
    let siempre: Bool

    init(_ titulo: String, _ contenido: ContenidoPestana, siempre: Bool = true) {
        self.titulo = titulo; self.contenido = contenido; self.siempre = siempre
    }
}

/// Una opción de «Nuevo ▾»: la ficha nace con su plantilla y ya enlazada a esta.
struct OpcionNuevo: Hashable, Sendable, Identifiable {
    var id: String { plantilla + titulo }
    let titulo: String
    let plantilla: String
    let tipo: NoteKind

    static let masculinos: Set<String> = ["proyecto", "presupuesto", "seguimiento", "informe", "procedimiento", "activo", "correo",
                                          "recibo", "recordatorio", "contrato"]

    /// «Nueva reunión», «Nuevo proyecto».
    var nuevoTitulo: String {
        let t = titulo.lowercased()
        let primera = t.split(separator: " ").first.map(String.init) ?? t
        return (Self.masculinos.contains(primera) ? "Nuevo " : "Nueva ") + t
    }
}

/// La configuración de cada tipo de ficha (DISEÑO §3.3 y §3.4): pestañas en orden, pestaña inicial según
/// el estado y lo que ofrece «Nuevo ▾».
struct TipoFicha: Sendable {
    let tipo: NoteKind
    let pestanas: [DefPestana]
    let nuevo: [OpcionNuevo]

    static let documentos: Set<NoteKind> = [.proposal, .quote, .agreement]

    static func de(_ tipo: NoteKind) -> TipoFicha {
        let comunes = [DefPestana("Notas", .notas), DefPestana("Actividad", .actividad), DefPestana("Fichero", .fichero)]
        switch tipo {
        case .organization:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Personas", .relacionados([.contact])),
                DefPestana("Oportunidades", .relacionados([.opportunity])),
                DefPestana("Reuniones", .relacionados([.meeting])),
                DefPestana("Propuestas", .relacionados(documentos)),
                DefPestana("Proyectos", .relacionados([.project])),
                DefPestana("Facturas", .relacionados([.invoice])),
                DefPestana("Tareas", .relacionados([.task])),
                DefPestana("Incidencias", .relacionados([.incident]), siempre: false),
                DefPestana("Conversaciones y casos", .relacionados([.conversation, .content]), siempre: false),
            ] + comunes, nuevo: [
                OpcionNuevo(titulo: "Reunión", plantilla: "reunion", tipo: .meeting),
                OpcionNuevo(titulo: "Propuesta", plantilla: "propuesta", tipo: .proposal),
                OpcionNuevo(titulo: "Proyecto", plantilla: "proyecto-de-entrega", tipo: .project),
                OpcionNuevo(titulo: "Factura", plantilla: "factura", tipo: .invoice),
                OpcionNuevo(titulo: "Persona", plantilla: "contacto", tipo: .contact),
                OpcionNuevo(titulo: "Tarea", plantilla: "tarea", tipo: .task),
            ])
        case .contact:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Oportunidades", .relacionados([.opportunity])),
                DefPestana("Reuniones", .relacionados([.meeting])),
                DefPestana("Propuestas", .relacionados(documentos)),
                DefPestana("Proyectos", .relacionados([.project])),
                DefPestana("Facturas", .relacionados([.invoice])),
                DefPestana("Tareas", .relacionados([.task]), siempre: false),
                DefPestana("Conversaciones", .relacionados([.conversation]), siempre: false),
            ] + comunes, nuevo: [
                OpcionNuevo(titulo: "Reunión", plantilla: "reunion", tipo: .meeting),
                OpcionNuevo(titulo: "Propuesta", plantilla: "propuesta", tipo: .proposal),
                OpcionNuevo(titulo: "Proyecto", plantilla: "proyecto-de-entrega", tipo: .project),
                OpcionNuevo(titulo: "Factura", plantilla: "factura", tipo: .invoice),
                OpcionNuevo(titulo: "Tarea", plantilla: "tarea", tipo: .task),
            ])
        case .opportunity:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Reuniones", .relacionados([.meeting])),
                DefPestana("Propuestas", .relacionados(documentos)),
                DefPestana("Facturas", .relacionados([.invoice])),
                DefPestana("Tareas", .relacionados([.task])),
            ] + comunes, nuevo: [
                OpcionNuevo(titulo: "Reunión", plantilla: "reunion", tipo: .meeting),
                OpcionNuevo(titulo: "Propuesta", plantilla: "propuesta", tipo: .proposal),
                OpcionNuevo(titulo: "Presupuesto", plantilla: "presupuesto", tipo: .quote),
                OpcionNuevo(titulo: "Tarea", plantilla: "tarea", tipo: .task),
            ])
        case .project:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Tareas", .tareasProyecto),
                DefPestana("Reuniones", .relacionados([.meeting])),
                DefPestana("Facturas", .relacionados([.invoice, .receipt])),
                DefPestana("Materiales", .materiales),
                DefPestana("Notas", .notas),
                DefPestana("Actividad", .actividad),
                DefPestana("Fichero", .fichero),
                DefPestana("Incidencias", .relacionados([.incident]), siempre: false),
                DefPestana("Informes", .relacionados([.report]), siempre: false),
            ], nuevo: [
                OpcionNuevo(titulo: "Tarea", plantilla: "tarea", tipo: .task),
                OpcionNuevo(titulo: "Seguimiento", plantilla: "reunion-de-seguimiento", tipo: .meeting),
                OpcionNuevo(titulo: "Acta de sesión", plantilla: "acta-de-sesion", tipo: .meeting),
                OpcionNuevo(titulo: "Incidencia", plantilla: "ficha-de-incidencia", tipo: .incident),
                OpcionNuevo(titulo: "Factura del hito", plantilla: "factura", tipo: .invoice),
                OpcionNuevo(titulo: "Informe", plantilla: "informe-de-avance", tipo: .report),
            ])
        case .task:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Actividad", .actividad),
                DefPestana("Subtareas", .subtareas),
                DefPestana("Fichero", .fichero),
            ], nuevo: [OpcionNuevo(titulo: "Subtarea", plantilla: "tarea", tipo: .task)])
        case .meeting:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Notas", .notas),
                DefPestana("Tareas", .relacionados([.task])),
                DefPestana("Propuestas", .relacionados(documentos)),
                DefPestana("Actividad", .actividad),
                DefPestana("Fichero", .fichero),
            ], nuevo: [
                OpcionNuevo(titulo: "Tarea", plantilla: "tarea", tipo: .task),
                OpcionNuevo(titulo: "Propuesta", plantilla: "propuesta", tipo: .proposal),
            ])
        case .invoice:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Cobros", .relacionados([.receipt])),
                DefPestana("Envíos", .relacionados([.draft])),
                DefPestana("Actividad", .actividad),
                DefPestana("Fichero", .fichero),
            ], nuevo: [OpcionNuevo(titulo: "Rectificativa", plantilla: "factura-rectificativa", tipo: .invoice)])
        case .system:
            return TipoFicha(tipo: tipo, pestanas: [
                DefPestana("Resumen", .resumen),
                DefPestana("Pasos", .seccion("Pasos")),
                DefPestana("Ejecuciones", .ejecuciones),
                DefPestana("Plantillas y activos", .seccion("Plantillas y activos")),
                DefPestana("Procedimientos", .relacionados([.procedure, .asset])),
                DefPestana("Referencias y ejemplos", .seccion("Referencias y ejemplos")),
                DefPestana("Aprendido", .seccion("Aprendido")),
            ] + comunes, nuevo: [
                OpcionNuevo(titulo: "Procedimiento", plantilla: "procedimiento", tipo: .procedure),
                OpcionNuevo(titulo: "Activo", plantilla: "activo", tipo: .asset),
            ])
        default:
            return TipoFicha(tipo: tipo, pestanas: [DefPestana("Resumen", .resumen)] + comunes, nuevo: [])
        }
    }

    /// La pestaña con la que abre (§3.3), según el tipo y el estado. `conSesiones`: el servicio del proyecto
    /// tiene sesiones (abre en Viaje).
    static func pestanaInicial(tipo: NoteKind, estado: String?, conSesiones: Bool = false) -> String {
        let e = estado.map(TextFolding.fold) ?? ""
        switch tipo {
        case .organization, .contact:
            return "Resumen"
        case .opportunity:
            switch e {
            case "prospecto", "diagnostico": return "Reuniones"
            case "propuesta": return "Propuestas"
            case "aceptada": return "Facturas"
            case "perdida", "pausada": return "Notas"
            default: return "Resumen"
            }
        case .project:
            switch e {
            case "en curso", "pausado": return conSesiones ? "Viaje" : "Tareas"
            default: return "Resumen"
            }
        case .meeting:
            return e == "hecha" ? "Notas" : "Resumen"
        case .task:
            return "Actividad"
        default:
            return "Resumen"
        }
    }
}
