import Foundation
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSIntegrations

/// F5 · corrector (revisión de experiencia, P1-1): el Cartero prepara respuestas en borrador pero no pide acciones
/// externas. Decisiones las prepara para aprobar en su nombre (`Aprobaciones.pedirParaAprobar`), con las mismas
/// comprobaciones, y al aprobar se abre la redacción en Mail: **nunca se envía**.
@Suite("Mail · correo del Cartero para aprobar", .serialized)
struct CorreoDelCarteroParaAprobarTests {
    @Test("Un correo del Cartero sin petición se prepara para aprobar y, al aprobarlo, se abre en Mail sin enviarse")
    func carteroAbreMail() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let foto = e.foto()
            let nuevo = NuevoBorrador(accion: .enviarCorreo, area: .ventas, asunto: "Re: Precio de la declaración de la Renta",
                                      cuerpo: "Hola, Lucía:\n\nLa Renta cuesta 90 € más IVA.", para: ["lucia.romero@correo.example"],
                                      enRespuestaA: ApoyoCorreo.enlace1)
            let ruta = Borradores.ruta(slug: nuevo.asunto, area: .ventas, layout: foto.layout)
            // Como lo deja el Cartero (`creado_por: agente:cartero`); se escribe aquí como persona para no depender de su sesión.
            let r = try await e.bus.ejecutar(WritePlan(autor: .persona("Manu"), descripcion: "borrador del Cartero",
                                                       ops: [.create(ruta, text: Borradores.texto(nuevo, creadoPor: .agente("cartero")))]))
            #expect(r.hecho)
            let redactor = RedactorFalso()
            let aprobaciones = Aprobaciones(bus: e.bus, autorizador: e.autorizador,
                                            ejecutor: EjecutorDeAprobaciones(correo: MailComposer(redactor: redactor,
                                                                                                    reloj: { _ in ApoyoCorreo.Empresa.reloj })))
            // Un asistente no puede: solo la persona.
            await #expect(throws: (any Error).self) { _ = try await aprobaciones.pedirParaAprobar(borrador: ruta, autor: .agente("cartero")) }
            let id = try await aprobaciones.pedirParaAprobar(borrador: ruta, autor: .persona("Manu"))
            // Pedirlo otra vez devuelve la misma (no se duplica).
            #expect(try await aprobaciones.pedirParaAprobar(borrador: ruta, autor: .persona("Manu")) == id)
            let ap = try #require(try aprobaciones.store.aprobacion(id))
            #expect(ap.agente == "cartero" && ap.accion == .enviarCorreo)
            let res = try await aprobaciones.aprobar(id, autor: .persona("Manu"))
            #expect(res == .abiertoEnMail(ruta))
            #expect(redactor.abiertas.count == 1 && redactor.abiertas.first?.para == ["lucia.romero@correo.example"])
        }
    }

    @Test("Un borrador escrito a mano (sin asistente) no se prepara: se abre y se envía desde Mail")
    func manualNoSePrepara() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let foto = e.foto()
            let (ruta, plan) = Borradores.plan(NuevoBorrador(accion: .enviarCorreo, area: .ventas, asunto: "Hola", cuerpo: "Texto",
                                                             para: ["a@correo.example"]), layout: foto.layout, autor: .persona("Manu"))
            let hecho = try await e.bus.ejecutar(plan).hecho
            #expect(hecho)
            let aprobaciones = Aprobaciones(bus: e.bus, autorizador: e.autorizador)
            await #expect(throws: (any Error).self) { _ = try await aprobaciones.pedirParaAprobar(borrador: ruta, autor: .persona("Manu")) }
        }
    }

    @Test("Nombres en llano de las herramientas y sus datos (P1-2, P2-5)")
    func nombresLlanos() {
        #expect(NombresLlanos.accion("send_sms") == "Mandar un SMS")
        #expect(NombresLlanos.accion("send_sms", programa: "GoHighLevel") == "Mandar un SMS desde GoHighLevel")
        #expect(NombresLlanos.accion("contacts_list") == "Ver contactos")
        #expect(NombresLlanos.accion("contact_update") == "Cambiar un contacto")
        #expect(NombresLlanos.accion("createContact") == "Crear un contacto")
        #expect(NombresLlanos.accion("get_contact") == "Ver un contacto")
        #expect(NombresLlanos.accion("email") == "Mandar un correo")
        #expect(NombresLlanos.dato("contactId") == "Contacto")
        #expect(NombresLlanos.dato("message") == "Mensaje")
        #expect(NombresLlanos.dato("first_name") == "Nombre")
    }
}
