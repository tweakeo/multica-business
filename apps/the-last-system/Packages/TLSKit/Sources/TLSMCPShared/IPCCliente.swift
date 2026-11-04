import Darwin
import Foundation

/// Errores del socket (texto corto: lo ve el asistente si la app no responde).
public enum IPCSocketError: Error, Equatable, Sendable, CustomStringConvertible {
    case rutaDemasiadoLarga(Int)
    case sistema(String, Int32)
    case cerrado
    case respuestaInesperada

    public var description: String {
        switch self {
        case .rutaDemasiadoLarga(let n): "La ruta del socket es demasiado larga (\(n) bytes; máximo 103)."
        case .sistema(let op, let e): "\(op): \(String(cString: strerror(e)))"
        case .cerrado: "La app cerró la conexión."
        case .respuestaInesperada: "La app respondió algo inesperado."
        }
    }
}

/// Utilidades BSD comunes a los dos lados.
public enum UnixSocket {
    /// `sun_path` mide 104 bytes en Darwin, con el NUL final.
    public static let maxPathBytes = 103

    /// `sockaddr_un` de una ruta, o error si no cabe.
    public static func address(_ path: String) throws -> sockaddr_un {
        let bytes = Array(path.utf8)
        guard bytes.count <= maxPathBytes else { throw IPCSocketError.rutaDemasiadoLarga(bytes.count) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    /// Sin SIGPIPE al escribir en un socket cerrado y con plazos de lectura y escritura.
    public static func configure(_ fd: Int32, readTimeout: TimeInterval?, writeTimeout: TimeInterval?) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        if let t = readTimeout { setTimeout(fd, SO_RCVTIMEO, t) }
        if let t = writeTimeout { setTimeout(fd, SO_SNDTIMEO, t) }
    }

    static func setTimeout(_ fd: Int32, _ option: Int32, _ seconds: TimeInterval) {
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    /// Conecta a un socket Unix (bloqueante).
    public static func connect(path: String) throws -> Int32 {
        var addr = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw IPCSocketError.sistema("socket", errno) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard r == 0 else {
            let e = errno
            close(fd)
            throw IPCSocketError.sistema("connect", e)
        }
        return fd
    }

    /// Escribe todos los bytes (reintenta si la escritura es parcial o la interrumpe una señal).
    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < raw.count {
                let n = Darwin.write(fd, base + sent, raw.count - sent)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw errno == EPIPE ? IPCSocketError.cerrado : IPCSocketError.sistema("write", errno)
                }
                if n == 0 { throw IPCSocketError.cerrado }
                sent += n
            }
        }
    }

    /// Lee hasta completar una trama (bloqueante; respeta `SO_RCVTIMEO`).
    public static func readFrame(_ fd: Int32, reader: inout IPCFrame.Reader) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let frame = try reader.next() { return frame }
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                throw IPCSocketError.sistema("read", errno)
            }
            if n == 0 { throw IPCSocketError.cerrado }
            reader.append(Data(buffer[0..<n]))
        }
    }
}

/// Lado del binario: una conexión con la app, una petición cada vez (las respuestas llegan en orden).
public final class IPCCliente: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "es.thelast.system.tls-mcp.ipc")
    private var reader = IPCFrame.Reader()
    private var nextID: UInt64 = 1
    private var closed = false

    /// Conecta y saluda con el token. Lanza `IPCError` si la app no acepta.
    public static func conectar(socket: String, token: String, timeout: TimeInterval = 300) throws -> IPCCliente {
        let fd = try UnixSocket.connect(path: socket)
        UnixSocket.configure(fd, readTimeout: timeout, writeTimeout: 30)
        let cliente = IPCCliente(fd: fd)
        do {
            let r = try cliente.enviarSincrono(.saludo(token: token, protocolo: TLSMCPInfo.ipcProtocol,
                                                       version: TLSMCPInfo.version))
            switch r {
            case .saludo: return cliente
            case .error(let e): throw e
            default: throw IPCSocketError.respuestaInesperada
            }
        } catch {
            cliente.cerrar()
            throw error
        }
    }

    init(fd: Int32) {
        self.fd = fd
    }

    deinit {
        cerrar()
    }

    /// Envía y espera la respuesta (bloqueante).
    public func enviarSincrono(_ operacion: IPCRequest.Operacion) throws -> IPCResponse.Resultado {
        try lock.withLock {
            guard !closed else { throw IPCSocketError.cerrado }
            let id = nextID
            nextID += 1
            try UnixSocket.writeAll(fd, try IPCCodec.encode(IPCRequest(id: id, operacion: operacion)))
            while true {
                let frame = try UnixSocket.readFrame(fd, reader: &reader)
                let response = try IPCCodec.decode(IPCResponse.self, from: frame)
                // Una respuesta a otra petición (no debería pasar): se descarta.
                if response.id == id { return response.resultado }
            }
        }
    }

    /// Igual, sin bloquear el hilo que llama.
    public func enviar(_ operacion: IPCRequest.Operacion) async throws -> IPCResponse.Resultado {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<IPCResponse.Resultado, Error>) in
            queue.async {
                do { cont.resume(returning: try self.enviarSincrono(operacion)) } catch { cont.resume(throwing: error) }
            }
        }
    }

    public func cerrar() {
        // Desbloquea una lectura en curso (que tiene el cerrojo) antes de cerrar el descriptor.
        Darwin.shutdown(fd, SHUT_RDWR)
        lock.withLock {
            guard !closed else { return }
            closed = true
            Darwin.close(fd)
        }
    }
}
