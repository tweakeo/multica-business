import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas fuera de pantalla de la pestaña Operación de Dirección, Ventas y Entrega (rol areas-a) con Ribera y los
/// proyectos de prueba de `ApoyoAreasA`, en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>`; las deja en esa
/// carpeta (p. ej. `build/capturas/f2-areas-a/`). Incluye la vista del cliente del portal (criterio F2-8).
@Suite("Capturas de la Operación de Dirección, Ventas y Entrega", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasAreasATests {
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
        for _ in 0..<16 {
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

    /// Las pantallas de Operación: (nombre, área, recuerdos de la pestaña de ventana).
    static let pantallas: [(String, AreaCode, [String: String])] = [
        ("direccion-cronograma", .direccion, ["direccion.vista": "Cronograma"]),
        ("direccion-objetivos", .direccion, ["direccion.vista": "Objetivos"]),
        ("direccion-mapa", .direccion, ["direccion.vista": "Mapa"]),
        ("direccion-decisiones", .direccion, ["direccion.vista": "Decisiones"]),
        ("ventas-crm", .ventas, ["ventas.vista": "CRM"]),
        ("ventas-seguimiento", .ventas, ["ventas.vista": "Seguimiento"]),
        ("ventas-contactos-empresas", .ventas, ["ventas.vista": "Contactos y empresas"]),
        ("entrega-expedientes", .entrega, ["entrega.vista": "Expedientes"]),
        ("entrega-cronograma", .entrega, ["entrega.vista": "Cronograma"]),
        ("entrega-carga", .entrega, ["entrega.vista": "Carga"]),
        ("entrega-revision-viernes", .entrega, ["entrega.vista": "Revisión del viernes"]),
        ("entrega-expediente-viaje", .entrega, ["entrega.expediente": ApoyoAreasA.talleres.raw, "entrega.pestana": "Viaje"]),
        ("entrega-expediente-incidencias", .entrega, ["entrega.expediente": ApoyoAreasA.talleres.raw, "entrega.pestana": "Incidencias"]),
        ("entrega-portal-interna", .entrega, ["entrega.expediente": ApoyoAreasA.talleres.raw, "entrega.pestana": "Portal"]),
        ("entrega-portal-cliente", .entrega, ["entrega.expediente": ApoyoAreasA.talleres.raw, "entrega.pestana": "Portal",
                                              "entrega.portal": "cliente"]),
    ]

    @Test("Operación de Dirección, Ventas y Entrega en claro y oscuro")
    func operacion() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        try ApoyoAreasA.preparar(e.carpeta)
        // Una grave de hoy a las 0:00: a cualquier hora del lunes del ejemplo, su cuenta atrás de 24 h hábiles corre.
        try ApoyoAreasA.cambiar(ApoyoAreasA.incidenciasTalleres.raw, en: e.carpeta, "el mismo día. |",
                                por: "el mismo día. |\n| INC-003 | 2026-10-19 00:00 | Jorge Martín | jorge@talleresmartin.example | Técnica | Grave | En curso | El enlace para subir documentos da error. | Manu |  |")
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        for (nombre, area, extra) in Self.pantallas {
            for oscuro in [false, true] {
                let destino = Destino.area(area, pestana: PestanaArea.operacion.rawValue)
                let nav = Navegacion(raiz: destino)
                nav.actualizarRecuerdo(de: .area(area)) { r in for (k, v) in extra { r.extra[k] = v } }
                let vista = PantallaDestino(destino: destino, sesion: sesion).environment(e.model).environment(\.navegacion, nav)
                try await capturar(vista, ancho: 1240, alto: 1500, oscuro: oscuro, nombre: "area-\(nombre)")
            }
        }
    }

    @Test("VEN-07 en el tablero: el aviso al soltar en Ganada sin cobro, con «Dejarla en Aceptada»")
    func bloqueoGanada() async throws {
        let (base, carpeta) = try ApoyoAreasA.ribera()
        defer { try? FileManager.default.removeItem(at: base) }
        try ApoyoAreasA.preparar(carpeta)
        let foto = ApoyoAreasA.foto(carpeta)
        let d = DatosVentas.calcular(foto: foto, hoy: ApoyoAreasA.hoy)
        let jorge = try #require(d.tablero.tarjeta(VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")))
        guard case .bloqueado(let mensaje, let alternativa) = TableroCRM.soltar(jorge, en: .ganada, invariantes: Invariantes(snapshot: foto),
                                                                               autor: .persona("Manu")) else {
            Issue.record("Debía bloquearse")
            return
        }
        for oscuro in [false, true] {
            let vista = ScrollView {
                TableroCRMVista(tablero: d.tablero, empresa: UUID(), motivoSoloLectura: nil,
                                bloqueo: BloqueoCRM(tarjeta: jorge, mensaje: mensaje, alternativa: alternativa),
                                alMover: { _, _ in }, alAbrir: { _ in }, alAlternativa: { _ in }, alCerrarBloqueo: {})
                    .padding(24)
            }
            .background(TLSPaleta.fondo.color)
            try await capturar(vista, ancho: 1240, alto: 900, oscuro: oscuro, nombre: "area-ventas-crm-ganada-bloqueada")
        }
    }
}
