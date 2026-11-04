import Foundation
import TLSCore

/// «Actualizar la copia desde la real» (PLAN §9 F3, criterio 9): lee la carpeta real (solo leer, sin lo privado, sin
/// descargar nada de iCloud) y trae a la copia lo que es nuevo, sin pisar nada. La real queda igual: su inventario
/// antes y después es idéntico.
public struct ActualizacionDesdeLaReal: Sendable {
    /// Un fichero de la real que se trae.
    public struct Nuevo: Sendable, Hashable {
        /// Ruta en la real.
        public let origen: VaultPath
        /// Ruta en la copia (la misma, la de sus hermanos ya ordenados, o `-2` si estaba ocupada).
        public let destino: VaultPath
        public let sha256: String
        public let motivo: String
    }

    public let nuevos: [Nuevo]
    /// Nuevos en la real que no se pueden traer sin estropearlos (propiedades rotas, texto ilegible), con su motivo.
    public let noSeTraen: [(ruta: VaultPath, motivo: String)]
    /// Están en la copia con otro contenido (o cambiaron en la real después de ordenarlos en la copia): no se tocan
    /// (se cuentan para que la persona lo sepa).
    public let distintos: [VaultPath]
    /// Ya estaban (misma ruta, mismo contenido en otro sitio o ya traídos en una importación).
    public let yaEstan: Int
    /// Solo en iCloud en la real: se ven por su nombre, no se traen (habría que descargarlos).
    public let soloEnICloud: [VaultPath]
    /// Huella del árbol de la real al leerla.
    public let hashArbolReal: String
    public let plan: WritePlan?

    /// «Traer 3 nuevos · 1 distinto no se toca · No se borra nada».
    public var resumen: String {
        var s = "Traer \(Plural.de(nuevos.count, "nuevo", "nuevos"))"
        if !noSeTraen.isEmpty { s += " · \(Plural.de(noSeTraen.count, "no se puede traer", "no se pueden traer"))" }
        if !distintos.isEmpty { s += " · \(Plural.de(distintos.count, "distinto no se toca", "distintos no se tocan"))" }
        if !soloEnICloud.isEmpty { s += " · \(soloEnICloud.count) solo en iCloud" }
        return s + " · No se borra nada"
    }

    // Para comprobar al aplicar.
    let real: URL
    let exclusiones: [VaultPath]

    /// Compara la real con la copia. Solo lee las dos.
    ///
    /// - `exclusiones`: lo que la persona dejó fuera de la copia (`exclusionesCopia`); se suma lo privado de `.tls/`.
    /// - `mapas`: las importaciones hechas en la copia (para no volver a traer lo que ya se movió a su sitio).
    public static func preparar(real: URL, copia: URL, exclusiones: [VaultPath], mapas: [MapaImportacion] = [],
                                autor: Autor = .persona("Manu"), fileSystem: any FileSystemAccess = LocalFileSystem())
        async throws -> ActualizacionDesdeLaReal {
        let realURL = real.standardizedFileURL.resolvingSymlinksInPath()
        let copiaURL = copia.standardizedFileURL.resolvingSymlinksInPath()
        // La copia nunca es la real ni está dentro de ella (ni al revés): se leería a sí misma.
        let kr = ExclusionRules.key(CopyJob.canonicalPath(realURL)), kc = ExclusionRules.key(CopyJob.canonicalPath(copiaURL))
        guard kr != kc, !kc.hasPrefix(kr + "/"), !kr.hasPrefix(kc + "/") else {
            throw ImportError.fuenteDentroDeLaCarpeta(realURL.lastPathComponent)
        }
        // La real, como la copia: sin lo privado, sin lo dejado fuera y sin `Archivo/`.
        let inventarioReal = try await Inventory.make(of: realURL, exclusiones: exclusiones, incluirArchivo: false,
                                                      conHashes: true, fileSystem: fileSystem)
        let inventarioCopia = try await Inventory.make(of: copiaURL, exclusiones: [], incluirArchivo: true, conHashes: true,
                                                       fileSystem: fileSystem)
        var enCopia: [String: InventoryEntry] = [:]
        var huellasCopia = Set<String>()
        for e in inventarioCopia.entradas where e.tipo == .fichero {
            enCopia[TextFolding.pathKey(e.ruta)] = e
            if let h = e.sha256 { huellasCopia.insert(h) }
        }
        // Lo que ya se trajo o se ordenó en una importación (alias «Carpeta»: rutas de la real), con su huella de
        // entonces (si el mapa la tiene) y adónde fue en la copia.
        var importados: [String: FilaMapa] = [:]
        var destinoDeHermanos: [String: [VaultPath]] = [:]
        for m in mapas {
            for f in m.filas {
                let (alias, ruta, _) = f.partesOrigen
                guard alias == FuenteImportacion.aliasDeLaEmpresa else { continue }
                importados[TextFolding.pathKey(ruta.raw)] = f
                if [.mover, .moverYRenombrar].contains(f.accion), let d = f.rutaDestino, let padre = ruta.parent, let dp = d.parent {
                    destinoDeHermanos[TextFolding.pathKey(padre.raw), default: []].append(dp)
                }
            }
        }
        var ocupadas = Set(inventarioCopia.entradas.map { TextFolding.pathKey($0.ruta) })
        var nuevos: [Nuevo] = []
        var distintos: [VaultPath] = []
        var soloEnICloud: [VaultPath] = []
        var ya = 0
        for e in inventarioReal.entradas where e.tipo == .fichero {
            let p = VaultPath(e.ruta)
            if p.components.contains(where: { $0.hasPrefix(".") }) { continue }   // ajustes y ocultos: no se traen
            if e.dataless { soloEnICloud.append(p); continue }
            guard let h = e.sha256 else { continue }
            let k = TextFolding.pathKey(p.raw)
            if let c = enCopia[k] {
                if c.sha256 == h { ya += 1 } else { distintos.append(p) }
                continue
            }
            if let f = importados[k] {
                // Ya se ordenó en la copia: si en la real ha cambiado desde entonces, se dice (no se trae ni se pisa).
                if Self.cambioDesdeQueSeOrdeno(f, sha: h, copia: copiaURL, enCopia: enCopia, fs: fileSystem, real: p.url(in: realURL)) {
                    distintos.append(p)
                } else {
                    ya += 1
                }
                continue
            }
            if huellasCopia.contains(h) { ya += 1; continue }
            // Sitio: donde fueron sus hermanos al ordenar (si todos fueron al mismo), o la misma ruta.
            var destino = p
            var motivo = "Es nuevo en tu carpeta real"
            if let padre = p.parent, let ds = destinoDeHermanos[TextFolding.pathKey(padre.raw)],
               Set(ds.map { TextFolding.pathKey($0.raw) }).count == 1 {
                destino = ds[0].appending(p.name)
                motivo += "; va con los demás de su carpeta"
            }
            destino = NombresLibres.limpiar(destino)
            var n = 2
            let pedido = destino
            while ocupadas.contains(TextFolding.pathKey(destino.raw)) {
                let ext = pedido.ext.isEmpty ? "" : "." + (pedido.name.split(separator: ".").last.map(String.init) ?? "")
                destino = (pedido.parent ?? .root).appending("\(pedido.stem)-\(n)\(ext)")
                n += 1
            }
            ocupadas.insert(TextFolding.pathKey(destino.raw))
            nuevos.append(Nuevo(origen: p, destino: destino, sha256: h, motivo: motivo))
        }
        // Leer lo nuevo (hilo protegido: nada se descarga) y comprobar que es lo inventariado.
        let fs = fileSystem
        let paraLeer = nuevos
        let leidos: [(Nuevo, WriteOp?, String?)] = try await DatalessGuard.run("TLSImport.actualizar.leer") { cancel in
            try paraLeer.map { n in
                try cancel.check()
                let data = try fs.contents(of: n.origen.url(in: realURL))
                guard ContentHash.of(data) == n.sha256 else { throw ImportError.cambioDesdeLaVistaPrevia(n.origen.name) }
                if let motivo = ImportApplier.noSePuedeCrear(n.destino, data: data) { return (n, nil, motivo) }
                return (n, .create(n.destino, contents: data), nil)
            }
        }
        // Lo que no se puede traer sale aparte, con su motivo (no cuenta como traído).
        let ops = leidos.compactMap(\.1)
        let noSeTraen = leidos.compactMap { x in x.2.map { (ruta: x.0.origen, motivo: $0) } }
        nuevos = leidos.filter { $0.1 != nil }.map(\.0)
        let plan = ops.isEmpty ? nil : WritePlan(autor: autor, descripcion: "Traer lo nuevo de tu carpeta real (\(ops.count))", ops: ops)
        return ActualizacionDesdeLaReal(nuevos: nuevos, noSeTraen: noSeTraen, distintos: distintos.sorted(), yaEstan: ya,
                                        soloEnICloud: soloEnICloud.sorted(), hashArbolReal: inventarioReal.hashArbol, plan: plan,
                                        real: realURL, exclusiones: exclusiones)
    }

    /// Un fichero de la real que la copia ya ordenó: ¿ha cambiado en la real desde entonces? Con la huella del mapa, se
    /// compara con ella. Sin huella (mapas de antes), con lo que hay en la copia donde fue: igual, o (en una nota) solo
    /// con propiedades añadidas al ordenar y el mismo texto.
    static func cambioDesdeQueSeOrdeno(_ f: FilaMapa, sha: String, copia: URL, enCopia: [String: InventoryEntry],
                                       fs: any FileSystemAccess, real: URL) -> Bool {
        if !f.sha256.isEmpty { return f.sha256 != sha }
        guard let destino = f.rutaDestino, let c = enCopia[TextFolding.pathKey(destino.raw)] else { return false }
        if c.sha256 == sha { return false }
        guard destino.ext == "md" || destino.ext == "markdown" else { return true }
        // Una nota a la que ordenar le añadió propiedades: lo que cuenta es su texto.
        let cuerpo = { (u: URL) -> String? in
            (try? fs.contents(of: u)).flatMap { FrontmatterDocument(data: $0) }.map { $0.body }
        }
        guard let enReal = cuerpo(real), let enLaCopia = cuerpo(destino.url(in: copia)) else { return true }
        return enReal.trimmingCharacters(in: .whitespacesAndNewlines) != enLaCopia.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resultado de aplicar: lo escrito y la comprobación de que la real no ha cambiado.
    public struct Resultado: Sendable {
        public let escritura: WriteResult?
        /// Lo traído está en la copia con el mismo SHA-256.
        public let comprobados: Int
        public let diferencias: [VaultPath]
        /// La real tiene el mismo inventario que al leerla.
        public let realIntacta: Bool
    }

    /// Escribe en la copia (un plan, como persona, que se deshace de una vez) y comprueba la copia y la real.
    public func aplicar(con bus: CommandBus, fileSystem: any FileSystemAccess = LocalFileSystem()) async throws -> Resultado {
        var escritura: WriteResult?
        var comprobados = 0
        var diferencias: [VaultPath] = []
        if let plan {
            let r = try await bus.ejecutar(plan)
            escritura = r
            for (n, p) in r.creadas.enumerated() {
                let esperado = nuevos.first { TextFolding.pathKey($0.destino.raw) == TextFolding.pathKey(p.raw) }?.sha256
                    ?? (n < nuevos.count ? nuevos[n].sha256 : nil)
                let raiz = bus.writer.root
                let actual = try await DatalessGuard.run("TLSImport.actualizar.comprobar") { _ in
                    try? fileSystem.sha256(of: p.url(in: raiz))
                }
                if actual != nil, actual == esperado { comprobados += 1 } else { diferencias.append(p) }
            }
        }
        let despues = try await Inventory.make(of: real, exclusiones: exclusiones, incluirArchivo: false, conHashes: true,
                                               fileSystem: fileSystem)
        return Resultado(escritura: escritura, comprobados: comprobados, diferencias: diferencias,
                         realIntacta: despues.hashArbol == hashArbolReal)
    }
}
