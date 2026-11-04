import Foundation

/// Reproduce grabaciones de `stream-json` en vez de lanzar Claude (Ribera, la demo y las pruebas).
///
/// **Formato de una grabación** (`<nombre>.jsonl`, en `Sources/TLSAgents/Simulado/Grabaciones/`): las líneas tal
/// como las escribe Claude Code con `--output-format stream-json --verbose` (`system/init`, `assistant`, `user`,
/// `rate_limit_event`, `result`). Antes de leer cada línea se sustituyen las variables `{{tarea}}` (ruta de la
/// tarea), `{{tarea_id}}`, `{{hoy}}` (AAAA-MM-DD del reloj del motor), `{{ahora}}` (AAAA-MM-DD HH:MM),
/// `{{agente}}`, `{{ejecucion}}`, `{{pregunta}}` y `{{respuesta}}` (al contestar una pregunta).
///
/// Se elige la primera que exista de `PeticionDeEjecucion.grabaciones` (de la más concreta a la más general:
/// `mika-algo-rojo`, `mika-rutina`, `mika`, `generica`).
///
/// Con servidor de herramientas, cada `tool_use` de `mcp__tls__*` **se ejecuta de verdad** por el servidor (con el
/// mismo token y la misma autorización que una ejecución real) y su resultado sustituye al grabado. El `session_id`
/// del `init` y del `result` es el de la petición (`--session-id` o `--resume`), así que reanudar funciona igual.
/// Todo lo que produce lleva la marca «Simulado» (`ResultadoDeEjecucion.simulado`, y la Actividad y la Bitácora
/// lo dicen).
public struct SimulatedRuntime: AgentRuntime {
    public var grabaciones: URL
    public var servidor: (any PuertaDeHerramientas)?
    /// Pausa entre líneas (la demo enseña «Leyendo…» unos instantes; las pruebas, 0).
    public var pausa: TimeInterval
    public var initGuard: InitGuard

    public let simulado = true

    public init(grabaciones: URL, servidor: (any PuertaDeHerramientas)? = nil, pausa: TimeInterval = 0,
                initGuard: InitGuard = InitGuard()) {
        self.grabaciones = grabaciones; self.servidor = servidor; self.pausa = pausa; self.initGuard = initGuard
    }

    /// La grabación que toca, o `nil`.
    public func grabacion(para p: PeticionDeEjecucion) -> URL? {
        for nombre in p.grabaciones + ["generica"] {
            let url = grabaciones.appendingPathComponent(nombre + ".jsonl")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    public func ejecutar(_ p: PeticionDeEjecucion, alEvento: @escaping @Sendable (AgentEvent) -> Void,
                         alArrancar: @escaping @Sendable (Int32) -> Void) async -> ResultadoDeEjecucion {
        guard let url = grabacion(para: p), let texto = try? String(contentsOf: url, encoding: .utf8) else {
            return ResultadoDeEjecucion(estado: .fallida(.error), avisos: ["No hay grabación para \(p.grabaciones.first ?? p.contexto.agente)."],
                                        simulado: true)
        }
        try? p.paths.create()
        let sesion: String
        var reanudar: UUID?
        switch p.sesion {
        case .new(let id): sesion = id.uuidString.lowercased()
        case .resume(let id): sesion = id.uuidString.lowercased(); reanudar = id
        case .ephemeral: sesion = UUID().uuidString.lowercased()
        }
        let recolector = RecolectorDeStream(stream: p.paths.stream, guardia: initGuard, reanudar: reanudar, alEvento: alEvento)
        defer { recolector.cerrar() }
        alArrancar(0)

        var ejecutadas = Set<String>()
        var cancelado = false
        for cruda in texto.split(whereSeparator: \.isNewline) {
            if Task.isCancelled { cancelado = true; break }
            let linea = Self.sustituir(String(cruda), p.variables)
            guard var obj = (try? JSONSerialization.jsonObject(with: Data(linea.utf8))) as? [String: Any] else {
                if recolector.linea(Data(linea.utf8)) == .terminar { break }
                continue
            }
            let tipo = obj["type"] as? String
            if obj["session_id"] != nil { obj["session_id"] = sesion }
            if tipo == "system", obj["subtype"] as? String == "init" { obj["cwd"] = p.paths.agentDirectory.path }
            // El resultado grabado de una herramienta que ya se ejecutó de verdad no se repite.
            if tipo == "user", servidor != nil, let ids = Self.resultadosDeHerramienta(obj), !ids.isEmpty,
               ids.allSatisfy(ejecutadas.contains) { continue }
            if recolector.linea(Self.datos(obj)) == .terminar { break }
            if tipo == "assistant", let servidor, let credencial = p.credencial {
                for (id, nombre, entrada) in Self.llamadas(obj) where nombre.hasPrefix("mcp__tls__") {
                    if Task.isCancelled { cancelado = true; break }
                    let r = await servidor.llamar(herramienta: String(nombre.dropFirst("mcp__tls__".count)),
                                                  argumentos: entrada, credencial: credencial)
                    ejecutadas.insert(id)
                    let resultado: [String: Any] = [
                        "type": "user", "session_id": sesion,
                        "message": ["role": "user", "content": [[
                            "type": "tool_result", "tool_use_id": id, "is_error": r.esError,
                            "content": [["type": "text", "text": r.texto]],
                        ] as [String: Any]]] as [String: Any],
                    ]
                    _ = recolector.linea(Self.datos(resultado))
                }
            }
            if pausa > 0 { try? await Task.sleep(nanoseconds: UInt64(pausa * 1_000_000_000)) }
        }
        if Task.isCancelled { cancelado = true }
        let estado = recolector.estadoFinal(cancelado: cancelado, tiempoAgotado: false)
        return recolector.resultado(estado: estado, pid: nil, simulado: true, avisos: [])
    }

    static func sustituir(_ s: String, _ variables: [String: String]) -> String {
        guard s.contains("{{") else { return s }
        var out = s
        for (k, v) in variables {
            // El valor va dentro de una cadena JSON: se escapa como tal.
            let escapado = String(String(decoding: (try? JSONSerialization.data(withJSONObject: [v], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8),
                                         as: UTF8.self).dropFirst(2).dropLast(2))
            out = out.replacingOccurrences(of: "{{\(k)}}", with: escapado)
        }
        return out
    }

    static func datos(_ obj: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])) ?? Data()
    }

    static func llamadas(_ obj: [String: Any]) -> [(String, String, String)] {
        let bloques = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        return bloques.compactMap { b in
            guard b["type"] as? String == "tool_use", let id = b["id"] as? String, let nombre = b["name"] as? String else { return nil }
            return (id, nombre, StreamJSONParser.compactJSON(b["input"]))
        }
    }

    static func resultadosDeHerramienta(_ obj: [String: Any]) -> [String]? {
        guard let bloques = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return nil }
        return bloques.compactMap { $0["type"] as? String == "tool_result" ? $0["tool_use_id"] as? String : nil }
    }
}
