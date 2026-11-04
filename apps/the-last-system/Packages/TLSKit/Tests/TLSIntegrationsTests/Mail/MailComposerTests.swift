import Foundation
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSIntegrations

/// El hueco de correo de `EjecutorDeAprobaciones` (F5): al aprobar, se pide abrir una redacción de Mail rellena con lo
/// aprobado. **Nunca se envía**: el redactor no tiene esa operación y el borrador queda «Abierto en Mail».
@Suite("Mail · MailComposer", .serialized)
struct MailComposerTests {
    /// Tarea de la persona en Ventas y un borrador de respuesta enlazado a ella y al correo; pedido por el Comercial.
    static func preparar(_ e: ApoyoCorreo.Empresa) async throws -> (tarea: VaultPath, borrador: VaultPath, aprobacion: String) {
        let foto = e.foto()
        let nota = try TaskStore(snapshot: foto, reloj: ApoyoCorreo.Empresa.reloj).crear(NuevaTarea(
            titulo: "Contestar a Lucía Romero", area: .ventas, responsable: "Manu", estado: .porHacer, autor: .persona("Manu")))
        #expect(try await e.bus.ejecutar(nota.plan).hecho)
        let (ruta, plan) = Borradores.plan(NuevoBorrador(
            accion: .enviarCorreo, area: .ventas, asunto: "Re: Precio de la declaración de la Renta",
            cuerpo: "Hola, Lucía:\n\nLa Renta cuesta 90 € más IVA.\n\nUn saludo,\nAsesoría Ribera",
            para: ["lucia.romero@correo.example"], enRespuestaA: ApoyoCorreo.enlace1, tarea: nota.ruta),
            layout: foto.layout, autor: .persona("Manu"))
        #expect(try await e.bus.ejecutar(plan).hecho)
        let a = Aprobaciones(bus: e.bus, autorizador: e.autorizador)
        let s = try await a.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial")
        #expect(s.estado == "aprobacion_requerida")
        return (nota.ruta, ruta, try #require(s.id))
    }

    @Test("Aprobar un correo pide abrir la redacción con lo aprobado (nunca enviarla); queda «Abierto en Mail» y la Actividad lo anota")
    func aprobarAbreLaRedaccion() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let (tarea, borrador, id) = try await Self.preparar(e)
            let redactor = RedactorFalso()
            let aprobaciones = Aprobaciones(bus: e.bus, autorizador: e.autorizador,
                                            ejecutor: EjecutorDeAprobaciones(correo: MailComposer(redactor: redactor,
                                                                                                    reloj: { _ in ApoyoCorreo.Empresa.reloj })))
            let r = try await aprobaciones.aprobar(id, autor: .persona("Manu"))
            #expect(r == .abiertoEnMail(borrador))
            #expect(r.texto.contains("pulsa Enviar tú"))
            #expect(r.abrir == nil, "Mail ya está abierto: la app no abre el borrador encima")
            // Lo que se pidió abrir: exactamente lo aprobado, en respuesta al correo.
            #expect(redactor.abiertas == [RedaccionDeCorreo(
                para: ["lucia.romero@correo.example"], asunto: "Re: Precio de la declaración de la Renta",
                cuerpo: "Hola, Lucía:\n\nLa Renta cuesta 90 € más IVA.\n\nUn saludo,\nAsesoría Ribera",
                enRespuestaA: "triaje-1.renta@correo.example")])
            // El espejo del borrador y la Actividad de su tarea.
            let textoB = try #require(e.texto(borrador.raw))
            let b = try #require(Borrador.leer(borrador, texto: textoB, layout: e.foto().layout))
            #expect(b.estado == .abiertoEnMail)
            let actividad = try #require(e.texto(tarea.raw))
            #expect(actividad.contains("### 2026-10-19 08:30 · Manu"))
            #expect(actividad.contains("Abrí en Mail el correo «Re: Precio de la declaración de la Renta»"))
            #expect(actividad.contains("\"tipo\":\"abierto_en_mail\""))
            // Ejecutada, sin rastro de «Enviado».
            let ap = try #require(try aprobaciones.store.aprobacion(id))
            #expect(ap.estado == .ejecutada)
            #expect(b.estado != .enviado)
        }
    }

    @Test("Con la Automatización denegada no se abre nada, el borrador no cambia y el error lo explica")
    func denegadaNoCambiaNada() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let (_, borrador, id) = try await Self.preparar(e)
            let jxa = EjecutorJXAFalso { _ in
                ResultadoJXA(salida: "", errores: "Not authorized to send Apple events to Mail. (-1743)", estado: 1)
            }
            let aprobaciones = Aprobaciones(bus: e.bus, autorizador: e.autorizador,
                                            ejecutor: EjecutorDeAprobaciones(correo: MailComposer(redactor: RedactorDeMailJXA(ejecutor: jxa))))
            await #expect(throws: ErrorDeMail.automatizacionDenegada) { _ = try await aprobaciones.aprobar(id, autor: .persona("Manu")) }
            #expect(jxa.llamadas.count == 1)
            #expect(jxa.llamadas.first?.guion == GuionesDeMail.redactar)
            #expect(ErrorDeMail.automatizacionDenegada.errorDescription?.contains("No se ha enviado nada") == true)
            let textoB = try #require(e.texto(borrador.raw))
            let b = try #require(Borrador.leer(borrador, texto: textoB, layout: e.foto().layout))
            #expect(b.estado == .pendiente)
        }
    }

    @Test("El redactor real manda a Mail lo aprobado como argumento (nunca pegado en el guion) y espera la ventana abierta")
    func redactorJXA() async throws {
        let jxa = EjecutorJXAFalso { _ in ResultadoJXA(salida: #"{"estado":"abierta"}"#) }
        let r = RedaccionDeCorreo(para: ["a@example.com"], asunto: "Hola \"y\" adiós');", cuerpo: "Línea 1\nLínea 2", enRespuestaA: "x@y")
        try await RedactorDeMailJXA(ejecutor: jxa).abrirRedaccion(r)
        let l = try #require(jxa.llamadas.first)
        #expect(l.guion == GuionesDeMail.redactar)
        #expect(!l.guion.contains("adiós"))
        let enviado = try JSONDecoder().decode(RedaccionDeCorreo.self, from: Data(try #require(l.argumentos.first).utf8))
        #expect(enviado == r)
    }
}
