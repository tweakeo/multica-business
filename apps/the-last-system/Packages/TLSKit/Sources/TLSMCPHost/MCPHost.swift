import Darwin
import Foundation
import MCP
import TLSCore
import TLSMCPShared

/// Lo que responde a las peticiones de `tls-mcp` una vez validados el proceso y el token.
public protocol ManejadorIPC: Sendable {
    /// Herramientas que ve este asistente (mínimo privilegio: cada uno ve solo las suyas).
    func herramientas(para contexto: ContextoDelAsistente) async -> [ToolSpec]
    func llamar(_ nombre: String, argumentos: [String: Value], contexto: ContextoDelAsistente) async -> ToolResult
}

public enum MCPHostError: Error, LocalizedError, Equatable, Sendable {
    case rutaDemasiadoLarga(String)
    case carpetaNoSegura(String)
    case yaEnUso(String)
    case sistema(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .rutaDemasiadoLarga: "No puedo preparar la conexión de los asistentes: la ruta es demasiado larga."
        case .carpetaNoSegura: "No puedo preparar la conexión de los asistentes: su carpeta no es segura."
        case .yaEnUso: "Otra ventana de The Last System ya atiende a los asistentes de esta empresa."
        case .sistema(let op, let e): "No puedo preparar la conexión de los asistentes (\(op): \(String(cString: strerror(e))))."
        }
    }
}

/// Servidor del socket de los asistentes (PLAN §5.4), uno por empresa abierta con escritor.
///
/// - Socket BSD (`socket`/`bind`/`listen`, `DispatchSource` para `accept`), en
///   `~/Library/Application Support/The Last System/s/<vault8>.sock`: carpeta 0700, socket 0600, ruta < 104 bytes.
/// - Cada conexión: `PeerValidator` al aceptar; primer mensaje `.saludo` con el token de la ejecución; cada petición
///   vuelve a comprobar que el token sigue vigente (cancelar lo revoca y cierra sus conexiones al momento).
public final class MCPHost: @unchecked Sendable {
    public let socket: URL
    public let tokens: AlmacenDeTokens
    public let validador: PeerValidator
    let manejador: any ManejadorIPC
    let auditoria: any RegistroDeAuditoria

    private let queue = DispatchQueue(label: "es.thelast.system.mcp-host")
    private let lock = NSLock()
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var conexiones: [ObjectIdentifier: ConexionHost] = [:]

    public init(socket: URL, tokens: AlmacenDeTokens = AlmacenDeTokens(), validador: PeerValidator,
                manejador: any ManejadorIPC, auditoria: any RegistroDeAuditoria = AuditoriaEnMemoria()) {
        self.socket = socket; self.tokens = tokens; self.validador = validador
        self.manejador = manejador; self.auditoria = auditoria
    }

    deinit {
        detener()
    }

    /// `<appSupport>/s/<8 primeros caracteres del id de la empresa>.sock`.
    public static func rutaDelSocket(vaultID: String, appSupport: URL = AppLocations.appSupport) throws -> URL {
        let corto = String(vaultID.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
        let url = appSupport.appendingPathComponent("s", isDirectory: true).appendingPathComponent("\(corto).sock")
        guard !corto.isEmpty, url.path.utf8.count <= UnixSocket.maxPathBytes else {
            throw MCPHostError.rutaDemasiadoLarga(url.path)
        }
        return url
    }

    public var enMarcha: Bool { lock.withLock { listenFD >= 0 } }
    public var conexionesAbiertas: Int { lock.withLock { conexiones.count } }

    // MARK: Arrancar y parar

    public func iniciar() throws {
        guard !enMarcha else { return }
        let path = socket.path
        guard path.utf8.count <= UnixSocket.maxPathBytes else { throw MCPHostError.rutaDemasiadoLarga(path) }
        try Self.prepararCarpeta(socket.deletingLastPathComponent())
        try Self.apartarSocketViejo(path)

        var addr: sockaddr_un
        do { addr = try UnixSocket.address(path) } catch { throw MCPHostError.rutaDemasiadoLarga(path) }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPHostError.sistema("socket", errno) }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let e = errno
            Darwin.close(fd)
            throw MCPHostError.sistema("bind", e)
        }
        // La carpeta ya es 0700; el socket, además, 0600.
        guard chmod(path, 0o600) == 0, Darwin.listen(fd, 16) == 0 else {
            let e = errno
            Darwin.close(fd)
            unlink(path)
            throw MCPHostError.sistema("listen", e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.aceptar() }
        source.setCancelHandler { Darwin.close(fd) }
        lock.withLock {
            listenFD = fd
            acceptSource = source
        }
        source.resume()
    }

    /// Cierra el socket y todas las conexiones, y borra el fichero del socket.
    public func detener() {
        let (source, abiertas, estaba) = lock.withLock { () -> (DispatchSourceRead?, [ConexionHost], Bool) in
            let s = acceptSource
            let c = Array(conexiones.values)
            let estaba = listenFD >= 0
            acceptSource = nil
            listenFD = -1
            conexiones.removeAll()
            return (s, c, estaba)
        }
        source?.cancel()
        for c in abiertas { c.cerrar() }
        if estaba { unlink(socket.path) }
    }

    /// Revoca un token y cierra al momento las conexiones que lo usan (cancelar una ejecución).
    public func revocar(token: String) {
        tokens.revocar(token)
        let huella = AlmacenDeTokens.huella(token)
        for c in lock.withLock({ Array(conexiones.values) }) where c.huellaDelToken == huella { c.cerrar() }
    }

    /// Revoca todos los tokens de una ejecución y cierra sus conexiones.
    public func revocar(ejecucion: String) {
        tokens.revocar(ejecucion: ejecucion)
        for c in lock.withLock({ Array(conexiones.values) }) where c.ejecucion == ejecucion { c.cerrar() }
    }

    /// `s/` con permisos 0700, del usuario y sin enlaces simbólicos.
    static func prepararCarpeta(_ dir: URL) throws {
        let fm = FileManager.default
        var st = stat()
        if lstat(dir.path, &st) == 0 {
            guard (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else { throw MCPHostError.carpetaNoSegura(dir.path) }
            if (st.st_mode & 0o777) != 0o700 { chmod(dir.path, 0o700) }
        } else {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch {
                throw MCPHostError.carpetaNoSegura(dir.path)
            }
        }
    }

    /// Un socket que quedó de una sesión anterior se borra; si alguien lo atiende, es que hay otra ventana.
    static func apartarSocketViejo(_ path: String) throws {
        var st = stat()
        guard lstat(path, &st) == 0 else { return }
        guard (st.st_mode & S_IFMT) == S_IFSOCK, st.st_uid == getuid() else { throw MCPHostError.carpetaNoSegura(path) }
        if let fd = try? UnixSocket.connect(path: path) {
            Darwin.close(fd)
            throw MCPHostError.yaEnUso(path)
        }
        unlink(path)
    }

    // MARK: Conexiones

    private func aceptar() {
        let fd = lock.withLock { listenFD }
        guard fd >= 0 else { return }
        while true {
            let c = Darwin.accept(fd, nil, nil)
            if c < 0 { return }  // EAGAIN: no hay más
            _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)
            _ = fcntl(c, F_SETFD, FD_CLOEXEC)
            UnixSocket.configure(c, readTimeout: nil, writeTimeout: 10)
            switch validador.validar(descriptor: c) {
            case .failure(let rechazo):
                auditoria.registrar(EventoDeAuditoria(accion: "conexion", veredicto: "rechazado", motivo: rechazo.description))
                Darwin.close(c)
            case .success(let peer):
                let conexion = ConexionHost(fd: c, peer: peer, queue: queue, host: self)
                lock.withLock { conexiones[ObjectIdentifier(conexion)] = conexion }
                conexion.empezar()
            }
        }
    }

    func olvidar(_ c: ConexionHost) {
        _ = lock.withLock { conexiones.removeValue(forKey: ObjectIdentifier(c)) }
    }

    /// Una trama de una conexión (en orden: la conexión procesa una cada vez).
    func procesar(_ payload: Data, en c: ConexionHost) async {
        let request: IPCRequest
        do {
            request = try IPCCodec.decode(IPCRequest.self, from: payload)
        } catch {
            c.responder(IPCResponse(id: 0, resultado: .error(IPCError(.peticionNoValida, "Petición ilegible."))))
            c.cerrar()
            return
        }
        // Primero, siempre, el saludo con el token.
        guard let token = c.token else {
            guard case .saludo(let t, let protocolo, _) = request.operacion else {
                auditoria.registrar(EventoDeAuditoria(accion: "saludo", veredicto: "rechazado", motivo: "sin saludo (pid \(c.peer.pid))"))
                c.responder(IPCResponse(id: request.id, resultado: .error(IPCError(.noAutorizado, "Primero hay que saludar con el token de la ejecución."))))
                c.cerrar()
                return
            }
            guard protocolo == TLSMCPInfo.ipcProtocol, let contexto = tokens.contexto(de: t) else {
                auditoria.registrar(EventoDeAuditoria(accion: "saludo", veredicto: "rechazado",
                                                      motivo: protocolo == TLSMCPInfo.ipcProtocol ? "token no válido" : "protocolo \(protocolo)"))
                c.responder(IPCResponse(id: request.id, resultado: .error(IPCError(.tokenNoValido, "Esta ejecución ya no está en curso."))))
                c.cerrar()
                return
            }
            c.ligar(token: t, ejecucion: contexto.ejecucion)
            c.responder(IPCResponse(id: request.id, resultado: .saludo(servidor: "The Last System \(TLSMCPInfo.version)")))
            return
        }
        guard let contexto = tokens.contexto(de: token) else {
            auditoria.registrar(EventoDeAuditoria(ejecucion: c.ejecucion, accion: "peticion", veredicto: "rechazado", motivo: "token revocado o caducado"))
            c.responder(IPCResponse(id: request.id, resultado: .error(IPCError(.tokenNoValido, "Esta ejecución ya no está en curso."))))
            c.cerrar()
            return
        }
        switch request.operacion {
        case .saludo:
            c.responder(IPCResponse(id: request.id, resultado: .saludo(servidor: "The Last System \(TLSMCPInfo.version)")))
        case .listarHerramientas:
            let specs = await manejador.herramientas(para: contexto)
            c.responder(IPCResponse(id: request.id, resultado: .herramientas(specs)))
        case .llamar(let nombre, let argumentos):
            let r = await manejador.llamar(nombre, argumentos: argumentos, contexto: contexto)
            c.responder(IPCResponse(id: request.id, resultado: .llamada(r)))
        }
    }
}

/// Una conexión aceptada: lee tramas con `DispatchSource` y las procesa de una en una.
final class ConexionHost: @unchecked Sendable {
    let fd: Int32
    let peer: PeerInfo
    private let source: DispatchSourceRead
    private let lock = NSLock()
    private var reader = IPCFrame.Reader()
    private var _token: String?
    private var _ejecucion: String?
    private var cerrada = false
    private let continuation: AsyncStream<Data>.Continuation
    private let stream: AsyncStream<Data>
    private weak var host: MCPHost?

    init(fd: Int32, peer: PeerInfo, queue: DispatchQueue, host: MCPHost) {
        self.fd = fd; self.peer = peer; self.host = host
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        (stream, continuation) = AsyncStream.makeStream(of: Data.self)
    }

    var token: String? { lock.withLock { _token } }
    var ejecucion: String? { lock.withLock { _ejecucion } }
    var huellaDelToken: Data? { token.map(AlmacenDeTokens.huella) }

    func ligar(token: String, ejecucion: String) {
        lock.withLock { _token = token; _ejecucion = ejecucion }
    }

    func empezar() {
        let fd = self.fd
        source.setEventHandler { [weak self] in self?.leer() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        let stream = self.stream
        Task { [weak self] in
            for await frame in stream {
                guard let self, let host = self.host else { break }
                await host.procesar(frame, en: self)
            }
        }
    }

    private func leer() {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        if n <= 0 {
            if n < 0, errno == EINTR || errno == EAGAIN { return }
            cerrar()
            return
        }
        var frames: [Data] = []
        let malformada: Bool = lock.withLock {
            reader.append(Data(buffer[0..<n]))
            do {
                while let f = try reader.next() { frames.append(f) }
                return false
            } catch {
                return true
            }
        }
        for f in frames { continuation.yield(f) }
        if malformada { cerrar() }
    }

    /// Escribe con el cerrojo tomado: así nunca se escribe en un descriptor que `cerrar` ya soltó.
    func responder(_ r: IPCResponse) {
        guard let data = try? IPCCodec.encode(r) else { cerrar(); return }
        let fallo: Bool = lock.withLock {
            guard !cerrada else { return false }
            do {
                try UnixSocket.writeAll(fd, data)
                return false
            } catch {
                return true
            }
        }
        if fallo { cerrar() }
    }

    func cerrar() {
        let primera = lock.withLock { () -> Bool in
            guard !cerrada else { return false }
            cerrada = true
            return true
        }
        guard primera else { return }
        Darwin.shutdown(fd, SHUT_RDWR)
        continuation.finish()
        source.cancel()
        host?.olvidar(self)
    }
}
