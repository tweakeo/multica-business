import Foundation
import Testing
import TLSAgents
import TLSCore
@testable import TLSUI

/// Las tarjetas nuevas de Decisiones de F5 (buzon-relevo): borrador de correo que se abre en Mail (nunca se envía),
/// «¿Actualizo la ficha?» con la diferencia, herramientas nuevas por revisar, permiso denegado y la acción sensible en
/// otro programa con literalmente qué se manda y a quién. Ribera en un temporal; ni Mail ni Calendario de verdad: el
/// correo es un doble que solo dice «abierto».
@Suite("Decisiones · tarjetas de las conexiones", .serialized)
@MainActor
struct TarjetasConexionesTests {
    /// Doble del `MailComposer`: apunta lo que le piden abrir y devuelve «Abierto en Mail». No hay forma de enviar.
    final class MailFalso: ProtocoloDeCorreo, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var abiertos: [String] = []

        func preparar(_ a: AprobacionEnCurso) async throws -> ResultadoDeAprobacion {
            lock.withLock { abiertos.append(a.aprobacion.carga.asunto ?? "") }
            guard let r = a.aprobacion.ruta else { throw ErrorDeGobierno.borradorNoValido("sin borrador") }
            return .abiertoEnMail(r)
        }
    }

    @Test("Con Mail conectado, aprobar un correo dice «Se abrirá en Mail para que tú lo envíes» y queda «Abierto en Mail»")
    func correoAbiertoEnMail() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let huecos = ConexionesEnDecisiones.de(e.sesion).huecos
        let mail = MailFalso()
        huecos.correo = mail
        let (ruta, id) = try await MikaApoyo.borradorPendiente(e)
        let m = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor) { await e.asistentes.cambio() }
        await m.cargar()
        #expect(m.abreMail)
        #expect(m.peticionExterna == nil)
        #expect(await m.aprobar())
        guard case .abiertoEnMail(let r)? = m.resultado else {
            Issue.record("Debía quedar abierto en Mail: \(String(describing: m.resultado))")
            return
        }
        #expect(r == ruta)
        #expect(m.resultado?.texto == "Abierto en Mail: revísalo y pulsa Enviar tú.")
        #expect(mail.abiertos == ["Seguimiento de la propuesta de la renta"], "se pide abrir una vez, con lo aprobado")
        #expect(e.texto(ruta.raw).contains("estado: Abierto en Mail"))
        // Sin Mail conectado: lo de F4 (queda listo para enviar desde el borrador).
        huecos.correo = nil
        let (_, id2) = try await MikaApoyo.borradorPendiente(e, slug: "otro-seguimiento", asunto: "Otro seguimiento")
        let m2 = ModeloAprobacion(id: id2, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
        await m2.cargar()
        #expect(!m2.abreMail)
        #expect(await m2.aprobar())
        guard case .listoParaEnviar? = m2.resultado else {
            Issue.record("Sin Mail, listo para enviar: \(String(describing: m2.resultado))")
            return
        }
    }

    @Test("Una acción en otro programa se enseña literalmente: a quién, qué hace y con qué datos (sin huellas)")
    func peticionExterna() throws {
        let json = #"{"argumentos":{"contactId":"c-123","importe":120.5,"mensaje":"Hola, te confirmo la cita del jueves.","urgente":true},"herramienta":"ext_ghl_send_message","huella":"9f2c0d"}"#
        let p = try #require(PeticionExternaLegible.leer(json))
        #expect(p.herramienta == "ext_ghl_send_message" && p.conexion == "ghl")
        #expect(p.accion == "Mandar un mensaje")  // F5 · corrector (P1-2): en llano
        #expect(p.datos.map(\.clave) == ["contactId", "importe", "mensaje", "urgente"])
        #expect(p.datos.map(\.valor) == ["c-123", "120.5", "Hola, te confirmo la cita del jueves.", "sí"])
        #expect(!p.datos.contains { $0.valor.contains("9f2c0d") }, "la huella no se enseña")
        // En un bloque de código (si alguien lo corrigió así) también; lo que no es una petición, no.
        #expect(PeticionExternaLegible.leer("```json\n\(json)\n```")?.accion == "Mandar un mensaje")
        #expect(PeticionExternaLegible.leer("Hola") == nil)
        #expect(PeticionExternaLegible.leer(#"{"herramienta":"tls_crear_tarea"}"#) == nil)
        #expect(PeticionExternaLegible.legible("createContactNote") == "Create contact note")
    }

    @Test("«¿Actualizo la ficha?», herramientas nuevas y permiso denegado: se ponen por origen, se resuelven y no vuelven")
    func tarjetas() async throws {
        let c = ConexionesEnDecisiones()
        let hechas = Contador()
        let cal = TarjetaDeConexion.calendario(
            id: "calendario:tls://rutina/repaso", titulo: "Cambiaste «Repaso semanal» en Calendario",
            texto: "Lo moviste en Calendario. La ficha dice otra cosa.",
            diferencias: [DiferenciaDeConexion(campo: "Hora", enFicha: "09:00", enCalendario: "11:30"),
                          DiferenciaDeConexion(campo: "Cuándo", enFicha: "Cada lunes", enCalendario: "Cada martes")],
            ruta: VaultPath("1 · Dirección/Rutinas/Repaso semanal.md"),
            hacer: { await hechas.sumar(); return "La ficha ya dice lo mismo que Calendario." },
            noHacer: { "El evento vuelve a lo de la ficha." })
        #expect(cal.pregunta == "¿Actualizo la ficha?")
        #expect(cal.principal.titulo == "Actualizar la ficha" && cal.secundaria?.titulo == "Dejar la ficha como está")
        let her = TarjetaDeConexion.herramientas(
            id: "conexion-revisar:ghl:abc", programa: "GoHighLevel", conexion: "ghl",
            texto: "GoHighLevel trae 2 herramientas nuevas o cambiadas: están desactivadas hasta que las revises.",
            herramientas: [HerramientaDeLaTarjeta(nombre: "Listar citas", cambiaCosas: false, motivo: "El programa dice que solo lee.", estado: "Nueva"),
                           HerramientaDeLaTarjeta(nombre: "Enviar SMS", cambiaCosas: true, motivo: "Su nombre dice que manda algo.", estado: "Nueva")],
            activar: { "Activadas." }, dejar: { "Se quedan desactivadas." })
        #expect(her.titulo == "Revisar herramientas nuevas de GoHighLevel" && her.pregunta == "¿Las activo?")
        let per = TarjetaDeConexion.permiso(
            id: "permiso:automatizacionMail", titulo: "The Last System no puede leer Mail",
            texto: "Lo desactivaste en Ajustes del Sistema. Sin eso, el Cartero no ve el correo.",
            pasos: ["Abre Ajustes del Sistema", "Privacidad y seguridad › Automatización", "Activa Mail bajo The Last System"],
            enlace: nil, origen: "mail")
        c.poner([cal], origen: "calendario")
        c.poner([her], origen: "pasarela:ghl")
        c.poner([per, cal], origen: "mail")   // la de Calendario no es de «mail»: no entra por ahí
        #expect(c.pendientes.map(\.clase) == [.permiso, .calendario, .herramientas])
        // Actualizar la ficha: se hace y sale de la bandeja con lo que se dijo; si la integración la repite, no vuelve.
        #expect(await c.pulsar(cal))
        #expect(await hechas.n == 1)
        #expect(c.hechas[cal.id] == "La ficha ya dice lo mismo que Calendario.")
        #expect(!c.pendientes.contains { $0.id == cal.id })
        c.poner([cal], origen: "calendario")
        #expect(!c.pendientes.contains { $0.id == cal.id })
        // El permiso sigue a la vista hasta que la app vea el permiso concedido (la integración la quita).
        #expect(await c.pulsar(per))
        #expect(c.pendientes.contains { $0.id == per.id } && c.avisos[per.id] != nil)
        c.poner([], origen: "mail")
        #expect(!c.pendientes.contains { $0.id == per.id })
        // Dejarlas desactivadas.
        #expect(await c.pulsar(her, principal: false))
        #expect(c.hechas[her.id] == "Se quedan desactivadas." && c.pendientes.isEmpty)
        // Un fallo se enseña y la tarjeta se queda.
        let mal = TarjetaDeConexion.calendario(id: "calendario:x", titulo: "X", texto: "Y", diferencias: [], ruta: nil,
                                               hacer: { throw ErrorDeGobierno.borradorNoValido("La ficha cambió mientras tanto.") })
        c.poner([mal], origen: "calendario")
        #expect(await c.pulsar(mal) == false)
        #expect(c.errores[mal.id] == "La ficha cambió mientras tanto." && c.pendientes.contains { $0.id == mal.id })
        #expect(mal.secundaria == nil)
    }

    @Test("Las tarjetas son de su empresa: otra sesión no las ve")
    func porSesion() async throws {
        let a = try await MikaApoyo.ribera()
        defer { a.cerrar() }
        let b = try await MikaApoyo.ribera()
        defer { b.cerrar() }
        let t = TarjetaDeConexion.permiso(id: "permiso:calendarios", titulo: "T", texto: "X", pasos: [], enlace: nil, origen: "calendario")
        ConexionesEnDecisiones.de(a.sesion).poner([t], origen: "calendario")
        #expect(ConexionesEnDecisiones.de(a.sesion).pendientes.count == 1)
        #expect(ConexionesEnDecisiones.de(b.sesion).pendientes.isEmpty)
        #expect(ConexionesEnDecisiones.de(a.sesion) === ConexionesEnDecisiones.de(a.sesion))
    }

    actor Contador {
        var n = 0
        func sumar() { n += 1 }
    }
}
