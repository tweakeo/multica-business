import SwiftUI
import TLSCore
import TLSDesign
import TLSEditor

/// Una nota sin molde de ficha (Markdown, texto o CSV), editable como en Obsidian (PLAN §6.6, DISEÑO §3.2):
/// las propiedades como formulario encima del texto (fuera del texto), el editor con vista previa en vivo, el
/// inspector (⌥⌘I) y el guardado automático. En la carpeta real y en solo lectura, se ve pero no se cambia.
struct NotaEditorPantalla: View {
    let ruta: VaultPath
    let sesion: VaultSession
    /// Se crea al aparecer (no en cada `init`): el editor lleva su `NSTextView`.
    @State private var modelo: ModeloNotaEditor?

    init(ruta: VaultPath, sesion: VaultSession) {
        self.ruta = ruta
        self.sesion = sesion
    }

    var body: some View {
        Group {
            if let modelo, modelo.ruta == ruta {
                NotaEditorCuerpo(ruta: ruta, sesion: sesion, modelo: modelo)
            } else {
                Color.clear
            }
        }
        .onAppear { crear() }
        .onChange(of: ruta) { _, _ in crear() }
    }

    private func crear() {
        if modelo?.ruta != ruta { modelo = ModeloNotaEditor(ruta: ruta, sesion: sesion) }
    }
}

/// La pantalla de la nota con su modelo ya creado.
private struct NotaEditorCuerpo: View {
    let ruta: VaultPath
    let sesion: VaultSession
    let modelo: ModeloNotaEditor
    @State private var lector: LectorNota
    @State private var verDiferencias = false
    @State private var margen: CGFloat = 24
    @State private var cabeceraPuesta = false
    @Environment(\.navegacion) private var nav
    @Environment(\.tlsEscalaTexto) private var escala

    init(ruta: VaultPath, sesion: VaultSession, modelo: ModeloNotaEditor) {
        self.ruta = ruta
        self.sesion = sesion
        self.modelo = modelo
        self._lector = State(initialValue: LectorNota(ruta: ruta, sesion: sesion))
    }

    var body: some View {
        @Bindable var sesion = sesion
        VStack(spacing: 0) {
            BarraNota(modelo: modelo, sesion: sesion, ruta: ruta)
                .padding(.horizontal, margen)
            if modelo.conflicto != nil {
                BannerConflicto(alQuedarme: { Task { await modelo.quedarmeConLoMio() } },
                                alUsarFuera: { Task { await modelo.usarLoDeFuera() } },
                                alVer: { verDiferencias = true })
                    .padding(.horizontal, margen)
                    .padding(.bottom, TLSEspacio.e12)
            }
            contenido
                .padding(.horizontal, margen)
                .padding(.bottom, margen)
        }
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { margen = TLSEspacio.margenPantalla(ancho: $0) }
        .inspector(isPresented: Binding(get: { nav?.inspector ?? sesion.showInspector },
                                        set: { v in if let nav { nav.inspector = v } else { sesion.showInspector = v } })) {
            NoteInspector(session: sesion, nota: lector.nota, titulos: modelo.titulos,
                          irA: { modelo.controlador.ir(a: $0) }, mostrarPropiedades: false)
                .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .task(id: sesion.revision) {
            await lector.cargar()
            if let n = lector.nota { modelo.recibir(n) }
        }
        .onChange(of: lector.nota?.lectura) { _, _ in
            if let n = lector.nota { modelo.recibir(n) }
        }
        .onChange(of: lector.sinLlegarDeICloud) { _, sin in if sin { modelo.noLlegaDeICloud() } }
        .onChange(of: sesion.modoEscritura) { _, _ in modelo.actualizarSoloLectura() }
        .onChange(of: modelo.esMarkdown) { _, md in ponerCabecera(md) }
        .onChange(of: escala) { _, _ in if modelo.esMarkdown { cabeceraPuesta = false; ponerCabecera(true) } }
        .onChange(of: modelo.modo) { _, m in nav?.actualizarRecuerdo(de: .nota(ruta)) { $0.extra["modo"] = m.rawValue } }
        .onAppear(perform: restaurar)
        .onDisappear {
            modelo.guardarYa()
            let y = modelo.controlador.desplazamiento
            nav?.actualizarRecuerdo(de: .nota(ruta)) { $0.desplazamiento = y }
        }
        .sheet(isPresented: $verDiferencias) {
            if let c = modelo.conflicto {
                DiferenciasVersiones(titulo: modelo.titulo,
                                     mia: ModeloNotaEditor.cuerpo(de: c.mia, markdown: modelo.esMarkdown),
                                     deFuera: ModeloNotaEditor.cuerpo(de: c.deFuera, markdown: modelo.esMarkdown),
                                     alQuedarme: { Task { await modelo.quedarmeConLoMio() } },
                                     alUsarFuera: { Task { await modelo.usarLoDeFuera() } },
                                     alCombinar: { t in Task { await modelo.combinar(cuerpo: t) } })
            }
        }
        .background { atajos }
        .alert("Enlace sin destino", isPresented: Binding(
            get: { sesion.linkProblem != nil },
            set: { if !$0 { sesion.linkProblem = nil } }
        )) {
            Button("Aceptar", role: .cancel) { sesion.linkProblem = nil }
        } message: {
            Text(sesion.linkProblem ?? "")
        }
        .accessibilityIdentifier("nota.editor")
        .tutorialAnchor(.ficha)
    }

    // MARK: Contenido

    @ViewBuilder
    private var contenido: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        switch modelo.contenido {
        case .cargando:
            ProgressView("Abriendo…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .editable:
            EditorMarkdown(controlador: modelo.controlador)
                .clipShape(forma)
                .overlay(forma.strokeBorder(TLSPaleta.borde1.color, lineWidth: 1))
                .tlsSombra(.uno, forma: forma)
                .accessibilityLabel("Texto de «\(modelo.titulo)»")
        case .csv(let cabecera, let filas):
            CSVTableView(header: cabecera, rows: filas)
                .background(forma.fill(TLSPaleta.superficie.color))
                .clipShape(forma)
        case .noDescargada:
            VStack(spacing: TLSEspacio.e12) {
                ProgressView().controlSize(.small)
                Label("Esta nota está solo en iCloud. La estoy descargando…", systemImage: "icloud.and.arrow.down")
                    .tlsTexto(TLSTipo.interfaz)
                Text("Se abrirá sola en cuanto llegue.")
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        case .sinLlegarDeICloud:
            VacioExplicado(icono: "icloud.slash", titulo: "No ha llegado de iCloud",
                           porQue: "Esta nota sigue solo en iCloud. Comprueba la conexión a internet y vuelve a intentarlo.",
                           accion: "Volver a intentarlo", alPulsar: { lector.reintentar() },
                           secundaria: "Mostrar en Finder", alPulsarSecundaria: { sesion.revealInFinder(ruta) })
        case .binario(let tamano):
            VacioExplicado(icono: FileKindIcon.systemImage(forExtension: ruta.ext),
                           titulo: "Este fichero no se puede ver aquí",
                           porQue: tamano.map { "Ocupa \(TLSFormat.tamano($0)). Puedes verlo desde Finder." } ?? "Puedes verlo desde Finder.",
                           accion: "Mostrar en Finder", alPulsar: { sesion.revealInFinder(ruta) })
        case .ilegible(let mensaje):
            VacioExplicado(icono: "exclamationmark.triangle", titulo: "No he podido leer esta nota", porQue: mensaje)
        }
    }

    /// Las propiedades van encima del texto, dentro del desplazamiento (como en Obsidian).
    private func ponerCabecera(_ markdown: Bool) {
        guard markdown, !cabeceraPuesta else { return }
        cabeceraPuesta = true
        modelo.controlador.ponerCabecera(
            CabeceraPropiedadesNota(modelo: modelo, sesion: sesion)
                .environment(\.tlsEscalaTexto, escala)
        )
    }

    private func restaurar() {
        guard let r = nav?.recuerdo(de: .nota(ruta)) else { return }
        if let m = r.extra["modo"].flatMap(ModoEditor.init(rawValue:)) { modelo.controlador.cambiarModo(m) }
        if let y = r.desplazamiento, y > 0 {
            Task { @MainActor in
                // Tras la primera lectura y disposición.
                try? await Task.sleep(for: .milliseconds(80))
                modelo.controlador.desplazamiento = y
            }
        }
    }

    /// ⌘E «Como texto» y ⇧⌘E «Lectura» (también con el foco fuera del texto).
    private var atajos: some View {
        ZStack {
            Button("") { modelo.controlador.alternarFuente() }
                .keyboardShortcut("e", modifiers: .command)
            Button("") { modelo.controlador.alternarLectura() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .disabled(!modelo.esMarkdown)
    }
}

/// La franja de arriba: qué es y dónde está, cómo va el guardado, los modos y el panel.
private struct BarraNota: View {
    let modelo: ModeloNotaEditor
    let sesion: VaultSession
    let ruta: VaultPath

    var body: some View {
        HStack(spacing: TLSEspacio.e12) {
            Image(systemName: modelo.tipo?.systemImage ?? "doc.text")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(modelo.titulo)
                    .tlsTexto(TLSTipo.tituloModulo)
                    .foregroundStyle(TLSPaleta.texto.color)
                    .lineLimit(1)
                Text([modelo.tipo?.etiqueta ?? "Nota", ruta.carpetaVisible].joined(separator: " · "))
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: TLSEspacio.e8)
            estadoGuardado
            if modelo.esMarkdown {
                PestanasCapsula(seleccion: Binding(get: { modelo.modo.rawValue },
                                                   set: { modelo.controlador.cambiarModo(ModoEditor(rawValue: $0) ?? .vivo) }),
                                pestanas: ModoEditor.allCases.map { PestanaCapsula(id: $0.rawValue, titulo: $0.titulo) },
                                atajosControl: false)
                    .fixedSize()
                    .disabled(modelo.controlador.soloFuente)
                    .help(modelo.controlador.soloFuente
                          ? "Esta nota pasa de 2 MB: se ve como texto fuente para que la app no vaya lenta."
                          : "⌘E texto fuente · ⇧⌘E lectura")
                    .accessibilityLabel("Cómo ver la nota")
            }
            Button {
                sesion.showInspector.toggle()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .tlsBoton(.discreto, alto: TLSAltura.objetivoMinimo + 4)
            .help("Panel de la nota · ⌥⌘I")
            .accessibilityLabel(sesion.showInspector ? "Ocultar el panel de la nota" : "Mostrar el panel de la nota")
        }
        .frame(minHeight: 56)
    }

    @ViewBuilder
    private var estadoGuardado: some View {
        if let motivo = modelo.motivoSoloLectura {
            Label("Solo lectura", systemImage: "lock")
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .help(motivo)
                .accessibilityLabel("Solo lectura: \(motivo)")
        } else {
            let e = modelo.estado
            HStack(spacing: TLSEspacio.e4) {
                switch e {
                case .guardando: ProgressView().controlSize(.mini)
                case .conflicto, .noSePudo: Image(systemName: TLSEstado.atencion.simbolo).foregroundStyle(TLSEstado.atencion.color.color)
                case .guardado: Image(systemName: "checkmark").foregroundStyle(TLSPaleta.textoSecundario.color)
                case .sinGuardar: Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                Text(e.texto)
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .help({ if case .noSePudo(let m) = e { return m }; return "Se guarda solo mientras escribes" }())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(e.texto)
        }
    }
}

/// Las propiedades encima del texto de la nota (se actualizan solas al leer la nota de nuevo).
struct CabeceraPropiedadesNota: View {
    let modelo: ModeloNotaEditor
    let sesion: VaultSession

    var body: some View {
        PropertiesForm(ruta: modelo.ruta, propiedades: modelo.propiedades, sesion: sesion,
                       motivoSoloLectura: modelo.motivoSoloLectura ?? (modelo.conflicto != nil ? "antes elige qué versión guardar" : nil))
            .padding(.bottom, TLSEspacio.e4)
    }
}
