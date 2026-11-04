import AppKit
import Darwin
import Foundation
import TLSCore

/// Comprobación de permisos de lectura de una carpeta (TCC de iCloud) y accesos a Finder y Ajustes. Pública para la
/// puesta en marcha (TLSOnboarding), que hace la misma comprobación en su bienvenida.
public enum FolderAccess {
    public enum Result: Equatable, Sendable {
        case ok
        /// macOS no deja leerla (EPERM / EACCES): pantalla de recuperación.
        case sinPermiso
        case noExiste
        /// Otro fallo del sistema. Lleva el detalle técnico (en inglés): solo para «Detalle técnico».
        case otro(String)
    }

    /// Lo que ve la persona cuando el fallo no es de permiso ni de carpeta inexistente.
    public static let mensajeOtro = "No he podido abrir esa carpeta: el disco no responde o no está disponible. Prueba de nuevo."

    /// Ajustes del Sistema › Privacidad y seguridad › Archivos y carpetas.
    static let ajustesArchivosURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    /// Abre la carpeta (sin leer sus entradas) para saber si macOS deja leerla.
    /// No descarga nada: el hilo desactiva la materialización de iCloud mientras dura la prueba.
    public static func check(_ url: URL) async -> Result {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: checkSync(url))
            }
        }
    }

    static func checkSync(_ url: URL) -> Result {
        UbiquityInspector.withoutMaterializing {
            let fd = url.withUnsafeFileSystemRepresentation { path -> Int32 in
                guard let path else { return -1 }
                return open(path, O_RDONLY | O_DIRECTORY)
            }
            if fd >= 0 {
                close(fd)
                return .ok
            }
            let code = errno
            switch code {
            case EPERM, EACCES: return .sinPermiso
            case ENOENT, ENOTDIR: return .noExiste
            default: return .otro(String(cString: strerror(code)))
            }
        }
    }

    /// `true` si el error (o alguno de sus subyacentes) es de permisos.
    static func isPermissionError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        var depth = 0
        while let e = current, depth < 6 {
            if e.domain == NSPOSIXErrorDomain, e.code == Int(EPERM) || e.code == Int(EACCES) { return true }
            if e.domain == NSCocoaErrorDomain,
               e.code == NSFileReadNoPermissionError || e.code == NSFileWriteNoPermissionError { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return false
    }

    @MainActor
    public static func openPrivacySettings() {
        NSWorkspace.shared.open(ajustesArchivosURL)
    }

    /// Selecciona el elemento en Finder (no lo abre ni lo descarga).
    @MainActor
    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
