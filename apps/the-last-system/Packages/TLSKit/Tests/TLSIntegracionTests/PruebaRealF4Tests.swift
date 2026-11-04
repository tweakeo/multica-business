import Foundation
import MCP
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSIntegracion
import TLSMCPHost
import TLSMCPShared
@testable import TLSUI

/// **La prueba real de F4, una sola vez y barata** (solo con `TLS_F4_REAL=1`; nunca en `make test`): Claude Code de
/// verdad, en su caja (`agente.sb`), con el `tls-mcp` firmado de la app compilada (`make build`), sobre una **copia
/// temporal de Ribera** (nunca datos reales). Mika (haiku, `--max-budget-usd 0.10`) crea una tarea interna por
/// `tls-mcp`: la ficha aparece con su Actividad y su línea de Bitácora y no sale ninguna tarjeta (criterio F4-1). Apunta el
/// coste y la salida. Aparte (sin Claude): el `tls-mcp` **firmado** de la app, por stdio y por el socket con el
/// `PeerValidator` de verdad, responde «aprobación requerida» a `tls_solicitar_accion`.
@Suite("F4 · prueba real con Claude Code (TLS_F4_REAL=1)", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["TLS_F4_REAL"] == "1"))
@MainActor
struct PruebaRealF4Tests {
    /// La app compilada (`make build` o `make dmg`): su `tls-mcp` firmado.
    static var app: URL {
        let productos = EntornoF4.repo.appendingPathComponent("build/DerivedData/Build/Products")
        for conf in ["Debug", "Release"] {
            let a = productos.appendingPathComponent("\(conf)/The Last System.app")
            if FileManager.default.isExecutableFile(atPath: a.appendingPathComponent("Contents/Helpers/tls-mcp").path) { return a }
        }
        return productos.appendingPathComponent("Debug/The Last System.app")
    }

    /// Los proyectos que Claude tiene apuntados en `~/.claude.json` dentro de `carpeta` (solo se leen las claves).
    static func proyectos(en carpeta: String) -> [String] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard let d = try? Data(contentsOf: url), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let p = o["projects"] as? [String: Any] else { return [] }
        return p.keys.filter { $0.hasPrefix(carpeta) }.sorted()
    }

    @Test("Mika, con Claude Code de verdad, crea una tarea interna sin tarjeta, con su Actividad y su Bitácora")
    func mikaDeVerdad() async throws {
        let helper = Self.app.appendingPathComponent("Contents/Helpers/tls-mcp")
        try #require(FileManager.default.isExecutableFile(atPath: helper.path), "Falta make build o make dmg")
        print("PRUEBA REAL · app: \(Self.app.path)")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tr-" + String(UUID().uuidString.lowercased().prefix(6)), isDirectory: true)
        let carpeta = base.appendingPathComponent("Ribera", isDirectory: true)
        let estado = base.appendingPathComponent("e", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: EntornoF4.ribera, to: carpeta)
        // Solo Mika, sin rutinas, con haiku y como mucho 0,10 USD por trabajo.
        let config = carpeta.appendingPathComponent(".tls/config.yaml")
        var t = try String(contentsOf: config, encoding: .utf8)
        t = t.replacingOccurrences(of: "clase: demo", with: "clase: copia")
            .replacingOccurrences(of: "activo: true", with: "activo: false")
            .replacingOccurrences(of: "activa: true", with: "activa: false")
        let mika = try #require(t.range(of: "  mika:\n    activo: false"))
        t.replaceSubrange(mika, with: "  mika:\n    activo: true")
        let bloque = try #require(t.range(of: "    modelo: sonnet\n    esfuerzo: medium\n    max_tareas_por_ejecucion: 10\n    presupuesto_ejecucion_usd: 0.5"))
        t.replaceSubrange(bloque, with: "    modelo: haiku\n    esfuerzo: low\n    max_tareas_por_ejecucion: 10\n    presupuesto_ejecucion_usd: 0.1")
        try Data(t.utf8).write(to: config)

        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("reg", isDirectory: true)))
        let entry = VaultEntry(nombre: "Asesoría Ribera (prueba)", ruta: carpeta.path, bookmark: nil, clase: .copia, escritura: .permitida)
        try model.register(entry)
        let integracion = AsistentesDeLaApp(opciones: .init(
            localizador: LocalizadorClaudeCode(), helper: helper, validador: .deLaApp(bundle: Self.app),
            appSupport: base.appendingPathComponent("a", isDirectory: true), appBundle: Self.app, catalogo: EntornoF4.catalogo,
            intervalo: 3600, usarSandbox: true, gracia: 5))
        model.integracionDeAsistentes = integracion
        let antesProyectos = Self.proyectos(en: base.path)
        let sesion = VaultSession(entry: entry, estado: estado)
        sesion.persona = "Manu"
        await sesion.start(using: model)
        do {
            try await esperar("motor montado", segundos: 60) { integracion.motor(de: sesion)?.listo == true }
            let motor = try #require(integracion.motor(de: sesion))
            guard let host = motor.host else {
                Issue.record("Sin Claude Code listo: \(String(describing: motor.claude))")
                await integracion.pararTodo()
                sesion.close()
                return
            }
            if case .listo(let binario, _, let version) = motor.claude { print("PRUEBA REAL · Claude Code \(version ?? "?") en \(binario.path)") }
            let p = motor.piezas
            let fotoAntes = await p.foto()
            let antes = Set(BandejaDeDecisiones.consultar(LecturaDominio(snapshot: fotoAntes), gobierno: .de(p.autorizador),
                                                          estado: p.autorizador.estado).tarjetas.map(\.id))
            let ej = try #require(try await host.pedir(a: "mika", instruccion:
                "Prueba de la app: crea con tls_crear_tarea UNA tarea interna titulada «Revisar el resumen de octubre» "
                + "(sin responsable, en Dirección) y después cierra con tls_finalizar con un resumen de una línea. No hagas nada más."))
            try await esperar("el trabajo de Mika termina", segundos: 240) {
                guard let x = await host.ejecuciones().first(where: { $0.id == ej.id }) else { return false }
                return x.estado.esFinal || x.estado == .esperandoRespuesta
            }
            let fin = try #require(await host.ejecuciones().first { $0.id == ej.id })
            print("PRUEBA REAL · trabajo \(fin.id): \(fin.estado.rawValue)\(fin.motivo.map { " (\($0))" } ?? "") · coste \(fin.costeUSD) USD · intento \(fin.intento)")
            print("PRUEBA REAL · resumen: \(fin.resumen ?? "-")")
            #expect(fin.estado == .completada)
            #expect(fin.costeUSD <= 0.10 + 0.0001)
            let stream = (try? String(contentsOf: p.estadoDeCarpeta.appendingPathComponent("ejecuciones/\(ej.id)/stream.jsonl"), encoding: .utf8)) ?? ""
            #expect(stream.contains("\"mcp__tls__tls_crear_tarea\""))
            #expect(!stream.contains("\"Bash\""))

            // La ficha, su Actividad y su línea de Bitácora; ninguna tarjeta nueva.
            try await esperar("la línea de la Bitácora", segundos: 15) {
                ((try? String(contentsOf: carpeta.appendingPathComponent("6 · Equipo/Bitácora/2026-10.md"), encoding: .utf8)) ?? "").contains(ej.id)
            }
            let foto = await p.foto()
            let tarea = try #require(foto.notes.first { $0.raw.contains("/Tareas/") && (foto.text($0) ?? "").contains("creada_por") &&
                                                         (foto.text($0) ?? "").contains("agente:mika") && (foto.text($0) ?? "").lowercased().contains("resumen de octubre") })
            let texto = try #require(foto.text(tarea))
            print("PRUEBA REAL · ficha creada: \(tarea.raw)")
            #expect(texto.contains("## Actividad"))
            let despues = Set(BandejaDeDecisiones.consultar(LecturaDominio(snapshot: foto), gobierno: .de(p.autorizador),
                                                            estado: p.autorizador.estado).tarjetas.map(\.id))
            #expect(despues.subtracting(antes).isEmpty, "Tarjetas nuevas: \(despues.subtracting(antes))")
            #expect(try p.autorizador.estado.auditoria(ejecucion: ej.id).contains { $0.accion == "tarea.crear" && $0.decision == "permitido" })

            // Claude apunta como mucho un proyecto (la carpeta de Mika) para esta copia.
            let nuevos = Set(Self.proyectos(en: base.path)).subtracting(antesProyectos)
            print("PRUEBA REAL · proyectos nuevos en ~/.claude.json para esta copia: \(nuevos.count) \(nuevos.map { URL(fileURLWithPath: $0).lastPathComponent })")
            #expect(nuevos.count <= 1)
        } catch {
            await integracion.pararTodo()
            sesion.close()
            throw error
        }
        await integracion.pararTodo()
        sesion.close()
        try await Task.sleep(for: .seconds(1))
        #expect(procesos(base.path).isEmpty, "ningún proceso de la prueba vivo")
    }

    @Test("El tls-mcp firmado de la app, por stdio y el socket con el PeerValidator de verdad: tls_solicitar_accion da «aprobación requerida»")
    func tlsMcpFirmado() async throws {
        let helper = Self.app.appendingPathComponent("Contents/Helpers/tls-mcp")
        try #require(FileManager.default.isExecutableFile(atPath: helper.path), "Falta make build o make dmg")
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tq-" + String(UUID().uuidString.lowercased().prefix(6)), isDirectory: true)
        let carpeta = base.appendingPathComponent("Ribera", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: EntornoF4.ribera, to: carpeta)
        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("reg", isDirectory: true)))
        let entry = VaultEntry(nombre: "Asesoría Ribera", ruta: carpeta.path, bookmark: nil, clase: .demo, escritura: .permitida)
        try model.register(entry)
        // El ejemplo (simulado: no se lanza Claude) con el validador de la app de verdad: solo acepta su `tls-mcp`.
        let integracion = AsistentesDeLaApp(opciones: .init(
            localizador: LocalizadorFijo(.noEncontrado), helper: helper, validador: .deLaApp(bundle: Self.app),
            appSupport: base.appendingPathComponent("a", isDirectory: true), appBundle: Self.app, catalogo: EntornoF4.catalogo,
            pausaSimulacion: 0, intervalo: 3600, reloj: RelojManual(EntornoF4.fecha(25, 12, 0))))
        model.integracionDeAsistentes = integracion
        let sesion = VaultSession(entry: entry, estado: base.appendingPathComponent("e", isDirectory: true))
        await sesion.start(using: model)
        try await esperar("motor montado", segundos: 60) { integracion.motor(de: sesion)?.listo == true }
        let motor = try #require(integracion.motor(de: sesion))
        let puerta = try #require(motor.puerta)
        let p = motor.piezas
        defer { Task { await integracion.pararTodo(); sesion.close() } }

        // Un proceso que no es el `tls-mcp` firmado no entra, aunque traiga un token bueno.
        let token = puerta.host.tokens.emitir(ContextoDelAsistente(ejecucion: "r-real-comercial", asistente: "comercial",
                                                                   areas: [.ventas], leeAreas: [.marca, .finanzas]))
        #expect(throws: (any Error).self) { _ = try IPCCliente.conectar(socket: puerta.host.socket.path, token: token, timeout: 5) }

        // El firmado, como lo lanza Claude Code: stdio, el socket por argumento y el token por el entorno.
        let mcp = try ClienteMCPStdio(helper: helper, socket: puerta.host.socket.path, token: token)
        defer { mcp.cerrar() }
        let ini = try mcp.pedir("initialize", ["protocolVersion": "2025-03-26", "capabilities": [String: Any](),
                                               "clientInfo": ["name": "prueba-f4", "version": "1"]])
        #expect((ini["result"] as? [String: Any])?["serverInfo"] != nil, "\(ini)")
        mcp.avisar("notifications/initialized")
        let lista = try mcp.pedir("tools/list", [:])
        let nombres = (((lista["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        print("PRUEBA REAL · tls-mcp firmado: \(nombres.count) herramientas para el Comercial")
        #expect(nombres.contains("tls_solicitar_accion"))
        let borrador = try mcp.pedir("tools/call", ["name": "tls_preparar_borrador", "arguments": [
            "tipo": "correo", "accion": "enviar_correo", "area": "Ventas", "asunto": "Prueba de la app",
            "cuerpo": "Hola: esto es una prueba de la app. No se envía nada."]])
        let textoBorrador = Self.texto(borrador)
        let ruta = try #require(Self.estructurado(borrador)?["ruta"] as? String, "\(textoBorrador)")
        let pide = try mcp.pedir("tools/call", ["name": "tls_solicitar_accion", "arguments": [
            "accion": "enviar_correo", "borrador_id": ruta]])
        let textoPide = Self.texto(pide)
        print("PRUEBA REAL · tls_solicitar_accion por el tls-mcp firmado → \(textoPide.prefix(240))")
        #expect(textoPide.contains("aprobacion_requerida") || (Self.estructurado(pide)?["estado"] as? String) == "aprobacion_requerida")
        // Queda pendiente de tu OK y no ha salido nada.
        #expect(try ApprovalStore(estado: p.autorizador.estado).abiertas(ahora: .distantPast).contains { $0.ruta?.raw == ruta })
        let texto = try String(contentsOf: VaultPath(ruta).url(in: carpeta), encoding: .utf8)
        #expect(texto.contains("Pendiente de tu OK"))
        mcp.cerrar()
        puerta.host.revocar(token: token)
    }

    static func texto(_ r: [String: Any]) -> String {
        let contenido = ((r["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        return contenido.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    static func estructurado(_ r: [String: Any]) -> [String: Any]? {
        if let s = (r["result"] as? [String: Any])?["structuredContent"] as? [String: Any] { return s }
        return texto(r).data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}

/// Un cliente MCP mínimo por stdio (JSON-RPC en líneas), como el de Claude Code, para hablar con el `tls-mcp` firmado.
final class ClienteMCPStdio: @unchecked Sendable {
    let proceso = Process()
    let entrada = Pipe()
    let salida = Pipe()
    private var pendiente = Data()
    private var siguiente = 1

    init(helper: URL, socket: String, token: String) throws {
        proceso.executableURL = helper
        proceso.arguments = ["--socket", socket]
        proceso.environment = ["TLS_MCP_TOKEN": token, "PATH": "/usr/bin:/bin"]
        proceso.standardInput = entrada
        proceso.standardOutput = salida
        proceso.standardError = FileHandle.nullDevice
        try proceso.run()
    }

    func enviar(_ o: [String: Any]) {
        var d = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
        d.append(0x0A)
        entrada.fileHandleForWriting.write(d)
    }

    func avisar(_ metodo: String) { enviar(["jsonrpc": "2.0", "method": metodo]) }

    /// Manda una petición y espera su respuesta (con su mismo `id`), como mucho 30 s.
    func pedir(_ metodo: String, _ params: [String: Any]) throws -> [String: Any] {
        let id = siguiente
        siguiente += 1
        enviar(["jsonrpc": "2.0", "id": id, "method": metodo, "params": params])
        let fin = Date().addingTimeInterval(30)
        while Date() < fin {
            while let n = pendiente.firstIndex(of: 0x0A) {
                let linea = pendiente[pendiente.startIndex..<n]
                pendiente.removeSubrange(pendiente.startIndex...n)
                if let o = try? JSONSerialization.jsonObject(with: Data(linea)) as? [String: Any], (o["id"] as? Int) == id { return o }
            }
            let d = salida.fileHandleForReading.availableData
            if d.isEmpty { break }
            pendiente.append(d)
        }
        throw ErrorDeEspera.tiempo("respuesta MCP a \(metodo)")
    }

    func cerrar() {
        try? entrada.fileHandleForWriting.close()
        if proceso.isRunning { proceso.terminate() }
    }
}
