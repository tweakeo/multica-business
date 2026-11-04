import Foundation
import TLSCore
import TLSDesign
import TLSImport

// F3 · rol ordenar. Por dónde escriben las pantallas de importación (ordenar, Multica, actualizar la copia): por la
// sesión de la empresa si está abierta (así sus ventanas se enteran al momento y el escritor es el mismo) o, si no, con
// un escritor propio que se abre para cada cambio y se cierra al terminar (como «Empiezo de cero» del motor). Siempre
// por `CommandBus` y como la persona; nunca en la carpeta real ni en una copia en solo lectura.

/// Acceso a la carpeta de una empresa para leer su foto y escribir planes.
@MainActor
public final class AccesoEmpresa {
    public let entry: VaultEntry
    public let raiz: URL
    /// Estado de la app para esta empresa (`<Application Support>/<id>`): diario, mapas de importación, avisos ignorados.
    public let estado: URL
    public let appSupport: URL
    public let persona: String
    /// La sesión abierta, si se escribe por ella.
    public let sesion: VaultSession?

    /// Por la sesión abierta de la empresa (necesita su carpeta resuelta).
    public init?(sesion: VaultSession) {
        guard let root = sesion.root else { return nil }
        self.sesion = sesion
        self.entry = sesion.entry
        self.raiz = root
        self.estado = sesion.directorioEstado
        self.appSupport = sesion.estado?.appendingPathComponent("asup", isDirectory: true) ?? AppLocations.appSupport
        self.persona = sesion.persona
    }

    /// Con un escritor propio (la empresa no está abierta en ninguna ventana).
    public init(entry: VaultEntry, raiz: URL, appSupport: URL = AppLocations.appSupport, estado: URL? = nil,
                persona: String = AppModel.personaPorDefecto) {
        self.sesion = nil
        self.entry = entry
        self.raiz = raiz.standardizedFileURL
        self.appSupport = appSupport
        self.estado = estado ?? appSupport.appendingPathComponent(entry.id.uuidString.lowercased(), isDirectory: true)
        self.persona = persona
    }

    public var autor: Autor { .persona(sesion?.persona ?? persona) }

    /// `nil` si se puede escribir; si no, por qué (en llano).
    public var motivoSoloLectura: String? {
        if entry.clase == .real, !entry.realTrasRelevo { return "es tu carpeta original y aquí solo se lee" }
        if let sesion {
            if case .soloLectura(let m) = sesion.modoEscritura { return m.texto.lowercased() }
            if sesion.bus == nil { return "la carpeta aún se está abriendo" }
            return nil
        }
        return entry.escritura == .permitida ? nil : "esta copia está en solo lectura"
    }

    // MARK: Leer

    /// Foto de la carpeta (sin lo que se dejó fuera de la copia). Lo privado está: quien enseña, lo filtra.
    public func foto() async -> VaultSnapshot? {
        if let sesion { return await sesion.instantanea() }
        let raiz = self.raiz
        let e = entry
        return await Task.detached(priority: .userInitiated) {
            FileManager.default.fileExists(atPath: raiz.path) ? VaultSnapshot.read(entry: e, root: raiz) : nil
        }.value
    }

    // MARK: Escribir

    /// Da el bus (y el motor del dominio, si hay) para una operación. Con escritor propio, lo abre y lo cierra al acabar.
    public func conBus<T: Sendable>(_ hacer: (CommandBus, MotorDeDominio?) async throws -> T) async throws -> T {
        if let motivo = motivoSoloLectura { throw ErrorAccesoEmpresa.soloLectura(motivo) }
        if let sesion {
            guard let bus = sesion.bus else { throw ErrorAccesoEmpresa.soloLectura("la carpeta aún se está abriendo") }
            return try await hacer(bus, DominioEmpresa.motor(de: sesion))
        }
        let writer = try await VaultWriter.open(entry: entry, root: raiz,
                                                options: .init(stateDirectory: estado, appSupport: appSupport))
        let bus = CommandBus(writer: writer)
        let motor = try? MotorDeDominio(bus: bus, opciones: .init(persona: persona))
        do {
            let r = try await hacer(bus, motor)
            await writer.close()
            return r
        } catch {
            await writer.close()
            throw error
        }
    }

    /// Escribe un plan de la persona. `importacion`: las reglas del dominio no se disparan mientras dura (lo traído entra
    /// como antecedente). `dominio`: pasa por el dominio (invariantes y eventos), como lo que toca registros de Finanzas.
    @discardableResult
    public func escribir(plan: WritePlan, dominio: Bool = false, importacion: Bool = false, aviso: String? = nil,
                         deshacer: UndoManager? = nil) async throws -> WriteResult {
        if let sesion {
            if let motivo = motivoSoloLectura { throw ErrorAccesoEmpresa.soloLectura(motivo) }
            let motor = DominioEmpresa.motor(de: sesion)
            if importacion { await motor?.setModoImportacion(true) }
            do {
                let r = dominio && motor != nil
                    ? try await sesion.escribirConDominio(plan: plan, aviso: aviso, deshacer: deshacer).escritura
                    : try await sesion.escribir(plan: plan, aviso: aviso, deshacer: deshacer)
                if importacion { await motor?.setModoImportacion(false) }
                return r
            } catch {
                if importacion { await motor?.setModoImportacion(false) }
                throw error
            }
        }
        return try await conBus { bus, motor in
            if importacion { await motor?.setModoImportacion(true) }
            do {
                let r: WriteResult
                if dominio, let motor { r = try await motor.ejecutar(plan).escritura } else { r = try await bus.ejecutar(plan) }
                if importacion { await motor?.setModoImportacion(false) }
                return r
            } catch {
                if importacion { await motor?.setModoImportacion(false) }
                throw error
            }
        }
    }

    /// Deshace unos planes (el más reciente primero), solo si son lo último que se escribió en la carpeta.
    @discardableResult
    public func deshacer(planes: [UUID]) async throws -> WriteResult {
        let autor = self.autor
        let r = try await conBus { bus, _ in try await ImportApplier.deshacer(planes: planes, con: bus, autor: autor) }
        if let sesion {
            sesion.aplicarMovimientos(r.movidas.map { (de: $0.de, a: $0.a) })
            DominioEmpresa.olvidar(planes, de: sesion)
        }
        return r
    }

    /// `true` si esos planes son lo último que se escribió (nada se ha escrito después).
    public func sePuedeDeshacer(planes: [UUID]) async -> Bool {
        guard !planes.isEmpty, motivoSoloLectura == nil else { return false }
        return (try? await conBus { bus, _ in await ImportApplier.sePuedeDeshacer(planes: planes, con: bus) }) ?? false
    }

    /// Tras mover ficheros: las pestañas abiertas de la empresa siguen llevando a su sitio.
    func movidos(_ movs: [Movimiento]) {
        sesion?.aplicarMovimientos(movs.map { (de: $0.de, a: $0.a) })
    }

    // MARK: Ajustes de la app (fuera de la carpeta de la empresa)

    /// Carpeta del estado de la app para esta empresa, creada con permisos 0700.
    func carpetaEstado(_ sub: String? = nil) throws -> URL {
        let dir = sub.map { estado.appendingPathComponent($0, isDirectory: true) } ?? estado
        guard !AppLocations.isInICloudDrive(dir.path) else { throw ErrorAccesoEmpresa.estadoEnICloud }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return dir
    }
}

/// Lo que impide escribir, en llano.
public enum ErrorAccesoEmpresa: Error, LocalizedError, Equatable {
    case soloLectura(String)
    case estadoEnICloud

    public var errorDescription: String? {
        switch self {
        case .soloLectura(let m): "No se puede escribir: \(m)."
        case .estadoEnICloud: "Los ajustes de la app no pueden ir dentro de iCloud Drive."
        }
    }
}
