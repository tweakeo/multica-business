import Foundation
import Testing
import TLSCore
import TLSUI
@testable import TLSOnboarding

/// F5 · rol conexiones: el paso 7 «Conectar» es la pantalla Conexiones en modo paso. Cada elección es la respuesta a
/// su pregunta; Mail se conecta con la explicación antes del aviso (servicios en memoria, nada real); Claude Code sale
/// de la comprobación del paso.
@Suite("Puesta en marcha · paso 7 con la pantalla Conexiones", .serialized)
@MainActor
struct PasoConectarConexionesTests {
    func enConectar(_ b: Banco) async -> ModeloPuesta {
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("cero"))
        m.actualizar { $0.ir(a: "conectar") }
        return m
    }

    @Test("«Ahora no» y «Conectar» quedan como respuestas del paso (también Avisos y la ventana cerrada)")
    func respuestas() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = await enConectar(b)
        #expect(m.pantalla?.id == "conectar")
        let c = PasoConectar.conexiones(m, servicios: .some(nil))
        #expect(c.modo.esPaso && !c.hayServicios)
        await c.cargar()
        await c.ahoraNo(.mail)
        await c.encender(.banco)
        await c.ahoraNo(.ventanaCerrada)
        #expect(m.respuesta(.conexion(.mail))?.valor.opcion == "ahora-no")
        #expect(m.respuesta(.conexion(.banco))?.valor.opcion == "conectar")
        #expect(m.respuesta(.conexion(.ventanaCerrada))?.valor.siNo == false)
        #expect(c.eleccion(.mail) == false && c.eleccion(.banco) == true)
        #expect(c.estado(.mail) == .ahoraNo)
        #expect(!PresenciaDeLaApp.trabajaConLaVentanaCerrada, "apagado de serie")
    }

    @Test("Con servicios, Mail se conecta en el mismo paso: explicación, aviso, cuenta y Cartero; la respuesta es «conectar»")
    func mailEnElPaso() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = await enConectar(b)
        let s = ServiciosDeConexionesEnMemoria()
        let c = PasoConectar.conexiones(m, servicios: .some(s))
        await c.cargar()
        await c.conectarMail()
        guard case .explicacion = c.faseMail else { Issue.record("sin explicación"); return }
        #expect(await s.peticiones.isEmpty)
        await c.continuarMail()
        await c.terminarMail()
        #expect(c.estado(.mail) == .conectado)
        #expect(await s.activaciones == [true])
        #expect(m.respuesta(.conexion(.mail))?.valor.opcion == "conectar")
    }

    @Test("Claude Code: lo que dice la comprobación del paso, en la fila de Conexiones")
    func claude() async {
        let b = Banco()
        defer { b.limpiar() }
        let m = await enConectar(b)
        let c = PasoConectar.conexiones(m, servicios: .some(nil))
        await m.detectarClaude()
        #expect(c.estado(.claude) == .conectado)
        #expect(c.detalle(.claude).contains("Claude Code está en este Mac"))
        await c.claude.probar()
        #expect(m.claude == .probado(ok: true, texto: "Funciona."))
        #expect(PasoConectar.info(.noEncontrado).estado == .ahoraNo)
        #expect(PasoConectar.info(.probado(ok: false, texto: "No contestó.")).estado == .error("No contestó."))
    }
}
