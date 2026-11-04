import Darwin
import Foundation
import Synchronization

/// Hilo propio con la política «no materializar» de iCloud.
///
/// `setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, OFF)` vale solo
/// para el hilo que la llama, y una tarea `async` puede saltar de hilo en cada `await`. Por eso el
/// recorrido y la copia corren enteros, sin `await`, en un `Thread` dedicado: un acceso por error a
/// un fichero que solo está en iCloud da error en vez de descargarlo.
enum DatalessGuard {
    /// `true` si el hilo actual no puede materializar ficheros de iCloud.
    static var currentThreadIsProtected: Bool {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
            == IOPOL_MATERIALIZE_DATALESS_FILES_OFF
    }

    /// Ejecuta `body` en un hilo nuevo protegido. Cancelar la tarea marca `CancelFlag`.
    static func run<T: Sendable>(_ name: String,
                                 _ body: @escaping @Sendable (CancelFlag) throws -> T) async throws -> T {
        let flag = CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let thread = Thread {
                    let r = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                                           IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
                    guard r == 0, currentThreadIsProtected else {
                        continuation.resume(throwing: CopyGuardError.proteccionICloud)
                        return
                    }
                    do {
                        continuation.resume(returning: try body(flag))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                thread.name = name
                thread.qualityOfService = .userInitiated
                thread.stackSize = 4 << 20  // recorrido recursivo: margen para árboles profundos
                thread.start()
            }
        } onCancel: {
            flag.cancel()
        }
    }

    /// Para herramientas de línea de órdenes: protege todo el proceso.
    @discardableResult
    static func protectProcess() -> Bool {
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS,
                       IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
    }
}

/// Señal de cancelación compartida entre la tarea y el hilo de copia.
final class CancelFlag: Sendable {
    private let state = Mutex(false)
    func cancel() { state.withLock { $0 = true } }
    var isCancelled: Bool { state.withLock { $0 } }
    func check() throws { if isCancelled { throw CancellationError() } }
}

/// Protección de iCloud para procesos enteros (tls-tool). Devuelve `false` si no se pudo activar.
public enum ICloudProtection {
    @discardableResult
    public static func protectCurrentProcess() -> Bool { DatalessGuard.protectProcess() }
}
