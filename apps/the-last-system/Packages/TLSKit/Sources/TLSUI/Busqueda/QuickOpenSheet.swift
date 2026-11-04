import SwiftUI
import TLSCore
import TLSDesign

/// ⌘O: abrir rápido por nombre. ↑↓ para elegir, ⏎ para abrir, esc para cerrar.
struct QuickOpenSheet: View {
    let session: VaultSession
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [NoteSummary] = []
    @State private var selected = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        PickerPanel(
            placeholder: "Abrir nota por nombre",
            query: $query,
            count: results.count,
            selected: $selected,
            fieldID: "abrirRapido.campo",
            listID: "abrirRapido.lista",
            emptyText: query.isEmpty ? "Escribe unas letras del nombre." : "No hay ninguna nota con ese nombre.",
            onSubmit: openSelected,
            onCancel: { dismiss() }
        ) { index, isSelected in
            let note = results[index]
            HStack(spacing: TLSTokens.Espacio.s) {
                Image(systemName: note.kind.systemImage)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(width: 18)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title).lineLimit(1)
                    Text(note.path.carpetaVisible)
                        .font(TLSTokens.Tipo.pie)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let area = note.area {
                    AreaDot(color: area.color, text: area.nombre, size: 6)
                        .font(TLSTokens.Tipo.pie)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if note.dataless {
                    StatusLabel("En iCloud", systemImage: "icloud")
                        .font(TLSTokens.Tipo.pie)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if note.privado {
                    Image(systemName: "lock")
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityLabel("Privado")
                }
            }
            .accessibilityElement(children: .combine)
            .onTapGesture(count: 2) { selected = index; openSelected() }
            .onTapGesture { selected = index }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let found = await session.quickOpen(query)
            guard !Task.isCancelled else { return }
            results = found
            selected = 0
        }
    }

    private func openSelected() {
        guard results.indices.contains(selected) else { return }
        let path = results[selected].path
        dismiss()
        session.open(path)
    }
}

/// Panel con campo y lista navegable con el teclado (⌘O y ⌘K).
struct PickerPanel<Row: View>: View {
    let placeholder: String
    @Binding var query: String
    let count: Int
    @Binding var selected: Int
    let fieldID: String
    let listID: String
    let emptyText: String
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let row: (Int, Bool) -> Row
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: TLSTokens.Espacio.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                TextField(placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
                    .accessibilityIdentifier(fieldID)
                    .onSubmit(onSubmit)
                    .onKeyPress(.downArrow) { move(1) }
                    .onKeyPress(.upArrow) { move(-1) }
                    .onKeyPress(.escape) { onCancel(); return .handled }
            }
            .padding(TLSTokens.Espacio.m)
            Divider()
            if count == 0 {
                Text(emptyText)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(0..<count, id: \.self) { index in
                                row(index, index == selected)
                                    .padding(.horizontal, TLSTokens.Espacio.s)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .tlsFocusRing(index == selected)
                                    .contentShape(Rectangle())
                                    .id(index)
                                    .accessibilityAddTraits(index == selected ? .isSelected : [])
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selected) { _, i in proxy.scrollTo(i) }
                }
                .accessibilityIdentifier(listID)
            }
            Divider()
            HStack(spacing: TLSTokens.Espacio.l) {
                Text("↑↓ para elegir · ⏎ para abrir · esc para cerrar")
                Spacer()
                Button("Cerrar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .font(TLSTokens.Tipo.pie)
            .foregroundStyle(TLSPaleta.textoSecundario.color)
            .padding(.horizontal, TLSTokens.Espacio.m)
            .padding(.vertical, 6)
        }
        .frame(width: 560)
        .onAppear { fieldFocused = true }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard count > 0 else { return .handled }
        selected = min(max(selected + delta, 0), count - 1)
        return .handled
    }
}
