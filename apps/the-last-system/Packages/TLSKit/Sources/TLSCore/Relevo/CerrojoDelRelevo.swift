// Procedencia: la ruta del cerrojo del escritor antiguo sigue FORK/server/internal/biz/writer.go (`lockPath`:
// `<estado>/locks/<hex(sha256(filepath.Clean(root))[:8])>.lock`, con `<estado>` = `TLS_STATE_DIR` o
// `~/Library/Application Support/TLS`), portada a Swift solo para comprobarla. No se escribe nada del fork.

import CryptoKit
import Darwin
import Foundation

/// Quién lleva la carpeta real ahora mismo, según su `.tls/escritor.json` (sin descargar nada de iCloud).
public enum EscritorAnterior: Sendable, Equatable {
    /// No hay `escritor.json`.
    case ninguno
    /// El fork (lleva `workspace_id`).
    case fork(empresa: String)
    /// Esta misma instalación (por ejemplo, un relevo deshecho que dejó su marca).
    case estaInstalacion
    /// Otra instalación de esta app (otro Mac).
    case otraInstalacion(equipo: String, desde: String)

    /// Lee `.tls/escritor.json` de `root`. Lanza `ErrorDeRelevo.escritorIlegible` si existe y no se entiende (o está
    /// solo en iCloud: no se descarga).
    public static func leer(root: URL, instalacion: UUID) throws -> (EscritorAnterior, Data?) {
        let url = VaultPath(WriterClaim.file).url(in: root)
        guard let st = UbiquityInspector.info(url) else { return (.ninguno, nil) }
        guard !st.isSymlink, !st.isDirectory, !st.dataless,
              let data = UbiquityInspector.withoutMaterializing({ FileManager.default.contents(atPath: url.path) }),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ErrorDeRelevo.escritorIlegible
        }
        if let ws = any["workspace_id"] as? String, !ws.isEmpty {
            return (.fork(empresa: any["empresa"] as? String ?? ""), data)
        }
        guard let inst = any["instalacion"] as? String, !inst.isEmpty else { throw ErrorDeRelevo.escritorIlegible }
        if inst.lowercased() == instalacion.uuidString.lowercased() { return (.estaInstalacion, data) }
        return (.otraInstalacion(equipo: any["equipo"] as? String ?? "otro Mac", desde: any["desde"] as? String ?? "?"), data)
    }
}

/// Paso 2 del relevo (PLAN §9 F6): `flock(LOCK_SH|LOCK_NB)` sobre el cerrojo del escritor antiguo.
///
/// - Cerrojo del fork: si existe el fichero, se toma **compartido** y se mantiene mientras dura el relevo (así el fork
///   no puede empezar a escribir a mitad). Si no se puede, el fork está abierto: se rechaza con un mensaje claro. Si el
///   fichero no existe, está libre (nunca se crea nada en el estado del fork).
/// - Cerrojo de esta app para la carpeta real (`locks/<sha8>.lock`): solo se comprueba y se suelta en el momento (el
///   escritor de la real lo tomará en exclusiva al escribir; mantenerlo compartido lo bloquearía).
/// - `escritor.json` de otro Mac: se rechaza.
public final class CerrojoDelRelevo: @unchecked Sendable {
    /// `~/Library/Application Support/TLS` (estado del fork). En pruebas se pasa una carpeta temporal.
    public static var estadoDelForkPorDefecto: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TLS", isDirectory: true)
    }

    public let escritorAnterior: EscritorAnterior
    /// Bytes del `escritor.json` que había (para la copia de seguridad y para «Deshacer»).
    public let escritorAnteriorDatos: Data?
    /// Cerrojos del fork que se tienen compartidos.
    public let cerrojosDelFork: [URL]

    private let lock = NSLock()
    private var fds: [Int32]

    private init(escritor: EscritorAnterior, datos: Data?, cerrojos: [URL], fds: [Int32]) {
        self.escritorAnterior = escritor; self.escritorAnteriorDatos = datos
        self.cerrojosDelFork = cerrojos; self.fds = fds
    }

    deinit { soltar() }

    public func soltar() {
        lock.withLock {
            for fd in fds {
                flock(fd, LOCK_UN)
                close(fd)
            }
            fds = []
        }
    }

    /// Comprueba y toma lo necesario. No escribe nada en ningún sitio.
    ///
    /// - `rutaRegistrada`: la ruta de la real tal como está en `vaults.json` (el fork calcula su cerrojo con la ruta que
    ///   tiene configurada, sin resolver enlaces): se prueban todas las formas posibles.
    public static func tomar(real: URL, rutaRegistrada: String?, appSupport: URL, estadoDelFork: URL,
                             instalacion: UUID) throws -> CerrojoDelRelevo {
        let (escritor, datos) = try EscritorAnterior.leer(root: real, instalacion: instalacion)
        if case .otraInstalacion(let equipo, let desde) = escritor {
            throw ErrorDeRelevo.otroEquipo(equipo: equipo, desde: desde)
        }
        // Esta app, en otra ventana o proceso.
        let propio = WriterClaim.lockURL(root: real, appSupport: appSupport)
        if FileManager.default.fileExists(atPath: propio.path) {
            let fd = open(propio.path, O_RDONLY)
            if fd >= 0 {
                defer { close(fd) }
                guard flock(fd, LOCK_SH | LOCK_NB) == 0 else { throw ErrorDeRelevo.otraVentanaAbierta }
                flock(fd, LOCK_UN)
            }
        }
        // El fork.
        var fds: [Int32] = []
        var tomados: [URL] = []
        do {
            for url in cerrojosDelFork(real: real, rutaRegistrada: rutaRegistrada, estadoDelFork: estadoDelFork)
            where FileManager.default.fileExists(atPath: url.path) {
                let fd = open(url.path, O_RDONLY)
                guard fd >= 0 else { throw ErrorDeRelevo.otraAplicacionAbierta }
                guard flock(fd, LOCK_SH | LOCK_NB) == 0 else {
                    close(fd)
                    throw ErrorDeRelevo.otraAplicacionAbierta
                }
                fds.append(fd)
                tomados.append(url)
            }
        } catch {
            for fd in fds { flock(fd, LOCK_UN); close(fd) }
            throw error
        }
        return CerrojoDelRelevo(escritor: escritor, datos: datos, cerrojos: tomados, fds: fds)
    }

    /// Rutas posibles del cerrojo del fork para esta carpeta: `locks/<16 hex>.lock` con el SHA-256 de la ruta (la
    /// registrada, la estándar y la real; en NFC y en NFD), sin repetir.
    public static func cerrojosDelFork(real: URL, rutaRegistrada: String?, estadoDelFork: URL) -> [URL] {
        var rutas: [String] = []
        if let r = rutaRegistrada, !r.isEmpty { rutas.append(limpiar(r)) }
        rutas.append(limpiar(real.path))
        rutas.append(real.standardizedFileURL.path)
        if let realpath = PathGuard.realPath(real) { rutas.append(realpath) }
        var vistas = Set<String>()
        var out: [URL] = []
        for r in rutas {
            for forma in [r, r.precomposedStringWithCanonicalMapping, r.decomposedStringWithCanonicalMapping] {
                let nombre = claveDelFork(forma)
                guard vistas.insert(nombre).inserted else { continue }
                out.append(estadoDelFork.appendingPathComponent("locks", isDirectory: true)
                    .appendingPathComponent("\(nombre).lock"))
            }
        }
        return out
    }

    /// `hex(sha256(ruta)[:8])`, como el fork.
    public static func claveDelFork(_ ruta: String) -> String {
        SHA256.hash(data: Data(ruta.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Como `filepath.Clean` de Go para rutas absolutas: sin `//`, sin `.` y sin `/` final.
    static func limpiar(_ ruta: String) -> String {
        guard ruta.hasPrefix("/") else { return ruta }
        var partes: [String] = []
        for p in ruta.split(separator: "/", omittingEmptySubsequences: true) {
            if p == "." { continue }
            if p == ".." { if !partes.isEmpty { partes.removeLast() }; continue }
            partes.append(String(p))
        }
        return "/" + partes.joined(separator: "/")
    }
}
