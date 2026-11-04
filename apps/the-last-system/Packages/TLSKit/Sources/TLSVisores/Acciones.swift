import AppKit
import SwiftUI
import TLSDesign

/// Acciones sobre un fichero que salen del visor: abrirlo con otra app del Mac o enseñarlo en Finder.
/// Ninguna escribe en el fichero.
@MainActor
public enum AccionesFichero {
    static let vistaPrevia = "com.apple.Preview"

    /// «Abrir en Vista Previa» (PDF e imágenes).
    public static func abrirEnVistaPrevia(_ url: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: vistaPrevia) else {
            NSWorkspace.shared.open(url)
            return
        }
        abrir(url, con: app)
    }

    /// «Mostrar en Finder».
    public static func mostrarEnFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// «Abrir con la app del Mac» (la de siempre para ese tipo).
    public static func abrirConLaDeSiempre(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Apps que pueden abrir el fichero, la de siempre primero.
    public static func aplicaciones(para url: URL) -> [URL] {
        let todas = NSWorkspace.shared.urlsForApplications(toOpen: url)
        guard let deSiempre = NSWorkspace.shared.urlForApplication(toOpen: url) else { return todas }
        return [deSiempre] + todas.filter { $0 != deSiempre }
    }

    public static func abrir(_ url: URL, con app: URL) {
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Nombre visible de una app («Vista Previa»).
    public static func nombre(de app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }
}

/// Menú «Abrir con…»: las apps del Mac que lo abren, la de siempre primero.
public struct MenuAbrirCon: View {
    let url: URL
    let compacto: Bool
    @State private var apps: [URL] = []

    public init(url: URL, compacto: Bool = false) {
        self.url = url
        self.compacto = compacto
    }

    public var body: some View {
        Menu {
            if apps.isEmpty {
                Button("Abrir con la app de siempre") { AccionesFichero.abrirConLaDeSiempre(url) }
            }
            ForEach(Array(apps.enumerated()), id: \.offset) { i, app in
                Button(AccionesFichero.nombre(de: app) + (i == 0 ? " (la de siempre)" : "")) {
                    AccionesFichero.abrir(url, con: app)
                }
                if i == 0 && apps.count > 1 { Divider() }
            }
        } label: {
            if compacto {
                Image(systemName: "arrow.up.forward.app")
            } else {
                Label("Abrir con…", systemImage: "arrow.up.forward.app")
            }
        }
        .menuStyle(.button)
        .tlsBoton(.secundario)
        .fixedSize()
        .help("Abrir con otra app del Mac")
        .accessibilityLabel("Abrir con otra app del Mac")
        .onAppear { apps = AccionesFichero.aplicaciones(para: url) }
    }
}
