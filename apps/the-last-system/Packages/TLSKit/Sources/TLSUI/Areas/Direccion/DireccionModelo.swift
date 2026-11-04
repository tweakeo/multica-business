import Foundation
import TLSCore
import TLSDesign

/// Todo lo que pinta la Operación de Dirección (PLAN §6.5, SISTEMAS §4.2 y DI1–DI3), calculado de una vez con la
/// foto de la carpeta. Lo privado, lo retirado y las plantillas no entran (los cálculos del núcleo ya lo quitan).
struct DatosDireccion: Sendable {
    let hoy: LocalDate
    let cronograma: Cronograma
    /// Los objetivos con su ritmo (los del trimestre primero).
    let objetivos: [RitmoObjetivo]
    /// Proyectos internos que cuelgan de cada objetivo (clave: ruta del objetivo).
    let proyectosPorObjetivo: [VaultPath: Int]
    /// Objetivos abiertos a los que se puede colgar un proyecto (para «Colgar de un objetivo»).
    let objetivosAbiertos: [FotoMetricas.Objetivo]
    let mapa: MapaMadurez
    let etapas: [EtapaArea]
    /// `Decisiones.md`, de la más reciente a la más antigua (las sustituidas, marcadas).
    let decisiones: [LineaDecision]
    let hayRegistro: Bool
    /// DIR-DEC14 y DIR-OBJ (los de Control de Dirección), del evaluador del núcleo.
    let cifras: [CifraOperacion]
    /// La propuesta de «Plan de 4 semanas para el cuello» (si hay cuello).
    let plan: PlanCuello?

    static let codigosCifras = ["DIR-DEC14", "DIR-OBJ"]

    static func calcular(foto: VaultSnapshot, hoy: LocalDate) -> DatosDireccion {
        let panel = PanelMetricas.calcular(snapshot: foto)
        let hoy = panel.hoy
        let layout = foto.layout
        let atenciones = Invariantes(snapshot: foto).atenciones()
        let cronograma = Cronograma.internos(proyectos: panel.foto.proyectos, objetivos: panel.foto.objetivos,
                                             ritmos: panel.objetivos, atenciones: atenciones, hoy: hoy)
        var porObjetivo: [VaultPath: Int] = [:]
        for b in cronograma.barras { if let o = b.objetivo { porObjetivo[o, default: 0] += 1 } }
        let objetivos = panel.objetivos.sorted { a, b in
            if a.objetivo.vivo(hoy: hoy) != b.objetivo.vivo(hoy: hoy) { return a.objetivo.vivo(hoy: hoy) }
            if a.objetivo.prioritario != b.objetivo.prioritario { return a.objetivo.prioritario }
            return a.objetivo.titulo.localizedStandardCompare(b.objetivo.titulo) == .orderedAscending
        }
        let abiertos = panel.foto.objetivos.filter { o in
            !["conseguido", "no conseguido", "cerrado", "archivado"].contains(TextFolding.fold(o.estado ?? ""))
        }
        let rutaRegistro = RegistroDecisiones.ruta(layout)
        let real = foto.existing(rutaRegistro)
        let texto = real.flatMap { layout.isPrivate($0) ? nil : foto.text($0) }
        let decisiones = (texto.map(RegistroDecisiones.leer)?.lineas ?? []).sorted { a, b in
            let fa = a.fecha ?? LocalDate(year: 1, month: 1, day: 1)!, fb = b.fecha ?? LocalDate(year: 1, month: 1, day: 1)!
            return fa != fb ? fa > fb : a.numeroDeLinea > b.numeroDeLinea
        }
        let cifras = codigosCifras.map { CifraOperacion(panel.evaluador.evaluar($0)) }
        return DatosDireccion(hoy: hoy, cronograma: cronograma, objetivos: objetivos, proyectosPorObjetivo: porObjetivo,
                              objetivosAbiertos: abiertos, mapa: panel.mapa, etapas: panel.etapas, decisiones: decisiones,
                              hayRegistro: texto != nil, cifras: cifras,
                              plan: PlanCuello.proponer(mapa: panel.mapa, etapas: panel.etapas, hoy: hoy))
    }
}

/// «Plan de 4 semanas para el cuello» (SISTEMAS DI3, paso 4): tres acciones para el área que frena a las demás y,
/// la cuarta semana, volver a diagnosticarla. Es una **propuesta**: no se escribe nada hasta tu OK, y entonces
/// crea las tareas (una por semana, planificadas el lunes) en un solo paso que se deshace entero.
struct PlanCuello: Sendable, Hashable {
    struct Semana: Sendable, Hashable, Identifiable {
        var id: Int { numero }
        let numero: Int
        let lunes: LocalDate
        let titulo: String
        let descripcion: String
    }

    let area: AreaCode
    /// «El cuello es 2 · Ventas: …».
    let porque: String
    let semanas: [Semana]

    /// La propuesta para el cuello del mapa (`nil` si no hay cuello).
    static func proponer(mapa: MapaMadurez, etapas: [EtapaArea], hoy: LocalDate) -> PlanCuello? {
        guard let cuello = mapa.cuello else { return nil }
        let area = cuello.area
        let etapa = etapas.first { $0.area == area }
        var acciones: [(String, String)] = []
        // Lo que falta montar y ya hace falta, por orden del estándar.
        for s in (etapa?.sistemas ?? []).filter({ $0.haceFalta && $0.estado != .montado }).sorted(by: { $0.sistema.orden < $1.sistema.orden }) {
            let verbo = s.estado == .aMedias ? "Terminar de montar" : "Montar"
            acciones.append(("\(verbo) «\(s.sistema.nombre)»",
                             "\(s.sistema.pregunta) Está \(s.estado.etiqueta.lowercased()): \(s.encendidas) de \(s.total) piezas."))
            if acciones.count == 3 { break }
        }
        if acciones.count < 3, let paso = etapa?.paso, !paso.que.isEmpty,
           !acciones.contains(where: { TextFolding.fold($0.0) == TextFolding.fold(paso.que) }) {
            acciones.append((paso.que, paso.porque))
        }
        if acciones.isEmpty {
            acciones.append(("Quitar lo que frena a \(area.nombre)", cuello.motivo))
        }
        let primerLunes = OperacionComun.lunes(de: hoy).adding(days: 7)
        var semanas: [Semana] = []
        for (i, a) in acciones.prefix(3).enumerated() {
            semanas.append(Semana(numero: i + 1, lunes: primerLunes.adding(days: 7 * i), titulo: a.0, descripcion: a.1))
        }
        let ultima = semanas.count + 1
        semanas.append(Semana(numero: ultima, lunes: primerLunes.adding(days: 7 * (ultima - 1)),
                              titulo: "Volver a diagnosticar \(area.etiquetaNumerada)",
                              descripcion: "Un área sube cuando desaparecen los síntomas, no cuando se ha hecho el trabajo. Mira el mapa y su ritmo."))
        return PlanCuello(area: area, porque: mapa.textoCuello, semanas: semanas)
    }

    /// Título de la tarea de una semana: «Plan del cuello · semana 1: Montar «Embudo»».
    func tituloTarea(_ s: Semana) -> String { "Plan del cuello · semana \(s.numero): \(s.titulo)" }

    /// Las tareas que se crean con tu OK (solo las semanas elegidas), en las tareas del área del cuello.
    func tareas(_ elegidas: Set<Int>, persona: String, autor: Autor) -> [NuevaTarea] {
        semanas.filter { elegidas.contains($0.numero) }.map { s in
            NuevaTarea(titulo: tituloTarea(s), area: area, responsable: persona, estado: .porHacer, prioridad: "Alta",
                       planificada: s.lunes,
                       descripcion: "\(s.descripcion)\n\nSemana \(s.numero) del plan de 4 semanas para el cuello (\(area.etiquetaNumerada)). \(porque)",
                       origen: "manual", autor: autor)
        }
    }
}
