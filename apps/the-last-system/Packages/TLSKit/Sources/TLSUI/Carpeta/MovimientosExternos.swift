import Foundation
import TLSCore

/// Lo que se movió fuera de la app (en Finder) y dejó enlaces apuntando a donde estaba. Se detecta de dos
/// formas, sin escribir nada:
/// 1. comparando la lista de ficheros de antes y de ahora (lo que desaparece y aparece con el mismo nombre);
/// 2. sin lista de antes (al abrir la Carpeta), por los enlaces con ruta que ya no llevan a nada y cuyo
///    nombre está en un único sitio.
/// El arreglo es `LinkRefactor.arreglarMovimientoExterno`: un plan que solo cambia enlaces, con Deshacer.
enum MovimientosExternos {
    /// Movimientos entre dos fotos de la carpeta: desaparece `de` y aparece un único fichero con su nombre.
    static func entre(antes: Set<VaultPath>, ahora: VaultSnapshot) -> [Traslado] {
        let actuales = Set(ahora.files)
        let desaparecidos = antes.subtracting(actuales)
        guard !desaparecidos.isEmpty else { return [] }
        var aparecidos: [String: [VaultPath]] = [:]
        for p in actuales.subtracting(antes) {
            aparecidos[TextFolding.nameKey(p.name), default: []].append(p)
        }
        var salida: [Traslado] = []
        var destinos: [VaultPath: Int] = [:]
        for d in desaparecidos.sorted() {
            guard let c = aparecidos[TextFolding.nameKey(d.name)], c.count == 1 else { continue }
            salida.append(Traslado(de: d, a: c[0]))
            destinos[c[0], default: 0] += 1
        }
        // Dos desaparecidos con el mismo nombre y un solo aparecido: no se sabe cuál fue.
        return salida.filter { destinos[$0.a] == 1 }
    }

    /// Movimientos que se deducen de enlaces con ruta rotos (Markdown relativos «flojos» y wikilinks con
    /// carpeta cuyo nombre solo está en un sitio).
    static func porEnlacesRotos(_ foto: VaultSnapshot) -> [Traslado] {
        var porNombre: [String: [VaultPath]] = [:]
        for p in foto.files {
            porNombre[TextFolding.nameKey(p.name), default: []].append(p)
        }
        var mapa: [VaultPath: VaultPath] = [:]
        var dudosos = Set<VaultPath>()
        func apuntar(_ de: VaultPath, _ a: VaultPath) {
            guard !de.isRoot, de != a, foto.existing(de) == nil, !dudosos.contains(de) else { return }
            if let ya = mapa[de], ya != a { mapa[de] = nil; dudosos.insert(de); return }
            mapa[de] = a
        }
        for e in SaludDeEnlaces(snapshot: foto).revisar() {
            let esWiki = e.enlace.hasPrefix("[[") || e.enlace.hasPrefix("![[")
            switch e.estado {
            case .flojo(let real) where !esWiki:
                guard var vieja = e.origen.resolvingRelative(e.destino.components(separatedBy: "#").first ?? e.destino) else { continue }
                if vieja.ext.isEmpty, !real.ext.isEmpty { vieja = VaultPath(vieja.raw + "." + real.ext) }
                guard TextFolding.nameKey(vieja.name) == TextFolding.nameKey(real.name) else { continue }
                apuntar(vieja, real)
            case .pendiente where esWiki && e.destino.contains("/"):
                var vieja = VaultPath(e.destino)
                if vieja.ext.isEmpty { vieja = VaultPath(vieja.raw + ".md") }
                guard let c = porNombre[TextFolding.nameKey(vieja.name)], c.count == 1 else { continue }
                apuntar(vieja, c[0])
            default:
                continue
            }
        }
        return mapa.map { Traslado(de: $0.key, a: $0.value) }.sorted { $0.de < $1.de }
    }

    /// Todos los que se detectan (primero los de la comparación, que son seguros).
    static func detectar(antes: Set<VaultPath>?, ahora: VaultSnapshot) -> [Traslado] {
        var salida = antes.map { entre(antes: $0, ahora: ahora) } ?? []
        let vistos = Set(salida.map(\.de))
        let destinos = Set(salida.map(\.a))
        for t in porEnlacesRotos(ahora) where !vistos.contains(t.de) && !destinos.contains(t.a) {
            salida.append(t)
        }
        return salida
    }

    /// Vista previa del arreglo (solo si hay enlaces que cambiar). Los traslados que no se pueden arreglar se
    /// quitan uno a uno.
    static func arreglo(_ traslados: [Traslado], foto: VaultSnapshot, opciones: LinkRefactor.Opciones) -> RefactorPreview? {
        guard !traslados.isEmpty else { return nil }
        let motor = LinkRefactor(snapshot: foto)
        // Solo los que tienen enlaces que arreglar (lo que Obsidian ya resolvió por el nombre no cuenta).
        var validos = traslados.prefix(50).filter { t in
            guard let p = try? motor.arreglarMovimientoExterno([t], opciones: opciones) else { return false }
            return p.enlaces + p.filasCSV > 0
        }
        while !validos.isEmpty {
            if let p = try? motor.arreglarMovimientoExterno(validos, opciones: opciones) {
                return p.enlaces + p.filasCSV > 0 && p.esSeguro ? p : nil
            }
            validos.removeLast()
        }
        return nil
    }
}
