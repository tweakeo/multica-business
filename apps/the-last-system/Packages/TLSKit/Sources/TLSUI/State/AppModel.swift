import Foundation
import Observation
import OSLog
import TLSCore
import TLSImport

/// Estado de la app: carpetas registradas en esta instalación y la sesión abierta de cada empresa.
@Observable @MainActor
public final class AppModel {
    /// Carpetas registradas, las más recientes primero.
    public private(set) var entries: [VaultEntry] = []

    /// Nombre con el que firma la persona lo que escribe desde la app (`Autor.persona`).
    public var persona: String {
        didSet {
            let limpio = persona.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults?.set(limpio.isEmpty ? nil : limpio, forKey: Self.clavePersona)
            for s in sesiones.values { s.persona = personaEfectiva }
        }
    }

    /// Tamaño del texto de la app (85–200 %), Ajustes › Visualización.
    public var escalaTexto: Double {
        didSet { defaults?.set(escalaTexto, forKey: Self.claveEscala) }
    }

    /// Cuándo sale la vista previa (Ajustes › Vista previa, §2.5).
    public var modoVistaPrevia: ModoVistaPrevia {
        didSet { defaults?.set(modoVistaPrevia.rawValue, forKey: Self.claveVistaPrevia) }
    }

    /// Última empresa con una ventana delante (para la pestaña nueva del botón «+» de la barra de pestañas).
    public var ultimaEmpresa: UUID?

    @ObservationIgnored public let registry: VaultRegistry
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var sesiones: [UUID: VaultSession] = [:]
    @ObservationIgnored private var usos: [UUID: Int] = [:]
    @ObservationIgnored private var cierres: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var arranques: [UUID: Task<Void, Never>] = [:]

    public static let personaPorDefecto = "Manu"
    static let clavePersona = "tls.persona"
    static let claveEscala = "tls.escalaTexto"
    static let claveVistaPrevia = "tls.vistaPrevia"
    private static let log = Logger(subsystem: "es.thelast.system", category: "AppModel")

    /// `defaults` = `nil` en pruebas (no toca las preferencias del Mac).
    public init(registry: VaultRegistry = VaultRegistry(), defaults: UserDefaults? = nil) {
        self.registry = registry
        self.defaults = defaults
        self.persona = defaults?.string(forKey: Self.clavePersona) ?? Self.personaPorDefecto
        let escala = defaults?.double(forKey: Self.claveEscala) ?? 0
        self.escalaTexto = escala == 0 ? 1 : min(max(escala, 0.85), 2)
        self.modoVistaPrevia = defaults?.string(forKey: Self.claveVistaPrevia).flatMap(ModoVistaPrevia.init(rawValue:)) ?? .alPasar
        reload()
    }

    /// El de la app: con las preferencias del Mac, las copias de F0 ya con escritura y, al arrancar, la puesta en marcha
    /// en lugar del selector si aún no hay ninguna empresa (`abrirPuestaAlArrancar`).
    public static func deLaApp() -> AppModel {
        let model = AppModel(defaults: .standard)
        model.prepararEscritura()
        model.abrirPuestaAlArrancar = true
        return model
    }

    /// Solo en la app (nunca en pruebas): el arranque abre la puesta en marcha si no hay ninguna empresa ni ninguna
    /// puesta en marcha a medias. Se usa una vez.
    @ObservationIgnored public var abrirPuestaAlArrancar = false

    /// Dónde guarda la app su estado (`vaults.json`, `onboarding.json`…): el del registro.
    public var appSupport: URL { registry.directory }

    /// El nombre que se usa (nunca vacío).
    public var personaEfectiva: String {
        let p = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? Self.personaPorDefecto : p
    }

    /// Al arrancar con F1: las copias que F0 registró en solo lectura pasan a poder escribirse
    /// (`VaultRegistry.permitirEscrituraEnCopias`, solo la primera vez). La carpeta real, nunca.
    public func prepararEscritura() {
        do {
            _ = try registry.permitirEscrituraEnCopias()
        } catch {
            Self.log.error("No he podido revisar qué copias se pueden escribir: \(error.localizedDescription, privacy: .public)")
        }
        reload()
    }

    // MARK: Sesiones compartidas

    /// La sesión de una empresa, compartida por todas sus pestañas y ventanas. La primera vez la abre.
    /// Cada `retenerSesion` necesita su `soltarSesion` (al desaparecer la ventana).
    public func retenerSesion(_ id: UUID) -> VaultSession? {
        cierres[id]?.cancel()
        cierres[id] = nil
        usos[id, default: 0] += 1
        ultimaEmpresa = id
        if let s = sesiones[id] { return s }
        guard let entry = entry(id: id) else { usos[id] = nil; return nil }
        let s = VaultSession(entry: entry)
        s.persona = personaEfectiva
        sesiones[id] = s
        arranques[id] = Task { [weak self] in
            guard let self else { return }
            await s.start(using: self)
            self.arranques[id] = nil
        }
        return s
    }

    /// Suelta una sesión; si nadie más la usa, se cierra al cabo de un momento (cambiar de pestaña no
    /// la cierra y la vuelve a abrir).
    public func soltarSesion(_ id: UUID) {
        guard let n = usos[id] else { return }
        if n > 1 { usos[id] = n - 1; return }
        usos[id] = 0
        cierres[id]?.cancel()
        cierres[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.usos[id] == 0 else { return }
            self.arranques[id]?.cancel()
            self.sesiones[id]?.close()
            self.sesiones[id] = nil
            self.usos[id] = nil
            self.cierres[id] = nil
        }
    }

    /// Sesión abierta de una empresa, si la hay (sin retenerla).
    public func sesionAbierta(_ id: UUID) -> VaultSession? { sesiones[id] }

    public func reload() {
        entries = registry.load()
    }

    public func entry(id: UUID) -> VaultEntry? {
        entries.first { $0.id == id }
    }

    public func register(_ entry: VaultEntry) throws {
        try registry.upsert(entry)
        reload()
    }

    /// Quita la carpeta de la lista. No borra nada del disco.
    public func remove(id: UUID) throws {
        try registry.remove(id: id)
        reload()
    }

    /// «Ver sin tocar»: registra la carpeta en solo lectura (o reutiliza la entrada que ya exista).
    /// `privadas` son rutas relativas que no se abren ni se listan; se suman a las ya guardadas.
    ///
    /// `config` es lo que dice su `.tls/config.yaml` (`CopyConfig.peek`): si es una copia hecha por
    /// la app (por ejemplo, una que se quitó de la lista), vuelve como copia, con su identificador
    /// (reutiliza su índice), su banner y su insignia; nunca se presenta como la carpeta real.
    @discardableResult
    public func registerReadOnly(url: URL, privadas: [VaultPath] = [],
                                 config: CopyConfig.Peek? = nil) throws -> VaultEntry {
        let ruta = url.standardizedFileURL.path
        let esCopia = config?.clase == .copia
        let clase: VaultClass = esCopia ? .copia : .real
        let nueva = { (id: UUID) in
            VaultEntry(id: id, nombre: url.lastPathComponent, ruta: ruta, bookmark: nil, clase: clase,
                       escritura: .bloqueada, origen: esCopia ? config?.origen : nil,
                       creada: esCopia ? (config?.creada?.date() ?? Date()) : Date())
        }
        var entry: VaultEntry
        if let existing = entries.first(where: { $0.clase == clase && $0.ruta == ruta }) {
            entry = existing
        } else if esCopia, let id = config?.id {
            // Su propio id, salvo que lo use otra carpeta presente (una copia duplicada en Finder).
            if let same = entries.first(where: { $0.id == id }) {
                let donde = resolveURL(same)?.standardizedFileURL.path
                entry = (donde == nil || donde == ruta) ? same : nueva(UUID())
            } else {
                entry = nueva(id)
            }
        } else {
            entry = nueva(UUID())
        }
        entry.ruta = ruta
        entry.clase = clase
        entry.escritura = .bloqueada
        for path in privadas where !path.isRoot && !entry.exclusionesCopia.contains(path.raw) {
            entry.exclusionesCopia.append(path.raw)
        }
        entry.bookmark = try? VaultRegistry.makeBookmark(for: url)
        try register(entry)
        return entry
    }

    /// Una carpeta privada guardada ya no está (se movió o cambió de nombre): se quita y se añaden
    /// las que la persona vuelva a elegir (`[]` = «No hay»).
    public func replaceExclusion(id: UUID, missing: String, with elegidas: [VaultPath]) throws {
        guard var entry = entry(id: id) else { return }
        let key = TextFolding.pathKey(missing)
        entry.exclusionesCopia.removeAll { TextFolding.pathKey($0) == key }
        for path in elegidas where !path.isRoot && !entry.exclusionesCopia.contains(path.raw) {
            entry.exclusionesCopia.append(path.raw)
        }
        try register(entry)
    }

    public func resolveURL(_ entry: VaultEntry) -> URL? {
        registry.resolveURL(entry)
    }
}

/// Cuándo sale la vista previa de una ficha (§2.5 y pregunta 6: al pasar el puntero, desactivable).
public enum ModoVistaPrevia: String, CaseIterable, Sendable, Identifiable {
    /// Al dejar el puntero 0,6 s encima (por defecto) o con la barra espaciadora.
    case alPasar
    /// Solo con la barra espaciadora.
    case soloEspacio
    /// Al pasar el puntero con ⌘ pulsado (y con la barra espaciadora).
    case conComando

    public var id: String { rawValue }

    public var titulo: String {
        switch self {
        case .alPasar: "Al pasar el puntero"
        case .soloEspacio: "Solo con la barra espaciadora"
        case .conComando: "Al pasar con ⌘ pulsado"
        }
    }
}
