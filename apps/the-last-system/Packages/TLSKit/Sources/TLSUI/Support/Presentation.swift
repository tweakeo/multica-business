import SwiftUI
import TLSCore
import TLSDesign

// Cómo se presentan los tipos de TLSCore en la interfaz (textos, iconos y colores).

extension AreaCode {
    /// Área de Mosaico v2 (colores, icono de app).
    public var tlsArea: TLSArea {
        switch self {
        case .direccion: .direccion
        case .ventas: .ventas
        case .entrega: .entrega
        case .finanzas: .finanzas
        case .marca: .marca
        case .equipo: .equipo
        }
    }

    /// Color de relleno del área (icono de app, punto, barra).
    var color: Color { tlsArea.relleno.color }

    /// «2 · Ventas».
    var etiquetaNumerada: String { "\(numero) · \(nombre)" }

    /// Icono del área (§1.11): el del icono de app.
    var systemImage: String { tlsArea.simbolo }

    /// Identificador estable para pruebas de interfaz.
    var accessibilityID: String { "area.\(rawValue)" }
}

extension AreaSummary {
    /// «2 · Ventas» con el nombre que tenga la ficha.
    var etiquetaNumerada: String {
        let nombre = titulo.trimmingCharacters(in: .whitespaces)
        return "\(code.numero) · \(nombre.isEmpty ? code.nombre : nombre)"
    }
}

extension AreaStatus {
    /// Icono del estado (el texto siempre lo acompaña).
    var systemImage: String {
        switch self {
        case .activa: "checkmark.circle"
        case .preparada: "circle.dashed"
        case .reposo: "moon.zzz"
        case .desconocido: "questionmark.circle"
        }
    }

    /// Texto en minúscula para la barra lateral («activa / preparada / en reposo»).
    var etiquetaCorta: String { etiqueta.lowercased() }
}

extension NoteKind {
    /// Nombre del tipo para la persona (singular), sin jerga.
    public var etiqueta: String {
        switch self {
        case .company: "Tu empresa"
        case .area: "Área"
        case .system: "Sistema"
        case .contact: "Contacto"
        case .organization: "Empresa"
        case .opportunity: "Oportunidad"
        case .service: "Servicio"
        case .offer: "Versión de oferta"
        case .project: "Proyecto"
        case .task: "Tarea"
        case .objective: "Objetivo"
        case .routine: "Rutina"
        case .decision: "Decisión"
        case .role: "Rol"
        case .content: "Contenido"
        case .conversation: "Conversación"
        case .meeting: "Reunión"
        case .asset: "Activo"
        case .draft: "Borrador"
        case .account: "Cuenta del banco"
        case .agreement: "Contrato"
        case .background: "Antecedentes"
        case .brand: "Manual de marca"
        case .capture: "Captura"
        case .closure: "Cierre"
        case .collaboration: "Colaboración"
        case .connection: "Conexión"
        case .diagnosis: "Diagnóstico"
        case .editorialPlan: "Plan editorial"
        case .importReport: "Informe de importación"
        case .incident: "Incidencia"
        case .index: "Nota índice"
        case .invoice: "Factura"
        case .log: "Registro"
        case .period: "Trimestre"
        case .portal: "Portal"
        case .procedure: "Procedimiento"
        case .proposal: "Propuesta"
        case .quote: "Presupuesto"
        case .receipt: "Recibo"
        case .report: "Informe"
        case .rootCause: "Cinco porqués"
        case .routineLog: "Revisión"
        case .sessionSummary: "Resumen de sesión"
        case .strategy: "Rumbo"
        case .welcome: "Bienvenida"
        case .deliveryTemplate: "Plan de entrega"
        case .note: "Nota"
        case .csv: "Tabla"
        case .other: "Fichero"
        }
    }

    /// SF Symbol del tipo (§1.11 donde el diseño lo fija). Todos existen en macOS 15.
    public var systemImage: String {
        switch self {
        case .company: "briefcase"
        case .area: "square.grid.2x2"
        case .system: "gearshape.2"
        case .contact: "person.crop.circle"
        case .organization: "building.2"
        case .opportunity: "target"
        case .service, .offer: "tag"
        case .project: "square.stack.3d.up"
        case .task: "checkmark.square"
        case .objective: "scope"
        case .routine: "arrow.triangle.2.circlepath"
        case .decision: "signpost.right.and.left"
        case .role: "person.text.rectangle"
        case .content: "square.and.pencil"
        case .conversation: "bubble.left.and.bubble.right"
        case .meeting: "calendar.badge.clock"
        case .asset: "cube"
        case .draft: "envelope"
        case .account: "building.columns"
        case .agreement: "signature"
        case .background: "doc.text.magnifyingglass"
        case .brand: "paintpalette"
        case .capture: "tray.and.arrow.down"
        case .closure: "flag.checkered"
        case .collaboration: "person.2"
        case .connection: "point.3.connected.trianglepath.dotted"
        case .diagnosis: "stethoscope"
        case .editorialPlan: "calendar"
        case .importReport: "square.and.arrow.down"
        case .incident: "exclamationmark.bubble"
        case .index: "list.bullet.rectangle.portrait"
        case .invoice: "eurosign.circle"
        case .log: "list.bullet.clipboard"
        case .period: "calendar.circle"
        case .portal: "globe"
        case .procedure: "list.number"
        case .proposal: "doc.text"
        case .quote: "doc.plaintext"
        case .receipt: "checkmark.seal"
        case .report: "chart.bar.doc.horizontal"
        case .rootCause: "magnifyingglass"
        case .routineLog: "arrow.triangle.2.circlepath.circle"
        case .sessionSummary: "text.bubble"
        case .strategy: "safari"
        case .welcome: "hand.wave"
        case .deliveryTemplate: "list.bullet.rectangle"
        case .note: "doc.text"
        case .csv: "tablecells"
        case .other: "doc"
        }
    }

    /// `true` si la nota se abre como ficha (con su molde de §3); si no, como nota o fichero.
    public var abreComoFicha: Bool {
        switch self {
        case .note, .csv, .other, .area, .index, .log, .capture, .importReport: false
        default: true
        }
    }
}

extension FolderEntry {
    /// Icono por tipo de fichero.
    var systemImage: String {
        if isDirectory { return privado ? "folder.badge.minus" : "folder" }
        return FileKindIcon.systemImage(forExtension: path.ext)
    }
}

enum FileKindIcon {
    static func systemImage(forExtension ext: String) -> String {
        switch ext {
        case "md", "markdown", "txt": "doc.text"
        case "csv", "tsv", "xlsx", "xls", "numbers": "tablecells"
        case "pdf": "doc.richtext"
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff", "svg": "photo"
        case "json", "yaml", "yml", "base", "canvas": "curlybraces"
        case "zip", "gz", "dmg": "archivebox"
        case "mov", "mp4", "m4v": "film"
        case "mp3", "m4a", "wav": "waveform"
        case "doc", "docx", "pages", "rtf": "doc.richtext"
        default: "doc"
        }
    }
}

extension VaultClass {
    var badge: BadgeKind {
        switch self {
        case .copia: .copia
        case .demo: .ejemplo
        case .real: .soloLectura
        }
    }
}

extension VaultEntry {
    /// F6 · integración: la carpeta real tras «Pasar a mi carpeta real» (solo entonces `vaults.json` la deja escribir).
    var realTrasRelevo: Bool { clase == .real && escritura == .permitida }

    /// La insignia del selector y de la ventana.
    var badge: BadgeKind { realTrasRelevo ? .real : clase.badge }

    /// Texto del banner permanente de la ventana de empresa.
    var bannerText: String {
        switch clase {
        case .copia:
            "Copia del \(TLSFormat.fechaCorta(creada)): lo que cambies aquí no llega a tu carpeta real"
        case .real where realTrasRelevo:
            "Tu carpeta real: la app escribe en ella desde que pasaste la copia; todo se puede deshacer"
        case .real:
            "Solo lectura: estás viendo tu carpeta real sin tocar nada"
        case .demo:
            "Empresa de ejemplo: los datos son ficticios"
        }
    }

    var bannerSystemImage: String {
        switch clase {
        case .copia: "doc.on.doc"
        case .real: realTrasRelevo ? "folder" : "lock"
        case .demo: "graduationcap"
        }
    }

    /// Subtítulo del selector («Copia del 21/10», «Ver sin tocar»…).
    var claseDescripcion: String {
        switch clase {
        case .copia: "Copia del \(TLSFormat.fechaCorta(creada))"
        case .real: realTrasRelevo ? "Tu carpeta real" : "Ver sin tocar"
        case .demo: "Ejemplo"
        }
    }
}

extension VaultPath {
    /// Carpeta contenedora para mostrar bajo un título («2 · Ventas › Sistemas»).
    var carpetaVisible: String {
        guard let parent, !parent.isRoot else { return "Carpeta de tu empresa" }
        return parent.components.joined(separator: " › ")
    }
}
