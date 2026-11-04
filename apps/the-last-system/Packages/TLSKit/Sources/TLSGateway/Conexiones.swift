import Foundation

/// Cómo se habla con el otro programa.
public enum TransporteDeConexion: Codable, Sendable, Hashable {
    /// Por internet (preferente): `HTTPClientTransport`.
    case http(HTTPDeConexion)
    /// Un programa que se ejecuta en tu Mac (con aviso y su propio perfil de sandbox).
    case stdio(StdioDeConexion)

    public var esStdio: Bool {
        if case .stdio = self { return true }
        return false
    }
}

/// Dirección del servidor y en qué cabecera va la clave (la clave, en el Llavero).
public struct HTTPDeConexion: Codable, Sendable, Hashable {
    /// `https://…` (o `http://localhost…` para un programa local).
    public var url: String
    /// Cabecera que lleva la clave (`Authorization`), si la hay.
    public var cabecera: String?
    /// Lo que va delante de la clave (`Bearer `).
    public var prefijo: String
    /// Campo del Llavero con la clave (`token`).
    public var campo: String?

    public init(url: String, cabecera: String? = "Authorization", prefijo: String = "Bearer ", campo: String? = "token") {
        self.url = url; self.cabecera = cabecera; self.prefijo = prefijo; self.campo = campo
    }
}

/// Programa local: su ruta y sus argumentos (sin claves: en esta versión, un programa local no recibe ninguna).
public struct StdioDeConexion: Codable, Sendable, Hashable {
    public var ejecutable: String
    public var argumentos: [String]
    /// Leíste y aceptaste el aviso («se ejecuta en tu Mac, sin acceso a tu carpeta ni a tus documentos»).
    public var avisoAceptado: Bool

    public init(ejecutable: String, argumentos: [String] = [], avisoAceptado: Bool = false) {
        self.ejecutable = ejecutable; self.argumentos = argumentos; self.avisoAceptado = avisoAceptado
    }
}

/// Una conexión con otro programa (en `conexiones.json`, **sin secretos**: solo el nombre de sus campos).
public struct Conexion: Codable, Sendable, Hashable, Identifiable {
    /// Nombre corto (`ghl`): 2–20 letras minúsculas o cifras, empieza por letra. Va en `ext_<id>_…` y en el Llavero.
    public var id: String
    /// En pantalla («GoHighLevel»).
    public var nombre: String
    /// Plantilla de la que sale (`web`, `ghl`, `stripe`, `calendly`, `generico`).
    public var plantilla: String
    public var transporte: TransporteDeConexion
    /// Campos guardados en el Llavero (`token`): nunca sus valores.
    public var secretos: [String]
    /// Apagada: no se conecta, no se sincroniza y ningún asistente la ve.
    public var activa: Bool
    public var catalogo: CatalogoDeConexion?
    /// Cada cuánto se sincroniza (minutos; 0 = a mano).
    public var sincronizarCadaMinutos: Int
    public var ultimaSincronizacion: Date?
    public var creada: Date

    public init(id: String, nombre: String, plantilla: String, transporte: TransporteDeConexion, secretos: [String] = [],
                activa: Bool = true, catalogo: CatalogoDeConexion? = nil, sincronizarCadaMinutos: Int = 60,
                ultimaSincronizacion: Date? = nil, creada: Date = Date()) {
        self.id = id; self.nombre = nombre; self.plantilla = plantilla; self.transporte = transporte; self.secretos = secretos
        self.activa = activa; self.catalogo = catalogo; self.sincronizarCadaMinutos = sincronizarCadaMinutos
        self.ultimaSincronizacion = ultimaSincronizacion; self.creada = creada
    }

    /// `ext:<id>:<algo>` (origen de lo que se refleja en las fichas).
    public func origen(_ algo: String) -> String { "ext:\(id):\(algo)" }

    /// Nombre corto válido: 2–20, minúsculas o cifras, empieza por letra (sin `_`, para que `ext_<id>_…` se lea bien).
    public static func idValido(_ id: String) -> Bool {
        id.range(of: #"^[a-z][a-z0-9]{1,19}$"#, options: .regularExpression) != nil
    }

    /// Comprueba lo que se va a guardar: id, dirección y que nada parezca una clave.
    public func validar() throws {
        guard Self.idValido(id) else { throw ErrorDePasarela.identificadorNoValido(id) }
        if Ocultador.pareceSecreto(nombre) { throw ErrorDePasarela.pareceUnSecreto("nombre") }
        switch transporte {
        case .http(let h):
            guard let u = URL(string: h.url), let esquema = u.scheme?.lowercased(), let host = u.host?.lowercased() else {
                throw ErrorDePasarela.direccionNoValida("escribe la dirección completa, con https://.")
            }
            let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
            guard esquema == "https" || (esquema == "http" && local) else {
                throw ErrorDePasarela.direccionNoValida("tiene que empezar por https://.")
            }
            guard u.user == nil, u.password == nil else { throw ErrorDePasarela.pareceUnSecreto("dirección") }
            if Ocultador.pareceSecreto(h.url) || (u.query ?? "").range(of: #"(?i)(key|token|secret|password|auth)="#,
                                                                       options: .regularExpression) != nil {
                throw ErrorDePasarela.pareceUnSecreto("dirección")
            }
            if let c = h.campo, !secretos.contains(c) { throw ErrorDePasarela.faltaSecreto(c) }
        case .stdio(let s):
            guard s.ejecutable.hasPrefix("/") else { throw ErrorDePasarela.direccionNoValida("escribe la ruta completa del programa.") }
            if s.argumentos.contains(where: Ocultador.pareceSecreto) { throw ErrorDePasarela.pareceUnSecreto("argumentos") }
            guard secretos.isEmpty else { throw ErrorDePasarela.stdioConSecretos }
        }
    }
}

/// `conexiones.json` en el directorio que diga la app (Application Support de la empresa). Solo configuración: los
/// secretos están en el Llavero. Se escribe entero, de forma atómica y con permisos 0600.
public final class AlmacenDeConexiones: @unchecked Sendable {
    public let directorio: URL
    private let lock = NSLock()

    struct Fichero: Codable {
        var version: Int
        var conexiones: [Conexion]
    }

    public init(directorio: URL) {
        self.directorio = directorio
    }

    public var url: URL { directorio.appendingPathComponent(TLSGatewayInfo.ficheroConexiones) }

    public func todas() -> [Conexion] {
        lock.withLock { leer() }
    }

    public func conexion(_ id: String) -> Conexion? {
        todas().first { $0.id == id }
    }

    /// Guarda (o sustituye) una conexión, ya validada.
    public func guardar(_ c: Conexion) throws {
        try c.validar()
        try lock.withLock {
            var todas = leer()
            if let i = todas.firstIndex(where: { $0.id == c.id }) { todas[i] = c } else { todas.append(c) }
            try escribir(todas)
        }
    }

    /// Cambia una conexión que ya existe.
    @discardableResult
    public func cambiar(_ id: String, _ cambio: (inout Conexion) throws -> Void) throws -> Conexion {
        try lock.withLock {
            var todas = leer()
            guard let i = todas.firstIndex(where: { $0.id == id }) else { throw ErrorDePasarela.conexionDesconocida(id) }
            try cambio(&todas[i])
            try todas[i].validar()
            try escribir(todas)
            return todas[i]
        }
    }

    /// Quita una conexión de la configuración (sus claves las borra `Pasarela.quitar`).
    public func quitar(_ id: String) throws {
        try lock.withLock {
            let todas = leer()
            try escribir(todas.filter { $0.id != id })
        }
    }

    private func leer() -> [Conexion] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode(Fichero.self, from: d))?.conexiones ?? []
    }

    private func escribir(_ conexiones: [Conexion]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directorio, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .iso8601
        let datos = try enc.encode(Fichero(version: 1, conexiones: conexiones.sorted { $0.id < $1.id }))
        try datos.write(to: url, options: [.atomic])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
