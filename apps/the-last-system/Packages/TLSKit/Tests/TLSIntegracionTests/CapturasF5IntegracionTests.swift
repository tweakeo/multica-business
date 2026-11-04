import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TLSAgents
import TLSCore
import TLSDesign
@testable import TLSIntegracion
import TLSIntegrations
import TLSGateway
@testable import TLSUI

/// Capturas de lo que monta la integración de F5, con el adaptador de verdad (sobre dobles: nada de Mail, EventKit, TCC,
/// red ni Llavero), fuera de pantalla y en claro y oscuro: Conexiones en el ejemplo (Mail y Calendario «Desactivado
/// (ejemplo)» y el programa «Simulado»), Conexiones en una copia con todo conectado, Hoy y Decisiones con lo que piden
/// las conexiones (Mail sin permiso y un evento cambiado en Calendario) y Ajustes con Conexiones. Solo con
/// `TLS_CAPTURAS=<carpeta>` (`make capturas` → `build/capturas/f5-integracion`).
@Suite("Capturas · integración de F5", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasF5IntegracionTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String, rondas: Int = 14) async throws {
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
        for _ in 0..<rondas {
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

    func conexiones(_ m: ModeloConexiones) -> some View {
        ConexionesVista(modelo: m, abrirBanco: {}).padding(TLSEspacio.e24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(TLSPaleta.fondo.color)
    }

    static let claude = ClaudeEnConexiones(
        info: { InfoClaude(estado: .conectado, texto: "Claude Code está en este Mac y tienes la sesión iniciada.", puedeProbar: true) },
        buscar: {}, probar: {})

    @Test("Conexiones en el ejemplo: Mail y Calendario desactivados (ejemplo) y el programa simulado")
    func ejemplo() async throws {
        let d = DoblesF5()
        try await EntornoF4.con(clase: .demo, inicio: CriteriosF4Tests.domingo, conexiones: d.sistema()) { e in
            _ = try await e.esperarConexiones()
            let s = try #require(ConexionesDeLaApp.fabrica?(e.entry.id))
            _ = try await s.probar(ConectorSimulado.id)
            let m = ModeloConexiones(servicios: s, claude: Self.claude, presencia: PreferenciasPresencia(), abrirEnlace: { _ in })
            await m.cargar()
            m.alternar(.otros)
            for oscuro in [false, true] {
                try await capturar(conexiones(m), ancho: 980, alto: 2000, oscuro: oscuro, nombre: "01-ejemplo-conexiones")
            }
            #expect(d.permisos.pedidos.isEmpty)
        }
    }

    @Test("Una copia con Mail, Calendario y un programa conectados; Hoy, Decisiones y Ajustes con lo que piden las conexiones")
    func copia() async throws {
        let token = "tok_capturas_" + UUID().uuidString.prefix(8)
        let servidorMCP = try await ServidorMCPF5.arrancar(token: String(token), herramientas: ServidorMCPF5.herramientas())
        let d = DoblesF5(permisos: PermisosDoble([.automatizacionMail: .concedido, .calendarios: .concedido]),
                         calendario: CalendarioDoble(permiso: .concedido))
        d.jxa.responder { l in l.guion == GuionesDeMail.cuentas ? JXADoble.cuentas : JXADoble.correos([]) }
        let ruta = "1 · Dirección/Rutinas/revision-de-la-semana.md"
        let grabaciones = try EntornoF4.grabaciones()
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        try await EntornoF4.con(clase: .copia, inicio: CriteriosF4Tests.domingo, preparar: { root in
            let url = VaultPath(ruta).url(in: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("---\ntls_type: routine\ntls_schema: 1\nnombre: Revisión de la semana\narea: direccion\ncadencia: semanal\ndia: lun\nhora: \"09:00\"\nduracion_min: 45\nactiva: true\ncalendario: true\n---\n# Revisión de la semana\n".utf8).write(to: url)
        }, runtime: { puerta in SimulatedRuntime(grabaciones: grabaciones, servidor: puerta) },
           conexiones: d.sistema(ahora: { EntornoF4.lunes })) { e in
            let c = try await e.esperarConexiones()
            let sesion = try #require(e.sesion)
            let s = try #require(ConexionesDeLaApp.fabrica?(e.entry.id))
            try await s.guardarAjustesDeMail(AjustesDeMailConexion(
                cuenta: "Asesoría", privados: [RemitentePrivadoConexion(patron: "consulta.example", etiqueta: "Expediente privado")]))
            try await s.activarCartero(true)
            _ = await s.conectarCalendario()
            try await s.anadir(AltaDeOtroPrograma(id: "ghl", nombre: "GoHighLevel", plantilla: "ghl",
                                                  transporte: .web(direccion: servidorMCP.direccion), clave: String(token)))
            _ = try await s.probar("ghl")
            try await s.cambiarInterruptor("ghl", permiso: "leer-contactos", encender: true)
            // F5 · corrector (P2-12): la misma comprobación de Claude Code en Conexiones y en Ajustes.
            ComprobacionClaude.compartida.comprobador = ComprobadorClaudeFijo(.encontrado(version: "2.1.307", sesion: true))
            await ComprobacionClaude.compartida.buscar()
            defer { ComprobacionClaude.compartida.comprobador = ComprobadorClaudeFijo(.noEncontrado, prueba: false) }
            let m = ModeloConexiones(servicios: s, claude: Self.claude, presencia: PreferenciasPresencia(), abrirEnlace: { _ in })
            await m.cargar()
            m.alternar(.otros)
            for oscuro in [false, true] {
                try await capturar(conexiones(m), ancho: 980, alto: 2100, oscuro: oscuro, nombre: "02-copia-conexiones")
            }

            // Lo que piden las conexiones: Mail sin permiso, un evento cambiado en Calendario y herramientas nuevas.
            d.jxa.responder { _ in JXADoble.denegada }
            _ = await c.leerCorreo()
            let ev = try #require(d.calendario.eventos.first { $0.titulo == "Revisión de la semana" })
            d.calendario.editarFuera(try #require(ev.id)) { $0.inicio = $0.inicio.addingTimeInterval(3600); $0.fin = $0.fin.addingTimeInterval(3600) }
            await c.sincronizarCalendario()
            servidorMCP.estado.herramientas += [ServidorMCPF5.cambia("contacts_delete", propiedades: ["id": .object(["type": "string"])])]
            _ = try await c.pasarela.refrescar("ghl")
            c.ponerRevisiones()
            #expect(ConexionesEnDecisiones.de(sesion).pendientes.count == 3)
            await AlmacenHoy.de(sesion).actualizar(forzar: true)
            func pantalla(_ nav: Navegacion) -> some View {
                ContenidoEmpresa(sesion: sesion, nav: nav).environment(e.model).environment(\.navegacion, nav)
            }
            for oscuro in [false, true] {
                try await capturar(pantalla(Navegacion(raiz: .hoy)), ancho: 1360, alto: 1300, oscuro: oscuro, nombre: "03-hoy-conexiones")
                try await capturar(pantalla(Navegacion(raiz: .decisiones)), ancho: 1360, alto: 2100, oscuro: oscuro,
                                   nombre: "04-decisiones-conexiones")
                // F5 · corrector (P2-12): Ajustes carga Conexiones y Avanzado en segundo plano; se espera a que estén.
                try await capturar(pantalla(Navegacion(raiz: .ajustes)), ancho: 1360, alto: 2300, oscuro: oscuro, nombre: "05-ajustes",
                                   rondas: 40)
            }
        }
        await servidorMCP.parar()
        #expect(FileManager.default.fileExists(atPath: destino.appendingPathComponent("02-copia-conexiones-claro.png").path))
    }
}
