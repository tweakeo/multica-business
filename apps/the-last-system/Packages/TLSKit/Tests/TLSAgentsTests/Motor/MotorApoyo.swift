import Darwin
import Foundation
import TLSCore
@testable import TLSAgents

/// Un `claude` falso (guion de sh) que hace de Claude Code en las pruebas: **nunca se lanza Claude de verdad**.
///
/// En cada llamada N apunta sus argumentos (`argv-N.txt`), su carpeta (`cwd-N.txt`), su entorno (`env-N.txt`) y la
/// primera línea de su entrada (`stdin-N.txt`); después escribe `stream-N.jsonl` (o `stream.jsonl`) cambiando
/// `__SESION__` por la sesión de `--session-id`/`--resume`, y sale con `salida-N` (o `salida`, o 0). Con `colgar-N`
/// (o `colgar`) se queda dormido 600 s; con `terco`, además ignora SIGTERM (solo lo para SIGKILL).
final class ClaudeFalso: @unchecked Sendable {
    let dir: URL
    var binario: URL { dir.appendingPathComponent("claude") }

    init() {
        dir = Apoyo.tempDir("tls-claude-falso")
        let guion = """
        #!/bin/sh
        D='\(dir.path)'
        N=$(cat "$D/contador" 2>/dev/null || echo 0); N=$((N+1)); echo $N > "$D/contador"
        printf '%s\\n' "$@" > "$D/argv-$N.txt"
        pwd > "$D/cwd-$N.txt"
        env > "$D/env-$N.txt"
        SES=""; PREV=""
        for A in "$@"; do
          if [ "$PREV" = "--session-id" ] || [ "$PREV" = "--resume" ]; then SES="$A"; fi
          PREV="$A"
        done
        if [ -f "$D/terco" ]; then trap '' TERM; fi
        head -n 1 > "$D/stdin-$N.txt"
        S="$D/stream-$N.jsonl"; [ -f "$S" ] || S="$D/stream.jsonl"
        [ -f "$S" ] && sed "s/__SESION__/$SES/g" "$S"
        if [ -f "$D/colgar-$N" ] || [ -f "$D/colgar" ]; then sleep 600; fi
        C=0; [ -f "$D/salida" ] && C=$(cat "$D/salida"); [ -f "$D/salida-$N" ] && C=$(cat "$D/salida-$N")
        exit $C

        """
        try! Data(guion.utf8).write(to: binario)
        chmod(binario.path, 0o755)
    }

    /// Stream para todas las llamadas (o solo la N).
    func stream(_ lineas: [String], llamada: Int? = nil) {
        let nombre = llamada.map { "stream-\($0).jsonl" } ?? "stream.jsonl"
        try! Data((lineas.joined(separator: "\n") + "\n").utf8).write(to: dir.appendingPathComponent(nombre))
    }

    func marcar(_ nombre: String, _ contenido: String = "") {
        try! Data(contenido.utf8).write(to: dir.appendingPathComponent(nombre))
    }

    func quitar(_ nombre: String) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(nombre)) }

    /// Veces que se ha llamado.
    var llamadas: Int {
        (try? String(contentsOf: dir.appendingPathComponent("contador"), encoding: .utf8))
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
    }

    func argv(_ n: Int) -> [String] {
        ((try? String(contentsOf: dir.appendingPathComponent("argv-\(n).txt"), encoding: .utf8)) ?? "")
            .components(separatedBy: "\n").dropLast().map { $0 }
    }

    func texto(_ nombre: String) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(nombre), encoding: .utf8)) ?? ""
    }

    /// Valor que sigue a un flag en la llamada N.
    func valor(_ flag: String, llamada n: Int) -> String? {
        let a = argv(n)
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    func limpiar() { Apoyo.limpiar(dir) }
}

/// Líneas de `stream-json` para las pruebas (como las de Claude Code 2.1.307).
enum Flujo {
    static func json(_ o: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    static func inicio(sesion: String = "__SESION__", herramientas: [String] = [], servidores: [String] = ["tls"],
                       modo: String = "dontAsk") -> String {
        json(["type": "system", "subtype": "init", "session_id": sesion, "tools": herramientas,
              "mcp_servers": servidores.map { ["name": $0, "status": "connected"] }, "permissionMode": modo,
              "apiKeySource": "none", "claude_code_version": "2.1.307", "model": "claude-haiku-5-5", "plugins": [] as [Any]])
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

    static func resultadoHerramienta(id: String, texto: String, error: Bool = false) -> String {
        json(["type": "user", "session_id": "__SESION__",
              "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": id, "is_error": error,
                                                         "content": [["type": "text", "text": texto]]] as [String: Any]]] as [String: Any]])
    }

    static func limite(rechazado: Bool, hasta: Date) -> String {
        json(["type": "rate_limit_event", "session_id": "__SESION__",
              "rate_limit_info": ["status": rechazado ? "rejected" : "allowed", "resetsAt": hasta.timeIntervalSince1970,
                                  "rateLimitType": "five_hour"] as [String: Any]])
    }

    static func resultado(_ texto: String = "hecho", subtipo: String = "success", error: Bool = false, coste: Double = 0.02,
                          estadoAPI: Int? = nil) -> String {
        var o: [String: Any] = ["type": "result", "subtype": subtipo, "is_error": error, "result": texto,
                                "total_cost_usd": coste, "num_turns": 2, "session_id": "__SESION__"]
        if let e = estadoAPI { o["api_error_status"] = e }
        return json(o)
    }

    /// Un trabajo que termina bien (con `tls_finalizar`).
    static func exito(_ resumen: String = "Revisé la tarea y la dejé lista.", coste: Double = 0.02) -> [String] {
        [inicio(), texto("Miro la tarea."), herramienta("tls_leer", id: "t1", entrada: ["ruta": "x"]),
         resultadoHerramienta(id: "t1", texto: "{}"), herramienta("tls_finalizar", id: "t2", entrada: ["resumen": resumen]),
         resultadoHerramienta(id: "t2", texto: "{\"ok\":true}"), resultado(resumen, coste: coste)]
    }
}

/// Puerta de herramientas falsa: apunta tokens abiertos y revocados (sin socket).
final class PuertaFalsa: PuertaDeHerramientas, @unchecked Sendable {
    private let lock = NSLock()
    private var _abiertas: [ContextoDeEjecucion] = []
    private var _revocadas: [String] = []
    private var _llamadas: [(String, String)] = []
    private var _arrancada = false
    private var _parada = false

    func arrancar() async throws -> URL? { lock.withLock { _arrancada = true }; return nil }
    func parar() async { lock.withLock { _parada = true } }
    func abrir(_ c: ContextoDeEjecucion) async throws -> CredencialDeEjecucion {
        lock.withLock { _abiertas.append(c) }
        return CredencialDeEjecucion(ejecucion: c.ejecucion, token: String(repeating: "ab", count: 32),
                                     servidor: MCPServerConfig(command: "/usr/bin/true", args: ["--token-file", "token"]), socket: nil)
    }
    func revocar(_ c: CredencialDeEjecucion) async { lock.withLock { _revocadas.append(c.ejecucion) } }
    func llamar(herramienta: String, argumentos: String, credencial: CredencialDeEjecucion) async -> ResultadoDeHerramienta {
        lock.withLock { _llamadas.append((herramienta, argumentos)) }
        if herramienta == "tls_preguntar" { return ResultadoDeHerramienta(esError: false, texto: #"{"ruta":"2 · Ventas/Tareas/t-0002-pregunta.md"}"#) }
        return ResultadoDeHerramienta(esError: false, texto: #"{"ok":true,"real":true}"#)
    }

    var abiertas: [ContextoDeEjecucion] { lock.withLock { _abiertas } }
    var revocadas: [String] { lock.withLock { _revocadas } }
    var llamadas: [(String, String)] { lock.withLock { _llamadas } }
    var arrancada: Bool { lock.withLock { _arrancada } }
    var parada: Bool { lock.withLock { _parada } }
}

/// Avisos del motor apuntados.
final class Avisos: @unchecked Sendable {
    private let lock = NSLock()
    private var _lista: [AvisoDelMotor] = []
    func apuntar(_ a: AvisoDelMotor) { lock.withLock { _lista.append(a) } }
    var lista: [AvisoDelMotor] { lock.withLock { _lista } }
}

/// Una empresa de prueba (nombres neutros) con su estado fuera de la carpeta, un `claude` falso y la cola.
///
/// Áreas: Dirección, Ventas y Finanzas activas; Entrega preparada; Marca y Equipo en reposo. Asistentes activos: Mika
/// (Dirección, coordinadora), Comercial (Ventas), Contable (Finanzas), Implementador (Entrega) y Marca (Marca).
final class EntornoMotor: @unchecked Sendable {
    let base: URL
    let raiz: URL
    let estadoDir: URL
    let claude = ClaudeFalso()
    let puerta = PuertaFalsa()
    let registro = RegistroEnMemoria()
    let avisos = Avisos()
    let reloj: RelojManual
    let zona = TimeZone(identifier: "Europe/Madrid")!
    private let lock = NSLock()
    private var _ajustes: AjustesDeAsistentes

    static let help: ClaudeHelp = ClaudeHelp(text: String(decoding: Apoyo.grabacion("help-2.1.307.txt"), as: UTF8.self))

    static let configBase = """
        version: 1
        clase: copia
        interruptor: encendido
        pausa_areas: []
        agenda: {zona: Europe/Madrid}
        agentes:
          mika:
            activo: true
            coordinador: true
            areas: [direccion]
            lee_areas: [todas]
            modelo: haiku
            esfuerzo: low
            presupuesto_ejecucion_usd: 0.5
            presupuesto_mes_usd: 15
            rutinas:
              - {id: algo-rojo, nombre: "¿Algo rojo?", dias: [lun,mar,mie,jue,vie], hora: "08:45", ventana_perdida_h: 6, activa: true}
          comercial:
            activo: true
            areas: [ventas]
            presupuesto_ejecucion_usd: 0.5
            presupuesto_mes_usd: 10
            rutinas:
              - {id: pipeline, nombre: "Repaso del embudo", dias: [lun], hora: "10:00", ventana_perdida_h: 4}
          contable:
            activo: true
            areas: [finanzas]
          implementador:
            activo: true
            areas: [entrega]
          marca:
            activo: true
            areas: [marca]

        """

    /// Lunes 19/10/2026 a las 09:00 (Madrid).
    static let lunes9: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 19; c.hour = 9; c.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return cal.date(from: c)!
    }()

    init(config: String = EntornoMotor.configBase, inicio: Date = EntornoMotor.lunes9) {
        base = Apoyo.tempDir("tls-motor")
        raiz = base.appendingPathComponent("Empresa Ejemplo", isDirectory: true)
        estadoDir = base.appendingPathComponent("estado", isDirectory: true)
        reloj = RelojManual(inicio)
        _ajustes = AjustesDeAsistentes.leer(yaml: config)
        try! FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        escribir(".tls/layout.json", #"{"preset":"humana","privado":["4 · Finanzas/Privado"]}"#)
        escribir(".tls/config.yaml", config)
        escribir(".tls/secuencias.json", "{\"tarea\":2}\n")
        escribir("Empresa.md", "# Empresa Ejemplo\n")
        let estados: [(AreaCode, String)] = [(.direccion, "activa"), (.ventas, "activa"), (.entrega, "preparada"),
                                              (.finanzas, "activa"), (.marca, "en reposo"), (.equipo, "en reposo")]
        for (a, e) in estados {
            escribir("\(a.numero) · \(a.nombre)/Área.md", "# \(a.nombre)\n\n**Estado:** \(e) · **La lleva:** Manu\n\n## Qué transforma\nAlgo.\n")
        }
        escribir("2 · Ventas/Sistemas/Seguimiento de oportunidades.md", "# Seguimiento de oportunidades\n\n> Para que nada se enfríe.\n")
        escribir("4 · Finanzas/Privado/Expediente privado.md", "# Expediente privado\n\nNada que ver aquí.\n")
    }

    var ajustes: AjustesDeAsistentes {
        get { lock.withLock { _ajustes } }
        set { lock.withLock { _ajustes = newValue } }
    }

    func escribir(_ ruta: String, _ texto: String) {
        Apoyo.escribir(texto, en: VaultPath(ruta).url(in: raiz))
    }

    func leer(_ ruta: String) -> String { (try? String(contentsOf: VaultPath(ruta).url(in: raiz), encoding: .utf8)) ?? "" }

    /// Tarea de prueba lista para un asistente.
    @discardableResult
    func tarea(_ n: Int, titulo: String, area: AreaCode = .ventas, responsable: String = "agente:comercial",
               estado: String = "Por hacer", actividad: String = "") -> VaultPath {
        let slug = titulo.lowercased().replacingOccurrences(of: " ", with: "-")
        let ruta = "\(area.numero) · \(area.nombre)/Tareas/t-\(String(format: "%04d", n))-\(slug).md"
        escribir(ruta, """
            ---
            tls_type: task
            tls_schema: 1
            id: 00000000-0000-4000-8000-\(String(format: "%012d", n))
            numero: T-\(String(format: "%04d", n))
            titulo: \(titulo)
            estado: \(estado)
            tipo: tarea
            responsable: \(responsable)
            creada: 2026-10-15
            ---
            # \(titulo)

            ## Descripción
            Algo que hacer.

            ## Actividad
            <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->
            \(actividad)
            """)
        return VaultPath(ruta)
    }

    var foto: @Sendable () async -> VaultSnapshot {
        let raiz = self.raiz
        return { VaultSnapshot.read(root: raiz) }
    }

    func runtime(gracia: TimeInterval = 5) -> ClaudeCodeRuntime {
        ClaudeCodeRuntime(claude: claude.binario, help: Self.help, home: Apoyo.home, gracia: gracia)
    }

    func estado() throws -> EstadoDelMotor { try EstadoDelMotor(directory: estadoDir) }

    func cola(runtime: (any AgentRuntime)? = nil, estado: EstadoDelMotor? = nil, catalogo: (any CatalogoDeAsistentes)? = nil,
              enVivo: EstadoEnVivo? = nil, esperas: [TimeInterval] = [60, 300]) throws -> ColaDeEjecuciones {
        let avisos = self.avisos
        return ColaDeEjecuciones(.init(
            estadoDeCarpeta: estadoDir, raiz: raiz, estado: try estado ?? self.estado(), runtime: runtime ?? self.runtime(),
            servidor: puerta, registro: registro, ajustes: AjustesConCierre { [self] in self.ajustes },
            catalogo: catalogo ?? Self.catalogo, reloj: reloj, foto: foto, enVivo: enVivo,
            alAvisar: { avisos.apuntar($0) }, empresa: "Empresa Ejemplo", tiempoMaximo: 60, esperasDeReintento: esperas))
    }

    func host(runtime: (any AgentRuntime)? = nil, catalogo: (any CatalogoDeAsistentes)? = nil,
              enVivo: EstadoEnVivo? = nil, leerEventos: Bool = true) throws -> AgentHost {
        let avisos = self.avisos
        return try AgentHost(.init(
            raiz: raiz, estadoDeCarpeta: estadoDir, runtime: runtime ?? self.runtime(), puerta: puerta, registro: registro,
            ajustes: AjustesConCierre { [self] in self.ajustes }, catalogo: catalogo ?? Self.catalogo, reloj: reloj,
            foto: foto, enVivo: enVivo, alAvisar: { avisos.apuntar($0) }, empresa: "Empresa Ejemplo", intervalo: 3600,
            leerEventos: leerEventos, tiempoMaximo: 60))
    }

    static let catalogo = CatalogoFijo([
        RolDeAsistente(slug: "mika", nombre: "Mika", area: .direccion, coordinador: true,
                       preguntaFija: "¿Hay algo en rojo que te tenga que contar?", instrucciones: "## Qué haces\nCoordinas.",
                       eventos: []),
        RolDeAsistente(slug: "comercial", nombre: "Comercial", area: .ventas, preguntaFija: "¿De dónde sale el próximo cliente?",
                       instrucciones: "## Qué haces\nSeguimientos.", eventos: ["contacto.creado"],
                       instruccionesPorEvento: ["contacto.creado": "Prepara el diagnóstico del contacto nuevo."]),
        RolDeAsistente(slug: "contable", nombre: "Contable", area: .finanzas, preguntaFija: "¿Hay caja y hay margen?",
                       instrucciones: "## Qué haces\nCuentas."),
        RolDeAsistente(slug: "implementador", nombre: "Implementador", area: .entrega, preguntaFija: "¿Cumplimos?",
                       instrucciones: "## Qué haces\nEntregas."),
        RolDeAsistente(slug: "marca", nombre: "Marca", area: .marca, preguntaFija: "¿Nos conocen?", instrucciones: "## Qué haces\nPiezas."),
    ])

    func limpiar() {
        claude.limpiar()
        Apoyo.limpiar(base)
    }
}

/// Espera (sondeando) a que algo sea verdad, hasta `segundos`.
func esperarA(_ segundos: TimeInterval = 10, _ condicion: @Sendable () async -> Bool) async -> Bool {
    let limite = Date().addingTimeInterval(segundos)
    while Date() < limite {
        if await condicion() { return true }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return await condicion()
}
