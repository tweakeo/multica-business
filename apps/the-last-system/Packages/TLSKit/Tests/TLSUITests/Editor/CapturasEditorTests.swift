import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSEditor
@testable import TLSUI

/// Capturas del editor fuera de pantalla (sin abrir la app): una nota de Ribera en «Edición en vivo» y en
/// «Lectura», en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>` (p. ej. `build/capturas/editor`).
@Suite("Capturas del editor", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasEditorTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    /// Pinta una ventana que nunca se enseña y guarda el PNG de su contenido.
    func guardar(_ ventana: NSWindow, nombre: String) throws {
        guard let vista = ventana.contentView else { return }
        vista.layoutSubtreeIfNeeded()
        vista.displayIfNeeded()
        let rep = try #require(vista.bitmapImageRepForCachingDisplay(in: vista.bounds))
        vista.cacheDisplay(in: vista.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre).png"))
    }

    func esperar(_ segundos: Double, _ vista: NSView) async {
        let fin = Date().addingTimeInterval(segundos)
        while Date() < fin {
            vista.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    @Test("Nota de Ribera (2 · Ventas/Área) en Edición en vivo y en Lectura, claro y oscuro")
    func notaDeRibera() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let area = VaultPath("2 · Ventas/Área.md")
        // Lo que se escribiría a mano en la nota (en la copia temporal, por CommandBus): tareas, un enlace,
        // un aviso, código y un PDF incrustado de la propia carpeta.
        let anadido = """
        - [ ] Llamar a [[sergio-nexo|Sergio Nexo]] por la propuesta de **trimestrales**
        - [x] Revisar el [guion de diagnóstico](Activos/guion-de-diagnostico-v1.md) #ventas
        - Preparar la oferta de *renta* para ==abril==

        > [!tip] Antes de enviar una propuesta
        > Comprueba que el cobro inicial está confirmado.

        Factura de referencia: `F-2026-0014`

        ![[2026-07-10 Movil Levante ML-07-2026 78,65€.pdf#page=1]]
        """
        try await sesion.escribir(.anadirASeccion(area, seccion: "Pendiente", texto: anadido))
        sesion.showInspector = false

        for oscuro in [false, true] {
            for modo in [ModoEditor.vivo, .lectura] {
                let nav = Navegacion(raiz: .area(.ventas))
                nav.entrar(.nota(area))
                let vista = PantallaDestino(destino: .nota(area), sesion: sesion)
                    .environment(e.model)
                    .environment(\.navegacion, nav)
                    .frame(width: 1180, height: 1720)
                let hosting = NSHostingView(rootView: vista)
                hosting.frame = NSRect(x: 0, y: 0, width: 1180, height: 1720)
                let ventana = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView],
                                       backing: .buffered, defer: false)
                ventana.isReleasedWhenClosed = false
                ventana.appearance = NSAppearance(named: oscuro ? .darkAqua : .aqua)
                ventana.contentView = hosting
                await esperar(1.2, hosting)
                // El editor de la pantalla: el modo y, en vivo, el cursor en la línea del enlace (marcas a la vista).
                let texto = try #require(hosting.buscar(VistaTextoMarkdown.self))
                let c = try #require(texto.controlador)
                c.cambiarModo(modo)
                if modo == .vivo {
                    ventana.makeFirstResponder(texto)
                    let r = (c.texto as NSString).range(of: "Revisar el [guion")
                    texto.setSelectedRange(NSRange(location: r.location + 11, length: 0))
                }
                await esperar(1.2, hosting)
                await c.esperarPintado()
                c.colocarIncrustaciones()
                await esperar(0.8, hosting)
                try guardar(ventana, nombre: "nota-ventas-\(modo == .vivo ? "en-vivo" : "lectura")-\(oscuro ? "oscuro" : "claro")")
                ventana.close()
            }
        }
    }
}

extension NSView {
    /// Primera subvista (en profundidad) de un tipo.
    func buscar<T: NSView>(_ tipo: T.Type) -> T? {
        if let v = self as? T { return v }
        for s in subviews { if let v = s.buscar(tipo) { return v } }
        return nil
    }
}
