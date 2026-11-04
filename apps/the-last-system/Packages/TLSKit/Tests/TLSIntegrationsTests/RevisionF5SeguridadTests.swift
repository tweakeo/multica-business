import Foundation
import MCP
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSIntegrations
@testable import TLSMCPHost
import TLSMCPShared

/// Revisión adversarial de seguridad y privacidad de F5 (rol revisión-seguridad): Mail y Calendario.
/// Nada real: `osascript` falso (`EjecutorJXAFalso`), calendario en memoria (`AlmacenEnMemoria`), nombres neutros.
/// Lo que hoy falla va en `withKnownIssue` con la referencia del hallazgo (S-…); al corregirlo, se quita el envoltorio.
@Suite("Revisión F5 · seguridad y privacidad (Mail y Calendario)", .serialized)
struct RevisionF5SeguridadTests {
    // MARK: S1 · El cursor pierde correos que Mail descarga tarde o fuera de orden

    /// El guion pide `dateReceived > cursor` y la app vuelve a filtrar `fecha > cursor`; el cursor salta al más nuevo
    /// guardado. Mail sincroniza lo más reciente primero (al despertar el Mac, al abrir Mail, en una cuenta IMAP lenta):
    /// si en una ronda solo ha bajado el de las 10:30, los de las 09:00 y 09:15 que bajan después tienen una fecha
    /// anterior al cursor y **no se leen nunca** (ni el triaje del Cartero los ve).
    @Test("S1 · Un correo que Mail baja después de otro más nuevo se pierde para siempre")
    func correoTardioSePierde() async throws {
        let estado = ApoyoCorreo.temporal("rev-s1")
        defer { try? FileManager.default.removeItem(at: estado) }
        let almacen = AlmacenDeCorreo(estado: estado, zona: ApoyoCorreo.madrid)
        let cursor = try CursorDeCorreo(estado: estado)
        // Lo que Mail tiene en la bandeja en cada ronda (la segunda, ya con los que bajaron tarde).
        let nuevo = EjecutorJXAFalso.crudo("nuevo@correo.example", ApoyoCorreo.fecha(19, 10, 30))
        let tarde1 = EjecutorJXAFalso.crudo("tarde-1@correo.example", ApoyoCorreo.fecha(19, 9, 0), asunto: "Requerimiento")
        let tarde2 = EjecutorJXAFalso.crudo("tarde-2@correo.example", ApoyoCorreo.fecha(19, 9, 15))
        let bandeja = BandejaDePrueba()
        bandeja.mensajes = [nuevo]
        // Se porta como el guion: `dateReceived > desde`, en orden, 50 como mucho.
        let ejecutor = EjecutorJXAFalso { l in
            let desde = (EjecutorJXAFalso.parametros(l)["desde"] as? Double) ?? 0
            let lista = bandeja.lock.withLock { bandeja.mensajes }
                .filter { ($0["fecha"] as? Double ?? 0) > desde }
                .sorted { ($0["fecha"] as? Double ?? 0) < ($1["fecha"] as? Double ?? 0) }
            return EjecutorJXAFalso.salida(Array(lista.prefix(50)))
        }
        let lector = LectorDeCorreo(ejecutor: ejecutor, almacen: almacen, cursor: cursor,
                                    ajustes: { AjustesDeCorreo(cuenta: "Asesoría") }, ahora: { ApoyoCorreo.fecha(19, 10, 45) })
        #expect(await lector.leer() == .leidos(nuevos: 1, mas: false))
        // Mail termina de bajar los anteriores.
        bandeja.lock.withLock { bandeja.mensajes = [tarde1, tarde2, nuevo] }
        _ = await lector.leer()
        let guardados = await almacen.mensajes(desde: .distantPast, hasta: .distantFuture).map(\.id)
        // Corregido (S1): se relee la ventana cursor − 48 h y lo ya guardado se descarta por Message-ID.
        #expect(Set(guardados) == ["nuevo@correo.example", "tarde-1@correo.example", "tarde-2@correo.example"])
    }

    // MARK: S2 · Empate en el corte de 50

    /// Con 51 correos nuevos y el 50.º y el 51.º con el mismo `dateReceived` (Mail guarda segundos: llegadas en bloque,
    /// importaciones, reglas de reenvío), el cursor queda en esa fecha y la siguiente ronda pide `> cursor`: el 51.º no
    /// se lee nunca, aunque la propia lectura dijo «quedan más».
    @Test("S2 · El correo que empata en fecha con el último del lote de 50 se pierde")
    func empateEnElCorteSePierde() async throws {
        let estado = ApoyoCorreo.temporal("rev-s2")
        defer { try? FileManager.default.removeItem(at: estado) }
        let almacen = AlmacenDeCorreo(estado: estado, zona: ApoyoCorreo.madrid)
        let cursor = try CursorDeCorreo(estado: estado)
        var todos = (0..<49).map { i in
            EjecutorJXAFalso.crudo("c\(i)@correo.example", ApoyoCorreo.fecha(19, 7).addingTimeInterval(Double(i) * 60))
        }
        let mismaHora = ApoyoCorreo.fecha(19, 8, 10)
        todos.append(EjecutorJXAFalso.crudo("empate-a@correo.example", mismaHora))
        todos.append(EjecutorJXAFalso.crudo("empate-b@correo.example", mismaHora))
        let bandeja = BandejaDePrueba()
        bandeja.mensajes = todos
        let ejecutor = EjecutorJXAFalso { l in
            let p = EjecutorJXAFalso.parametros(l)
            let desde = (p["desde"] as? Double) ?? 0
            // Como el guion: salta los `vistos` antes de cortar en 50.
            let vistos = Set((p["vistos"] as? [String]) ?? [])
            let nuevos = bandeja.lock.withLock { bandeja.mensajes }
                .filter { ($0["fecha"] as? Double ?? 0) > desde && !vistos.contains($0["id"] as? String ?? "") }
            return EjecutorJXAFalso.salida(Array(nuevos.prefix(50)), mas: nuevos.count > 50)
        }
        let lector = LectorDeCorreo(ejecutor: ejecutor, almacen: almacen, cursor: cursor,
                                    ajustes: { AjustesDeCorreo(cuenta: "Asesoría") }, ahora: { ApoyoCorreo.fecha(19, 8, 30) })
        #expect(await lector.leer() == .leidos(nuevos: 50, mas: true))
        _ = await lector.leer()
        let guardados = await almacen.mensajes(desde: .distantPast, hasta: .distantFuture)
        // Corregido (S2): la ventana con margen vuelve a pedir esa hora y el 51.º entra.
        #expect(guardados.count == 51)
    }

    // MARK: S3 · Un remitente privado añadido después no protege lo ya recogido

    /// Lo privado se aplica solo al guardar (`FiltroDePrivacidad` en `LectorDeCorreo`). `tls_correo_pendiente` lee el
    /// almacén tal cual y nunca vuelve a mirar `ajustes.json`; guardar los ajustes tampoco limpia lo ya guardado. Si Manu
    /// marca como privado un remitente cuyo correo ya se recogió (lo normal: lo ve llegar y entonces lo marca), el
    /// Cartero sigue recibiendo su asunto, su texto y sus adjuntos durante toda la ventana del triaje, y el texto sigue
    /// en `correo/AAAA-MM-DD.jsonl`.
    @Test("S3 · Marcar un remitente como privado después no impide que su correo llegue al Cartero")
    func privadoAnadidoDespues() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let estado = e.base.appendingPathComponent("estado-correo", isDirectory: true)
            let almacen = AlmacenDeCorreo(estado: estado, zona: ApoyoCorreo.madrid)
            let crudo = EjecutorJXAFalso.crudo("consulta-1@expediente.example", ApoyoCorreo.fecha(19, 8, 0),
                                               de: "Consulta <consulta@expediente.example>", asunto: "Resultados de la prueba",
                                               texto: "Contenido del expediente privado de prueba.")
            let bandeja = BandejaDePrueba()
            bandeja.mensajes = [crudo]
            let ejecutor = EjecutorJXAFalso { _ in EjecutorJXAFalso.salida(bandeja.lock.withLock { bandeja.mensajes }) }
            try AjustesDeCorreo(cuenta: "Asesoría").guardar(estado)
            let lector = LectorDeCorreo(ejecutor: ejecutor, almacen: almacen, cursor: try CursorDeCorreo(estado: estado),
                                        ajustes: { AjustesDeCorreo.leer(estado) }, ahora: { ApoyoCorreo.fecha(19, 8, 15) })
            #expect(await lector.leer() == .leidos(nuevos: 1, mas: false))
            // Manu lo marca como privado (como lo guarda la pantalla Conexiones).
            try AjustesDeCorreo(cuenta: "Asesoría",
                                privados: [RemitentePrivado(patron: "expediente.example", etiqueta: "Expediente privado")]).guardar(estado)
            let r = await e.servidor(correo: almacen).llamar("tls_correo_pendiente", argumentos: [:], contexto: ApoyoCorreo.cartero())
            #expect(!r.esError, "\(r.texto)")
            // Corregido (S3): lo privado se vuelve a aplicar al leer y lo guardado se depura al guardar los ajustes.
            #expect(!r.texto.contains("Resultados de la prueba"))
            #expect(!r.texto.contains("Contenido del expediente"))
            #expect(!r.texto.contains("consulta@expediente.example"))
            let enDisco = try FileManager.default.contentsOfDirectory(at: almacen.carpeta, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }.joined()
            #expect(!enDisco.contains("Contenido del expediente") && !enDisco.contains("Resultados de la prueba"))
        }
    }

    // MARK: S4 · Responder en el hilo añade un destinatario que no se aprobó

    /// `GuionesDeMail.redactar`, con `enRespuestaA`, usa `reply` de Mail: la redacción nace dirigida al remitente del
    /// original y el guion solo **añade** los aprobados que falten; nunca quita los que sobran. Si lo aprobado va a otra
    /// persona (el Cartero prepara «escribir a cliente» enlazado al correo de un proveedor, o Manu cambia el «Para» al
    /// aprobar), la ventana que se abre lleva también al remitente original. No se envía solo, pero ya no es «exactamente
    /// lo aprobado». (Comprobado leyendo el guion: las pruebas no pueden automatizar Mail.)
    @Test("S4 · La redacción en respuesta deja solo a los destinatarios aprobados")
    func respuestaConDestinatarioNoAprobado() {
        let g = GuionesDeMail.redactar
        // Corregido: solo se responde en el hilo si la respuesta (Reply-To o remitente) es uno de los aprobados, la
        // respuesta nace oculta y solo se enseña si sus destinatarios son exactamente los aprobados; si no, redacción nueva.
        #expect(g.contains("reply({openingWindow: false, replyToAll: false})"))
        #expect(g.contains("aprobados.indexOf(responderA) >= 0"))
        #expect(g.contains("r.toRecipients().length === aprobados.length && soloAprobados(r)"))
        // Ya no se limita a añadir los que faltan a una respuesta que puede llevar a otra persona.
        #expect(!g.contains("if (ya.indexOf(String(p.para[i]).toLowerCase()) < 0)"))
    }

    // MARK: S5 · Un evento que movió Manu a otro calendario se borra o se mueve desde allí

    /// `leer(fila…)` busca primero por identificador en **cualquier** calendario. Si Manu movió el ritual a otro calendario
    /// (por ejemplo uno compartido con la familia o con el equipo, sin invitados), al retirar la ficha la app lo borra de
    /// ese calendario (y el borrado llega a todos los que lo comparten); si cambia la ficha, lo vuelve a mover a «The
    /// Last System». La app solo debería tocar lo que está en su calendario.
    @Test("S5 · Retirar la ficha no borra un evento que ya está en otro calendario")
    func eventoMovidoAOtroCalendario() async throws {
        let carpeta = try CarpetaCalendario()
        defer { carpeta.borrar() }
        let almacen = AlmacenEnMemoria()
        let sync = SincronizadorCalendario(almacen: almacen, mapa: try MapaCalendario(directory: nil))
        _ = try await sync.sincronizar(foto: carpeta.foto)
        let ev = try #require(almacen.evento(url: "tls://rutina/rutina-semana-prueba"))
        let id = try #require(ev.id)
        // Manu lo pasa a un calendario compartido (sin invitados).
        let compartido = almacen.anadirCalendarioAjeno("Compartido de prueba")
        almacen.editarFuera(id) { $0.calendario = compartido }
        // Y retira la ficha.
        try carpeta.retirar(CarpetaCalendario.rutina)
        _ = try await sync.sincronizar(foto: carpeta.foto)
        // Corregido (S5): la app solo toca lo que está en su calendario.
        #expect(!almacen.retiradas.contains(id))
        #expect(almacen.eventos.contains { $0.id == id && $0.calendario == compartido })
    }
}

/// Lo que «tiene» Mail en la bandeja de entrada en cada ronda (JSON sintético del guion).
final class BandejaDePrueba: @unchecked Sendable {
    let lock = NSLock()
    var mensajes: [[String: Any]] = []
}
