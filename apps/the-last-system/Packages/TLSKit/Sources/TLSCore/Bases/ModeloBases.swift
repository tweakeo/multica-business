import Foundation

// Bases (DISENO-MOSAICO-V2 §4): las colecciones de fichas que la app enseña en Tabla, Tablero, Lista,
// Galería, Calendario y Cronograma. Aquí solo hay datos y reglas, sin interfaz: lo usan `TLSUI/Bases`,
// `TLSUI/Busqueda` y las pruebas.

/// Cómo se ve una base (§4.4).
public enum TipoVista: String, Codable, CaseIterable, Sendable, Hashable {
    case tabla, tablero, lista, galeria, calendario, cronograma

    public var nombre: String {
        switch self {
        case .tabla: "Tabla"
        case .tablero: "Tablero"
        case .lista: "Lista"
        case .galeria: "Galería"
        case .calendario: "Calendario"
        case .cronograma: "Cronograma"
        }
    }

    public var simbolo: String {
        switch self {
        case .tabla: "tablecells"
        case .tablero: "rectangle.split.3x1"
        case .lista: "list.bullet"
        case .galeria: "square.grid.2x2"
        case .calendario: "calendar"
        case .cronograma: "chart.bar.xaxis"
        }
    }

    /// Lee el `vista:` de una nota índice («tabla», «galería», «Tablero»…).
    public init?(leyendo texto: String) {
        let t = TextFolding.fold(texto).trimmingCharacters(in: .whitespaces)
        switch t {
        case "tabla": self = .tabla
        case "tablero": self = .tablero
        case "lista": self = .lista
        case "galeria": self = .galeria
        case "calendario": self = .calendario
        case "cronograma": self = .cronograma
        default: return nil
        }
    }
}

/// Tipo de una columna, según el diccionario de propiedades (SISTEMAS §1.5). Decide cómo se pinta, cómo se
/// ordena y con qué control se edita en la celda (§4.7).
public enum TipoColumna: String, Codable, Sendable, Hashable {
    /// El nombre de la ficha: elige la fila (clic) y entra (doble clic o ↩).
    case titulo
    case texto
    /// Un valor de una lista cerrada (estado, etapa, tipo…), con su orden.
    case opcion
    /// Varios valores (relación con cliente, canales…).
    case opciones
    case fecha
    case dinero
    case porcentaje
    case numero
    /// Enlace a otra ficha (`empresa: "[[slug|Nombre]]"`).
    case relacion
    /// Persona o asistente (`responsable: lucia` o `agente:<slug>`).
    case persona
    case siNo
    /// Se calcula con otras fichas o propiedades: no se escribe.
    case calculada
}

/// Qué se calcula en una columna calculada (§2.2, principio 5: lo que se calcula no se escribe).
public enum Calculo: String, Codable, Sendable, Hashable {
    /// Oportunidad: valor × probabilidad.
    case ponderado
    /// Oportunidad: días desde que entró en su etapa (o desde que se creó).
    case diasEnEtapa
    /// Propuestas: «Propuesta», «Presupuesto» o «Contrato», según el tipo de ficha.
    case tipoDeFicha
    /// Contacto: fecha de la última reunión o conversación que lo enlaza.
    case ultimoContacto
    /// Empresa: proyectos sin cerrar que la enlazan.
    case proyectosActivos
    /// Empresa: facturas emitidas o enviadas menos lo cobrado.
    case pendienteDeCobro
    /// Servicio: clientes con una oportunidad Aceptada o Ganada de ese servicio.
    case clientesActivos
    /// Servicio: total de sus facturas de este año.
    case ingresosDelAno
    /// Factura: cobros confirmados en `pagos.csv` con su número.
    case cobradoFactura
    /// Proyecto: sesiones hechas sobre incluidas.
    case avanceProyecto
    /// Proyecto: lo cobrado de sus facturas.
    case cobradoProyecto
    /// Rol: sistemas que lo nombran.
    case sistemasDelRol
    /// Reunión: acciones sin hacer del acta.
    case accionesPendientes
    /// Sistema: pasos que no hace una persona.
    case pasosSinTi
    /// Objetivo: cifra del número clave y ritmo.
    case cifraObjetivo
    case ritmoObjetivo
}

/// Una columna de una base (§4.7): la propiedad que enseña, su tipo y cómo se edita.
public struct ColumnaBase: Hashable, Sendable, Identifiable {
    public var id: String { clave }
    /// Propiedad (o columna del CSV). Las especiales empiezan por `_` (`_titulo`, `_area`).
    public let clave: String
    public let etiqueta: String
    public let tipo: TipoColumna
    /// Otros nombres que se aceptan al leer (heredados o del CSV: `tercero` para Empresa).
    public let alias: [String]
    /// Valores de una opción, en el orden del diccionario.
    public let opciones: [String]
    /// Base a la que apunta una relación (`empresas`, `contactos`…).
    public let relacionCon: String?
    public let calculo: Calculo?
    /// De dónde sale lo calculado (se dice al pasar el puntero).
    public let explicacion: String?
    /// Ancho de partida en puntos.
    public let ancho: Double
    /// Va entre las columnas de serie (§4.2); si no, se puede añadir con «Columnas…».
    public let deSerie: Bool

    public init(_ clave: String, _ etiqueta: String, _ tipo: TipoColumna, alias: [String] = [], opciones: [String] = [],
                relacionCon: String? = nil, calculo: Calculo? = nil, explicacion: String? = nil, ancho: Double = 140,
                deSerie: Bool = true) {
        self.clave = clave; self.etiqueta = etiqueta; self.tipo = tipo; self.alias = alias; self.opciones = opciones
        self.relacionCon = relacionCon; self.calculo = calculo; self.explicacion = explicacion; self.ancho = ancho
        self.deSerie = deSerie
    }

    /// Claves que se miran al leer, en orden.
    public var claves: [String] { [clave] + alias }

    /// Alineada a la derecha (cifras).
    public var esCifra: Bool {
        switch tipo {
        case .dinero, .porcentaje, .numero: true
        case .calculada: [.ponderado, .pendienteDeCobro, .ingresosDelAno, .cobradoFactura, .cobradoProyecto,
                          .proyectosActivos, .clientesActivos, .sistemasDelRol, .diasEnEtapa].contains(calculo)
        default: false
        }
    }

    /// Clave del título de la fila.
    public static let claveTitulo = "_titulo"
    /// Clave del área de la ficha (sale de su carpeta).
    public static let claveArea = "_area"
}

/// Una pestaña de una base (§4.3): por el valor de una propiedad o por un criterio de trabajo (Tareas: «Lo
/// mío», «Hoy»…).
public struct PestanaBase: Hashable, Sendable, Identifiable {
    public let id: String
    public let titulo: String
    public let filtro: FiltroPestana
    /// Lo archivado o retirado: va la última y no sale en «Todas» (SISTEMAS §1.4).
    public let archivada: Bool

    public init(_ titulo: String, _ filtro: FiltroPestana, archivada: Bool = false, id: String? = nil) {
        self.id = id ?? titulo
        self.titulo = titulo
        self.filtro = filtro
        self.archivada = archivada
    }

    /// Id de la pestaña «Todas».
    public static let todas = "Todas"
}

/// Qué fichas enseña una pestaña.
public enum FiltroPestana: Hashable, Sendable {
    /// La propiedad vale alguno de estos valores (sin distinguir mayúsculas ni tildes).
    case valores(String, [String])
    /// La propiedad no vale ninguno de estos (Movimientos: «Sin conciliar»).
    case noValores(String, [String])
    /// El responsable es la persona que usa la app.
    case mio
    /// Esa fecha es hoy (o antes y sigue abierta).
    case hoy(String)
    /// Esa fecha cae en los próximos 7 días.
    case semana(String)
    /// Esa fecha ya pasó y la ficha sigue abierta.
    case vencidas(String)
}

/// De dónde salen las filas de una base.
public enum FuenteBase: Hashable, Sendable {
    /// Fichas con estos `tls_type`, estén en la carpeta que estén (sin plantillas ni `Archivo/`).
    case fichas([NoteKind])
    /// Filas de CSV: los ficheros con ese nombre bajo esa carpeta (`{finanzas}/Registros`), con su columna
    /// clave y, si se da, solo las filas cuya columna vale eso (`direccion` = `cobro`).
    case filasCSV(carpeta: String, nombre: String, clave: String, soloSi: [String: String])
}

/// Grupo de «Todas las bases» (§4.1): «Comunes» o un área.
public enum GrupoBase: Hashable, Sendable, Comparable {
    case comunes
    case area(AreaCode)

    public var titulo: String {
        switch self {
        case .comunes: "Comunes"
        case .area(let a): "\(a.numero) · \(a.nombre)"
        }
    }

    private var orden: Int {
        switch self {
        case .comunes: 0
        case .area(let a): a.numero
        }
    }

    public static func < (a: GrupoBase, b: GrupoBase) -> Bool { a.orden < b.orden }
}

/// Una colección de fichas (§4.2): qué guarda, dónde, cómo se ve por defecto y con qué plantilla se crea.
public struct ColeccionBase: Hashable, Sendable, Identifiable {
    /// Id estable (el de `BaseConocida.deSerie` y `Destino.base`).
    public let id: String
    public let nombre: String
    /// «oportunidad», «factura»: para «Nueva oportunidad», «1 factura».
    public let singular: String
    public let femenino: Bool
    public let icono: String
    public let area: AreaCode?
    public let fuentes: [FuenteBase]
    /// Carpeta donde viven (texto para el pie: «2 · Ventas/Oportunidades»), con `{ventas}`…
    public let hogar: String
    /// Ruta de la nota índice, si la tiene (`{ventas}/Contactos/Contactos.md`).
    public let notaIndice: String?
    /// Frase de serie si la nota índice no tiene (o no hay nota).
    public let frase: String
    public let vista: TipoVista
    /// Vistas que tienen sentido en esta base (siempre Tabla y Lista).
    public let vistas: [TipoVista]
    public let columnas: [ColumnaBase]
    /// Propiedad del tablero y de las pestañas (`estado`, `tipo`…).
    public let agruparPor: String?
    public let pestanas: [PestanaBase]
    /// Valores que cuentan como cerrados (no abiertos): Ganada, Hecha, Cobrada…
    public let cerrados: [String]
    /// Columnas plegadas al final del tablero (Perdida, Pausada).
    public let plegadas: [String]
    /// Fecha del calendario por defecto (`fecha`, `vence`, `siguiente_fecha`…).
    public let fechaCalendario: String?
    /// Inicio y fin del cronograma.
    public let cronograma: (inicio: String, fin: String)?
    /// Plantilla con la que se crea (`nil` = no se crea desde aquí).
    public let plantilla: String?
    /// Por qué no se crea desde aquí.
    public let motivoSinCrear: String?
    /// Solo pide el título al crear: fila de creación al final de la Tabla y la Lista (§4.8).
    public let creaConTitulo: Bool
    /// Módulo que la enciende (`objetivos`); `nil` = siempre encendida.
    public let modulo: String?
    /// Pestañas por los valores que haya de esta propiedad (Gastos: por categoría), si no hay `pestanas`.
    public let pestanasPor: String?
    /// El calendario abre en mes o en semana (Reuniones: semana, §4.2).
    public let escalaCalendario: EscalaCalendario

    public init(id: String, nombre: String, singular: String, femenino: Bool, icono: String, area: AreaCode?,
                fuentes: [FuenteBase], hogar: String, notaIndice: String?, frase: String, vista: TipoVista,
                vistas: [TipoVista], columnas: [ColumnaBase], agruparPor: String?, pestanas: [PestanaBase],
                cerrados: [String], plegadas: [String] = [], fechaCalendario: String?,
                cronograma: (inicio: String, fin: String)? = nil, plantilla: String?, motivoSinCrear: String? = nil,
                creaConTitulo: Bool = false, modulo: String? = nil, pestanasPor: String? = nil,
                escalaCalendario: EscalaCalendario = .mes) {
        self.id = id; self.nombre = nombre; self.singular = singular; self.femenino = femenino; self.icono = icono
        self.area = area; self.fuentes = fuentes; self.hogar = hogar; self.notaIndice = notaIndice; self.frase = frase
        self.vista = vista; self.vistas = vistas; self.columnas = columnas; self.agruparPor = agruparPor
        self.pestanas = pestanas; self.cerrados = cerrados; self.plegadas = plegadas
        self.fechaCalendario = fechaCalendario; self.cronograma = cronograma; self.plantilla = plantilla
        self.motivoSinCrear = motivoSinCrear; self.creaConTitulo = creaConTitulo; self.modulo = modulo
        self.pestanasPor = pestanasPor; self.escalaCalendario = escalaCalendario
    }

    public static func == (a: ColeccionBase, b: ColeccionBase) -> Bool { a.id == b.id }
    public func hash(into h: inout Hasher) { h.combine(id) }

    public var grupo: GrupoBase { area.map(GrupoBase.area) ?? .comunes }

    /// Tipos de ficha que guarda.
    public var tipos: [NoteKind] {
        fuentes.flatMap { f -> [NoteKind] in
            if case .fichas(let t) = f { return t }
            return []
        }
    }

    /// «Nueva oportunidad», «Nuevo contacto».
    public var textoNueva: String { (femenino ? "Nueva " : "Nuevo ") + singular }

    /// «Nueva…» o «Nuevo…» para menús.
    public var textoNuevaCorto: String { femenino ? "Nueva…" : "Nuevo…" }

    public func columna(_ clave: String) -> ColumnaBase? { columnas.first { $0.clave == clave } }

    /// Columnas de serie, en su orden.
    public var columnasDeSerie: [String] { columnas.filter(\.deSerie).map(\.clave) }

    /// La columna de la propiedad de estado (la de agrupar o, si no, `estado`).
    public var columnaEstado: ColumnaBase? {
        if let a = agruparPor, let c = columna(a), c.tipo == .opcion { return c }
        return columna("estado")
    }

    /// La primera columna de dinero (para las sumas del tablero y de los grupos).
    public var columnaDinero: ColumnaBase? { columnas.first { $0.tipo == .dinero } }

    public var tieneCSV: Bool {
        fuentes.contains { if case .filasCSV = $0 { return true }; return false }
    }
}
