import Foundation
import TLSAgents
import TLSCore

// F4 · rol mika. El contexto de la pantalla para ⌘J (PLAN §6.1: «Mika con el contexto de la pantalla»): una frase
// para ti («Estás en Ventas › NEXO»), lo que se le cuenta a Mika (la ruta de lo que ves, para que lo lea con sus
// herramientas) y las acciones rápidas del área. **Nada privado** sale de aquí: una nota privada es «una nota
// privada», sin nombre ni ruta (PLAN §8: lo privado nunca llega a un asistente).

/// Una acción rápida de ⌘J: lo que se le pide a un asistente con un botón.
struct AccionRapidaMika: Sendable, Hashable, Identifiable {
    var id: String { "\(asistente).\(accion)" }
    /// `comercial`, `mika`…
    let asistente: String
    /// «Comercial».
    let nombreAsistente: String
    /// `preparar-seguimiento` (el id del perfil: la grabación y el motor lo reconocen).
    let accion: String
    /// «Preparar seguimiento».
    let titulo: String
    /// Lo que se le pide.
    let peticion: String
}

/// Dónde estás cuando abres ⌘J.
struct ContextoPantalla: Sendable, Hashable {
    /// «Estás en Ventas › NEXO».
    let frase: String
    /// Lo que se le cuenta a Mika en el primer mensaje («Ventas › Oportunidad «…» (ruta)»), sin nada privado.
    let paraMika: String
    /// El área de lo que se ve (para las acciones rápidas).
    let area: AreaCode?
    /// La ficha o nota que se ve (nunca una privada).
    let ruta: VaultPath?
    /// La tarea que se ve (los trabajos que se piden desde ella dejan ahí su Actividad).
    let tarea: VaultPath?

    static let general = ContextoPantalla(frase: "Estás en Hoy", paraMika: "Hoy", area: nil, ruta: nil, tarea: nil)

    /// El contexto de la pestaña que tiene el foco.
    @MainActor
    static func de(_ nav: Navegacion?, sesion: VaultSession) -> ContextoPantalla {
        guard let nav else { return .general }
        return de(camino: [nav.raiz] + nav.pila, sesion: sesion)
    }

    @MainActor
    static func de(camino: [Destino], sesion: VaultSession) -> ContextoPantalla {
        var nombres: [String] = []
        var paraMika: [String] = []
        var area: AreaCode?
        var ruta: VaultPath?
        var tarea: VaultPath?
        let layout = sesion.estructura
        for d in camino {
            switch d {
            case .area(let a, _):
                area = a
                nombres.append(a.nombre)
                paraMika.append(a.etiquetaNumerada)
            case .ficha(let p, _), .nota(let p), .fichero(let p), .tarea(let p):
                if sesion.esPrivado(p) {
                    // Lo privado no sale: ni su nombre ni su ruta (a Mika, ni que existe).
                    nombres.append("una nota privada")
                    ruta = nil
                    tarea = nil
                    continue
                }
                let titulo = sesion.titulo(de: p)
                nombres.append(PlegadoMigas.nombreCorto(titulo, codigo: PlegadoMigas.codigo(titulo: titulo, fichero: p.stem),
                                                        anteriores: nombres))
                let tipo = sesion.resumen(de: p)?.kind
                paraMika.append("\(Self.tipo(tipo, destino: d)) «\(titulo)» (\(p.raw))")
                ruta = p
                if case .tarea = d { tarea = p } else if tipo == .task { tarea = p } else { tarea = nil }
                if let a = layout?.area(of: p) { area = a }
            case .decision:
                let n = sesion.nombre(de: d)
                nombres.append(PlegadoMigas.nombreCorto(n))
                paraMika.append("Decisión «\(n)»")
                if let p = d.ruta, !sesion.esPrivado(p) { ruta = p; tarea = p; if let a = layout?.area(of: p) { area = a } }
            case .asistente(let slug):
                // F4 · integración: en la ficha de un asistente, sus acciones rápidas («Pedir algo» abre ⌘J aquí).
                let n = sesion.nombre(de: d)
                nombres.append(PlegadoMigas.nombreCorto(n))
                paraMika.append(n)
                if let a = PerfilDeAsistente.deSerie.first(where: { $0.slug == slug })?.area { area = a }
            case .busqueda:
                // Lo que se busca puede ser privado: solo se dice que se está buscando.
                nombres.append("Buscar")
                paraMika.append("Buscar en la carpeta")
            default:
                let n = sesion.nombre(de: d)
                nombres.append(PlegadoMigas.nombreCorto(n))
                paraMika.append(n)
            }
        }
        // Como mucho los tres últimos niveles (la frase cabe en la cabecera del panel).
        let visibles = nombres.count > 3 ? Array(nombres.suffix(3)) : nombres
        let frase = "Estás en " + (visibles.isEmpty ? "Hoy" : visibles.joined(separator: " › "))
        return ContextoPantalla(frase: frase, paraMika: paraMika.isEmpty ? "Hoy" : paraMika.joined(separator: " › "),
                                area: area, ruta: ruta, tarea: tarea)
    }

    static func tipo(_ k: NoteKind?, destino: Destino) -> String {
        if case .tarea = destino { return "Tarea" }
        switch k {
        case .task: return "Tarea"
        case .opportunity: return "Oportunidad"
        case .contact: return "Contacto"
        case .organization: return "Empresa"
        case .project: return "Proyecto"
        case .invoice: return "Factura"
        case .draft: return "Borrador"
        case .system: return "Sistema"
        case .decision: return "Decisión"
        default: return "Nota"
        }
    }

    /// Las acciones rápidas que tienen sentido aquí: las del asistente del área (si lo hay) y las de Mika.
    func accionesRapidas(perfiles: [PerfilDeAsistente] = PerfilDeAsistente.deSerie) -> [AccionRapidaMika] {
        var out: [AccionRapidaMika] = []
        func anadir(_ p: PerfilDeAsistente) {
            for a in p.accionesRapidas where !out.contains(where: { $0.accion == a.id && $0.asistente == p.slug }) {
                out.append(AccionRapidaMika(asistente: p.slug, nombreAsistente: p.nombre, accion: a.id, titulo: a.titulo,
                                            peticion: a.peticion))
            }
        }
        if let area, let p = perfiles.first(where: { $0.area == area && !$0.coordinador }) { anadir(p) }
        if let mika = perfiles.first(where: \.coordinador) { anadir(mika) }
        // Sin área (Hoy, Decisiones…): además, lo que más se pide (cobros).
        if area == nil, let contable = perfiles.first(where: { $0.area == .finanzas }) {
            for a in contable.accionesRapidas.prefix(1) where !out.contains(where: { $0.accion == a.id }) {
                out.append(AccionRapidaMika(asistente: contable.slug, nombreAsistente: contable.nombre, accion: a.id,
                                            titulo: a.titulo, peticion: a.peticion))
            }
        }
        return Array(out.prefix(4))
    }
}
