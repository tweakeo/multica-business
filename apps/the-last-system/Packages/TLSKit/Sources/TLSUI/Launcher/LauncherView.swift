import AppKit
import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

/// Selector de empresa (`Window("launcher")`) con la estética de Mosaico v2: la cabecera azul noche, las
/// empresas de esta instalación como filas (copia, ejemplo o solo lectura) y, abajo, «Ver sin tocar…»,
/// «Ver un ejemplo», «Abrir copia» y «Crear copia de mi carpeta…».
struct LauncherView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection: UUID?
    @State private var showCreateCopy = false
    @State private var showViewOnlyIntro = false
    @State private var permissionProblem: String?
    @State private var errorMessage: String?
    @State private var pendingRemoval: VaultEntry?
    @State private var reiniciando: VaultEntry?
    @State private var preparandoEjemplo = false
    /// Puestas en marcha a medias (F3): una fila «Seguir con la puesta en marcha» por cada una.
    @State private var pendientes: [PendientePuesta] = []

    /// Quién instala el ejemplo (en pruebas y capturas, uno con carpetas temporales).
    let instalador: InstaladorEjemplo

    init(instalador: InstaladorEjemplo = InstaladorEjemplo()) {
        self.instalador = instalador
    }

    var body: some View {
        VStack(spacing: TLSEspacio.e16) {
            cabecera
            PuestasPendientesArranque(pendientes: pendientes) { id in abrirPuesta(.retomar, vaultID: id) }
            list
            actions
        }
        .padding(TLSEspacio.e24)
        .frame(minWidth: 640, minHeight: 460)
        .background(TLSPaleta.fondo.color)
        .onAppear {
            model.reload()
            pendientes = PuestaDeLaEmpresa.pendientes(model)
            if !UITestHooks.consumed, let id = UITestHooks.vaultToOpen, let entry = model.entry(id: id) {
                UITestHooks.consumed = true
                open(entry)
            } else if !UITestHooks.consumed, let sheet = UITestHooks.launcherSheet {
                UITestHooks.consumed = true
                showCreateCopy = sheet == "crearCopia"
                showViewOnlyIntro = sheet == "verSinTocar"
            } else if model.abrirPuestaAlArrancar {
                // F3: la primera vez (sin empresas ni puestas en marcha a medias) el arranque es la puesta en marcha.
                model.abrirPuestaAlArrancar = false
                if model.entries.isEmpty, pendientes.isEmpty { abrirPuesta(.empezar) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            pendientes = PuestaDeLaEmpresa.pendientes(model)
        }
        .sheet(isPresented: $showCreateCopy) {
            CreateCopySheet(onOpen: { entry in open(entry) },
                            onPonerEnMarcha: { entry in abrirPuesta(.empezar, vaultID: entry.id) })
        }
        .sheet(isPresented: $showViewOnlyIntro) {
            ViewOnlyIntroSheet { Task { await chooseViewOnly() } }
        }
        .sheet(isPresented: Binding(
            get: { permissionProblem != nil },
            set: { if !$0 { permissionProblem = nil } }
        )) {
            PermissionRecoveryView(folderName: permissionProblem, onRetry: {
                permissionProblem = nil
                showViewOnlyIntro = true
            }, onClose: { permissionProblem = nil })
        }
        .alert("No se ha podido abrir", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "¿Quitar «\(pendingRemoval?.nombre ?? "")» de la lista?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Quitar de la lista", role: .destructive) {
                if let entry = pendingRemoval { try? model.remove(id: entry.id) }
                pendingRemoval = nil
            }
        } message: {
            Text("La carpeta no se borra: solo deja de aparecer aquí.")
        }
        .confirmationDialog(
            "¿Reiniciar el ejemplo?",
            isPresented: Binding(get: { reiniciando != nil }, set: { if !$0 { reiniciando = nil } }),
            titleVisibility: .visible
        ) {
            Button("Reiniciar ejemplo", role: .destructive) {
                if let e = reiniciando { Task { await reiniciarEjemplo(e) } }
                reiniciando = nil
            }
        } message: {
            Text("El ejemplo que tienes va a la Papelera (lo puedes recuperar) y se instala otro, como nuevo. Los cambios que hiciste en él no pasan al nuevo.")
        }
    }

    // MARK: Partes

    private var cabecera: some View {
        CabeceraAzulNoche(rotulo: "The Last System", titulo: "Elige tu empresa",
                          subtitulo: "Trabajas en una copia de la carpeta de tu empresa: el original no se toca.",
                          altoMinimo: TLSAltura.cabeceraBase) {
            Image(systemName: "building.2")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(TLSPaleta.sobreColor.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(TLSPaleta.sobreCabeceraSuave.color))
                .accessibilityHidden(true)
        } acciones: {
            Button {
                abrirPuesta(.empezar, como: "cero")
            } label: {
                Label("Empezar de cero…", systemImage: "plus.circle")
            }
            .tlsBoton(.sobreCabecera)
            .help("Crea la carpeta de una empresa nueva con la puesta en marcha, paso a paso")
            .accessibilityIdentifier("selector.empezarDeCero")
        }
    }

    @ViewBuilder
    private var list: some View {
        let forma = RoundedRectangle(cornerRadius: TLSRadio.mosaico, style: .continuous)
        Group {
            if model.entries.isEmpty {
                VacioExplicado(icono: "building.2", titulo: "Aún no hay ninguna empresa",
                               porQue: "Crea una copia de la carpeta de tu empresa para empezar (tu carpeta original no se toca), o mira cómo funciona con una empresa de ejemplo.",
                               accion: "Crear copia de mi carpeta…", alPulsar: { showCreateCopy = true },
                               secundaria: "Ver un ejemplo", alPulsarSecundaria: { Task { await verEjemplo() } })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("selector.vacio")
            } else {
                List(selection: $selection) {
                    ForEach(model.entries) { entry in
                        LauncherRow(entry: entry)
                            .tag(entry.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: TLSEspacio.e8, bottom: 0, trailing: TLSEspacio.e8))
                            .listRowSeparator(.hidden)
                            .contextMenu { menu(entry) }
                            .accessibilityAction(named: "Abrir") { open(entry) }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 56)
                .contextMenu(forSelectionType: UUID.self) { _ in
                } primaryAction: { ids in
                    if let id = ids.first, let entry = model.entry(id: id) { open(entry) }
                }
                .onKeyPress(.return) {
                    guard let entry = selectedEntry else { return .ignored }
                    open(entry)
                    return .handled
                }
                .accessibilityIdentifier("selector.lista")
                .accessibilityLabel("Empresas de este Mac")
            }
        }
        .padding(.vertical, TLSEspacio.e4)
        .background(forma.fill(TLSPaleta.superficie.color))
        .tlsSombra(.uno, forma: forma)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func menu(_ entry: VaultEntry) -> some View {
        Button("Abrir") { open(entry) }
        Button("Mostrar en Finder") {
            if let url = model.resolveURL(entry) { FolderAccess.revealInFinder(url) }
        }
        if entry.clase == .demo {
            Divider()
            Button("Reiniciar ejemplo…") { reiniciando = entry }
        }
        Divider()
        Button("Quitar de la lista…") { pendingRemoval = entry }
    }

    private var actions: some View {
        HStack(spacing: TLSEspacio.e8) {
            Button("Ver sin tocar…") { showViewOnlyIntro = true }
                .tlsBoton(.discreto)
                .help("Abre tu carpeta real solo para mirar")
                .accessibilityIdentifier("selector.verSinTocar")
            Button {
                Task { await verEjemplo() }
            } label: {
                if preparandoEjemplo {
                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Preparando el ejemplo…") }
                } else {
                    Label("Ver un ejemplo", systemImage: "graduationcap")
                }
            }
            .tlsBoton(.secundario)
            .disabled(preparandoEjemplo)
            .help("Abre Asesoría Ribera, una empresa ficticia, para probar sin miedo")
            .accessibilityIdentifier("selector.ejemplo")
            Spacer()
            Button(Self.openTitle(for: entryToOpen)) {
                if let entry = entryToOpen { open(entry) }
            }
            .tlsBoton(.secundario)
            .disabled(entryToOpen == nil)
            .help(entryToOpen == nil ? "Elige una carpeta de la lista" : "Abre la carpeta elegida")
            .accessibilityIdentifier("selector.abrirCopia")
            Button("Crear copia de mi carpeta…") { showCreateCopy = true }
                .tlsBoton(.principal)
                .keyboardShortcut(model.entries.isEmpty ? .defaultAction : nil)
                .accessibilityIdentifier("selector.crearCopia")
        }
    }

    // MARK: Acciones

    private var selectedEntry: VaultEntry? {
        selection.flatMap { model.entry(id: $0) }
    }

    /// «Abrir copia» solo si lo elegido es una copia; si no, «Abrir» (no se abre la carpeta real
    /// con un botón que dice «copia»).
    static func openTitle(for entry: VaultEntry?) -> String {
        entry?.clase == .copia || entry == nil ? "Abrir copia" : "Abrir"
    }

    /// La elegida en la lista; si no hay ninguna elegida y solo hay una copia, esa.
    private var entryToOpen: VaultEntry? {
        if let selectedEntry { return selectedEntry }
        let copias = model.entries.filter { $0.clase != .real }
        return copias.count == 1 ? copias[0] : nil
    }

    private func open(_ entry: VaultEntry) {
        openWindow.abrirEmpresa(entry.id)
        dismissWindow(id: SceneID.launcher)
    }

    /// La puesta en marcha (F3) en su ventana: empezar (sin carpeta, con «Empiezo de cero» ya elegido o sobre una copia
    /// recién hecha) o seguir una a medias.
    private func abrirPuesta(_ modo: PeticionPuestaEnMarcha.Modo, vaultID: UUID? = nil, como: String? = nil) {
        openWindow(id: PuertaPuestaEnMarcha.ventanaID, value: PeticionPuestaEnMarcha(modo: modo, vaultID: vaultID, como: como))
        dismissWindow(id: SceneID.launcher)
    }

    /// «Ver un ejemplo»: lo instala la primera vez (con un `id` nuevo) y lo abre.
    private func verEjemplo() async {
        guard !preparandoEjemplo else { return }
        preparandoEjemplo = true
        defer { preparandoEjemplo = false }
        do {
            let r = try await instalador.instalarOAbrir(en: model)
            selection = r.entrada.id
            open(r.entrada)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "No he podido preparar el ejemplo."
        }
    }

    /// «Reiniciar ejemplo»: cierra sus ventanas, espera a que se suelte y lo instala de nuevo.
    private func reiniciarEjemplo(_ entry: VaultEntry) async {
        preparandoEjemplo = true
        defer { preparandoEjemplo = false }
        await model.cerrarVentanas(de: entry.id)
        do {
            let nueva = try await instalador.reiniciar(en: model)
            selection = nueva.id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "No he podido reiniciar el ejemplo."
        }
    }

    /// «Ver sin tocar»: selector → comprobación del permiso → registro en solo lectura → ventana.
    private func chooseViewOnly() async {
        // Deja que se cierre la hoja de explicación antes de abrir el selector.
        try? await Task.sleep(for: .milliseconds(250))
        guard let url = FolderPanels.chooseCompanyFolder(
            prompt: "Ver sin tocar", message: "Elige la carpeta de tu empresa. Solo se va a leer.")
        else { return }
        switch await FolderAccess.check(url) {
        case .ok:
            // Respuesta obligatoria: lo privado no se abre ni se lista (se guarda en vaults.json).
            guard let privadas = FolderPanels.askPrivate(inside: url) else { return }
            // Una copia hecha por la app (p. ej. quitada de la lista) vuelve como copia, no como la real.
            let config = try? await CopyConfig.peek(url)
            do {
                let entry = try model.registerReadOnly(url: url, privadas: privadas, config: config)
                open(entry)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "No he podido guardar esa carpeta en la lista."
            }
        case .sinPermiso:
            permissionProblem = url.lastPathComponent
        case .noExiste:
            errorMessage = "No encuentro esa carpeta."
        case .otro:
            errorMessage = FolderAccess.mensajeOtro
        }
    }
}

/// Una empresa de la lista: monograma, nombre, su clase (COPIA, EJEMPLO, SOLO LECTURA) y dónde está.
struct LauncherRow: View {
    let entry: VaultEntry
    @Environment(\.backgroundProminence) private var prominencia

    var body: some View {
        let resaltada = prominencia == .increased
        HStack(spacing: TLSEspacio.e12) {
            Monograma(nombre: entry.nombre, tamano: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TLSEspacio.e8) {
                    Text(entry.nombre)
                        .tlsTexto(TLSTipo.interfazFuerte)
                        .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.texto.color)
                        .lineLimit(1)
                    Text(entry.badge.text)
                        .tlsTexto(TLSTipo.rotulo)
                        .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule(style: .circular).fill(resaltada ? TLSPaleta.sobreCabeceraSuave.color : TLSPaleta.bandeja.color))
                }
                Text(TLSFormat.rutaCorta(entry.ruta))
                    .tlsTexto(TLSTipo.secundario)
                    .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(entry.claseDescripcion)
                .tlsTexto(TLSTipo.secundario)
                .foregroundStyle(resaltada ? TLSPaleta.sobrePrincipal.color : TLSPaleta.textoSecundario.color)
        }
        .padding(.horizontal, TLSEspacio.e4)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.nombre), \(entry.badge.accessibilityText), \(entry.claseDescripcion)")
        .accessibilityIdentifier("selector.fila.\(entry.id.uuidString)")
    }
}
