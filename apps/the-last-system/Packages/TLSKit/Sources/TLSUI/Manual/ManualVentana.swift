import AppKit
import Observation
import SwiftUI
import TLSCore
import TLSDesign

/// Qué sección enseña la ventana del manual (la comparten «Saber más», el menú Ayuda y la ventana).
@MainActor
@Observable
public final class ManualNavegacion {
    public static let compartida = ManualNavegacion()
    /// `Window("manual")`.
    public static let idVentana = "manual"
    /// Sección de «De dónde salen las ideas».
    public static let seccionIdeas = "ideas"

    public var seccion: String?
    public var busqueda = ""

    public init() {}

    /// Abre (o deja lista) una sección. Vacío: la primera.
    public func abrir(_ seccion: String) {
        self.seccion = seccion.isEmpty ? nil : seccion
        busqueda = ""
    }
}

/// La escena del manual: `Window("Manual", id: "manual")`, con búsqueda. Se añade a `TLSScenes`.
public struct EscenaManual: Scene {
    public init() {}

    public var body: some Scene {
        Window("Manual", id: ManualNavegacion.idVentana) {
            ManualVentana()
        }
        .defaultSize(width: 960, height: 680)
        .windowResizability(.contentMinSize)
    }
}

/// «Saber más»: abre el manual en su sección.
public struct BotonSaberMas: View {
    let seccion: String
    let titulo: String
    @Environment(\.openWindow) private var openWindow

    public init(seccion: String, titulo: String = "Saber más") {
        self.seccion = seccion
        self.titulo = titulo
    }

    public var body: some View {
        Button(titulo) {
            ManualNavegacion.compartida.abrir(seccion)
            openWindow(id: ManualNavegacion.idVentana)
        }
        .tlsBoton(.enlace)
        .help("Abre el manual en «\(ManualBiblioteca.deLaApp.seccion(seccion)?.titulo ?? "Manual")»")
        .accessibilityIdentifier("saberMas.\(seccion)")
    }
}

/// La ventana del manual: a la izquierda, buscar y las secciones; a la derecha, la sección elegida.
public struct ManualVentana: View {
    let biblioteca: ManualBiblioteca
    @Bindable private var navegacion: ManualNavegacion
    @FocusState private var buscando: Bool
    @Environment(\.tlsEscalaTexto) private var escala

    public init() {
        self.init(biblioteca: ManualBiblioteca.deLaApp, navegacion: .compartida)
    }

    init(biblioteca: ManualBiblioteca, navegacion: ManualNavegacion) {
        self.biblioteca = biblioteca
        self.navegacion = navegacion
    }

    private var elegida: SeccionManual? {
        navegacion.seccion.flatMap(biblioteca.seccion) ?? biblioteca.secciones.first
    }

    public var body: some View {
        HStack(spacing: 0) {
            lateral
                .frame(width: 300)
                .background(TLSPaleta.superficie.color)
                .overlay(alignment: .trailing) { Rectangle().fill(TLSPaleta.separador.color).frame(width: 1) }
            contenido
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(TLSPaleta.fondo.color)
        .accessibilityIdentifier("manual")
    }

    // MARK: Izquierda

    private var lateral: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(TLSPaleta.textoSecundario.color).accessibilityHidden(true)
                TextField("Buscar en el manual", text: $navegacion.busqueda)
                    .textFieldStyle(.plain)
                    .tlsTexto(TLSTipo.interfaz)
                    .focused($buscando)
                    .accessibilityIdentifier("manual.buscar")
                if !navegacion.busqueda.isEmpty {
                    Button { navegacion.busqueda = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .accessibilityLabel("Borrar la búsqueda")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: TLSAltura.objetivoMinimo + 4)
            .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
            .padding(TLSEspacio.e16)
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if navegacion.busqueda.trimmingCharacters(in: .whitespaces).isEmpty {
                        ForEach(biblioteca.documentos) { doc in
                            Rotulo(doc.titulo)
                                .padding(.horizontal, 12)
                                .padding(.top, TLSEspacio.e12)
                                .padding(.bottom, 4)
                            ForEach(doc.secciones) { s in fila(s, detalle: nil) }
                        }
                    } else {
                        let resultados = biblioteca.buscar(navegacion.busqueda)
                        Rotulo(resultados.isEmpty ? "Sin resultados" : (resultados.count == 1 ? "1 sección" : "\(resultados.count) secciones"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                        ForEach(resultados) { r in fila(r.seccion, detalle: r.extracto) }
                    }
                }
                .padding(.horizontal, TLSEspacio.e8)
                .padding(.bottom, TLSEspacio.e16)
            }
            // La sección abierta desde «Saber más» se ve en la lista aunque esté abajo.
            .onAppear { if let id = elegida?.id { proxy.scrollTo(id, anchor: .center) } }
            .onChange(of: navegacion.seccion) { _, id in
                if let id, navegacion.busqueda.isEmpty { proxy.scrollTo(id, anchor: .center) }
            }
            }
        }
    }

    private func fila(_ s: SeccionManual, detalle: String?) -> some View {
        let seleccionada = s.id == elegida?.id
        return Button {
            navegacion.seccion = s.id
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.titulo).tlsTexto(seleccionada ? TLSTipo.interfazFuerte : TLSTipo.interfaz)
                    .foregroundStyle(TLSPaleta.texto.color)
                if let detalle {
                    Text(detalle).tlsTexto(TLSTipo.secundario)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: TLSAltura.filaBarraLateral)
            .background(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous)
                .fill(seleccionada ? TLSPaleta.principalSuave.color : .clear))
            .contentShape(RoundedRectangle(cornerRadius: TLSRadio.fila, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(s.id)
        .accessibilityAddTraits(seleccionada ? .isSelected : [])
        .accessibilityIdentifier("manual.seccion.\(s.id)")
    }

    // MARK: Derecha

    @ViewBuilder
    private var contenido: some View {
        if let s = elegida {
            ScrollView {
                VStack(alignment: .leading, spacing: TLSEspacio.e16) {
                    Text(biblioteca.documentos.first { $0.id == s.documento }?.titulo ?? "Manual")
                        .tlsTexto(TLSTipo.rotulo)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                    Text(s.titulo)
                        .tlsTexto(TLSTipo.tituloPantalla)
                        .foregroundStyle(TLSPaleta.texto.color)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(Array(s.bloques.enumerated()), id: \.offset) { _, b in bloque(b) }
                    vecinas(s)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, TLSEspacio.e32)
                .padding(.vertical, TLSEspacio.e32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(s.id)
            .environment(\.openURL, OpenURLAction { url in
                let t = url.absoluteString
                guard t.hasPrefix("#") else { return .systemAction }
                navegacion.seccion = String(t.dropFirst())
                return .handled
            })
            .accessibilityIdentifier("manual.contenido")
        } else {
            VacioExplicado(icono: "book", titulo: "El manual no está",
                           porQue: "No encuentro el manual dentro de la app. Vuelve a instalar The Last System.")
        }
    }

    @ViewBuilder
    private func bloque(_ b: BloqueManual) -> some View {
        switch b {
        case .subtitulo(let t):
            Text(Self.enLinea(t, TLSTipo.tituloSeccion, escala: escala)).tlsTexto(TLSTipo.tituloSeccion).foregroundStyle(TLSPaleta.texto.color)
                .padding(.top, TLSEspacio.e8)
                .accessibilityAddTraits(.isHeader)
        case .parrafo(let t):
            Text(Self.enLinea(t, TLSTipo.lectura, escala: escala)).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                .fixedSize(horizontal: false, vertical: true)
        case .lista(let items, let numerada):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(numerada ? "\(i + 1)." : "•").tlsTexto(TLSTipo.lectura)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                            .frame(minWidth: 18, alignment: .trailing)
                        Text(Self.enLinea(item, TLSTipo.lectura, escala: escala)).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .cita(let t):
            HStack(spacing: 12) {
                Rectangle().fill(TLSPaleta.principal.color).frame(width: 3)
                Text(Self.enLinea(t, TLSTipo.lectura, escala: escala)).tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
        }
    }

    /// «Anterior» y «Siguiente» al pie.
    private func vecinas(_ s: SeccionManual) -> some View {
        let todas = biblioteca.secciones
        let i = todas.firstIndex { $0.id == s.id } ?? 0
        return HStack {
            if i > 0 {
                Button("‹ \(todas[i - 1].titulo)") { navegacion.seccion = todas[i - 1].id }.tlsBoton(.enlace)
            }
            Spacer(minLength: TLSEspacio.e16)
            if i + 1 < todas.count {
                Button("\(todas[i + 1].titulo) ›") { navegacion.seccion = todas[i + 1].id }.tlsBoton(.enlace)
            }
        }
        .padding(.top, TLSEspacio.e16)
    }

    /// Negritas, cursivas y enlaces dentro de una línea, con la letra de Mosaico (no la del sistema).
    static func enLinea(_ t: String, _ estilo: TLSEstiloTexto, escala: CGFloat) -> AttributedString {
        guard var a = try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(t)
        }
        let e = min(max(escala, 0.85), 2)
        for run in a.runs {
            let intent = run.inlinePresentationIntent ?? []
            var s = estilo
            if intent.contains(.stronglyEmphasized) { s = s.peso(max(estilo.peso, 700)) }
            if intent.contains(.emphasized) { s = s.enItalica }
            if intent.contains(.code) { s = TLSTipo.codigo }
            if s != estilo || intent.contains(.code) { a[run.range].font = s.font(escala: e) }
            if run.link != nil {
                a[run.range].foregroundColor = TLSPaleta.enlace.color
                a[run.range].underlineStyle = .single
            }
        }
        return a
    }
}
