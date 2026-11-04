import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// Lanzamiento exacto de Claude Code (PLAN §5.3), sesiones, preguntas y reanudación, con un `claude` falso.
@Suite("Motor · lanzamiento exacto, sesiones y preguntas", .serialized)
struct LanzamientoTests {
    func disparo(_ ruta: VaultPath, agente: String = "comercial") -> Disparo {
        Disparo.tareaLista(id: ruta.raw, ruta: ruta, hash: Disparo.huella("\(UUID())"), agente: agente, titulo: ruta.stem)
    }

    @Test("Argumentos, entorno, carpeta y ficheros de la ejecución son los del PLAN")
    func lanzamientoExacto() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let t = e.tarea(1, titulo: "Llamar")
        let cola = try e.cola()
        let ej = try #require(try await cola.encolar(disparo(t)))
        await cola.procesar()
        let a = e.claude.argv(1)
        let paths = try AgentPaths(vaultState: e.estadoDir, slug: "comercial", runID: ej.id)
        func tras(_ f: String) -> String? { e.claude.valor(f, llamada: 1) }
        #expect(a.first == "-p")
        #expect(tras("--output-format") == "stream-json")
        #expect(tras("--input-format") == "stream-json")
        #expect(a.contains("--verbose"))
        #expect(tras("--session-id").flatMap(UUID.init(uuidString:)) != nil)
        #expect(!a.contains("--resume"))
        #expect(a.contains("--restricted"))
        #expect(tras("--tools") == "")
        #expect(a.contains("--disable-slash-commands"))
        #expect(tras("--mcp-config") == paths.mcpConfig.path)
        #expect(a.contains("--strict-mcp-config"))
        #expect(tras("--allowedTools") == "mcp__tls")
        #expect(tras("--disallowedTools") == "Bash,Read,Edit,Write,NotebookEdit,Glob,Grep,WebFetch,WebSearch,Task,AskUserQuestion")
        #expect(tras("--permission-mode") == "dontAsk")
        #expect(tras("--permission-prompts") == "none")
        #expect(tras("--settings") == paths.settings.path)
        // El brief: con `--append-system-prompt-file` si esta versión lo tiene; si no (2.1.307), su texto.
        let ficheros = try FileManager.default.contentsOfDirectory(atPath: paths.agentDirectory.path).filter { $0.hasPrefix("brief-") }
        #expect(ficheros.count == 1)
        let textoBrief = try String(contentsOf: paths.agentDirectory.appendingPathComponent(ficheros[0]), encoding: .utf8)
        if let fichero = tras("--append-system-prompt-file") {
            #expect(fichero == paths.agentDirectory.appendingPathComponent(ficheros[0]).path)
        } else {
            let enLinea = try #require(tras("--append-system-prompt"))
            #expect(enLinea.hasPrefix(textoBrief.components(separatedBy: "\n").first ?? "x"))
            #expect(textoBrief.contains(enLinea.components(separatedBy: "\n").first ?? "x"))
        }
        #expect(tras("--max-budget-usd") == "0.5000")
        for nunca in ["--max-turns", "--dangerously-skip-permissions", "bypassPermissions"] { #expect(!a.contains(nunca)) }
        // `cwd` estable del asistente y entorno mínimo sin clave de API.
        #expect(SandboxProfileBuilder.realPath(e.claude.texto("cwd-1.txt").trimmingCharacters(in: .whitespacesAndNewlines))
                == SandboxProfileBuilder.realPath(paths.agentDirectory.path))
        let env = Set(e.claude.texto("env-1.txt").components(separatedBy: "\n").compactMap { $0.split(separator: "=").first.map(String.init) })
        #expect(!env.contains("ANTHROPIC_API_KEY"))
        for k in ["PATH", "HOME", "USER", "LANG", "TMPDIR", "DISABLE_AUTOUPDATER", "CLAUDE_CODE_DISABLE_CLAUDE_MDS",
                  "CLAUDE_CODE_DISABLE_AUTO_MEMORY", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] { #expect(env.contains(k), "\(k)") }
        #expect(e.claude.texto("env-1.txt").contains("TMPDIR=" + paths.tmp.path))
        // Ficheros de la ejecución.
        let mcp = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.mcpConfig)) as? [String: Any]
        #expect(((mcp?["mcpServers"] as? [String: Any])?.keys).map(Array.init) == ["tls"])
        let settings = try String(contentsOf: paths.settings, encoding: .utf8)
        #expect(settings.contains("\"disableAllHooks\" : true") && settings.contains("dontAsk"))
        #expect(try String(contentsOf: paths.runDirectory.appendingPathComponent("token"), encoding: .utf8).count == 64)
        let perfil = try String(contentsOf: paths.profile, encoding: .utf8)
        #expect(perfil.contains(SandboxProfileBuilder.realPath(e.raiz.path)))
        // El primer mensaje lleva lo variable.
        let stdin = try JSONSerialization.jsonObject(with: Data(e.claude.texto("stdin-1.txt").utf8)) as? [String: Any]
        #expect(stdin?["type"] as? String == "user")
        let contenido = try #require((stdin?["message"] as? [String: Any])?["content"] as? String)
        #expect(contenido.hasPrefix("Trabajo:") && contenido.contains(t.raw))
        // Contexto del token.
        let c = try #require(e.puerta.abiertas.first)
        #expect(c.agente == "comercial" && c.areas == [.ventas] && c.tarea == t && c.profundidad == 0 && !c.simulado)
    }

    @Test("Preflight: sin un flag prescindible se lanza sin él; sin uno imprescindible no se lanza")
    func preflight() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        var opciones = EntornoMotor.help.options
        opciones.remove("--disable-slash-commands")
        let sinBarra = ClaudeCodeRuntime(claude: e.claude.binario, help: ClaudeHelp(options: opciones), home: Apoyo.home)
        let cola = try e.cola(runtime: sinBarra)
        let uno = try #require(try await cola.encolar(disparo(e.tarea(1, titulo: "Uno"))))
        await cola.procesar()
        #expect(try e.estado().ejecucion(uno.id)?.estado == .completada)
        #expect(!e.claude.argv(1).contains("--disable-slash-commands"))
        opciones.remove("--strict-mcp-config")
        let sinEstricto = ClaudeCodeRuntime(claude: e.claude.binario, help: ClaudeHelp(options: opciones), home: Apoyo.home)
        let cola2 = try e.cola(runtime: sinEstricto)
        let dos = try #require(try await cola2.encolar(disparo(e.tarea(2, titulo: "Dos"))))
        await cola2.procesar()
        let x = try #require(try e.estado().ejecucion(dos.id))
        #expect(x.estado == .fallida && x.motivo == .flagsAusentes)
        #expect(e.claude.llamadas == 1)
    }

    @Test("Sesión: se reanuda mientras el brief no cambia; con otro brief, sesión nueva")
    func sesionYBrief() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream(Flujo.exito())
        let cola = try e.cola()
        _ = try await cola.encolar(disparo(e.tarea(1, titulo: "Uno")))
        await cola.procesar()
        let s1 = try #require(e.claude.valor("--session-id", llamada: 1))
        _ = try await cola.encolar(disparo(e.tarea(2, titulo: "Dos")))
        await cola.procesar()
        #expect(e.claude.valor("--resume", llamada: 2) == s1)
        // Cambian las instrucciones del rol: otra huella, sesión nueva.
        var roles = EntornoMotor.catalogo.roles
        roles[1].instrucciones += "\nNueva regla."
        let otra = try e.cola(catalogo: CatalogoFijo(roles))
        _ = try await otra.encolar(disparo(e.tarea(3, titulo: "Tres")))
        await otra.procesar()
        let s3 = try #require(e.claude.valor("--session-id", llamada: 3))
        #expect(s3 != s1)
        let ficheros = try FileManager.default.contentsOfDirectory(
            atPath: try AgentPaths(vaultState: e.estadoDir, slug: "comercial", runID: "x").agentDirectory.path).filter { $0.hasPrefix("brief-") }
        #expect(ficheros.count == 2)
    }

    @Test("tls_preguntar deja el trabajo esperando; al contestar se reanuda la misma sesión y hay otra entrada (criterio 6)")
    func preguntaYRespuesta() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let pregunta = "2 · Ventas/Tareas/t-0009-pregunta-precio.md"
        e.claude.stream([Flujo.inicio(), Flujo.herramienta("tls_preguntar", id: "p1", entrada: ["titulo": "¿Qué precio?"]),
                         Flujo.resultadoHerramienta(id: "p1", texto: "{\"ruta\":\"\(pregunta)\",\"id\":\"q-1\"}"),
                         Flujo.herramienta("tls_finalizar", id: "f1", entrada: ["resumen": "Necesito saber el precio."]),
                         Flujo.resultadoHerramienta(id: "f1", texto: "{}"), Flujo.resultado("Pregunta hecha.")], llamada: 1)
        e.claude.stream(Flujo.exito("Preparé la propuesta con ese precio."), llamada: 2)
        let t = e.tarea(1, titulo: "Propuesta")
        let estado = try e.estado()
        let cola = try e.cola(estado: estado)
        let ej = try #require(try await cola.encolar(disparo(t)))
        await cola.procesar()
        var x = try #require(try estado.ejecucion(ej.id))
        #expect(x.estado == .esperandoRespuesta)
        #expect(x.pregunta == pregunta)
        #expect(e.registro.cierres.last?.estado == .esperandoRespuesta)
        let sesion = try #require(e.claude.valor("--session-id", llamada: 1))
        // Contesta Manu.
        let respuesta = try #require(try await cola.responder(ejecucion: ej.id, texto: "150 € (precio de la Oferta)."))
        await cola.procesar()
        #expect(e.claude.valor("--resume", llamada: 2) == sesion)
        #expect(e.claude.texto("stdin-2.txt").contains("150 € (precio de la Oferta)."))
        let r = try #require(try estado.ejecucion(respuesta.id))
        #expect(r.estado == .completada)
        #expect(r.tarea == t)
        x = try #require(try estado.ejecucion(ej.id))
        #expect(x.estado == .completada)
        #expect(e.registro.cierres.filter { $0.tarea == t }.count == 2)
        // El token de la respuesta lleva el origen de la pregunta (para `tls_registrar_decision`).
        #expect(e.puerta.abiertas.last?.origen == "pregunta:" + pregunta)
    }

    @Test("Reanudación rechazada: sesión nueva con el resumen de la anterior, una sola vez")
    func reanudacionRechazada() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.claude.stream([Flujo.inicio(), Flujo.herramienta("tls_preguntar", id: "p1"),
                         Flujo.resultadoHerramienta(id: "p1", texto: "{\"ruta\":\"2 · Ventas/Tareas/t-0009-p.md\"}"),
                         Flujo.resultado("Te pregunto el precio.")], llamada: 1)
        // Al reanudar, el CLI abre otra sesión (otro session_id): se rechaza.
        e.claude.stream([Flujo.inicio(sesion: "11111111-2222-4333-8444-555555555555"), Flujo.resultado()], llamada: 2)
        e.claude.stream(Flujo.exito("Seguí con la sesión nueva."), llamada: 3)
        let estado = try e.estado()
        let cola = try e.cola(estado: estado)
        let ej = try #require(try await cola.encolar(disparo(e.tarea(1, titulo: "Propuesta"))))
        await cola.procesar()
        let r = try #require(try await cola.responder(ejecucion: ej.id, texto: "150 €"))
        await cola.procesar()
        #expect(e.claude.llamadas == 3)
        #expect(e.claude.valor("--resume", llamada: 2) != nil)
        let nueva = try #require(e.claude.valor("--session-id", llamada: 3))
        #expect(nueva != e.claude.valor("--resume", llamada: 2))
        #expect(e.claude.texto("stdin-3.txt").contains("No se pudo recuperar la conversación anterior"))
        #expect(e.claude.texto("stdin-3.txt").contains("Te pregunto el precio."))
        #expect(try estado.ejecucion(r.id)?.estado == .completada)
    }
}
