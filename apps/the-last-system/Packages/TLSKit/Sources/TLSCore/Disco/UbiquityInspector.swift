import Darwin
import Foundation

/// Datos de un fichero leídos con `lstat` (no abre el fichero ni lo descarga de iCloud).
public struct FileInfo: Sendable, Hashable {
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: Int64
    /// Fecha de modificación en nanosegundos desde 1970 (comparación exacta).
    public let mtimeNanos: Int64
    /// Solo en iCloud, sin descargar (`SF_DATALESS`).
    public let dataless: Bool

    public var modified: Date { Date(timeIntervalSince1970: Double(mtimeNanos) / 1_000_000_000) }
}

/// iCloud sin descargas accidentales.
///
/// - `dataless` = `st_flags & SF_DATALESS` vía `lstat`.
/// - `withoutMaterializing` pone `IOPOL_MATERIALIZE_DATALESS_FILES_OFF` en el hilo mientras
///   dura el bloque (y restaura el valor anterior): leer un fichero no descargado da error
///   en vez de descargarlo.
/// - `requestDownload` solo se llama al abrir una nota.
public enum UbiquityInspector {
    /// `SF_DATALESS` de `<sys/stat.h>`.
    public static let datalessFlag: UInt32 = 0x4000_0000

    public static func info(_ url: URL) -> FileInfo? {
        info(path: url.path)
    }

    public static func info(path: String) -> FileInfo? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        let type = st.st_mode & S_IFMT
        let nanos = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        return FileInfo(isDirectory: type == S_IFDIR, isSymlink: type == S_IFLNK, size: Int64(st.st_size),
                        mtimeNanos: nanos, dataless: (st.st_flags & datalessFlag) != 0)
    }

    public static func isDataless(_ url: URL) -> Bool {
        info(url)?.dataless ?? false
    }

    /// Ejecuta `body` en este hilo sin permitir que se materialicen ficheros de iCloud.
    /// El cuerpo debe ser síncrono (una tarea `async` puede cambiar de hilo).
    public static func withoutMaterializing<T>(_ body: () throws -> T) rethrows -> T {
        let type = Int32(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES)
        let scope = Int32(IOPOL_SCOPE_THREAD)
        let previous = getiopolicy_np(type, scope)
        _ = setiopolicy_np(type, scope, Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF))
        defer {
            _ = setiopolicy_np(type, scope, previous >= 0 ? previous : Int32(IOPOL_MATERIALIZE_DATALESS_FILES_DEFAULT))
        }
        return try body()
    }

    /// Política actual del hilo (para tests).
    public static var currentThreadPolicy: Int32 {
        getiopolicy_np(Int32(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES), Int32(IOPOL_SCOPE_THREAD))
    }

    /// Pide a iCloud la descarga. Solo al abrir una nota; nunca al escanear.
    public static func requestDownload(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }
}
