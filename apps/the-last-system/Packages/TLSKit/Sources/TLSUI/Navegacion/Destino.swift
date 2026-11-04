import Foundation
import TLSCore
import TLSVisores

/// Un sitio al que se puede ir dentro de la ventana de una empresa (DISENO §2.1 y §7.2).
///
/// Las **raíces** son lo que se elige en la barra lateral, con ⌘1–9 o con ⌘K; los **niveles** se entran
/// desde una raíz (una ficha, una base filtrada por lo que vienes viendo, una nota, un fichero). Las
/// migas son `[raíz] + niveles`. Es `Codable` para restaurar cada pestaña al volver a abrir la app.
public enum Destino: Hashable, Codable, Sendable {
    case hoy
    case decisiones
    case tareas
    /// Conflictos, duplicados y lo recuperado al abrir: se llega desde Hoy.
    case revisar
    /// Un área, con su pestaña (Resumen · Operación · Control · Sistemas y activos). `nil` = la de por defecto.
    case area(AreaCode, pestana: String? = nil)
    case todasLasBases
    /// Una base (`id` de colección: «contactos», «facturas»…), con su vista guardada y, si se entra desde una
    /// ficha, el contexto («Facturas de Arquitectura Nexo»).
    case base(String, vista: String? = nil, contexto: VaultPath? = nil)
    /// Una ficha (contacto, proyecto, factura…) con la pestaña en la que estaba. `nil` = la que toca (§3.3).
    case ficha(VaultPath, pestana: String? = nil)
    /// Una nota sin molde de ficha (Markdown, texto o CSV), en el editor.
    case nota(VaultPath)
    /// Un fichero que se ve con un visor: PDF, imagen, audio, vídeo u otros (R1).
    case fichero(VaultPath)
    /// La carpeta de la empresa (`nil`) o una de sus carpetas.
    case carpeta(VaultPath? = nil)
    /// Resultados de buscar un texto en toda la carpeta.
    case busqueda(String)
    case asistentes
    /// F4 · La ficha de un asistente (`Asistentes/AsistenteFichaPantalla`), por su `slug` («contable»): `Asistentes ›
    /// Contable` en las migas.
    case asistente(String)
    case ajustes
    /// F2 · Una tarea con su detalle (`Tareas/TareaDetalle`). `Destino.para` (y `sesion.destino(para:)`) lleva aquí
    /// las fichas de tarea; «Abrir como ficha» del tablero del proyecto sigue entrando en `.ficha`.
    case tarea(VaultPath)
    /// F2 · Una decisión de la bandeja (`Pantallas/DecisionesPantalla`, `DecisionDetalle`). El texto lo decide quien
    /// la prepara; para las que son una nota, `Destino.decision(de: ruta)` («ruta:…»).
    case decision(String)
    /// F2 · Banco y conciliación de Finanzas (`Areas/Finanzas/BancoPantalla`). `nil` = todas las cuentas; si no, la
    /// carpeta de la cuenta (`4 · Finanzas/Registros/Bancos/<cuenta>`).
    case banco(VaultPath? = nil)

    /// La misma pantalla sin tener en cuenta la pestaña elegida dentro (para «sin bucles» y los recuerdos).
    public var identidad: String {
        switch self {
        case .hoy: "hoy"
        case .decisiones: "decisiones"
        case .tareas: "tareas"
        case .revisar: "revisar"
        case .area(let a, _): "area:\(a.rawValue)"
        case .todasLasBases: "bases"
        case .base(let id, let vista, let contexto): "base:\(id)|\(vista ?? "")|\(contexto?.raw ?? "")"
        case .ficha(let p, _): "ficha:\(p.raw)"
        case .nota(let p): "nota:\(p.raw)"
        case .fichero(let p): "fichero:\(p.raw)"
        case .carpeta(let p): "carpeta:\(p?.raw ?? "")"
        case .busqueda(let q): "busqueda:\(q)"
        case .asistentes: "asistentes"
        case .asistente(let s): "asistente:\(s)"
        case .ajustes: "ajustes"
        case .tarea(let p): "tarea:\(p.raw)"
        case .decision(let id): "decision:\(id)"
        case .banco(let p): "banco:\(p?.raw ?? "")"
        }
    }

    /// Pestaña elegida dentro de la pantalla (área o ficha).
    public var pestana: String? {
        switch self {
        case .area(_, let p), .ficha(_, let p): p
        default: nil
        }
    }

    /// El mismo destino con otra pestaña (en los que no tienen pestañas, el mismo).
    public func conPestana(_ pestana: String?) -> Destino {
        switch self {
        case .area(let a, _): .area(a, pestana: pestana)
        case .ficha(let p, _): .ficha(p, pestana: pestana)
        default: self
        }
    }

    /// Ruta de la carpeta a la que se refiere, si la hay.
    public var ruta: VaultPath? {
        switch self {
        case .ficha(let p, _), .nota(let p), .fichero(let p), .tarea(let p): p
        case .carpeta(let p): p
        case .base(_, _, let contexto): contexto
        case .banco(let p): p
        case .decision: rutaDeDecision
        default: nil
        }
    }

    /// El mismo destino con la ruta cambiada (al renombrar o mover algo que está en las migas o en el historial).
    public func moviendo(de origen: VaultPath, a destino: VaultPath) -> Destino {
        func m(_ p: VaultPath) -> VaultPath {
            if p == origen { return destino }
            if p.isDescendant(of: origen) {
                return VaultPath(components: destino.components + Array(p.components.dropFirst(origen.components.count)))
            }
            return p
        }
        switch self {
        case .ficha(let p, let t): return .ficha(m(p), pestana: t)
        case .nota(let p): return .nota(m(p))
        case .fichero(let p): return .fichero(m(p))
        case .carpeta(let p?): return .carpeta(m(p))
        case .base(let id, let v, let c?): return .base(id, vista: v, contexto: m(c))
        case .tarea(let p): return .tarea(m(p))
        case .banco(let p?): return .banco(m(p))
        case .decision:
            if let p = rutaDeDecision { return .decision(de: m(p)) }
            return self
        default: return self
        }
    }

    /// Puede ser raíz (lo que se elige en la barra lateral, ⌘1–9 o ⌘K).
    public var puedeSerRaiz: Bool {
        switch self {
        case .ficha, .nota, .fichero, .tarea, .decision, .asistente: false
        default: true
        }
    }

    /// SF Symbol del tipo de pantalla (para migas y pestañas de ventana) cuando no hay uno más concreto.
    public var simbolo: String {
        switch self {
        case .hoy: "sun.max"
        case .decisiones: "signpost.right.and.left"
        case .tareas: "checkmark.square"
        case .revisar: "exclamationmark.arrow.triangle.2.circlepath"
        case .area(let a, _): a.systemImage
        case .todasLasBases, .base: "tablecells"
        case .ficha: "doc.text"
        case .nota: "doc.text"
        case .fichero(let p): TipoFichero.de(extension: p.ext).simbolo
        case .carpeta: "folder"
        case .busqueda: "magnifyingglass"
        case .asistentes, .asistente: "sparkle"
        case .ajustes: "gearshape"
        case .tarea: "checkmark.square"
        case .decision: "signpost.right.and.left"
        case .banco: "building.columns"
        }
    }

    /// La decisión que es una nota (una pregunta de un asistente, un borrador por aprobar…).
    public static func decision(de ruta: VaultPath) -> Destino { .decision(prefijoRutaDecision + ruta.raw) }

    /// Ruta de la nota de una decisión hecha con `decision(de:)`.
    public var rutaDeDecision: VaultPath? {
        guard case .decision(let id) = self, id.hasPrefix(Self.prefijoRutaDecision) else { return nil }
        let raw = String(id.dropFirst(Self.prefijoRutaDecision.count))
        return raw.isEmpty ? nil : VaultPath(raw)
    }

    static let prefijoRutaDecision = "ruta:"

    /// A dónde lleva abrir una ruta de la carpeta: carpeta, ficha, nota o fichero, según su tipo.
    public static func para(_ ruta: VaultPath, tipo: NoteKind?, esCarpeta: Bool) -> Destino {
        if esCarpeta || ruta.isRoot { return .carpeta(ruta.isRoot ? nil : ruta) }
        // F2 (rol tareas, docs/F2-CONTRATOS.md §3): una tarea abre su detalle (`Tareas/TareaDetalle`).
        if tipo == .task { return .tarea(ruta) }
        if let tipo, tipo.abreComoFicha { return .ficha(ruta) }
        if TipoFichero.de(extension: ruta.ext).esVisor { return .fichero(ruta) }
        return .nota(ruta)
    }
}

/// Lo que una pantalla quiere encontrar igual al volver con Atrás o con su miga (criterio §11.1):
/// desplazamiento, filtros, selección y otros valores pequeños. Lo guarda `Navegacion` por pestaña de
/// ventana y se restaura al volver a abrir la app.
public struct RecuerdoPantalla: Hashable, Codable, Sendable {
    /// Desplazamiento vertical en puntos.
    public var desplazamiento: CGFloat?
    /// Identificador de la fila o el bloque que estaba arriba (más estable que los puntos).
    public var ancla: String?
    /// Filtros activos, como texto (la pantalla decide el formato): «estado» → «Activo».
    public var filtros: [String: String]
    /// Lo elegido (identificadores).
    public var seleccion: [String]
    /// Texto del buscador de la pantalla.
    public var busqueda: String?
    /// Cualquier otro valor pequeño (vista, agrupación, orden…).
    public var extra: [String: String]

    public init(desplazamiento: CGFloat? = nil, ancla: String? = nil, filtros: [String: String] = [:],
                seleccion: [String] = [], busqueda: String? = nil, extra: [String: String] = [:]) {
        self.desplazamiento = desplazamiento; self.ancla = ancla; self.filtros = filtros
        self.seleccion = seleccion; self.busqueda = busqueda; self.extra = extra
    }

    public var vacio: Bool { self == RecuerdoPantalla() }
}
