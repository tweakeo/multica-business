import SwiftUI
import TLSCore
import TLSDesign

/// Ajustes (raíz de la barra lateral y ventana de Ajustes del Mac, ⌘,): tu nombre, tamaño del texto,
/// vista previa, modo de la carpeta y dónde están tus copias.
struct AjustesPantalla: View {
    let sesion: VaultSession?
    @Environment(AppModel.self) private var model

    init(sesion: VaultSession?) {
        self.sesion = sesion
    }

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Tú") {
                TextField("Tu nombre", text: $model.persona, prompt: Text(AppModel.personaPorDefecto))
                    .help("Firma lo que cambias desde la app en el historial de cada nota.")
            }
            Section("Visualización") {
                LabeledContent("Tamaño del texto") {
                    HStack {
                        Slider(value: $model.escalaTexto, in: 0.85...2, step: 0.05)
                            .frame(maxWidth: 220)
                            .accessibilityValue("\(Int((model.escalaTexto * 100).rounded())) %")
                        Text("\(Int((model.escalaTexto * 100).rounded())) %")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                Picker("Vista previa", selection: $model.modoVistaPrevia) {
                    ForEach(ModoVistaPrevia.allCases) { Text($0.titulo).tag($0) }
                }
            }
            if let sesion {
                Section("Esta empresa") {
                    LabeledContent("Carpeta", value: TLSFormat.rutaCorta(sesion.entry.ruta))
                    LabeledContent("Modo") {
                        switch sesion.modoEscritura {
                        case .escribe: StatusLabel("La app escribe; todo se puede deshacer", systemImage: "pencil.circle")
                        case .abriendo: StatusLabel("Abriendo…", systemImage: "hourglass")
                        case .soloLectura(let m): StatusLabel("Solo lectura: \(m.texto.lowercased())", systemImage: "lock")
                        }
                    }
                    if sesion.entry.clase != .real {
                        if sesion.puedeEscribir {
                            Button("Pasar a solo lectura") { Task { await sesion.pasarASoloLectura(using: model) } }
                        } else {
                            Button("Permitir cambios en esta copia") { Task { await sesion.permitirCambios(using: model) } }
                        }
                        FilasPuestaEnAjustes(sesion: sesion)
                    }
                    // F4 · integración: en una copia hecha por la app, crear su carpeta privada (pendiente de F3).
                    if sesion.entry.clase == .copia, sesion.puedeEscribir {
                        FilaCarpetaPrivada(sesion: sesion)
                    }
                    // F6 · buzon-relevo: «Pasar a mi carpeta real» (solo en una copia cuya carpeta de origen está
                    // registrada como real; oculto en el resto).
                    FilaRelevoAjustes(sesion: sesion)
                    // F6 · corrector (P1-3): «Deshacer el último relevo», también tras cerrar la hoja.
                    FilaDeshacerRelevo(sesion: sesion)
                }
            }
            // F4 · rol mika: interruptor, Claude Code y la app fuera de la ventana (Mika/AjustesAsistentes).
            SeccionesAsistentesAjustes(sesion: sesion)
            // F5 · conexiones: el estado de cada conexión, «Abrir Conexiones» y Avanzado (Conexiones/ConexionesAjustes).
            SeccionesConexionesAjustes(sesion: sesion)
            Section("Tus copias") {
                LabeledContent("Dónde están") {
                    HStack {
                        Text(TLSFormat.rutaCorta(AppLocations.empresas.path)).textSelection(.enabled)
                        Button("Mostrar en Finder") { FolderAccess.revealInFinder(AppLocations.empresas) }
                            .disabled(!FileManager.default.fileExists(atPath: AppLocations.empresas.path))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(TLSPaleta.fondo.color)
        .accessibilityIdentifier("ajustes.general")
    }
}
