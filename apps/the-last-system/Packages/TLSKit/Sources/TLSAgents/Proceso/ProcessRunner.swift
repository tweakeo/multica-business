import Darwin
import Foundation

/// Qué lanzar y cómo. El entorno es exactamente `environment`: no se hereda nada del proceso actual.
public struct ProcessSpec: Sendable {
    public var executable: String
    /// Argumentos sin `argv[0]` (se pone `executable`).
    public var arguments: [String]
    public var environment: [String: String]
    /// Directorio de trabajo (`nil` = el actual).
    public var directory: String?
    /// Se escribe entero en stdin y después se cierra. `nil` = `/dev/null`.
    public var stdin: Data?
    /// Al vencer, SIGTERM al grupo y SIGKILL a los `grace` segundos.
    public var timeout: TimeInterval
    public var grace: TimeInterval
    /// Bytes como máximo que se guardan de stdout y de stderr (las líneas se entregan todas).
    public var maxCapture: Int
    /// Entrada que sigue abierta mientras quien lanza quiera (chat): se escribe con `EntradaViva.escribir`
    /// y se cierra con `cerrar()`. Si hay `entradaViva`, `stdin` se escribe primero por ella.
    public var entradaViva: EntradaViva?
    /// Se llama con el pid (que es también el grupo) en cuanto arranca: para apuntarlo y poder pararlo al volver
    /// a abrir la app si quedó huérfano.
    public var alArrancar: (@Sendable (pid_t) -> Void)?

    public init(executable: String, arguments: [String] = [], environment: [String: String] = [:],
                directory: String? = nil, stdin: Data? = nil, timeout: TimeInterval = 30,
                grace: TimeInterval = 5, maxCapture: Int = 4 << 20, entradaViva: EntradaViva? = nil,
                alArrancar: (@Sendable (pid_t) -> Void)? = nil) {
        self.executable = executable; self.arguments = arguments; self.environment = environment
        self.directory = directory; self.stdin = stdin; self.timeout = timeout; self.grace = grace
        self.maxCapture = maxCapture; self.entradaViva = entradaViva; self.alArrancar = alArrancar
    }
}

/// Entrada estándar que se queda abierta (F4 · chat ⌘J: el proceso espera más mensajes por stdin).
///
/// Lo escrito antes de que arranque el proceso se guarda y se manda al conectar. Escribir después de cerrar
/// (o con el proceso ya muerto) devuelve `false`; nunca lanza SIGPIPE.
public final class EntradaViva: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var pendiente = Data()
    private var cerrada = false

    public init() {}

    /// `true` si se entregó entero al proceso (o quedó guardado para cuando arranque).
    @discardableResult
    public func escribir(_ data: Data) -> Bool {
        lock.withLock {
            guard !cerrada else { return false }
            guard fd >= 0 else { pendiente.append(data); return true }
            return Self.escribirTodo(fd, data)
        }
    }

    /// Cierra la entrada: el proceso ve el final y termina cuando acabe lo que tenga entre manos.
    public func cerrar() {
        lock.withLock {
            guard !cerrada else { return }
            cerrada = true
            if fd >= 0 { close(fd); fd = -1 }
        }
    }

    public var estaCerrada: Bool { lock.withLock { cerrada } }

    /// Lo llama el lanzador con el extremo de escritura del tubo (pasa a ser de esta entrada).
    func conectar(_ descriptor: Int32) {
        lock.withLock {
            guard !cerrada else { close(descriptor); return }
            fd = descriptor
            if !pendiente.isEmpty {
                if !Self.escribirTodo(descriptor, pendiente) { close(descriptor); fd = -1; cerrada = true }
                pendiente.removeAll()
            }
        }
    }

    static func escribirTodo(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return true }
            var off = 0
            while off < raw.count {
                let n = write(fd, base + off, raw.count - off)
                if n > 0 { off += n } else if n < 0 && errno == EINTR { continue } else { return false }
            }
            return true
        }
    }
}

public struct ProcessOutput: Sendable {
    public var pid: pid_t
    /// Código de salida, o 128 + señal si terminó por una señal.
    public var status: Int32
    public var signal: Int32?
    public var stdout: Data
    public var stderr: Data
    public var timedOut: Bool
    /// `true` si el lector de líneas pidió terminar.
    public var stoppedByCaller: Bool
    /// `true` si se canceló la tarea que esperaba.
    public var cancelled: Bool

    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Respuesta del lector a cada línea de stdout.
public enum LineDecision: Sendable { case seguir, terminar }

public enum ProcessError: Error, Equatable, CustomStringConvertible {
    case pipe(Int32)
    case spawn(String, Int32)

    public var description: String {
        switch self {
        case .pipe(let e): "No se pudo preparar la comunicación con el proceso (\(String(cString: strerror(e))))."
        case .spawn(let path, let e): "No se pudo lanzar \(path) (\(String(cString: strerror(e))))."
        }
    }
}

/// Lanzador con `posix_spawn`: grupo de procesos propio (para parar también a los hijos, como `tls-mcp`),
/// sin heredar descriptores (`POSIX_SPAWN_CLOEXEC_DEFAULT`), señales por defecto y tope de tiempo.
///
/// Parar (por tiempo, por el lector o al cancelar la tarea) = SIGTERM al grupo y SIGKILL a los `grace`
/// segundos. Al terminar el proceso principal, lo que quede del grupo también se para. Las señales al
/// grupo solo se mandan mientras el proceso principal no se ha recogido (su número no se puede reutilizar).
public enum ProcessRunner {
    /// Lanza y espera. `onLine` recibe cada línea de stdout (sin `\n`) en un hilo propio.
    public static func run(_ spec: ProcessSpec,
                           onLine: (@Sendable (Data) -> LineDecision)? = nil) async throws -> ProcessOutput {
        let control = Control(grace: spec.grace)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                // Hilo dedicado: una ejecución de un asistente puede durar minutos.
                let thread = Thread {
                    do { cont.resume(returning: try runBlocking(spec, control: control, onLine: onLine)) } catch {
                        cont.resume(throwing: error)
                    }
                }
                thread.name = "es.thelast.system.proceso"
                thread.start()
            }
        } onCancel: {
            control.stop(.cancelled)
        }
    }

    /// `true` si queda algún proceso vivo en el grupo (un principal ya terminado y sin recoger no cuenta).
    public static func groupAlive(_ pgid: pid_t) -> Bool {
        pgid > 1 && Darwin.kill(-pgid, 0) == 0
    }

    static func runBlocking(_ spec: ProcessSpec, control: Control,
                            onLine: (@Sendable (Data) -> LineDecision)?) throws -> ProcessOutput {
        var inFD: [Int32] = [-1, -1], outFD: [Int32] = [-1, -1], errFD: [Int32] = [-1, -1]
        func closeAll() { for fd in inFD + outFD + errFD where fd >= 0 { close(fd) } }
        for i in 0..<3 {
            if i == 0 && spec.stdin == nil && spec.entradaViva == nil { continue }
            var p: [Int32] = [-1, -1]
            guard pipe(&p) == 0 else { let e = errno; closeAll(); throw ProcessError.pipe(e) }
            for fd in p { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }
            switch i { case 0: inFD = p; case 1: outFD = p; default: errFD = p }
        }
        if inFD[1] >= 0 { _ = fcntl(inFD[1], F_SETNOSIGPIPE, 1) }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        if inFD[0] >= 0 {
            posix_spawn_file_actions_adddup2(&actions, inFD[0], 0)
        } else {
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        }
        posix_spawn_file_actions_adddup2(&actions, outFD[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errFD[1], 2)
        if let dir = spec.directory { posix_spawn_file_actions_addchdir_np(&actions, dir) }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attr, Int16(flags))
        posix_spawnattr_setpgroup(&attr, 0)
        var defaults = sigset_t()
        sigfillset(&defaults); sigdelset(&defaults, SIGKILL); sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var mask = sigset_t()
        sigemptyset(&mask)
        posix_spawnattr_setsigmask(&attr, &mask)

        let argv: [UnsafeMutablePointer<CChar>?] = ([spec.executable] + spec.arguments).map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] = spec.environment.sorted { $0.key < $1.key }
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { for p in argv + envp { free(p) } }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, spec.executable, &actions, &attr, argv, envp)
        // Los extremos del hijo se cierran en el padre.
        for fd in [inFD[0], outFD[1], errFD[1]] where fd >= 0 { close(fd) }
        guard rc == 0 else {
            for fd in [inFD[1], outFD[0], errFD[0]] where fd >= 0 { close(fd) }
            throw ProcessError.spawn(spec.executable, rc)
        }
        control.started(pid)
        spec.alArrancar?(pid)

        let group = DispatchGroup()
        // Colas propias (serie: GCD les da hilo aunque las colas globales estén llenas de trabajo bloqueado): el tope
        // de tiempo y el SIGKILL tienen que llegar aunque la app (o todo el paquete de pruebas) esté muy cargada.
        let colaEntrada = DispatchQueue(label: "es.thelast.system.proceso.stdin")
        let colaErrores = DispatchQueue(label: "es.thelast.system.proceso.stderr")
        // stdin: se escribe en otra cola para no bloquear la lectura.
        if let viva = spec.entradaViva, inFD[1] >= 0 {
            // Entrada que sigue abierta (chat): el extremo pasa a la `EntradaViva`, que lo cierra al terminar.
            if let data = spec.stdin { viva.escribir(data) }
            viva.conectar(inFD[1])
        } else if let data = spec.stdin, inFD[1] >= 0 {
            let fd = inFD[1]
            group.enter()
            colaEntrada.async {
                data.withUnsafeBytes { raw in
                    var off = 0
                    while off < raw.count {
                        let n = write(fd, raw.baseAddress! + off, raw.count - off)
                        if n > 0 { off += n } else if n < 0 && errno == EINTR { continue } else { break }
                    }
                }
                close(fd)
                group.leave()
            }
        }

        // stderr: se acumula hasta el tope.
        let errBox = Capture(limit: spec.maxCapture)
        let errRead = errFD[0]
        group.enter()
        colaErrores.async {
            readLoop(errRead) { errBox.append($0) }
            close(errRead)
            group.leave()
        }

        // Tope de tiempo.
        let timer = DispatchSource.makeTimerSource(queue: control.cola)
        timer.schedule(deadline: .now() + spec.timeout)
        timer.setEventHandler { control.stop(.timeout) }
        timer.resume()

        // stdout: líneas para el lector y copia hasta el tope.
        let outBox = Capture(limit: spec.maxCapture)
        var pending = Data()
        let outRead = outFD[0]
        readLoop(outRead) { chunk in
            outBox.append(chunk)
            guard let onLine else { return }
            pending.append(chunk)
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = pending[pending.startIndex..<nl]
                pending.removeSubrange(pending.startIndex...nl)
                if !line.isEmpty, onLine(Data(line)) == .terminar { control.stop(.caller) }
            }
        }
        if let onLine, !pending.isEmpty, onLine(pending) == .terminar { control.stop(.caller) }
        close(outRead)

        // Espera a que termine sin recogerlo: mientras sea un zombi, su grupo no se reutiliza.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) < 0 && errno == EINTR {}
        timer.cancel()
        // Lo que quede del grupo (por ejemplo, un servidor MCP huérfano): SIGTERM y, si sigue, SIGKILL.
        if groupAlive(pid) {
            _ = Darwin.kill(-pid, SIGTERM)
            let limit = Date().addingTimeInterval(spec.grace)
            while groupAlive(pid) && Date() < limit { usleep(50_000) }
            if groupAlive(pid) { _ = Darwin.kill(-pid, SIGKILL) }
        }
        let status = control.reap()
        spec.entradaViva?.cerrar()
        group.wait()

        let termSig = status & 0x7f
        let exited = termSig == 0
        return ProcessOutput(pid: pid,
                             status: exited ? (status >> 8) & 0xff : 128 + termSig,
                             signal: exited ? nil : termSig,
                             stdout: outBox.data, stderr: errBox.data,
                             timedOut: control.reason == .timeout, stoppedByCaller: control.reason == .caller,
                             cancelled: control.reason == .cancelled)
    }

    /// Lee hasta EOF (reintenta ante EINTR).
    static func readLoop(_ fd: Int32, _ body: (Data) -> Void) {
        let size = 64 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 1)
        defer { buffer.deallocate() }
        while true {
            let n = read(fd, buffer, size)
            if n > 0 { body(Data(bytes: buffer, count: n)) } else if n < 0 && errno == EINTR { continue } else { break }
        }
    }

    /// Quién para el proceso y cuándo se puede señalar su grupo. Todo bajo el mismo cerrojo.
    final class Control: @unchecked Sendable {
        enum Reason { case timeout, caller, cancelled }

        private let lock = NSLock()
        private let grace: TimeInterval
        /// Cola propia del tope de tiempo y del SIGKILL (ver `runBlocking`).
        let cola = DispatchQueue(label: "es.thelast.system.proceso.control")
        private var pid: pid_t = 0
        private var reaped = false
        private var _reason: Reason?

        init(grace: TimeInterval) { self.grace = grace }

        var reason: Reason? { lock.withLock { _reason } }

        func started(_ pid: pid_t) {
            let pendiente = lock.withLock { () -> Bool in self.pid = pid; return _reason != nil }
            // Cancelado antes de arrancar: se para enseguida.
            if pendiente { signalGroup() }
        }

        /// La primera causa manda; las siguientes no hacen nada.
        func stop(_ r: Reason) {
            let first = lock.withLock { () -> Bool in
                guard _reason == nil, !reaped else { return false }
                _reason = r
                return true
            }
            if first { signalGroup() }
        }

        private func signalGroup() {
            let ready = lock.withLock { () -> Bool in
                guard pid > 1, !reaped else { return false }
                _ = Darwin.kill(-pid, SIGTERM)
                return true
            }
            guard ready else { return }
            // Un hijo creado justo mientras llegaba la señal (un `fork` en ese instante) no la recibe y seguiría
            // con la salida abierta: se repite SIGTERM al grupo un par de veces antes del SIGKILL.
            for repeticion in [0.2, 1.0] where repeticion < grace {
                cola.asyncAfter(deadline: .now() + repeticion) { [self] in
                    lock.withLock {
                        if !reaped, ProcessRunner.groupAlive(pid) { _ = Darwin.kill(-pid, SIGTERM) }
                    }
                }
            }
            cola.asyncAfter(deadline: .now() + grace) { [self] in
                lock.withLock {
                    if !reaped, ProcessRunner.groupAlive(pid) { _ = Darwin.kill(-pid, SIGKILL) }
                }
            }
        }

        /// Recoge el proceso principal; desde aquí no se manda ninguna señal más a su grupo.
        func reap() -> Int32 {
            lock.withLock {
                reaped = true
                var status: Int32 = 0
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                return status
            }
        }
    }

    final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        let limit: Int
        init(limit: Int) { self.limit = limit }
        func append(_ d: Data) {
            lock.withLock {
                let room = limit - buffer.count
                if room > 0 { buffer.append(d.prefix(room)) }
            }
        }
        var data: Data { lock.withLock { buffer } }
    }
}
