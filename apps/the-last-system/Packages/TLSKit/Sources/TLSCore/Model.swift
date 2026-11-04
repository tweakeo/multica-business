import Foundation

// Contratos públicos de TLSCore para la fase F0 (solo lectura).
// La interfaz (TLSUI), la copia (TLSImport) y tls-tool programan contra estos tipos.
// Cambiar una firma pública exige actualizar docs/F0-CONTRATOS.md.

/// Las seis áreas de TLB. El número de carpeta es fijo; el nombre puede cambiar.
public enum AreaCode: String, CaseIterable, Sendable, Codable, Hashable {
    case direccion = "DIR", ventas = "VEN", entrega = "ENT", finanzas = "FIN", marca = "MAR", equipo = "EQU"

    public var numero: Int {
        switch self {
        case .direccion: 1
        case .ventas: 2
        case .entrega: 3
        case .finanzas: 4
        case .marca: 5
        case .equipo: 6
        }
    }

    public var nombre: String {
        switch self {
        case .direccion: "Dirección"
        case .ventas: "Ventas"
        case .entrega: "Entrega"
        case .finanzas: "Finanzas"
        case .marca: "Marca"
        case .equipo: "Equipo"
        }
    }

    /// Color de área en hexadecimal: el relleno en claro de Mosaico v2 (DISENO-MOSAICO-V2 §1.7: ciruela,
    /// verde, petróleo, ámbar, oliva y granate). La interfaz usa `TLSArea`, con sus variantes por modo.
    /// Solo como acento: el color nunca va solo.
    public var colorHex: String {
        switch self {
        case .direccion: "#791E74"
        case .ventas: "#178A5C"
        case .entrega: "#0F6681"
        case .finanzas: "#B87817"
        case .marca: "#6D7010"
        case .equipo: "#952C3C"
        }
    }

    /// Clave del preset en layout.json (`{direccion}`, `{ventas}`…).
    public var layoutKey: String {
        switch self {
        case .direccion: "direccion"
        case .ventas: "ventas"
        case .entrega: "entrega"
        case .finanzas: "finanzas"
        case .marca: "marca"
        case .equipo: "equipo"
        }
    }
}

/// Estado de un área, leído solo de su `Área.md` (`**Estado:** activa · …`).
public enum AreaStatus: String, Sendable, Codable, Hashable {
    case activa, preparada, reposo, desconocido

    /// Texto para la interfaz (el estado nunca se comunica solo con color).
    public var etiqueta: String {
        switch self {
        case .activa: "Activa"
        case .preparada: "Preparada"
        case .reposo: "En reposo"
        case .desconocido: "Sin estado"
        }
    }
}

/// Resumen de un área tal como lo escribe `N · Área/Área.md`.
public struct AreaSummary: Sendable, Hashable, Identifiable {
    public var id: AreaCode { code }
    public let code: AreaCode
    /// Carpeta del área (`2 · Ventas`).
    public let folder: VaultPath
    public let titulo: String
    public let estado: AreaStatus
    /// Texto literal tras `**Estado:**` (p. ej. «preparada, sin activar (se activa en enero)»).
    public let estadoTexto: String
    public let lleva: String?
    public let rol: String?
    /// Primer párrafo de `## Qué transforma`.
    public let transforma: String?
    /// Enlaces de `## Sistemas`, resueltos.
    public let sistemas: [SystemRef]
    /// `false` si no existe `Área.md`.
    public let tieneFicha: Bool

    public init(code: AreaCode, folder: VaultPath, titulo: String, estado: AreaStatus, estadoTexto: String,
                lleva: String?, rol: String?, transforma: String?, sistemas: [SystemRef], tieneFicha: Bool) {
        self.code = code; self.folder = folder; self.titulo = titulo; self.estado = estado
        self.estadoTexto = estadoTexto; self.lleva = lleva; self.rol = rol; self.transforma = transforma
        self.sistemas = sistemas; self.tieneFicha = tieneFicha
    }
}

public struct SystemRef: Sendable, Hashable {
    public let nombre: String
    public let path: VaultPath?
    public let resumen: String?
    public init(nombre: String, path: VaultPath?, resumen: String?) {
        self.nombre = nombre; self.path = path; self.resumen = resumen
    }
}

/// Valor de una propiedad del frontmatter. Las fechas se leen como texto, nunca como `Date`.
public enum PropertyValue: Sendable, Hashable {
    case text(String)
    case number(String)
    case bool(Bool)
    case list([String])
    /// Mapa u otra estructura: se muestra como YAML literal.
    case raw(String)
    case empty

    public var displayText: String {
        switch self {
        case .text(let s), .number(let s), .raw(let s): s
        case .bool(let b): b ? "Sí" : "No"
        case .list(let l): l.joined(separator: ", ")
        case .empty: ""
        }
    }
}

public struct Property: Sendable, Hashable, Identifiable {
    public var id: String { key }
    public let key: String
    public let value: PropertyValue
    public init(key: String, value: PropertyValue) { self.key = key; self.value = value }
}

/// Qué es una nota para la app (`tls_type` > `tipo` heredado > carpeta).
///
/// Un caso por cada `tls_type` de las plantillas de serie (47, `PLANTILLAS.md`; `fragment` no es una nota:
/// se inserta dentro de otra), más `note`, `csv` y `other`. El valor bruto es el `tls_type` tal cual se
/// escribe en la carpeta. Añadir un caso obliga a subir `VaultIndex.schemaVersion`.
public enum NoteKind: String, Sendable, Codable, Hashable, CaseIterable {
    case company, area, system, contact, organization, opportunity, service, offer, project, task,
         objective, routine, decision, role, content, conversation, meeting, asset, draft, account
    // Añadidos en F1 (hallazgo 9 de fidelidad): antes se leían como «Nota».
    case agreement, background, brand, capture, closure, collaboration, connection, diagnosis
    case editorialPlan = "editorial_plan"
    case importReport = "import_report"
    case incident, index, invoice, log, period, portal, procedure, proposal, quote, receipt, report
    case rootCause = "root_cause"
    case routineLog = "routine_log"
    case sessionSummary = "session_summary"
    case strategy, welcome
    case deliveryTemplate = "delivery_template"
    case note, csv, other

    /// Los 47 `tls_type` de las plantillas (todo menos `note`, `csv` y `other`).
    public static var tiposDePlantilla: [NoteKind] {
        allCases.filter { ![.note, .csv, .other].contains($0) }
    }
}

/// Ficha de una nota indexada (lo que listan la carpeta, ⌘O y la búsqueda).
public struct NoteSummary: Sendable, Hashable, Identifiable {
    public var id: VaultPath { path }
    public let path: VaultPath
    public let title: String
    public let kind: NoteKind
    public let area: AreaCode?
    /// Solo en iCloud, sin descargar: no se ha leído su contenido.
    public let dataless: Bool
    /// Ruta marcada como privada en la configuración. Visible para la persona; nunca para agentes.
    public let privado: Bool
    public let modified: Date?
    public init(path: VaultPath, title: String, kind: NoteKind, area: AreaCode?, dataless: Bool,
                privado: Bool, modified: Date?) {
        self.path = path; self.title = title; self.kind = kind; self.area = area
        self.dataless = dataless; self.privado = privado; self.modified = modified
    }
}

public struct SearchHit: Sendable, Hashable, Identifiable {
    public var id: VaultPath { note.path }
    public let note: NoteSummary
    /// Fragmento con la coincidencia; los términos encontrados van entre «‹» y «›».
    public let snippet: String
    public init(note: NoteSummary, snippet: String) { self.note = note; self.snippet = snippet }
}

/// Entrada del navegador de carpeta (lectura del disco, no del índice).
public struct FolderEntry: Sendable, Hashable, Identifiable {
    public var id: VaultPath { path }
    public let path: VaultPath
    public let isDirectory: Bool
    public let dataless: Bool
    public let privado: Bool
    public let size: Int64?
    public init(path: VaultPath, isDirectory: Bool, dataless: Bool, privado: Bool, size: Int64?) {
        self.path = path; self.isDirectory = isDirectory; self.dataless = dataless
        self.privado = privado; self.size = size
    }
}

/// Contenido de una nota abierta en el visor.
public enum NoteContent: Sendable {
    case markdown(text: String, properties: [Property], body: String, title: String, kind: NoteKind)
    case csv(header: [String], rows: [[String]], text: String)
    case plain(text: String)
    /// Solo en iCloud: la app pide la descarga al abrir y vuelve a intentarlo.
    case notDownloaded
    case binary(size: Int64?)
    case unreadable(message: String)
}

public struct IndexProgress: Sendable {
    public let processed: Int
    public let total: Int?
    public let currentPath: VaultPath?
    public init(processed: Int, total: Int?, currentPath: VaultPath?) {
        self.processed = processed; self.total = total; self.currentPath = currentPath
    }
}

public struct IndexStats: Sendable {
    public let notes: Int
    public let dataless: Int
    public let seconds: Double
    public init(notes: Int, dataless: Int, seconds: Double) {
        self.notes = notes; self.dataless = dataless; self.seconds = seconds
    }
}
