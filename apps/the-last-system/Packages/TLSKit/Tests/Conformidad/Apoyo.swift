import CryptoKit
import Foundation
import TLSCore

/// Rutas de las pruebas de conformidad, a partir de este fichero (no del bundle): los golden se
/// regeneran en su sitio con `TLS_ACTUALIZAR_GOLDEN=1`.
enum RutasConformidad {
    static let esteFichero = URL(fileURLWithPath: #filePath)
    /// `Packages/TLSKit/Tests/Conformidad`.
    static var conformidad: URL { esteFichero.deletingLastPathComponent() }
    static var casos: URL { conformidad.appendingPathComponent("Casos", isDirectory: true) }
    /// `Packages/TLSKit`.
    static var paquete: URL { conformidad.deletingLastPathComponent().deletingLastPathComponent() }
    static var repo: URL { paquete.deletingLastPathComponent().deletingLastPathComponent() }
    static var empresaMinima: URL {
        paquete.appendingPathComponent("Tests/TLSCoreTests/Fixtures/EmpresaMinima", isDirectory: true)
    }
    /// La empresa de ejemplo versionada (salida de `tls-tool convertir-g2`).
    static var ejemploRibera: URL {
        repo.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera", isDirectory: true)
    }

    /// Carpeta G2 de Ribera (ficticia), si está en este Mac: `TLS_RIBERA_G2` o `~/TLS Empresas/DEV - Asesoría Ribera`.
    /// Nunca dentro de iCloud Drive.
    static var origenRibera: URL? {
        let ruta = ProcessInfo.processInfo.environment["TLS_RIBERA_G2"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("TLS Empresas/DEV - Asesoría Ribera").path
        guard !AppLocations.isInICloudDrive(ruta) else { return nil }
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: ruta, isDirectory: &dir) && dir.boolValue
            ? URL(fileURLWithPath: ruta, isDirectory: true) : nil
    }

    static var actualizarGolden: Bool { ProcessInfo.processInfo.environment["TLS_ACTUALIZAR_GOLDEN"] == "1" }

    /// Carpeta temporal nueva.
    static func temporal(_ nombre: String = "conformidad") -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(nombre)-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Árbol de ficheros (rutas relativas en NFC → bytes), con los ocultos (`.tls/`) y sin `.DS_Store`.
enum Arbol {
    static func leer(_ raiz: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let fm = FileManager.default
        var pendientes: [VaultPath] = [.root]
        while let carpeta = pendientes.popLast() {
            for nombre in try fm.contentsOfDirectory(atPath: carpeta.url(in: raiz).path) where nombre != ".DS_Store" && nombre != ".gitkeep" {
                let ruta = carpeta.appending(nombre)
                let url = ruta.url(in: raiz)
                var dir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &dir) else { continue }
                if dir.boolValue { pendientes.append(ruta) } else { out[ruta.raw] = try Data(contentsOf: url) }
            }
        }
        return out
    }

    /// Rutas que faltan, sobran o cambian entre dos árboles.
    static func diferencias(_ a: [String: Data], _ b: [String: Data]) -> [String] {
        Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }.sorted().map { ruta in
            switch (a[ruta], b[ruta]) {
            case (nil, _): "sobra \(ruta)"
            case (_, nil): "falta \(ruta)"
            default: "cambia \(ruta)"
            }
        }
    }

    /// Escribe un árbol en `destino` (que no debe existir).
    static func escribir(_ arbol: [String: Data], en destino: URL) throws {
        for (ruta, datos) in arbol {
            let url = VaultPath(ruta).url(in: destino)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try datos.write(to: url)
        }
    }

    /// Sustituye el contenido de una carpeta de golden por `arbol` (solo para `TLS_ACTUALIZAR_GOLDEN=1`).
    static func reemplazarGolden(_ carpeta: URL, con arbol: [String: Data]) throws {
        let base = RutasConformidad.temporal("golden")
        defer { try? FileManager.default.removeItem(at: base) }
        let tmp = base.appendingPathComponent("esperado", isDirectory: true)
        try escribir(arbol, en: tmp)
        if !FileManager.default.fileExists(atPath: tmp.path) {
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        }
        if FileManager.default.fileExists(atPath: carpeta.path) {
            _ = try FileManager.default.replaceItemAt(carpeta, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: carpeta)
        }
    }

    static func sha256(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }
}
