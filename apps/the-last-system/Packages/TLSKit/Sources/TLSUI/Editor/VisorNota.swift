import SwiftUI
import TLSCore
import TLSDesign

/// La nota leída, en solo lectura (F0, adaptado a F1: recibe la lectura de su pantalla). Las notas se editan en
/// `NotaEditorPantalla`; esto queda para enseñar lo que no se edita (iCloud, ficheros que no son texto) desde otras
/// pantallas, como la ficha.
struct VisorNota: View {
    let sesion: VaultSession
    let lector: LectorNota

    var body: some View {
        Group {
            if let note = lector.nota {
                content(note)
            } else {
                ProgressView("Abriendo…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .background(TLSPaleta.superficie.color)
        .alert("Enlace sin destino", isPresented: Binding(
            get: { sesion.linkProblem != nil },
            set: { if !$0 { sesion.linkProblem = nil } }
        )) {
            Button("Aceptar", role: .cancel) { sesion.linkProblem = nil }
        } message: {
            Text(sesion.linkProblem ?? "")
        }
    }

    @ViewBuilder
    private func content(_ note: NoteSnapshot) -> some View {
        switch note.content {
        case nil:
            ProgressView("Abriendo…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .markdown(_, _, let body, _, _)?:
            SourceTextView(text: body, mode: .markdown, spans: note.spans, identity: identity(note),
                           onLink: { sesion.followLink($0, desde: note.path) })
        case .plain(let text)?:
            SourceTextView(text: text, mode: .plain, identity: identity(note),
                           onLink: { sesion.followLink($0, desde: note.path) })
        case .csv(let header, let rows, _)?:
            CSVTableView(header: header, rows: rows)
        case .notDownloaded? where lector.sinLlegarDeICloud:
            VacioExplicado(icono: "icloud.slash", titulo: "No ha llegado de iCloud",
                           porQue: "Este fichero sigue solo en iCloud. Comprueba la conexión a internet y vuelve a intentarlo.",
                           accion: "Volver a intentarlo", alPulsar: { lector.reintentar() },
                           secundaria: "Mostrar en Finder", alPulsarSecundaria: { sesion.revealInFinder(note.path) })
                .accessibilityIdentifier("visor.descargaFallida")
        case .notDownloaded?:
            VStack(spacing: TLSEspacio.e12) {
                ProgressView()
                    .controlSize(.small)
                Label("Este fichero está solo en iCloud. Lo estoy descargando…", systemImage: "icloud.and.arrow.down")
                    .tlsTexto(TLSTipo.interfaz)
                Text("Se abrirá solo en cuanto llegue.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("visor.descargando")
        case .binary(let size)?:
            VacioExplicado(icono: FileKindIcon.systemImage(forExtension: note.path.ext),
                           titulo: "Este fichero no se puede ver aquí",
                           porQue: size.map { "Ocupa \(TLSFormat.tamano($0)). Puedes verlo desde Finder." } ?? "Puedes verlo desde Finder.",
                           accion: "Mostrar en Finder", alPulsar: { sesion.revealInFinder(note.path) })
        case .unreadable(let message)?:
            VacioExplicado(icono: "exclamationmark.triangle", titulo: "No he podido leer este fichero", porQue: message)
        }
    }

    private func identity(_ note: NoteSnapshot) -> String {
        "\(note.path.raw)#\(note.lectura)"
    }
}

/// Tabla de un archivo CSV (solo lectura).
struct CSVTableView: View {
    struct Row: Identifiable {
        let id: Int
        let cells: [String]
        func cell(_ i: Int) -> String { i < cells.count ? cells[i] : "" }
    }

    struct Column: Identifiable {
        let id: Int
        let title: String
    }

    let columns: [Column]
    let rows: [Row]

    init(header: [String], rows: [[String]]) {
        let width = max(header.count, rows.map(\.count).max() ?? 0)
        self.columns = (0..<width).map { i in
            let title = i < header.count ? header[i] : ""
            return Column(id: i, title: title.isEmpty ? "Columna \(i + 1)" : title)
        }
        self.rows = rows.enumerated().map { Row(id: $0.offset, cells: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(rows) {
                TableColumnForEach(columns) { column in
                    TableColumn(column.title) { row in
                        Text(row.cell(column.id))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .help(row.cell(column.id))
                    }
                    .width(min: 60, ideal: 150)
                }
            }
            .accessibilityIdentifier("visor.tabla")
            Divider()
            Text(TLSFormat.cuenta(rows.count, "fila", "filas"))
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
        }
    }
}
