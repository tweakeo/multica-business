import Foundation
import MCP
import TLSAgents
import TLSCore
import TLSMCPShared

/// La puerta del motor (`PuertaDeHerramientas`, TLSAgents) al servidor de herramientas de una carpeta: el socket
/// (`MCPHost`) y las herramientas (`ServidorDeHerramientas`). El motor la arranca con la carpeta, pide un token por
/// ejecución y lo revoca al terminar o al cancelar (al momento: sus conexiones se cierran).
public final class PuertaMCP: PuertaDeHerramientas, @unchecked Sendable {
    public let host: MCPHost
    public let servidor: ServidorDeHerramientas
    /// `tls-mcp` (en el bundle de la app). `nil` en simulación: no se lanza nada.
    public let helper: URL?
    /// ¿Trabaja este asistente en el Buzón? (de la configuración confirmada).
    let buzon: @Sendable (String) -> Bool

    public init(host: MCPHost, servidor: ServidorDeHerramientas, helper: URL? = ConfiguracionMCP.localizarHelper(),
                buzon: @escaping @Sendable (String) -> Bool = { ["cartero", "ordenador"].contains($0) }) {
        self.host = host; self.servidor = servidor; self.helper = helper; self.buzon = buzon
    }

    /// Puerta de una empresa abierta: socket en `~/Library/Application Support/The Last System/s/<vault8>.sock`,
    /// `PeerValidator` de la app y lo del Buzón leído de la configuración confirmada del gobierno.
    public convenience init(vaultID: UUID, servidor: ServidorDeHerramientas, autorizador: Autorizador?,
                            auditoria: any RegistroDeAuditoria = AuditoriaEnMemoria()) throws {
        let socket = try MCPHost.rutaDelSocket(vaultID: vaultID.uuidString)
        let host = MCPHost(socket: socket, validador: .deLaApp(), manejador: servidor, auditoria: auditoria)
        self.init(host: host, servidor: servidor, buzon: { slug in
            autorizador?.config.efectiva().asistente(slug)?.buzon ?? ["cartero", "ordenador"].contains(slug)
        })
    }

    public func arrancar() async throws -> URL? {
        try host.iniciar()
        return host.socket
    }

    public func parar() async {
        host.tokens.revocarTodos()
        host.detener()
    }

    public func abrir(_ c: ContextoDeEjecucion) async throws -> CredencialDeEjecucion {
        let contexto = ContextoDelAsistente(
            ejecucion: c.ejecucion, asistente: c.agente, coordinador: c.coordinador, areas: c.areas, leeAreas: c.leeAreas,
            profundidad: c.profundidad, tarea: c.tarea, origen: c.origen, maxTareas: c.maxTareasPorEjecucion,
            buzon: buzon(c.agente), simulado: c.simulado)
        let token = host.tokens.emitir(contexto)
        let servidor = helper.flatMap {
            ConfiguracionMCP.servidores(helper: $0, socket: host.socket, token: token)[TLSMCPInfo.serverName]
        } ?? MCPServerConfig(command: "tls-mcp", args: ["--socket", host.socket.path],
                             env: [TLSMCPInfo.tokenEnvironmentKey: token])
        return CredencialDeEjecucion(ejecucion: c.ejecucion, token: token, servidor: servidor, socket: host.socket)
    }

    public func revocar(_ credencial: CredencialDeEjecucion) async {
        host.revocar(token: credencial.token)
    }

    /// Una llamada como si llegara por el socket con ese token (simulación): mismo token, mismo contexto, mismas
    /// herramientas y mismos cerrojos.
    public func llamar(herramienta: String, argumentos: String, credencial: CredencialDeEjecucion) async -> ResultadoDeHerramienta {
        guard let contexto = host.tokens.contexto(de: credencial.token) else {
            return ResultadoDeHerramienta(esError: true, texto: "Esta ejecución ya no está en curso.")
        }
        let args: [String: Value]
        if argumentos.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args = [:]
        } else if let a = try? JSONDecoder().decode([String: Value].self, from: Data(argumentos.utf8)) {
            args = a
        } else {
            return ResultadoDeHerramienta(esError: true, texto: "Los argumentos no se entienden.")
        }
        let r = await servidor.llamar(herramienta, argumentos: args, contexto: contexto)
        return ResultadoDeHerramienta(esError: r.esError, texto: r.texto)
    }
}
