import Foundation
import Testing
@testable import TLSCore
@testable import TLSIntegrations

/// Permisos del sistema con un consultor falso (nunca se pregunta a TCC en las pruebas).
@Suite("Permisos del sistema")
struct PermisosTests {
    @Test("Nunca se pide un permiso sin enseñar antes su explicación (ni con la de otro, ni dos veces con la misma)")
    func explicacionAntes() async throws {
        let c = ConsultorFalso([:])
        let puerta = PuertaDePermisos(consultor: c)
        let otra = PuertaDePermisos(consultor: c)
        // Sin explicación: no hay forma de fabricar una «vista» fuera de la puerta; con la de otro permiso u otra puerta, no vale.
        let (_, vistaCal) = await puerta.explicar(.calendarios)
        await #expect(throws: ErrorDePermiso.sinExplicacion(.automatizacionMail)) {
            _ = try await puerta.pedir(.automatizacionMail, tras: vistaCal)
        }
        let (_, deOtra) = await otra.explicar(.automatizacionMail)
        await #expect(throws: ErrorDePermiso.sinExplicacion(.automatizacionMail)) {
            _ = try await puerta.pedir(.automatizacionMail, tras: deOtra)
        }
        #expect(c.pedidos.isEmpty)
        // Con la suya: se pide una vez.
        let (exp, vista) = await puerta.explicar(.automatizacionMail)
        #expect(exp.titulo.contains("correo") && exp.nunca.contains { $0.contains("Enviar nada") })
        #expect(try await puerta.pedir(.automatizacionMail, tras: vista) == .concedido)
        #expect(c.pedidos == [.automatizacionMail])
        // La misma explicación no sirve para otra petición.
        await #expect(throws: ErrorDePermiso.sinExplicacion(.automatizacionMail)) {
            _ = try await puerta.pedir(.automatizacionMail, tras: vista)
        }
        #expect(await puerta.peticiones == [.automatizacionMail])
    }

    @Test("Denegado: no se vuelve a preguntar; se enseña la recuperación con el enlace a Ajustes del Sistema")
    func denegadoRecupera() async throws {
        let c = ConsultorFalso([.automatizacionMail: .denegado, .calendarios: .restringido, .notificaciones: .concedido])
        let puerta = PuertaDePermisos(consultor: c)
        let (_, vista) = await puerta.explicar(.automatizacionMail)
        #expect(try await puerta.pedir(.automatizacionMail, tras: vista) == .denegado)
        #expect(c.pedidos.isEmpty)
        guard case .recuperar(let r) = await puerta.situacion(.automatizacionMail) else { Issue.record("Esperaba recuperación"); return }
        #expect(r.enlace.scheme == "x-apple.systempreferences")
        #expect(r.pasos.contains { $0.contains("Automatización") })
        guard case .recuperar = await puerta.situacion(.calendarios) else { Issue.record("Restringido también se recupera"); return }
        #expect(await puerta.situacion(.notificaciones) == .listo)
        #expect(PuertaDePermisos.situacion(.calendarios, estado: .sinPreguntar) == .explicar(PermisoDelSistema.calendarios.explicacion))
        let estados = await puerta.estados()
        #expect(estados[.automatizacionMail] == .denegado && estados.count == 3)
    }

    @Test("Textos en lenguaje llano y sin jerga; cada permiso con su panel de Ajustes")
    func textos() {
        for p in PermisoDelSistema.allCases {
            let e = p.explicacion, r = p.recuperacion
            let todo = [e.titulo, e.para, e.queVeras, e.boton, r.titulo, r.texto, r.boton, p.titulo, EstadoDePermiso.denegado.texto]
                + e.hace + e.nunca + r.pasos
            for t in todo { #expect(jerga(t).isEmpty, "«\(t)» → \(jerga(t))") }
            #expect(p.enlaceAjustes.scheme == "x-apple.systempreferences")
            #expect(r.permiso == p && e.permiso == p)
        }
        #expect(PermisoDelSistema.calendarios.explicacion.nunca.contains { $0.contains("Invitar") })
    }

    @Test("Códigos de Apple Events: concedido, denegado, sin preguntar y Mail cerrado")
    func codigos() {
        #expect(ConsultorDePermisosDelSistema.automatizacion(status: 0) == .concedido)
        #expect(ConsultorDePermisosDelSistema.automatizacion(status: -1743) == .denegado)
        #expect(ConsultorDePermisosDelSistema.automatizacion(status: -1744) == .sinPreguntar)
        #expect(ConsultorDePermisosDelSistema.automatizacion(status: -600) == .desconocido)
        #expect(ResultadoJXA(salida: "", errores: "Not authorized to send Apple events to Mail. (-1743)", estado: 1).automatizacionDenegada)
        #expect(!ResultadoJXA(salida: "{}", errores: "", estado: 0).automatizacionDenegada)
    }
}
