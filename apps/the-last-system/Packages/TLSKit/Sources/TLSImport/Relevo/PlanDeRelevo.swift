import Foundation
import TLSCore

/// Un fichero que el relevo cambia en la carpeta real.
public struct CambioDeRelevo: Sendable, Hashable {
    public enum Accion: String, Sendable, Hashable, Codable {
        /// Está en la copia y no en la real: se crea.
        case anadir
        /// Está en las dos con otro contenido y la real no ha cambiado desde la copia: se pone el de la copia.
        case cambiar
        /// Estaba en la real cuando se hizo la copia y en la copia ya no está (se retiró o se movió): va a `Archivo/`.
        case archivar
    }

    public let ruta: VaultPath
    public let accion: Accion
    /// SHA-256 de lo que se pone (añadir y cambiar).
    public let shaCopia: String?
    /// SHA-256 de lo que hay en la real (cambiar y archivar): se comprueba antes de escribir.
    public let shaReal: String?
    public let motivo: String
}

/// Un fichero que cambió en la real después de hacer la copia y que la copia también tocó. Por defecto se queda la real.
public struct ConflictoDeRelevo: Sendable, Hashable {
    public enum Tipo: String, Sendable, Hashable {
        /// Cambió en las dos.
        case cambiaronLasDos
        /// Cambió en la real y en la copia se quitó.
        case laCopiaLoQuito
    }

    public enum Eleccion: String, Sendable, Hashable, Codable {
        case quedarseConLaReal
        case quedarseConLaCopia
    }

    public let ruta: VaultPath
    public let tipo: Tipo
    public let shaReal: String
    public let shaCopia: String?

    /// Lo que se hace si se elige la copia.
    public var siSeEligeLaCopia: CambioDeRelevo {
        switch tipo {
        case .cambiaronLasDos:
            CambioDeRelevo(ruta: ruta, accion: .cambiar, shaCopia: shaCopia, shaReal: shaReal,
                           motivo: "Cambió en las dos; elegiste la copia")
        case .laCopiaLoQuito:
            CambioDeRelevo(ruta: ruta, accion: .archivar, shaCopia: nil, shaReal: shaReal,
                           motivo: "Cambió en la real y en la copia se quitó; elegiste la copia")
        }
    }

    public var explicacion: String {
        switch tipo {
        case .cambiaronLasDos: "Ha cambiado en tu carpeta real después de hacer la copia, y en la copia también."
        case .laCopiaLoQuito: "Ha cambiado en tu carpeta real después de hacer la copia, y en la copia se quitó."
        }
    }
}

/// Vista previa de «Pasar a mi carpeta real» (paso 3): qué se añade, qué cambia, qué se archiva y los conflictos. **No
/// se borra nada.** Prepararla solo lee las dos carpetas (sin lo privado y sin descargar nada de iCloud).
public struct VistaPreviaDeRelevo: Sendable {
    public let real: URL
    public let copia: URL
    public let realEntry: VaultEntry
    public let copiaEntry: VaultEntry
    public let hoy: LocalDate
    /// Lo que se hace sin dudas.
    public let cambios: [CambioDeRelevo]
    /// Lo que cambió en la real desde la copia. Por defecto, se queda la real (`elecciones`).
    public let conflictos: [ConflictoDeRelevo]
    public private(set) var elecciones: [VaultPath: ConflictoDeRelevo.Eleccion]
    /// Solo en iCloud en la real: se ven por su nombre y no se tocan (habría que descargarlos).
    public let soloEnICloud: [VaultPath]
    /// Nuevos en la real después de la copia (y que la copia no tiene): se quedan como están.
    public let nuevosEnLaReal: [VaultPath]
    /// Cambiaron solo en la real: se quedan como están.
    public let soloCambiaronEnLaReal: [VaultPath]
    /// La real los quitó después de hacer la copia y la copia no los tocó: no se vuelven a poner.
    public let quitadosEnLaReal: [VaultPath]
    /// De la copia, dentro de algo privado o dejado fuera en la real: nunca se pasan.
    public let noSePasan: [VaultPath]
    /// Iguales en las dos.
    public let iguales: Int
    /// Carpetas privadas que quedan declaradas en `privado` de la real (paso 5).
    public let privado: [VaultPath]
    /// Lo que nunca se toca en la real (lo privado de las dos y lo que se dejó fuera de la copia).
    public let protegidas: [VaultPath]
    /// Lo que no se lee de la real al hacer su foto (lo dejado fuera de la copia y lo que la copia declara privado). La
    /// usan igual la comprobación de antes de escribir, la de después y «Deshacer».
    public let exclusionesReal: [VaultPath]
    /// Foto de la real al prepararla (sin `Archivo/`, sin lo privado): «Deshacer» la deja con esta huella.
    public let inventarioReal: Inventory
    /// Textos actuales de `Empresa.md` y `AGENTS.md` de la real (para la nota de propuestas).
    public let textoEmpresa: String?
    public let textoAgentes: String?
    public let textosSoloEnICloud: [String]
    /// Huellas de lo que se lee de la copia (se comprueban otra vez al aplicar).
    let shaCopia: [String: String]

    public var hashArbolReal: String { inventarioReal.hashArbol }

    /// Elegir en un conflicto (por defecto, la real).
    public mutating func elegir(_ e: ConflictoDeRelevo.Eleccion, para ruta: VaultPath) {
        guard conflictos.contains(where: { $0.ruta == ruta }) else { return }
        elecciones[ruta] = e
    }

    public func eleccion(_ ruta: VaultPath) -> ConflictoDeRelevo.Eleccion {
        elecciones[ruta] ?? .quedarseConLaReal
    }

    /// Lo que se va a hacer de verdad: los cambios más los conflictos en los que se eligió la copia.
    public var efectivos: [CambioDeRelevo] {
        (cambios + conflictos.filter { eleccion($0.ruta) == .quedarseConLaCopia }.map(\.siSeEligeLaCopia))
            .sorted { $0.ruta < $1.ruta }
    }

    public var anadir: Int { efectivos.filter { $0.accion == .anadir }.count }
    public var cambiar: Int { efectivos.filter { $0.accion == .cambiar }.count }
    public var archivar: Int { efectivos.filter { $0.accion == .archivar }.count }

    public var hayCambios: Bool { !efectivos.isEmpty }

    /// «Añadir 3 · Cambiar 2 · Archivar 1 · 1 conflicto: se queda la real · No se borra nada».
    public var resumen: String {
        var s = "Añadir \(anadir) · Cambiar \(cambiar) · Archivar \(archivar)"
        let real = conflictos.filter { eleccion($0.ruta) == .quedarseConLaReal }.count
        if !conflictos.isEmpty {
            s += " · " + (conflictos.count == 1 ? "1 conflicto" : "\(conflictos.count) conflictos")
            if real > 0 { s += real == conflictos.count ? ": se queda la real" : " (\(real) con la real)" }
        }
        if !soloEnICloud.isEmpty { s += " · \(soloEnICloud.count) solo en iCloud, no se tocan" }
        return s + " · No se borra nada"
    }

    /// Texto literal de la confirmación (con el nombre de la empresa de la real).
    public var textoDeConfirmacion: String {
        TextosDelRelevo.confirmacion(empresa: realEntry.nombre, anadir: anadir, cambiar: cambiar, archivar: archivar,
                                     conflictos: conflictos.count, privado: privado.count, propuestas: true)
    }
}

/// Paso 3 del relevo (PLAN §9 F6): compara la copia con la real. Solo lee.
///
/// La referencia es la fecha de la copia (`VaultEntry.creada`): la copia conserva la fecha de modificación de cada
/// fichero (`DemoCopier`), así que
/// - un fichero de la real modificado después de esa fecha «cambió en la real desde la copia»;
/// - uno de la copia modificado después «cambió en la copia».
///
/// Con eso:
/// - en las dos e iguales → nada; distintos y la real sin cambios → **cambiar**; la real cambió y la copia también →
///   **conflicto** (se queda la real por defecto); solo cambió la real → se queda;
/// - solo en la copia y cambiado en la copia (nuevo, editado o movido a otro sitio) → **añadir**; solo en la copia y sin
///   tocar → la real lo quitó después: no se vuelve a poner (salvo que sea un movimiento hecho en la copia: su contenido
///   sigue en la real en otra ruta que la copia ya no tiene);
/// - solo en la real y anterior a la copia → **archivar** (la copia lo retiró o lo movió); posterior → nuevo en la real,
///   se queda; si cambió en la real y la copia lo quitó → **conflicto**.
///
/// Nunca entra en lo privado de la real ni en lo que se dejó fuera de la copia, ni en `Archivo/`, `.tls/` u otros
/// ocultos. Lo que está solo en iCloud se trata por su nombre y no se toca.
public enum PlanDeRelevo {
    public static func preparar(copia: URL, copiaEntry: VaultEntry, real: URL, realEntry: VaultEntry, hoy: LocalDate,
                                informeCopia: CopyReport? = nil,
                                fileSystem: any FileSystemAccess = LocalFileSystem()) async throws -> VistaPreviaDeRelevo {
        let realURL = real.standardizedFileURL.resolvingSymlinksInPath()
        let copiaURL = copia.standardizedFileURL.resolvingSymlinksInPath()
        guard !CopyJob.isInside(copiaURL, realURL), !CopyJob.isInside(realURL, copiaURL) else {
            throw ImportError.fuenteDentroDeLaCarpeta(realURL.lastPathComponent)
        }
        guard case .disponible(let r) = DisponibilidadDelRelevo.evaluar(copiaEntry, registradas: [copiaEntry, realEntry]),
              r.id == realEntry.id else {
            throw ErrorDeRelevo.noDisponible(
                DisponibilidadDelRelevo.evaluar(copiaEntry, registradas: [copiaEntry, realEntry]).motivo ?? "")
        }
        // Lo que nunca se toca en la real: lo que se dejó fuera de la copia (sin `Archivo`, que ya queda fuera) y lo que
        // la real declara privado (lo poda el inventario).
        let dejadoFuera = copiaEntry.exclusionesCopia.map { VaultPath($0) }
        let privadoReal = try await DatalessGuard.run("TLSImport.relevo.privado") { _ in
            try VaultLayout.declaredPrivado(root: realURL)
        }
        // S10: lo que Manu marcó privado en la copia también es privado en la real (ni se lee, ni se archiva, y queda
        // declarado en la real en el paso 5).
        let privadoCopia = ((try? VaultLayout.declaredPrivado(root: copiaURL)) ?? []).filter { !$0.isRoot }
        let protegidas = (dejadoFuera + privadoReal + privadoCopia).filter { !$0.isRoot }
        let exclusionesReal = Self.sinRepetir(dejadoFuera + privadoCopia)
        let inventarioReal = try await Inventory.make(of: realURL, exclusiones: exclusionesReal, incluirArchivo: false,
                                                      conHashes: true, fileSystem: fileSystem)
        let inventarioCopia = try await Inventory.make(of: copiaURL, exclusiones: [], incluirArchivo: false,
                                                       conHashes: true, fileSystem: fileSystem)
        let referencia = copiaEntry.creada
        let nuncaCopiados = Set(((informeCopia?.soloEnICloud ?? []) + (informeCopia?.enlacesOmitidos ?? []))
            .map { TextFolding.pathKey($0) })

        func visible(_ e: InventoryEntry) -> Bool {
            e.tipo == .fichero && !VaultPath(e.ruta).components.contains(where: { $0.hasPrefix(".") })
        }
        func protegida(_ p: VaultPath) -> Bool {
            let k = TextFolding.pathKey(p.raw)
            return protegidas.contains { let d = TextFolding.pathKey($0.raw); return k == d || k.hasPrefix(d + "/") }
        }
        func modificado(_ raiz: URL, _ p: VaultPath) -> Date? {
            UbiquityInspector.info(p.url(in: raiz))?.modified
        }
        func posterior(_ d: Date?) -> Bool { (d ?? .distantPast) > referencia }
        // S11: la línea base de la copia (SHA-256 de la real al copiar). Con ella se decide por contenido; sin ella
        // (copias anteriores), por fechas.
        let base: [String: String]? = informeCopia?.huellas.map {
            Dictionary($0.map { (TextFolding.pathKey($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        }
        func cambioEnLaReal(_ k: String, _ p: VaultPath, sha: String) -> Bool {
            if let base { return base[k] != sha }
            return posterior(modificado(realURL, p))
        }
        func cambioEnLaCopia(_ k: String, _ p: VaultPath, sha: String) -> Bool {
            if let base { return base[k] != sha }
            return posterior(modificado(copiaURL, p))
        }

        var enReal: [String: InventoryEntry] = [:]
        var shaEnReal: [String: [String]] = [:]
        for e in inventarioReal.entradas where visible(e) {
            let k = TextFolding.pathKey(e.ruta)
            enReal[k] = e
            if let h = e.sha256 { shaEnReal[h, default: []].append(k) }
        }
        var enCopia: [String: InventoryEntry] = [:]
        for e in inventarioCopia.entradas where visible(e) { enCopia[TextFolding.pathKey(e.ruta)] = e }

        var cambios: [CambioDeRelevo] = []
        var conflictos: [ConflictoDeRelevo] = []
        var soloEnICloud: [VaultPath] = []
        var nuevosEnLaReal: [VaultPath] = []
        var soloReal: [VaultPath] = []
        var quitados: [VaultPath] = []
        var noSePasan: [VaultPath] = []
        var iguales = 0
        var shaCopia: [String: String] = [:]

        // Lo de la copia.
        for (k, c) in enCopia {
            let p = VaultPath(c.ruta)
            if protegida(p) { noSePasan.append(p); continue }
            guard let hc = c.sha256, !c.dataless else { noSePasan.append(p); continue }
            shaCopia[k] = hc
            let copiaCambio = cambioEnLaCopia(k, p, sha: hc)
            if let r = enReal[k] {
                let pr = VaultPath(r.ruta)
                if r.dataless { soloEnICloud.append(pr); continue }
                guard let hr = r.sha256 else { continue }
                if hr == hc { iguales += 1; continue }
                let realCambio = cambioEnLaReal(k, pr, sha: hr)
                switch (realCambio, copiaCambio) {
                case (false, _):
                    cambios.append(CambioDeRelevo(ruta: pr, accion: .cambiar, shaCopia: hc, shaReal: hr,
                                                  motivo: "Lo cambiaste en la copia"))
                case (true, true):
                    conflictos.append(ConflictoDeRelevo(ruta: pr, tipo: .cambiaronLasDos, shaReal: hr, shaCopia: hc))
                case (true, false):
                    soloReal.append(pr)
                }
                continue
            }
            if copiaCambio {
                cambios.append(CambioDeRelevo(ruta: p, accion: .anadir, shaCopia: hc, shaReal: nil,
                                              motivo: "Es nuevo en la copia"))
            } else if let otras = shaEnReal[hc], otras.contains(where: { enCopia[$0] == nil }) {
                // Movido en la copia: su contenido sigue en la real en una ruta que la copia ya no tiene (esa se archiva).
                cambios.append(CambioDeRelevo(ruta: p, accion: .anadir, shaCopia: hc, shaReal: nil,
                                              motivo: "Lo cambiaste de sitio en la copia"))
            } else {
                quitados.append(p)
            }
        }
        // Lo que solo está en la real.
        for (k, r) in enReal where enCopia[k] == nil {
            let p = VaultPath(r.ruta)
            if protegida(p) { continue }
            if r.dataless { soloEnICloud.append(p); continue }
            if nuncaCopiados.contains(k) { nuevosEnLaReal.append(p); continue }
            guard let hr = r.sha256 else { continue }
            if let base, base[k] == nil {
                // No estaba al hacer la copia: es nuevo en la real y se queda.
                nuevosEnLaReal.append(p)
            } else if cambioEnLaReal(k, p, sha: hr) {
                // ¿Lo tenía la copia al hacerse? Con la línea base, sí (está en ella); sin ella, solo se sabe por la fecha
                // de creación del fichero: si existía antes de la copia, la copia lo quitó.
                let nacio = (try? p.url(in: realURL).resourceValues(forKeys: [.creationDateKey]).creationDate) ?? nil
                if base != nil || (nacio.map { $0 <= referencia } ?? false) {
                    conflictos.append(ConflictoDeRelevo(ruta: p, tipo: .laCopiaLoQuito, shaReal: hr, shaCopia: nil))
                } else {
                    nuevosEnLaReal.append(p)
                }
            } else {
                cambios.append(CambioDeRelevo(ruta: p, accion: .archivar, shaCopia: nil, shaReal: hr,
                                              motivo: "En la copia se retiró o se cambió de sitio"))
            }
        }

        // Paso 5: lo privado de la copia (lo que se dejó fuera y lo que se marcó privado en ella) queda declarado en la
        // real, si existe allí y aún no lo está.
        let yaPrivadoEnReal = Set(privadoReal.map { TextFolding.pathKey($0.raw) })
        let privado = Self.sinRepetir(copiaEntry.carpetasPrivadasDeLaCopia.map { VaultPath($0) } + privadoCopia)
            .filter { !yaPrivadoEnReal.contains(TextFolding.pathKey($0.raw)) }
            .filter { FileManager.default.fileExists(atPath: $0.url(in: realURL).path) }

        // Textos para la nota de propuestas (sin descargar nada).
        var textosICloud: [String] = []
        let fs = fileSystem
        let leidos: [String: String] = try await DatalessGuard.run("TLSImport.relevo.textos") { _ in
            var out: [String: String] = [:]
            for nombre in ["Empresa.md", "AGENTS.md"] {
                let url = realURL.appendingPathComponent(nombre)
                guard fs.fileExists(url), !fs.isSymbolicLink(url) else { continue }
                if fs.isDataless(url) { out[nombre] = "\u{0}icloud"; continue }
                if let d = try? fs.contents(of: url), let t = TextDecoding.decode(d) { out[nombre] = TextDecoding.strippingBOM(t) }
            }
            return out
        }
        for (n, t) in leidos where t == "\u{0}icloud" { textosICloud.append(n) }
        func texto(_ n: String) -> String? { leidos[n].flatMap { $0 == "\u{0}icloud" ? nil : $0 } }

        return VistaPreviaDeRelevo(
            real: realURL, copia: copiaURL, realEntry: realEntry, copiaEntry: copiaEntry, hoy: hoy,
            cambios: cambios.sorted { $0.ruta < $1.ruta }, conflictos: conflictos.sorted { $0.ruta < $1.ruta },
            elecciones: [:], soloEnICloud: soloEnICloud.sorted(), nuevosEnLaReal: nuevosEnLaReal.sorted(),
            soloCambiaronEnLaReal: soloReal.sorted(), quitadosEnLaReal: quitados.sorted(), noSePasan: noSePasan.sorted(),
            iguales: iguales, privado: privado, protegidas: protegidas, exclusionesReal: exclusionesReal,
            inventarioReal: inventarioReal,
            textoEmpresa: texto("Empresa.md"), textoAgentes: texto("AGENTS.md"), textosSoloEnICloud: textosICloud.sorted(),
            shaCopia: shaCopia)
    }
}

extension PlanDeRelevo {
    /// Sin repetir (comparando como el sistema de ficheros), en el orden de llegada.
    static func sinRepetir(_ rutas: [VaultPath]) -> [VaultPath] {
        var vistos: Set<String> = []
        return rutas.filter { vistos.insert(TextFolding.pathKey($0.raw)).inserted }
    }
}

extension DisponibilidadDelRelevo {
    var motivo: String? {
        if case .oculto(let m) = self { return m }
        return nil
    }
}
