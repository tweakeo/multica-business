import Foundation

/// Lo que queda apuntado de un relevo en los ajustes de la app (`<appSupport>/<id de la real>/relevo.json`), nunca en
/// la carpeta. Sirve para «Deshacer», para saber dónde está la copia de seguridad y para que la app sepa que la real ya
/// se puede escribir.
public struct MarcaDeRelevo: Sendable, Codable, Hashable {
    public enum Estado: String, Sendable, Codable, Hashable {
        case hecho, deshecho
        /// Se escribió, pero la comprobación final no cuadró: la real sigue en solo lectura (y se puede deshacer).
        case sinComprobar = "sin_comprobar"
    }

    public var real_id: String
    public var copia_id: String
    public var fecha: String
    public var estado: Estado
    /// Planes escritos en la real, en orden (para «Deshacer»).
    public var planes: [String]
    /// Carpeta de la copia de seguridad previa (en los ajustes de la app).
    public var respaldo: String
    public var anadidos: Int
    public var cambiados: Int
    public var archivados: Int
    /// Huella del árbol de la real antes del relevo (sin `Archivo/`): «Deshacer» la deja igual.
    public var hash_antes: String

    public init(real_id: String, copia_id: String, fecha: String, estado: Estado, planes: [String], respaldo: String,
                anadidos: Int, cambiados: Int, archivados: Int, hash_antes: String) {
        self.real_id = real_id; self.copia_id = copia_id; self.fecha = fecha; self.estado = estado; self.planes = planes
        self.respaldo = respaldo; self.anadidos = anadidos; self.cambiados = cambiados; self.archivados = archivados
        self.hash_antes = hash_antes
    }
}

/// Pasos 6 y su vuelta atrás: `escritor.json` de la real y `vaults.json`.
public enum RegistroDeRelevo {
    public static let fichero = "relevo.json"

    /// Carpeta de estado del relevo de una real.
    public static func carpeta(appSupport: URL, real id: UUID) -> URL {
        appSupport.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    public static func leer(appSupport: URL, real id: UUID) -> MarcaDeRelevo? {
        let url = carpeta(appSupport: appSupport, real: id).appendingPathComponent(fichero)
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        return try? JSONDecoder().decode(MarcaDeRelevo.self, from: data)
    }

    public static func guardar(_ marca: MarcaDeRelevo, appSupport: URL, real id: UUID) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let url = carpeta(appSupport: appSupport, real: id).appendingPathComponent(fichero)
        try AtomicFiles.writeDurable(try enc.encode(marca), to: url, mode: 0o600)
    }

    /// `vaults.json`: la real pasa a `escritura: permitida` (o vuelve a `bloqueada` al deshacer).
    public static func fijarEscritura(_ escritura: WriteAccess, registro: VaultRegistry, real id: UUID) throws {
        guard var entry = registro.load().first(where: { $0.id == id }) else { return }
        entry.escritura = escritura
        try registro.upsert(entry)
    }

    /// Se reclama `.tls/escritor.json` para esta instalación y esta carpeta (0600, atómico). Si había otro (el del fork),
    /// se sustituye solo si sigue siendo el mismo que se leyó (`anterior`); si no había, se crea.
    @discardableResult
    public static func reclamarEscritor(root: URL, entry: VaultEntry, instalacion: UUID, app: String, now: Date,
                                        anterior: Data?) throws -> WriterClaim.Info {
        let info = WriterClaim.Info(instalacion: instalacion.uuidString.lowercased(), equipo: WriterClaim.hostName(),
                                    vault_id: entry.id.uuidString.lowercased(), empresa: entry.nombre, app: app,
                                    desde: ISO8601DateFormatter().string(from: now))
        try escribirEscritor(datos(de: info), root: root, anterior: anterior)
        return info
    }

    /// Vuelve a dejar el `escritor.json` que había (sus mismos bytes) si lo que hay es el que puso el relevo. Si antes no
    /// había ninguno, el del relevo se aparta a `apartarEn` (los ajustes de la app): no queda nadie como escritor.
    public static func restaurarEscritor(root: URL, anterior: Data?, puesto: Data?, apartarEn: URL) throws {
        let url = VaultPath(WriterClaim.file).url(in: root)
        let actual = UbiquityInspector.withoutMaterializing { FileManager.default.contents(atPath: url.path) }
        // Si alguien lo cambió después, no se toca.
        if let puesto, let actual, actual != puesto { return }
        if let anterior {
            try escribirEscritor(anterior, root: root, anterior: actual)
        } else if actual != nil {
            try FileManager.default.createDirectory(at: apartarEn, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let destino = apartarEn.appendingPathComponent("escritor.json.apartado")
            try? FileManager.default.removeItem(at: destino)
            try FileManager.default.moveItem(at: url, to: destino)
        }
    }

    static func datos(de info: WriterClaim.Info) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try enc.encode(info)
        data.append(0x0A)
        return data
    }

    /// Bytes que `reclamarEscritor` dejó (para comprobarlos al deshacer).
    public static func escritorActual(root: URL) -> Data? {
        let url = VaultPath(WriterClaim.file).url(in: root)
        return UbiquityInspector.withoutMaterializing { FileManager.default.contents(atPath: url.path) }
    }

    private static func escribirEscritor(_ data: Data, root: URL, anterior: Data?) throws {
        let url = VaultPath(WriterClaim.file).url(in: root)
        let dir = url.deletingLastPathComponent()
        if let i = UbiquityInspector.info(dir), i.isSymlink || !i.isDirectory { throw WriteError.rutaNoPermitida(".tls") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try UbiquityInspector.withoutMaterializing {
            if let anterior {
                try AtomicFiles.replace(url, with: data, expected: ContentHash.of(anterior), display: WriterClaim.file,
                                        afterTemporary: {})
                _ = chmod(url.path, 0o600)
            } else {
                try AtomicFiles.create(url, with: data, display: WriterClaim.file, mode: 0o600, afterTemporary: {})
            }
        }
    }
}
