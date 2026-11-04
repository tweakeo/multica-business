import Foundation
import TLSCore

/// Opciones de una copia de trabajo de una carpeta de empresa.
public struct CopyOptions: Sendable, Hashable {
    /// Rutas relativas que NO se copian ni se listan (la carpeta privada que elige la persona).
    public var exclusiones: [VaultPath]
    /// `Archivo/` se excluye por defecto: escanearlo descargó ~10.000 ficheros de iCloud.
    public var incluirArchivo: Bool
    /// Nombre visible de la copia (por defecto «<origen> (copia AAAA-MM-DD)»).
    public var nombre: String?

    public init(exclusiones: [VaultPath], incluirArchivo: Bool = false, nombre: String? = nil) {
        self.exclusiones = exclusiones; self.incluirArchivo = incluirArchivo; self.nombre = nombre
    }

    /// Exclusiones que se aplican siempre, además de las de la persona.
    /// Con «/», ruta desde la raíz; sin «/», nombre a cualquier profundidad.
    public static let siempre: [String] = [".tls/escritor.json", ".DS_Store", ".obsidian/workspace.json"]
}

public struct CopyProgress: Sendable {
    public enum Fase: String, Sendable { case inventario, copia, verificacion, terminado }
    public let fase: Fase
    public let hechos: Int
    public let total: Int?
    public init(fase: Fase, hechos: Int, total: Int?) { self.fase = fase; self.hechos = hechos; self.total = total }
}

/// Resultado de la copia. Se guarda también en AppLocations.vaultState(id)/copia-informe.json.
public struct CopyReport: Sendable, Codable {
    public let vaultID: UUID
    public let destino: String
    public let copiados: Int
    public let bytes: Int64
    /// Solo en iCloud: no se copian para no descargar nada. La interfaz los explica.
    public let soloEnICloud: [String]
    public let verificados: Int
    /// Rutas cuyo SHA-256 no coincide tras copiar (debe ser 0).
    public let diferencias: [String]
    public let exclusiones: [String]
    public let fecha: Date
    /// Enlaces simbólicos del origen: no se siguen ni se copian (podrían apuntar a la carpeta real).
    public var enlacesOmitidos: [String] = []
    /// Línea base del relevo (S11): SHA-256 de cada fichero del origen al copiarlo (ruta → huella). Con ella, «cambió en
    /// la real desde la copia» se decide por contenido y no por fechas. `nil` en informes anteriores.
    public var huellas: [String: String]?

    public init(vaultID: UUID, destino: String, copiados: Int, bytes: Int64, soloEnICloud: [String],
                verificados: Int, diferencias: [String], exclusiones: [String], fecha: Date) {
        self.vaultID = vaultID; self.destino = destino; self.copiados = copiados; self.bytes = bytes
        self.soloEnICloud = soloEnICloud; self.verificados = verificados; self.diferencias = diferencias
        self.exclusiones = exclusiones; self.fecha = fecha
    }
}

extension CopyReport {
    /// El identificador va en minúsculas, como en `vaults.json` y en el nombre de la carpeta de estado.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(vaultID.uuidString.lowercased(), forKey: .vaultID)
        try c.encode(destino, forKey: .destino)
        try c.encode(copiados, forKey: .copiados)
        try c.encode(bytes, forKey: .bytes)
        try c.encode(soloEnICloud, forKey: .soloEnICloud)
        try c.encode(verificados, forKey: .verificados)
        try c.encode(diferencias, forKey: .diferencias)
        try c.encode(exclusiones, forKey: .exclusiones)
        try c.encode(fecha, forKey: .fecha)
        try c.encode(enlacesOmitidos, forKey: .enlacesOmitidos)
        try c.encodeIfPresent(huellas, forKey: .huellas)
    }
}

public enum CopyError: Error, LocalizedError, Sendable {
    case origenNoAccesible(String)
    case destinoExiste(String)
    case verificacionFallida(Int)

    public var errorDescription: String? {
        switch self {
        case .origenNoAccesible(let p): "No puedo leer la carpeta de origen (\(p)). Revisa el permiso en Ajustes del Sistema › Privacidad y seguridad."
        case .destinoExiste(let p): "Ya existe una copia en \(p)."
        case .verificacionFallida(let n): "\(n) archivos no coinciden con el original. La copia no se ha registrado."
        }
    }
}

/// Problemas que impiden empezar una copia y que `CopyError` no recoge (ampliación de F0).
public enum CopyGuardError: Error, LocalizedError, Sendable {
    /// No se pudo activar la protección que evita descargar de iCloud.
    case proteccionICloud
    /// La carpeta de destino quedaría dentro de la de origen.
    case destinoDentroDelOrigen(String)
    /// Una exclusión no coincide con nada del origen (¿errata?). Se para para no copiar lo privado por error.
    case exclusionNoEncontrada(String)
    /// La carpeta declara privada una ruta que no existe (¿se movió o cambió de nombre?).
    case privadoNoEncontrado(String)
    /// No se puede saber qué declara privado la carpeta (sus ajustes están solo en iCloud o dañados).
    case privadoIlegible

    public var errorDescription: String? {
        switch self {
        case .proteccionICloud:
            "No he podido activar la protección que evita descargar archivos de iCloud, así que no he copiado nada."
        case .destinoDentroDelOrigen(let p):
            "La copia no puede ir dentro de la carpeta de tu empresa (\(p)). Elige otro sitio."
        case .exclusionNoEncontrada(let p):
            "No encuentro «\(p)» en la carpeta de tu empresa. Para no copiar nada privado por error, no he hecho la copia. Revisa el nombre."
        case .privadoNoEncontrado(let p):
            "Tu carpeta marca «\(p)» como privada, pero no la encuentro. Para no copiar nada privado por error, no he hecho la copia. Comprueba si la has movido o le has cambiado el nombre."
        case .privadoIlegible:
            "No he podido leer qué carpetas marca como privadas tu carpeta (puede que esa parte esté solo en iCloud). Para no copiar nada privado por error, no he hecho la copia."
        }
    }
}

/// Copia de trabajo de una carpeta de empresa, sin tocar el origen y sin descargar nada de iCloud.
///
/// Contrato:
/// - nunca lista ni entra en una ruta excluida (se poda ANTES de descender);
/// - el origen no cambia (inventario idéntico antes y después) y no se descarga nada;
/// - SHA-256 del destino igual al del origen en cada fichero copiado;
/// - escribe `.tls/config.yaml` de la copia con `clase: copia`, un `id` nuevo y `origen`;
/// - no copia `.tls/escritor.json`.
public struct DemoCopier: Sendable {
    public init(fileSystem: any FileSystemAccess = LocalFileSystem()) {
        self.fs = fileSystem
        self.appSupport = nil
    }

    /// Igual, pero con el estado técnico (informe) en `appSupport` en vez de `AppLocations.appSupport`.
    public init(fileSystem: any FileSystemAccess = LocalFileSystem(), appSupport: URL) {
        self.fs = fileSystem
        self.appSupport = appSupport
    }

    let fs: any FileSystemAccess
    let appSupport: URL?

    /// Nombre del informe dentro del estado de la carpeta.
    public static let reportFileName = "copia-informe.json"

    /// Carpeta de estado de una copia (la misma regla que `AppLocations.vaultState`).
    public func stateDirectory(for id: UUID) -> URL {
        guard let appSupport else { return AppLocations.vaultState(id) }
        return appSupport.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    /// Copia `origen` a una carpeta nueva dentro de `empresas` y devuelve el informe y la entrada a registrar.
    public func copy(from origen: URL, into empresas: URL = AppLocations.empresas, options: CopyOptions,
                     progress: @escaping @Sendable (CopyProgress) -> Void) async throws -> (CopyReport, VaultEntry) {
        let id = UUID()
        let now = Date()
        let job = CopyJob(fs: fs, id: id, now: now, stateDirectory: stateDirectory(for: id), progress: progress)
        let result = try await DatalessGuard.run("TLSImport.copia") { cancel in
            try job.run(origen: origen, empresas: empresas, options: options, cancel: cancel)
        }
        let bookmark = try? VaultRegistry.makeBookmark(for: result.destino)
        let entry = VaultEntry(id: id, nombre: result.destino.lastPathComponent, ruta: result.destino.path,
                               bookmark: bookmark, clase: .copia, escritura: WritePolicy.escrituraInicial(para: .copia),
                               exclusionesCopia: result.report.exclusiones, origen: result.origen.path,
                               creada: now)
        progress(CopyProgress(fase: .terminado, hechos: result.report.copiados, total: result.report.copiados))
        return (result.report, entry)
    }
}

/// Una copia concreta. Todo `run` corre en el hilo protegido, sin `await`.
struct CopyJob: Sendable {
    let fs: any FileSystemAccess
    let id: UUID
    let now: Date
    let stateDirectory: URL
    let progress: @Sendable (CopyProgress) -> Void

    struct Result: Sendable {
        let report: CopyReport
        let origen: URL
        let destino: URL
    }

    private struct Copied {
        let path: VaultPath
        let src: URL
        let dst: URL
        let sha256: String
    }

    /// Cada cuántas entradas se avisa del progreso.
    static let progressStep = 50
    static let configPath = VaultPath(".tls/config.yaml")

    func run(origen rawOrigen: URL, empresas rawEmpresas: URL, options: CopyOptions,
             cancel: CancelFlag) throws -> Result {
        let origen = rawOrigen.standardizedFileURL.resolvingSymlinksInPath()
        guard fs.isDirectory(origen), !fs.isDataless(origen) else {
            throw CopyError.origenNoAccesible(rawOrigen.path)
        }
        let empresas = rawEmpresas.standardizedFileURL.resolvingSymlinksInPath()
        if Self.isInside(empresas, origen) {
            throw CopyGuardError.destinoDentroDelOrigen(empresas.path)
        }

        // 1. Reglas: persona + privado (leído con el núcleo) + siempre + Archivo. El config.yaml del
        //    origen se sustituye por el de la copia.
        let plan = try CopyExclusions.make(origen: origen, personales: options.exclusiones,
                                           incluirArchivo: options.incluirArchivo, fs: fs)
        var copyRules = plan.rules
        copyRules.add(Self.configPath)

        // 2. Inventario con poda.
        var items: [WalkItem] = []
        let pruned: [VaultPath]
        do {
            pruned = try TreeWalker(fs: fs, rules: copyRules).walk(root: origen, cancel: cancel) { item in
                items.append(item)
                if items.count % Self.progressStep == 0 {
                    progress(CopyProgress(fase: .inventario, hechos: items.count, total: nil))
                }
            }
        } catch let error as CancellationError {
            throw error
        } catch where items.isEmpty {
            throw CopyError.origenNoAccesible(rawOrigen.path)
        }
        progress(CopyProgress(fase: .inventario, hechos: items.count, total: items.count))
        try plan.checkUnmatched(pruned: pruned, items: items)
        let exclusiones = plan.reported(pruned: pruned)

        // 3. Carpeta nueva; nunca se reutiliza una existente.
        let destino = try makeDestination(in: empresas, origen: origen, nombre: options.nombre)
        do {
            return try fill(destino, origen: origen, items: items, exclusiones: exclusiones, cancel: cancel)
        } catch {
            // Cancelada, verificación fallida o error de disco: lo copiado a medias va a la Papelera
            // (recuperable) y no se registra nada.
            try? fs.trashItem(destino)
            throw error
        }
    }

    /// Pasos 4 a 7: copiar, verificar, escribir la configuración de la copia y el informe.
    private func fill(_ destino: URL, origen: URL, items: [WalkItem], exclusiones: [String],
                      cancel: CancelFlag) throws -> Result {
        // 4. Copia: carpetas en preorden; cada fichero se resume antes de clonarlo.
        var copied: [Copied] = []
        var dirs: [(src: URL, dst: URL)] = []
        var soloEnICloud: [String] = []
        var enlaces: [String] = []
        var bytes: Int64 = 0
        let total = items.count
        for (i, item) in items.enumerated() {
            try cancel.check()
            let dst = item.url(in: destino)
            switch item.kind {
            case .directory:
                try fs.createDirectory(at: dst)
                dirs.append((item.url, dst))
            case .file:
                let hash: String
                do {
                    hash = try fs.sha256(of: item.url)
                } catch where fs.isDataless(item.url) {
                    // iCloud lo desalojó durante la copia: se trata como «solo en iCloud».
                    soloEnICloud.append(item.path.raw)
                    continue
                }
                try fs.copyItem(at: item.url, to: dst)
                copied.append(Copied(path: item.path, src: item.url, dst: dst, sha256: hash))
                bytes += fs.fileSize(item.url) ?? 0
            case .dataless:
                soloEnICloud.append(item.path.raw)
            case .symlink:
                enlaces.append(item.path.raw)
            }
            if (i + 1) % Self.progressStep == 0 || i + 1 == total {
                progress(CopyProgress(fase: .copia, hechos: i + 1, total: total))
            }
        }

        // 5. Verificación: SHA-256 de cada copia contra el del origen.
        var diferencias: [String] = []
        var verificados = 0
        for (i, c) in copied.enumerated() {
            try cancel.check()
            if (try? fs.sha256(of: c.dst)) == c.sha256 { verificados += 1 } else { diferencias.append(c.path.raw) }
            if (i + 1) % Self.progressStep == 0 || i + 1 == copied.count {
                progress(CopyProgress(fase: .verificacion, hechos: i + 1, total: copied.count))
            }
        }

        var report = CopyReport(vaultID: id, destino: destino.path, copiados: copied.count, bytes: bytes,
                                soloEnICloud: soloEnICloud, verificados: verificados, diferencias: diferencias,
                                exclusiones: exclusiones, fecha: now)
        report.enlacesOmitidos = enlaces
        report.huellas = Dictionary(copied.map { ($0.path.raw, $0.sha256) }, uniquingKeysWith: { a, _ in a })

        guard diferencias.isEmpty else {
            // Se deja el informe para diagnosticar; la copia no se registra y va a la Papelera.
            try? writeReport(report)
            throw CopyError.verificacionFallida(diferencias.count)
        }

        // 6. Configuración propia de la copia.
        let tls = destino.appendingPathComponent(".tls", isDirectory: true)
        if !fs.fileExists(tls) { try fs.createDirectory(at: tls) }
        let yaml = CopyConfig.yaml(id: id, origen: origen.path, creada: LocalDate(date: now))
        try fs.write(Data(yaml.utf8), to: tls.appendingPathComponent("config.yaml"))

        // 7. Fechas de las carpetas, de dentro afuera (escribir dentro las cambia).
        for d in dirs.reversed() {
            if let date = fs.modificationDate(d.src) { try? fs.setModificationDate(date, for: d.dst) }
        }

        try writeReport(report)
        return Result(report: report, origen: origen, destino: destino)
    }

    /// `true` si `child` es `parent` o cuelga de él, con rutas reales (`/tmp` = `/private/tmp`).
    static func isInside(_ child: URL, _ parent: URL) -> Bool {
        let c = ExclusionRules.key(canonicalPath(child))
        let p = ExclusionRules.key(canonicalPath(parent))
        return c == p || c.hasPrefix(p.hasSuffix("/") ? p : p + "/")
    }

    /// Ruta real aunque la carpeta aún no exista: `realpath` del antepasado existente más cercano
    /// más el resto. `resolvingSymlinksInPath` no sirve: quita `/private` solo si la ruta existe.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while true {
            let resolved: String? = existing.withUnsafeFileSystemRepresentation { path in
                guard let path, let r = realpath(path, nil) else { return nil }
                defer { free(r) }
                return String(cString: r)
            }
            if var base = resolved {
                for c in rest.reversed() { base += (base.hasSuffix("/") ? "" : "/") + c }
                return base
            }
            let parent = existing.deletingLastPathComponent()
            if parent.path == existing.path { return url.standardizedFileURL.path }
            rest.append(existing.lastPathComponent)
            existing = parent
        }
    }

    /// `<empresas>/<nombre> (copia AAAA-MM-DD)`, y si existe, « 2», « 3»…
    func makeDestination(in empresas: URL, origen: URL, nombre: String?) throws -> URL {
        if !fs.fileExists(empresas) { try fs.createDirectory(at: empresas) }
        let base = Self.destinationName(origen: origen, nombre: nombre, date: LocalDate(date: now))
        for n in 1...999 {
            let candidate = empresas.appendingPathComponent(n == 1 ? base : "\(base) \(n)", isDirectory: true)
            if fs.fileExists(candidate) { continue }
            do {
                try fs.createDirectory(at: candidate)
                return candidate
            } catch where fs.fileExists(candidate) {
                continue  // otra copia la creó a la vez
            }
        }
        throw CopyError.destinoExiste(empresas.appendingPathComponent(base).path)
    }

    static func destinationName(origen: URL, nombre: String?, date: LocalDate) -> String {
        let clean = { (s: String) -> String in
            s.precomposedStringWithCanonicalMapping
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let nombre, !clean(nombre).isEmpty, !clean(nombre).hasPrefix(".") { return clean(nombre) }
        return "\(clean(origen.lastPathComponent)) (copia \(date.description))"
    }

    func writeReport(_ report: CopyReport) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        if !fs.fileExists(stateDirectory) { try fs.createDirectory(at: stateDirectory) }
        try fs.write(data, to: stateDirectory.appendingPathComponent(DemoCopier.reportFileName))
    }
}
