import Foundation
import Observation
import OSLog
import TLSCore
import TLSDesign

/// Cómo tienes cada inicio (Hoy y el Resumen de las seis áreas) en esta empresa: uno por empresa abierta, guardado en
/// `inicios.json` dentro de su estado (Application Support), nunca en la carpeta. Cada cambio deja un aviso con
/// «Deshacer» («Ocultaste «Caja» del inicio»).
@Observable @MainActor
final class AlmacenInicios {
    private(set) var inicios: [String: DisposicionInicio] = [:]
    /// Inicios en modo edición (por su clave). No se guarda: al abrir la empresa, ninguno.
    private(set) var editando: Set<String> = []

    @ObservationIgnored let archivo: URL?
    @ObservationIgnored private weak var sesion: VaultSession?
    private static let log = Logger(subsystem: "es.thelast.system", category: "Inicios")

    private final class Entrada {
        weak var sesion: VaultSession?
        let almacen: AlmacenInicios
        init(_ s: VaultSession, _ a: AlmacenInicios) { sesion = s; almacen = a }
    }

    private static var porSesion: [ObjectIdentifier: Entrada] = [:]

    /// El de esta empresa abierta.
    static func de(_ sesion: VaultSession) -> AlmacenInicios {
        porSesion = porSesion.filter { $0.value.sesion != nil }
        let k = ObjectIdentifier(sesion)
        if let e = porSesion[k], e.sesion === sesion { return e.almacen }
        let a = AlmacenInicios(archivo: sesion.directorioEstado.appendingPathComponent("inicios.json"), sesion: sesion)
        porSesion[k] = Entrada(sesion, a)
        return a
    }

    /// `archivo` = `nil` en pruebas: solo en memoria.
    init(archivo: URL?, sesion: VaultSession? = nil) {
        self.archivo = archivo
        self.sesion = sesion
        if let archivo, let data = try? Data(contentsOf: archivo) {
            inicios = Self.leer(data)
        }
    }

    func alternarEdicion(_ inicio: InicioID, _ activo: Bool) {
        if activo { editando.insert(inicio.clave) } else { editando.remove(inicio.clave) }
    }

    func disposicion(_ inicio: InicioID) -> DisposicionInicio {
        inicios[inicio.clave] ?? CatalogoModulos.deSerie(inicio)
    }

    /// Aplica un cambio. Si cambia algo, lo guarda y, con `aviso`, deja «… · Deshacer» en la sesión.
    @discardableResult
    func cambiar(_ inicio: InicioID, aviso: String? = nil, _ cambio: (inout DisposicionInicio) -> Bool) -> Bool {
        let antes = disposicion(inicio)
        var d = antes
        guard cambio(&d), d != antes else { return false }
        inicios[inicio.clave] = d
        guardar()
        if let aviso, let sesion {
            sesion.aviso = Aviso(aviso, estado: nil, tituloAccion: "Deshacer") { [weak self] in
                self?.inicios[inicio.clave] = antes
                self?.guardar()
            }
        }
        return true
    }

    /// Vuelve a lo de serie.
    func restaurar(_ inicio: InicioID) {
        let antes = disposicion(inicio)
        inicios[inicio.clave] = nil
        guardar()
        sesion?.aviso = Aviso("Volviste al inicio de serie", tituloAccion: "Deshacer") { [weak self] in
            self?.inicios[inicio.clave] = antes
            self?.guardar()
        }
    }

    // MARK: Disco

    struct Pieza: Codable { var id: String; var tamano: String; var posicion: Int? }
    struct Forma: Codable { var visibles: [Pieza]; var ocultos: [Pieza] }
    struct Guardado: Codable { var version = 1; var inicios: [String: Forma] }

    /// Lee lo guardado; lo que ya no existe (un módulo retirado, un tamaño que no admite) se quita o se corrige.
    static func leer(_ data: Data) -> [String: DisposicionInicio] {
        guard let g = try? JSONDecoder().decode(Guardado.self, from: data) else { return [:] }
        var out: [String: DisposicionInicio] = [:]
        for (clave, f) in g.inicios {
            let vis = f.visibles.compactMap { p -> ModuloColocado? in
                guard let m = ModuloID(rawValue: p.id), let t = TamanoMosaico(rawValue: p.tamano) else { return nil }
                return ModuloColocado(m, t)
            }
            let ocu = f.ocultos.compactMap { p -> ModuloOculto? in
                guard let m = ModuloID(rawValue: p.id), let t = TamanoMosaico(rawValue: p.tamano) else { return nil }
                return ModuloOculto(modulo: m, tamano: t, posicion: p.posicion ?? 0)
            }
            out[clave] = DisposicionInicio(visibles: vis, ocultos: ocu).saneada()
        }
        return out
    }

    static func datos(_ inicios: [String: DisposicionInicio]) -> Data? {
        let g = Guardado(inicios: inicios.mapValues { d in
            Forma(visibles: d.visibles.map { Pieza(id: $0.modulo.rawValue, tamano: $0.tamano.rawValue, posicion: nil) },
                  ocultos: d.ocultos.map { Pieza(id: $0.modulo.rawValue, tamano: $0.tamano.rawValue, posicion: $0.posicion) })
        })
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? e.encode(g)
    }

    private func guardar() {
        guard let archivo, let data = Self.datos(inicios) else { return }
        do {
            try FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: archivo, options: .atomic)
        } catch {
            Self.log.error("No se pudo guardar el inicio: \(error.localizedDescription, privacy: .public)")
        }
    }
}
