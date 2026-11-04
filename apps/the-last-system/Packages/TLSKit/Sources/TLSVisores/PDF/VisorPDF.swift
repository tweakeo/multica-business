import AppKit
import PDFKit
import SwiftUI
import TLSDesign

/// Visor de PDF dentro de la app (R1), como en Obsidian: miniaturas de las páginas, índice si el PDF lo trae,
/// zoom con «Ajustar a ancho» y «Ajustar a página», «Buscar en el PDF» con sus resultados, selección y copia,
/// «Abrir en Vista Previa» y «Mostrar en Finder». En claro y en oscuro (las páginas siguen en blanco, como
/// el papel). No edita ni anota el fichero.
///
/// Recibe una URL **ya en el Mac** (`VisorFichero` se ocupa de iCloud). `pagina` empieza en 1.
public struct VisorPDF: View {
    let url: URL
    let pagina: Int?
    let alCambiarPagina: ((Int) -> Void)?
    let externo: ControladorPDF?
    @State private var propio: ControladorPDF?
    @State private var cargado: URL?

    public init(url: URL, pagina: Int? = nil, alCambiarPagina: ((Int) -> Void)? = nil) {
        self.url = url
        self.pagina = pagina
        self.alCambiarPagina = alCambiarPagina
        self.externo = nil
    }

    /// Con un controlador propio (para quien quiera mandar sobre él: pruebas, capturas).
    public init(controlador: ControladorPDF, url: URL, pagina: Int? = nil, alCambiarPagina: ((Int) -> Void)? = nil) {
        self.url = url
        self.pagina = pagina
        self.alCambiarPagina = alCambiarPagina
        self.externo = controlador
    }

    public var body: some View {
        Group {
            if let controlador = externo ?? propio {
                PanelVisorPDF(controlador: controlador, url: url)
                    .onAppear { cargarSiHaceFalta(controlador) }
                    .onChange(of: url) { _, _ in cargarSiHaceFalta(controlador) }
                    .onChange(of: controlador.numeroPagina) { _, n in if n > 0 { alCambiarPagina?(n) } }
            } else {
                Color.clear.onAppear { propio = ControladorPDF() }
            }
        }
    }

    private func cargarSiHaceFalta(_ controlador: ControladorPDF) {
        guard cargado != url else { return }
        cargado = url
        if controlador.url != url || controlador.documento == nil {
            controlador.cargar(url: url, pagina: pagina)
            if controlador.totalPaginas > 1, controlador.panel == nil { controlador.panel = .miniaturas }
        } else if let pagina {
            controlador.ir(aPagina: pagina)
        }
    }
}

/// El visor de PDF con su barra y su panel lateral, sobre un controlador ya cargado.
public struct PanelVisorPDF: View {
    @Bindable var controlador: ControladorPDF
    let url: URL
    @State private var textoBusqueda = ""
    @State private var textoPagina = ""
    @FocusState private var enBusqueda: Bool
    @FocusState private var enPagina: Bool

    public init(controlador: ControladorPDF, url: URL) {
        self.controlador = controlador
        self.url = url
    }

    public var body: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        VStack(spacing: 0) {
            barra
                .padding(.horizontal, TLSEspacio.e12)
                .padding(.vertical, TLSEspacio.e8)
            if let error = controlador.error {
                VacioExplicado(icono: "doc.badge.ellipsis", titulo: "No se puede enseñar este PDF", porQue: error,
                               accion: "Abrir en Vista Previa", alPulsar: { AccionesFichero.abrirEnVistaPrevia(url) })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: TLSEspacio.e8) {
                    if let panel = controlador.panel {
                        panelLateral(panel)
                            .frame(width: 208)
                            .transition(.opacity)
                    }
                    VistaPDFKit(controlador: controlador)
                        .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
                        .accessibilityLabel("PDF \(url.deletingPathExtension().lastPathComponent), \(controlador.textoPagina)")
                }
                .padding([.horizontal, .bottom], TLSEspacio.e12)
            }
        }
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .background { atajos }
        .onAppear {
            textoPagina = "\(controlador.numeroPagina)"
            textoBusqueda = controlador.busqueda
        }
        .onChange(of: controlador.busqueda) { _, nueva in if !enBusqueda { textoBusqueda = nueva } }
        .onChange(of: controlador.numeroPagina) { _, n in if !enPagina { textoPagina = "\(n)" } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visor de PDF")
    }

    // MARK: Barra

    private var barra: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TLSEspacio.e8) {
                grupoNavegacion
                Spacer(minLength: TLSEspacio.e8)
                grupoZoom(compacto: false)
                campoBusqueda(ancho: 180)
                grupoFuera(compacto: false)
            }
            VStack(alignment: .leading, spacing: TLSEspacio.e8) {
                HStack(spacing: TLSEspacio.e8) {
                    grupoNavegacion
                    Spacer(minLength: TLSEspacio.e8)
                    grupoFuera(compacto: true)
                }
                HStack(spacing: TLSEspacio.e8) {
                    grupoZoom(compacto: true)
                    campoBusqueda(ancho: 140)
                }
            }
        }
    }

    private var grupoNavegacion: some View {
        HStack(spacing: TLSEspacio.e4) {
            Button {
                withAnimation(TLSMovimiento.pestana) {
                    controlador.panel = controlador.panel == nil ? (controlador.resultados.isEmpty ? .miniaturas : .resultados) : nil
                }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .tlsBoton(.discreto)
            .help(controlador.panel == nil ? "Mostrar las páginas" : "Ocultar el panel")
            .accessibilityLabel(controlador.panel == nil ? "Mostrar las páginas" : "Ocultar el panel")

            Button { controlador.paginaAnterior() } label: { Image(systemName: "chevron.left") }
                .tlsBoton(.discreto)
                .disabled(!controlador.puedeIrAtras)
                .help("Página anterior")
                .accessibilityLabel("Página anterior")
            HStack(spacing: 4) {
                Text("Página").tlsTexto(TLSTipo.interfaz).foregroundStyle(TLSPaleta.textoSecundario.color)
                TextField("", text: $textoPagina)
                    .textFieldStyle(.plain)
                    .tlsTexto(TLSTipo.cifraFila)
                    .multilineTextAlignment(.center)
                    .frame(width: 36, height: TLSAltura.objetivoMinimo)
                    .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
                    .focused($enPagina)
                    .onSubmit {
                        if let n = Int(textoPagina.trimmingCharacters(in: .whitespaces)) { controlador.ir(aPagina: n) }
                        textoPagina = "\(controlador.numeroPagina)"
                    }
                    .accessibilityLabel("Ir a la página")
                    .accessibilityValue(controlador.textoPagina)
                Text("de \(controlador.totalPaginas)")
                    .tlsTexto(TLSTipo.cifraFila)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize()
            }
            Button { controlador.paginaSiguiente() } label: { Image(systemName: "chevron.right") }
                .tlsBoton(.discreto)
                .disabled(!controlador.puedeIrAdelante)
                .help("Página siguiente")
                .accessibilityLabel("Página siguiente")
        }
    }

    private func grupoZoom(compacto: Bool) -> some View {
        HStack(spacing: TLSEspacio.e4) {
            Button { controlador.alejar() } label: { Image(systemName: "minus.magnifyingglass") }
                .tlsBoton(.discreto)
                .help("Alejar (⌘−)")
                .accessibilityLabel("Alejar")
            Text(controlador.textoEscala)
                .tlsTexto(TLSTipo.cifraFila)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .frame(minWidth: 44)
                .accessibilityLabel("Zoom \(controlador.textoEscala)")
            Button { controlador.acercar() } label: { Image(systemName: "plus.magnifyingglass") }
                .tlsBoton(.discreto)
                .help("Acercar (⌘+)")
                .accessibilityLabel("Acercar")
            BotonAlternar(titulo: compacto ? "Ancho" : "Ajustar a ancho", icono: "arrow.left.and.right",
                          activo: controlador.ajuste == .ancho, etiqueta: "Ajustar a ancho") { controlador.ajustarAncho() }
            BotonAlternar(titulo: compacto ? "Página" : "Ajustar a página", icono: "arrow.up.left.and.arrow.down.right",
                          activo: controlador.ajuste == .pagina, etiqueta: "Ajustar a página") { controlador.ajustarPagina() }
        }
    }

    private func campoBusqueda(ancho: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            TextField("Buscar en el PDF", text: $textoBusqueda)
                .textFieldStyle(.plain)
                .tlsTexto(TLSTipo.interfaz)
                .frame(width: ancho)
                .focused($enBusqueda)
                .onSubmit {
                    if textoBusqueda == controlador.busqueda, !controlador.resultados.isEmpty {
                        controlador.siguienteResultado()
                    } else {
                        controlador.buscar(textoBusqueda)
                    }
                }
                .onChange(of: textoBusqueda) { _, nuevo in
                    if nuevo.isEmpty { controlador.limpiarBusqueda() }
                }
                .onExitCommand {
                    textoBusqueda = ""
                    controlador.limpiarBusqueda()
                }
                .accessibilityLabel("Buscar en el PDF")
            if let r = controlador.textoResultados {
                Text(r)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize()
                if !controlador.resultados.isEmpty {
                    Button { controlador.anteriorResultado() } label: { Image(systemName: "chevron.up") }
                        .tlsBoton(.discreto)
                        .help("Resultado anterior (⇧⌘G)")
                        .accessibilityLabel("Resultado anterior")
                    Button { controlador.siguienteResultado() } label: { Image(systemName: "chevron.down") }
                        .tlsBoton(.discreto)
                        .help("Resultado siguiente (⌘G)")
                        .accessibilityLabel("Resultado siguiente")
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(minHeight: TLSAltura.objetivoMinimo + 4)
        .background(Capsule(style: .circular).fill(TLSPaleta.bandeja.color))
        .tlsAnilloFoco(enBusqueda, radio: 999)
    }

    private func grupoFuera(compacto: Bool) -> some View {
        HStack(spacing: TLSEspacio.e4) {
            Button { AccionesFichero.abrirEnVistaPrevia(url) } label: {
                if compacto { Image(systemName: "arrow.up.forward.app") } else { Text("Abrir en Vista Previa") }
            }
            .tlsBoton(.secundario)
            .help("Abrir en Vista Previa")
            .accessibilityLabel("Abrir en Vista Previa")
            Button { AccionesFichero.mostrarEnFinder(url) } label: { Image(systemName: "folder") }
                .tlsBoton(.discreto)
                .help("Mostrar en Finder")
                .accessibilityLabel("Mostrar en Finder")
        }
    }

    // MARK: Panel lateral

    private func panelesDisponibles() -> [PanelPDF] {
        var p: [PanelPDF] = [.miniaturas]
        if !controlador.indice.isEmpty { p.append(.indice) }
        if !controlador.resultados.isEmpty { p.append(.resultados) }
        return p
    }

    private func panelLateral(_ panel: PanelPDF) -> some View {
        VStack(alignment: .leading, spacing: TLSEspacio.e8) {
            let disponibles = panelesDisponibles()
            if disponibles.count > 1 {
                Picker("Panel", selection: Binding(get: { panel }, set: { controlador.panel = $0 })) {
                    ForEach(disponibles) { Text($0.titulo).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Qué enseña el panel")
            } else {
                Rotulo(panel.titulo)
            }
            switch panel {
            case .miniaturas:
                MiniaturasPDF(controlador: controlador)
                    .clipShape(RoundedRectangle(cornerRadius: TLSRadio.bloque, style: .continuous))
            case .indice:
                listaIndice
            case .resultados:
                listaResultados
            }
        }
    }

    private var listaIndice: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(controlador.indice) { entrada in
                    Button { controlador.ir(a: entrada) } label: {
                        HStack(spacing: 6) {
                            Text(entrada.titulo)
                                .tlsTexto(entrada.nivel == 0 ? TLSTipo.interfazMedia : TLSTipo.interfaz)
                                .foregroundStyle(TLSPaleta.texto.color)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            if let p = entrada.pagina {
                                Text("\(p)").tlsTexto(TLSTipo.cifraFila).foregroundStyle(TLSPaleta.textoSecundario.color)
                            }
                        }
                        .padding(.leading, CGFloat(entrada.nivel) * 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(EstiloFila(alto: TLSAltura.filaTabla))
                    .focusEffectDisabled()
                    .accessibilityLabel(entrada.pagina.map { "\(entrada.titulo), página \($0)" } ?? entrada.titulo)
                }
            }
        }
    }

    private var listaResultados: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(controlador.resultados) { r in
                    Button { controlador.irAResultado(r.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Página \(r.pagina)").tlsTexto(TLSTipo.rotulo)
                                .foregroundStyle(controlador.resultadoElegido == r.id ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                            Text(r.fragmento).tlsTexto(TLSTipo.secundario)
                                .foregroundStyle(controlador.resultadoElegido == r.id ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(EstiloFila(seleccionada: controlador.resultadoElegido == r.id, alto: TLSAltura.filaLista))
                    .focusEffectDisabled()
                    .accessibilityLabel("Página \(r.pagina): \(r.fragmento)")
                }
            }
        }
    }

    // MARK: Atajos

    /// ⌘F busca, ⌘G y ⇧⌘G pasan de resultado, ⌘+ ⌘− y ⌘0 cambian el zoom.
    private var atajos: some View {
        Group {
            Button("") { enBusqueda = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { controlador.siguienteResultado() }.keyboardShortcut("g", modifiers: .command)
            Button("") { controlador.anteriorResultado() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("") { controlador.acercar() }.keyboardShortcut("+", modifiers: .command)
            Button("") { controlador.acercar() }.keyboardShortcut("=", modifiers: .command)
            Button("") { controlador.alejar() }.keyboardShortcut("-", modifiers: .command)
            Button("") { controlador.tamanoReal() }.keyboardShortcut("0", modifiers: .command)
        }
        .buttonStyle(.plain)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Cápsula que se queda marcada mientras está activa («Ajustar a ancho»).
struct BotonAlternar: View {
    let titulo: String
    let icono: String
    let activo: Bool
    let etiqueta: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Label(titulo, systemImage: icono).labelStyle(.titleOnly)
        }
        .tlsBoton(.secundario)
        .background(Capsule(style: .circular).fill(activo ? TLSPaleta.principalSuave.color : .clear))
        .accessibilityLabel(etiqueta)
        .accessibilityAddTraits(activo ? .isSelected : [])
        .help(etiqueta)
    }
}
