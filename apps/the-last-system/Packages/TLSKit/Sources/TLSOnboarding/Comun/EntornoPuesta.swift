import AppKit
import Foundation
import TLSAgents
import TLSCore
import TLSImport
import TLSUI
import UniformTypeIdentifiers

// F3 · rol pasos. Lo que la puesta en marcha necesita de fuera de su ventana: el modelo de la app (registro y
// sesiones abiertas), instalar el ejemplo, comprobar el permiso de macOS, los paneles de elegir carpeta, la copia,
// Claude Code y el tutorial. Todo se puede sustituir en las pruebas (nunca se abre un panel, nunca se lanza Claude,
// nunca se toca el Application Support de verdad).

/// Lo que dice macOS al intentar leer una carpeta.
public enum AccesoCarpeta: Equatable, Sendable {
    case ok
    /// macOS no deja leerla (EPERM / EACCES): sale la pantalla de recuperación.
    case sinPermiso
    case noExiste
    case otro

    /// Abre la carpeta (sin listarla ni descargar nada de iCloud) para saber si macOS deja leerla. Es la misma
    /// comprobación que hace el arranque (`FolderAccess.check` de TLSUI).
    public static func comprobar(_ url: URL) async -> AccesoCarpeta {
        switch await FolderAccess.check(url) {
        case .ok: .ok
        case .sinPermiso: .sinPermiso
        case .noExiste: .noExiste
        case .otro: .otro
        }
    }
}

/// Los paneles del sistema para elegir carpetas y ficheros (en pruebas, unos que contestan solos).
@MainActor
public protocol PanelesPuesta {
    /// La carpeta de la empresa.
    func elegirCarpeta(mensaje: String) -> URL?
    /// Carpetas o ficheros **dentro** de `raiz` (rutas relativas). Vacío si se cancela.
    func elegirDentro(de raiz: URL, mensaje: String) -> [VaultPath]
    /// Un fichero (el logo).
    func elegirFichero(mensaje: String, tipos: [String]) -> URL?
}

/// Los paneles de verdad (`NSOpenPanel`): los del arranque (`FolderPanels` de TLSUI) y uno para el logo.
@MainActor
public struct PanelesDelSistema: PanelesPuesta {
    public init() {}

    public func elegirCarpeta(mensaje: String) -> URL? {
        FolderPanels.chooseCompanyFolder(prompt: "Elegir", message: mensaje)
    }

    public func elegirDentro(de raiz: URL, mensaje: String) -> [VaultPath] {
        FolderPanels.choosePrivate(inside: raiz, prompt: "No copiar", message: mensaje)
    }

    public func elegirFichero(mensaje: String, tipos: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        panel.message = mensaje
        panel.allowedContentTypes = tipos.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Claude Code

/// Lo que se sabe de Claude Code en este Mac.
public enum EstadoClaude: Equatable, Sendable {
    case sinMirar
    case buscando
    case encontrado(version: String?, aviso: String?)
    case noEncontrado
    case probando
    case probado(ok: Bool, texto: String)

    public var encontrado: Bool {
        switch self {
        case .encontrado, .probando, .probado: true
        default: false
        }
    }
}

/// Busca Claude Code, lo prueba y da el lanzador del entrevistador. En pruebas, uno falso: nunca se lanza Claude.
public protocol DetectorClaude: Sendable {
    /// Busca el programa (sin lanzar ninguna consulta).
    func detectar() async -> EstadoClaude
    /// Una consulta mínima dentro del sandbox para ver que responde.
    func probar(estado: URL, negadas: [URL]) async -> EstadoClaude
    /// El lanzador del entrevistador (si está).
    func lanzador(estado: URL, negadas: [URL]) async -> (any LanzadorEntrevista)?
}

/// Claude Code de verdad: `ClaudeLocator` y `LanzadorClaudeCode` (sandbox de los asistentes).
public struct DetectorClaudeCode: DetectorClaude {
    public init() {}

    /// F4 · rol mika: además de la versión, si tienes la sesión iniciada (`claude auth status`), en palabras llanas.
    public func detectar() async -> EstadoClaude {
        let loc = ClaudeLocator()
        guard let i = try? await loc.locate() else { return .noEncontrado }
        let sesion = (try? await loc.authStatus(binary: i.binary))?.loggedIn
        return .encontrado(version: i.version?.description, aviso: Self.aviso(version: i.version?.description, sesion: sesion))
    }

    /// «Tienes la sesión iniciada.» / «No has iniciado sesión: …» y, si la versión no es la comprobada, una frase más.
    public static func aviso(version: String?, sesion: Bool?) -> String {
        var partes: [String] = []
        switch sesion {
        case true?: partes.append("Tienes la sesión iniciada.")
        case false?: partes.append("No has iniciado sesión. " + (TextosClaude.consejo(version: nil, sesion: false) ?? ""))
        case nil: partes.append("No he podido comprobar si tienes la sesión iniciada; «Probar» lo confirma.")
        }
        if sesion != false, let c = TextosClaude.consejo(version: version, sesion: true) { partes.append(c) }
        return partes.joined(separator: " ")
    }

    public func probar(estado: URL, negadas: [URL]) async -> EstadoClaude {
        guard let l = await lanzador(estado: estado, negadas: negadas) as? LanzadorClaudeCode else { return .noEncontrado }
        do {
            let salida = try await l.pedir("Contesta solo con {\"vaga\": false}. Es una prueba de conexión.",
                                           esquema: InterviewEngine.esquemaJSON)
            return salida.contains("vaga") ? .probado(ok: true, texto: "Funciona: ha contestado dentro de su caja.")
                : .probado(ok: false, texto: "Ha contestado algo raro. Sigo sin él.")
        } catch {
            return .probado(ok: false, texto: "No ha contestado. Sigo sin él; lo puedes probar más tarde.")
        }
    }

    public func lanzador(estado: URL, negadas: [URL]) async -> (any LanzadorEntrevista)? {
        let loc = ClaudeLocator()
        guard let i = try? await loc.locate(), let ayuda = try? await loc.help(of: i.binary) else { return nil }
        return LanzadorClaudeCode(probe: ClaudeProbe(claude: i.binary, help: ayuda), estado: estado, negadas: negadas)
    }
}

// MARK: - Entorno

/// Lo que la app le pasa a la puesta en marcha. Lo pone la integración (`OnboardingEscena(entorno:)` o
/// `EntornoPuesta.compartido`); sin ello todo funciona con lo mínimo: el registro de siempre, sin sesiones abiertas
/// y, para el ejemplo, el selector de empresa.
@MainActor
public final class EntornoPuesta {
    public static let compartido = EntornoPuesta()

    /// El modelo de la app (registro y sesiones abiertas). Con él, «Aplicar» escribe por la sesión abierta.
    public var app: AppModel?
    /// Instala (o reutiliza) Asesoría Ribera y devuelve su carpeta (`InstaladorEjemplo` de TLSUI).
    public var instalarEjemplo: (@MainActor () async throws -> VaultEntry)?
    /// ¿Deja macOS leer esta carpeta?
    public var comprobarAcceso: @Sendable (URL) async -> AccesoCarpeta = { await AccesoCarpeta.comprobar($0) }
    public var paneles: any PanelesPuesta = PanelesDelSistema()
    public var detectorClaude: any DetectorClaude = DetectorClaudeCode()
    /// Dónde guarda el tutorial su avance (`tutorial.json`). El de la app solo se abre si se usa (las pruebas ponen
    /// el suyo y nunca tocan el Application Support de verdad).
    public var almacenTutorial: AlmacenTutorial {
        get { almacenPropio ?? .compartido }
        set { almacenPropio = newValue }
    }
    private var almacenPropio: AlmacenTutorial?
    /// Ajustes del Sistema › Privacidad y seguridad › Archivos y carpetas.
    public var abrirAjustes: @MainActor () -> Void = {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }
    /// Enseñar una carpeta en el Finder (sin abrirla ni descargarla).
    public var mostrarEnFinder: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }

    public init() {}

    /// El de la app (lo declara `App/Sources`): el `AppModel` de `TLSScenes` (registro y sesiones abiertas: «Aplicar»
    /// escribe por la sesión abierta) y el ejemplo de verdad (`AppModel.instalarEjemplo`).
    /// En pruebas: otro entorno, el ejemplo del repositorio y unas empresas temporales.
    public static func deLaApp(_ app: AppModel, en entorno: EntornoPuesta = .compartido, ejemplo: URL? = nil,
                               empresas: URL = AppLocations.empresas) -> EntornoPuesta {
        entorno.app = app
        entorno.instalarEjemplo = { [weak app] in
            guard let app else { throw ErrorPuesta.sinCarpeta }
            return try await app.instalarEjemplo(origen: ejemplo, empresas: empresas)
        }
        return entorno
    }

    /// Guarda el avance del tutorial en otro `tutorial.json` (pruebas: nunca el de la app).
    public func tutorialEn(_ archivo: URL) {
        almacenTutorial = AlmacenTutorial(archivo: archivo)
    }

    /// El «Recorrido con tu empresa» está en marcha para esa empresa.
    public func recorridoEnCurso(empresa: UUID) -> Bool {
        TutorialEventos.estado(.tuEmpresa, empresa: empresa, almacen: almacenTutorial).fase == .enCurso
    }
}

/// Lo que puede hacer la ventana (lo pone la vista con su `openWindow` y su `dismiss`).
@MainActor
public struct AccionesVentana {
    public var abrirEmpresa: (UUID) -> Void
    public var abrirSelector: () -> Void
    public var cerrar: () -> Void

    public init(abrirEmpresa: @escaping (UUID) -> Void = { _ in }, abrirSelector: @escaping () -> Void = {},
                cerrar: @escaping () -> Void = {}) {
        self.abrirEmpresa = abrirEmpresa; self.abrirSelector = abrirSelector; self.cerrar = cerrar
    }
}
