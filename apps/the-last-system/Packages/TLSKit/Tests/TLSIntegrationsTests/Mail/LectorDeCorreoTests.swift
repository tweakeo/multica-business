import Foundation
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSIntegrations

/// `LectorDeCorreo` con un `osascript` falso que devuelve JSON sintético: nunca se habla con Mail de verdad.
@Suite("Mail · LectorDeCorreo", .serialized)
struct LectorDeCorreoTests {
    struct Escenario {
        let estado: URL
        let almacen: AlmacenDeCorreo
        let cursor: CursorDeCorreo

        init() throws {
            estado = ApoyoCorreo.temporal("tl")
            almacen = AlmacenDeCorreo(estado: estado, zona: ApoyoCorreo.madrid)
            cursor = try CursorDeCorreo(estado: estado)
        }

        func lector(_ ejecutor: EjecutorJXAFalso, ajustes: AjustesDeCorreo = AjustesDeCorreo(cuenta: "Asesoría"),
                    ahora: Date = ApoyoCorreo.fecha(19, 8, 30)) -> LectorDeCorreo {
            LectorDeCorreo(ejecutor: ejecutor, almacen: almacen, cursor: cursor, ajustes: { ajustes }, ahora: { ahora })
        }

        /// Todo lo guardado, en bruto (para buscar lo que no debe estar).
        func bruto() -> String {
            let dir = estado.appendingPathComponent("correo")
            let nombres = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            return nombres.filter { $0.hasSuffix(".jsonl") }.sorted()
                .compactMap { try? String(contentsOf: dir.appendingPathComponent($0), encoding: .utf8) }.joined()
        }

        func limpiar() { try? FileManager.default.removeItem(at: estado) }
    }

    @Test("Cursor y topes: desde el cursor, 50 mensajes y 120 s; lo que sobra queda para la próxima lectura")
    func cursorYTopes() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let cuenta = "Asesoría"
        let cursor0 = ApoyoCorreo.fecha(16, 9)
        try e.cursor.avanzar(cuenta, a: cursor0)
        // 60 correos nuevos (uno cada 10 min desde el viernes 16 a las 10:00) y uno anterior al cursor que el guion
        // no debería devolver. El doble no respeta los topes: la app los aplica igual.
        let nuevos = (0..<60).map { i in
            EjecutorJXAFalso.crudo("n\(i)@correo.example", ApoyoCorreo.fecha(16, 10).addingTimeInterval(Double(i) * 600),
                                   texto: String(repeating: "á", count: 3000))
        }
        // «viejo» queda fuera incluso del margen de relectura (cursor − 48 h).
        let viejo = EjecutorJXAFalso.crudo("viejo@correo.example", ApoyoCorreo.fecha(13, 9))
        let todo = EjecutorJXAFalso.salida([viejo] + nuevos)
        let resto = EjecutorJXAFalso.salida(Array(nuevos[50...]))
        let ultimo = (nuevos[59]["fecha"] as! Double)
        let limite = cursor0.timeIntervalSince1970 * 1000
        let ejecutor = EjecutorJXAFalso { l in
            let desde = (EjecutorJXAFalso.parametros(l)["desde"] as? Double) ?? 0
            // Primera vez: todo (sin respetar nada). Después, lo posterior al cursor.
            if desde <= limite { return todo }
            return desde >= ultimo ? EjecutorJXAFalso.salida([]) : resto
        }
        let lector = e.lector(ejecutor)
        let r1 = await lector.leer()
        #expect(r1 == .leidos(nuevos: 50, mas: true))
        let l1 = try #require(ejecutor.llamadas.first)
        #expect(l1.tope == 120)
        #expect(l1.guion == GuionesDeMail.leer)
        let p = EjecutorJXAFalso.parametros(l1)
        #expect(p["cuenta"] as? String == cuenta && p["max"] as? Int == 50 && p["maxTexto"] as? Int == 4096)
        // Desde el cursor con el margen de relectura (S1, S2).
        #expect(p["desde"] as? Double == cursor0.addingTimeInterval(-LectorDeCorreo.margen).timeIntervalSince1970 * 1000)
        // El cursor queda en el último guardado (el 50.º); el anterior al cursor no se guardó.
        let tras1 = try #require(try e.cursor.leer(cuenta))
        #expect(tras1 == Date(timeIntervalSince1970: (nuevos[49]["fecha"] as! Double) / 1000))
        let guardados = await e.almacen.mensajes(desde: .distantPast, hasta: .distantFuture)
        #expect(guardados.count == 50 && !guardados.contains { $0.id == "viejo@correo.example" })
        // 4 KB de texto como mucho (en bytes, sin partir caracteres).
        #expect(guardados.allSatisfy { $0.texto.utf8.count <= 4096 && !$0.texto.isEmpty })

        // Segunda ronda: los 10 que quedaban; la tercera, nada nuevo.
        #expect(await lector.leer() == .leidos(nuevos: 10, mas: false))
        #expect(await lector.leer() == .leidos(nuevos: 0, mas: false))
        #expect(await e.almacen.mensajes(desde: .distantPast, hasta: .distantFuture).count == 60)
        // Fuera de la carpeta: en el estado de la app, con permisos solo para la persona.
        let fichero = e.almacen.fichero(LocalDate(year: 2026, month: 10, day: 16)!)
        #expect(fichero.path.hasPrefix(e.estado.appendingPathComponent("correo").path))
        let attrs = try FileManager.default.attributesOfItem(atPath: fichero.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Sin cuenta elegida, con Mail cerrado o pasado de tiempo: no se guarda nada ni se mueve el cursor")
    func sinLeer() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let nunca = EjecutorJXAFalso { _ in Issue.record("No debía lanzarse"); return ResultadoJXA(salida: "") }
        #expect(await e.lector(nunca, ajustes: AjustesDeCorreo()).leer() == .sinCuenta)
        let cerrado = EjecutorJXAFalso { _ in ResultadoJXA(salida: #"{"estado":"mail_cerrado"}"#) }
        #expect(await e.lector(cerrado).leer() == .mailCerrado)
        let lento = EjecutorJXAFalso { _ in ResultadoJXA(salida: "", estado: 15, tiempoAgotado: true) }
        #expect(await e.lector(lento).leer() == .tiempoAgotado)
        let sinCuenta = EjecutorJXAFalso { _ in ResultadoJXA(salida: #"{"estado":"sin_buzon"}"#) }
        #expect(await e.lector(sinCuenta).leer() == .cuentaNoEncontrada("Asesoría"))
        #expect(try e.cursor.leer("Asesoría") == nil)
        #expect(e.bruto().isEmpty)
    }

    @Test("Remitente o dominio privado: solo metadatos («correo privado de X»), aunque el guion trajera más")
    func remitentePrivado() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let ajustes = AjustesDeCorreo(cuenta: "Asesoría", privados: [
            RemitentePrivado(patron: "@consulta-medica.example", etiqueta: "Expediente privado"),
            RemitentePrivado(patron: "persona@otra.example", etiqueta: "una persona"),
        ])
        let ejecutor = EjecutorJXAFalso { _ in
            EjecutorJXAFalso.salida([
                // El guion no lo filtró (simulado): la app lo filtra igual.
                EjecutorJXAFalso.crudo("p1@consulta-medica.example", ApoyoCorreo.fecha(19, 8), de: "Dra. Pérez <citas@sede.consulta-medica.example>",
                                       asunto: "Resultados del análisis", texto: "Diagnóstico confidencial zarzaparrilla",
                                       adjuntos: [["nombre": "informe-privado.pdf", "bytes": 1200]]),
                // El guion sí lo filtró (lo normal): solo id, fecha, leído y la regla.
                ["id": "p2@otra.example", "fecha": ApoyoCorreo.fecha(19, 8, 1).timeIntervalSince1970 * 1000, "leido": true,
                 "privado": true, "regla": 1],
                EjecutorJXAFalso.crudo("n1@cliente.example", ApoyoCorreo.fecha(19, 8, 2), asunto: "Cita", texto: "¿Nos vemos?"),
            ])
        }
        #expect(await e.lector(ejecutor, ajustes: ajustes).leer() == .leidos(nuevos: 3, mas: false))
        // Al guion le llegan los patrones (para que ni siquiera lea el contenido de lo privado).
        #expect(EjecutorJXAFalso.parametros(try #require(ejecutor.llamadas.first))["privados"] as? [String]
                == ["@consulta-medica.example", "persona@otra.example"])
        let todos = await e.almacen.mensajes(desde: .distantPast, hasta: .distantFuture)
        let p1 = try #require(todos.first { $0.id == "p1@consulta-medica.example" })
        #expect(p1.privado && p1.de == "correo privado de Expediente privado")
        #expect(p1.asunto.isEmpty && p1.texto.isEmpty && p1.para.isEmpty && p1.adjuntos.isEmpty)
        let p2 = try #require(todos.first { $0.id == "p2@otra.example" })
        #expect(p2.privado && p2.de == "correo privado de una persona" && p2.leido)
        #expect(todos.first { $0.id == "n1@cliente.example" }?.asunto == "Cita")
        let bruto = e.bruto()
        for nunca in ["Resultados del análisis", "zarzaparrilla", "citas@sede", "Dra. Pérez", "informe-privado"] {
            #expect(!bruto.contains(nunca), "«\(nunca)» no debe guardarse")
        }
    }

    @Test("Adjuntos: solo nombre y tamaño, nunca su contenido")
    func adjuntosSinContenido() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let ejecutor = EjecutorJXAFalso { _ in
            EjecutorJXAFalso.salida([EjecutorJXAFalso.crudo("a1@proveedor.example", ApoyoCorreo.fecha(19, 8), asunto: "Factura",
                                                            adjuntos: [["nombre": "factura.pdf", "bytes": 186_000,
                                                                        "contenido": "JVBERi0xLjQgQ09OVEVOSURPLURFTC1BREpVTlRP"]])])
        }
        #expect(await e.lector(ejecutor).leer() == .leidos(nuevos: 1, mas: false))
        let m = try #require(await e.almacen.mensaje("a1@proveedor.example"))
        #expect(m.adjuntos == [AdjuntoDeCorreo(nombre: "factura.pdf", bytes: 186_000)])
        #expect(!e.bruto().contains("JVBERi0x"))
        // Lo que ve el Cartero de ese adjunto: nombre y bytes.
        let visto = m.paraElCartero(ApoyoCorreo.madrid)["adjuntos"] as? [[String: Any]]
        #expect(visto?.first?.keys.sorted() == ["bytes", "nombre"])
    }

    @Test("Automatización denegada: tarjeta que explica cómo arreglarlo y sin reintentos en bucle")
    func automatizacionDenegada() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let ejecutor = EjecutorJXAFalso { _ in
            ResultadoJXA(salida: "", errores: "execution error: Not authorized to send Apple events to Mail. (-1743)", estado: 1)
        }
        let lector = e.lector(ejecutor)
        guard case .automatizacionDenegada(let t) = await lector.leer() else { Issue.record("Esperaba la tarjeta"); return }
        #expect(t.permiso == .automatizacionMail && t.id == "permiso:automatizacion_mail")
        #expect(t.enlace.absoluteString.hasPrefix("x-apple.systempreferences:") && t.enlace.absoluteString.contains("Privacy_Automation"))
        #expect(t.boton == "Abrir Ajustes del Sistema" && !t.pasos.isEmpty)
        #expect(t.texto.contains("Nada se ha enviado"))
        #expect(jerga(t.titulo + " " + t.texto + " " + t.pasos.joined(separator: " ")).isEmpty)
        // Lo técnico, solo en «Detalle técnico».
        #expect(t.detalleTecnico?.contains("-1743") == true)
        // Más rondas: la misma tarjeta y ningún `osascript` más.
        for _ in 0..<5 {
            guard case .automatizacionDenegada = await lector.leer() else { Issue.record("Debía seguir bloqueado"); return }
        }
        #expect(ejecutor.llamadas.count == 1)
        #expect(await lector.lanzamientos == 1)
        // Hasta que la persona lo arregla y pulsa «Volver a intentar».
        await lector.reintentar()
        _ = await lector.leer()
        #expect(ejecutor.llamadas.count == 2)
        #expect(try e.cursor.leer("Asesoría") == nil)
    }

    @Test("Los guiones solo leen o abren una redacción: ni enviar, ni borrar, ni mover, ni marcar como leído")
    func guionesSinSalidas() {
        for g in [GuionesDeMail.leer, GuionesDeMail.redactar, GuionesDeMail.cuentas] {
            for prohibido in [".send(", "send()", ".delete(", "delete(", ".move(", "move(", "readStatus =", "readStatus=",
                              "junkMailStatus", "flaggedStatus =", "forward(", "redirect(", "doShellScript", "do shell script"] {
                #expect(!g.contains(prohibido), "«\(prohibido)» en un guion de Mail")
            }
        }
        // Leer no abre Mail si está cerrado; la redacción se ve (la envías tú).
        #expect(GuionesDeMail.leer.contains("Mail.running()") && !GuionesDeMail.leer.contains("activate"))
        #expect(GuionesDeMail.redactar.contains("visible: true") && GuionesDeMail.redactar.contains("redaccion.visible = true"))
    }

    @Test("Cuentas de Mail para elegir (solo nombres) y Mail cerrado")
    func cuentas() async {
        let ok = EjecutorJXAFalso { _ in ResultadoJXA(salida: #"{"estado":"ok","cuentas":["Asesoría","Personal"]}"#) }
        #expect(await CuentasDeMail.listar(ok) == .cuentas(["Asesoría", "Personal"]))
        #expect(ok.llamadas.first?.guion == GuionesDeMail.cuentas && ok.llamadas.first?.argumentos.isEmpty == true)
        let cerrado = EjecutorJXAFalso { _ in ResultadoJXA(salida: #"{"estado":"mail_cerrado"}"#) }
        #expect(await CuentasDeMail.listar(cerrado) == .mailCerrado)
        let no = EjecutorJXAFalso { _ in ResultadoJXA(salida: "", errores: "(-1743)", estado: 1) }
        guard case .automatizacionDenegada = await CuentasDeMail.listar(no) else { Issue.record("Esperaba la tarjeta"); return }
    }

    @Test("Enlaces message:// de ida y vuelta")
    func enlaces() {
        let id = "CAF=abc+1@mail.example.com"
        let e = EnlaceDeCorreo.enlace("<\(id)>")
        #expect(e.hasPrefix("message://%3C") && e.hasSuffix("%3E"))
        #expect(EnlaceDeCorreo.id(e) == id)
        #expect(EnlaceDeCorreo.id("message://<x@y>") == "x@y")
        #expect(EnlaceDeCorreo.id("https://example.com") == nil)
        #expect(VentanaDeTriaje.horas(LocalDate(year: 2026, month: 10, day: 19)!) == 72)
        #expect(VentanaDeTriaje.horas(LocalDate(year: 2026, month: 10, day: 20)!) == 24)
        #expect(OcultarSecretos.texto("Mi contraseña: hunter2 y el token=abcdef").contains("[oculto]"))
        #expect(!OcultarSecretos.texto("clave: sk-ant-1234567890abcdefghij").contains("sk-ant"))
    }
}
