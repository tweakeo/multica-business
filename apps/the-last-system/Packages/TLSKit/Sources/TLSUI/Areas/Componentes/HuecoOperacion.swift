import SwiftUI
import TLSCore
import TLSDesign

/// Lo que enseña una pestaña Operación mientras su rol de pantallas no la llena: qué habrá (PLAN §6.5) y un
/// camino a lo que ya existe. Sin datos inventados.
struct HuecoOperacion: View {
    let contexto: ContextoArea
    let sesion: VaultSession
    /// «Cronograma de proyectos internos · Mapa 6×6 · Objetivos · Cronología de decisiones».
    let queHabra: String
    var accion: (titulo: String, destino: Destino)?
    @Environment(\.navegar) private var navegar

    var body: some View {
        VacioExplicado(icono: "list.bullet.rectangle", titulo: "La operación de \(contexto.titulo) llega en esta versión",
                       porQue: "Aquí verás: \(queHabra). Mientras tanto, puedes ver su carpeta.",
                       accion: accion?.titulo ?? "Ver la carpeta del área",
                       alPulsar: { navegar(accion?.destino ?? .carpeta(contexto.carpeta), modo: .automatico) },
                       secundaria: accion == nil ? nil : "Ver la carpeta del área",
                       alPulsarSecundaria: accion == nil ? nil : { navegar(.carpeta(contexto.carpeta), modo: .automatico) })
            .accessibilityIdentifier("area.operacion.\(contexto.area.rawValue)")
    }
}
