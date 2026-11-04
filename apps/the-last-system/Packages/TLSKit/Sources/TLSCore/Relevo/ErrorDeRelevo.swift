import Foundation

/// Por qué «Pasar a mi carpeta real» no sigue (PLAN §9 F6). Cada texto dice qué hacer y, si no se escribió nada, lo dice.
public enum ErrorDeRelevo: Error, LocalizedError, Sendable, Equatable {
    /// El botón solo aparece en una copia cuya carpeta de origen está registrada como real.
    case noDisponible(String)
    /// Falta escribir el nombre de la empresa tal cual.
    case sinConfirmar
    /// La otra aplicación que llevaba la carpeta (la de Multica) la tiene abierta.
    case otraAplicacionAbierta
    /// Otra ventana o proceso de esta app tiene la carpeta real abierta para escribir.
    case otraVentanaAbierta
    /// La carpeta real la escribe otro Mac.
    case otroEquipo(equipo: String, desde: String)
    /// No se sabe quién escribe la carpeta (fichero dañado o solo en iCloud).
    case escritorIlegible
    /// La carpeta real cambió desde la vista previa.
    case laRealCambio(String)
    /// La copia cambió desde la vista previa.
    case laCopiaCambio(String)
    /// No hay nada que pasar.
    case sinCambios
    /// La copia de seguridad previa no se pudo hacer o comprobar.
    case respaldoFallido(String)
    /// Se escribió, pero la comprobación no cuadra (se puede deshacer).
    case comprobacionFallida(Int)
    /// «Deshacer» ya no se puede (se escribió algo después).
    case deshacerNoDisponible

    public var errorDescription: String? {
        switch self {
        case .noDisponible(let motivo):
            motivo
        case .sinConfirmar:
            "Escribe el nombre de tu empresa tal cual aparece para confirmar. No se ha cambiado nada."
        case .otraAplicacionAbierta:
            "La otra aplicación que lleva tu carpeta real (Multica) está abierta y la está usando. Ciérrala del todo y vuelve a intentarlo. No se ha cambiado nada."
        case .otraVentanaAbierta:
            "Tu carpeta real está abierta para guardar cambios en otra ventana de The Last System. Ciérrala y vuelve a intentarlo. No se ha cambiado nada."
        case .otroEquipo(let equipo, let desde):
            "Tu carpeta real la lleva otro Mac («\(equipo)», desde \(desde)). Pásala desde ese Mac o deja de usarla allí primero. No se ha cambiado nada."
        case .escritorIlegible:
            "No puedo saber quién lleva tu carpeta real: su fichero de ajustes está dañado o solo en iCloud. No se ha cambiado nada."
        case .laRealCambio(let r):
            "Tu carpeta real ha cambiado desde la vista previa («\(r)»). Vuelve a preparar la vista previa. No se ha cambiado nada."
        case .laCopiaCambio(let r):
            "La copia ha cambiado desde la vista previa («\(r)»). Vuelve a preparar la vista previa. No se ha cambiado nada."
        case .sinCambios:
            "Tu carpeta real ya tiene todo lo de la copia: no hay nada que pasar."
        case .respaldoFallido(let r):
            "No he podido guardar la copia de seguridad previa («\(r)»). No se ha cambiado nada."
        case .comprobacionFallida(let n):
            "Lo pasado no cuadra con la vista previa en \(n == 1 ? "1 fichero" : "\(n) ficheros"). Pulsa «Deshacer» para dejar tu carpeta real como estaba."
        case .deshacerNoDisponible:
            "Ya no se puede deshacer el paso a tu carpeta real: después se han guardado otros cambios. La copia de seguridad sigue en los ajustes de la app."
        }
    }
}
