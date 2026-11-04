import CoreServices
import Foundation

/// Vigilancia de la carpeta con FSEvents.
///
/// `FileEvents | NoDefer | WatchRoot`, latencia 0,3 s. Cada ruta espera 1,5 s sin
/// cambios antes de entregarse (los editores guardan en varios pasos). Si FSEvents
/// pide reescanear (`MustScanSubDirs`, `EventIdsWrapped`, eventos perdidos o la raíz
/// cambió), se entrega `.rescan`.
public final class VaultWatcher: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        case paths([URL])
        case rescan
    }

    public let root: URL
    let latency: TimeInterval
    let settle: TimeInterval
    let queue: DispatchQueue
    let handler: @Sendable (Event) -> Void

    // Solo se tocan en `queue`.
    private var stream: FSEventStreamRef?
    private var pending: [String: Date] = [:]
    private var needsRescan = false
    private var timer: DispatchSourceTimer?
    private var box: Unmanaged<WatcherBox>?

    public init(root: URL, latency: TimeInterval = 0.3, settle: TimeInterval = 1.5,
                handler: @escaping @Sendable (Event) -> Void) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.latency = latency
        self.settle = settle
        self.queue = DispatchQueue(label: "es.thelast.system.watcher")
        self.handler = handler
        queue.setSpecific(key: queueKey, value: ())
    }

    private let queueKey = DispatchSpecificKey<Void>()

    /// Ejecuta en `queue` sin bloquearse si ya estamos en ella.
    private func onQueue<T>(_ body: () -> T) -> T {
        DispatchQueue.getSpecific(key: queueKey) != nil ? body() : queue.sync(execute: body)
    }

    deinit {
        // `stop()` debe llamarse antes; aquí solo se liberan restos.
        if let s = stream {
            FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        }
        box?.release()
    }

    /// Arranca la vigilancia. Devuelve `false` si FSEvents no la acepta.
    @discardableResult
    public func start() -> Bool {
        onQueue { startOnQueue() }
    }

    public func stop() {
        onQueue {
            timer?.cancel(); timer = nil
            if let s = stream {
                FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
            }
            stream = nil
            box?.release(); box = nil
            pending.removeAll()
        }
    }

    private func startOnQueue() -> Bool {
        guard stream == nil else { return true }
        let b = Unmanaged.passRetained(WatcherBox(self))
        box = b
        var context = FSEventStreamContext(version: 0, info: b.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                           | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<WatcherBox>.fromOpaque(info).takeUnretainedValue().watcher
            let array = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
            var list: [(String, FSEventStreamEventFlags)] = []
            for i in 0..<count {
                if let p = array[i] as? String { list.append((p, flags[i])) }
            }
            watcher?.received(list)
        }
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, [root.path] as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
            b.release(); box = nil
            return false
        }
        FSEventStreamSetDispatchQueue(s, queue)
        guard FSEventStreamStart(s) else {
            FSEventStreamInvalidate(s); FSEventStreamRelease(s)
            b.release(); box = nil
            return false
        }
        stream = s
        // Temporizador de un solo disparo: solo se arma cuando hay algo pendiente (no despierta el
        // proceso 4 veces por segundo sin motivo).
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.setEventHandler { [weak self] in self?.flush() }
        t.schedule(deadline: .distantFuture, leeway: .milliseconds(50))
        t.resume()
        timer = t
        return true
    }

    /// En `queue`: arma el temporizador para la próxima entrega (o lo deja dormido si no hay nada).
    private func armTimer(now: Date = Date()) {
        guard let timer else { return }
        guard needsRescan || !pending.isEmpty else {
            timer.schedule(deadline: .distantFuture, leeway: .milliseconds(50))
            return
        }
        let earliest = pending.values.min() ?? now
        let latest = pending.values.max() ?? now
        // Cuando la primera ruta lleve `settle` quieta (o, si hay que reescanear, cuando todo lo esté).
        let due = needsRescan ? latest.addingTimeInterval(settle) : earliest.addingTimeInterval(settle)
        let delay = max(0.05, due.timeIntervalSince(now))
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(50))
    }

    /// En `queue`.
    private func received(_ events: [(String, FSEventStreamEventFlags)]) {
        let rescanFlags = UInt32(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagEventIdsWrapped
                                 | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                                 | kFSEventStreamEventFlagRootChanged)
        let now = Date()
        for (path, flag) in events {
            if flag & rescanFlags != 0 { needsRescan = true; continue }
            if flag & UInt32(kFSEventStreamEventFlagHistoryDone) != 0 { continue }
            pending[path] = now
        }
        armTimer(now: now)
    }

    /// En `queue`: entrega las rutas que llevan `settle` segundos quietas.
    private func flush() {
        let now = Date()
        defer { armTimer(now: Date()) }
        if needsRescan {
            // Espera también a que se calme antes de reescanear.
            let quiet = pending.values.allSatisfy { now.timeIntervalSince($0) >= settle }
            guard quiet else { return }
            needsRescan = false
            pending.removeAll()
            handler(.rescan)
            return
        }
        let ready = pending.filter { now.timeIntervalSince($0.value) >= settle }.map(\.key)
        guard !ready.isEmpty else { return }
        for p in ready { pending.removeValue(forKey: p) }
        handler(.paths(ready.sorted().map { URL(fileURLWithPath: $0) }))
    }
}

/// Referencia débil para el contexto C de FSEvents.
private final class WatcherBox: Sendable {
    weak let watcher: VaultWatcher?
    init(_ w: VaultWatcher) { watcher = w }
}
