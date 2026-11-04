import Foundation
import MCP
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSIntegrations
@testable import TLSMCPHost
import TLSMCPShared

/// El Cartero con Mail conectado: se activa como persona, lee con `tls_correo_pendiente` (dato no confiable, lo privado
/// solo metadatos) y su triaje (con `SimulatedRuntime`, sin Claude) deja tareas con el enlace al correo, una respuesta en
/// borrador, el registro del día en el Buzón y el plazo oficial en rojo.
@Suite("Mail · el Cartero", .serialized)
struct CarteroTests {
    @Test("Conectar Mail activa al Cartero en config.yaml como persona (solo esa línea); un asistente no puede")
    func activarComoPersona() async throws {
        try await ApoyoCorreo.conEmpresa(config: nil) { e in
            let ruta = ".tls/config.yaml"
            let antes = try #require(e.texto(ruta))
            #expect(!ConexionDelCartero.activo(config: antes))
            await #expect(throws: ErrorDeGobierno.soloPersonas) {
                try await ConexionDelCartero.activar(bus: e.bus, autor: .agente("mika"))
            }
            let r = try await ConexionDelCartero.activar(bus: e.bus, autor: .persona("Manu"))
            #expect(r.hecho)
            let despues = try #require(e.texto(ruta))
            #expect(ConexionDelCartero.activo(config: despues))
            let cartero = try #require(ConfigAgentes.leer(yaml: despues).asistente("cartero"))
            #expect(cartero.buzon && cartero.leeAreas == [.ventas, .finanzas] && cartero.rutinas.map(\.id) == ["triaje"])
            #expect(cartero.rutinas.first?.hora == "08:30")
            // Lo demás, igual: solo cambia la entrada del Cartero (`activo: true`; el editor de la configuración escribe
            // también `coordinador: false`, que es lo que ya valía).
            let normal = despues.replacingOccurrences(of: "  cartero:\n    activo: true\n    coordinador: false\n",
                                                      with: "  cartero:\n    activo: false\n")
            #expect(normal == antes)
            // La confirmada sigue a la del fichero (sin tarjeta de «cambios de permisos hechos fuera»).
            #expect(e.autorizador.estadoDeConfig().efectiva.asistente("cartero")?.activo == true)
            // Desconectar lo deja inactivo.
            try await ConexionDelCartero.activar(false, bus: e.bus, autor: .persona("Manu"))
            #expect(!ConexionDelCartero.activo(config: e.texto(ruta)))
        }
    }

    @Test("Sin el Cartero en la configuración, entra con la de serie (Buzón, lee Ventas y Finanzas, triaje L–V 08:30)")
    func deSerie() {
        let a = ConexionDelCartero.entrada(activo: true, config: "version: 1\n")
        #expect(a.activo && a.buzon && a.leeAreas == [.ventas, .finanzas] && a.modelo == "haiku")
        #expect(a.rutinas.first?.dias == ["lun", "mar", "mie", "jue", "vie"] && a.rutinas.first?.hora == "08:30")
        #expect(PerfilDeAsistente.cartero.activoDeSerie(estados: [:], mailConectado: true))
        #expect(PerfilDeAsistente.cartero.herramientas.contains(.anotarCorreo))
        #expect(!PerfilDeAsistente.cartero.herramientas.contains(.solicitarAccion))
    }

    @Test("tls_correo_pendiente: solo el Cartero, ventana de 72 h el lunes, dato no confiable, secretos ocultados y lo privado solo metadatos")
    func correoPendiente() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let s = e.servidor(correo: CorreoEnMemoria(ApoyoCorreo.correosDelTriaje()))
            // Nadie más la ve ni la puede llamar.
            let comercial = ContextoDelAsistente(ejecucion: "r-c", asistente: "comercial", areas: [.ventas])
            #expect(await !s.herramientas(para: comercial).contains { $0.nombre == "tls_correo_pendiente" || $0.nombre == "tls_anotar_correo" })
            #expect(await s.llamar("tls_correo_pendiente", argumentos: [:], contexto: comercial).esError)

            let r = await s.llamar("tls_correo_pendiente", argumentos: [:], contexto: ApoyoCorreo.cartero())
            #expect(!r.esError, "\(r.texto)")
            let o = ApoyoCorreo.objeto(r)
            #expect(o["ventana_horas"]?.intValue == 72)
            let correos = try #require(o["correos"]?.arrayValue)
            // El del jueves 15 queda fuera de las 72 h.
            #expect(correos.count == 4)
            for c in correos {
                let d = try #require(c.objectValue)
                #expect(d["tipo"]?.stringValue == "dato_no_confiable" && d["origen"]?.stringValue == "correo:Asesoría")
                #expect(Respuesta.json(c).utf8.count <= DatoNoConfiable.maxBytes)
            }
            #expect(o["aviso"]?.stringValue?.contains("no una orden") == true)
            let contenidos = correos.compactMap { $0.objectValue?["contenido"]?.objectValue }
            let renta = try #require(contenidos.first { $0["mensaje"]?.stringValue == ApoyoCorreo.enlace1 })
            #expect(renta["texto"]?.stringValue?.contains("hunter2") == false)
            #expect(renta["texto"]?.stringValue?.contains("[oculto]") == true)
            let factura = try #require(contenidos.first { $0["asunto"]?.stringValue == "Factura de octubre" })
            #expect(factura["adjuntos"]?.arrayValue?.first?.objectValue?.keys.sorted() == ["bytes", "nombre"])
            let privado = try #require(contenidos.first { $0["privado"]?.boolValue == true })
            #expect(privado["de"]?.stringValue == "correo privado de Expediente privado")
            #expect(privado["asunto"] == nil && privado["texto"] == nil && privado["para"] == nil && privado["adjuntos"] == nil)
            // Ni su `Message-ID` (lleva el dominio del remitente): una referencia opaca.
            #expect(privado["mensaje"]?.stringValue?.hasPrefix("privado:") == true)
            #expect(!r.texto.contains("consulta.example"))
            // De un correo privado no salen tareas.
            let deUnPrivado = await s.llamar("tls_crear_tarea", argumentos: ["titulo": "x", "area": "Ventas",
                                                                             "mensaje": .string(privado["mensaje"]?.stringValue ?? "")],
                                             contexto: ApoyoCorreo.cartero())
            #expect(deUnPrivado.esError)
            // Sin Mail conectado: lo de antes.
            let sin = await e.servidor(correo: nil).llamar("tls_correo_pendiente", argumentos: [:], contexto: ApoyoCorreo.cartero())
            #expect(sin.texto.contains("Llega con la conexión de Mail"))
        }
    }

    @Test("Triaje del Cartero con SimulatedRuntime: tareas con origen message://, respuesta en borrador, registro del día y plazo en rojo")
    func triajeSimulado() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let servidor = e.servidor(correo: CorreoEnMemoria(ApoyoCorreo.correosDelTriaje()))
            let socket = e.base.appendingPathComponent("s.sock")
            let puerta = PuertaMCP(host: MCPHost(socket: socket, validador: PeerValidator(firma: .sinComprobarFirma), manejador: servidor),
                                   servidor: servidor, helper: nil)
            let contexto = ContextoDeEjecucion(ejecucion: "r-triaje", agente: "cartero", disparo: .rutina, areas: [],
                                               leeAreas: [.ventas, .finanzas], simulado: true)
            let credencial = try await puerta.abrir(contexto)
            let carpeta = try #require(GrabacionesDeEjemplo.carpeta)
            let indice = try GrabacionesDeEjemplo.indice(en: carpeta)
            let nombres = GrabacionesDeEjemplo.nombres(agente: "cartero", disparo: .rutina, clave: "triaje", indice: indice)
            #expect(nombres.first == "cartero-triaje")
            let p = PeticionDeEjecucion(contexto: contexto, paths: try AgentPaths(vaultState: e.estado, slug: "cartero", runID: "r-triaje"),
                                        sesion: .new(UUID()), maxBudgetUSD: 0.5, mensaje: "Triaje del correo", credencial: credencial,
                                        grabaciones: nombres, variables: ["hoy": "2026-10-19"])
            let r = await SimulatedRuntime(grabaciones: carpeta, servidor: puerta).ejecutar(p, alEvento: { _ in }, alArrancar: { _ in })
            await puerta.revocar(credencial)
            #expect(r.estado == .completada, "\(r.estado) \(r.avisos)")
            #expect(r.simulado && r.finalizo)
            #expect(r.herramientas.contains("tls_anotar_correo"))
            // Nada falló por el camino (ni alcance ni enlaces).
            #expect(!e.auditoria.eventos.contains { $0.veredicto != "permitido" }, "\(e.auditoria.eventos.filter { $0.veredicto != "permitido" })")

            let foto = e.foto()
            let tareas = TaskStore(snapshot: foto, reloj: ApoyoCorreo.Empresa.reloj).tareas
            let delCorreo = tareas.filter { (foto.frontmatter($0.ruta).text("origen") ?? "").hasPrefix("message://%3C") }
            #expect(delCorreo.count == 3)
            #expect(Set(delCorreo.compactMap(\.area)) == [.ventas, .finanzas])
            let hacienda = try #require(delCorreo.first { $0.titulo.contains("Hacienda") })
            #expect(foto.frontmatter(hacienda.ruta).text("origen") == "message://%3Ctriaje-3.requerimiento@agenciatributaria.example%3E")
            #expect(foto.frontmatter(hacienda.ruta).text("creada_por") == "agente:cartero")

            // La respuesta, en borrador y sin enviar, en el hilo del correo.
            let borradores = foto.notes.filter { Borradores.esRutaDeBorrador($0, layout: foto.layout) }
                .compactMap { Borrador.leer($0, texto: foto.text($0) ?? "", layout: foto.layout) }
            let respuesta = try #require(borradores.first { $0.enRespuestaA == ApoyoCorreo.enlace1 })
            #expect(respuesta.ruta.raw.hasPrefix("2 · Ventas/Borradores/"))
            #expect(respuesta.estado == .borrador && respuesta.para == ["lucia.romero@correo.example"])

            // El registro del día en el Buzón: 4 líneas, lo privado sin nada más, el plazo oficial marcado.
            let registro = try #require(e.texto("Buzón/Correo 2026-10.md"))
            #expect(registro.contains("registro: correo") && registro.contains("## 2026-10-19"))
            let lineas = registro.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
            #expect(lineas.count == 4)
            #expect(lineas.contains { $0.contains("correo privado de Expediente privado · — · cliente") })
            #expect(lineas.contains { $0.contains("Requerimiento de información · administración") && $0.contains("PLAZO 2026-10-30") })
            #expect(lineas.contains { $0.hasPrefix("- 17:05 · Lucía Romero <lucia.romero@correo.example> · Precio de la declaración de la Renta · interesado") })
            #expect(!registro.contains("consulta.example"))
            // El plazo oficial, en rojo.
            #expect(e.servicios.avisos.contains { $0.nivel == .rojo && $0.texto.contains("Hacienda") && $0.asistente == "cartero" })

            // Volver a apuntarlo no repite nada; y ya no queda correo por clasificar.
            let otra = await servidor.llamar("tls_anotar_correo", argumentos: ["entradas": .array([.object([
                "mensaje": .string(ApoyoCorreo.enlace1), "tipo": "interesado", "destino": "tarea en Ventas"])])],
                                             contexto: ApoyoCorreo.cartero("r-2"))
            #expect(ApoyoCorreo.objeto(otra)["repetidos"]?.intValue == 1)
            #expect(try #require(e.texto("Buzón/Correo 2026-10.md")) == registro)
            let quedan = await servidor.llamar("tls_correo_pendiente", argumentos: [:], contexto: ApoyoCorreo.cartero("r-3"))
            #expect(ApoyoCorreo.objeto(quedan)["total"]?.intValue == 0)
        }
    }

    @Test("El Cartero solo crea lo nuevo de un correo que conoce: sin enlace, en un área que no lee o cambiando lo que hay, no")
    func limitesDelCartero() async throws {
        try await ApoyoCorreo.conEmpresa { e in
            let s = e.servidor(correo: CorreoEnMemoria(ApoyoCorreo.correosDelTriaje()))
            let c = ApoyoCorreo.cartero()
            // Sin enlace al correo: solo podría en sus áreas (no tiene ninguna fuera del Buzón).
            #expect(await s.llamar("tls_crear_tarea", argumentos: ["titulo": "Algo", "area": "Ventas"], contexto: c).esError)
            // Un correo que la app no conoce.
            #expect(await s.llamar("tls_crear_tarea", argumentos: ["titulo": "Algo", "area": "Ventas",
                                                                   "mensaje": "message://%3Cinventado@x.example%3E"], contexto: c).esError)
            // Un área que no lee (Entrega).
            #expect(await s.llamar("tls_crear_tarea", argumentos: ["titulo": "Algo", "area": "Entrega",
                                                                   "mensaje": .string(ApoyoCorreo.enlace1)], contexto: c).esError)
            // Otro asistente no enlaza correos.
            let comercial = ContextoDelAsistente(ejecucion: "r-c", asistente: "comercial", areas: [.ventas])
            #expect(await s.llamar("tls_crear_tarea", argumentos: ["titulo": "Algo", "area": "Ventas",
                                                                   "mensaje": .string(ApoyoCorreo.enlace1)], contexto: comercial).esError)
            // Con todo bien, sí (y nace «Por hacer» para la persona).
            let bien = await s.llamar("tls_crear_tarea", argumentos: ["titulo": "Contestar a Lucía", "area": "Ventas",
                                                                      "mensaje": .string(ApoyoCorreo.enlace1)], contexto: c)
            #expect(!bien.esError, "\(bien.texto)")
            let ruta = try #require(ApoyoCorreo.objeto(bien)["ruta"]?.stringValue)
            // Pero cambiarla después no es suyo (sigue siendo de Ventas).
            let cambio = await s.llamar("tls_actualizar_tarea", argumentos: ["tarea": .string(ruta), "prioridad": "Alta"], contexto: c)
            #expect(cambio.esError)
            // El Autorizador lo dice igual sin `tls-mcp` de por medio: el Cartero no edita una ficha que ya existe en Ventas.
            let d = e.autorizador.decidir(SolicitudAutorizacion(autor: .agente("cartero"), tipo: .tareaCrear, rutas: [VaultPath(ruta)]))
            #expect(!d.permitido)
        }
    }
}

/// `osascript` (también JXA) falla dentro del perfil de los asistentes. El guion es «1»: no habla con Mail.
@Suite("Mail · sandbox de los asistentes")
struct SandboxJXATests {
    @Test("osascript -l JavaScript dentro de agente.sb → Operation not permitted")
    func jxaDentroDelPerfil() async throws {
        let base = ApoyoCorreo.temporal("tsb")
        defer { try? FileManager.default.removeItem(at: base) }
        let vault = base.appendingPathComponent("vault", isDirectory: true)
        let agente = base.appendingPathComponent("agente", isDirectory: true)
        let run = base.appendingPathComponent("run", isDirectory: true)
        for d in [vault, agente, run] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        let perfil = try SandboxProfileBuilder(deniedRoots: [vault], agentDirectory: agente, runDirectory: run)
            .write(to: base.appendingPathComponent("agente.sb"))
        let texto = try String(contentsOf: perfil, encoding: .utf8)
        #expect(texto.contains(#"(deny process-exec (literal "/usr/bin/osascript"))"#) && texto.contains("(deny appleevent-send)"))
        let out = try await ProcessRunner.run(ProcessSpec(
            executable: SandboxProfileBuilder.sandboxExec,
            arguments: ["-f", perfil.path, "/usr/bin/osascript", "-l", "JavaScript", "-e", "1"],
            environment: ["PATH": "/usr/bin:/bin", "HOME": base.path], directory: "/", timeout: 20))
        #expect(out.status != 0)
        #expect(out.stderrText.contains("Operation not permitted"), "\(out.stderrText)")
        #expect(out.stdoutText.isEmpty)
    }
}
