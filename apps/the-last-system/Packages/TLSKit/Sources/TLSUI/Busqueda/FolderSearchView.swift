import SwiftUI
import TLSCore
import TLSDesign

/// ⇧⌘F: búsqueda de texto en toda la carpeta (sin tildes). Elegir un resultado abre la nota.
struct FolderSearchView: View {
    let session: VaultSession
    @State private var query = ""
    @State private var selection: VaultPath?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: TLSTokens.Espacio.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                TextField("Buscar en la carpeta", text: $query)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .accessibilityIdentifier("buscar.campo")
                    .onSubmit { selection = session.searchHits.first?.id }
                    .onKeyPress(.downArrow) {
                        selection = session.searchHits.first?.id
                        fieldFocused = false
                        return .handled
                    }
                if session.searching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, TLSTokens.Espacio.m)
            .padding(.vertical, 9)
            .tlsFocusRing(fieldFocused)
            .padding(6)
            Divider()

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView {
                    Label("Busca en toda tu empresa", systemImage: "magnifyingglass")
                } description: {
                    Text("Da igual que escribas con o sin tildes.")
                }
                .frame(maxHeight: .infinity)
            } else if session.searchHits.isEmpty && !session.searching {
                ContentUnavailableView {
                    Label("Sin resultados", systemImage: "magnifyingglass")
                } description: {
                    Text("No hay nada con «\(query)» en la carpeta de tu empresa.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(session.searchHits) { hit in
                        SearchHitRow(hit: hit)
                            .tag(hit.id)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .contextMenu(forSelectionType: VaultPath.self) { _ in } primaryAction: { paths in
                    if let path = paths.first { session.open(path) }
                }
                .onKeyPress(.return) {
                    guard let selection else { return .ignored }
                    session.open(selection)
                    return .handled
                }
                .accessibilityIdentifier("buscar.resultados")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(TLSTokens.fondo)
        .onAppear {
            query = session.searchQuery
            fieldFocused = true
        }
        .onChange(of: query) { _, q in session.updateSearch(q) }
        .onChange(of: session.searchFocusToken) { _, _ in fieldFocused = true }
    }
}

private struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: hit.note.kind.systemImage)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .accessibilityHidden(true)
                Text(hit.note.title)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if hit.note.privado {
                    Image(systemName: "lock")
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityLabel("Privado")
                }
            }
            Text(hit.note.path.carpetaVisible)
                .font(TLSTokens.Tipo.pie)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .lineLimit(1)
                .truncationMode(.middle)
            if !hit.snippet.isEmpty {
                SnippetText(hit.snippet)
                    .font(TLSTokens.Tipo.detalle)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
