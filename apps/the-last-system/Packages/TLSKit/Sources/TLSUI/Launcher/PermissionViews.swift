import AppKit
import SwiftUI
import TLSCore
import TLSDesign

/// Explicación de 2 líneas antes del selector de carpetas (permiso de iCloud de macOS).
struct ICloudExplanation: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Puede que macOS te pida permiso para leer iCloud Drive.", systemImage: "icloud")
                .fontWeight(.medium)
            Text("Acéptalo: The Last System solo lee y no cambia nada. No descarga nada de iCloud salvo la nota que abras.")
                .foregroundStyle(TLSPaleta.textoSecundario.color)
                .padding(.leading, 26)
        }
        .font(TLSTokens.Tipo.detalle)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("permiso.explicacion")
    }
}

/// Hoja previa a «Ver sin tocar»: explicación y botón para elegir la carpeta.
struct ViewOnlyIntroSheet: View {
    let onChoose: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            HStack(spacing: TLSTokens.Espacio.s) {
                Text("Ver sin tocar").font(TLSTokens.Tipo.titulo)
                Badge(.soloLectura)
            }
            Text("Abre tu carpeta real solo para mirar. Hasta que tú lo decidas, la app no escribe en ella.")
                .fixedSize(horizontal: false, vertical: true)
            ICloudExplanation()
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("verSinTocar.cancelar")
                Button("Elegir carpeta…") {
                    dismiss()
                    onChoose()
                }
                .tlsPrimaryButton()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("verSinTocar.elegir")
            }
        }
        .padding(TLSTokens.Espacio.xl)
        .frame(width: 480)
    }
}

/// Pantalla de recuperación cuando macOS no deja leer la carpeta (EPERM).
struct PermissionRecoveryView: View {
    let folderName: String?
    var onRetry: (() -> Void)?
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: TLSTokens.Espacio.l) {
            Label {
                Text("macOS no deja leer \(folderName.map { "«\($0)»" } ?? "esta carpeta")")
                    .font(TLSTokens.Tipo.titulo)
            } icon: {
                Image(systemName: "lock.trianglebadge.exclamationmark")
                    .foregroundStyle(TLSPaleta.textoSecundario.color)
            }
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: TLSTokens.Espacio.s) {
                Text("Para verla, The Last System necesita permiso para leer archivos de iCloud Drive.")
                Text("1. Abre Ajustes del Sistema › Privacidad y seguridad › Archivos y carpetas.")
                Text("2. Busca The Last System y activa iCloud Drive (o la carpeta donde está tu empresa).")
                Text("3. Vuelve aquí y pulsa «Volver a intentarlo».")
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                if let onClose {
                    Button("Cerrar", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                if let onRetry {
                    Button("Volver a intentarlo", action: onRetry)
                        .accessibilityIdentifier("permiso.reintentar")
                }
                Button("Abrir Ajustes del Sistema") {
                    FolderAccess.openPrivacySettings()
                }
                .tlsPrimaryButton()
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("permiso.abrirAjustes")
            }
        }
        .padding(TLSTokens.Espacio.xl)
        .frame(maxWidth: 560)
        .accessibilityIdentifier("permiso.recuperacion")
    }
}

/// Selectores de carpeta (NSOpenPanel). Públicos para la puesta en marcha (TLSOnboarding).
@MainActor
public enum FolderPanels {
    /// Elige una carpeta de empresa.
    public static func chooseCompanyFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = prompt
        panel.message = message
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// «Ver sin tocar»: pregunta obligatoria por las carpetas privadas.
    /// Devuelve las elegidas, `[]` si «No hay», o `nil` si la persona cancela.
    static func askPrivate(inside root: URL) -> [VaultPath]? {
        while true {
            let alert = NSAlert()
            alert.messageText = "¿Hay carpetas privadas que no deben abrirse?"
            alert.informativeText = "Las que elijas no se abren ni se muestran: ni siquiera se mira qué contienen."
            alert.addButton(withTitle: "Sí, las elijo")
            alert.addButton(withTitle: "No hay")
            alert.addButton(withTitle: "Cancelar")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let elegidas = choosePrivate(inside: root, prompt: "No abrir",
                                             message: "Elige las carpetas privadas que no deben abrirse (solo dentro de «\(root.lastPathComponent)»).")
                if !elegidas.isEmpty { return elegidas }
                // Sin elegir nada: se vuelve a preguntar.
            case .alertSecondButtonReturn:
                return []
            default:
                return nil
            }
        }
    }

    /// Elige carpetas o archivos privados **dentro** de `root`. Devuelve rutas relativas.
    public static func choosePrivate(
        inside root: URL, prompt: String = "No copiar",
        message: String? = nil
    ) -> [VaultPath] {
        let panel = NSOpenPanel()
        let delegate = InsideFolderDelegate(root: root)
        panel.delegate = delegate
        panel.directoryURL = root
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = prompt
        panel.message = message
            ?? "Elige las carpetas privadas que no deben copiarse (solo dentro de «\(root.lastPathComponent)»)."
        let response = panel.runModal()
        withExtendedLifetime(delegate) {}
        guard response == .OK else { return [] }
        return panel.urls.compactMap { url in
            guard let rel = VaultPath(url: url, root: root), !rel.isRoot else { return nil }
            return rel
        }
    }
}

/// Restringe el selector a lo que cuelga de `root` (comparación de rutas; no lista nada).
final class InsideFolderDelegate: NSObject, NSOpenSavePanelDelegate {
    private let rootPath: String

    init(root: URL) {
        rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
    }

    private func isInside(_ url: URL, allowRoot: Bool) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
        return (allowRoot && p == rootPath) || p.hasPrefix(rootPath + "/")
    }

    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        isInside(url, allowRoot: true)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        guard isInside(url, allowRoot: false) else {
            throw NSError(domain: "es.thelast.system", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Elige carpetas dentro de la carpeta de origen.",
            ])
        }
    }
}
