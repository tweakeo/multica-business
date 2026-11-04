import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas fuera de pantalla del andamio de las áreas con Ribera (Dirección y Finanzas en sus pestañas, y un área en
/// reposo y otra preparada), en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>`; las deja en esa carpeta.
@Suite("Capturas del andamio de F2", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasAndamioTests {
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
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable],
                         backing: .buffered, defer: false)
        w.appearance = apariencia
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        for _ in 0..<14 {
            hosting.layoutSubtreeIfNeeded()
            // Deja correr las tareas del actor principal (lectura del área en segundo plano) entre pasadas.
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        w.close()
    }

    @Test("Dirección y Finanzas de Ribera: Resumen, Control y Sistemas y activos")
    func areas() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        for area in [AreaCode.direccion, .finanzas] {
            for p in [PestanaArea.resumen, .control, .sistemas] {
                for oscuro in [false, true] {
                    let nav = Navegacion(raiz: .area(area, pestana: p.rawValue))
                    let vista = PantallaDestino(destino: .area(area, pestana: p.rawValue), sesion: sesion)
                        .environment(e.model).environment(\.navegacion, nav)
                    let sufijo = p == .resumen ? "resumen" : (p == .control ? "control" : "sistemas")
                    try await capturar(vista, ancho: 1240, alto: 900, oscuro: oscuro,
                                       nombre: "area-\(area.layoutKey)-\(sufijo)")
                }
            }
        }
    }

    @Test("Estados: en reposo con «Activar» y el aviso de los 30 días, y preparada")
    func estados() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        // Solo en la copia temporal: Marca en reposo, Ventas activada hace 12 días y Entrega preparada.
        func cambiar(_ ruta: String, _ de: String, _ por: String) throws {
            let u = e.carpeta.appendingPathComponent(ruta)
            let t = try String(contentsOf: u, encoding: .utf8)
            try Data(t.replacingOccurrences(of: de, with: por).utf8).write(to: u)
        }
        try cambiar("5 · Marca/Área.md", "convierte: Mercado en demanda", "estado: en reposo\nconvierte: Mercado en demanda")
        try cambiar("2 · Ventas/Área.md", "convierte: Desconocidos en clientes", "estado: activa\nactivada: 2026-10-07\nconvierte: Desconocidos en clientes")
        try cambiar("3 · Entrega/Área.md", "convierte: Promesas en resultados", "estado: preparada\nconvierte: Promesas en resultados")
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        for (area, nombre) in [(AreaCode.marca, "reposo"), (.entrega, "preparada")] {
            for oscuro in [false, true] {
                let nav = Navegacion(raiz: .area(area))
                let vista = PantallaDestino(destino: .area(area), sesion: sesion).environment(e.model).environment(\.navegacion, nav)
                try await capturar(vista, ancho: 1240, alto: 860, oscuro: oscuro, nombre: "area-\(area.layoutKey)-\(nombre)")
            }
        }
    }
}
