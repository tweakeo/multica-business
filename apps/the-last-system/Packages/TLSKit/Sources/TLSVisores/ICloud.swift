import Darwin
import Foundation
import Observation

/// Dónde está un fichero: en este Mac o solo en iCloud (sin descargar).
public enum EstadoICloud: Sendable, Equatable {
    /// En el disco: se puede leer sin descargar nada.
    case local
    /// Solo en iCloud. `tamano` es el que tendrá al bajar (si se sabe).
    case soloEnICloud(tamano: Int64?)
    case noExiste
}

/// Acceso a iCloud de los visores. Sustituible en pruebas. **Mirar nunca descarga**: solo `pedirDescarga`,
/// que se llama cuando la persona abre el fichero (acción explícita), nunca al recorrer ni al pintar
/// una miniatura.
public protocol AccesoICloud: Sendable {
    /// Estado sin abrir el fichero (`lstat` y marcador antiguo `.nombre.icloud`).
    func estado(de url: URL) -> EstadoICloud
    /// Pide a iCloud que lo baje (`startDownloadingUbiquitousItem`).
    func pedirDescarga(de url: URL) throws
}

/// El de verdad: `lstat` con `SF_DATALESS` y `FileManager.startDownloadingUbiquitousItem`.
public struct AccesoICloudSistema: AccesoICloud {
    /// `SF_DATALESS` de `<sys/stat.h>`.
    static let marcaSinDatos: UInt32 = 0x4000_0000

    public init() {}

    public func estado(de url: URL) -> EstadoICloud {
        var st = stat()
        if lstat(url.path, &st) == 0 {
            return (st.st_flags & Self.marcaSinDatos) != 0 ? .soloEnICloud(tamano: Int64(st.st_size)) : .local
        }
        // Marcador antiguo de iCloud: «.acta.pdf.icloud» junto a donde estaría «acta.pdf».
        let marcador = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
        if lstat(marcador.path, &st) == 0 { return .soloEnICloud(tamano: nil) }
        return .noExiste
    }

    public func pedirDescarga(de url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// Ejecuta `cuerpo` en este hilo sin permitir que se materialicen ficheros de iCloud: leer uno sin
    /// descargar da error en vez de bajarlo. El cuerpo debe ser síncrono.
    public static func sinDescargar<T>(_ cuerpo: () throws -> T) rethrows -> T {
        let tipo = Int32(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES)
        let alcance = Int32(IOPOL_SCOPE_THREAD)
        let antes = getiopolicy_np(tipo, alcance)
        _ = setiopolicy_np(tipo, alcance, Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF))
        defer { _ = setiopolicy_np(tipo, alcance, antes >= 0 ? antes : Int32(IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT)) }
        return try cuerpo()
    }
}

/// Descarga explícita de un fichero que solo está en iCloud, con su progreso y «Volver a intentarlo».
///
/// - `comprobar()` solo mira (no descarga).
/// - `descargar()` pide la descarga y comprueba cada `intervalo` hasta que el fichero está en el Mac; si pasa
///   `limite`, queda en `.tardando` (sigue mirando y ofrece «Volver a intentarlo»).
@Observable @MainActor
public final class DescargaICloud {
    public enum Fase: Equatable, Sendable {
        case comprobando
        /// En el Mac: se puede enseñar.
        case lista
        /// Solo en iCloud: hace falta descargarlo para verlo.
        case soloEnICloud
        case descargando
        /// Baja más despacio de lo normal (sigue intentándolo).
        case tardando
        /// No se pudo pedir la descarga. Texto llano.
        case fallo(String)
        case noExiste
    }

    public let url: URL
    public private(set) var fase: Fase = .comprobando
    /// Tamaño que tendrá al bajar, si se sabe.
    public private(set) var tamano: Int64?
    /// Segundos que lleva descargando (para el texto del progreso).
    public private(set) var segundos = 0
    /// Fracción descargada, si el sistema la da (`nil` = progreso indeterminado).
    public private(set) var fraccion: Double?

    @ObservationIgnored private let acceso: any AccesoICloud
    @ObservationIgnored private let intervalo: Duration
    @ObservationIgnored private let limite: Duration
    @ObservationIgnored private var tarea: Task<Void, Never>?

    public init(url: URL, acceso: any AccesoICloud = AccesoICloudSistema(),
                intervalo: Duration = .milliseconds(500), limite: Duration = .seconds(120)) {
        self.url = url
        self.acceso = acceso
        self.intervalo = intervalo
        self.limite = limite
    }

    /// Mira dónde está, sin descargar.
    public func comprobar() {
        switch acceso.estado(de: url) {
        case .local:
            fase = .lista
        case .soloEnICloud(let t):
            tamano = t
            if fase != .descargando && fase != .tardando { fase = .soloEnICloud }
        case .noExiste:
            fase = .noExiste
        }
    }

    /// Pide la descarga (solo al abrir: acción explícita de la persona) y espera a que llegue.
    public func descargar() {
        comprobar()
        guard fase != .lista, fase != .noExiste else { return }
        do {
            try acceso.pedirDescarga(de: url)
        } catch {
            fase = .fallo("No he podido pedir la descarga a iCloud. Comprueba la conexión y vuelve a intentarlo.")
            return
        }
        fase = .descargando
        segundos = 0
        tarea?.cancel()
        let reloj = ContinuousClock()
        let inicio = reloj.now
        tarea = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: self.intervalo)
                guard !Task.isCancelled else { return }
                let pasado = reloj.now - inicio
                self.segundos = Int(pasado.components.seconds)
                switch self.acceso.estado(de: self.url) {
                case .local:
                    self.fraccion = 1
                    self.fase = .lista
                    return
                case .noExiste:
                    self.fase = .noExiste
                    return
                case .soloEnICloud:
                    if pasado > self.limite, self.fase == .descargando { self.fase = .tardando }
                }
            }
        }
    }

    /// «Volver a intentarlo».
    public func reintentar() {
        tarea?.cancel()
        tarea = nil
        fase = .soloEnICloud
        descargar()
    }

    /// Deja de mirar (al cerrar el visor). La descarga que ya pidió iCloud sigue sola.
    public func cancelar() {
        tarea?.cancel()
        tarea = nil
    }

    /// Texto del estado para la persona.
    public var texto: String {
        switch fase {
        case .comprobando: "Comprobando dónde está…"
        case .lista: "Listo"
        case .soloEnICloud:
            "Está solo en iCloud." + (TamanoFichero.texto(tamano).map { " Ocupa \($0)." } ?? "")
        case .descargando:
            "Descargando de iCloud…" + (TamanoFichero.texto(tamano).map { " (\($0))" } ?? "")
        case .tardando: "Está tardando más de lo normal. Sigo esperando a iCloud."
        case .fallo(let t): t
        case .noExiste: "No encuentro este fichero. Puede que se haya movido."
        }
    }
}
