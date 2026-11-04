import SwiftUI
import TLSCore
import TLSDesign

/// ⌘K: paleta mínima (abrir área, abrir rápido, buscar, carpeta, mostrar en Finder).
struct CommandPaletteSheet: View {
    let session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0

    var body: some View {
        let actions = PaletteAction.filtered(PaletteAction.all(session: session), query: query)
        PickerPanel(
            placeholder: "¿Qué quieres hacer?",
            query: $query,
            count: actions.count,
            selected: $selected,
            fieldID: "paleta.campo",
            listID: "paleta.lista",
            emptyText: "No hay ninguna acción con ese nombre.",
            onSubmit: { run(actions) },
            onCancel: { dismiss() }
        ) { index, _ in
            let action = actions[index]
            HStack(spacing: TLSTokens.Espacio.s) {
                Image(systemName: action.systemImage)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                if let area = action.area {
                    AreaDot(color: area.color, text: action.title)
                } else {
                    Text(action.title)
                }
                Spacer()
                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            .accessibilityElement(children: .combine)
            .onTapGesture(count: 2) { selected = index; run(actions) }
            .onTapGesture { selected = index }
        }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func run(_ actions: [PaletteAction]) {
        guard actions.indices.contains(selected) else { return }
        let action = actions[selected]
        dismiss()
        // La acción se ejecuta cuando la hoja ya se ha cerrado (puede abrir otra hoja).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            action.perform()
        }
    }
}

/// Una acción de la paleta.
struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var shortcut: String?
    var area: AreaCode?
    let perform: @MainActor () -> Void

    @MainActor
    static func all(session: VaultSession) -> [PaletteAction] {
        var actions: [PaletteAction] = AreaCode.allCases.map { code in
            let title = session.area(code)?.etiquetaNumerada ?? code.etiquetaNumerada
            return PaletteAction(id: "area.\(code.rawValue)", title: "Abrir área \(title)",
                                 systemImage: code.systemImage, shortcut: "⌘\(code.numero + 3)", area: code) {
                session.select(area: code)
            }
        }
        actions += [
            PaletteAction(id: "abrirRapido", title: "Abrir rápido una nota", systemImage: "doc.text.magnifyingglass",
                          shortcut: "⌘O") { session.navegacionActiva?.hoja = .abrirRapido },
            PaletteAction(id: "buscar", title: "Buscar en la carpeta", systemImage: "magnifyingglass",
                          shortcut: "⇧⌘F") { session.navegar(a: .busqueda(""), modo: .raiz) },
            PaletteAction(id: "carpeta", title: "Ver la carpeta de tu empresa", systemImage: "folder") {
                session.navegar(a: .carpeta(nil), modo: .raiz)
            },
            PaletteAction(id: "bases", title: "Ver todas las bases", systemImage: "tablecells",
                          shortcut: "⇧⌘B") { session.navegar(a: .todasLasBases, modo: .raiz) },
            PaletteAction(id: "finder", title: "Mostrar en Finder", systemImage: "arrow.up.forward.app",
                          shortcut: "⇧⌘R") { session.revealInFinder() },
            PaletteAction(id: "inspector", title: "Mostrar u ocultar las propiedades", systemImage: "sidebar.trailing",
                          shortcut: "⌥⌘I") { session.showInspector.toggle() },
        ]
        return actions
    }

    /// Filtra sin distinguir mayúsculas ni tildes; todas las palabras deben aparecer.
    static func filtered(_ actions: [PaletteAction], query: String) -> [PaletteAction] {
        let words = fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return actions }
        return actions.filter { action in
            let title = fold(action.title)
            return words.allSatisfy { title.contains($0) }
        }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
    }
}
