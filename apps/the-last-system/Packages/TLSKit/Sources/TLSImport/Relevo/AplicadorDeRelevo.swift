import Foundation
import TLSCore

/// Lo que quedó tras «Pasar a mi carpeta real».
public struct ResultadoDeRelevo: Sendable {
    /// Planes escritos en la real (uno): «Deshacer» los deshace.
    public let planes: [UUID]
    public let escritura: WriteResult
    /// Cambios de la vista previa comprobados uno a uno (SHA-256).
    public let comprobados: Int
    /// Lo que no cuadra con la vista previa (debe estar vacío).
    public let diferencias: [String]
    /// Recuento de ficheros de la real (sin `Archivo/`) antes, después y el esperado por la vista previa.
    public let recuentoAntes: Int
    public let recuentoDespues: Int
    public let recuentoEsperado: Int
    /// Copia de seguridad previa (en los ajustes de la app, nunca en la carpeta).
    public let respaldo: URL
    /// Nota con las propuestas (no aplicadas) en el Buzón de la real.
    public let notaDePropuestas: VaultPath?
    /// Huella del árbol de la real antes (sin `Archivo/` ni lo privado): «Deshacer» la deja igual.
    public let hashArbolAntes: String
    /// `escritor.json` que había antes (el del fork, si lo había) y el que se puso.
    public let escritorAnterior: Data?
    public let escritorPuesto: Data?
    public let marca: MarcaDeRelevo
    /// Escritor de la real con el que se escribió (para «Deshacer» en esta sesión).
    public let bus: CommandBus

    public var correcto: Bool { diferencias.isEmpty && recuentoDespues == recuentoEsperado }
}

/// Pasos 1 a 7 de «Pasar a mi carpeta real» (PLAN §9 F6), en orden, sobre una vista previa ya preparada:
///
/// 1. confirmación explícita (el nombre de la empresa escrito tal cual);
/// 2. `flock(LOCK_SH|LOCK_NB)` sobre el cerrojo del escritor antiguo (el fork) y comprobación de que ninguna otra
///    ventana tiene la real abierta para escribir; si no, se rechaza sin tocar nada;
/// 3. la vista previa sigue valiendo: la real tiene la misma huella y lo que se lee de la copia, el mismo SHA-256;
///    copia de seguridad completa de lo que se va a tocar (en los ajustes de la app, comprobada con SHA-256);
/// 4. se reclama `escritor.json` (el escritor de la real lo necesita para escribir) y se aplica **un solo plan, como
///    persona, por `CommandBus`**: añadir (`create`, nunca pisa), cambiar (compare-and-swap con la huella de la vista
///    previa; nunca se sobrescribe lo que cambió en la real), archivar (`retire` a `Archivo/Relevo AAAA-MM-DD/`);
///    después, recuento y SHA-256 de todo el árbol;
/// 5. `privado` escrito en `.tls/config.yaml` de la real (en el mismo plan);
/// 6. `vaults.json` pasa a `escritura: permitida` para la real y queda la marca del relevo (`relevo.json`);
/// 7. nota en `Buzón/` con el parche **propuesto** de `validar.py` y los textos de `Empresa.md` y `AGENTS.md` (en el
///    mismo plan; no se aplica nada de lo propuesto).
///
/// «Deshacer» deja la real con su huella de antes, devuelve el `escritor.json` que había y la vuelve a dejar en solo
/// lectura.
public struct AplicadorDeRelevo: Sendable {
    /// Abre el escritor de la carpeta real (con su `CommandBus`). La app lo abre con la entrada de la real; en las
    /// pruebas, con una carpeta sintética.
    public typealias AbrirEscritor = @Sendable (VaultEntry, URL) async throws -> CommandBus

    public struct Entorno: Sendable {
        /// Ajustes de la app (`AppLocations.appSupport`): copia de seguridad, marca del relevo y cerrojos propios.
        public var appSupport: URL
        public var registro: VaultRegistry
        /// Estado del fork (sus cerrojos). Por defecto `~/Library/Application Support/TLS`.
        public var estadoDelFork: URL
        public var app: String
        public var autor: Autor
        public var ahora: @Sendable () -> Date

        public init(appSupport: URL = AppLocations.appSupport, registro: VaultRegistry? = nil,
                    estadoDelFork: URL = CerrojoDelRelevo.estadoDelForkPorDefecto, app: String = VaultWriter.defaultAppName,
                    autor: Autor = .persona("Manu"), ahora: @escaping @Sendable () -> Date = { Date() }) {
            self.appSupport = appSupport
            self.registro = registro ?? VaultRegistry(directory: appSupport)
            self.estadoDelFork = estadoDelFork; self.app = app; self.autor = autor; self.ahora = ahora
        }
    }

    public let entorno: Entorno
    let fs: any FileSystemAccess

    public init(entorno: Entorno, fileSystem: any FileSystemAccess = LocalFileSystem()) {
        self.entorno = entorno
        self.fs = fileSystem
    }

    /// Informe de la copia (`copia-informe.json`): lo que estaba solo en iCloud al copiar no se archiva nunca.
    public static func informeDeLaCopia(appSupport: URL, id: UUID) -> CopyReport? {
        let url = appSupport.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(DemoCopier.reportFileName)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(CopyReport.self, from: data)
    }

    // MARK: Aplicar

    public func aplicar(_ vista: VistaPreviaDeRelevo, confirmacion: ConfirmacionDeRelevo,
                        abrir: AbrirEscritor) async throws -> ResultadoDeRelevo {
        // 1. Confirmación explícita, con el nombre de la empresa de la real.
        guard confirmacion.confirmada,
              ConfirmacionDeRelevo(nombreEmpresa: vista.realEntry.nombre, escrito: confirmacion.escrito).confirmada else {
            throw ErrorDeRelevo.sinConfirmar
        }
        guard vista.hayCambios else { throw ErrorDeRelevo.sinCambios }
        let real = vista.real
        let instalacion = entorno.registro.installationID()

        // 2. Cerrojos: el del fork compartido mientras dure; nadie más escribiendo la real.
        let cerrojo = try CerrojoDelRelevo.tomar(real: real, rutaRegistrada: vista.realEntry.ruta,
                                                 appSupport: entorno.appSupport, estadoDelFork: entorno.estadoDelFork,
                                                 instalacion: instalacion)
        defer { cerrojo.soltar() }

        // 3. La vista previa sigue valiendo (real y copia), y se leen los bytes de la copia.
        let ahora = entorno.ahora()
        let ahoraInv = try await Inventory.make(of: real, exclusiones: vista.exclusionesReal,
                                                incluirArchivo: false, conHashes: true, fileSystem: fs)
        if ahoraInv.hashArbol != vista.hashArbolReal {
            let distinta = vista.inventarioReal.diferencias(con: ahoraInv).first ?? real.lastPathComponent
            throw ErrorDeRelevo.laRealCambio(distinta)
        }
        let efectivos = vista.efectivos
        let copiaURL = vista.copia
        let fs = self.fs
        let bytesCopia: [VaultPath: Data] = try await DatalessGuard.run("TLSImport.relevo.copia") { cancel in
            var out: [VaultPath: Data] = [:]
            for c in efectivos where c.accion != .archivar {
                try cancel.check()
                let d = try fs.contents(of: c.ruta.url(in: copiaURL))
                guard ContentHash.of(d) == c.shaCopia else { throw ErrorDeRelevo.laCopiaCambio(c.ruta.name) }
                out[c.ruta] = d
            }
            return out
        }

        // 3 bis. Copia de seguridad completa de lo que se toca, fuera de la carpeta.
        let stamp = ISO8601DateFormatter().string(from: ahora).replacingOccurrences(of: ":", with: "-")
        let respaldo = RegistroDeRelevo.carpeta(appSupport: entorno.appSupport, real: vista.realEntry.id)
            .appendingPathComponent("relevo", isDirectory: true).appendingPathComponent(stamp, isDirectory: true)
        let config = VaultPath(VaultLayout.configFile)
        let layout = VaultLayout.load(root: real).layout
        let tocadas = efectivos.filter { $0.accion != .anadir }.map(\.ruta) + [config]
        let bytesReal = try await respaldar(tocadas, real: real, en: respaldo, escritor: cerrojo.escritorAnteriorDatos,
                                            vista: vista)

        // 4. Plan único: cambios, `privado` (paso 5) y la nota de propuestas (paso 7).
        let archivo = "Relevo \(vista.hoy.description)"
        var ops: [WriteOp] = []
        for c in efectivos {
            switch c.accion {
            case .anadir:
                ops.append(.create(c.ruta, contents: bytesCopia[c.ruta]!))
            case .cambiar:
                let base = bytesReal[c.ruta]!
                if let nuevo = bytesCopia[c.ruta].flatMap(Self.textoUTF8), let viejo = Self.textoUTF8(base), nuevo.bom == viejo.bom,
                   let op = WriteOp.replaceText(c.ruta, base: base, text: nuevo.texto) {
                    ops.append(op)
                } else {
                    // No es texto: la versión de la real va al Archivo y en su sitio queda la de la copia.
                    ops.append(.retire(c.ruta, apartado: archivo + "/Versiones anteriores"))
                    ops.append(.create(c.ruta, contents: bytesCopia[c.ruta]!))
                }
            case .archivar:
                ops.append(.retire(c.ruta, apartado: archivo))
            }
        }
        if !vista.privado.isEmpty {
            let actual = bytesReal[config].flatMap { TextDecoding.decode($0) }
            guard let nuevo = VaultLayout.configConPrivado(actual, anadir: vista.privado) else {
                throw ErrorDeRelevo.laRealCambio(VaultLayout.configFile)
            }
            if let base = bytesReal[config] {
                if nuevo != actual, let op = WriteOp.replaceText(config, base: base, text: nuevo) { ops.append(op) }
            } else {
                ops.append(.create(config, text: nuevo))
            }
        }
        let nota = VaultPath(layout.buzon ?? "Buzón").appending(PropuestasDelRelevo.nombre(vista.hoy))
        ops.append(.create(nota, text: PropuestasDelRelevo.nota(hoy: vista.hoy, empresa: vista.textoEmpresa,
                                                                 agentes: vista.textoAgentes,
                                                                 soloEnICloud: vista.textosSoloEnICloud)))
        let plan = WritePlan(autor: entorno.autor,
                             descripcion: "Pasar la copia a tu carpeta real (\(vista.anadir) nuevos, \(vista.cambiar) cambiados, \(vista.archivar) archivados)",
                             ops: ops)

        // 4 bis. Reclamar `escritor.json` (si era del fork, se sustituye; queda en la copia de seguridad) y escribir.
        let puesto: Data?
        do {
            try RegistroDeRelevo.reclamarEscritor(root: real, entry: vista.realEntry, instalacion: instalacion,
                                                  app: entorno.app, now: ahora, anterior: cerrojo.escritorAnteriorDatos)
            puesto = RegistroDeRelevo.escritorActual(root: real)
        } catch {
            throw ErrorDeRelevo.escritorIlegible
        }
        let escritura: WriteResult
        let bus: CommandBus
        do {
            bus = try await abrir(vista.realEntry, real)
            escritura = try await bus.ejecutar(plan)
            guard escritura.hecho else {
                throw ErrorDeRelevo.laRealCambio(escritura.conflicto?.ruta.name ?? real.lastPathComponent)
            }
        } catch {
            try? RegistroDeRelevo.restaurarEscritor(root: real, anterior: cerrojo.escritorAnteriorDatos, puesto: puesto,
                                                    apartarEn: respaldo)
            if let e = error as? WriteError, case .cambioExterno(let r) = e { throw ErrorDeRelevo.laRealCambio(r) }
            throw error
        }

        // 4 ter. Comprobar: recuento y SHA-256 contra la vista previa.
        // F6 · integración: `Archivo/` se deja fuera de la copia por tamaño (no por privado); aquí hay que mirarlo, que es
        // donde queda lo archivado (si no, lo archivado nunca se daba por comprobado y la real no pasaba a escribible).
        let claveArchivo = TextFolding.pathKey(layout.archivo)
        let exclusionesDespues = vista.exclusionesReal
            .filter { TextFolding.pathKey($0.raw) != claveArchivo }
        let despues = try await Inventory.make(of: real, exclusiones: exclusionesDespues,
                                               incluirArchivo: true, conHashes: true, fileSystem: fs)
        let comprobacion = Self.comprobar(vista: vista, efectivos: efectivos, escritura: escritura, despues: despues,
                                          extras: [config, nota], archivo: VaultPath(layout.archivo))

        // 6. `vaults.json` y la marca del relevo: «hecho» (y la real escribible) solo si todo cuadra; si no, queda
        // «sin comprobar» para poder deshacerlo, y la real sigue en solo lectura.
        let cuadra = comprobacion.diferencias.isEmpty && comprobacion.despues == comprobacion.esperado
        let marca = MarcaDeRelevo(real_id: vista.realEntry.id.uuidString.lowercased(),
                                  copia_id: vista.copiaEntry.id.uuidString.lowercased(),
                                  fecha: ISO8601DateFormatter().string(from: ahora), estado: cuadra ? .hecho : .sinComprobar,
                                  planes: [escritura.planID.uuidString.lowercased()], respaldo: respaldo.path,
                                  anadidos: vista.anadir, cambiados: vista.cambiar, archivados: vista.archivar,
                                  hash_antes: vista.hashArbolReal)
        try RegistroDeRelevo.guardar(marca, appSupport: entorno.appSupport, real: vista.realEntry.id)
        if cuadra {
            try RegistroDeRelevo.fijarEscritura(.permitida, registro: entorno.registro, real: vista.realEntry.id)
        }
        return ResultadoDeRelevo(planes: [escritura.planID], escritura: escritura, comprobados: comprobacion.comprobados,
                                 diferencias: comprobacion.diferencias, recuentoAntes: comprobacion.antes,
                                 recuentoDespues: comprobacion.despues, recuentoEsperado: comprobacion.esperado,
                                 respaldo: respaldo, notaDePropuestas: escritura.creadas.last { $0.parent == nota.parent && $0.stem.hasPrefix("Propuestas del relevo") },
                                 hashArbolAntes: vista.hashArbolReal, escritorAnterior: cerrojo.escritorAnteriorDatos,
                                 escritorPuesto: puesto, marca: marca, bus: bus)
    }

    /// Texto UTF-8 (con o sin BOM): así el cambio deja exactamente los bytes de la copia.
    static func textoUTF8(_ d: Data) -> (bom: Bool, texto: String)? {
        let bom = d.starts(with: [0xEF, 0xBB, 0xBF])
        guard let t = String(data: bom ? d.dropFirst(3) : d, encoding: .utf8) else { return nil }
        return (bom, t)
    }

    // MARK: Copia de seguridad

    struct Respaldado: Codable {
        var ruta: String
        var sha256: String
    }

    /// Copia en `respaldo/ficheros/` lo que se va a tocar (más `escritor.json` y `vaults.json`), con un índice y su
    /// comprobación por SHA-256. Devuelve los bytes leídos (base de los cambios). Si algo no cuadra, no sigue.
    func respaldar(_ rutas: [VaultPath], real: URL, en respaldo: URL, escritor: Data?,
                   vista: VistaPreviaDeRelevo) async throws -> [VaultPath: Data] {
        let fs = self.fs
        let esperado = Dictionary(vista.efectivos.compactMap { c in c.shaReal.map { (c.ruta, $0) } }, uniquingKeysWith: { a, _ in a })
        let leidos: [VaultPath: Data] = try await DatalessGuard.run("TLSImport.relevo.respaldo") { cancel in
            var out: [VaultPath: Data] = [:]
            for p in rutas {
                try cancel.check()
                let url = p.url(in: real)
                guard fs.fileExists(url) else {
                    if esperado[p] != nil { throw ErrorDeRelevo.laRealCambio(p.name) }
                    continue
                }
                if fs.isDataless(url) || fs.isSymbolicLink(url) { throw ErrorDeRelevo.laRealCambio(p.name) }
                let d = try fs.contents(of: url)
                if let sha = esperado[p], ContentHash.of(d) != sha { throw ErrorDeRelevo.laRealCambio(p.name) }
                out[p] = d
            }
            return out
        }
        do {
            let fm = FileManager.default
            let ficheros = respaldo.appendingPathComponent("ficheros", isDirectory: true)
            try fm.createDirectory(at: ficheros, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var indice: [Respaldado] = []
            for (p, d) in leidos.sorted(by: { $0.key < $1.key }) {
                let destino = Self.rutaEnRespaldo(p, en: ficheros)
                try fm.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
                try d.write(to: destino, options: [.atomic])
                guard let vuelta = fm.contents(atPath: destino.path), ContentHash.of(vuelta) == ContentHash.of(d) else {
                    throw ErrorDeRelevo.respaldoFallido(p.name)
                }
                indice.append(Respaldado(ruta: p.raw, sha256: ContentHash.of(d)))
            }
            if let escritor {
                try escritor.write(to: respaldo.appendingPathComponent("escritor.json.anterior"), options: [.atomic])
            }
            let vaults = entorno.registro.directory.appendingPathComponent("vaults.json")
            if let v = fm.contents(atPath: vaults.path) {
                try v.write(to: respaldo.appendingPathComponent("vaults.json.anterior"), options: [.atomic])
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try enc.encode(indice).write(to: respaldo.appendingPathComponent("indice.json"), options: [.atomic])
            try enc.encode(vista.inventarioReal).write(to: respaldo.appendingPathComponent("inventario-antes.json"),
                                                       options: [.atomic])
        } catch let e as ErrorDeRelevo {
            throw e
        } catch {
            throw ErrorDeRelevo.respaldoFallido(error.localizedDescription)
        }
        return leidos
    }

    /// Ruta dentro del respaldo: `.tls` se guarda como «Ajustes de la carpeta» (visible).
    static func rutaEnRespaldo(_ p: VaultPath, en dir: URL) -> URL {
        let comps = p.components.map { $0 == ".tls" ? "Ajustes de la carpeta" : $0 }
        return comps.reduce(dir) { $0.appendingPathComponent($1) }
    }

    // MARK: Comprobación

    struct Comprobacion {
        var comprobados = 0
        var diferencias: [String] = []
        var antes = 0
        var despues = 0
        var esperado = 0
    }

    /// Lo de después es exactamente lo de antes con los cambios de la vista previa: misma lista de ficheros (sin
    /// `Archivo/`) y mismo SHA-256 en cada uno; lo archivado, en `Archivo/` con su SHA-256 de antes.
    static func comprobar(vista: VistaPreviaDeRelevo, efectivos: [CambioDeRelevo], escritura: WriteResult,
                          despues: Inventory, extras: [VaultPath], archivo: VaultPath) -> Comprobacion {
        var r = Comprobacion()
        func key(_ s: String) -> String { TextFolding.pathKey(s) }
        func enArchivo(_ s: String) -> Bool { let k = key(s), a = key(archivo.raw); return k == a || k.hasPrefix(a + "/") }
        // Esperado: lo de antes (ficheros) con los cambios.
        var esperado: [String: (ruta: String, sha: String?)] = [:]
        for e in vista.inventarioReal.entradas where e.tipo == .fichero { esperado[key(e.ruta)] = (e.ruta, e.sha256) }
        r.antes = esperado.count
        for c in efectivos {
            switch c.accion {
            case .anadir, .cambiar: esperado[key(c.ruta.raw)] = (c.ruta.raw, c.shaCopia)
            case .archivar: esperado[key(c.ruta.raw)] = nil
            }
        }
        // Lo que el plan escribió aparte (ajustes y nota): con la huella que dejó el escritor.
        let escritos = Dictionary(escritura.hashes.map { (key($0.key.raw), $0.value) }, uniquingKeysWith: { a, _ in a })
        for p in extras {
            if let creada = escritura.creadas.first(where: { $0.parent == p.parent && $0.stem.hasPrefix(p.stem) }) {
                esperado[key(creada.raw)] = (creada.raw, escritos[key(creada.raw)])
            } else if let h = escritos[key(p.raw)] {
                esperado[key(p.raw)] = (p.raw, h)
            }
        }
        r.esperado = esperado.count
        var actual: [String: InventoryEntry] = [:]
        for e in despues.entradas where e.tipo == .fichero && !enArchivo(e.ruta) { actual[key(e.ruta)] = e }
        r.despues = actual.count
        for (k, v) in esperado {
            guard let a = actual[k] else { r.diferencias.append("falta \(v.ruta)"); continue }
            if a.sha256 != v.sha { r.diferencias.append("distinto \(v.ruta)") }
        }
        for (k, a) in actual where esperado[k] == nil { r.diferencias.append("sobra \(a.ruta)") }
        // Cada cambio, uno a uno.
        var porArchivo: [String: String] = [:]
        for e in despues.entradas where e.tipo == .fichero && enArchivo(e.ruta) { if let h = e.sha256 { porArchivo[key(e.ruta)] = h } }
        for c in efectivos {
            switch c.accion {
            case .anadir, .cambiar:
                if let a = actual[key(c.ruta.raw)], a.sha256 == c.shaCopia { r.comprobados += 1 }
            case .archivar:
                if let m = escritura.movidas.first(where: { key($0.de.raw) == key(c.ruta.raw) }),
                   porArchivo[key(m.a.raw)] == c.shaReal, actual[key(c.ruta.raw)] == nil {
                    r.comprobados += 1
                } else {
                    r.diferencias.append("no archivado \(c.ruta.raw)")
                }
            }
        }
        r.diferencias.sort()
        return r
    }

    // MARK: Deshacer

    /// F6 · corrector (P1-3): el último relevo de esa carpeta real, si aún está en pie («hecho» o «sin comprobar»).
    public static func ultimoRelevo(appSupport: URL, real id: UUID) -> MarcaDeRelevo? {
        guard let m = RegistroDeRelevo.leer(appSupport: appSupport, real: id), m.estado != .deshecho else { return nil }
        return m
    }

    /// F6 · corrector (P1-3): «Deshacer el último relevo» desde Ajustes, también después de cerrar la hoja o la app. Usa
    /// la marca (`relevo.json`) y la copia de seguridad: deshace el plan del relevo (si nada se ha escrito después en la
    /// real), devuelve el `escritor.json` que había, deja la real en solo lectura y marca el relevo como deshecho.
    /// `bus`: el escritor de la real (con su diario de cambios en los ajustes de la app). Devuelve si la real quedó con su
    /// huella de antes.
    @discardableResult
    public func deshacerUltimo(real: VaultEntry, root: URL, con bus: CommandBus) async throws -> Bool {
        guard var marca = Self.ultimoRelevo(appSupport: entorno.appSupport, real: real.id) else {
            throw ErrorDeRelevo.deshacerNoDisponible
        }
        let planes = marca.planes.compactMap { UUID(uuidString: $0) }
        guard await ImportApplier.sePuedeDeshacer(planes: planes, con: bus) else { throw ErrorDeRelevo.deshacerNoDisponible }
        do {
            try await ImportApplier.deshacer(planes: planes, con: bus, autor: entorno.autor)
        } catch {
            throw ErrorDeRelevo.deshacerNoDisponible
        }
        let respaldo = URL(fileURLWithPath: marca.respaldo, isDirectory: true)
        let anterior = FileManager.default.contents(atPath: respaldo.appendingPathComponent("escritor.json.anterior").path)
        try RegistroDeRelevo.restaurarEscritor(root: root, anterior: anterior, puesto: RegistroDeRelevo.escritorActual(root: root),
                                               apartarEn: respaldo)
        try RegistroDeRelevo.fijarEscritura(.bloqueada, registro: entorno.registro, real: real.id)
        marca.estado = .deshecho
        try RegistroDeRelevo.guardar(marca, appSupport: entorno.appSupport, real: real.id)
        // La misma foto que la vista previa: sin lo dejado fuera de la copia ni lo que la copia declara privado.
        var exclusiones: [VaultPath] = []
        if let copia = entorno.registro.load().first(where: { $0.id.uuidString.lowercased() == marca.copia_id }) {
            exclusiones = copia.exclusionesCopia.map { VaultPath($0) }
            let raizCopia = entorno.registro.resolveURL(copia) ?? URL(fileURLWithPath: copia.ruta, isDirectory: true)
            exclusiones += ((try? VaultLayout.declaredPrivado(root: raizCopia)) ?? []).filter { !$0.isRoot }
        }
        let ahora = try await Inventory.make(of: root, exclusiones: PlanDeRelevo.sinRepetir(exclusiones), incluirArchivo: false,
                                             conHashes: true, fileSystem: fs)
        return ahora.hashArbol == marca.hash_antes
    }

    /// Deshace el relevo: el plan (la real vuelve a su huella de antes; lo creado va a `Archivo/`), el `escritor.json`
    /// que había (o se aparta el del relevo), la real vuelve a solo lectura y la marca queda como deshecha.
    /// Devuelve si la real quedó con su huella de antes.
    @discardableResult
    public func deshacer(_ r: ResultadoDeRelevo, vista: VistaPreviaDeRelevo, con bus: CommandBus) async throws -> Bool {
        guard await ImportApplier.sePuedeDeshacer(planes: r.planes, con: bus) else { throw ErrorDeRelevo.deshacerNoDisponible }
        do {
            try await ImportApplier.deshacer(planes: r.planes, con: bus, autor: entorno.autor)
        } catch {
            throw ErrorDeRelevo.deshacerNoDisponible
        }
        await bus.writer.close()
        try RegistroDeRelevo.restaurarEscritor(root: vista.real, anterior: r.escritorAnterior, puesto: r.escritorPuesto,
                                               apartarEn: r.respaldo)
        try RegistroDeRelevo.fijarEscritura(.bloqueada, registro: entorno.registro, real: vista.realEntry.id)
        var marca = r.marca
        marca.estado = .deshecho
        try RegistroDeRelevo.guardar(marca, appSupport: entorno.appSupport, real: vista.realEntry.id)
        let ahora = try await Inventory.make(of: vista.real, exclusiones: vista.exclusionesReal,
                                             incluirArchivo: false, conHashes: true, fileSystem: fs)
        return ahora.hashArbol == r.hashArbolAntes
    }
}
