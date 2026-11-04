import Foundation
import TLSAgents

// F4 · integración. ¿Pueden trabajar los asistentes de una copia en este Mac? Necesitan Claude Code instalado, con la
// sesión iniciada y con los flags que exige el lanzamiento (preflight de `--help`). Sin eso no se monta el motor: la
// app sigue igual, ⌘J contesta con el enrutador y Asistentes explica cómo conectarlo. El ejemplo (Ribera) no lo
// necesita: va simulado.

/// Lo que se sabe de Claude Code para los asistentes.
public enum ClaudeDisponible: Sendable, Equatable {
    case listo(binario: URL, ayuda: ClaudeHelp, version: String?)
    case noEncontrado
    case sinSesion(version: String?)
    case fallo(String)

    public var listo: Bool { if case .listo = self { true } else { false } }

    /// Qué hacer, en palabras de persona (`nil` si está listo).
    public var explicacion: String? {
        switch self {
        case .listo:
            nil
        case .noEncontrado:
            "Los asistentes de esta empresa trabajan con Claude Code y no lo encuentro en este Mac. Instálalo, abre "
                + "Terminal, escribe claude e inicia sesión; después pulsa «Buscar otra vez». Mientras tanto, Mika te "
                + "contesta con lo que sabe mirar."
        case .sinSesion:
            "Claude Code está en este Mac, pero sin la sesión iniciada. Abre Terminal, escribe claude y sigue los pasos; "
                + "después pulsa «Buscar otra vez». Mientras tanto, los asistentes no trabajan."
        case .fallo:
            "No he podido comprobar Claude Code en este Mac. Pulsa «Buscar otra vez» o mira Ajustes › Asistentes."
        }
    }

}

/// Busca Claude Code (en pruebas, uno fijo: nunca se lanza Claude de verdad).
public protocol LocalizadorDeClaude: Sendable {
    func buscar() async -> ClaudeDisponible
}

/// El de verdad: `ClaudeLocator` (PATH de la shell de inicio, versión, `auth status --json` y `--help`).
public struct LocalizadorClaudeCode: LocalizadorDeClaude {
    public init() {}

    public func buscar() async -> ClaudeDisponible {
        let loc = ClaudeLocator()
        guard let i = try? await loc.locate() else { return .noEncontrado }
        let version = i.version?.description
        guard let auth = try? await loc.authStatus(binary: i.binary) else { return .fallo("auth status") }
        guard auth.loggedIn else { return .sinSesion(version: version) }
        guard let ayuda = try? await loc.help(of: i.binary) else { return .fallo("--help") }
        return .listo(binario: i.binary, ayuda: ayuda, version: version)
    }
}

/// Siempre el mismo resultado (pruebas, capturas).
public struct LocalizadorFijo: LocalizadorDeClaude {
    public var valor: ClaudeDisponible
    public init(_ valor: ClaudeDisponible) { self.valor = valor }
    public func buscar() async -> ClaudeDisponible { valor }
}
