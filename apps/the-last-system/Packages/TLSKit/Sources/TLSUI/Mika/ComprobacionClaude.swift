import Foundation
import Observation
import TLSAgents
import TLSCore

// F4 · rol mika. ¿Hay Claude Code en este Mac y se puede usar? (PLAN §5.3 `ClaudeLocator`, §6.7 paso 7 «Conectar»:
// «detectado, prueba»). Busca el programa, lee su versión, comprueba que tienes la sesión iniciada y, si lo pides,
// hace una consulta muy pequeña dentro de la caja de los asistentes (sin ver ninguna carpeta). Todo en palabras de
// persona: el detalle técnico, solo en «Detalle técnico». En pruebas, un comprobador falso: nunca se lanza Claude.

/// Lo que se sabe de Claude Code.
public enum EstadoClaudeCode: Sendable, Equatable {
    case sinMirar
    case buscando
    case noEncontrado
    /// `sesion`: `true` iniciada, `false` sin iniciar, `nil` no se pudo comprobar.
    case encontrado(version: String?, sesion: Bool?)
    case probando
    case probado(ok: Bool)

    public var encontrado: Bool {
        switch self {
        case .encontrado, .probando, .probado: true
        default: false
        }
    }
}

/// Los textos (los usan Ajustes y el paso 7 de la puesta en marcha).
public enum TextosClaude {
    /// «Claude Code está en este Mac (versión 2.1.307) y tienes la sesión iniciada.»
    /// F5 · corrector (P3-17): la versión va en «Detalle técnico», no aquí.
    public static func encontrado(version: String?, sesion: Bool?) -> String {
        switch sesion {
        case true?: return "Claude Code está en este Mac y tienes la sesión iniciada."
        case false?: return "Claude Code está en este Mac, pero no has iniciado sesión."
        case nil: return "Claude Code está en este Mac. No he podido comprobar si tienes la sesión iniciada."
        }
    }

    /// Lo que hay que hacer, si algo.
    public static func consejo(version: String?, sesion: Bool?) -> String? {
        if sesion == false {
            return "Abre Terminal, escribe claude y sigue los pasos para iniciar sesión. Después pulsa «Buscar otra vez». Mientras tanto, la app funciona igual sin él."
        }
        guard let version, let v = ClaudeVersion(version) else { return nil }
        if v == ClaudeLocator.verifiedVersion { return nil }
        return "La app está comprobada con la versión \(ClaudeLocator.verifiedVersion). Con la tuya debería ir igual; si algo falla, pulsa «Probar»."
    }

    public static let noEncontrado = "No encuentro Claude Code en este Mac. Mika te contesta igual con lo que sabe mirar; para que los asistentes trabajen, instálalo (el manual lo explica en «Conectar Claude Code») y pulsa «Buscar otra vez»."
    public static let buscando = "Buscando Claude Code en este Mac…"
    public static let probando = "Probando con una consulta muy pequeña, sin ver ninguna carpeta…"
    public static func probado(_ ok: Bool) -> String {
        ok ? "Funciona: ha contestado. Los asistentes ya pueden trabajar con él."
            : "No ha contestado. La app sigue sin él; puedes volver a probar más tarde."
    }

    public static func texto(_ e: EstadoClaudeCode) -> String {
        switch e {
        case .sinMirar: "Aún no lo he buscado."
        case .buscando: buscando
        case .noEncontrado: noEncontrado
        case .encontrado(let v, let s): encontrado(version: v, sesion: s)
        case .probando: probando
        case .probado(let ok): probado(ok)
        }
    }
}

/// Busca y prueba Claude Code.
public protocol ComprobadorClaude: Sendable {
    /// Busca el programa, su versión y si hay sesión (sin consultas).
    func buscar() async -> (estado: EstadoClaudeCode, detalle: String?)
    /// Una consulta muy pequeña, sin servidores ni herramientas, en la caja de los asistentes.
    func probar(estado: URL, negadas: [URL]) async -> Bool
}

/// El de verdad: `ClaudeLocator` y `ClaudeProbe` (TLSAgents).
public struct ComprobadorClaudeCode: ComprobadorClaude {
    public init() {}

    public func buscar() async -> (estado: EstadoClaudeCode, detalle: String?) {
        let loc = ClaudeLocator()
        guard let i = try? await loc.locate() else { return (.noEncontrado, nil) }
        let sesion = try? await loc.authStatus(binary: i.binary)
        let detalle = "Programa: \(i.binary.path)" + (i.isNative ? "" : " (no nativo)")
            + (sesion?.authMethod.map { " · acceso: \($0)" } ?? "")
        return (.encontrado(version: i.version?.description, sesion: sesion?.loggedIn), detalle)
    }

    public func probar(estado: URL, negadas: [URL]) async -> Bool {
        let loc = ClaudeLocator()
        guard let i = try? await loc.locate(), let ayuda = try? await loc.help(of: i.binary),
              let paths = try? AgentPaths(vaultState: estado, slug: "comprobacion") else { return false }
        let r = ClaudeProbe.Request(paths: paths, deniedRoots: negadas, servers: [:], session: .ephemeral, model: "haiku",
                                    maxBudgetUSD: 0.02, message: "Contesta solo con la palabra listo. Es una prueba de conexión.",
                                    timeout: 60)
        guard let out = try? await ClaudeProbe(claude: i.binary, help: ayuda).run(r) else { return false }
        return out.state == .completada && !(out.result?.text ?? "").isEmpty
    }
}

/// En pruebas.
public struct ComprobadorClaudeFijo: ComprobadorClaude {
    public var estado: EstadoClaudeCode
    public var prueba: Bool
    public init(_ estado: EstadoClaudeCode, prueba: Bool = true) { self.estado = estado; self.prueba = prueba }
    public func buscar() async -> (estado: EstadoClaudeCode, detalle: String?) { (estado, nil) }
    public func probar(estado: URL, negadas: [URL]) async -> Bool { prueba }
}

/// La comprobación de Claude Code de Ajustes › Asistentes.
@MainActor
@Observable
final class ComprobacionClaude {
    private(set) var estado: EstadoClaudeCode = .sinMirar
    /// Para «Detalle técnico» (dónde está el programa y cómo se entra).
    private(set) var detalle: String?
    /// La versión y la sesión de la última búsqueda (para el consejo, también tras probar).
    private(set) var version: String?
    private(set) var sesion: Bool?
    @ObservationIgnored var comprobador: any ComprobadorClaude

    init(comprobador: any ComprobadorClaude = ComprobadorClaudeCode()) { self.comprobador = comprobador }

    /// La de la app; en pruebas, una que nunca lanza nada.
    static let compartida = ComprobacionClaude(comprobador: PreferenciasPresencia.esLaApp ? ComprobadorClaudeCode()
                                                   : ComprobadorClaudeFijo(.noEncontrado, prueba: false))

    var texto: String { TextosClaude.texto(estado) }
    var consejo: String? {
        switch estado {
        case .encontrado, .probado: TextosClaude.consejo(version: version, sesion: sesion)
        default: nil
        }
    }

    func buscar() async {
        guard estado != .buscando, estado != .probando else { return }
        estado = .buscando
        let (e, d) = await comprobador.buscar()
        estado = e
        detalle = d
        if case .encontrado(let v, let s) = e {
            version = v; sesion = s
            if let v { detalle = "Versión \(v)" + (d.map { " · " + $0 } ?? "") }
        }
    }

    /// `estado`: una carpeta de la app (nunca la de una empresa); `negadas`: las empresas, que la prueba no ve.
    func probar(estado dir: URL, negadas: [URL]) async {
        guard estado.encontrado, estado != .probando else { return }
        estado = .probando
        estado = .probado(ok: await comprobador.probar(estado: dir, negadas: negadas))
    }
}
