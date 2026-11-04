import Foundation
import MCP
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSIntegracion
import TLSMCPHost
import TLSOnboarding
@testable import TLSUI

/// La integración de F4 en la app: al abrir una copia o el ejemplo arrancan sus asistentes (cola, planificador y
/// servidor de herramientas); al cerrar, al pasar a solo lectura o al salir, se para todo. Sin Claude en una copia,
/// se explica cómo conectarlo. La puesta en marcha (paso 4) y Ajustes dejan listos los asistentes de serie. En una copia
/// hecha por la app, «Crear una carpeta privada». Sin Claude de verdad.
@Suite("F4 · integración: ciclo de vida, puesta en marcha y carpeta privada", .serialized)
@MainActor
struct CicloDeVidaTests {

    @Test("El ejemplo: al abrirlo arrancan sus asistentes simulados (socket, ⌘J y pantallas); al cerrarlo se para todo")
    func ejemploAbrirYCerrar() async throws {
        let e = try EntornoF4(clase: .demo)
        do {
            try await e.abrir()
            let sesion = try #require(e.sesion)
            let m = try #require(e.motor)
            #expect(m.simulado)
            #expect(m.claude == nil, "el ejemplo no busca Claude Code")
            let host = try #require(m.host)
            #expect(host.configuracion.runtime.simulado)
            let socket = try #require(m.puerta?.host.socket)
            #expect(FileManager.default.fileExists(atPath: socket.path))
            #expect(m.puerta?.host.enMarcha == true)
            // Las pantallas ven el mismo motor y el mismo estado en vivo; ⌘J habla con la simulación.
            let conexion = try #require(RegistroDeAsistentes.compartido.conexion(de: sesion))
            #expect(conexion.host === host)
            #expect(conexion.sinMotor == nil)
            #expect(AsistentesDeLaEmpresa.de(sesion).fabricaDeChat != nil)
            // El Autorizador es uno: el del bus, el de Decisiones y el del servidor de herramientas.
            #expect(sesion.bus?.autorizador === m.piezas.autorizador)
            #expect(sesion.autorizadorDeLaCarpeta() === m.piezas.autorizador)
            // ⌘J con Mika, simulado y con la marca.
            let fabrica = try #require(AsistentesDeLaEmpresa.de(sesion).fabricaDeChat)
            let chat = fabrica()
            let r = await chat.enviar("¿Qué tengo hoy?", pantalla: "Hoy")
            #expect(r.simulado)
            #expect(!r.texto.isEmpty)

            // Pasar a solo lectura para los asistentes antes de soltar el escritor.
            await sesion.pasarASoloLectura(using: e.model)
            #expect(e.motor == nil)
            #expect(!FileManager.default.fileExists(atPath: socket.path))
            #expect(RegistroDeAsistentes.compartido.conexion(de: sesion) == nil)
            #expect(AsistentesDeLaEmpresa.de(sesion).fabricaDeChat == nil)
            // Y al volver a permitir cambios, vuelven.
            await sesion.permitirCambios(using: e.model)
            try await esperar("vuelven los asistentes", segundos: 30) { e.motor?.listo == true && e.motor?.host != nil }
            let socket2 = try #require(e.motor?.puerta?.host.socket)
            #expect(FileManager.default.fileExists(atPath: socket2.path))

            // Al cerrar la empresa (como la ventana): se para todo y no queda ningún tls-mcp.
            sesion.close()
            try await esperar("todo parado al cerrar", segundos: 15) {
                e.app.motor(de: sesion) == nil && !FileManager.default.fileExists(atPath: socket2.path)
            }
            #expect(procesos(socket2.path).isEmpty)
        } catch {
            await e.cerrar()
            throw error
        }
        await e.cerrar()
    }

    @Test("Una copia sin Claude Code: no hay motor, ⌘J usa el enrutador y Asistentes explica cómo conectarlo")
    func copiaSinClaude() async throws {
        for (claude, debe) in [(ClaudeDisponible.noEncontrado, "no lo encuentro"), (.sinSesion(version: "2.1.307"), "sin la sesión iniciada")] {
            try await EntornoF4.con(clase: .copia, inicio: CriteriosF4Tests.domingo, localizador: LocalizadorFijo(claude)) { e in
                let sesion = try #require(e.sesion)
                let m = try #require(e.motor)
                #expect(m.host == nil)
                #expect(m.puerta == nil)
                let conexion = try #require(RegistroDeAsistentes.compartido.conexion(de: sesion))
                #expect(conexion.host == nil)
                let motivo = try #require(conexion.sinMotor)
                #expect(motivo.contains(debe))
                #expect(motivo.contains("Buscar otra vez"))
                #expect(conexion.reintentar != nil)
                #expect(AsistentesDeLaEmpresa.de(sesion).fabricaDeChat == nil, "sin Claude, ⌘J contesta el enrutador de la app")
                // Una acción rápida dice por qué no se puede.
                #expect(PedirAAsistente.motivo(sesion) == "Falta Claude Code en este Mac: mira Asistentes.")
                #expect(PedirAAsistente.motivo(sesion, slug: "marca") == "5 · Marca está preparada: su asistente empezará cuando la actives.")
                // Sin motor no hay socket.
                let sockets = (try? FileManager.default.contentsOfDirectory(atPath: e.appSupport.appendingPathComponent("s").path)) ?? []
                #expect(sockets.isEmpty)
            }
        }
    }

    @Test("Una copia con Claude Code: el motor lanza Claude en su caja (orden exacta) y nunca con la clave de la API")
    func copiaConClaude() async throws {
        try await EntornoF4.con(clase: .copia, inicio: CriteriosF4Tests.domingo, abrir: false) { e in
            e.claude.stream([FlujoF4.inicio(), FlujoF4.resultado("Listo.")])
            try await e.abrir()
            let host = try #require(e.host)
            #expect(!host.configuracion.runtime.simulado)
            let ej = try #require(try await host.pedir(a: "mika", instruccion: "Mira el día"))
            try await e.esperarTrabajos()
            #expect(await host.ejecuciones().first { $0.id == ej.id }?.estado == .completada)
            let argv = e.claude.argv(1)
            for f in ["--restricted", "--strict-mcp-config", "--disable-slash-commands"] { #expect(argv.contains(f)) }
            #expect(e.claude.valor("--tools", llamada: 1) == "")
            #expect(e.claude.valor("--allowedTools", llamada: 1) == "mcp__tls")
            #expect(e.claude.valor("--permission-mode", llamada: 1) == "dontAsk")
            #expect(!argv.contains("--dangerously-skip-permissions") && !argv.contains("bypassPermissions"))
            let mcp = try String(contentsOf: URL(fileURLWithPath: try #require(e.claude.valor("--mcp-config", llamada: 1))), encoding: .utf8)
            #expect(mcp.contains("\"tls\""))
            #expect(mcp.contains(try #require(e.motor?.puerta?.host.socket.path)))
        }
    }

    @Test("Paso 4 de la puesta en marcha: deja la sección de los asistentes y sus fichas en el mismo plan; no pisa nada")
    func pasoCuatro() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tp-" + String(UUID().uuidString.prefix(6)))
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Ribera")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: EntornoF4.ribera, to: root)
        // Una copia de antes de F4: sin asistentes en la configuración ni fichas de asistente.
        let url = root.appendingPathComponent(".tls/config.yaml")
        let t = try String(contentsOf: url, encoding: .utf8)
        try Data(String(t[..<(try #require(t.range(of: "# Asistentes:"))).lowerBound]).utf8).write(to: url)
        let roles = root.appendingPathComponent("6 · Equipo/Roles")
        for f in try FileManager.default.contentsOfDirectory(atPath: roles.path) where f.hasPrefix("asistente-") {
            try FileManager.default.removeItem(at: roles.appendingPathComponent(f))
        }
        var m = OnboardingEngine(estado: EstadoPuestaEnMarcha(vaultID: UUID()), contexto: ContextoCarpeta.leer(root))
        // Sin proveedor (F3): el paso 4 no escribe asistentes.
        let sin = try m.vistaPrevia(.sinTi)
        #expect(!(sin.cambios.contains { $0.ruta.raw == ".tls/config.yaml" && ($0.despues ?? "").contains("agentes:") }))
        // Con el de la app (TLSOnboarding lo pone en `ModeloPuesta`): Ventas activa, Marca preparada, Equipo en reposo.
        let modelo = ModeloPuesta(motor: m)
        m = modelo.motor
        #expect(m.asistentes != nil)
        await m.responder(PreguntaID.estadoArea(.marca), .opcion("preparada"))
        await m.responder(PreguntaID.estadoArea(.equipo), .opcion("en reposo"))
        let v = try m.vistaPrevia(.sinTi)
        let config = try #require(v.cambios.first { $0.ruta.raw == ".tls/config.yaml" }?.despues)
        #expect(config.contains("agentes:"))
        #expect(config.contains("interruptor: encendido"))
        let ajustes = AjustesDeAsistentes.leer(yaml: config)
        #expect(ajustes.agente("mika")?.activo == true)
        #expect(ajustes.agente("marca")?.activo == false, "Marca está preparada")
        #expect(ajustes.agente("equipo")?.activo == false, "Equipo está en reposo")
        // Lo que ya había sigue igual (nunca quita nada).
        for l in t[..<(t.range(of: "# Asistentes:")!.lowerBound)].split(separator: "\n") { #expect(config.contains(l)) }
        let fichas = v.cambios.filter { $0.ruta.raw.hasPrefix("6 · Equipo/Roles/asistente-") }
        #expect(fichas.count == 8)
        #expect(fichas.allSatisfy { $0.clase == .crear })
        // Todo en el plan de la persona (un solo Deshacer).
        let plan = try #require(v.plan)
        #expect(plan.autor.esPersona)
    }

    @Test("Ajustes › Asistentes deja listos los asistentes de serie en una copia de antes de F4, como la persona y con Deshacer")
    func ajustesDejanListos() async throws {
        try await EntornoF4.con(clase: .copia, inicio: CriteriosF4Tests.domingo, preparar: { root in
            let url = root.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: url, encoding: .utf8)
            try Data(String(t[..<(try #require(t.range(of: "# Asistentes:"))).lowerBound]).utf8).write(to: url)
        }) { e in
            let cambios = AsistentesDeSerie.cambios(root: e.carpeta, semilla: e.entry.id.uuidString.lowercased())
            #expect(FilaAsistentesDeSerie.resumen(cambios) == "Añade los asistentes a la configuración de la carpeta.")
            let sesion = try #require(e.sesion)
            let plan = try #require(AsistentesDeSerie.plan(root: e.carpeta, persona: sesion.persona))
            let r = try await sesion.escribir(plan: plan, aviso: "Asistentes de serie listos")
            #expect(r.hecho)
            #expect(AsistentesDeSerie.cambios(root: e.carpeta).isEmpty, "idempotente: nada más que añadir")
            // Lo escrito por la app queda confirmado: no sale la tarjeta de «permisos cambiados fuera de la app».
            #expect(try #require(e.piezas).autorizador.estadoDeConfig().cambiadaFuera == false)
            await sesion.deshacer(plan: r.planID)
            #expect(!(e.texto(".tls/config.yaml") ?? "").contains("agentes:"))
            // Deshacer lo que escribió la app tampoco parece un cambio hecho fuera (el bus vuelve a confirmar).
            #expect(try #require(e.piezas).autorizador.estadoDeConfig().cambiadaFuera == false)
        }
    }

    @Test("«Crear una carpeta privada» en una copia: la crea, la marca en privado (como la persona) y ningún asistente la ve")
    func carpetaPrivada() async throws {
        try await EntornoF4.con(clase: .copia, inicio: CriteriosF4Tests.domingo) { e in
            let sesion = try #require(e.sesion)
            #expect(sesion.carpetasPrivadas.isEmpty)
            #expect(throws: CarpetaPrivadaNueva.Fallo.yaExiste("Buzón")) {
                _ = try CarpetaPrivadaNueva.plan(nombre: "Buzón", root: e.carpeta, persona: "Manu")
            }
            let carpeta = try #require(await sesion.crearCarpetaPrivada(nombre: "Privado"))
            #expect(carpeta.raw == "Privado")
            #expect(e.existe("Privado/Léeme.md"))
            let config = try #require(e.texto(".tls/config.yaml"))
            #expect(config.contains("privado:\n  - Privado") || config.contains("privado:\n  - \"Privado\""))
            try await esperar("el índice lo ve privado", segundos: 10) { sesion.carpetasPrivadas.contains(carpeta) }
            #expect(sesion.esPrivado(VaultPath("Privado/Léeme.md")))
            // Para un asistente, no existe.
            let servidor = try #require(e.motor?.servidor)
            let c = ContextoDelAsistente(ejecucion: "r-privado", asistente: "mika", coordinador: true, areas: [.direccion],
                                         leeAreas: AreaCode.allCases)
            let r = await servidor.llamar("tls_leer", argumentos: ["ruta": .string("Privado/Léeme.md")], contexto: c)
            #expect(r.esError && r.texto.lowercased().contains("no encontrad"))
            // Las tareas personales de Multica ya tienen dónde ir.
            let foto = try #require(await sesion.instantanea())
            #expect(foto.layout.privado.contains(carpeta))
        }
    }

    @Test("Cambiar un asistente con el editor de la configuración no pierde «el día 5 de cada mes» ni «solo si hay rojo»")
    func editorConservaRutinas() throws {
        let texto = try String(contentsOf: EntornoF4.ribera.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
        var contable = try #require(ConfigAgentes.leer(yaml: texto).asistente("contable"))
        contable.activo = false
        let r = try EditorConfigAgentes.texto(poner: contable, en: texto)
        #expect(r.contains("dia_mes: 5"))
        #expect(r.contains("meses: [1, 4, 7, 10]"))
        #expect(r.contains("solo_si_rojo: true"), "lo de Mika sigue igual")
        #expect(ConfigAgentes.leer(yaml: r).asistente("contable")?.activo == false)
        // Si cambian sus rutinas y llevan claves que el editor no conoce, no escribe nada antes que perderlas.
        var otra = contable
        otra.rutinas = Array(otra.rutinas.prefix(1))
        #expect(throws: ErrorDeGobierno.configIlegible) { _ = try EditorConfigAgentes.texto(poner: otra, en: texto) }
    }

    @Test("Las herramientas de tls-mcp y las de los perfiles de los asistentes son las mismas 31")
    func catalogosAtados() {
        let delServidor = Set(CatalogoTLS.definiciones.map(\.nombre))
        let deLosPerfiles = Set(HerramientaDeAsistente.allCases.map(\.rawValue))
        #expect(delServidor == deLosPerfiles)
        // F5 · mail: 31 con `tls_anotar_correo` (solo el Cartero).
        #expect(delServidor.count == 31)
        // Cada perfil de serie solo pide herramientas que el servidor tiene.
        for p in PerfilDeAsistente.deSerie { #expect(Set(p.herramientas.map(\.rawValue)).isSubset(of: delServidor), "\(p.slug)") }
    }

    @Test("Los hitos del tutorial «⌘J», «pausar y reanudar» y «aprobar la propuesta de Mika» ya se hacen de verdad")
    func tutorial() {
        #expect(HitoTutorial.allCases.allSatisfy { !$0.llegaConLosAsistentes })
        #expect(HitoTutorial.disponibles.count == 10)
        #expect(HitoRecorrido.allCases.allSatisfy { !$0.llegaConLosAsistentes })
        #expect(TutorialEvent.propuestaAprobada.parte == "propuesta")
        #expect(TutorialEvent.asistenteAbierto.parte == "asistente")
    }
}
