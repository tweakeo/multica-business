import Foundation
import TLSCore
import TLSDesign

// Módulos de inicio (DISENO-MOSAICO-V2 §6, maqueta M2-Hoy; SISTEMAS §4.2 «Resumen: módulos por defecto» y §5.9):
// rejilla de 4 columnas, tamaños Pequeño 1×1 · Mediano 2×1 · Grande 2×2 · Ancho 4×1, 8 a la vista como mucho. Se
// mueven, se ocultan (y se recuperan desde «Ocultos del inicio» o «Añadir») y cambian de tamaño. Cómo los tienes es
// tuyo y de tu Mac: se guarda por empresa en Application Support (`inicios.json` del estado), nunca en la carpeta.

/// Qué inicio: el de Hoy o el Resumen de un área.
public enum InicioID: Hashable, Sendable {
    case hoy
    case area(AreaCode)

    /// Clave en `inicios.json` («hoy», «area-ventas»).
    public var clave: String {
        switch self {
        case .hoy: "hoy"
        case .area(let a): "area-\(a.layoutKey)"
        }
    }
}

/// Los módulos que existen. Cada uno sabe de dónde sale su dato (`DatosModulos`); sin dato lo dice, nunca pone 0.
public enum ModuloID: String, CaseIterable, Sendable, Hashable, Codable {
    // Hoy (M2-Hoy)
    case caja, ritmo, semana, cabe, cobros, quietas, sesiones, sinConciliar, trimestre, publicadas, asistentes, embudo,
         pendientes
    // Resumen de cada área (SISTEMAS §4.2)
    case cuello, decisiones, rutina, objetivos, ganadas, diagnosticos, seguimientos, proyectosRiesgo, incidencias,
         cobrosVencidos, conversaciones, piezas, casos, rutinasSemana, usoTope, areasSinDueno
}

/// Ficha de un módulo en la galería «Añadir un módulo».
public struct DefinicionModulo: Sendable, Hashable, Identifiable {
    public var id: ModuloID { modulo }
    public let modulo: ModuloID
    public let titulo: String
    /// Área a la que pertenece (icono y categoría de la galería); `nil` = de todas.
    public let area: AreaCode?
    /// Una línea para la galería: qué enseña.
    public let descripcion: String
    /// Tamaños posibles, el primero es el de serie.
    public let tamanos: [TamanoMosaico]

    public var porDefecto: TamanoMosaico { tamanos[0] }
}

/// El catálogo de módulos y lo que sale de serie en cada inicio.
public enum CatalogoModulos {
    static let cifra: [TamanoMosaico] = [.pequeno, .mediano]

    public static func definicion(_ m: ModuloID) -> DefinicionModulo {
        switch m {
        case .caja: d(m, "Caja", .finanzas, "Saldo de tus cuentas y su gráfica", [.grande, .mediano, .ancho])
        case .ritmo: d(m, "Ritmo por área", .direccion, "Cómo va cada área frente a su meta", [.grande, .mediano, .ancho])
        case .semana: d(m, "Tu semana", .direccion, "Horas de cada día frente al tope", [.ancho, .grande])
        case .cabe: d(m, "Lo que cabe hoy", .direccion, "Lo tuyo de hoy, con su hora", [.mediano, .grande, .ancho])
        case .cobros: d(m, "Cobros por confirmar", .finanzas, "Lo que llegó al banco y falta confirmar", cifra)
        case .quietas: d(m, "Oportunidades quietas", .ventas, "Sin moverse 7 días o más", cifra)
        case .sesiones: d(m, "Próximas sesiones", .entrega, "Reuniones con fecha a partir de hoy", cifra)
        case .sinConciliar: d(m, "Movimientos sin conciliar", .finanzas, "Movimientos del banco sin su factura o gasto", cifra)
        case .trimestre: d(m, "Próximo trimestre", .finanzas, "Días que quedan para presentar", cifra)
        case .publicadas: d(m, "Publicadas", .marca, "Piezas publicadas en los últimos 30 días", cifra)
        case .asistentes: d(m, "Salud de los asistentes", .equipo, "Qué hace cada asistente", cifra)
        case .embudo: d(m, "Valor del embudo", .ventas, "Valor abierto y ponderado", cifra)
        case .pendientes: d(m, "Facturas por cobrar", .finanzas, "Emitidas y aún sin cobrar", cifra)
        case .cuello: d(m, "El cuello", .direccion, "El área que más frena al resto, en texto", [.mediano, .ancho])
        case .decisiones: d(m, "Decisiones pendientes", .direccion, "Lo que espera tu decisión", cifra)
        case .rutina: d(m, "Próxima rutina", .direccion, "La siguiente rutina con día", cifra)
        case .objetivos: d(m, "Objetivos en ritmo", .direccion, "Objetivos que llegan a tiempo", cifra)
        case .ganadas: d(m, "Conversión de propuestas", .ventas, "Ganadas sobre propuestas cerradas", cifra)
        case .diagnosticos: d(m, "Próximas reuniones de Ventas", .ventas, "Reuniones de Ventas a partir de hoy", cifra)
        case .seguimientos: d(m, "Seguimientos de hoy", .ventas, "Oportunidades que piden un mensaje", cifra)
        case .proyectosRiesgo: d(m, "Proyectos en riesgo", .entrega, "Fuera de fecha o que llegan justos", cifra)
        case .incidencias: d(m, "Incidencias", .entrega, "Incidencias abiertas con su cuenta atrás", cifra)
        case .cobrosVencidos: d(m, "Cobros vencidos", .finanzas, "Facturas vencidas sin cobrar", cifra)
        case .conversaciones: d(m, "Conversaciones cualificadas", .marca, "Conversaciones que encajan, este mes", cifra)
        case .piezas: d(m, "Próximas piezas", .marca, "Contenido en preparación", cifra)
        case .casos: d(m, "Casos pendientes de permiso", .marca, "Casos de éxito a la espera del cliente", cifra)
        case .rutinasSemana: d(m, "Rutinas de la semana", .equipo, "Las rutinas que tocan esta semana", cifra)
        case .usoTope: d(m, "Uso frente al tope", .equipo, "Lo que gastan los asistentes este mes", cifra)
        case .areasSinDueno: d(m, "Áreas sin dueño", .equipo, "Áreas sin una persona al frente", cifra)
        }
    }

    private static func d(_ m: ModuloID, _ t: String, _ a: AreaCode?, _ desc: String, _ tam: [TamanoMosaico]) -> DefinicionModulo {
        DefinicionModulo(modulo: m, titulo: t, area: a, descripcion: desc, tamanos: tam)
    }

    /// Módulos que tienen sentido en un inicio (la galería solo ofrece estos).
    public static func disponibles(en inicio: InicioID) -> [ModuloID] {
        switch inicio {
        case .hoy:
            [.caja, .ritmo, .semana, .cabe, .cobros, .quietas, .sesiones, .sinConciliar, .trimestre, .publicadas,
             .asistentes, .embudo, .pendientes, .decisiones, .cuello, .cobrosVencidos, .seguimientos, .proyectosRiesgo]
        case .area(let a):
            ModuloID.allCases.filter { definicion($0).area == a } + [.semana, .cabe, .decisiones].filter { definicion($0).area != a }
        }
    }

    /// Lo que sale de serie (M2-Hoy; SISTEMAS §4.2 para cada área).
    public static func deSerie(_ inicio: InicioID) -> DisposicionInicio {
        func c(_ m: ModuloID, _ t: TamanoMosaico? = nil) -> ModuloColocado { ModuloColocado(m, t ?? definicion(m).porDefecto) }
        switch inicio {
        case .hoy:
            return DisposicionInicio(visibles: [c(.caja), c(.ritmo), c(.semana), c(.cabe), c(.cobros), c(.quietas)])
        case .area(.direccion):
            return DisposicionInicio(visibles: [c(.cuello), c(.decisiones), c(.objetivos), c(.ritmo), c(.semana, .ancho), c(.rutina)])
        case .area(.ventas):
            return DisposicionInicio(visibles: [c(.quietas), c(.embudo), c(.ganadas), c(.diagnosticos), c(.seguimientos)])
        case .area(.entrega):
            return DisposicionInicio(visibles: [c(.proyectosRiesgo), c(.sesiones), c(.incidencias), c(.semana, .ancho)])
        case .area(.finanzas):
            return DisposicionInicio(visibles: [c(.caja), c(.cobrosVencidos), c(.sinConciliar), c(.trimestre), c(.pendientes)])
        case .area(.marca):
            return DisposicionInicio(visibles: [c(.publicadas), c(.conversaciones), c(.piezas), c(.casos)])
        case .area(.equipo):
            return DisposicionInicio(visibles: [c(.rutinasSemana), c(.asistentes), c(.usoTope), c(.areasSinDueno)])
        }
    }
}

/// Un módulo a la vista, con su tamaño.
public struct ModuloColocado: Sendable, Hashable, Codable, Identifiable {
    public var id: ModuloID { modulo }
    public var modulo: ModuloID
    public var tamano: TamanoMosaico

    public init(_ modulo: ModuloID, _ tamano: TamanoMosaico) { self.modulo = modulo; self.tamano = tamano }
}

/// Un módulo oculto: conserva su tamaño y el sitio al que vuelve con «Mostrar».
public struct ModuloOculto: Sendable, Hashable, Codable, Identifiable {
    public var id: ModuloID { modulo }
    public var modulo: ModuloID
    public var tamano: TamanoMosaico
    public var posicion: Int
}

/// Cómo está un inicio: los módulos a la vista (en orden) y los ocultos. Puro: lo prueban las pruebas.
public struct DisposicionInicio: Sendable, Hashable, Codable {
    /// Como mucho 8 a la vista (DISENO §6).
    public static let maximo = 8

    public private(set) var visibles: [ModuloColocado]
    public private(set) var ocultos: [ModuloOculto]

    public init(visibles: [ModuloColocado], ocultos: [ModuloOculto] = []) {
        var vistos = Set<ModuloID>()
        self.visibles = Array(visibles.filter { vistos.insert($0.modulo).inserted }.prefix(Self.maximo))
        self.ocultos = ocultos.filter { vistos.insert($0.modulo).inserted }
    }

    public var lleno: Bool { visibles.count >= Self.maximo }
    public func contiene(_ m: ModuloID) -> Bool { visibles.contains { $0.modulo == m } || ocultos.contains { $0.modulo == m } }
    public func indice(_ m: ModuloID) -> Int? { visibles.firstIndex { $0.modulo == m } }

    /// Los del catálogo de ese inicio que no están ni a la vista ni ocultos (los que ofrece la galería).
    public func paraAnadir(_ inicio: InicioID) -> [ModuloID] {
        CatalogoModulos.disponibles(en: inicio).filter { !contiene($0) }
    }

    /// Oculta un módulo (conserva su tamaño y su sitio).
    @discardableResult
    public mutating func ocultar(_ m: ModuloID) -> Bool {
        guard let i = indice(m) else { return false }
        let c = visibles.remove(at: i)
        ocultos.append(ModuloOculto(modulo: c.modulo, tamano: c.tamano, posicion: i))
        return true
    }

    /// Lo devuelve a su sitio. `false` si ya hay 8 a la vista.
    @discardableResult
    public mutating func mostrar(_ m: ModuloID) -> Bool {
        guard !lleno, let k = ocultos.firstIndex(where: { $0.modulo == m }) else { return false }
        let o = ocultos.remove(at: k)
        visibles.insert(ModuloColocado(o.modulo, o.tamano), at: min(max(0, o.posicion), visibles.count))
        return true
    }

    /// Añade un módulo nuevo al final con su tamaño de serie (o lo muestra si estaba oculto).
    @discardableResult
    public mutating func anadir(_ m: ModuloID) -> Bool {
        if ocultos.contains(where: { $0.modulo == m }) { return mostrar(m) }
        guard !lleno, indice(m) == nil else { return false }
        visibles.append(ModuloColocado(m, CatalogoModulos.definicion(m).porDefecto))
        return true
    }

    /// Lo mueve `desplazamiento` puestos (−1 = antes, +1 = después).
    @discardableResult
    public mutating func mover(_ m: ModuloID, _ desplazamiento: Int) -> Bool {
        guard let i = indice(m) else { return false }
        let j = i + desplazamiento
        guard j >= 0, j < visibles.count, j != i else { return false }
        let c = visibles.remove(at: i)
        visibles.insert(c, at: j)
        return true
    }

    /// Arrastrar y soltar: lo deja en el sitio de `destino` (delante si venía de detrás, detrás si venía de delante).
    @discardableResult
    public mutating func mover(_ m: ModuloID, aLaPosicionDe destino: ModuloID) -> Bool {
        guard m != destino, let i = indice(m), let j = indice(destino) else { return false }
        let c = visibles.remove(at: i)
        visibles.insert(c, at: j)
        return true
    }

    /// Pasa al tamaño siguiente de los que admite (Pequeño → Mediano → …). Devuelve el nuevo, o `nil` si solo tiene uno.
    @discardableResult
    public mutating func siguienteTamano(_ m: ModuloID) -> TamanoMosaico? {
        guard let i = indice(m) else { return nil }
        let t = CatalogoModulos.definicion(m).tamanos
        guard t.count > 1 else { return nil }
        let actual = t.firstIndex(of: visibles[i].tamano) ?? -1
        visibles[i].tamano = t[(actual + 1) % t.count]
        return visibles[i].tamano
    }

    /// Lo que se lee de disco con módulos o tamaños que ya no existen: se quitan y se corrigen.
    func saneada() -> DisposicionInicio {
        func tam(_ m: ModuloID, _ t: TamanoMosaico) -> TamanoMosaico {
            let ok = CatalogoModulos.definicion(m).tamanos
            return ok.contains(t) ? t : ok[0]
        }
        return DisposicionInicio(visibles: visibles.map { ModuloColocado($0.modulo, tam($0.modulo, $0.tamano)) },
                                 ocultos: ocultos.map { ModuloOculto(modulo: $0.modulo, tamano: tam($0.modulo, $0.tamano), posicion: $0.posicion) })
    }
}

extension TamanoMosaico {
    /// «Pequeño», «Mediano», «Grande», «Ancho».
    var nombre: String {
        switch self {
        case .pequeno: "Pequeño"
        case .mediano: "Mediano"
        case .grande: "Grande"
        case .ancho: "Ancho"
        }
    }
}
