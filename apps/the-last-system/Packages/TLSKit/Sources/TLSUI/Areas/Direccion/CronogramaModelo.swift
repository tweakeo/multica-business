import Foundation
import TLSCore
import TLSDesign

// El cronograma de proyectos (PLAN §6.5): en Dirección, los proyectos internos de las seis áreas agrupados por su
// objetivo («Sin objetivo» en gris, con la atención DIR-03 y sus dos salidas); en Entrega, los expedientes de
// cliente. Es puro: lo pinta `CronogramaVista` (Gantt propio en `Canvas`) y lo prueban las pruebas.

/// Un proyecto en el cronograma.
struct BarraCronograma: Identifiable, Hashable, Sendable {
    var id: VaultPath { ruta }
    let ruta: VaultPath
    let nombre: String
    let area: AreaCode?
    let estado: FotoMetricas.EstadoProyecto?
    let inicio: LocalDate?
    let fin: LocalDate?
    let objetivo: VaultPath?
    let sinObjetivo: Bool
    /// DIR-03: en curso sin objetivo (se guardó igual, pero queda en atención con «Colgar de un objetivo» y
    /// «Seguir sin objetivo»).
    let atencion: AvisoInvariante?
    /// Lo que se lee al lado del nombre («2 · Ventas», «Talleres Martín»).
    let detalle: String?

    var conFechas: Bool { inicio != nil && fin != nil }

    var textoEstado: String { estado?.rawValue ?? "Sin estado" }

    /// «del 12 oct al 6 nov».
    func textoFechas(hoy: LocalDate) -> String {
        guard let inicio, let fin else { return "Sin fechas" }
        return "del \(OperacionComun.fecha(inicio, hoy: hoy)) al \(OperacionComun.fecha(fin, hoy: hoy))"
    }

    func etiquetaAccesible(hoy: LocalDate) -> String {
        var partes = [nombre]
        if let detalle { partes.append(detalle) }
        partes.append(textoEstado)
        partes.append(textoFechas(hoy: hoy))
        if atencion != nil { partes.append("Atención: en curso sin objetivo") }
        return partes.joined(separator: ", ")
    }
}

/// Las barras de un objetivo (o las que no cuelgan de ninguno).
struct GrupoCronograma: Identifiable, Hashable, Sendable {
    let id: String
    let titulo: String
    let objetivo: VaultPath?
    /// El ritmo del objetivo (si lo tiene).
    let ritmo: RitmoObjetivo?
    let barras: [BarraCronograma]
    /// El grupo de «Sin objetivo» (va en gris).
    let gris: Bool
}

/// El cronograma entero: grupos, la ventana de fechas (de lunes a domingo) y hoy.
struct Cronograma: Hashable, Sendable {
    let grupos: [GrupoCronograma]
    let desde: LocalDate
    let hasta: LocalDate
    let hoy: LocalDate

    static let idSinObjetivo = "sin-objetivo"

    /// Días de la ventana.
    var dias: Int { max(1, RangoFechas.diasEntre(desde, hasta) + 1) }

    /// Los lunes de la ventana.
    var semanas: [LocalDate] { stride(from: 0, to: dias, by: 7).map { desde.adding(days: $0) } }

    var barras: [BarraCronograma] { grupos.flatMap(\.barras) }
    var conFechas: [BarraCronograma] { barras.filter(\.conFechas) }
    var sinFechas: [BarraCronograma] { barras.filter { !$0.conFechas } }
    var vacio: Bool { barras.isEmpty }

    /// Posición de un día en la ventana (0 = `desde`).
    func indice(_ d: LocalDate) -> Int { RangoFechas.diasEntre(desde, d) }

    // MARK: Construir

    /// Dirección: los proyectos internos de las seis áreas (ni de entrega, ni cerrados, ni archivados), por objetivo.
    /// «Sin objetivo», al final y en gris; la atención DIR-03 la da el dominio (`Invariantes.atenciones()`).
    static func internos(proyectos: [FotoMetricas.Proyecto], objetivos: [FotoMetricas.Objetivo], ritmos: [RitmoObjetivo],
                         atenciones: [AvisoInvariante], hoy: LocalDate) -> Cronograma {
        let dir03 = Dictionary(atenciones.filter { $0.codigo == "DIR-03" }.map { (TextFolding.pathKey($0.ruta.raw), $0) },
                               uniquingKeysWith: { a, _ in a })
        let internos = proyectos.filter { p in
            !p.esDeEntrega && p.area != .entrega && (p.estado?.abierto ?? true)
        }
        let barras = internos.map { p in
            BarraCronograma(ruta: p.ruta, nombre: p.nombre, area: p.area, estado: p.estado, inicio: p.inicio, fin: p.fin,
                            objetivo: p.objetivoRuta, sinObjetivo: p.sinObjetivo, atencion: dir03[TextFolding.pathKey(p.ruta.raw)],
                            detalle: p.area?.etiquetaNumerada)
        }
        var grupos: [GrupoCronograma] = []
        let porObjetivo = Dictionary(grouping: barras.filter { $0.objetivo != nil }, by: { TextFolding.pathKey($0.objetivo!.raw) })
        let ordenados = objetivos.sorted { a, b in
            if a.prioritario != b.prioritario { return a.prioritario }
            return a.titulo.localizedStandardCompare(b.titulo) == .orderedAscending
        }
        var vistos = Set<String>()
        for o in ordenados {
            let k = TextFolding.pathKey(o.ruta.raw)
            guard let lista = porObjetivo[k], !lista.isEmpty else { continue }
            vistos.insert(k)
            grupos.append(GrupoCronograma(id: o.ruta.raw, titulo: o.titulo, objetivo: o.ruta,
                                          ritmo: ritmos.first { TextFolding.pathKey($0.objetivo.ruta.raw) == k },
                                          barras: ordenar(lista), gris: false))
        }
        // Objetivos que no están en la lista (privados o retirados): sus proyectos van con su nombre de fichero.
        for (k, lista) in porObjetivo where !vistos.contains(k) {
            let ruta = lista[0].objetivo!
            grupos.append(GrupoCronograma(id: ruta.raw, titulo: ruta.stem, objetivo: ruta, ritmo: nil, barras: ordenar(lista), gris: false))
        }
        let sueltos = barras.filter { $0.objetivo == nil }
        if !sueltos.isEmpty {
            grupos.append(GrupoCronograma(id: idSinObjetivo, titulo: "Sin objetivo", objetivo: nil, ritmo: nil,
                                          barras: ordenar(sueltos), gris: true))
        }
        let (desde, hasta) = ventana(barras, hoy: hoy)
        return Cronograma(grupos: grupos, desde: desde, hasta: hasta, hoy: hoy)
    }

    /// Entrega: los expedientes de cliente (en curso, sin empezar y pausados), agrupados por estado.
    static func deEntrega(_ expedientes: [ExpedienteEntrega], hoy: LocalDate) -> Cronograma {
        let barras = expedientes.filter { $0.estado?.abierto ?? true }.map { e in
            BarraCronograma(ruta: e.ruta, nombre: e.nombre, area: .entrega, estado: e.estado, inicio: e.inicio, fin: e.fin,
                            objetivo: nil, sinObjetivo: false, atencion: nil, detalle: e.empresa)
        }
        let orden: [FotoMetricas.EstadoProyecto?] = [.enCurso, .sinEmpezar, .pausado, nil]
        var grupos: [GrupoCronograma] = []
        for e in orden {
            let lista = barras.filter { $0.estado == e }
            guard !lista.isEmpty else { continue }
            grupos.append(GrupoCronograma(id: e?.rawValue ?? "sin-estado", titulo: e?.rawValue ?? "Sin estado", objetivo: nil,
                                          ritmo: nil, barras: ordenar(lista), gris: e == .pausado))
        }
        let (desde, hasta) = ventana(barras, hoy: hoy)
        return Cronograma(grupos: grupos, desde: desde, hasta: hasta, hoy: hoy)
    }

    static func ordenar(_ b: [BarraCronograma]) -> [BarraCronograma] {
        b.sorted { x, y in
            switch (x.inicio, y.inicio) {
            case let (a?, b?) where a != b: return a < b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return x.nombre.localizedStandardCompare(y.nombre) == .orderedAscending
            }
        }
    }

    /// De lunes a domingo: desde una semana antes de hoy (o el primer inicio) hasta ocho semanas después (o el
    /// último fin), con 26 semanas como mucho.
    static func ventana(_ barras: [BarraCronograma], hoy: LocalDate) -> (LocalDate, LocalDate) {
        var desde = hoy.adding(days: -7)
        var hasta = hoy.adding(days: 56)
        for b in barras where b.conFechas {
            if let i = b.inicio, i < desde { desde = i }
            if let f = b.fin, f > hasta { hasta = f }
        }
        let lunes = OperacionComun.lunes(de: max(desde, hoy.adding(days: -7 * 13)))
        var domingo = OperacionComun.lunes(de: hasta).adding(days: 6)
        if RangoFechas.diasEntre(lunes, domingo) > 7 * 26 { domingo = lunes.adding(days: 7 * 26 - 1) }
        return (lunes, domingo)
    }

    // MARK: Mover

    /// Mueve un proyecto `dias` días naturales; si una fecha cae en sábado o domingo, se corre al lunes (ENT-04).
    static func mover(inicio: LocalDate, fin: LocalDate, dias: Int) -> (inicio: LocalDate, fin: LocalDate) {
        let i = Tarea.laborable(inicio.adding(days: dias))
        let f = max(i, Tarea.laborable(fin.adding(days: dias)))
        return (i, f)
    }

    /// Cambia solo el fin (arrastrar el borde): nunca antes del inicio; en fin de semana, al lunes.
    static func cambiarFin(inicio: LocalDate, fin: LocalDate, dias: Int) -> LocalDate {
        max(inicio, Tarea.laborable(fin.adding(days: dias)))
    }

    /// Con el teclado o el menú: un día laborable antes o después (saltando el fin de semana).
    static func moverUnDia(inicio: LocalDate, fin: LocalDate, adelante: Bool) -> (inicio: LocalDate, fin: LocalDate) {
        let paso = adelante ? 1 : -1
        let i = OperacionComun.laborable(inicio, paso: paso)
        let f = max(i, OperacionComun.laborable(fin, paso: paso))
        return (i, f)
    }

    /// La escritura: solo `inicio` y `fin` del proyecto.
    static func comando(_ b: BarraCronograma, inicio: LocalDate, fin: LocalDate) -> CommandBus.Comando {
        .cambiarPropiedades(b.ruta, poner: [Property(key: "inicio", value: .text(inicio.description)),
                                            Property(key: "fin", value: .text(fin.description))], quitar: [])
    }
}
