import SwiftUI
import TLSCore
import TLSDesign
import TLSImport

/// Estado de la hoja «Crear copia de mi carpeta».
@Observable @MainActor
final class CreateCopyModel {
    enum Privadas: Equatable { case sinResponder, si, no }

    enum Paso {
        case configurar
        case copiando(CopyProgress?)
        /// «Cancelar» pulsado: se espera a que la copia se pare de verdad.
        case cancelando
        /// Parada: no se ha registrado nada y lo copiado a medias está en la Papelera.
        case cancelada
        case terminado(CopyReport, VaultEntry)
        case sinPermiso
        case error(String)
    }

    var origen: URL?
    var privadas: Privadas = .sinResponder
    var exclusiones: [VaultPath] = []
    var incluirArchivo = false
    var paso: Paso = .configurar

    @ObservationIgnored private var task: Task<Void, Never>?

    /// La pregunta de las carpetas privadas es obligatoria.
    var puedeCrear: Bool {
        guard origen != nil else { return false }
        switch privadas {
        case .sinResponder: return false
        case .no: return true
        case .si: return !exclusiones.isEmpty
        }
    }

    var copiando: Bool {
        switch paso {
        case .copiando, .cancelando: return true
        default: return false
        }
    }

    func elegirOrigen() async {
        guard let url = FolderPanels.chooseCompanyFolder(
            prompt: "Elegir", message: "Elige la carpeta de tu empresa. Se copiará; el original no se toca.")
        else { return }
        switch await FolderAccess.check(url) {
        case .ok:
            cambiarOrigen(url)
        case .sinPermiso:
            paso = .sinPermiso
        case .noExiste:
            paso = .error("No encuentro esa carpeta.")
        case .otro:
            paso = .error(FolderAccess.mensajeOtro)
        }
    }

    /// Otra carpeta de origen: la respuesta sobre las carpetas privadas era de la anterior y no vale.
    func cambiarOrigen(_ url: URL) {
        guard url.standardizedFileURL != origen?.standardizedFileURL else { return }
        origen = url
        privadas = .sinResponder
        exclusiones = []
    }

    func elegirPrivadas() {
        guard let origen else { return }
        let elegidas = FolderPanels.choosePrivate(inside: origen)
        var set = Set(exclusiones)
        for path in elegidas where !set.contains(path) {
            exclusiones.append(path)
            set.insert(path)
        }
        privadas = exclusiones.isEmpty ? .sinResponder : .si
    }

    func quitar(_ path: VaultPath) {
        exclusiones.removeAll { $0 == path }
        if exclusiones.isEmpty, privadas == .si { privadas = .sinResponder }
    }

    /// `copier` y `empresas` se sustituyen en las pruebas.
    func crear(model: AppModel, copier: DemoCopier = DemoCopier(), empresas: URL? = nil) {
        guard puedeCrear, let origen else { return }
        let options = CopyOptions(exclusiones: privadas == .si ? exclusiones : [], incluirArchivo: incluirArchivo)
        let destinoBase = empresas ?? AppLocations.empresas
        paso = .copiando(nil)
        task = Task { [weak self] in
            let progress = AsyncStream<CopyProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let progressTask = Task { [weak self] in
                for await p in progress.stream {
                    guard let self, case .copiando = self.paso else { continue }
                    self.paso = .copiando(p)
                }
            }
            defer { progressTask.cancel() }
            do {
                // Sin `Task.detached`: así «Cancelar» llega a la copia, que ya corre en su propio hilo
                // protegido (DatalessGuard) y no ocupa el hilo principal.
                let (report, copied) = try await copier.copy(from: origen, into: destinoBase, options: options) {
                    progress.continuation.yield($0)
                }
                progress.continuation.finish()
                if Task.isCancelled {
                    // Terminó justo al cancelar: tampoco se registra, y va a la Papelera como las demás.
                    try? FileManager.default.trashItem(at: URL(fileURLWithPath: report.destino), resultingItemURL: nil)
                    self?.paso = .cancelada
                    return
                }
                var entry = copied
                if entry.bookmark == nil {
                    entry.bookmark = try? VaultRegistry.makeBookmark(for: URL(fileURLWithPath: entry.ruta))
                }
                if entry.exclusionesCopia.isEmpty { entry.exclusionesCopia = options.exclusiones.map(\.raw) }
                if entry.origen == nil { entry.origen = origen.path }
                try model.register(entry)
                self?.paso = .terminado(report, entry)
            } catch {
                progress.continuation.finish()
                guard let self else { return }
                if error is CancellationError || Task.isCancelled {
                    self.paso = .cancelada
                } else if FolderAccess.isPermissionError(error) {
                    self.paso = .sinPermiso
                } else if case CopyError.origenNoAccesible = error {
                    self.paso = .sinPermiso
                } else {
                    self.paso = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }
    }

    /// «Cancelar» durante la copia: se para de verdad (lo copiado a medias va a la Papelera) y no se
    /// registra nada. Mientras se para, la hoja dice «Cancelando…».
    func cancelar() {
        guard let task else { return }
        task.cancel()
        if case .copiando = paso { paso = .cancelando }
    }

    /// Espera a que termine la copia en curso (pruebas).
    func esperar() async {
        await task?.value
    }

    /// «1.034 archivos copiados y verificados · 12 solo en iCloud, no se han descargado».
    static func resumen(_ report: CopyReport) -> String {
        var parts: [String] = []
        if report.verificados == report.copiados {
            parts.append("\(TLSFormat.cuenta(report.copiados, "archivo copiado y verificado", "archivos copiados y verificados"))")
        } else {
            parts.append(TLSFormat.cuenta(report.copiados, "archivo copiado", "archivos copiados"))
            parts.append(TLSFormat.cuenta(report.verificados, "verificado", "verificados"))
        }
        if !report.soloEnICloud.isEmpty {
            parts.append("\(TLSFormat.entero(report.soloEnICloud.count)) solo en iCloud, no se han descargado")
        }
        return parts.joined(separator: " · ")
    }
}

/// Hoja «Crear copia de mi carpeta».
struct CreateCopySheet: View {
    let onOpen: (VaultEntry) -> Void
    /// F3: al terminar se ofrece la puesta en marcha sobre la copia (llega premarcada con lo que ya hay en ella).
    var onPonerEnMarcha: ((VaultEntry) -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copy = CreateCopyModel()

    var body: some View {
        Group {
            switch copy.paso {
            case .configurar:
                form
            case .copiando(let progress):
                CopyProgressView(progress: progress, cancelando: false) {
                    copy.cancelar()
                }
            case .cancelando:
                CopyProgressView(progress: nil, cancelando: true) {}
            case .cancelada:
                cancelledView
            case .terminado(let report, let entry):
                summary(report, entry)
            case .sinPermiso:
                PermissionRecoveryView(folderName: copy.origen?.lastPathComponent, onRetry: {
                    copy.paso = .configurar
                }, onClose: { dismiss() })
            case .error(let message):
                errorView(message)
            }
        }
        .frame(width: 560)
        .interactiveDismissDisabled(copy.copiando)
    }

    // MARK: Formulario

    private var form: some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Crear copia de mi carpeta").font(TLSTokens.Tipo.titulo)
                Text("Trabajarás sobre la copia. Tu carpeta original no cambia y no se descarga nada de iCloud.")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 1. Origen
            VStack(alignment: .leading, spacing: TLSTokens.Espacio.s) {
                SectionTitle("Carpeta de origen")
                ICloudExplanation()
                HStack {
                    if let origen = copy.origen {
                        RowLabel(origen.lastPathComponent, subtitle: TLSFormat.rutaCorta(origen.path),
                                 systemImage: "folder")
                    } else {
                        Text("Sin elegir").foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    Spacer()
                    Button(copy.origen == nil ? "Elegir carpeta…" : "Cambiar…") {
                        Task { await copy.elegirOrigen() }
                    }
                    .accessibilityIdentifier("crearCopia.elegirOrigen")
                }
            }

            Divider()

            // 2. Carpetas privadas (respuesta obligatoria)
            VStack(alignment: .leading, spacing: TLSTokens.Espacio.s) {
                Text("¿Hay carpetas privadas que no deben copiarse?")
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: TLSTokens.Espacio.s) {
                    Toggle(isOn: Binding(
                        get: { copy.privadas == .si },
                        set: { if $0 { copy.elegirPrivadas() } }
                    )) {
                        Label("Sí, las elijo", systemImage: "lock")
                    }
                    .toggleStyle(.button)
                    .disabled(copy.origen == nil)
                    .accessibilityIdentifier("crearCopia.privadasSi")

                    Toggle(isOn: Binding(
                        get: { copy.privadas == .no },
                        set: { if $0 { copy.privadas = .no; copy.exclusiones = [] } }
                    )) {
                        Label("No hay", systemImage: "checkmark")
                    }
                    .toggleStyle(.button)
                    .disabled(copy.origen == nil)
                    .accessibilityIdentifier("crearCopia.privadasNo")
                }
                if copy.origen == nil {
                    Text("Elige primero la carpeta de origen.")
                        .font(TLSTokens.Tipo.pie)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
                if copy.privadas == .si {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(copy.exclusiones, id: \.self) { path in
                            HStack {
                                StatusLabel(path.raw, systemImage: "lock")
                                Spacer()
                                Button("Quitar") { copy.quitar(path) }
                                    .buttonStyle(.link)
                                    .accessibilityLabel("Quitar \(path.raw)")
                            }
                        }
                        Button("Añadir otra…") { copy.elegirPrivadas() }
                            .buttonStyle(.link)
                        Text("No se copian ni se abren: ni siquiera se mira qué contienen.")
                            .font(TLSTokens.Tipo.pie)
                            .foregroundStyle(TLSPaleta.textoSecundario.color)
                    }
                    .padding(.leading, 4)
                    .accessibilityIdentifier("crearCopia.listaPrivadas")
                }
            }

            Divider()

            // 3. Archivo
            Toggle(isOn: $copy.incluirArchivo) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Incluir Archivo (más lento)")
                    Text("Lo retirado. Si no lo incluyes, la copia es mucho más rápida.")
                        .font(TLSTokens.Tipo.pie)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("crearCopia.incluirArchivo")

            HStack {
                Text("La copia irá a \(TLSFormat.rutaCorta(AppLocations.empresas.path)).")
                    .font(TLSTokens.Tipo.pie)
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(AppLocations.empresas.path)
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("crearCopia.cancelar")
                Button("Crear copia") { copy.crear(model: model) }
                    .tlsPrimaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!copy.puedeCrear)
                    .accessibilityIdentifier("crearCopia.crear")
            }
        }
        .padding(TLSTokens.Espacio.xl)
    }

    // MARK: Resumen

    private func summary(_ report: CopyReport, _ entry: VaultEntry) -> some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            Label {
                Text("Copia lista").font(TLSTokens.Tipo.titulo)
            } icon: {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Text(CreateCopyModel.resumen(report))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("crearCopia.resumen")
            VStack(alignment: .leading, spacing: 4) {
                RowLabel(entry.nombre, subtitle: TLSFormat.rutaCorta(report.destino), systemImage: "folder")
                if !report.exclusiones.isEmpty {
                    StatusLabel("Sin copiar: \(report.exclusiones.joined(separator: ", "))", systemImage: "lock")
                        .font(TLSTokens.Tipo.pie)
                        .foregroundStyle(TLSPaleta.textoSecundario.color)
                }
            }
            HStack {
                Button("Mostrar en Finder") {
                    FolderAccess.revealInFinder(URL(fileURLWithPath: report.destino))
                }
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if let onPonerEnMarcha {
                    Button("Abrir la copia") {
                        dismiss()
                        onOpen(entry)
                    }
                    .accessibilityIdentifier("crearCopia.abrir")
                    Button("Ponerla en marcha") {
                        dismiss()
                        onPonerEnMarcha(entry)
                    }
                    .tlsPrimaryButton()
                    .keyboardShortcut(.defaultAction)
                    .help("Te guío paso a paso sobre la copia: nada se escribe hasta que pulsas «Aplicar»")
                    .accessibilityIdentifier("crearCopia.ponerEnMarcha")
                } else {
                    Button("Abrir la copia") {
                        dismiss()
                        onOpen(entry)
                    }
                    .tlsPrimaryButton()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("crearCopia.abrir")
                }
            }
        }
        .padding(TLSTokens.Espacio.xl)
    }

    private var cancelledView: some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            Label {
                Text("He cancelado la copia").font(TLSTokens.Tipo.titulo)
            } icon: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Text("No se ha guardado ninguna copia. Si ya había copiado algo, lo tienes en la Papelera.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Tu carpeta original no ha cambiado.")
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Volver") { copy.paso = .configurar }
                    .tlsPrimaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(TLSTokens.Espacio.xl)
        .accessibilityIdentifier("crearCopia.cancelada")
    }

    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            Label {
                Text("No he podido crear la copia").font(TLSTokens.Tipo.titulo)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tu carpeta original no ha cambiado.")
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            HStack {
                Spacer()
                Button("Cerrar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Volver") { copy.paso = .configurar }
                    .tlsPrimaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(TLSTokens.Espacio.xl)
        .accessibilityIdentifier("crearCopia.error")
    }
}

/// Progreso por fases: contar, copiar, comprobar.
private struct CopyProgressView: View {
    let progress: CopyProgress?
    /// «Cancelar» ya pulsado: se espera a que la copia se pare.
    let cancelando: Bool
    let onCancel: () -> Void

    private let fases: [(CopyProgress.Fase, String)] = [
        (.inventario, "Contar archivos"),
        (.copia, "Copiar"),
        (.verificacion, "Comprobar que cada archivo es idéntico"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            Text(cancelando ? "Cancelando…" : "Creando la copia…").font(TLSTokens.Tipo.titulo)
            VStack(alignment: .leading, spacing: TLSTokens.Espacio.s) {
                ForEach(Array(fases.enumerated()), id: \.offset) { index, fase in
                    HStack {
                        StatusLabel(fase.1, systemImage: icon(for: index))
                            .foregroundStyle(estado(index) == 1 ? TLSPaleta.texto.color : TLSPaleta.textoSecundario.color)
                        Spacer()
                        if estado(index) == 0, let progress {
                            Text(TLSFormat.progreso(progress.hechos, de: progress.total))
                                .monospacedDigit()
                                .foregroundStyle(TLSPaleta.textoSecundario.color)
                        }
                    }
                }
            }
            if let progress, let total = progress.total, total > 0, progress.fase != .inventario {
                ProgressView(value: Double(min(progress.hechos, total)), total: Double(total))
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text("Tu carpeta original no cambia. Lo que esté solo en iCloud no se descarga.")
                .font(TLSTokens.Tipo.pie)
                .foregroundStyle(TLSPaleta.textoSecundario.color)
            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(cancelando)
                    .accessibilityIdentifier("crearCopia.cancelarCopia")
            }
        }
        .padding(TLSTokens.Espacio.xl)
        .accessibilityIdentifier("crearCopia.progreso")
    }

    private var actual: Int {
        switch progress?.fase {
        case nil, .inventario?: 0
        case .copia?: 1
        case .verificacion?: 2
        case .terminado?: 3
        }
    }

    /// 0 = en curso, 1 = hecha, 2 = pendiente.
    private func estado(_ index: Int) -> Int {
        index < actual ? 1 : (index == actual ? 0 : 2)
    }

    private func icon(for index: Int) -> String {
        switch estado(index) {
        case 1: "checkmark.circle"
        case 0: "arrow.triangle.2.circlepath"
        default: "circle"
        }
    }
}
