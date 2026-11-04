import Foundation
import Yams

/// Quién puede escribir en qué carpeta.
///
/// - La carpeta real (`clase: real`) no se escribe («Ver sin tocar»)… salvo tras «Pasar a mi carpeta real» (F6):
///   durante el relevo (solo `AplicadorDeRelevo`, con `VaultWriter.Options.relevo`) y después, cuando el relevo quedó
///   hecho (`relevo.json` con `estado: hecho` en los ajustes de la app) **y** `vaults.json` dice `escritura: permitida`.
///   «Deshacer» el relevo la devuelve a solo lectura.
/// - Las copias y la demo sí, salvo que estén en modo solo lectura (`escritura: bloqueada`).
/// - Por si la entrada estuviera mal, también se mira lo que dice la propia carpeta
///   (`.tls/config.yaml` con `clase: real`) y que no esté en iCloud Drive (donde vive la real).
public enum WritePolicy {
    /// Escritura con la que nace una entrada de esa clase.
    public static func escrituraInicial(para clase: VaultClass) -> WriteAccess {
        switch clase {
        case .real: .bloqueada
        case .copia, .demo: .permitida
        }
    }

    /// Lanza un error claro si la app no puede escribir en esta carpeta.
    /// - Parameters:
    ///   - appSupport: ajustes de la app donde vive la marca del relevo (`<appSupport>/<id>/relevo.json`). Sin ellos, la
    ///     real no se escribe nunca.
    ///   - relevo: solo `AplicadorDeRelevo` (pasos 4–7 y su «Deshacer»), con la confirmación y el cerrojo ya tomados.
    public static func comprobar(_ entry: VaultEntry, root: URL, appSupport: URL? = nil, relevo: Bool = false) throws {
        if entry.clase == .real {
            // F6 · integración: la real solo se escribe durante el relevo o con el relevo hecho y la escritura permitida.
            guard relevo || realConRelevoHecho(entry, appSupport: appSupport) else { throw WriteError.carpetaReal }
            return
        }
        if AppLocations.isInICloudDrive(root.path) || AppLocations.isInICloudDrive(PathGuard.canonicalPath(root)) {
            throw WriteError.carpetaReal
        }
        if clase(declaradaEn: root) == .real { throw WriteError.carpetaReal }
        guard entry.escritura == .permitida else { throw WriteError.soloLectura }
    }

    /// F6 · integración: la real se escribe porque el relevo quedó hecho (la marca `relevo.json` dice `hecho`) y
    /// `vaults.json` la tiene en `escritura: permitida`. Sin `appSupport`, nunca.
    public static func realConRelevoHecho(_ entry: VaultEntry, appSupport: URL?) -> Bool {
        guard entry.clase == .real, entry.escritura == .permitida, let appSupport else { return false }
        return RegistroDeRelevo.leer(appSupport: appSupport, real: entry.id)?.estado == .hecho
    }

    /// `clase:` de `.tls/config.yaml` (sin descargar nada de iCloud). `nil` si no existe o no lo dice.
    /// Si existe y no se puede leer (enlace, solo en iCloud, YAML roto, clase desconocida), `.real`:
    /// por precaución, como lo privado, se para antes que arriesgarse.
    public static func clase(declaradaEn root: URL) -> VaultClass? {
        let url = VaultPath(VaultLayout.configFile).url(in: root)
        guard let info = UbiquityInspector.info(url) else { return nil }
        guard !info.isSymlink, !info.isDirectory, !info.dataless,
              let data = UbiquityInspector.withoutMaterializing({ FileManager.default.contents(atPath: url.path) }),
              let text = TextDecoding.decode(data) else { return .real }
        if text.allSatisfy({ $0.isWhitespace }) { return nil }
        guard let node = try? Yams.compose(yaml: text, Resolver.basic) else { return .real }
        guard case .mapping(let m) = node else { return nil }
        for (k, v) in m where k.string == "clase" {
            return v.string.flatMap { VaultClass(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? .real
        }
        return nil
    }
}

extension VaultRegistry {
    static let escrituraFile = "escritura.json"

    /// F1: las copias y la demo pasan a poder escribirse (en F0 se registraban todas como
    /// `bloqueada`). Cada entrada se revisa una sola vez: si luego alguien la pone en solo
    /// lectura, se queda así. La carpeta real siempre queda `bloqueada`.
    /// Devuelve las entradas que cambiaron.
    @discardableResult
    public func permitirEscrituraEnCopias() throws -> [UUID] {
        let markURL = directory.appendingPathComponent(Self.escrituraFile)
        // Solo en el primer arranque con F1 se abren las copias de F0. Después, una copia en solo
        // lectura es una elección («Ver sin tocar» o el modo solo lectura): las copias nuevas ya
        // nacen con escritura (`DemoCopier`).
        let primeraVez = !FileManager.default.fileExists(atPath: markURL.path)
        var revisadas = Set<String>()
        if let data = FileManager.default.contents(atPath: markURL.path),
           let obj = try? JSONDecoder().decode([String: [String]].self, from: data) {
            revisadas = Set(obj["revisadas"] ?? [])
        }
        var changed: [UUID] = []
        var touched = false
        for var entry in load() {
            let id = entry.id.uuidString.lowercased()
            // F6 · integración: la real con el relevo hecho sigue escribiéndose (si no, cada arranque desharía el paso 6).
            if entry.clase == .real, entry.escritura != .bloqueada,
               RegistroDeRelevo.leer(appSupport: directory, real: entry.id)?.estado != .hecho {
                entry.escritura = .bloqueada
                try upsert(entry)
                changed.append(entry.id)
            }
            guard !revisadas.contains(id) else { continue }
            revisadas.insert(id)
            touched = true
            if primeraVez, entry.clase != .real, entry.escritura == .bloqueada {
                entry.escritura = .permitida
                try upsert(entry)
                changed.append(entry.id)
            }
        }
        if touched || primeraVez {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try VaultRegistry.atomicWrite(try enc.encode(["revisadas": revisadas.sorted()]), to: markURL)
        }
        return changed
    }
}
