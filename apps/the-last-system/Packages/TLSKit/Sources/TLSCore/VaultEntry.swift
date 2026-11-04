import Foundation

/// Clase de una carpeta registrada. La real no se escribe en la v1 hasta F6.
public enum VaultClass: String, Sendable, Codable, Hashable {
    case real, copia, demo
}

public enum WriteAccess: String, Sendable, Codable, Hashable {
    case permitida, bloqueada
}

/// Una carpeta de empresa conocida por esta instalación (`vaults.json`).
public struct VaultEntry: Sendable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var nombre: String
    /// Última ruta conocida (informativa; la verdad es el bookmark).
    public var ruta: String
    public var bookmark: Data?
    public var clase: VaultClass
    public var escritura: WriteAccess
    /// Rutas relativas que no se copiaron (la carpeta privada, Archivo…). Nunca van en el código.
    public var exclusionesCopia: [String]
    /// Para una copia, ruta de la carpeta de origen.
    public var origen: String?
    public var creada: Date

    public init(id: UUID = UUID(), nombre: String, ruta: String, bookmark: Data?, clase: VaultClass,
                escritura: WriteAccess, exclusionesCopia: [String] = [], origen: String? = nil,
                creada: Date = Date()) {
        self.id = id; self.nombre = nombre; self.ruta = ruta; self.bookmark = bookmark
        self.clase = clase; self.escritura = escritura; self.exclusionesCopia = exclusionesCopia
        self.origen = origen; self.creada = creada
    }

    enum CodingKeys: String, CodingKey {
        case id, nombre, ruta, bookmark, clase, escritura
        case exclusionesCopia = "exclusiones_copia"
        case origen, creada
    }

    /// Lo privado que se quedó fuera de la copia: lo dejado fuera menos `Archivo/` (que no se copia por tamaño, no por
    /// privado). Es la cifra que se enseña («1 carpeta privada se quedó fuera de la copia») y lo que se premarca.
    public var carpetasPrivadasDeLaCopia: [String] {
        exclusionesCopia.filter { TextFolding.pathKey($0) != TextFolding.pathKey("Archivo") }
    }
}

/// Ubicaciones fuera de la carpeta de la empresa. Todo el estado técnico vive aquí.
///
/// `TLS_APP_SUPPORT` y `TLS_EMPRESAS` existen para pruebas y para `tls-tool` (carpetas temporales).
/// Se ignoran si apuntan dentro de iCloud Drive: ni el índice ni las copias van nunca a iCloud.
public enum AppLocations {
    /// `~/Library/Mobile Documents` (iCloud Drive). Solo se usa para comparar rutas: nunca se abre.
    public static var iCloudDrivePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true).standardizedFileURL.path
    }

    /// `true` si `path` queda dentro de iCloud Drive (comparación de texto, sin tocar el disco).
    public static func isInICloudDrive(_ path: String) -> Bool {
        let k = TextFolding.pathKey(URL(fileURLWithPath: path).standardizedFileURL.path)
        let icloud = TextFolding.pathKey(iCloudDrivePath)
        return k == icloud || k.hasPrefix(icloud + "/")
    }

    /// Variable de entorno de pruebas, si es válida (no vacía y fuera de iCloud Drive).
    static func override(_ name: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty,
              !isInICloudDrive(value) else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// `~/Library/Application Support/The Last System`. Se puede sustituir en pruebas con `TLS_APP_SUPPORT`.
    public static var appSupport: URL {
        if let override = override("TLS_APP_SUPPORT") { return override }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("The Last System", isDirectory: true)
    }

    /// `~/The Last System/Empresas`: copias y ejemplo, visibles en Finder y fuera de iCloud.
    public static var empresas: URL {
        if let override = override("TLS_EMPRESAS") { return override }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("The Last System", isDirectory: true)
            .appendingPathComponent("Empresas", isDirectory: true)
    }

    public static var logs: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/The Last System", isDirectory: true)
    }

    /// Estado de una carpeta concreta (índice, diario, copias…).
    public static func vaultState(_ id: UUID) -> URL {
        appSupport.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }
}
