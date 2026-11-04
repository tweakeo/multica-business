import Foundation
import TLSAgents
import TLSCore
import TLSImport

// F3 · rol motor (no lo rehace la fase de pantallas: se usa tal cual). El entrevistador con el Claude Code de la
// persona: `claude -p --json-schema --no-session-persistence` dentro del sandbox, con el perfil de los asistentes
// (la carpeta de la empresa y la carpeta personal negadas), sin servidores ni herramientas. Solo se usa con
// consentimiento (`EstadoPuestaEnMarcha.usarAsistente`). Si algo falla, el motor decide con su lista fija.

/// Lanza una consulta del entrevistador con `ClaudeProbe` (TLSAgents).
public struct LanzadorClaudeCode: LanzadorEntrevista {
    public let probe: ClaudeProbe
    /// Estado de la carpeta (`<Application Support>/<vault-id>`): ahí va el directorio del entrevistador.
    public let estado: URL
    /// Carpetas que el sandbox niega (la de la empresa y, si se conoce, la original).
    public let negadas: [URL]
    public let modelo: String?
    public let presupuestoUSD: Double
    public let tiempo: TimeInterval

    public init(probe: ClaudeProbe, estado: URL, negadas: [URL], modelo: String? = "haiku", presupuestoUSD: Double = 0.05,
                tiempo: TimeInterval = 60) {
        self.probe = probe; self.estado = estado; self.negadas = negadas; self.modelo = modelo
        self.presupuestoUSD = presupuestoUSD; self.tiempo = tiempo
    }

    public enum ErrorLanzador: Error, Equatable {
        case sinResultado(String)
    }

    public func pedir(_ mensaje: String, esquema: String) async throws -> String {
        let paths = try AgentPaths(vaultState: estado, slug: "entrevistador")
        let r = ClaudeProbe.Request(paths: paths, deniedRoots: negadas, servers: [:], session: .ephemeral, model: modelo,
                                    maxBudgetUSD: presupuestoUSD, jsonSchema: esquema, message: mensaje, timeout: tiempo)
        let out = try await probe.run(r)
        guard out.state == .completada else { throw ErrorLanzador.sinResultado(String(describing: out.state)) }
        // Con `--json-schema` la respuesta llega en `structured_output` del evento final (si no, en `result`).
        if let estructurada = Self.salidaEstructurada(en: paths.stream) { return estructurada }
        guard let texto = out.result?.text, !texto.isEmpty else { throw ErrorLanzador.sinResultado("vacío") }
        return texto
    }

    /// `structured_output` del último evento `result` del stream guardado.
    static func salidaEstructurada(en stream: URL) -> String? {
        guard let data = try? Data(contentsOf: stream) else { return nil }
        for linea in data.split(separator: 0x0A).reversed() {
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(linea))) as? [String: Any],
                  obj["type"] as? String == "result" else { continue }
            guard let s = obj["structured_output"], JSONSerialization.isValidJSONObject(s),
                  let d = try? JSONSerialization.data(withJSONObject: s, options: [.sortedKeys]) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        return nil
    }
}

// El clasificador del paso 2 (`AIClassifier`, TLSImport) lanza igual: mismo sandbox, sesión efímera y `--json-schema`.
// Solo con el mismo consentimiento (`EstadoPuestaEnMarcha.usarAsistente`): quien lo crea lo comprueba.
extension LanzadorClaudeCode: EjecutorClasificacion {
    public func ejecutar(peticion: String, esquema: String) async throws -> Data {
        Data(try await pedir(peticion, esquema: esquema).utf8)
    }
}
