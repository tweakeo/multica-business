import Darwin
import Foundation
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSIntegracion
import TLSMCPHost
import TLSMCPShared
@testable import TLSUI

/// Apoyo de las pruebas de integración de F4: una copia de Asesoría Ribera (ficticia, `hoy: 2026-10-19`) en un temporal
/// de ruta corta (el socket de `tls-mcp` no pasa de 103 bytes), abierta con su `VaultSession` como en la app y con la
/// integración (`AsistentesDeLaApp`) enganchada. **Nunca se lanza Claude de verdad**: el ejemplo va con
/// `SimulatedRuntime`; una copia, con un `claude` falso (guion de sh) que, si se le pide, arranca el `tls-mcp-dev`
/// compilado como haría Claude Code. Nunca se toca el ejemplo del repositorio.
@MainActor
final class EntornoF4 {
    let base: URL
    let carpeta: URL
    let estado: URL
    let appSupport: URL
    let home: URL
    let model: AppModel
    let entry: VaultEntry
    let app: AsistentesDeLaApp
    let claude: ClaudeFalsoF4
    let reloj: RelojManual
    private(set) var sesion: VaultSession!

    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../..").standardizedFileURL
    }

    static var ribera: URL { repo.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera") }
    static var catalogo: CatalogoAsistentesTLS {
        CatalogoAsistentesTLS(carpetaInstrucciones: CatalogoAsistentesTLS.carpetaDelRepositorio(repo))
    }

    /// Una fecha en Madrid.
    static func fecha(_ dia: Int, _ hora: Int = 9, _ minuto: Int = 30, mes: Int = 10) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = madrid
        return c.date(from: DateComponents(year: 2026, month: mes, day: dia, hour: hora, minute: minuto))!
    }

    /// `tls-mcp-dev` compilado junto a las pruebas.
    static var helper: URL? {
        let args = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        var candidatos = [Bundle(for: ClaudeFalsoF4.self).bundleURL.deletingLastPathComponent(),
                          args.deletingLastPathComponent(), args.deletingLastPathComponent().deletingLastPathComponent()]
        candidatos += Bundle.allBundles.map { $0.bundleURL.deletingLastPathComponent() }
        var dir = args
        for _ in 0..<5 { dir = dir.deletingLastPathComponent(); candidatos.append(dir) }
        for d in candidatos {
            let url = d.appendingPathComponent("tls-mcp-dev")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// - Parameters:
    ///   - clase: `.demo` (Ribera, simulado) o `.copia` (con el `claude` falso o la simulación que diga `runtime`).
    ///   - preparar: cambia ficheros de la copia antes de abrirla (no es la app escribiendo).
    ///   - runtime: el runtime de la copia (por defecto, Claude Code con el `claude` falso).
    init(clase: VaultClass, inicio: Date = EntornoF4.fecha(19), preparar: ((URL) throws -> Void)? = nil,
         localizador: (any LocalizadorDeClaude)? = nil, grabaciones: URL? = nil,
         runtime: (@Sendable (PuertaMCP) -> any AgentRuntime)? = nil,
         conexiones: SistemaDeConexiones? = nil) throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ti-" + String(UUID().uuidString.lowercased().prefix(6)), isDirectory: true)
        carpeta = base.appendingPathComponent("Ribera", isDirectory: true)
        estado = base.appendingPathComponent("e", isDirectory: true)
        appSupport = base.appendingPathComponent("a", isDirectory: true)
        home = base.appendingPathComponent("h", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.copyItem(at: Self.ribera, to: carpeta)
        if clase != .demo {
            let config = carpeta.appendingPathComponent(".tls/config.yaml")
            let texto = try String(contentsOf: config, encoding: .utf8).replacingOccurrences(of: "clase: demo", with: "clase: \(clase.rawValue)")
            try Data(texto.utf8).write(to: config)
        }
        try preparar?(carpeta)
        model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("reg", isDirectory: true)))
        entry = VaultEntry(nombre: "Asesoría Ribera", ruta: carpeta.path, bookmark: nil, clase: clase, escritura: .permitida)
        try model.register(entry)
        claude = ClaudeFalsoF4(dir: base.appendingPathComponent("c", isDirectory: true))
        reloj = RelojManual(inicio)
        let claudeFalso = claude
        let help = ClaudeFalsoF4.help
        let home = self.home
        let fabrica: (@Sendable (PuertaMCP) -> any AgentRuntime)? = clase == .demo ? nil : (runtime ?? { _ in
            ClaudeCodeRuntime(claude: claudeFalso.binario, help: help, home: home, gracia: 5, usarSandbox: false)
        })
        app = AsistentesDeLaApp(opciones: .init(
            localizador: localizador ?? LocalizadorFijo(.listo(binario: claude.binario, ayuda: help, version: "2.1.307")),
            helper: Self.helper, validador: PeerValidator(firma: .sinComprobarFirma), appSupport: appSupport, appBundle: nil,
            catalogo: Self.catalogo, grabaciones: grabaciones ?? GrabacionesDeEjemplo.carpeta, pausaSimulacion: 0, intervalo: 3600,
            home: home, usarSandbox: false, gracia: 5, reloj: reloj, fabricaDeRuntime: localizador == nil ? fabrica : nil,
            conexiones: conexiones))
    }

    /// Abre la empresa como la app (índice, escritor y, con él, los asistentes) y espera a que estén montados.
    func abrir() async throws {
        if model.integracionDeAsistentes == nil { model.integracionDeAsistentes = app }
        let s = VaultSession(entry: entry, estado: estado)
        s.persona = "Manu"
        sesion = s
        await s.start(using: model)
        #expect(s.isReady)
        #expect(s.puedeEscribir)
        try await esperar("motor montado", segundos: 30) { [self] in app.motor(de: s)?.listo == true }
    }

    /// Abre, ejecuta la prueba y lo cierra todo siempre (también si falla): ningún proceso ni temporal queda.
    static func con(clase: VaultClass, inicio: Date = EntornoF4.fecha(19), preparar: ((URL) throws -> Void)? = nil,
                    localizador: (any LocalizadorDeClaude)? = nil, grabaciones: URL? = nil,
                    runtime: (@Sendable (PuertaMCP) -> any AgentRuntime)? = nil, conexiones: SistemaDeConexiones? = nil,
                    abrir: Bool = true, _ cuerpo: (EntornoF4) async throws -> Void) async throws {
        let e = try EntornoF4(clase: clase, inicio: inicio, preparar: preparar, localizador: localizador, grabaciones: grabaciones,
                              runtime: runtime, conexiones: conexiones)
        do {
            if abrir { try await e.abrir() }
            try await cuerpo(e)
        } catch {
            await e.cerrar()
            throw error
        }
        await e.cerrar()
    }

    /// Las grabaciones del ejemplo más las de la prueba (en un temporal propio).
    static func grabaciones(_ extra: [String: [String]] = [:], copias: [String: String] = [:]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tg-" + String(UUID().uuidString.lowercased().prefix(6)))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let origen = try #require(GrabacionesDeEjemplo.carpeta)
        for f in try FileManager.default.contentsOfDirectory(atPath: origen.path) where f.hasSuffix(".jsonl") {
            try FileManager.default.copyItem(at: origen.appendingPathComponent(f), to: dir.appendingPathComponent(f))
        }
        for (nuevo, de) in copias {
            try FileManager.default.copyItem(at: origen.appendingPathComponent(de + ".jsonl"), to: dir.appendingPathComponent(nuevo + ".jsonl"))
        }
        for (nombre, lineas) in extra { try FlujoF4.grabacion(lineas, en: dir, nombre: nombre) }
        return dir
    }

    var motor: MotorDeEmpresa? { sesion.flatMap { app.motor(de: $0) } }
    /// F5 · integración: las conexiones de la empresa abierta (si se montaron).
    var conexiones: ConexionesDeEmpresa? { motor?.conexiones }
    var host: AgentHost? { motor?.host }
    var piezas: PiezasDeLaEmpresa? { motor?.piezas }

    /// Cierra la empresa (para los asistentes antes de soltar el escritor) y borra todo.
    func cerrar() async {
        if let s = sesion {
            await app.escritorSeVa(s)
            s.close()
        }
        await app.desinstalar()
        claude.matarTodo()
        try? await Task.sleep(for: .milliseconds(200))
        // Para mirar qué pasó: TLS_F4_CONSERVAR=1 deja la carpeta temporal.
        if ProcessInfo.processInfo.environment["TLS_F4_CONSERVAR"] == "1" { print("Conservado: \(base.path)"); return }
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: Leer

    func foto() -> VaultSnapshot { VaultSnapshot.read(root: carpeta, layout: nil) }
    func texto(_ p: String) -> String? { try? String(contentsOf: VaultPath(p).url(in: carpeta), encoding: .utf8) }
    func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: VaultPath(p).url(in: carpeta).path) }

    /// La bandeja de Decisiones de F4 (la de Hoy, Decisiones y la insignia).
    func bandeja() throws -> BandejaDeDecisiones {
        let a = try #require(piezas?.autorizador)
        return BandejaDeDecisiones.consultar(LecturaDominio(snapshot: foto()), gobierno: .de(a), estado: a.estado)
    }

    /// Todas las líneas de la Bitácora del mes.
    func bitacora(_ mes: String = "2026-10") -> String { texto("6 · Equipo/Bitácora/\(mes).md") ?? "" }

    /// Espera a que no quede ningún trabajo en marcha ni esperando turno (los que esperan respuesta no cuentan).
    func esperarTrabajos(segundos: Double = 30) async throws {
        let h = try #require(host)
        try await esperar("trabajos terminados", segundos: segundos) {
            let abiertas = await h.ejecuciones(limite: 2000).filter { $0.estado.abierta && $0.estado != .esperandoRespuesta }
            return abiertas.isEmpty
        }
    }

    /// Una tarea de la persona para un asistente (o para ella, con `nil`), como la crearía en la app, con fecha de hoy.
    @discardableResult
    func tareaPara(_ slug: String?, titulo: String, area: AreaCode) async throws -> VaultPath {
        let s = try #require(sesion)
        let f = foto()
        let nota = try TaskStore(snapshot: f, reloj: Reloj.deCarpeta(f)).crear(NuevaTarea(
            titulo: titulo, area: area, responsable: slug.map { "agente:\($0)" } ?? "Manu", estado: .porHacer,
            planificada: LocalDate(year: 2026, month: 10, day: 19)!, origen: "manual", autor: .persona("Manu")))
        let r = try await s.escribir(plan: nota.plan, aviso: "")
        #expect(r.hecho)
        return nota.ruta
    }
}

/// Espera a que se cumpla algo (o falla la prueba).
@MainActor
func esperar(_ que: String, segundos: Double = 10, _ condicion: @MainActor () async -> Bool) async throws {
    let fin = Date().addingTimeInterval(segundos)
    while Date() < fin {
        if await condicion() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    if await condicion() { return }
    Issue.record("No llegó a pasar: \(que)")
    throw ErrorDeEspera.tiempo(que)
}

enum ErrorDeEspera: Error { case tiempo(String) }

/// Procesos vivos cuya línea de órdenes contiene `patron` (como `pgrep -f`).
func procesos(_ patron: String) -> [Int32] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", patron]
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
    let texto = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return texto.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
}

/// El `claude` falso de la integración (sh): apunta argumentos y carpeta de cada llamada, apunta su carpeta de trabajo
/// en `$HOME/.claude-proyectos.txt` (lo que Claude Code apuntaría en `~/.claude.json`), con `con-mcp` arranca el
/// `tls-mcp` de su `mcp.json` como lo haría Claude Code (stdio, con el token por el entorno), escribe `stream-N.jsonl`
/// (o `stream.jsonl`) con la sesión de `--session-id`/`--resume` y, con `colgar`, se queda trabajando 600 s.
final class ClaudeFalsoF4: @unchecked Sendable {
    let dir: URL
    var binario: URL { dir.appendingPathComponent("claude") }

    static let help = ClaudeHelp(options: [
        "-p", "--print", "--output-format", "--input-format", "--verbose", "--session-id", "--resume", "--restricted", "--tools",
        "--disable-slash-commands", "--mcp-config", "--strict-mcp-config", "--allowedTools", "--allowed-tools",
        "--disallowedTools", "--disallowed-tools", "--permission-mode", "--permission-prompts", "--settings",
        "--append-system-prompt", "--append-system-prompt-file", "--model", "--effort", "--max-budget-usd",
    ])

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let guion = """
        #!/bin/sh
        D='\(dir.path)'
        N=$(cat "$D/contador" 2>/dev/null || echo 0); N=$((N+1)); echo $N > "$D/contador"
        printf '%s\\n' "$@" > "$D/argv-$N.txt"
        pwd > "$D/cwd-$N.txt"
        echo "$(pwd)" >> "$HOME/.claude-proyectos.txt"
        SES=""; PREV=""; MCP=""
        for A in "$@"; do
          if [ "$PREV" = "--session-id" ] || [ "$PREV" = "--resume" ]; then SES="$A"; fi
          if [ "$PREV" = "--mcp-config" ]; then MCP="$A"; fi
          PREV="$A"
        done
        if [ -f "$D/con-mcp" ] && [ -n "$MCP" ]; then
          CMD=$(/usr/bin/plutil -extract mcpServers.tls.command raw -o - "$MCP")
          SOCK=$(/usr/bin/plutil -extract mcpServers.tls.args.1 raw -o - "$MCP")
          TOK=$(/usr/bin/plutil -extract mcpServers.tls.env.TLS_MCP_TOKEN raw -o - "$MCP")
          ( /bin/sleep 600 | TLS_MCP_TOKEN="$TOK" "$CMD" --socket "$SOCK" > "$D/mcp-$N.log" 2>&1 ) &
        fi
        head -n 1 > "$D/stdin-$N.txt"
        S="$D/stream-$N.jsonl"; [ -f "$S" ] || S="$D/stream.jsonl"
        [ -f "$S" ] && sed "s/__SESION__/$SES/g" "$S"
        if [ -f "$D/colgar" ]; then /bin/sleep 600; fi
        exit 0

        """
        try! Data(guion.utf8).write(to: binario)
        chmod(binario.path, 0o755)
    }

    func stream(_ lineas: [String], llamada: Int? = nil) {
        let nombre = llamada.map { "stream-\($0).jsonl" } ?? "stream.jsonl"
        try! Data((lineas.joined(separator: "\n") + "\n").utf8).write(to: dir.appendingPathComponent(nombre))
    }

    func marcar(_ nombre: String) { try? Data().write(to: dir.appendingPathComponent(nombre)) }
    func quitar(_ nombre: String) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(nombre)) }

    var llamadas: Int {
        (try? String(contentsOf: dir.appendingPathComponent("contador"), encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    }

    func argv(_ n: Int) -> [String] {
        ((try? String(contentsOf: dir.appendingPathComponent("argv-\(n).txt"), encoding: .utf8)) ?? "")
            .components(separatedBy: "\n").dropLast().map { $0 }
    }

    func valor(_ flag: String, llamada n: Int) -> String? {
        let a = argv(n)
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// Por si una prueba falla a medias: nada de este `claude` falso queda vivo.
    func matarTodo() {
        for pid in procesos(dir.path) { kill(pid, SIGKILL) }
    }
}

/// Líneas de `stream-json` como las de Claude Code 2.1.307.
enum FlujoF4 {
    static func json(_ o: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func inicio(sesion: String = "__SESION__") -> String {
        json(["type": "system", "subtype": "init", "session_id": sesion, "tools": ["mcp__tls__tls_estado", "mcp__tls__tls_crear_tarea",
                                                                                 "mcp__tls__tls_finalizar"],
              "mcp_servers": [["name": "tls", "status": "connected"]], "permissionMode": "dontAsk",
              "apiKeySource": "none", "claude_code_version": "2.1.307", "model": "claude-haiku-4-5", "plugins": [] as [Any]])
    }

    static func texto(_ t: String) -> String {
        json(["type": "assistant", "session_id": "__SESION__",
              "message": ["role": "assistant", "content": [["type": "text", "text": t]]] as [String: Any]])
    }

    static func herramienta(_ nombre: String, id: String, entrada: [String: Any] = [:]) -> String {
        json(["type": "assistant", "session_id": "__SESION__",
              "message": ["role": "assistant", "content": [["type": "tool_use", "id": id, "name": "mcp__tls__" + nombre,
                                                              "input": entrada] as [String: Any]]] as [String: Any]])
    }

    static func resultadoHerramienta(id: String, texto: String) -> String {
        json(["type": "user", "session_id": "__SESION__",
              "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "is_error": false,
                                                         "content": [["type": "text", "text": texto]]] as [String: Any]]] as [String: Any]])
    }

    static func resultado(_ texto: String = "hecho", subtipo: String = "success", error: Bool = false, coste: Double = 0.02) -> String {
        json(["type": "result", "subtype": subtipo, "is_error": error, "result": texto, "total_cost_usd": coste, "num_turns": 2,
              "session_id": "__SESION__"])
    }

    /// Una grabación para `SimulatedRuntime` (cada `tool_use` se ejecuta de verdad por el servidor de herramientas).
    static func grabacion(_ lineas: [String], en dir: URL, nombre: String) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data((lineas.joined(separator: "\n") + "\n").utf8).write(to: dir.appendingPathComponent(nombre + ".jsonl"))
    }
}
