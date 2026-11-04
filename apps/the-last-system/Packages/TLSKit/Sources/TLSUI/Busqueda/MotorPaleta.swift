import Foundation
import TLSCore
import TLSDesign

/// Para qué se acota ⌘K (§4.9): Todo · Fichas · Bases · Acciones · Texto.
enum AcotarPaleta: String, CaseIterable, Sendable {
    case todo, fichas, bases, acciones, texto

    var nombre: String {
        switch self {
        case .todo: "Todo"
        case .fichas: "Fichas"
        case .bases: "Bases"
        case .acciones: "Acciones"
        case .texto: "Texto"
        }
    }
}

/// Qué hace un resultado de ⌘K al abrirlo.
enum AccionPaleta: Hashable, Sendable {
    /// Abrir una ficha o nota (con su base, para sembrar las migas: `Facturas › F-2026-0013`).
    case abrir(VaultPath, base: String?)
    /// Abrir una base (con lo que se busca dentro).
    case base(String, busqueda: String?)
    /// «Nueva …» en una base, si se da, ya enlazada con una ficha.
    case nueva(String, contexto: VaultPath?)
    /// Ir a una pantalla.
    case ir(Destino)
}

/// Un resultado de ⌘K.
struct ItemPaleta: Identifiable, Hashable, Sendable {
    let id: String
    let titulo: String
    let sub: String
    let tipo: String
    let icono: String
    let area: AreaCode?
    /// Resaltar lo buscado en el título (no en las acciones).
    let resaltar: Bool
    let accion: AccionPaleta
    /// Ruta para la vista previa (fichas y notas).
    var ruta: VaultPath? {
        if case .abrir(let r, _) = accion { return r }
        return nil
    }
}

/// Una sección de ⌘K: «Mejores resultados», una por base, «Acciones», «Bases», «Dentro de notas».
struct SeccionPaleta: Identifiable, Hashable, Sendable {
    var id: String { titulo }
    let titulo: String
    let grupo: AcotarPaleta
    let items: [ItemPaleta]
}

/// Lo que enseña ⌘K para lo escrito: puro, sin interfaz (se prueba aparte). Nunca lo privado: el catálogo y la
/// búsqueda de texto ya llegan sin ello.
enum MotorPaleta {
    static let maxMejores = 3
    static let maxPorBase = 5

    /// Secciones para lo escrito (vacío: Recientes · Pide tu decisión · Bases fijadas).
    static func secciones(_ consulta: String, catalogo: CatalogoBusqueda, texto: [SearchHit], recientes: [VaultPath],
                          fijadas: [String], acotar: AcotarPaleta, puedeCrear: Bool) -> [SeccionPaleta] {
        let q = consulta.trimmingCharacters(in: .whitespaces)
        var out: [SeccionPaleta] = []
        if q.isEmpty {
            let rec = recientes.compactMap { catalogo.entrada($0) }.prefix(5).map(item)
            if !rec.isEmpty { out.append(SeccionPaleta(titulo: "Recientes", grupo: .fichas, items: Array(rec))) }
            let pide = catalogo.entradas.filter(\.pideDecision)
                .sorted { ($0.modificada ?? .distantPast) > ($1.modificada ?? .distantPast) }.prefix(3).map(item)
            if !pide.isEmpty { out.append(SeccionPaleta(titulo: "Pide tu decisión", grupo: .fichas, items: Array(pide))) }
            let bases = fijadas.compactMap(CatalogoBases.coleccion).map(itemBase)
            if !bases.isEmpty { out.append(SeccionPaleta(titulo: "Bases fijadas", grupo: .bases, items: bases)) }
            return filtrar(out, acotar)
        }
        // Fichas: las 3 mejores y, después, una sección por base.
        let resultados = catalogo.buscar(q, limite: 60)
        let mejores = Array(resultados.prefix(maxMejores))
        if !mejores.isEmpty {
            out.append(SeccionPaleta(titulo: "Mejores resultados", grupo: .fichas, items: mejores.map { item($0.entrada, $0) }))
        }
        let resto = resultados.dropFirst(maxMejores)
        for c in CatalogoBases.deSerie {
            let xs = resto.filter { $0.entrada.base == c.id }.prefix(maxPorBase)
            if !xs.isEmpty { out.append(SeccionPaleta(titulo: c.nombre, grupo: .fichas, items: xs.map { item($0.entrada, $0) })) }
        }
        let sueltas = resto.filter { $0.entrada.base == nil }.prefix(maxPorBase)
        if !sueltas.isEmpty { out.append(SeccionPaleta(titulo: "Otras notas", grupo: .fichas, items: sueltas.map { item($0.entrada, $0) })) }
        // Acciones.
        let acciones = Self.acciones(q, primera: resultados.first?.entrada, puedeCrear: puedeCrear)
        if !acciones.isEmpty { out.append(SeccionPaleta(titulo: "Acciones", grupo: .acciones, items: acciones)) }
        // Bases.
        let fq = TextFolding.fold(q)
        let bases = CatalogoBases.deSerie.filter { c in
            let n = TextFolding.fold(c.nombre)
            return n.hasPrefix(fq) || fq.hasPrefix(n) || TextFolding.fold(c.singular).hasPrefix(fq)
        }.map(itemBase)
        if !bases.isEmpty { out.append(SeccionPaleta(titulo: "Bases", grupo: .bases, items: bases)) }
        // Dentro de notas: texto completo, con la línea donde aparece.
        let vistos = Set(resultados.map(\.entrada.ruta))
        let dentro = texto.filter { !$0.note.privado && !vistos.contains($0.note.path) }.prefix(6).map { hit in
            ItemPaleta(id: "texto:\(hit.note.path.raw)", titulo: limpiarFragmento(hit.snippet),
                       sub: "\(hit.note.title) · \(hit.note.path.parent?.raw ?? "")", tipo: "Texto",
                       icono: "text.alignleft", area: hit.note.area, resaltar: true,
                       accion: .abrir(hit.note.path, base: CatalogoBases.coleccion(paraTipo: hit.note.kind)?.id))
        }
        if !dentro.isEmpty { out.append(SeccionPaleta(titulo: "Dentro de notas", grupo: .texto, items: Array(dentro))) }
        return filtrar(out, acotar)
    }

    static func filtrar(_ s: [SeccionPaleta], _ acotar: AcotarPaleta) -> [SeccionPaleta] {
        acotar == .todo ? s : s.filter { $0.grupo == acotar }
    }

    /// «‹vencida›…» → «vencida…» (las marcas del fragmento se quitan; lo buscado se resalta al pintar).
    static func limpiarFragmento(_ s: String) -> String {
        s.replacingOccurrences(of: "‹", with: "").replacingOccurrences(of: "›", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func item(_ e: EntradaBusqueda) -> ItemPaleta { item(e, nil) }

    static func item(_ e: EntradaBusqueda, _ r: ResultadoBusqueda?) -> ItemPaleta {
        let base = e.base.flatMap(CatalogoBases.coleccion)
        var sub = [e.codigos.first, e.detalle.isEmpty ? nil : e.detalle].compactMap { $0 }.joined(separator: " · ")
        if let r, r.lugar == .otroNombre, let c = r.coincidencia { sub = "También «\(c)»" + (sub.isEmpty ? "" : " · \(sub)") }
        if sub.isEmpty { sub = e.ruta.parent?.raw ?? "" }
        return ItemPaleta(id: "ficha:\(e.ruta.raw)", titulo: e.titulo, sub: sub,
                          tipo: base.map { $0.singular.prefix(1).uppercased() + $0.singular.dropFirst() } ?? "Nota",
                          icono: base?.icono ?? "doc.text", area: e.area, resaltar: true, accion: .abrir(e.ruta, base: e.base))
    }

    static func itemBase(_ c: ColeccionBase) -> ItemPaleta {
        ItemPaleta(id: "base:\(c.id)", titulo: c.nombre, sub: c.area.map { "\($0.numero) · \($0.nombre)" } ?? "Comunes",
                   tipo: "Base", icono: c.icono, area: c.area, resaltar: true, accion: .base(c.id, busqueda: nil))
    }

    /// Acciones para lo escrito: «Nueva factura para Arquitectura Nexo», «Ir a Facturas», «Nueva tarea…» y,
    /// si se empieza por el nombre de una base, buscar dentro de ella («facturas vencidas»).
    static func acciones(_ q: String, primera: EntradaBusqueda?, puedeCrear: Bool) -> [ItemPaleta] {
        let fq = TextFolding.fold(q)
        let palabras = fq.split(separator: " ").map(String.init)
        var out: [ItemPaleta] = []
        // Empieza por el nombre de una base: buscar dentro de ella con el resto.
        for c in CatalogoBases.deSerie {
            let n = TextFolding.fold(c.nombre)
            if palabras.count > 1, palabras[0] == n || palabras[0] == TextFolding.fold(c.singular) {
                let resto = q.split(separator: " ").dropFirst().joined(separator: " ")
                out.append(ItemPaleta(id: "buscar:\(c.id)", titulo: "Buscar «\(resto)» en \(c.nombre)",
                                      sub: "Con lo que parezca un filtro, como «vencidas»", tipo: "Acción", icono: "magnifyingglass",
                                      area: c.area, resaltar: false, accion: .base(c.id, busqueda: resto)))
            }
        }
        // Una ficha de empresa o contacto: crear ya enlazado.
        if puedeCrear, let e = primera, e.tipo == .organization || e.tipo == .contact {
            for id in ["facturas", "oportunidades", "reuniones"] {
                guard let c = CatalogoBases.coleccion(id), c.plantilla != nil else { continue }
                out.append(ItemPaleta(id: "nueva:\(id):\(e.ruta.raw)", titulo: "\(c.textoNueva) para \(e.titulo)",
                                      sub: "Nace ya enlazada con \(e.titulo)", tipo: "Acción", icono: "plus",
                                      area: c.area, resaltar: false, accion: .nueva(id, contexto: e.ruta)))
            }
        }
        // «nueva tarea», «tarea», «facturas»: crear o ir a la base.
        let sinNueva = palabras.filter { !["nueva", "nuevo", "crear"].contains($0) }.joined(separator: " ")
        for c in CatalogoBases.deSerie where !sinNueva.isEmpty {
            let n = TextFolding.fold(c.nombre), s = TextFolding.fold(c.singular)
            guard n.hasPrefix(sinNueva) || s.hasPrefix(sinNueva) else { continue }
            if puedeCrear, c.plantilla != nil {
                out.append(ItemPaleta(id: "nueva:\(c.id)", titulo: "\(c.textoNueva)…", sub: "Solo lo que pide su plantilla",
                                      tipo: "Acción", icono: "plus", area: c.area, resaltar: false, accion: .nueva(c.id, contexto: nil)))
            }
            out.append(ItemPaleta(id: "ir:\(c.id)", titulo: "Ir a \(c.nombre)", sub: "La base entera, con sus vistas",
                                  tipo: "Acción", icono: c.icono, area: c.area, resaltar: false, accion: .base(c.id, busqueda: nil)))
        }
        if "bases".hasPrefix(fq) || fq.hasPrefix("todas") || fq.hasPrefix("ir a bases") {
            out.append(ItemPaleta(id: "ir:bases", titulo: "Ir a Todas las bases", sub: "Las 24, por área", tipo: "Acción",
                                  icono: "tablecells", area: nil, resaltar: false, accion: .ir(.todasLasBases)))
        }
        var vistos = Set<String>()
        return Array(out.filter { vistos.insert($0.id).inserted }.prefix(4))
    }
}
