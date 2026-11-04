import Foundation
import Observation
import OSLog
import TLSCore
import SwiftUI
import TLSDesign
import UniformTypeIdentifiers

/// Secciones con rótulo de la barra lateral.
public enum SeccionBarra: String, Codable, Sendable, Hashable {
    case areas, bases

    public var titulo: String {
        switch self {
        case .areas: "Áreas"
        case .bases: "Bases"
        }
    }
}

/// Un elemento de la barra lateral (DISENO §6 y la maqueta M2-Hoy).
public enum ElementoBarra: Hashable, Codable, Sendable {
    case hoy, decisiones, tareas, asistentes, carpeta, ajustes, todasLasBases
    case area(AreaCode)
    /// Una base fijada (`id` de colección).
    case base(String)
    case seccion(SeccionBarra)

    public var id: String {
        switch self {
        case .hoy: "hoy"
        case .decisiones: "decisiones"
        case .tareas: "tareas"
        case .asistentes: "asistentes"
        case .carpeta: "carpeta"
        case .ajustes: "ajustes"
        case .todasLasBases: "todasLasBases"
        case .area(let a): "area.\(a.rawValue)"
        case .base(let b): "base.\(b)"
        case .seccion(let s): "seccion.\(s.rawValue)"
        }
    }

    public var esSeccion: Bool { if case .seccion = self { return true }; return false }

    /// Hoy siempre se ve; los rótulos de sección no se ocultan ni se mueven.
    public var sePuedeOcultar: Bool { self != .hoy && !esSeccion }

    /// A dónde lleva (`nil` en los rótulos).
    public var destino: Destino? {
        switch self {
        case .hoy: .hoy
        case .decisiones: .decisiones
        case .tareas: .tareas
        case .asistentes: .asistentes
        case .carpeta: .carpeta(nil)
        case .ajustes: .ajustes
        case .todasLasBases: .todasLasBases
        case .area(let a): .area(a)
        case .base(let b): .base(b)
        case .seccion: nil
        }
    }

    /// El elemento que corresponde a una raíz (para marcarlo como elegido).
    public static func para(_ destino: Destino) -> ElementoBarra? {
        switch destino {
        case .hoy: .hoy
        case .decisiones: .decisiones
        case .tareas: .tareas
        case .asistentes: .asistentes
        case .carpeta(nil): .carpeta
        case .ajustes: .ajustes
        case .todasLasBases: .todasLasBases
        case .area(let a, _): .area(a)
        case .base(let b, nil, nil): .base(b)
        default: nil
        }
    }
}

/// Lo que la barra sabe de una base para pintarla (nombre, icono y área). El catálogo completo, con sus
/// consultas, es del rol de bases (`TLSCore/Bases`); aquí basta lo visible.
public struct BaseConocida: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let nombre: String
    public let icono: String
    public let area: AreaCode?

    public init(id: String, nombre: String, icono: String, area: AreaCode?) {
        self.id = id; self.nombre = nombre; self.icono = icono; self.area = area
    }

    /// Las 24 bases de §4.2 (los `id` son el contrato con el rol de bases).
    public static let deSerie: [BaseConocida] = [
        .init(id: "contactos", nombre: "Contactos", icono: "person.crop.circle", area: .ventas),
        .init(id: "empresas", nombre: "Empresas", icono: "building.2", area: .ventas),
        .init(id: "oportunidades", nombre: "Oportunidades", icono: "target", area: .ventas),
        .init(id: "servicios", nombre: "Servicios", icono: "tag", area: .ventas),
        .init(id: "propuestas", nombre: "Propuestas", icono: "doc.text", area: .ventas),
        .init(id: "reuniones", nombre: "Reuniones", icono: "calendar.badge.clock", area: .ventas),
        .init(id: "proyectos", nombre: "Proyectos", icono: "square.stack.3d.up", area: .entrega),
        .init(id: "planes-de-entrega", nombre: "Planes de entrega", icono: "list.bullet.rectangle", area: .entrega),
        .init(id: "incidencias", nombre: "Incidencias", icono: "exclamationmark.bubble", area: .entrega),
        .init(id: "tareas", nombre: "Tareas", icono: "checkmark.square", area: nil),
        .init(id: "facturas", nombre: "Facturas", icono: "eurosign.circle", area: .finanzas),
        .init(id: "cobros", nombre: "Cobros", icono: "checkmark.seal", area: .finanzas),
        .init(id: "gastos", nombre: "Gastos", icono: "cart", area: .finanzas),
        .init(id: "movimientos", nombre: "Movimientos", icono: "arrow.left.arrow.right", area: .finanzas),
        .init(id: "contenidos", nombre: "Contenidos", icono: "square.and.pencil", area: .marca),
        .init(id: "conversaciones", nombre: "Conversaciones", icono: "bubble.left.and.bubble.right", area: .marca),
        .init(id: "sistemas", nombre: "Sistemas", icono: "gearshape.2", area: nil),
        .init(id: "activos", nombre: "Activos", icono: "cube", area: nil),
        .init(id: "roles", nombre: "Roles", icono: "person.text.rectangle", area: .equipo),
        .init(id: "decisiones", nombre: "Decisiones", icono: "signpost.right.and.left", area: .direccion),
        .init(id: "objetivos", nombre: "Objetivos", icono: "scope", area: .direccion),
        .init(id: "rutinas", nombre: "Rutinas", icono: "arrow.triangle.2.circlepath", area: .direccion),
        .init(id: "colaboraciones", nombre: "Colaboraciones", icono: "person.2", area: .equipo),
        .init(id: "borradores", nombre: "Borradores", icono: "envelope", area: nil),
    ]

    /// Las 6 que vienen fijadas (§4.1).
    public static let fijadasDeSerie = ["contactos", "empresas", "oportunidades", "proyectos", "reuniones", "facturas"]
}

/// Una fila de la barra: el elemento y si va metido dentro del anterior (sangría de 20 pt).
public struct FilaBarra: Hashable, Codable, Sendable {
    public var elemento: ElementoBarra
    public var dentro: Bool
    public init(_ elemento: ElementoBarra, dentro: Bool = false) { self.elemento = elemento; self.dentro = dentro }
}

/// Un elemento oculto, con el sitio del que salió (para volver a ponerlo ahí con «Mostrar»).
public struct OcultoBarra: Hashable, Codable, Sendable {
    public var elemento: ElementoBarra
    public var previo: ElementoBarra?
    public var dentro: Bool
}

/// Dato que acompaña a una fila: a la derecha («8», «7 abiertas», «⇧⌘B»), debajo («activa»), un aviso de
/// Atención («2 quietas») o la insignia magenta (Decisiones 3). Lo rellenan la sesión y las pantallas.
public struct DatoFilaBarra: Hashable, Sendable {
    public var derecha: String?
    public var derechaEsAtajo: Bool
    public var debajo: String?
    public var atencion: String?
    public var insignia: Int?
    public var palabraInsignia: String
    public var atenuado: Bool

    public init(derecha: String? = nil, derechaEsAtajo: Bool = false, debajo: String? = nil, atencion: String? = nil,
                insignia: Int? = nil, palabraInsignia: String = "esperan tu decisión", atenuado: Bool = false) {
        self.derecha = derecha; self.derechaEsAtajo = derechaEsAtajo; self.debajo = debajo; self.atencion = atencion
        self.insignia = insignia; self.palabraInsignia = palabraInsignia; self.atenuado = atenuado
    }
}

/// La barra lateral de una empresa: orden, sangrías, ocultos y bases fijadas (§6, §10.3).
///
/// Se personaliza como los complementos de Obsidian pero con gesto de app: mantener pulsado y arrastrar
/// para ordenar, arrastrar fuera para ocultar (bandeja «Ocultos»), ⌥⌘→/⌥⌘← para meter y sacar,
/// ⌥⌘↑/⌥⌘↓ para mover, y el mismo menú en el clic derecho. Cada cambio se puede deshacer y se guarda
/// por empresa en `Application Support` (`barra-lateral.json` del estado), nunca en la carpeta.
@Observable @MainActor
public final class BarraLateralModelo {
    public private(set) var filas: [FilaBarra]
    public private(set) var ocultos: [OcultoBarra]
    /// Modo edición (tiemblan, «−», asa y «Listo»).
    public var editando = false
    /// Datos a la derecha o debajo de cada fila.
    public var datos: [ElementoBarra: DatoFilaBarra] = [:]
    /// Aviso con «Deshacer» de la propia barra («Ocultaste 6 · Equipo»).
    public var aviso: Aviso?
    public private(set) var bases: [String: BaseConocida]

    @ObservationIgnored let archivo: URL?
    private static let log = Logger(subsystem: "es.thelast.system", category: "BarraLateral")

    struct Guardado: Codable {
        var version = 1
        var filas: [FilaBarra]
        var ocultos: [OcultoBarra]
        var bases: [BaseConocida]
    }

    /// `archivo` = dónde se guarda (`nil` en pruebas: solo en memoria).
    public init(archivo: URL?) {
        self.archivo = archivo
        self.bases = Dictionary(uniqueKeysWithValues: BaseConocida.deSerie.map { ($0.id, $0) })
        self.filas = Self.filasDeSerie
        self.ocultos = []
        if let archivo, let data = try? Data(contentsOf: archivo),
           let g = try? JSONDecoder().decode(Guardado.self, from: data) {
            filas = Self.normalizar(g.filas)
            ocultos = g.ocultos
            for b in g.bases { bases[b.id] = b }
        }
    }

    public static var filasDeSerie: [FilaBarra] {
        var f: [FilaBarra] = [.init(.hoy), .init(.decisiones), .init(.tareas), .init(.seccion(.areas))]
        f += AreaCode.allCases.map { FilaBarra(.area($0)) }
        f.append(.init(.seccion(.bases)))
        f += BaseConocida.fijadasDeSerie.map { FilaBarra(.base($0)) }
        f += [.init(.todasLasBases), .init(.asistentes), .init(.carpeta), .init(.ajustes)]
        return f
    }

    // MARK: Lectura

    public func indice(de e: ElementoBarra) -> Int? { filas.firstIndex { $0.elemento == e } }
    public func estaOculto(_ e: ElementoBarra) -> Bool { ocultos.contains { $0.elemento == e } }
    public func base(_ id: String) -> BaseConocida? { bases[id] }

    /// Se puede meter dentro del anterior: no es el primero de su sección ni ya está dentro.
    public func sePuedeMeter(_ e: ElementoBarra) -> Bool {
        guard let i = indice(de: e), i > 0, !filas[i].dentro, !e.esSeccion else { return false }
        return !filas[i - 1].elemento.esSeccion
    }

    public func estaDentro(_ e: ElementoBarra) -> Bool { indice(de: e).map { filas[$0].dentro } ?? false }

    /// El elemento del que cuelga uno metido dentro (para la guía vertical en su color).
    public func padre(de e: ElementoBarra) -> ElementoBarra? {
        guard let i = indice(de: e), filas[i].dentro else { return nil }
        return filas[..<i].last { !$0.dentro }?.elemento
    }

    // MARK: Cambios (todos se pueden deshacer)

    /// Mueve un elemento a la posición `destino` (índice en `filas` antes de quitarlo). Lo usa el arrastre.
    public func mover(_ e: ElementoBarra, antesDe objetivo: ElementoBarra?, dentro: Bool = false, deshacer: UndoManager? = nil) {
        guard !e.esSeccion, e != objetivo else { return }
        cambiar("Mover \(nombre(e))", deshacer: deshacer) {
            guard let i = indice(de: e) else { return }
            let fila = FilaBarra(e, dentro: dentro)
            filas.remove(at: i)
            let j = objetivo.flatMap { o in filas.firstIndex { $0.elemento == o } } ?? filas.count
            filas.insert(fila, at: j)
        }
    }

    /// ⌥⌘↑ y ⌥⌘↓.
    public func desplazar(_ e: ElementoBarra, _ paso: Int, deshacer: UndoManager? = nil) {
        guard !e.esSeccion, let i = indice(de: e) else { return }
        let j = i + paso
        guard j >= 0, j < filas.count else { return }
        cambiar(paso < 0 ? "Subir \(nombre(e))" : "Bajar \(nombre(e))", deshacer: deshacer) {
            filas.swapAt(i, j)
        }
    }

    /// ⌥⌘→ (meter dentro del anterior) y ⌥⌘← (sacar del grupo).
    public func meterDentro(_ e: ElementoBarra, _ dentro: Bool, deshacer: UndoManager? = nil) {
        guard let i = indice(de: e), filas[i].dentro != dentro, !dentro || sePuedeMeter(e) else { return }
        cambiar(dentro ? "Meter \(nombre(e))" : "Sacar \(nombre(e))", deshacer: deshacer) {
            filas[i].dentro = dentro
        }
    }

    /// Ocultar (arrastrar fuera, «−», menú). Hoy no se oculta.
    public func ocultar(_ e: ElementoBarra, deshacer: UndoManager? = nil) {
        guard e.sePuedeOcultar, let i = indice(de: e) else { return }
        let antes = foto
        cambiar("Ocultar \(nombre(e))", deshacer: deshacer) {
            let previo = i > 0 ? filas[i - 1].elemento : nil
            ocultos.append(OcultoBarra(elemento: e, previo: previo, dentro: filas[i].dentro))
            filas.remove(at: i)
        }
        aviso = Aviso("Ocultaste \(nombre(e))") { [weak self] in self?.restaurar(antes) }
    }

    /// «Mostrar» desde la bandeja (vuelve a su sitio) o soltando en la barra (`antesDe`).
    public func mostrar(_ e: ElementoBarra, antesDe objetivo: ElementoBarra? = nil, deshacer: UndoManager? = nil) {
        guard let k = ocultos.firstIndex(where: { $0.elemento == e }) else { return }
        cambiar("Mostrar \(nombre(e))", deshacer: deshacer) {
            let o = ocultos.remove(at: k)
            if let objetivo, let j = indice(de: objetivo) {
                filas.insert(FilaBarra(e), at: j)
            } else if let previo = o.previo, let j = indice(de: previo) {
                filas.insert(FilaBarra(e, dentro: o.dentro), at: j + 1)
            } else {
                filas.append(FilaBarra(e))
            }
        }
    }

    /// «Mostrar en la barra lateral» desde una miga raíz: si está oculto, vuelve; si es una base sin
    /// fijar, se fija.
    public func mostrarEnBarra(_ destino: Destino, deshacer: UndoManager? = nil) {
        guard let e = ElementoBarra.para(destino) else { return }
        if estaOculto(e) { mostrar(e, deshacer: deshacer); return }
        if case .base(let id) = e, indice(de: e) == nil { fijarBase(id, deshacer: deshacer) }
    }

    /// «Restaurar barra original».
    public func restaurarOriginal(deshacer: UndoManager? = nil) {
        cambiar("Restaurar la barra lateral", deshacer: deshacer) {
            filas = Self.filasDeSerie
            ocultos = []
        }
    }

    // MARK: Bases fijadas (API para el rol de bases)

    /// Describe una base que no está en el catálogo de serie (o cambia cómo se ve).
    public func describirBase(_ base: BaseConocida) {
        bases[base.id] = base
        guardar()
    }

    public func estaFijada(_ id: String) -> Bool { indice(de: .base(id)) != nil }

    /// Fija una base al final de la sección Bases (antes de «Todas las bases»).
    public func fijarBase(_ id: String, deshacer: UndoManager? = nil) {
        let e = ElementoBarra.base(id)
        guard indice(de: e) == nil else { return }
        if estaOculto(e) { mostrar(e, deshacer: deshacer); return }
        cambiar("Fijar \(nombre(e))", deshacer: deshacer) {
            let j = indice(de: .todasLasBases) ?? filas.count
            filas.insert(FilaBarra(e), at: j)
        }
    }

    /// Quita una base de la barra (no se oculta: deja de estar fijada).
    public func desfijarBase(_ id: String, deshacer: UndoManager? = nil) {
        let e = ElementoBarra.base(id)
        cambiar("Desfijar \(nombre(e))", deshacer: deshacer) {
            filas.removeAll { $0.elemento == e }
            ocultos.removeAll { $0.elemento == e }
        }
    }

    // MARK: Nombres

    public func nombre(_ e: ElementoBarra) -> String {
        switch e {
        case .hoy: "Hoy"
        case .decisiones: "Decisiones"
        case .tareas: "Tareas"
        case .asistentes: "Asistentes"
        case .carpeta: "Carpeta"
        case .ajustes: "Ajustes"
        case .todasLasBases: "Todas las bases"
        case .area(let a): "\(a.numero) · \(a.nombre)"
        case .base(let id): bases[id]?.nombre ?? id.capitalized
        case .seccion(let s): s.titulo
        }
    }

    // MARK: Interno

    struct Foto: Equatable { var filas: [FilaBarra]; var ocultos: [OcultoBarra] }

    var foto: Foto { Foto(filas: filas, ocultos: ocultos) }

    func restaurar(_ f: Foto) {
        filas = f.filas
        ocultos = f.ocultos
        guardar()
    }

    /// Aplica un cambio, lo normaliza, lo guarda y lo deja en Deshacer (y Rehacer).
    private func cambiar(_ nombre: String, deshacer: UndoManager?, _ cambio: () -> Void) {
        let antes = foto
        cambio()
        filas = Self.normalizar(filas)
        guard foto != antes else { return }
        guardar()
        registrarDeshacer(volverA: antes, nombre: nombre, en: deshacer)
    }

    private func registrarDeshacer(volverA foto: Foto, nombre: String, en um: UndoManager?) {
        guard let um else { return }
        let ahora = self.foto
        um.registerUndo(withTarget: self) { modelo in
            MainActor.assumeIsolated {
                modelo.restaurar(foto)
                modelo.registrarDeshacer(volverA: ahora, nombre: nombre, en: um)
            }
        }
        um.setActionName(nombre)
    }

    /// Un elemento metido dentro necesita uno normal antes (no un rótulo).
    static func normalizar(_ filas: [FilaBarra]) -> [FilaBarra] {
        var out = filas
        for i in out.indices where out[i].dentro {
            if i == 0 || out[i - 1].elemento.esSeccion || out[i].elemento.esSeccion { out[i].dentro = false }
        }
        return out
    }

    func guardar() {
        guard let archivo else { return }
        let g = Guardado(filas: filas, ocultos: ocultos,
                         bases: bases.values.filter { b in !BaseConocida.deSerie.contains(b) }.sorted { $0.id < $1.id })
        do {
            try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(g).write(to: archivo, options: .atomic)
        } catch {
            Self.log.error("No he podido guardar la barra lateral: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Lo que viaja al arrastrar una fila de la barra (o de la bandeja «Ocultos»).
public struct ArrastreBarra: Codable, Transferable, Sendable {
    public let elemento: ElementoBarra
    public let desdeOcultos: Bool

    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tlsElementoBarra)
    }
}

public extension UTType {
    /// Tipo propio de la app (declarado en `Info.plist`): una fila de la barra lateral arrastrada.
    static let tlsElementoBarra = UTType(exportedAs: "es.thelast.system.elemento-barra")
}
