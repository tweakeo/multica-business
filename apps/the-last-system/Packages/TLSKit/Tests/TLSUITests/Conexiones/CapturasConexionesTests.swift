import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// F5 · rol conexiones: capturas de la pantalla Conexiones, fuera de pantalla (sin abrir la app ni tocar el ratón), en
/// claro y en oscuro: la pantalla completa, Mail antes del permiso, Mail denegado, Calendario, añadir GoHighLevel y
/// revisar herramientas nuevas. Solo con `TLS_CAPTURAS=<carpeta>` (p. ej. `build/capturas/f5-conexiones`). Servicios en
/// memoria: nada toca Mail, Calendario, la red ni el Llavero.
@Suite("Capturas · Conexiones", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasConexionesTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat = 980, alto: CGFloat, oscuro: Bool, nombre: String) async throws {
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
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        w.close()
    }

    func pantalla(_ m: ModeloConexiones) -> some View {
        // Sin ScrollView: fuera de pantalla no se pinta su contenido.
        ConexionesVista(modelo: m, abrirBanco: {}).padding(TLSEspacio.e24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TLSPaleta.fondo.color)
    }

    static let claude = ClaudeEnConexiones(
        info: { InfoClaude(estado: .conectado, texto: TextosClaude.encontrado(version: "2.1.307", sesion: true), puedeProbar: true) },
        buscar: {}, probar: {})

    func modelo(_ s: ServiciosDeConexionesEnMemoria) async -> ModeloConexiones {
        let m = ModeloConexiones(servicios: s, claude: Self.claude, presencia: PreferenciasPresencia(), abrirEnlace: { _ in })
        await m.cargar()
        return m
    }

    @Test("Conexiones completa, Mail antes del permiso, Mail denegado, Calendario, añadir GoHighLevel y revisar herramientas")
    func capturas() async throws {
        let ayer = Date(timeIntervalSince1970: 1_760_860_800) // 19/10/2026 08:00 UTC aprox.
        for oscuro in [false, true] {
            // 1. Completa: Mail y Calendario conectados, GoHighLevel con un interruptor encendido.
            let s1 = ServiciosDeConexionesEnMemoria()
            await s1.poner(permiso: .mail, .concedido)
            await s1.poner(ajustes: AjustesDeMailConexion(cuenta: "Trabajo", privados: [
                RemitentePrivadoConexion(patron: "@clinica-ejemplo.es", etiqueta: "Expediente privado")]), cartero: true)
            await s1.poner(permiso: .calendario, .concedido)
            await s1.poner(calendarioCreado: true)
            await s1.sembrar(id: "ghl", nombre: "GoHighLevel", plantilla: "ghl", encendidos: ["leer-contactos"], ultima: ayer)
            let m1 = await modelo(s1)
            m1.abierta = .otros
            try await capturar(pantalla(m1), alto: 2000, oscuro: oscuro, nombre: "conexiones-completa")

            // 2. Mail antes del permiso: la explicación.
            let s2 = ServiciosDeConexionesEnMemoria()
            let m2 = await modelo(s2)
            await m2.conectarMail()
            try await capturar(pantalla(m2), alto: 1750, oscuro: oscuro, nombre: "mail-antes-del-permiso")

            // 3. Mail denegado: la recuperación.
            let s3 = ServiciosDeConexionesEnMemoria()
            await s3.poner(alPedir: .mail, .denegado)
            let m3 = await modelo(s3)
            await m3.conectarMail()
            await m3.continuarMail()
            try await capturar(pantalla(m3), alto: 1700, oscuro: oscuro, nombre: "mail-denegado")

            // 3b. Mail: elegir la cuenta y los remitentes privados.
            let s3b = ServiciosDeConexionesEnMemoria()
            await s3b.poner(permiso: .mail, .concedido)
            let m3b = await modelo(s3b)
            await m3b.conectarMail()
            m3b.nuevoPrivado = RemitentePrivadoConexion(patron: "@clinica-ejemplo.es", etiqueta: "Expediente privado")
            m3b.anadirPrivado()
            try await capturar(pantalla(m3b), alto: 1850, oscuro: oscuro, nombre: "mail-cuentas")

            // 4. Calendario: la explicación antes del permiso.
            let s4 = ServiciosDeConexionesEnMemoria()
            let m4 = await modelo(s4)
            await m4.conectarCalendario()
            try await capturar(pantalla(m4), alto: 1700, oscuro: oscuro, nombre: "calendario")

            // 5. Añadir GoHighLevel.
            let s5 = ServiciosDeConexionesEnMemoria()
            let m5 = await modelo(s5)
            if let ghl = m5.plantillas.first(where: { $0.id == "ghl" }) { m5.empezarAlta(ghl) }
            m5.alta?.clave = "clave-de-prueba"
            try await capturar(pantalla(m5), alto: 1950, oscuro: oscuro, nombre: "anadir-ghl")

            // 6. Revisar herramientas nuevas.
            let s6 = ServiciosDeConexionesEnMemoria()
            await s6.sembrar(id: "ghl", nombre: "GoHighLevel", plantilla: "ghl", encendidos: ["leer-contactos"],
                             nuevas: [("contacts_search", true), ("invoice_send", false)], ultima: ayer)
            let m6 = await modelo(s6)
            try await capturar(pantalla(m6), alto: 1950, oscuro: oscuro, nombre: "revisar-herramientas")

            // 7. Ajustes › Avanzado: la matriz técnica.
            let s7 = ServiciosDeConexionesEnMemoria()
            await s7.sembrar(id: "ghl", nombre: "GoHighLevel", plantilla: "ghl", encendidos: ["leer-contactos", "pedir-acciones"])
            let m7 = await modelo(s7)
            await m7.leerMatrices()
            try await capturar(MatrizTecnicaVista(modelo: m7).padding(TLSEspacio.e24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(TLSPaleta.fondo.color),
                               alto: 420, oscuro: oscuro, nombre: "avanzado-matriz")
        }
    }
}
