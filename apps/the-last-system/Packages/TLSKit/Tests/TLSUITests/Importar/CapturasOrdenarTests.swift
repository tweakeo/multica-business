import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
import TLSImport
@testable import TLSUI

/// Capturas de las pantallas de «Ordenar lo que tienes», «Actualizar la copia desde la real» y «Importar de Multica»,
/// fuera de pantalla y en claro y oscuro: solo con `TLS_CAPTURAS=<carpeta>` (van a `<carpeta>/f3-ordenar/`). Nunca se
/// abre la app ni se toca el ratón; todo sobre temporales propios y con un Multica y un Claude falsos.
@Suite("Capturas de ordenar", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasOrdenarTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("f3-ordenar", isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat = 860, alto: CGFloat = 900, oscuro: Bool, nombre: String) async throws {
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
        defer { w.close() }
        for _ in 0..<12 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
    }

    /// Una pantalla del paso como se ve en la ventana: con su margen y desplazamiento.
    func marco<V: View>(_ v: V) -> some View {
        ScrollView { v.padding(TLSEspacio.e24).frame(maxWidth: 800, alignment: .leading) }
            .background(TLSPaleta.fondo.color)
    }

    /// Una empresa desordenada con más variedad (para que las pantallas tengan qué enseñar).
    func empresa() throws -> EmpresaOrdenar {
        let e = try EmpresaOrdenar.desordenada()
        try e.escribir("Notion/Reunión con Panadería Sol 1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d.md", "# Reunión\nAcuerdos de la reunión.\n")
        try e.escribir("Notion/Propuesta jardinería 2026-09 9f8e7d6c5b4a39281706f5e4d3c2b1a0.md", "# Propuesta\nPresupuesto para un cliente.\n")
        try e.escribir("Fotos/logo.png", datos: Data(count: 2048))
        try e.escribir("Fotos/equipo verano.jpg", datos: Data(count: 4096))
        try e.escribir("Documentos/Contrato alquiler local.pdf", datos: Data("%PDF-1.4 contrato".utf8))
        try e.escribir("Documentos/Plan de empresa.docx", datos: Data(count: 1024))
        try e.escribir("Documentos/Cosas varias.txt", "Apuntes sin más.\n")
        try e.escribir("4 · Finanzas/Fiscal/2026/T1/Gastos/recibo sin fecha.pdf", datos: Data("%PDF-1.4 recibo".utf8))
        return e
    }

    @Test("Las pantallas del paso 2 sobre una carpeta por ordenar, en claro y en oscuro")
    func pantallas() async throws {
        for oscuro in [false, true] {
            let e = try empresa()
            defer { e.limpiar() }
            let m = e.modelo()
            m.ejecutorIA = ClaudeEnMemoria()
            await m.arrancar()
            try await capturar(marco(OrdenarLoQueHay(modelo: m)), oscuro: oscuro, nombre: "1-lo-que-hay")
            try await capturar(marco(OrdenarPreparar(modelo: m)), alto: 1100, oscuro: oscuro, nombre: "2-preparar")
            if let viejo = m.bloques.first(where: { $0.bloque.nombre == "Viejo" }) { m.dejarFuera(bloque: viejo.id) }
            m.fijarAlcance(.carpetas, .loActivo(desde: LocalDate(year: 2025, month: 1, day: 1)!))
            try await capturar(marco(OrdenarPorPrograma(modelo: m, multica: true)), oscuro: oscuro, nombre: "3-por-programa")
            try await capturar(marco(OrdenarRepetidos(modelo: m)), oscuro: oscuro, nombre: "4-repetidos")
            await m.prepararVista()
            try await capturar(marco(OrdenarVistaPrevia(modelo: m)), alto: 1200, oscuro: oscuro, nombre: "5-vista-previa")
            await m.aplicar()
            #expect(m.hecho != nil, "\(m.error ?? "")")
            try await capturar(marco(OrdenarComprobacion(modelo: m)), oscuro: oscuro, nombre: "6-comprobacion")
            await m.revisarCalidad()
            try await capturar(marco(OrdenarCalidad(modelo: m)), oscuro: oscuro, nombre: "7-calidad")
        }
    }

    @Test("La copia de G3: completar las fichas, el banco y la comprobación")
    func copiaDeG3() async throws {
        for oscuro in [false, true] {
            let e = try EmpresaOrdenar(copiaDe: EmpresaOrdenar.fixtureG3, exclusiones: ["Privado"])
            defer { e.limpiar() }
            var csv = "fecha,concepto,tercero,total,tipo,numero_factura,cobrado\n"
            for i in 1...9 { csv += "2026-05-0\(i),Consultoría,Cliente \(i),242.00,ingreso,F26010\(i),no\n" }
            try e.escribir("4 · Finanzas/Registros/importar/2026 T2 movimientos.csv", csv)
            let m = e.modelo(.completar)
            await m.arrancar()
            await m.prepararVista()
            try await capturar(marco(OrdenarCompletarFichas(modelo: m)), alto: 1000, oscuro: oscuro, nombre: "g3-1-completar-fichas")
            await m.prepararHeredados()
            try await capturar(marco(OrdenarBanco(modelo: m, abrirBanco: {})), alto: 700, oscuro: oscuro, nombre: "g3-2-banco")
            await m.aplicar()
            try await capturar(marco(OrdenarCompletarFichas(modelo: m)), oscuro: oscuro, nombre: "g3-1-completar-fichas-hecho")
        }
    }

    @Test("Actualizar la copia desde la real y Multica con «0 nuevas»")
    func hojas() async throws {
        for oscuro in [false, true] {
            let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-real-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: base) }
            let real = base.appendingPathComponent("Real", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: EmpresaOrdenar.fixtureG3, to: real)
            let e = try EmpresaOrdenar(copiaDe: real, exclusiones: ["Privado"], origenReal: real.path)
            defer { e.limpiar() }
            try Data("# Nueva Persona\n".utf8).write(to: real.appendingPathComponent("2 · Ventas/Contactos/Nueva Persona.md"))
            try Data("# Otra Persona\n".utf8).write(to: real.appendingPathComponent("2 · Ventas/Contactos/Otra Persona.md"))
            let rumbo = real.appendingPathComponent("1 · Dirección/Rumbo.md")
            try (String(contentsOf: rumbo, encoding: .utf8) + "\nCambio hecho en la real.\n").write(to: rumbo, atomically: true, encoding: .utf8)
            let copia = ModeloActualizarCopia(acceso: e.acceso, real: real)
            await copia.leer()
            try await capturar(ActualizarCopiaHoja(modelo: copia), ancho: 720, alto: 560, oscuro: oscuro, nombre: "actualizar-copia-previa")
            await copia.aplicar(deshacer: nil)
            try await capturar(ActualizarCopiaHoja(modelo: copia), ancho: 720, alto: 560, oscuro: oscuro, nombre: "actualizar-copia-hecho")

            let ribera = try EmpresaOrdenar(copiaDe: EmpresaOrdenar.ribera)
            defer { ribera.limpiar() }
            let config = ribera.url(".tls/config.yaml")
            try String(contentsOf: config, encoding: .utf8).replacingOccurrences(of: "clase: demo", with: "clase: copia")
                .write(to: config, atomically: true, encoding: .utf8)
            let primera = ModeloImportarMultica(acceso: ribera.acceso, ejecutor: OrdenarIntegracionTests.MulticaDeTrabajo())
            await primera.arrancar()
            await primera.leer()
            await primera.aplicar(deshacer: nil)
            let segunda = ModeloImportarMultica(acceso: ribera.acceso, ejecutor: OrdenarIntegracionTests.MulticaDeTrabajo())
            await segunda.arrancar()
            await segunda.leer()
            #expect(segunda.nuevas == 0)
            try await capturar(ImportarMulticaHoja(modelo: segunda), ancho: 780, alto: 620, oscuro: oscuro, nombre: "multica-0-nuevas")
        }
    }
}
