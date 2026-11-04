import Foundation

// F3 · rol motor. `onboarding.json`: el progreso de la puesta en marcha, en el estado de la carpeta
// (`<Application Support>/<vault-id>/onboarding.json`, PLAN §3.4), **fuera de la carpeta de la empresa**. Se guarda
// tras cada respuesta (criterio F3-3). En «Empiezo de cero» el identificador se elige al empezar, así que el fichero
// existe antes que la carpeta.

public struct AlmacenPuesta: Sendable {
    public static let nombreFichero = "onboarding.json"

    public let appSupport: URL
    public let vaultID: UUID

    public init(vaultID: UUID, appSupport: URL = AppLocations.appSupport) {
        self.vaultID = vaultID; self.appSupport = appSupport
    }

    /// `<appSupport>/<id>/onboarding.json`.
    public var url: URL {
        appSupport.appendingPathComponent(vaultID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(Self.nombreFichero)
    }

    static let codificador: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decodificador: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func leer() -> EstadoPuestaEnMarcha? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decodificador.decode(EstadoPuestaEnMarcha.self, from: data)
    }

    /// Hay un `onboarding.json` pero no se puede leer (dañado o de una versión que esta no entiende).
    public var ilegible: Bool {
        FileManager.default.fileExists(atPath: url.path) && leer() == nil
    }

    /// Antes de empezar de cero sobre un fichero que no se puede leer, se aparta (nunca se pisa): queda al lado como
    /// `onboarding.json.ilegible-<fecha>`. Devuelve dónde quedó.
    @discardableResult
    public func apartarIlegible(ahora: Date = Date()) -> URL? {
        guard ilegible else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        var destino = url.deletingLastPathComponent().appendingPathComponent("\(Self.nombreFichero).ilegible-\(f.string(from: ahora))")
        var n = 2
        while FileManager.default.fileExists(atPath: destino.path) {
            destino = url.deletingLastPathComponent().appendingPathComponent("\(Self.nombreFichero).ilegible-\(f.string(from: ahora))-\(n)")
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: destino)
            return destino
        } catch {
            return nil
        }
    }

    /// Escribe de forma atómica (carpeta 0700, fichero 0600). Nunca dentro de iCloud Drive. Un fichero que está pero no
    /// se puede leer no se pisa: se aparta antes (`apartarIlegible`).
    public func guardar(_ e: EstadoPuestaEnMarcha) throws {
        guard !AppLocations.isInICloudDrive(url.path) else { throw ErrorPuesta.estadoEnICloud }
        if ilegible, apartarIlegible() == nil { throw ErrorPuesta.estadoIlegible }
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        let data = try Self.codificador.encode(e)
        try data.write(to: url, options: [.atomic])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Quita el fichero (al pasar el estado a la carpeta nueva tras la copia). Es estado de la app, no de la empresa.
    public func retirar() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Puestas en marcha sin terminar de esta instalación (para «Seguir con la puesta en marcha» en el arranque). Una
    /// que se abrió y se cerró sin contestar nada no cuenta: no hay nada que seguir.
    public static func pendientes(appSupport: URL = AppLocations.appSupport) -> [EstadoPuestaEnMarcha] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil) else { return [] }
        return dirs.compactMap { d -> EstadoPuestaEnMarcha? in
            guard let id = UUID(uuidString: d.lastPathComponent) else { return nil }
            return AlmacenPuesta(vaultID: id, appSupport: appSupport).leer()
        }.filter { !$0.terminada && !$0.sinEmpezar }.sorted { $0.actualizado > $1.actualizado }
    }
}

/// Errores de la puesta en marcha, en español llano.
public enum ErrorPuesta: Error, LocalizedError, Sendable, Equatable {
    case estadoEnICloud
    case carpetaReal
    case soloLectura
    case sinCarpeta
    case nombreVacio
    case logoDemasiadoGrande(String)
    case logoIlegible(String)
    case ajustesIlegibles
    case cambioFuera(String)
    case nadaQueDeshacer
    case otroPlanDespues(String)
    case estadoIlegible

    public var errorDescription: String? {
        switch self {
        case .estadoEnICloud:
            "No guardo el progreso dentro de iCloud Drive. Revisa dónde está la carpeta de la app."
        case .carpetaReal:
            "Es tu carpeta original: solo la miro. La puesta en marcha se hace sobre una copia."
        case .soloLectura:
            "Esta carpeta está en modo solo lectura: no puedo aplicar nada."
        case .sinCarpeta:
            "Aún no hay carpeta. Empieza por la bienvenida."
        case .nombreVacio:
            "Dime cómo se llama tu empresa para crear su carpeta."
        case .logoDemasiadoGrande(let n):
            "«\(n)» pasa de 10 MB. Elige un fichero más ligero o déjalo para después."
        case .logoIlegible(let n):
            "No puedo leer «\(n)». Elige otro fichero o déjalo para después."
        case .ajustesIlegibles:
            "Los ajustes de tu carpeta no se pueden leer. No los toco: revísalos antes de seguir."
        case .cambioFuera(let r):
            "«\(r)» cambió fuera de la app mientras mirabas la vista previa. Vuelve a mirarla antes de aplicar."
        case .nadaQueDeshacer:
            "No hay nada que deshacer de este paso."
        case .otroPlanDespues(let d):
            "Después de este paso se hizo «\(d)». Deshaz eso primero."
        case .estadoIlegible:
            "No puedo leer cómo iba la puesta en marcha y no lo quiero pisar. Revisa la carpeta de la app antes de seguir."
        }
    }
}

/// Cómo pide la interfaz que se abra la puesta en marcha (arranque, Hoy, el ejemplo). Es el valor de la ventana
/// `PuertaPuestaEnMarcha.ventanaID`: TLSUI la abre con `openWindow(id:value:)` sin depender de TLSOnboarding.
public struct PeticionPuestaEnMarcha: Codable, Sendable, Hashable {
    public enum Modo: String, Codable, Sendable, Hashable {
        /// Empezar (sin carpeta o con la carpeta elegida).
        case empezar
        /// Seguir donde se quedó.
        case retomar
        /// Repasar una puesta en marcha terminada (el ejemplo).
        case repasar
    }

    public var modo: Modo
    /// Carpeta registrada (o el identificador elegido para la empresa nueva).
    public var vaultID: UUID?
    /// Lo ya elegido en «¿Cómo empiezas?» (`carpeta`, `cero` o `ejemplo`), p. ej. «Empezar de cero…» del arranque.
    public var como: String?

    public init(modo: Modo, vaultID: UUID? = nil, como: String? = nil) {
        self.modo = modo; self.vaultID = vaultID; self.como = como
    }
}

/// Dónde se abre la puesta en marcha.
public enum PuertaPuestaEnMarcha {
    /// Identificador de la ventana (`WindowGroup(id:for:)` de `OnboardingEscena` en TLSOnboarding).
    public static let ventanaID = "puesta-en-marcha"

    /// Lo que enseña Hoy de una carpeta: «Seguir con la puesta en marcha · paso 4 de 9» (`nil` si no hay nada que
    /// seguir: sin empezar o terminada).
    public static func avisoDeHoy(vaultID: UUID, appSupport: URL = AppLocations.appSupport) -> ProgresoPuestaEnMarcha? {
        guard let p = ProgresoPuestaEnMarcha.leer(vaultID: vaultID, appSupport: appSupport), !p.terminada else { return nil }
        return p
    }
}
