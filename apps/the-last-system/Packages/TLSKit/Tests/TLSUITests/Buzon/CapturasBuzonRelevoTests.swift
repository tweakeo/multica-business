import AppKit
import Foundation
import SwiftUI
import Testing
import TLSAgents
import TLSCore
import TLSDesign
import TLSImport
@testable import TLSUI

/// Capturas de F5 · buzon-relevo, fuera de pantalla (sin abrir la app ni tocar el ratón), en claro y en oscuro: el Buzón
/// de un día, la tarjeta de un correo (antes de aprobar y «Abierto en Mail»), la acción sensible en otro programa, las
/// tarjetas de Calendario, herramientas nuevas y permiso en Decisiones, y la hoja del relevo (explicación, vista previa,
/// conflicto, confirmación, bloqueo y hecho). Solo con `TLS_CAPTURAS=<carpeta>` (p. ej. `build/capturas/f5-buzon-relevo`).
/// Ribera en un temporal y carpetas sintéticas; Mail es un doble.
@Suite("Capturas · Buzón, tarjetas de conexiones y relevo", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasBuzonRelevoTests {
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

    /// Una acción sensible en otro programa preparada por Comercial (como `tls-mcp` con una `ext_*` sensible).
    func accionExterna(_ e: MikaApoyo.Empresa) async throws -> String {
        let bus = try #require(e.sesion.bus)
        let peticion = #"{"argumentos":{"contactId":"c-0042","mensaje":"Hola, Javier: te confirmo la reunión del jueves a las 10:00.","telefono":"+34 600 000 000"},"herramienta":"ext_ghl_send_sms","huella":"5b1e0c9a"}"#
        let b = NuevoBorrador(accion: .externa, area: .ventas, asunto: "Confirmar la reunión por SMS", cuerpo: peticion,
                              para: ["GoHighLevel"], paraTi: "Lo pidió Javier por teléfono.", ejecucion: "r-externa", slug: "sms-javier")
        let (ruta, plan) = Borradores.plan(b, layout: e.foto().layout, autor: .agente("comercial"))
        #expect(try await bus.ejecutar(plan).hecho)
        let s = try await #require(e.asistentes.aprobaciones).solicitar(accion: .externa, borrador: ruta, asistente: "comercial",
                                                                         ejecucion: ContextoEjecucion(id: "r-externa"),
                                                                         herramienta: "ext_ghl_send_sms")
        return try #require(s.id)
    }

    /// Las tres tarjetas de las conexiones, como las pondría la integración.
    func tarjetas(_ e: MikaApoyo.Empresa) {
        let c = ConexionesEnDecisiones.de(e.sesion)
        c.poner([TarjetaDeConexion.calendario(
            id: "calendario:tls://rutina/repaso-semanal", titulo: "Cambiaste «Repaso semanal» en Calendario",
            texto: "Lo moviste en Calendario y la ficha de la rutina dice otra cosa. La app no lo pisa: decides tú.",
            diferencias: [DiferenciaDeConexion(campo: "Cuándo", enFicha: "Cada lunes", enCalendario: "Cada martes"),
                          DiferenciaDeConexion(campo: "Hora", enFicha: "09:00", enCalendario: "11:30"),
                          DiferenciaDeConexion(campo: "Duración", enFicha: "30 min", enCalendario: "30 min")],
            ruta: VaultPath("1 · Dirección/Rutinas/Repaso semanal.md"),
            hacer: { "La ficha ya dice lo mismo que Calendario." }, noHacer: { "El evento vuelve a lo de la ficha." }),
                 TarjetaDeConexion.permiso(
            id: "permiso:calendarios", titulo: "The Last System no puede usar Calendario",
            texto: "Se lo quitaste en Ajustes del Sistema. Sin eso, tus rituales no se apuntan en Calendario ni se cuenta lo que tienes ocupado.",
            pasos: ["Abre Ajustes del Sistema.", "Ve a Privacidad y seguridad › Calendarios.", "Activa The Last System."],
            enlace: nil, detalleTecnico: "EKAuthorizationStatus.denied", origen: "calendario")],
                origen: "calendario")
        c.poner([TarjetaDeConexion.herramientas(
            id: "conexion-revisar:ghl:5b1e", programa: "GoHighLevel", conexion: "ghl",
            texto: "GoHighLevel trae 2 herramientas nuevas o cambiadas: están desactivadas hasta que las revises.",
            herramientas: [HerramientaDeLaTarjeta(nombre: "List appointments", descripcion: "Lists calendar appointments for a contact.",
                                                  cambiaCosas: false, motivo: "El programa dice que solo lee.", estado: "Nueva"),
                           HerramientaDeLaTarjeta(nombre: "Send SMS", descripcion: "Sends an SMS to a contact.",
                                                  cambiaCosas: true, motivo: "Su nombre dice que manda algo.", estado: "Cambiada")],
            activar: { "Activadas." }, dejar: { "Se quedan desactivadas." })], origen: "pasarela:ghl")
        #expect(c.pendientes.count == 3)
    }

    @Test("Buzón de un día, tarjetas de correo, de otro programa y de Calendario")
    func buzonYTarjetas() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        try BuzonTests.sembrar(e)
        await e.esperar({ e.sesion.resumen(de: VaultPath("Buzón/Correo 2026-10.md")) != nil })
        ConexionesEnDecisiones.de(e.sesion).huecos.correo = TarjetasConexionesTests.MailFalso()
        let (_, idCorreo) = try await MikaApoyo.borradorPendiente(e)
        let idExterna = try await accionExterna(e)
        tarjetas(e)

        func pantalla(_ nav: Navegacion) -> some View {
            ContenidoEmpresa(sesion: e.sesion, nav: nav).environment(e.entorno.model).environment(\.navegacion, nav)
        }
        for oscuro in [false, true] {
            try await capturar(pantalla(Navegacion(raiz: .carpeta(VaultPath("Buzón")))), ancho: 1360, alto: 1250, oscuro: oscuro,
                               nombre: "01-buzon-dia")
            let m = ModeloAprobacion(id: idCorreo, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
            await m.cargar()
            try await capturar(SensitiveConfirmSheet(modelo: m) { _ in }, ancho: 600, alto: 620, oscuro: oscuro, nombre: "02-tarjeta-correo")
            let x = ModeloAprobacion(id: idExterna, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
            await x.cargar()
            #expect(x.peticionExterna != nil)
            try await capturar(SensitiveConfirmSheet(modelo: x) { _ in }, ancho: 600, alto: 620, oscuro: oscuro, nombre: "04-accion-externa")
            try await capturar(pantalla(Navegacion(raiz: .decisiones)), ancho: 1360, alto: 1700, oscuro: oscuro,
                               nombre: "05-decisiones-conexiones")
        }
        // Aprobado: «Abierto en Mail» (una sola vez: después ya no está pendiente).
        let m = ModeloAprobacion(id: idCorreo, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
        await m.cargar()
        #expect(await m.aprobar())
        for oscuro in [false, true] {
            try await capturar(SensitiveConfirmSheet(modelo: m) { _ in }, ancho: 600, alto: 620, oscuro: oscuro,
                               nombre: "03-tarjeta-correo-abierto-en-mail")
        }
        #expect(FileManager.default.fileExists(atPath: destino.appendingPathComponent("01-buzon-dia-claro.png").path))
    }

    @Test("Relevo: explicación, vista previa, conflicto, confirmación, bloqueo y hecho (carpetas sintéticas)")
    func relevo() async throws {
        let s = try await RelevoUITests.Escenario()
        try await s.trabajar()
        let m = s.modelo()
        for oscuro in [false, true] {
            try await capturar(RelevoHoja(modelo: m), ancho: 720, alto: 780, oscuro: oscuro, nombre: "06-relevo-explicacion")
        }
        await m.preparar()
        #expect(m.fase == .vistaPrevia)
        for oscuro in [false, true] {
            try await capturar(RelevoHoja(modelo: m), ancho: 720, alto: 780, oscuro: oscuro, nombre: "07-relevo-vista-previa")
        }
        let c = try #require(m.vista?.conflictos.first)
        m.elegir(.quedarseConLaCopia, para: c.ruta)
        for oscuro in [false, true] {
            try await capturar(RelevoHoja(modelo: m, alto: 1180), ancho: 720, alto: 1180, oscuro: oscuro, nombre: "08-relevo-conflicto")
        }
        m.elegir(.quedarseConLaReal, para: c.ruta)
        m.escrito = RelevoUITests.Escenario.empresa
        for oscuro in [false, true] {
            try await capturar(RelevoHoja(modelo: m, alto: 1180), ancho: 720, alto: 1180, oscuro: oscuro, nombre: "09-relevo-confirmacion")
        }
        #expect(await m.pasar())
        for oscuro in [false, true] {
            try await capturar(RelevoHoja(modelo: m), ancho: 720, alto: 780, oscuro: oscuro, nombre: "11-relevo-hecho")
        }
        #expect(await m.deshacer())
        // Bloqueado: la otra aplicación tiene su cerrojo.
        let lock = try #require(CerrojoDelRelevo.cerrojosDelFork(real: s.real, rutaRegistrada: s.realEntry.ruta, estadoDelFork: s.estadoFork).first)
        try FileManager.default.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: lock.path, contents: Data())
        let fd = open(lock.path, O_RDWR)
        flock(fd, LOCK_EX | LOCK_NB)
        let b = s.modelo()
        await b.preparar()
        for oscuro in [false, true] {
            try await capturar(RelevoHoja(modelo: b), ancho: 720, alto: 780, oscuro: oscuro, nombre: "10-relevo-bloqueado")
        }
        flock(fd, LOCK_UN)
        close(fd)
        await s.limpiar()
    }
}
