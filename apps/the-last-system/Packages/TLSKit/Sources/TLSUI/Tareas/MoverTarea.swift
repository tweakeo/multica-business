import Foundation
import TLSCore

/// «Mover a…» de una tarea (PLAN §4.2: la tarea vive donde vive su contenedor y la ruta manda): a la carpeta
/// `Tareas/` de otra área (suelta) o a la de un proyecto. Un solo plan con el traslado y todos sus enlaces
/// (`LinkRefactor`) y, en la misma operación, `area` y `proyecto` puestos como dice la carpeta nueva. Se deshace de
/// una vez. Nunca a una carpeta privada.
enum MoverTarea {
    enum Destino: Hashable, Sendable {
        case area(AreaCode)
        /// El `Proyecto.md` del proyecto.
        case proyecto(VaultPath)
    }

    enum Error: Swift.Error, LocalizedError, Equatable {
        case yaEsta
        case privado
        case noEsTarea

        var errorDescription: String? {
            switch self {
            case .yaEsta: "La tarea ya está ahí."
            case .privado: "Una tarea no se mueve a una carpeta privada."
            case .noEsTarea: "No encuentro la tarea."
            }
        }
    }

    /// Carpeta `Tareas/` del destino.
    static func carpeta(_ d: Destino, layout: VaultLayout) -> VaultPath {
        switch d {
        case .area(let a): layout.areaFolder(a).appending(layout.tareas)
        case .proyecto(let p): (p.parent ?? .root).appending(layout.tareas)
        }
    }

    /// Proyectos a los que se puede mover (no privados, no retirados ni cerrados), por área y nombre.
    static func proyectos(_ foto: VaultSnapshot, grafo: GrafoRelaciones?) -> [(ruta: VaultPath, nombre: String, area: AreaCode?)] {
        let layout = foto.layout
        return foto.notes.filter { p in
            TextFolding.nameKey(p.name) == "proyecto.md" && !layout.isPrivate(p) && !layout.isArchived(p)
                && !VaultSnapshot.isTemplatePath(p)
                && p.components.count >= 3 && TextFolding.nameKey(p.components[p.components.count - 3]) == TextFolding.nameKey(layout.proyectos)
        }
        .compactMap { p -> (VaultPath, String, AreaCode?)? in
            let fm = foto.frontmatter(p)
            let estado = TextFolding.fold(fm.text("estado") ?? "")
            guard estado != "cerrado", estado != "archivado" else { return nil }
            let nombre = grafo?.ficha(p)?.nombre ?? fm.text("nombre") ?? p.parent?.name ?? p.stem
            return (p, nombre, layout.area(of: p))
        }
        .sorted { ($0.2?.numero ?? 9, TextFolding.fold($0.1)) < ($1.2?.numero ?? 9, TextFolding.fold($1.1)) }
    }

    static func preparar(_ ruta: VaultPath, a destino: Destino, foto: VaultSnapshot, autor: Autor) throws -> RefactorPreview {
        let layout = foto.layout
        guard let t = TaskStore(snapshot: foto).tarea(ruta) else { throw Error.noEsTarea }
        let carpeta = carpeta(destino, layout: layout)
        if case .proyecto(let p) = destino, layout.isPrivate(p) { throw Error.privado }
        guard !layout.isPrivate(carpeta.appending(t.ruta.name)) else { throw Error.privado }
        guard TextFolding.pathKey((t.ruta.parent ?? .root).raw) != TextFolding.pathKey(carpeta.raw) else { throw Error.yaEsta }
        let fm = foto.frontmatter(t.ruta)
        var poner: [Property] = []
        var quitar: [String] = []
        let area: AreaCode? = {
            switch destino {
            case .area(let a): return a
            case .proyecto(let p): return layout.area(of: p)
            }
        }()
        if let a = area, fm.text("area") != a.layoutKey { poner.append(Property(key: "area", value: .text(a.layoutKey))) }
        switch destino {
        case .proyecto(let p):
            let nombre = foto.frontmatter(p).text("nombre") ?? p.parent?.name ?? p.stem
            poner.append(Property(key: "proyecto", value: .text(NombresDeFicha.wikilink(p, nombre: nombre, en: foto))))
            if fm.properties.contains(where: { $0.key == "proyecto_id" }) { quitar.append("proyecto_id") }
        case .area:
            quitar += ["proyecto", "proyecto_id"].filter { k in fm.properties.contains { $0.key == k } }
        }
        let extra: [WriteOp] = poner.isEmpty && quitar.isEmpty ? [] : [.mergeFrontmatter(t.ruta, set: poner, unset: quitar)]
        let nombreDestino: String = {
            switch destino {
            case .area(let a): return "\(a.numero) · \(a.nombre)"
            case .proyecto(let p): return foto.frontmatter(p).text("nombre") ?? p.parent?.name ?? p.stem
            }
        }()
        return try LinkRefactor(snapshot: foto).preparar([Traslado(de: t.ruta, a: carpeta.appending(t.ruta.name))],
                                                        descripcion: "Mover «\(t.titulo)» a \(nombreDestino)",
                                                        opciones: .init(autor: autor, alias: .nunca), extra: extra)
    }
}
