import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TLSAgents
import TLSCore
import TLSDesign
@testable import TLSIntegracion
@testable import TLSUI

/// Capturas de lo que añade la integración de F4, fuera de pantalla y en claro y oscuro: Asistentes en una copia sin
/// Claude Code (el aviso con «Buscar otra vez»), la cabecera de un área con «Pedir a …» y «Generar borrador de pieza» en
/// Marca con su motivo. Solo con `TLS_CAPTURAS=<carpeta>` (`make capturas` → `build/capturas/f4-asistentes`). Nunca se
/// abre la app en pantalla ni se lanza Claude.
@Suite("Capturas · integración de F4", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasIntegracionTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String) async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let hosting = NSHostingView(rootView: vista.frame(width: ancho, height: alto))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        hosting.appearance = apariencia
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        w.appearance = apariencia
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        for _ in 0..<14 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        w.close()
    }

    @Test("Asistentes sin Claude Code en una copia, «Pedir a Comercial» en Ventas y «Generar borrador de pieza» en Marca")
    func capturas() async throws {
        try await EntornoF4.con(clase: .copia, inicio: CriteriosF4Tests.domingo, localizador: LocalizadorFijo(.noEncontrado)) { e in
            let sesion = try #require(e.sesion)
            func pantalla(_ nav: Navegacion) -> some View {
                ContenidoEmpresa(sesion: sesion, nav: nav)
                    .environment(e.model)
                    .environment(\.navegacion, nav)
            }
            for oscuro in [false, true] {
                try await capturar(pantalla(Navegacion(raiz: .asistentes)), ancho: 1360, alto: 1000, oscuro: oscuro,
                                   nombre: "09-asistentes-sin-claude")
                try await capturar(pantalla(Navegacion(raiz: .area(.ventas))), ancho: 1360, alto: 700, oscuro: oscuro,
                                   nombre: "10-area-ventas-pedir")
                try await capturar(pantalla(Navegacion(raiz: .area(.marca, pestana: PestanaArea.operacion.rawValue))),
                                   ancho: 1360, alto: 760, oscuro: oscuro, nombre: "11-marca-generar-pieza")
            }
        }
        #expect(FileManager.default.fileExists(atPath: destino.appendingPathComponent("09-asistentes-sin-claude-claro.png").path))
    }
}
