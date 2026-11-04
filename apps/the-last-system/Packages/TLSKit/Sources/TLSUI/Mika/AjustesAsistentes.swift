import SwiftUI
import TLSCore
import TLSDesign

// F4 · rol mika. Ajustes › Asistentes: el interruptor de esta empresa, Claude Code (encontrado, versión, sesión y
// «Probar», con el detalle técnico plegado) y la app fuera de la ventana (barra de menús, avisos y «Trabajar con la
// ventana cerrada»), **todo apagado de serie**. `AjustesPantalla` lo incluye con una línea.

/// Las secciones de los asistentes en Ajustes.
struct SeccionesAsistentesAjustes: View {
    let sesion: VaultSession?
    @Bindable var presencia: PreferenciasPresencia
    @Bindable var claude: ComprobacionClaude
    @Environment(AppModel.self) private var model
    @State private var tecnico = false

    init(sesion: VaultSession?, presencia: PreferenciasPresencia = .compartidas, claude: ComprobacionClaude = .compartida) {
        self.sesion = sesion
        self.presencia = presencia
        self.claude = claude
    }

    var body: some View {
        Section("Asistentes") {
            if let sesion {
                LabeledContent("En esta empresa") { InterruptorGeneralAsistentes(sesion: sesion, estilo: .compacto) }
                // F4 · integración: si la carpeta aún no trae los asistentes de serie, se dejan listos desde aquí.
                FilaAsistentesDeSerie(sesion: sesion)
            }
            LabeledContent("Claude Code") {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(claude.texto).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ajustes.claude.estado")
                    if let c = claude.consejo {
                        Text(c).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button(claude.estado == .sinMirar ? "Buscar" : "Buscar otra vez") { Task { await claude.buscar() } }
                            .disabled(claude.estado == .buscando || claude.estado == .probando)
                        Button("Probar") {
                            let negadas = model.entries.compactMap { model.resolveURL($0) }
                            Task { await claude.probar(estado: model.appSupport.appendingPathComponent("comprobacion", isDirectory: true), negadas: negadas) }
                        }
                        .disabled(!claude.estado.encontrado || claude.estado == .probando)
                        .help("Una consulta muy pequeña, sin ver ninguna de tus carpetas")
                        // F4 · corrector (P2): cómo se instala y qué cuenta hace falta.
                        BotonSaberMas(seccion: "claude-code", titulo: "Cómo se conecta")
                    }
                }
            }
            DisclosureGroup("Detalle técnico", isExpanded: $tecnico) {
                Text(claude.detalle ?? "Busca Claude Code para ver dónde está.")
                    .font(.callout.monospaced()).textSelection(.enabled).foregroundStyle(.secondary)
            }
        }
        .task { if claude.estado == .sinMirar { await claude.buscar() } }

        Section("Fuera de la ventana") {
            Toggle("Mostrar los asistentes en la barra de menús", isOn: $presencia.barraDeMenus)
                .accessibilityIdentifier("ajustes.barraDeMenus")
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Avisos del Mac", isOn: Binding(get: { presencia.avisos },
                                                       set: { v in Task { await presencia.encenderAvisos(v) } }))
                    .accessibilityIdentifier("ajustes.avisos")
                Text("Solo lo que está en rojo y lo que espera tu OK; como mucho 3 avisos al día que no sean rojos, y cada cosa una vez.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Trabajar con la ventana cerrada", isOn: $presencia.ventanaCerrada)
                    .accessibilityIdentifier("ajustes.ventanaCerrada")
                Text("La app se abre al iniciar sesión y se queda en la barra de menús: los asistentes siguen con lo suyo aunque cierres la ventana.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if presencia.item.pidePermiso {
                Button("Permitirlo en Ajustes del Sistema") { presencia.item.abrirAjustesDelSistema() }
            }
            if let p = presencia.problema {
                AvisoEnLinea(p, estado: .atencion)
            }
        }
    }
}
