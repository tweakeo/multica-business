import SwiftUI
import TLSCore
import TLSDesign

/// Buscar en toda la carpeta (raíz «búsqueda», ⇧⌘F): las fichas agrupadas por base (por número, nombre, otros
/// nombres y propiedades) y «Dentro de notas» con la línea donde aparece. Nunca lo privado. Clic entra.
struct ResultadosBusquedaPantalla: View {
    let consulta: String
    let sesion: VaultSession
    @State private var texto: String
    @State private var catalogo: CatalogoBusqueda = .vacio
    @State private var hits: [SearchHit] = []
    @State private var buscando = false
    @FocusState private var enfocado: Bool
    @Environment(\.navegar) private var navegar
    @Environment(\.navegacion) private var nav

    init(consulta: String, sesion: VaultSession) {
        self.consulta = consulta
        self.sesion = sesion
        _texto = State(initialValue: consulta)
    }

    var body: some View {
        let q = texto.trimmingCharacters(in: .whitespaces)
        let secciones = MotorPaleta.secciones(q, catalogo: catalogo, texto: [], recientes: [], fijadas: [], acotar: .fichas,
                                              puedeCrear: false)
        ContenedorPantalla(destino: .busqueda(consulta)) {
            CabeceraAzulNoche(rotulo: "Buscar", titulo: q.isEmpty ? "Buscar en la carpeta" : "«\(q)»",
                              subtitulo: "Fichas por número, nombre u otros nombres, y el texto de todas las notas. Lo privado no sale.",
                              altoMinimo: TLSAltura.cabeceraBase) {
                AvatarCabecera(simbolo: "magnifyingglass")
            } acciones: {
                EmptyView()
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                TextField("Buscar en la carpeta", text: $texto)
                    .textFieldStyle(.plain)
                    .focused($enfocado)
                    .accessibilityLabel("Buscar en la carpeta")
                if buscando { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: 520, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous).fill(TLSPaleta.superficie.color))
            .overlay(RoundedRectangle(cornerRadius: TLSRadio.campo, style: .continuous)
                .strokeBorder(enfocado ? TLSPaleta.principal.color : TLSPaleta.separador.color, lineWidth: enfocado ? 2 : 1))
            if q.isEmpty {
                VacioExplicado(icono: "magnifyingglass", titulo: "Escribe lo que buscas",
                               porQue: "Un nombre, un número (F-2026-0013, T-0041) o una palabra que esté dentro de una nota.")
            } else if secciones.isEmpty && hits.isEmpty && !buscando {
                VacioExplicado(icono: "magnifyingglass", titulo: "Nada coincide con «\(q)»",
                               porQue: "Prueba con otra palabra, un número o un nombre más corto. Lo privado no se busca.")
            }
            ForEach(secciones) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo(s.titulo)
                    ForEach(s.items) { it in
                        FilaLista(it.titulo, detalle: it.sub, icono: it.icono, area: it.area?.tlsArea,
                                  etiquetaAccesible: "\(it.titulo), \(it.sub)", accion: { abrir(it) }) {
                            Text(it.tipo).tlsTexto(TLSTipo.secundario).foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                }
            }
            if !hits.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Rotulo("Dentro de notas")
                    ForEach(hits.filter { !$0.note.privado }) { hit in
                        Button { navegar(sesion.destino(para: hit.note.path), modo: .automatico) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.note.title).tlsTexto(TLSTipo.interfazFuerte).foregroundStyle(TLSPaleta.texto.color)
                                Text(Self.fragmento(hit.snippet)).tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.texto.color)
                                    .lineLimit(2)
                                Text(hit.note.path.parent?.raw ?? "").tlsTexto(TLSTipo.secundario)
                                    .foregroundStyle(TLSPaleta.textoSecundario.color).lineLimit(1).truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(EstiloFila(alto: 64))
                        .accessibilityLabel("\(hit.note.title): \(MotorPaleta.limpiarFragmento(hit.snippet))")
                    }
                }
            }
        }
        .task { catalogo = await AlmacenBases.de(sesion).catalogoBusqueda() }
        .task(id: texto) {
            let q = texto.trimmingCharacters(in: .whitespaces)
            nav?.actualizarRecuerdo(de: .busqueda(consulta)) { $0.busqueda = q.isEmpty ? nil : q }
            guard q.count >= 2 else { hits = []; return }
            buscando = true
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let r = await sesion.buscar(q, limite: 50)
            guard !Task.isCancelled else { return }
            hits = r
            buscando = false
        }
        .onAppear {
            if let r = nav?.recuerdo(de: .busqueda(consulta)).busqueda, !r.isEmpty { texto = r }
            enfocado = true
        }
    }

    /// El fragmento con lo encontrado resaltado (entre «‹» y «›» en el índice).
    static func fragmento(_ s: String) -> AttributedString {
        var out = AttributedString()
        var dentro = false
        var actual = ""
        func volcar() {
            var a = AttributedString(actual.replacingOccurrences(of: "\n", with: " "))
            if dentro {
                a.backgroundColor = TLSPaleta.principalSuave.color
                a.underlineStyle = .single
            }
            out += a
            actual = ""
        }
        for ch in s {
            if ch == "‹" { volcar(); dentro = true } else if ch == "›" { volcar(); dentro = false } else { actual.append(ch) }
        }
        volcar()
        return out
    }

    private func abrir(_ it: ItemPaleta) {
        switch it.accion {
        case .abrir(let ruta, _): navegar(sesion.destino(para: ruta), modo: .automatico)
        case .base(let id, _): navegar(.base(id), modo: .automatico)
        case .nueva(let id, let c): navegar(.base(id, contexto: c), modo: .automatico)
        case .ir(let d): navegar(d, modo: .automatico)
        }
    }
}
