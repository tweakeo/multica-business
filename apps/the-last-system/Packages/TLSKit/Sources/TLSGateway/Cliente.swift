import Foundation
import MCP
import System

/// Un cliente abierto con otro programa. Lo usa solo la `Pasarela` (nunca un asistente).
public protocol ClienteExterno: Sendable {
    func listarHerramientas() async throws -> [Tool]
    func llamar(_ nombre: String, argumentos: [String: Value]) async throws -> CallTool.Result
    func cerrar() async
}

/// Abre clientes. La de la app es `FabricaMCP`; en pruebas, la misma con una configuración de URL propia.
public protocol FabricaDeClientes: Sendable {
    /// `secretos`: campo → valor, leídos del Llavero en este momento (no se guardan en ningún otro sitio).
    /// `alCambiarLista`: el programa avisó de que cambió su lista de herramientas (`listChanged`).
    func abrir(_ c: Conexion, secretos: [String: String],
               alCambiarLista: @escaping @Sendable () async -> Void) async throws -> any ClienteExterno
}

/// Clientes MCP del SDK Swift: HTTP (`HTTPClientTransport`, la clave en su cabecera) o stdio (un proceso con su perfil
/// de sandbox, sin claves).
public struct FabricaMCP: FabricaDeClientes {
    /// Configuración de URL (en pruebas, con un `URLProtocol` propio; nada sale a la red).
    public var configuracionHTTP: @Sendable () -> URLSessionConfiguration
    /// Escuchar avisos del programa (necesario para `listChanged` por HTTP).
    public var escucharAvisos: Bool
    /// Plazo de cada petición.
    public var plazo: Duration
    /// Para stdio: directorio de trabajo (`<ASUP>/<empresa>/conexiones/<id>/`) y carpetas que el programa no puede leer.
    public var directorioStdio: @Sendable (Conexion) -> URL
    public var carpetasProhibidas: [String]

    public init(configuracionHTTP: @escaping @Sendable () -> URLSessionConfiguration = { Self.configuracionPorDefecto() },
                escucharAvisos: Bool = true, plazo: Duration = .seconds(60),
                directorioStdio: @escaping @Sendable (Conexion) -> URL = { c in
                    FileManager.default.temporaryDirectory.appendingPathComponent("tls-conexion-\(c.id)", isDirectory: true)
                },
                carpetasProhibidas: [String] = []) {
        self.configuracionHTTP = configuracionHTTP; self.escucharAvisos = escucharAvisos; self.plazo = plazo
        self.directorioStdio = directorioStdio; self.carpetasProhibidas = carpetasProhibidas
    }

    /// Sin caché en disco ni cookies: nada de lo que responde el programa se queda en Application Support.
    public static func configuracionPorDefecto() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 60
        return c
    }

    public func abrir(_ c: Conexion, secretos: [String: String],
                      alCambiarLista: @escaping @Sendable () async -> Void) async throws -> any ClienteExterno {
        let client = Client(name: "The Last System", version: "1.0.0")
        await client.onNotification(ToolListChangedNotification.self) { _ in await alCambiarLista() }
        switch c.transporte {
        case .http(let h):
            guard let url = URL(string: h.url) else { throw ErrorDePasarela.direccionNoValida(h.url) }
            var cabecera: (String, String)?
            if let nombre = h.cabecera, let campo = h.campo {
                guard let v = secretos[campo], !v.isEmpty else { throw ErrorDePasarela.faltaSecreto(campo) }
                cabecera = (nombre, h.prefijo + v)
            }
            let fija = cabecera
            let transporte = HTTPClientTransport(endpoint: url, configuration: configuracionHTTP(), streaming: escucharAvisos,
                                                 requestModifier: { r in
                                                     var r = r
                                                     if let (n, v) = fija { r.setValue(v, forHTTPHeaderField: n) }
                                                     return r
                                                 })
            try await Plazo.con(plazo, nombre: c.nombre) { _ = try await client.connect(transport: transporte) }
            return ClienteMCP(client: client, nombre: c.nombre, plazo: plazo, proceso: nil)
        case .stdio(let s):
            guard s.avisoAceptado else { throw ErrorDePasarela.avisoSinAceptar }
            guard c.secretos.isEmpty else { throw ErrorDePasarela.stdioConSecretos }
            let proceso = try ProcesoStdio.lanzar(s, directorio: directorioStdio(c), prohibidas: carpetasProhibidas)
            let transporte = StdioTransport(input: FileDescriptor(rawValue: proceso.lectura),
                                            output: FileDescriptor(rawValue: proceso.escritura))
            do {
                try await Plazo.con(plazo, nombre: c.nombre) { _ = try await client.connect(transport: transporte) }
            } catch {
                proceso.terminar()
                throw error
            }
            return ClienteMCP(client: client, nombre: c.nombre, plazo: plazo, proceso: proceso)
        }
    }
}

/// Un cliente del SDK con plazo en cada petición.
actor ClienteMCP: ClienteExterno {
    let client: Client
    let nombre: String
    let plazo: Duration
    let proceso: ProcesoStdio?

    init(client: Client, nombre: String, plazo: Duration, proceso: ProcesoStdio?) {
        self.client = client; self.nombre = nombre; self.plazo = plazo; self.proceso = proceso
    }

    func listarHerramientas() async throws -> [Tool] {
        var todas: [Tool] = []
        var cursor: String?
        // Como mucho 20 páginas y 500 herramientas: un catálogo sin fin no bloquea la app.
        for _ in 0..<20 {
            let c = cursor
            let pagina = try await Plazo.con(plazo, nombre: nombre) { try await self.client.listTools(cursor: c) }
            todas += pagina.tools
            cursor = pagina.nextCursor
            if cursor == nil || todas.count >= 500 { break }
        }
        return Array(todas.prefix(500))
    }

    func llamar(_ herramienta: String, argumentos: [String: Value]) async throws -> CallTool.Result {
        try await Plazo.con(plazo, nombre: nombre) {
            let ctx: RequestContext<CallTool.Result> = try await self.client.send(
                CallTool.request(.init(name: herramienta, arguments: argumentos)))
            return try await ctx.value
        }
    }

    func cerrar() async {
        await client.disconnect()
        proceso?.terminar()
    }
}

/// Plazo para una operación con el otro programa.
enum Plazo {
    static func con<T: Sendable>(_ d: Duration, nombre: String, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { g in
            g.addTask { try await op() }
            g.addTask {
                try await Task.sleep(for: d)
                throw ErrorDePasarela.sinRespuesta(nombre)
            }
            defer { g.cancelAll() }
            guard let r = try await g.next() else { throw ErrorDePasarela.sinRespuesta(nombre) }
            return r
        }
    }
}

/// Perfil de sandbox de un programa local (PLAN §7.4: «stdio con aviso y su propio perfil de sandbox, como los
/// asistentes»): no lee ni escribe tu carpeta personal, otros discos ni las empresas; solo su directorio de trabajo y
/// el del propio programa; nada de AppleScript ni de eventos a otras apps; ningún socket local (ni el de `tls-mcp`).
public enum PerfilDeSandboxStdio {
    public static func texto(home: String, trabajo: String, ejecutable: String, prohibidas: [String] = []) -> String {
        func q(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        // El sandbox compara rutas reales (`/private/var/…`, sin enlaces).
        let homeReal = rutaReal(home)
        let ejecutableReal = rutaReal(ejecutable)
        let dirPrograma = URL(fileURLWithPath: ejecutableReal).deletingLastPathComponent().path
        let otrasNegadas = ["(subpath \"/Volumes\")"] + prohibidas.filter { !$0.isEmpty }.map { "(subpath \(q(rutaReal($0))))" }
        let negadas = ["(subpath \(q(homeReal)))"] + otrasNegadas
        // S9: en el perfil manda la última regla. El directorio del programa solo se abre si no reabre la carpeta
        // personal: fuera de ella, o dentro a dos niveles o más y fuera de `~/Library`. Si no, solo el propio ejecutable.
        let lecturaDirectorio = Self.directorioSeguro(dirPrograma, home: homeReal)
            ? "(allow file-read* (subpath \(q(dirPrograma))))\n" : ""
        let trabajo = rutaReal(trabajo)
        return """
            (version 1)
            (allow default)
            (deny file-read* file-write* \(negadas.joined(separator: " ")))
            (allow file-read-metadata)
            \(lecturaDirectorio)(deny file-read* file-write* \(otrasNegadas.joined(separator: " ")) (subpath \(q(homeReal + "/Library"))))
            (allow file-read* (literal \(q(ejecutableReal))))
            (allow file-read* file-write* (subpath \(q(trabajo))))
            (deny network-outbound (remote unix-socket))
            (deny process-exec (literal "/usr/bin/osascript"))
            (deny appleevent-send)

            """
    }

    /// ¿Se puede abrir entero el directorio del programa sin reabrir la carpeta personal?
    static func directorioSeguro(_ dir: String, home: String) -> Bool {
        guard dir == home || dir.hasPrefix(home + "/") else { return dir != "/" && !dir.isEmpty }
        let relativa = dir.dropFirst(home.count).split(separator: "/")
        return relativa.count >= 2 && relativa.first != "Library"
    }
}

/// La ruta real (`realpath`): resuelve enlaces y `/var` → `/private/var`. Si no existe, la de partida.
func rutaReal(_ p: String) -> String {
    guard let r = realpath(p, nil) else { return p }
    defer { free(r) }
    return String(cString: r)
}

/// Un programa local lanzado en su sandbox, con stdin y stdout para el protocolo. Entorno mínimo y sin claves.
final class ProcesoStdio: @unchecked Sendable {
    let proceso: Process
    let entrada: Pipe
    let salida: Pipe

    var lectura: Int32 { salida.fileHandleForReading.fileDescriptor }
    var escritura: Int32 { entrada.fileHandleForWriting.fileDescriptor }

    init(proceso: Process, entrada: Pipe, salida: Pipe) {
        self.proceso = proceso; self.entrada = entrada; self.salida = salida
    }

    static func lanzar(_ s: StdioDeConexion, directorio: URL, prohibidas: [String]) throws -> ProcesoStdio {
        let fm = FileManager.default
        let tmp = directorio.appendingPathComponent("tmp", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let home = fm.homeDirectoryForCurrentUser.path
        let perfil = directorio.appendingPathComponent("programa.sb")
        try PerfilDeSandboxStdio.texto(home: home, trabajo: directorio.path, ejecutable: s.ejecutable,
                                       prohibidas: prohibidas).write(to: perfil, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        p.arguments = ["-f", perfil.path, s.ejecutable] + s.argumentos
        p.currentDirectoryURL = directorio
        p.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "LANG": "es_ES.UTF-8",
                         "HOME": directorio.path, "TMPDIR": tmp.path]
        let entrada = Pipe()
        let salida = Pipe()
        p.standardInput = entrada
        p.standardOutput = salida
        p.standardError = FileHandle.nullDevice
        try p.run()
        return ProcesoStdio(proceso: p, entrada: entrada, salida: salida)
    }

    func terminar() {
        guard proceso.isRunning else { return }
        proceso.terminate()
        let pid = proceso.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [self] in
            if proceso.isRunning { kill(pid, SIGKILL) }
        }
    }
}
