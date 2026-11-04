import SwiftUI
import TLSCore
import TLSDesign
import TLSUI

// F3 · rol pasos; F5 · rol conexiones. 7 · Conectar (PLAN §6.7, 1 pantalla; cada fila con «Ahora no»): es la misma
// pantalla Conexiones de Ajustes (`ConexionesVista`, TLSUI) en modo paso. Claude Code (lo busco en este Mac, miro si
// tienes la sesión iniciada y lo pruebo dentro de su caja), Mail (explicación antes del aviso de macOS, cuenta,
// remitentes privados y el Cartero), Calendario («The Last System», sin invitar a nadie), Banco por extracto, Otros
// programas, Avisos y «Trabajar con la ventana cerrada» (apagados de serie). Cada elección es la respuesta a su
// pregunta (`.conexion(c)`: «conectar» / «ahora-no»; la ventana cerrada, sí o no). Mail, Calendario y otros programas
// se conectan de verdad solo si la app ya escribe en esa empresa (la integración da sus servicios con
// `ConexionesDeLaApp.fabrica`); si no, queda la elección y se termina en Ajustes › Conexiones.

public struct PasoConectar: View {
    @Bindable var modelo: ModeloPuesta
    @State private var conexiones: ModeloConexiones?

    public init(modelo: ModeloPuesta) {
        self.modelo = modelo
    }

    public var body: some View {
        MarcoPaso(modelo: modelo, paso: .conectar) { _ in
            VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                if let conexiones {
                    ConexionesVista(modelo: conexiones)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .task(id: modelo.motor.estado.vaultID) {
            conexiones = PasoConectar.conexiones(modelo)
        }
        .accessibilityIdentifier("puesta.paso.conectar")
    }

    /// El modelo de Conexiones en modo paso, atado a las respuestas y a la comprobación de Claude Code del paso.
    @MainActor
    static func conexiones(_ modelo: ModeloPuesta, servicios: (any ServiciosDeConexiones)?? = nil) -> ModeloConexiones {
        let s = servicios ?? ConexionesDeLaApp.fabrica?(modelo.motor.estado.vaultID)
        return ModeloConexiones(servicios: s, modo: .paso(elecciones(modelo)), claude: claude(modelo))
    }

    /// Cada elección es la respuesta a su pregunta del paso.
    @MainActor
    static func elecciones(_ modelo: ModeloPuesta) -> EleccionesDelPaso {
        EleccionesDelPaso(
            leer: { [weak modelo] c in
                guard let r = modelo?.respuesta(.conexion(c)) else { return nil }
                if c == .ventanaCerrada { return r.valor.siNo }
                switch r.valor.opcion {
                case "conectar": return true
                case "ahora-no": return false
                default: return nil
                }
            },
            elegir: { [weak modelo] c, si in
                guard let modelo, modelo.preguntas.contains(where: { $0.id == .conexion(c) }) else { return }
                await modelo.contestar(.conexion(c), c == .ventanaCerrada ? .siNo(si) : .opcion(si ? "conectar" : "ahora-no"))
            })
    }

    /// Claude Code según la comprobación del paso (la misma que usa el entrevistador).
    @MainActor
    static func claude(_ modelo: ModeloPuesta) -> ClaudeEnConexiones {
        ClaudeEnConexiones(
            info: { [weak modelo] in
                guard let modelo else { return InfoClaude(estado: .ahoraNo, texto: "") }
                return info(modelo.claude)
            },
            buscar: { [weak modelo] in await modelo?.detectarClaude() },
            probar: { [weak modelo] in await modelo?.probarClaude() })
    }

    static func info(_ e: EstadoClaude) -> InfoClaude {
        switch e {
        case .sinMirar:
            InfoClaude(estado: .ahoraNo, texto: "Aún no lo he buscado.")
        case .buscando:
            InfoClaude(estado: .ahoraNo, texto: TextosClaude.buscando, ocupado: true)
        case .encontrado(_, let aviso):
            InfoClaude(estado: .conectado, texto: "Claude Code está en este Mac.",
                       consejo: aviso, puedeProbar: true)
        case .noEncontrado:
            InfoClaude(estado: .ahoraNo, texto: "No encuentro Claude Code en este Mac. Sigo sin él: todo funciona igual.")
        case .probando:
            InfoClaude(estado: .conectado, texto: TextosClaude.probando, ocupado: true, puedeProbar: true)
        case .probado(let ok, let t):
            InfoClaude(estado: ok ? .conectado : .error(t), texto: t, puedeProbar: true)
        }
    }
}
