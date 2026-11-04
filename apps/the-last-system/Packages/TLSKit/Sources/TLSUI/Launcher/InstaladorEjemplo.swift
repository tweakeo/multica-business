import Foundation
import TLSCore
import TLSImport

/// Errores al instalar el ejemplo, en texto llano.
enum ErrorEjemplo: Error, LocalizedError, Equatable {
    /// La app no trae el ejemplo (instalación dañada).
    case sinOrigen
    /// Ya hay una carpeta con ese nombre que no es el ejemplo: no se toca.
    case ocupado(String)
    /// El ejemplo está abierto en alguna ventana.
    case abierto
    case copia(String)

    var errorDescription: String? {
        switch self {
        case .sinOrigen:
            "No encuentro la empresa de ejemplo dentro de la app. Vuelve a instalar The Last System."
        case .ocupado(let nombre):
            "Ya hay una carpeta llamada «\(nombre)» que no es el ejemplo. Cámbiale el nombre en Finder y vuelve a intentarlo."
        case .abierto:
            "Cierra antes las ventanas del ejemplo."
        case .copia(let detalle):
            "No he podido preparar el ejemplo: \(detalle)"
        }
    }
}

/// «Ver un ejemplo»: instala Asesoría Ribera (ficticia) desde la app en
/// `~/The Last System/Empresas/Asesoría Ribera (ejemplo)/` con un `id` nuevo y la registra como ejemplo
/// (`clase: demo`, con escritura y Deshacer). Si ya está, la reutiliza. «Reiniciar ejemplo» la manda a la
/// Papelera (recuperable) y la instala otra vez.
///
/// - Nunca escribe encima de nada: copia a una carpeta temporal hermana, cambia ahí el `id` de
///   `.tls/config.yaml` y la renombra al final (de una vez). Lo que quede a medias va a la Papelera.
/// - En pruebas, `empresas`, el registro y la papelera son temporales (`TLS_EMPRESAS`, `TLS_APP_SUPPORT`):
///   nunca se instala en el `~/The Last System` de verdad.
struct InstaladorEjemplo: Sendable {
    static let nombre = "Asesoría Ribera"
    static let nombreCarpeta = "Asesoría Ribera (ejemplo)"

    /// El ejemplo que trae la app (`Contents/Resources/Recursos/Ejemplos/Asesoria-Ribera`).
    static var origenEnLaApp: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Recursos/Ejemplos/Asesoria-Ribera", isDirectory: true)
    }

    let origen: URL?
    let empresas: URL
    /// Mover a la Papelera (recuperable). En pruebas, a una carpeta temporal.
    let papelera: @Sendable (URL) throws -> Void

    init(origen: URL? = InstaladorEjemplo.origenEnLaApp, empresas: URL = AppLocations.empresas,
         papelera: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) {
        self.origen = origen
        self.empresas = empresas
        self.papelera = papelera
    }

    var destino: URL { empresas.appendingPathComponent(Self.nombreCarpeta, isDirectory: true) }

    enum Resultado: Equatable {
        case instalado(VaultEntry)
        case yaEstaba(VaultEntry)
        var entrada: VaultEntry {
            switch self { case .instalado(let e), .yaEstaba(let e): e }
        }
    }

    /// El ejemplo ya registrado cuya carpeta sigue en su sitio.
    @MainActor
    func existente(en model: AppModel) -> VaultEntry? {
        let clave = TextFolding.pathKey(destino.standardizedFileURL.path)
        return model.entries.first { e in
            e.clase == .demo && TextFolding.pathKey(URL(fileURLWithPath: e.ruta).standardizedFileURL.path) == clave
                && model.resolveURL(e) != nil
        }
    }

    /// Lo instala si no está; si está, lo devuelve para abrirlo.
    @MainActor
    func instalarOAbrir(en model: AppModel) async throws -> Resultado {
        model.reload()
        if let e = existente(en: model) { return .yaEstaba(e) }
        // Registrado, pero su carpeta ya no está: se quita de la lista (la carpeta no existe, no se borra nada).
        let clave = TextFolding.pathKey(destino.standardizedFileURL.path)
        for e in model.entries where e.clase == .demo && TextFolding.pathKey(URL(fileURLWithPath: e.ruta).standardizedFileURL.path) == clave {
            try? model.remove(id: e.id)
        }
        // La carpeta está, pero no en la lista (se quitó de la lista): se vuelve a registrar con su id.
        if FileManager.default.fileExists(atPath: destino.path) {
            let peek = try? await CopyConfig.peek(destino)
            guard peek?.clase == .demo else { throw ErrorEjemplo.ocupado(Self.nombreCarpeta) }
            let entrada = try registrar(id: peek?.id ?? UUID(), en: model)
            return .yaEstaba(entrada)
        }
        let id = UUID()
        try await copiar(id: id)
        return .instalado(try registrar(id: id, en: model))
    }

    /// «Reiniciar ejemplo»: el que hay va a la Papelera y se instala otro, nuevo. Las ventanas del ejemplo
    /// tienen que estar cerradas.
    @MainActor
    func reiniciar(en model: AppModel) async throws -> VaultEntry {
        model.reload()
        if let e = existente(en: model) {
            guard model.sesionAbierta(e.id) == nil else { throw ErrorEjemplo.abierto }
        }
        if FileManager.default.fileExists(atPath: destino.path) {
            let peek = try? await CopyConfig.peek(destino)
            guard peek?.clase == .demo else { throw ErrorEjemplo.ocupado(Self.nombreCarpeta) }
            let carpeta = destino
            let tirar = papelera
            try await Task.detached(priority: .userInitiated) { try tirar(carpeta) }.value
        }
        let clave = TextFolding.pathKey(destino.standardizedFileURL.path)
        for e in model.entries where e.clase == .demo && TextFolding.pathKey(URL(fileURLWithPath: e.ruta).standardizedFileURL.path) == clave {
            try? model.remove(id: e.id)
        }
        return try await instalarOAbrir(en: model).entrada
    }

    // MARK: Pasos

    @MainActor
    private func registrar(id: UUID, en model: AppModel) throws -> VaultEntry {
        let entrada = VaultEntry(id: id, nombre: Self.nombre, ruta: destino.standardizedFileURL.path,
                                 bookmark: try? VaultRegistry.makeBookmark(for: destino), clase: .demo,
                                 escritura: .permitida, creada: Date())
        try model.register(entrada)
        return entrada
    }

    /// Copia el ejemplo a una carpeta temporal hermana, le pone el `id` nuevo y la renombra al final.
    private func copiar(id: UUID) async throws {
        guard let origen, FileManager.default.fileExists(atPath: origen.appendingPathComponent(".tls/config.yaml").path) else {
            throw ErrorEjemplo.sinOrigen
        }
        guard !AppLocations.isInICloudDrive(empresas.path) else {
            throw ErrorEjemplo.copia("la carpeta de empresas no puede estar en iCloud Drive.")
        }
        let empresas = self.empresas
        let destino = self.destino
        let tirar = papelera
        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            do {
                try fm.createDirectory(at: empresas, withIntermediateDirectories: true)
            } catch {
                throw ErrorEjemplo.copia(error.localizedDescription)
            }
            let temporal = empresas.appendingPathComponent(".instalando-ejemplo-\(UUID().uuidString)", isDirectory: true)
            do {
                try fm.copyItem(at: origen, to: temporal)
                try Self.ponerID(id, en: temporal)
                try fm.moveItem(at: temporal, to: destino)
            } catch {
                if fm.fileExists(atPath: temporal.path) { try? tirar(temporal) }
                if fm.fileExists(atPath: destino.path) { throw ErrorEjemplo.ocupado(Self.nombreCarpeta) }
                throw ErrorEjemplo.copia(error.localizedDescription)
            }
        }.value
    }

    /// Cambia solo la línea `id:` de `.tls/config.yaml` (el resto de bytes, igual).
    static func ponerID(_ id: UUID, en carpeta: URL) throws {
        let config = carpeta.appendingPathComponent(".tls/config.yaml")
        let texto = try String(contentsOf: config, encoding: .utf8)
        var lineas = texto.components(separatedBy: "\n")
        guard let i = lineas.firstIndex(where: { $0.hasPrefix("id:") }) else {
            throw ErrorEjemplo.copia("al ejemplo le falta su identificador.")
        }
        lineas[i] = "id: \(id.uuidString.lowercased())"
        try Data(lineas.joined(separator: "\n").utf8).write(to: config, options: .atomic)
    }
}
