import Foundation

/// Lo que pregunta la app al sistema por un permiso. Lo real es `ConsultorDePermisosDelSistema`; en pruebas, un doble
/// (nunca se pide un permiso de verdad en las pruebas).
public protocol ConsultorDePermisos: Sendable {
    /// Estado actual, **sin preguntar** a la persona.
    func estado(_ p: PermisoDelSistema) async -> EstadoDePermiso
    /// Lanza el aviso de macOS (solo lo llama `PuertaDePermisos`, después de la explicación).
    func pedir(_ p: PermisoDelSistema) async -> EstadoDePermiso
}

/// Qué enseñar de un permiso ahora mismo.
public enum SituacionDePermiso: Sendable, Hashable {
    /// Todo bien.
    case listo
    /// Sin preguntar: primero la explicación; su botón llama a `PuertaDePermisos.pedir(_:tras:)`.
    case explicar(ExplicacionDePermiso)
    /// Denegado o restringido: pantalla de recuperación (no se vuelve a preguntar).
    case recuperar(RecuperacionDePermiso)
    /// No se sabe (Mail cerrado…): se vuelve a mirar más tarde, sin preguntar.
    case sinComprobar
}

/// Constancia de que la explicación se ha enseñado. Solo la fabrica `PuertaDePermisos.explicar(_:)`.
public struct ExplicacionVista: Sendable, Hashable {
    public let permiso: PermisoDelSistema
    let id: UUID
    let puerta: ObjectIdentifier
}

public enum ErrorDePermiso: Error, Sendable, Hashable, LocalizedError {
    /// Se intentó pedir sin enseñar antes la explicación (o con la de otro permiso).
    case sinExplicacion(PermisoDelSistema)

    public var errorDescription: String? {
        switch self {
        case .sinExplicacion(let p): "Antes de pedir el permiso de \(p.titulo) hay que explicar para qué es."
        }
    }
}

/// La única puerta para pedir permisos: **nunca se pide uno sin la explicación antes** y, si ya se denegó, no se vuelve
/// a preguntar (se enseña la recuperación). Una explicación vista sirve para una sola petición.
public actor PuertaDePermisos {
    let consultor: any ConsultorDePermisos
    private var vistas: Set<UUID> = []
    /// Peticiones hechas (para la auditoría y las pruebas).
    public private(set) var peticiones: [PermisoDelSistema] = []

    public init(consultor: any ConsultorDePermisos) {
        self.consultor = consultor
    }

    public func estado(_ p: PermisoDelSistema) async -> EstadoDePermiso {
        await consultor.estado(p)
    }

    /// Estado de todos (para Conexiones).
    public func estados() async -> [PermisoDelSistema: EstadoDePermiso] {
        var r: [PermisoDelSistema: EstadoDePermiso] = [:]
        for p in PermisoDelSistema.allCases { r[p] = await consultor.estado(p) }
        return r
    }

    /// Qué enseñar ahora de este permiso.
    public func situacion(_ p: PermisoDelSistema) async -> SituacionDePermiso {
        Self.situacion(p, estado: await consultor.estado(p))
    }

    public static func situacion(_ p: PermisoDelSistema, estado: EstadoDePermiso) -> SituacionDePermiso {
        switch estado {
        case .concedido: .listo
        case .sinPreguntar: .explicar(p.explicacion)
        case .denegado, .restringido: .recuperar(p.recuperacion)
        case .desconocido: .sinComprobar
        }
    }

    /// La pantalla enseña la explicación y se queda con esta constancia para el botón «Continuar».
    public func explicar(_ p: PermisoDelSistema) -> (explicacion: ExplicacionDePermiso, vista: ExplicacionVista) {
        let v = ExplicacionVista(permiso: p, id: UUID(), puerta: ObjectIdentifier(self))
        vistas.insert(v.id)
        return (p.explicacion, v)
    }

    /// Pide el permiso a macOS tras la explicación. Si ya estaba concedido, denegado o restringido, no pregunta: devuelve
    /// lo que hay (y la pantalla enseña la recuperación si hace falta).
    public func pedir(_ p: PermisoDelSistema, tras vista: ExplicacionVista) async throws -> EstadoDePermiso {
        guard vista.permiso == p, vista.puerta == ObjectIdentifier(self), vistas.remove(vista.id) != nil else {
            throw ErrorDePermiso.sinExplicacion(p)
        }
        let ahora = await consultor.estado(p)
        guard ahora == .sinPreguntar || ahora == .desconocido else { return ahora }
        peticiones.append(p)
        return await consultor.pedir(p)
    }
}

/// Tarjeta para Decisiones y Conexiones cuando un permiso falta (por ejemplo, la Automatización de Mail denegada al
/// leer el correo). La pinta la fase de pantallas; aquí, su contenido.
public struct TarjetaDePermiso: Sendable, Hashable, Identifiable {
    /// `permiso:<permiso>`: una sola tarjeta por permiso (no se repite en bucle).
    public var id: String { "permiso:" + permiso.rawValue }
    public let permiso: PermisoDelSistema
    public let titulo: String
    public let texto: String
    public let pasos: [String]
    public let boton: String
    public let enlace: URL
    /// Detalle técnico (código de error), solo para «Detalle técnico».
    public let detalleTecnico: String?

    public init(_ r: RecuperacionDePermiso, detalleTecnico: String? = nil) {
        permiso = r.permiso; titulo = r.titulo; texto = r.texto; pasos = r.pasos; boton = r.boton; enlace = r.enlace
        self.detalleTecnico = detalleTecnico
    }

    public static func de(_ p: PermisoDelSistema, detalleTecnico: String? = nil) -> TarjetaDePermiso {
        TarjetaDePermiso(p.recuperacion, detalleTecnico: detalleTecnico)
    }
}
