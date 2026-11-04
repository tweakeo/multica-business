import Foundation

/// Condición de un filtro (§4.5): «es», «no es», «contiene», «antes de», «después de», «está vacía»,
/// «enlaza con» y, en lo calculado, «pide atención».
public enum CondicionFiltro: String, Codable, CaseIterable, Sendable, Hashable {
    case es, noEs, contiene, antesDe, despuesDe, estaVacia, noEstaVacia, enlazaCon, pideAtencion

    public var texto: String {
        switch self {
        case .es: "es"
        case .noEs: "no es"
        case .contiene: "contiene"
        case .antesDe: "antes de"
        case .despuesDe: "después de"
        case .estaVacia: "está vacía"
        case .noEstaVacia: "no está vacía"
        case .enlazaCon: "enlaza con"
        case .pideAtencion: "pide atención"
        }
    }

    /// No necesita valor.
    public var sinValor: Bool { [.estaVacia, .noEstaVacia, .pideAtencion].contains(self) }

    /// Condiciones que tienen sentido en una columna.
    public static func para(_ col: ColumnaBase) -> [CondicionFiltro] {
        switch col.tipo {
        case .fecha: [.antesDe, .despuesDe, .es, .estaVacia, .noEstaVacia]
        case .dinero, .porcentaje, .numero: [.es, .noEs, .estaVacia, .noEstaVacia]
        case .relacion: [.enlazaCon, .contiene, .estaVacia, .noEstaVacia]
        case .calculada: [.contiene, .pideAtencion]
        case .opcion, .opciones, .persona, .siNo: [.es, .noEs, .estaVacia, .noEstaVacia]
        case .titulo, .texto: [.contiene, .es, .noEs, .estaVacia, .noEstaVacia]
        }
    }
}

/// Un filtro de una base: propiedad, condición y valores («alguna de» si hay varios).
public struct FiltroBase: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(clave)|\(condicion.rawValue)|\(valores.joined(separator: "|"))" }
    public var clave: String
    public var condicion: CondicionFiltro
    /// Valores (vale cualquiera de ellos). En fechas, `hoy` es el día de hoy.
    public var valores: [String]

    public init(_ clave: String, _ condicion: CondicionFiltro, _ valores: [String] = []) {
        self.clave = clave; self.condicion = condicion; self.valores = valores
    }

    public static let hoy = "hoy"
    /// Último día del mes en curso («Por cerrar este mes»).
    public static let finDeMes = "fin de mes"

    /// «Estado es Activo», «Responsable es Lucía o Manu», «Vence antes de hoy».
    public func etiqueta(en c: ColeccionBase) -> String {
        let nombre = c.columna(clave)?.etiqueta ?? clave
        if condicion.sinValor { return "\(nombre) \(condicion.texto)" }
        let col = c.columna(clave)
        let vs = valores.map { v -> String in
            if col?.tipo == .persona { return FormatoBase.persona(v) }
            if col?.tipo == .opcion || col?.tipo == .opciones { return FormatoBase.opcionVisible(v) }
            return v
        }
        return "\(nombre) \(condicion.texto) \(vs.joined(separator: " o "))"
    }
}

/// Orden de una base: una columna (o `_urgente`, «lo urgente primero») y su sentido.
public struct OrdenBase: Codable, Hashable, Sendable {
    public var clave: String
    public var ascendente: Bool

    public init(_ clave: String, ascendente: Bool = true) { self.clave = clave; self.ascendente = ascendente }

    /// Pide tu decisión → vencido → hoy o quieto → falta un dato → por fecha (§2.2).
    public static let urgente = OrdenBase("_urgente")
}

/// Densidad de la tabla (§1.10): 32 pt o 28 pt por fila.
public enum DensidadTabla: String, Codable, Sendable, Hashable { case normal, compacta }

/// Tamaño de las tarjetas de la galería (§4.4).
public enum TamanoGaleria: String, Codable, Sendable, Hashable, CaseIterable {
    case s, m, l
    public var nombre: String {
        switch self {
        case .s: "Pequeñas"
        case .m: "Medianas"
        case .l: "Grandes"
        }
    }
    public var ancho: Double {
        switch self {
        case .s: 180
        case .m: 220
        case .l: 280
        }
    }
}

/// Escala del calendario (§4.4): el mes entero o una semana con sus horas.
public enum EscalaCalendario: String, Codable, Sendable, Hashable, CaseIterable {
    case mes, semana
    public var nombre: String { self == .mes ? "Mes" : "Semana" }
}

/// Cómo se está viendo una base (§4.6): lo que recoge «Guardar vista».
public struct ConfigVista: Codable, Hashable, Sendable {
    public var vista: TipoVista
    /// Pestaña por estado o tipo (`nil` = Todas).
    public var pestana: String?
    public var filtros: [FiltroBase]
    /// Propiedad por la que se agrupa (`nil` = sin agrupar). En el tablero, la de sus columnas.
    public var agrupar: String?
    public var orden: [OrdenBase]
    /// Columnas visibles, en su orden.
    public var columnas: [String]
    /// Anchos por columna.
    public var anchos: [String: Double]
    /// Orden y anchos que guarda la tabla del sistema (`TableColumnCustomization` codificada).
    public var personalizacionTabla: Data?
    /// Propiedad de fecha del calendario.
    public var fechaCalendario: String?
    public var tamanoGaleria: TamanoGaleria
    public var densidad: DensidadTabla
    /// Grupos plegados (en la tabla, la lista y el tablero).
    public var plegados: [String]
    /// Mes o semana en el calendario (`nil` = la de serie de la base). Opcional: las vistas guardadas antes
    /// se siguen leyendo.
    public var escalaCalendario: EscalaCalendario?

    public init(vista: TipoVista, pestana: String? = nil, filtros: [FiltroBase] = [], agrupar: String? = nil,
                orden: [OrdenBase] = [.urgente], columnas: [String], anchos: [String: Double] = [:],
                personalizacionTabla: Data? = nil, fechaCalendario: String? = nil, tamanoGaleria: TamanoGaleria = .m,
                densidad: DensidadTabla = .normal, plegados: [String] = [], escalaCalendario: EscalaCalendario? = nil) {
        self.vista = vista; self.pestana = pestana; self.filtros = filtros; self.agrupar = agrupar; self.orden = orden
        self.columnas = columnas; self.anchos = anchos; self.personalizacionTabla = personalizacionTabla
        self.fechaCalendario = fechaCalendario; self.tamanoGaleria = tamanoGaleria; self.densidad = densidad
        self.plegados = plegados; self.escalaCalendario = escalaCalendario
    }

    /// La de serie de una base: la vista que dice su nota índice, sus columnas de serie y lo urgente primero.
    /// En el tablero, las columnas plegadas de serie (Perdida, Pausada).
    public static func deSerie(_ datos: DatosBase) -> ConfigVista {
        let c = datos.coleccion
        let vista = datos.vistaPorDefecto
        let agrupar = vista == .tablero ? (datos.agruparPor ?? c.agruparPor)
            : (vista == .lista ? datos.indice?.agruparPor ?? (c.vista == .lista ? c.agruparPor : nil) : datos.indice?.agruparPor)
        return ConfigVista(vista: vista, agrupar: agrupar, columnas: c.columnasDeSerie, fechaCalendario: c.fechaCalendario,
                           plegados: c.plegadas, escalaCalendario: c.escalaCalendario)
    }

    /// La escala que se usa: la elegida o la de serie de la base.
    public func escala(en c: ColeccionBase) -> EscalaCalendario { escalaCalendario ?? c.escalaCalendario }
}

/// Una vista guardada: nombre y configuración. Sale como pestaña en la base (§4.6).
public struct VistaGuardada: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var nombre: String
    public var config: ConfigVista

    public init(id: String = UUID().uuidString, nombre: String, config: ConfigVista) {
        self.id = id; self.nombre = nombre; self.config = config
    }
}

public extension CatalogoBases {
    /// Vistas de serie de una base (viven en la app: no se quitan ni se sobrescriben; «Guardar como…» hace una
    /// tuya). Oportunidades trae las de la maqueta: Abiertas · Por cerrar este mes · Ganadas.
    static func vistasDeSerie(_ c: ColeccionBase) -> [VistaGuardada] {
        switch c.id {
        case "oportunidades":
            let cols = c.columnasDeSerie
            return [
                VistaGuardada(id: "serie:abiertas", nombre: "Abiertas",
                              config: ConfigVista(vista: .tabla, filtros: [FiltroBase("estado", .es, etapasAbiertas)],
                                                  agrupar: "estado", columnas: cols, fechaCalendario: c.fechaCalendario)),
                VistaGuardada(id: "serie:por-cerrar", nombre: "Por cerrar este mes",
                              config: ConfigVista(vista: .tablero,
                                                  filtros: [FiltroBase("estado", .es, ["Propuesta", "Aceptada"]),
                                                            FiltroBase("siguiente_fecha", .antesDe, [FiltroBase.finDeMes])],
                                                  agrupar: "estado", orden: [OrdenBase("siguiente_fecha")], columnas: cols,
                                                  fechaCalendario: c.fechaCalendario, plegados: c.plegadas)),
                VistaGuardada(id: "serie:ganadas", nombre: "Ganadas",
                              config: ConfigVista(vista: .lista, filtros: [FiltroBase("estado", .es, ["Ganada"])],
                                                  orden: [OrdenBase("valor", ascendente: false)], columnas: cols,
                                                  fechaCalendario: c.fechaCalendario)),
            ]
        default:
            return []
        }
    }
}

public extension VistaGuardada {
    /// Viene con la app (no se quita ni se sobrescribe).
    var esDeSerie: Bool { id.hasPrefix("serie:") }
}
