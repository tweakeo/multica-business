import SwiftUI
import TLSAgents
import TLSCore
import TLSDesign

// F4 · integración. Dos filas de Ajustes:
// - «Esta empresa» › «Crear una carpeta privada» (solo en una copia hecha por la app que se puede escribir).
// - «Asistentes» › «Dejar listos los asistentes» (si la configuración de la carpeta aún no trae los asistentes de serie:
//   una copia o una empresa de antes de F4). Escribe lo mismo que el paso 4 de la puesta en marcha
//   (`AsistentesDeSerie`), como la persona y con Deshacer; nunca cambia ni quita nada de lo que ya hay.

/// «Crear una carpeta privada».
struct FilaCarpetaPrivada: View {
    let sesion: VaultSession
    @State private var nombre = CarpetaPrivadaNueva.nombrePorDefecto
    @State private var creando = false

    var body: some View {
        let privadas = sesion.carpetasPrivadas
        LabeledContent("Carpetas privadas") {
            VStack(alignment: .trailing, spacing: 6) {
                Text(privadas.isEmpty ? "Ninguna: lo privado de tu carpeta real se quedó fuera de la copia."
                     : privadas.map(\.raw).joined(separator: ", "))
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("ajustes.privadas")
                HStack(spacing: 8) {
                    TextField("Nombre", text: $nombre, prompt: Text(CarpetaPrivadaNueva.nombrePorDefecto))
                        .frame(maxWidth: 160)
                        .accessibilityLabel("Nombre de la carpeta privada")
                    Button("Crear una carpeta privada") {
                        creando = true
                        Task {
                            _ = await sesion.crearCarpetaPrivada(nombre: nombre)
                            creando = false
                        }
                    }
                    .disabled(creando || nombre.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("ajustes.crearPrivada")
                }
                Text("Lo que pongas ahí no sale en las bases ni en la búsqueda, y ningún asistente lo ve. Por ejemplo, tus tareas personales de Multica.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// «Dejar listos los asistentes» (si faltan en la configuración de la carpeta).
struct FilaAsistentesDeSerie: View {
    let sesion: VaultSession
    @State private var cambios: [CambioDeAsistentes]?
    @State private var escribiendo = false

    var body: some View {
        Group {
            if let cambios, !cambios.isEmpty, sesion.puedeEscribir {
                LabeledContent("Asistentes de serie") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(Self.resumen(cambios))
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        Button("Dejar listos los asistentes") { Task { await escribir() } }
                            .disabled(escribiendo)
                            .accessibilityIdentifier("ajustes.asistentesDeSerie")
                        Text("Los de las áreas preparadas o en reposo quedan sin activar. Se puede deshacer.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .task(id: sesion.revision) { await leer() }
    }

    static func resumen(_ c: [CambioDeAsistentes]) -> String {
        let fichas = c.filter { $0.ruta.raw != VaultLayout.configFile }.count
        let config = c.contains { $0.ruta.raw == VaultLayout.configFile }
        var partes: [String] = []
        if config { partes.append("añade los asistentes a la configuración de la carpeta") }
        if fichas > 0 { partes.append(fichas == 1 ? "crea 1 ficha de rol" : "crea \(fichas) fichas de rol") }
        let t = partes.joined(separator: " y ")
        return t.prefix(1).uppercased() + t.dropFirst() + "."
    }

    private func leer() async {
        guard let root = sesion.root, sesion.puedeEscribir else { cambios = nil; return }
        let semilla = sesion.entry.id.uuidString.lowercased()
        cambios = await Task.detached(priority: .utility) { AsistentesDeSerie.cambios(root: root, semilla: semilla) }.value
    }

    private func escribir() async {
        guard let root = sesion.root else { return }
        escribiendo = true
        defer { escribiendo = false }
        let semilla = sesion.entry.id.uuidString.lowercased()
        guard let plan = AsistentesDeSerie.plan(root: root, persona: sesion.persona, semilla: semilla) else { return }
        _ = try? await sesion.escribir(plan: plan, aviso: "Asistentes de serie listos", deshacer: sesion.undoManagerActivo)
        await leer()
    }
}
