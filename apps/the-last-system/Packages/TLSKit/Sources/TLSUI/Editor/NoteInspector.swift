import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSEditor

/// Panel derecho (⌥⌘I) de una nota o una ficha: propiedades como formulario (una línea por cambio), índice
/// de la nota, «Enlazan aquí», «Menciones sin enlazar» y el fichero (ruta, Mostrar en Finder, Abrir en
/// Obsidian). Las menciones no enseñan lo privado.
struct NoteInspector: View {
    let session: VaultSession
    /// Nota que enseña (la de la pantalla). Sin ella, la del visor de F0.
    var nota: NoteSnapshot?
    /// Títulos de la nota (del editor) y adónde llevan.
    var titulos: [TituloNota] = []
    var irA: ((Int) -> Void)?
    /// `false` cuando la pantalla ya enseña las propiedades (la nota las lleva encima del texto).
    var mostrarPropiedades = true

    @State private var menciones: [MencionSinEnlazar] = []
    @State private var buscandoMenciones = false
    @State private var foto: VaultSnapshot?

    var body: some View {
        Group {
            if let note = nota ?? session.note {
                List {
                    if mostrarPropiedades, case .markdown(_, let properties, _, _, let kind)? = note.content {
                        Section {
                            LabeledContent("Tipo") {
                                StatusLabel(kind.etiqueta, systemImage: kind.systemImage)
                            }
                            PropertiesForm(ruta: note.path, propiedades: properties, sesion: session,
                                           motivoSoloLectura: motivoSoloLectura, compacta: true)
                        } header: {
                            SectionTitle("Propiedades")
                        }
                    }

                    if !titulos.isEmpty {
                        Section {
                            ForEach(titulos) { t in
                                Button {
                                    irA?(t.posicion)
                                } label: {
                                    Text(t.texto)
                                        .tlsTexto(t.nivel <= 1 ? TLSTipo.interfazFuerte : TLSTipo.interfaz)
                                        .foregroundStyle(TLSPaleta.texto.color)
                                        .lineLimit(1)
                                        .padding(.leading, CGFloat(max(0, t.nivel - 1)) * 12)
                                        .frame(maxWidth: .infinity, minHeight: TLSAltura.objetivoMinimo, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Ir a «\(t.texto)», nivel \(t.nivel)")
                            }
                        } header: {
                            SectionTitle("Índice")
                        }
                        .accessibilityIdentifier("inspector.indice")
                    }

                    Section {
                        if note.content == nil {
                            ProgressView().controlSize(.small)
                        } else if note.backlinks.isEmpty {
                            Text("Ninguna nota enlaza aquí.")
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                        } else {
                            ForEach(note.backlinks) { link in
                                Button {
                                    session.open(link.path)
                                } label: {
                                    RowLabel(link.title, subtitle: link.path.carpetaVisible,
                                             systemImage: link.kind.systemImage)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(link.title), en \(link.path.carpetaVisible)")
                            }
                        }
                    } header: {
                        SectionTitle("Enlazan aquí")
                    }
                    .accessibilityIdentifier("inspector.enlazanAqui")

                    Section {
                        if buscandoMenciones {
                            ProgressView().controlSize(.small)
                        } else if menciones.isEmpty {
                            Text("Ninguna nota la nombra sin enlazarla.")
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                        } else {
                            ForEach(Array(menciones.prefix(20).enumerated()), id: \.offset) { _, m in
                                mencion(m)
                            }
                        }
                    } header: {
                        SectionTitle("Menciones sin enlazar")
                    }
                    .accessibilityIdentifier("inspector.menciones")

                    Section {
                        LabeledContent("Ruta") {
                            Text(note.path.raw)
                                .textSelection(.enabled)
                                .multilineTextAlignment(.trailing)
                        }
                        if let modified = note.summary?.modified {
                            LabeledContent("Modificada", value: TLSFormat.fecha(modified))
                        }
                        if note.summary?.privado == true {
                            StatusLabel("Privada: los asistentes no la ven", systemImage: "lock")
                        }
                        Button {
                            session.revealInFinder(note.path)
                        } label: {
                            Label("Mostrar en Finder", systemImage: "folder")
                        }
                        .accessibilityIdentifier("inspector.mostrarEnFinder")
                        abrirEnObsidian(note.path)
                    } header: {
                        SectionTitle("Fichero")
                    }
                }
                .listStyle(.sidebar)
                .task(id: note.path) { await buscarMenciones(note.path) }
            } else {
                Text("Sin nota abierta")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityIdentifier("inspector")
    }

    private var motivoSoloLectura: String? {
        if case .soloLectura(let m) = session.modoEscritura { return m.texto }
        return session.modoEscritura == .abriendo ? "Abriendo…" : nil
    }

    // MARK: Menciones

    private func buscarMenciones(_ ruta: VaultPath) async {
        buscandoMenciones = true
        defer { buscandoMenciones = false }
        guard let foto = await session.instantanea() else { menciones = []; return }
        self.foto = foto
        let todas = await Task.detached(priority: .utility) { SaludDeEnlaces(snapshot: foto).mencionesSinEnlazar(de: ruta) }.value
        menciones = todas.filter { !session.esPrivado($0.origen) }
    }

    private func mencion(_ m: MencionSinEnlazar) -> some View {
        HStack(alignment: .top, spacing: TLSEspacio.e8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.titulo(de: m.origen))
                    .tlsTexto(TLSTipo.interfazFuerte)
                    .lineLimit(1)
                Text(m.extracto)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button("Enlazar") { Task { await enlazar(m) } }
                .tlsBoton(.discreto, alto: TLSAltura.objetivoMinimo)
                .disabled(!session.puedeEscribir)
                .help(session.puedeEscribir ? "Convierte esta mención en un enlace" : (motivoSoloLectura ?? ""))
                .accessibilityLabel("Enlazar la mención de «\(m.texto)» en \(session.titulo(de: m.origen))")
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { session.open(m.origen) }
        .accessibilityElement(children: .contain)
    }

    private func enlazar(_ m: MencionSinEnlazar) async {
        guard let foto, let plan = SaludDeEnlaces(snapshot: foto).enlazar([m], estilo: .markdown, autor: session.autor) else { return }
        let r = try? await session.escribir(plan: plan, aviso: "Enlacé la mención de «\(m.texto)»")
        if r?.hecho == true { menciones.removeAll { $0 == m } }
    }

    // MARK: Obsidian

    @ViewBuilder
    private func abrirEnObsidian(_ ruta: VaultPath) -> some View {
        if let raiz = session.root {
            let conoce = FileManager.default.fileExists(atPath: raiz.appendingPathComponent(".obsidian").path)
            if conoce, let url = Self.urlObsidian(ruta.url(in: raiz)) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Abrir en Obsidian", systemImage: "arrow.up.forward.app")
                }
            } else {
                Text("Para abrirla en Obsidian, abre antes la carpeta de tu empresa desde Obsidian («Abrir carpeta»).")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
        }
    }

    static func urlObsidian(_ fichero: URL) -> URL? {
        var c = URLComponents()
        c.scheme = "obsidian"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "path", value: fichero.path)]
        return c.url
    }
}
