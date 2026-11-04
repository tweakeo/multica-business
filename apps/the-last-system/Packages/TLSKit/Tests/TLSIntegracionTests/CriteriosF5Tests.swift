import Foundation
import MCP
import Testing
@testable import TLSAgents
@testable import TLSCore
import TLSGateway
@testable import TLSIntegracion
import TLSIntegrations
import TLSMCPHost
import TLSMCPShared
@testable import TLSUI

/// Los criterios de aceptación de F5 (PLAN §9) de punta a punta: la empresa se abre como en la app y la integración
/// monta, con ella, sus conexiones (Mail con el Cartero, Calendario y otros programas) sobre dobles: nunca Mail, EventKit,
/// TCC ni el Llavero de verdad; para otros programas, un servidor de herramientas propio (SDK Swift) sin red.
@Suite("F5 · criterios de aceptación de punta a punta", .serialized)
@MainActor
struct CriteriosF5Tests {
    static let domingo = CriteriosF4Tests.domingo

    static func simulado(_ grabaciones: URL) -> @Sendable (PuertaMCP) -> any AgentRuntime {
        { puerta in SimulatedRuntime(grabaciones: grabaciones, servidor: puerta) }
    }

    /// Correos nuevos de la cuenta «Asesoría»: uno normal (con adjunto) y uno de un remitente privado.
    static func correos() -> [[String: Any]] { [
        JXADoble.correo("f5-1@cliente.example", EntornoF4.fecha(18, 10, 10), de: "Lucía Romero <lucia@cliente.example>",
                        asunto: "Precio de la Renta", texto: "¿Cuánto cuesta la Renta?",
                        adjuntos: [["nombre": "dni.pdf", "bytes": 120_000, "contenido": "NO DEBE SALIR"]]),
        JXADoble.correo("f5-2@consulta.example", EntornoF4.fecha(18, 10, 20), de: "Paciente <persona@consulta.example>",
                        asunto: "Resultado del expediente", texto: "Texto privado que nunca debe guardarse"),
    ] }

    // MARK: F5-1 · Mail

    @Test("F5-1 · Mail: explicación antes del permiso; privado solo metadatos; Automatización denegada → tarjeta sin bucles; aprobar abre la redacción (nunca envía)")
    func criterio1() async throws {
        let d = DoblesF5(permisos: PermisosDoble([.automatizacionMail: .sinPreguntar]))
        let salida = JXADoble.correos(Self.correos())
        d.jxa.responder { l in l.guion == GuionesDeMail.cuentas ? JXADoble.cuentas : salida }
        let grabaciones = try EntornoF4.grabaciones()
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, runtime: Self.simulado(grabaciones), conexiones: d.sistema(ahora: { EntornoF4.lunes })) { e in
            let c = try await e.esperarConexiones()
            let sesion = try #require(e.sesion)
            let s = try #require(ConexionesDeLaApp.fabrica?(e.entry.id))
            let p = try #require(e.piezas)

            // 1. La explicación va antes del aviso de macOS: sin ella no se pide nada.
            guard case .explicar(let explicacion) = await s.situacion(.mail) else { Issue.record("Esperaba la explicación"); return }
            #expect(!explicacion.nunca.isEmpty)
            await #expect(throws: ErrorDeConexion.self) {
                _ = try await s.pedir(.mail, tras: PermisoExplicado(permiso: .mail, explicacion: explicacion))
            }
            #expect(d.permisos.pedidos.isEmpty)
            let vista = await s.explicar(.mail)
            #expect(try await s.pedir(.mail, tras: vista) == .concedido)
            #expect(d.permisos.pedidos == [.automatizacionMail])
            // La misma explicación no sirve dos veces.
            await #expect(throws: ErrorDeConexion.self) { _ = try await s.pedir(.mail, tras: vista) }

            // 2. Cuenta, remitente privado y el Cartero activo (como la persona: queda en la configuración).
            #expect(await s.cuentasDeMail() == .cuentas(["Asesoría"]))
            try await s.guardarAjustesDeMail(AjustesDeMailConexion(
                cuenta: "Asesoría", privados: [RemitentePrivadoConexion(patron: "consulta.example", etiqueta: "Expediente privado")]))
            #expect(!c.carteroActivo)
            try await s.activarCartero(true)
            #expect(c.carteroActivo)
            #expect(p.autorizador.estadoDeConfig().efectiva.asistente("cartero")?.activo == true)
            #expect(c.mailConectado)
            // Activar el Cartero lee el correo (la app, nunca un asistente) y lo guarda fuera de la carpeta.
            guard case .leidos(let n, _) = try #require(c.ultimaLectura) else { Issue.record("Esperaba correo leído"); return }
            #expect(n == 2)
            let guardado = try #require(try FileManager.default.contentsOfDirectory(
                at: p.estadoDeCarpeta.appendingPathComponent("correo"), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "jsonl" }
                .map { try String(contentsOf: $0, encoding: .utf8) }.joined())
            // Del privado solo queda «correo privado de X» (su identificador de Mail no sale de los ajustes de la app).
            #expect(guardado.contains("correo privado de Expediente privado"))
            #expect(!guardado.contains("persona@consulta.example"))
            #expect(!guardado.contains("Resultado del expediente"))
            #expect(!guardado.contains("Texto privado"))
            #expect(guardado.contains("dni.pdf"))
            #expect(!guardado.contains("NO DEBE SALIR"))
            #expect(EntornoF4.ficherosCon("Texto privado", en: e.carpeta).isEmpty)

            // Lo que ve el Cartero con `tls_correo_pendiente`: un dato no confiable; lo privado, solo metadatos.
            let servidor = try #require(e.motor?.servidor)
            let cartero = try #require(p.autorizador.estadoDeConfig().efectiva.asistente("cartero"))
            let r = await servidor.llamar("tls_correo_pendiente", argumentos: [:], contexto: ContextoDelAsistente(ejecucion: "r-cartero", asistente: cartero))
            #expect(!r.esError, "\(r.texto)")
            #expect(r.texto.contains("dato_no_confiable"))
            #expect(r.texto.contains("correo privado de Expediente privado"))
            #expect(!r.texto.contains("consulta.example"))
            #expect(!r.texto.contains("Resultado del expediente"))

            // 3. Automatización denegada: tarjeta explicativa en Decisiones y ningún reintento en bucle.
            d.jxa.responder { _ in JXADoble.denegada }
            let antes = d.jxa.lecturas
            let r1 = await c.leerCorreo()
            guard case .automatizacionDenegada = r1 else { Issue.record("Esperaba la Automatización denegada: \(String(describing: r1))"); return }
            let tarjetas = ConexionesEnDecisiones.de(sesion).pendientes.filter { $0.origen == "mail" }
            #expect(tarjetas.count == 1)
            #expect(tarjetas.first?.clase == .permiso)
            #expect(tarjetas.first?.principal.titulo == "Abrir Ajustes del Sistema")
            #expect(!(tarjetas.first?.pasos.isEmpty ?? true))
            for _ in 0..<3 { _ = await c.leerCorreo(); await c.rondaDeCorreo() }
            #expect(d.jxa.lecturas == antes + 1, "No se vuelve a lanzar osascript hasta que la persona lo pida")
            // La persona lo arregla y lo pide: se vuelve a leer y la tarjeta se va.
            d.jxa.responder { l in l.guion == GuionesDeMail.cuentas ? JXADoble.cuentas : JXADoble.correos([]) }
            await c.reintentarCorreo()
            _ = await c.leerCorreo()
            #expect(d.jxa.lecturas == antes + 2)
            #expect(ConexionesEnDecisiones.de(sesion).pendientes.filter { $0.origen == "mail" }.isEmpty)

            // 4. Aprobar un correo abre la redacción de Mail con lo aprobado; enviar es tuyo (no hay cómo enviar).
            #expect(HuecosDeAprobacion.abreMail(p.aprobaciones.ejecutor))
            let host = try #require(e.host)
            _ = try #require(try await host.pedir(a: "comercial", instruccion: "Repasa el embudo", accion: "repaso-embudo"))
            try await e.esperarTrabajos()
            let apr = try #require(try ApprovalStore(estado: p.autorizador.estado).abiertas(ahora: .distantPast).first { $0.accion == .enviarCorreo })
            let borrador = try #require(apr.ruta)
            let resultado = try await p.aprobaciones.aprobar(apr.id, autor: .persona("Manu"))
            guard case .abiertoEnMail = resultado else { Issue.record("Esperaba «Abierto en Mail»: \(resultado)"); return }
            #expect(d.redactor.abiertas.count == 1)
            let abierta = try #require(d.redactor.abiertas.first)
            #expect(!abierta.para.isEmpty)
            #expect(e.texto(borrador.raw)?.contains("Abierto en Mail") == true)
            #expect(e.texto(borrador.raw)?.contains(abierta.asunto) == true)
            // Ningún guion de los que lanza la app envía, mueve ni borra.
            for g in [GuionesDeMail.leer, GuionesDeMail.cuentas, GuionesDeMail.redactar] {
                #expect(!g.contains(".send(") && !g.contains("delete(") && !g.contains(".move("))
            }
        }
    }

    // MARK: F5-2 · Calendario

    @Test("F5-2 · Una rutina con «Al Calendario» crea un evento recurrente sin invitados en «The Last System»; retirar la ficha retira el evento; Hoy solo ve «Ocupado»")
    func criterio2() async throws {
        let d = DoblesF5(permisos: PermisosDoble([.calendarios: .sinPreguntar]))
        let ruta = "1 · Dirección/Rutinas/revision-de-la-semana.md"
        let grabaciones = try EntornoF4.grabaciones()
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, preparar: { root in
            let url = VaultPath(ruta).url(in: root)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("""
            ---
            tls_type: routine
            tls_schema: 1
            nombre: Revisión de la semana
            area: direccion
            cadencia: semanal
            dia: lun
            hora: "09:00"
            duracion_min: 45
            activa: true
            calendario: true
            ---
            # Revisión de la semana

            """.utf8).write(to: url)
        }, runtime: Self.simulado(grabaciones), conexiones: d.sistema()) { e in
            let c = try await e.esperarConexiones()
            let sesion = try #require(e.sesion)
            let s = try #require(ConexionesDeLaApp.fabrica?(e.entry.id))
            // Sin conectar, el Calendario no se toca (ni se crea nada).
            #expect(d.calendario.calendarios.isEmpty)
            #expect(await s.estadoDelCalendario() == .sinConectar)

            // Explicación → permiso → «The Last System» y la primera pasada.
            guard case .explicar = await s.situacion(.calendario) else { Issue.record("Esperaba la explicación"); return }
            let vista = await s.explicar(.calendario)
            d.calendario.ponerPermiso(.concedido)
            d.permisos.alPedir = .concedido
            #expect(try await s.pedir(.calendario, tras: vista) == .concedido)
            guard case .conectado = await s.conectarCalendario() else { Issue.record("Esperaba el Calendario conectado"); return }
            #expect(d.calendario.calendarios == ["The Last System"])
            let ev = try #require(d.calendario.eventos.first { $0.titulo == "Revisión de la semana" })
            #expect(ev.repeticion == .semanal(diaSemana: 1))
            #expect(ev.invitados == 0)
            #expect(d.calendario.guardados.allSatisfy { $0.invitados == 0 })
            #expect(ev.minutos == 45)

            // Hoy y `tls_agenda`: de otros calendarios, solo «Ocupado» (nunca su título).
            d.calendario.anadirAjeno(titulo: "Cita médica de Expediente privado", inicio: EntornoF4.fecha(19, 11), fin: EntornoF4.fecha(19, 12))
            let ocupado = await c.calendario!.ocupado(desde: LocalDate(year: 2026, month: 10, day: 19)!,
                                                      hasta: LocalDate(year: 2026, month: 10, day: 19)!, zona: EntornoF4.madrid)
            #expect(ocupado.count == 1)
            #expect(ocupado.allSatisfy { $0.titulo == "Ocupado" })
            #expect(AlmacenHoy.de(sesion).ocupado != nil)

            // Retirar la ficha (a Archivo/, como la persona) retira el evento.
            let r = try await sesion.escribirComoPersona(WritePlan(autor: .persona("Manu"), descripcion: "Retirar la rutina",
                                                                   ops: [.retire(VaultPath(ruta))]))
            #expect(r.hecho)
            try await esperar("el evento retirado", segundos: 10) {
                d.calendario.eventos.first { $0.titulo == "Revisión de la semana" } == nil
            }
            #expect(e.existe("Archivo/" + VaultPath(ruta).name) || !e.existe(ruta))
        }
    }

    // MARK: F5-3 · Otros programas

    @Test("F5-3 · Otro programa: se listan sus herramientas; una sensible genera aprobación; una nueva queda desactivada; un lead crea su contacto una vez; la clave no está en ningún fichero")
    func criterio3() async throws {
        let token = "tok_f5_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let servidorMCP = try await ServidorMCPF5.arrancar(token: token, herramientas: ServidorMCPF5.herramientas())
        let d = DoblesF5()
        let grabaciones = try EntornoF4.grabaciones()
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, preparar: { root in
            // Contactos en autónomo para que el reflejo escriba la ficha (si no, quedaría como propuesta).
            let url = root.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: url, encoding: .utf8)
            try Data((t + "capacidades:\n  VEN-02: {modo: autonomo}\n  VEN-03: {modo: autonomo}\n").utf8).write(to: url)
        }, runtime: Self.simulado(grabaciones), conexiones: d.sistema()) { e in
            let c = try await e.esperarConexiones()
            let sesion = try #require(e.sesion)
            let s = try #require(ConexionesDeLaApp.fabrica?(e.entry.id))
            let p = try #require(e.piezas)

            // Alta con la clave (va al Llavero; en `conexiones.json` solo el nombre del campo) y «Probar».
            try await s.anadir(AltaDeOtroPrograma(id: "prueba", nombre: "Programa de prueba", plantilla: "ghl",
                                                  transporte: .web(direccion: servidorMCP.direccion), clave: token))
            let frase = try await s.probar("prueba")
            #expect(frase.hasPrefix("Responde. Trae 3 herramientas: 1 solo lee y 2 piden tu OK."), "\(frase)")
            let programas = await s.otrosProgramas()
            #expect(programas.first?.estado == .conectado)
            #expect(programas.first?.activas == 3)
            let matriz = await s.matriz("prueba")
            #expect(Set(matriz.map(\.expuesta)) == ["ext_prueba_contacts_list", "ext_prueba_send_sms", "ext_prueba_contacts_update"])
            #expect(matriz.first { $0.expuesta == "ext_prueba_send_sms" }?.motivo.hasPrefix("Su nombre lleva") == true)

            // Interruptores en llano (como la persona): leer contactos y pedir cambios con tu OK.
            let ints = await s.interruptores("prueba")
            #expect(ints.contains { $0.texto == "Comercial puede leer contactos de Programa de prueba" })
            try await s.cambiarInterruptor("prueba", permiso: "leer-contactos", encender: true)
            try await s.cambiarInterruptor("prueba", permiso: "pedir-acciones", encender: true)
            let comercial = try #require(p.autorizador.estadoDeConfig().efectiva.asistente("comercial"))
            #expect(comercial.herramientasExternas.contains("ext_prueba_contacts_list"))

            // `tls-mcp` las expone al Comercial; lo sensible genera aprobación y no sale nada.
            let servidor = try #require(e.motor?.servidor)
            let ctx = ContextoDelAsistente(ejecucion: "r-f5-3", asistente: comercial)
            let visibles = await servidor.herramientas(para: ctx).map(\.nombre).filter { $0.hasPrefix("ext_") }
            #expect(Set(visibles) == ["ext_prueba_contacts_list", "ext_prueba_send_sms", "ext_prueba_contacts_update"])
            let r = await servidor.llamar("ext_prueba_send_sms", argumentos: ["to": "600000000", "text": "Hola"], contexto: ctx)
            #expect(r.estructurado?.objectValue?["estado"]?.stringValue == "aprobacion_requerida", "\(r.texto)")
            #expect(!servidorMCP.estado.llamadas.contains { $0.0 == "send_sms" })
            // Al aprobar, la app (GatewayRouter, por el hueco de esta empresa) llama con los datos exactos.
            let id = try #require(r.estructurado?.objectValue?["id"]?.stringValue)
            let resultado = try await p.aprobaciones.aprobar(id, autor: .persona("Manu"))
            guard case .enviadoAPasarela = resultado else { Issue.record("Esperaba enviado a la pasarela: \(resultado)"); return }
            #expect(servidorMCP.estado.llamadas.filter { $0.0 == "send_sms" }.map(\.1) == [["to": "600000000", "text": "Hola"]])

            // Una herramienta nueva queda desactivada, con su tarjeta en Decisiones y en Conexiones.
            servidorMCP.estado.herramientas += [ServidorMCPF5.cambia("contacts_delete", propiedades: ["id": .object(["type": "string"])])]
            // (El programa avisa de que cambió su lista: la app vuelve a listar, como con `listChanged`.)
            let cambios = try await c.pasarela.refrescar("prueba")
            #expect(cambios.nuevas == ["contacts_delete"])
            c.ponerRevisiones()
            let revisiones = await s.revisiones()
            #expect(revisiones.first?.herramientas.map(\.nombre) == ["contacts_delete"])
            #expect(ConexionesEnDecisiones.de(sesion).pendientes.contains { $0.clase == .herramientas && $0.origen == "pasarela:prueba" })
            #expect(!c.pasarela.herramientasActivas().contains { $0.herramienta.nombre == "contacts_delete" })
            let visibles2 = await servidor.herramientas(para: ctx).map(\.nombre)
            #expect(!visibles2.contains("ext_prueba_contacts_delete"))
            // «Dejarlas desactivadas» desde Decisiones: la tarjeta se va y sigue sin estar.
            let tarjeta = try #require(ConexionesEnDecisiones.de(sesion).pendientes.first { $0.clase == .herramientas })
            #expect(await ConexionesEnDecisiones.de(sesion).pulsar(tarjeta, principal: false))
            #expect(c.pasarela.tarjetasDeRevision().isEmpty)

            // Un lead de prueba crea su contacto en Ventas; la segunda sincronización no crea nada.
            let uno = try await s.sincronizarAhora("prueba")
            #expect(e.existe("2 · Ventas/Contactos/lead-de-prueba.md"), "\(uno)")
            #expect(e.texto("2 · Ventas/Contactos/lead-de-prueba.md")?.contains("ext:prueba:c-001") == true)
            let antes = Set(e.foto().notes.map(\.raw))
            let dos = try await s.sincronizarAhora("prueba")
            #expect(dos.hasPrefix("0 fichas nuevas"), "\(dos)")
            #expect(Set(e.foto().notes.map(\.raw)) == antes)

            // La clave no está en ningún fichero: ni en la carpeta ni en los ajustes de la app (ni en `conexiones.json`).
            #expect(EntornoF4.ficherosCon(token, en: e.carpeta).isEmpty)
            #expect(EntornoF4.ficherosCon(token, en: e.base).isEmpty)
            #expect(try String(contentsOf: p.estadoDeCarpeta.appendingPathComponent("conexiones.json"), encoding: .utf8).contains("\"token\""))
            #expect((try? d.llavero.leer(id: "prueba", campo: "token")) == token)
        }
        await servidorMCP.parar()
    }

    // MARK: Ciclo de vida y ejemplo

    @Test("Las conexiones se montan y se paran con la empresa: al cerrar no queda nada (ni huecos, ni tarjetas, ni servicios)")
    func cicloDeVida() async throws {
        let d = DoblesF5()
        let grabaciones = try EntornoF4.grabaciones()
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        let e = try EntornoF4(clase: .copia, inicio: Self.domingo, runtime: Self.simulado(grabaciones), conexiones: d.sistema())
        do {
            try await e.abrir()
            let c = try await e.esperarConexiones()
            let sesion = try #require(e.sesion)
            #expect(ConexionesDeLaApp.fabrica?(e.entry.id) != nil)
            #expect(ConexionesEnDecisiones.de(sesion).huecos.pasarela != nil)
            await e.app.escritorSeVa(sesion)
            #expect(!c.arrancada)
            #expect(ConexionesDeLaApp.fabrica?(e.entry.id) == nil)
            #expect(ConexionesEnDecisiones.de(sesion).huecos.pasarela == nil)
            #expect(ConexionesEnDecisiones.de(sesion).huecos.correo == nil)
        } catch {
            await e.cerrar()
            throw error
        }
        await e.cerrar()
    }

    @Test("En Ribera (ejemplo), Mail y Calendario quedan desactivados y «Otros programas» trae un programa simulado; nada pregunta a macOS")
    func ejemplo() async throws {
        let d = DoblesF5(permisos: PermisosDoble([.automatizacionMail: .sinPreguntar, .calendarios: .sinPreguntar]))
        try await EntornoF4.con(clase: .demo, inicio: Self.domingo, conexiones: d.sistema()) { e in
            let c = try await e.esperarConexiones()
            #expect(c.ejemplo)
            let s = try #require(ConexionesDeLaApp.fabrica?(e.entry.id))
            #expect(await s.enEjemplo(.mail) != nil)
            #expect(await s.enEjemplo(.calendario) != nil)
            // La pantalla los enseña «Desactivado (ejemplo)» sin preguntar nada.
            let m = ModeloConexiones(servicios: s)
            await m.cargar()
            #expect(m.estado(.mail) == .enEjemplo)
            #expect(m.estado(.calendario) == .enEjemplo)
            #expect(m.palabra(.mail) == "Desactivado (ejemplo)")
            await m.conectarMail()
            await m.conectarCalendario()
            #expect(d.permisos.pedidos.isEmpty)
            #expect(d.jxa.llamadas.isEmpty)
            #expect(d.calendario.calendarios.isEmpty)
            // El programa del ejemplo: simulado, sin red ni clave.
            let programas = await s.otrosProgramas()
            #expect(programas.map(\.id) == [ConectorSimulado.id])
            #expect(programas.first?.simulado == true)
            let frase = try await s.probar(ConectorSimulado.id)
            #expect(frase.hasPrefix("Responde. Trae 4 herramientas: 2 solo leen y 2 piden tu OK."), "\(frase)")
            #expect(c.pasarela.buscar(expuesta: "ext_simulado_send_message")?.herramienta.clase == .sensible)
            // `tls-mcp` no da correo en el ejemplo.
            let servidor = try #require(e.motor?.servidor)
            let cartero = ContextoDelAsistente(ejecucion: "r-ej", asistente: "cartero", buzon: true)
            let r = await servidor.llamar("tls_correo_pendiente", argumentos: [:], contexto: cartero)
            #expect(r.esError || r.texto.contains("Mail"))
        }
    }
}
