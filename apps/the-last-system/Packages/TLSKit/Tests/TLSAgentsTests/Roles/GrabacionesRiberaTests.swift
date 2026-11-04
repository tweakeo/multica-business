import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// PLAN §6.8: las grabaciones de Ribera se reproducen enteras con `SimulatedRuntime` (sin lanzar Claude), pasan
/// `InitGuard`, solo usan herramientas del asistente con los argumentos que pide `tls-mcp` y hablan de datos que
/// están de verdad en la carpeta de Ribera.
@Suite("Ribera · grabaciones de los asistentes", .serialized)
struct GrabacionesRiberaTests {
    static let carpeta = ApoyoRoles.grabaciones

    /// Argumentos obligatorios de cada herramienta (los del catálogo de `tls-mcp`, `CatalogoTLS.definiciones`).
    static let requeridos: [String: [String]] = [
        "tls_buscar": ["consulta"], "tls_leer": ["ruta"], "tls_leer_sistema": ["nombre"], "tls_expediente": ["empresa"],
        "tls_crear_tarea": ["titulo"], "tls_actualizar_tarea": ["tarea"], "tls_comentar": ["tarea", "texto"],
        "tls_preparar_borrador": ["tipo", "accion", "asunto", "cuerpo"], "tls_mover_archivo": ["desde", "a"],
        "tls_proponer_conciliacion": ["movimiento"], "tls_avisar": ["texto"], "tls_programar_seguimiento": ["tarea", "fecha"],
        "tls_delegar": ["asistente", "titulo"], "tls_finalizar": ["resumen"], "tls_preguntar": ["pregunta"],
        "tls_proponer": ["titulo", "opciones"], "tls_registrar_decision": ["decision"],
        "tls_solicitar_accion": ["accion", "borrador_id"],
    ]

    struct Llamada {
        let nombre: String
        let entrada: [String: Any]
    }

    static func lineas(_ nombre: String) throws -> [[String: Any]] {
        let texto = try String(contentsOf: carpeta.appendingPathComponent(nombre + ".jsonl"), encoding: .utf8)
        return try texto.split(separator: "\n").map {
            try #require(try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any], "línea no válida en \(nombre)")
        }
    }

    static func llamadas(_ lineas: [[String: Any]]) -> [Llamada] {
        lineas.flatMap { l -> [Llamada] in
            guard l["type"] as? String == "assistant",
                  let bloques = (l["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return [] }
            return bloques.compactMap { b in
                guard b["type"] as? String == "tool_use", let n = b["name"] as? String else { return nil }
                return Llamada(nombre: String(n.dropFirst("mcp__tls__".count)), entrada: b["input"] as? [String: Any] ?? [:])
            }
        }
    }

    @Test("El índice y las grabaciones coinciden; cada asistente tiene la suya y Mika contesta al chat por temas")
    func indice() throws {
        let indice = try GrabacionesDeEjemplo.indice(en: Self.carpeta)
        #expect(indice.hoy == "2026-10-19")
        let ficheros = try FileManager.default.contentsOfDirectory(atPath: Self.carpeta.path)
            .filter { $0.hasSuffix(".jsonl") }.map { String($0.dropLast(6)) }.sorted()
        #expect(ficheros == indice.grabaciones.map(\.nombre).sorted())
        // El recorrido que pide el ejemplo.
        for n in ["mika-algo-rojo", "mika-resumen-semana", "comercial-repaso-embudo", "contable-extracto-importado",
                  "contable-respuesta", "generica"] {
            #expect(indice.grabacion(n) != nil, "Falta \(n)")
        }
        #expect(indice.grabaciones.filter { $0.disparo == "chat" && $0.asistente == "mika" && $0.palabras != nil }.count >= 3)
        // Nombres que pide el motor para cada disparo (de lo concreto a lo general).
        #expect(GrabacionesDeEjemplo.nombres(agente: "mika", disparo: .rutina, clave: "algo-rojo").first == "mika-algo-rojo")
        #expect(GrabacionesDeEjemplo.nombres(agente: "contable", disparo: .evento, clave: "extracto.importado").first == "contable-extracto-importado")
        #expect(GrabacionesDeEjemplo.nombres(agente: "agente:contable", disparo: .respuesta) == ["contable-respuesta", "contable"])
        #expect(GrabacionesDeEjemplo.nombres(agente: "mika", disparo: .chat, texto: "¿Cómo vamos de caja?", indice: indice)
            == ["mika-chat-caja", "mika-chat", "mika"])
        #expect(GrabacionesDeEjemplo.paraChat("¿Qué tengo hoy?", indice: indice) == "mika-chat-hoy")
        #expect(GrabacionesDeEjemplo.paraChat("¿Cómo va el embudo de ventas?", indice: indice) == "mika-chat-embudo")
        #expect(GrabacionesDeEjemplo.paraChat("Prepárame la llamada con Amparo", indice: indice) == "mika-chat-tarea")
        #expect(GrabacionesDeEjemplo.paraChat("Cuéntame un chiste", indice: indice) == nil)
        // Las del paquete son estas mismas (el recurso se copia tal cual).
        let paquete = try #require(GrabacionesDeEjemplo.carpeta)
        let delPaquete = try FileManager.default.contentsOfDirectory(atPath: paquete.path).sorted()
        let delRepositorio = try FileManager.default.contentsOfDirectory(atPath: Self.carpeta.path).sorted()
        #expect(delPaquete == delRepositorio)
    }

    @Test("Cada grabación es stream-json válido: init que pasa la guardia, herramientas suyas con sus argumentos y un result")
    func formato() throws {
        let indice = try GrabacionesDeEjemplo.indice(en: Self.carpeta)
        for g in indice.grabaciones {
            let lineas = try Self.lineas(g.nombre)
            var parser = StreamJSONParser()
            var eventos: [AgentEvent] = []
            for l in lineas { eventos += parser.consume(try JSONSerialization.data(withJSONObject: l) + Data([0x0A])) }
            eventos += parser.finish()
            #expect(!eventos.contains { if case .lineaInvalida = $0 { true } else { false } }, "\(g.nombre)")
            guard case .inicio(let info)? = eventos.first else { Issue.record("\(g.nombre): no empieza por init"); continue }
            #expect(InitGuard().evaluate(info) == .permitido, "\(g.nombre)")
            #expect(info.claudeCodeVersion == "\(ClaudeLocator.verifiedVersion)", "\(g.nombre)")
            guard case .resultado(let r)? = eventos.last else { Issue.record("\(g.nombre): no acaba en result"); continue }
            #expect(r.subtype == "success" && !r.isError && (r.totalCostUSD ?? 0) > 0 && (r.totalCostUSD ?? 1) <= 0.5, "\(g.nombre)")
            // Cada llamada tiene su resultado (mismo id) y usa herramientas que el asistente tiene.
            let usos = eventos.compactMap { e -> String? in if case .herramienta(let id, _, _) = e { id } else { nil } }
            let resultados = eventos.compactMap { e -> String? in if case .resultadoHerramienta(let id, _, _) = e { id } else { nil } }
            #expect(usos == resultados, "\(g.nombre)")
            let slug = g.asistente.isEmpty ? "mika" : g.asistente
            let perfil = try #require(PerfilDeAsistente.deSerie.first { $0.slug == slug })
            #expect(Set(info.tools) == Set(perfil.herramientas.map(\.nombreCompleto)), "\(g.nombre): init con otras herramientas")
            let llamadas = Self.llamadas(lineas)
            for c in llamadas {
                let h = try #require(HerramientaDeAsistente(rawValue: c.nombre), "\(g.nombre): \(c.nombre)")
                #expect(perfil.herramientas.contains(h), "\(g.nombre): \(slug) no tiene \(c.nombre)")
                for k in Self.requeridos[c.nombre] ?? [] { #expect(c.entrada[k] != nil, "\(g.nombre): \(c.nombre) sin «\(k)»") }
            }
            // Los trabajos (no el chat) se cierran con tls_finalizar, una vez y al final.
            if g.disparo != "chat" {
                #expect(llamadas.filter { $0.nombre == "tls_finalizar" }.count == 1 && llamadas.last?.nombre == "tls_finalizar", "\(g.nombre)")
            }
        }
    }

    @Test("La línea roja también en el ejemplo: lo que sale fuera solo se pide, y sobre un borrador que acaba de preparar")
    func lineaRoja() throws {
        let indice = try GrabacionesDeEjemplo.indice(en: Self.carpeta)
        var pedidas = 0
        for g in indice.grabaciones {
            let llamadas = Self.llamadas(try Self.lineas(g.nombre))
            for (i, c) in llamadas.enumerated() where c.nombre == "tls_solicitar_accion" {
                pedidas += 1
                let previo = try #require(llamadas[..<i].last { $0.nombre == "tls_preparar_borrador" }, "\(g.nombre)")
                #expect(c.entrada["accion"] as? String == previo.entrada["accion"] as? String)
                let area = try #require((previo.entrada["area"] as? String).flatMap(AjustesDeAsistentes.area))
                let asunto = try #require(previo.entrada["asunto"] as? String)
                let ruta = VaultLayout.humana.areaFolder(area).appending("Borradores").appending(NombresDeFicha.slug(asunto) + ".md")
                #expect(c.entrada["borrador_id"] as? String == ruta.raw, "\(g.nombre)")
            }
            // Nadie cambia estados prohibidos, mueve «vence» ni registra decisiones sin origen.
            for c in llamadas {
                #expect(!["Hecha", "Cancelada"].contains(c.entrada["estado"] as? String ?? ""), "\(g.nombre)")
                #expect(c.entrada["vence"] == nil, "\(g.nombre)")
                #expect(c.nombre != "tls_registrar_decision", "\(g.nombre)")
            }
        }
        // Comercial (repaso del embudo y, desde F4 · integración, «Preparar seguimiento», el mismo borrador) y Contable.
        #expect(pedidas == 3)
    }

    @Test("Hablan de lo que hay en Ribera: rutas, movimientos y facturas existen")
    func datosDeRibera() throws {
        let root = ApoyoRoles.ribera
        let movimientos = try String(contentsOf: root.appendingPathComponent("4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv"), encoding: .utf8)
        let emitidas = try String(contentsOf: root.appendingPathComponent("4 · Finanzas/Registros/emitidas.csv"), encoding: .utf8)
        let indice = try GrabacionesDeEjemplo.indice(en: Self.carpeta)
        for g in indice.grabaciones {
            for c in Self.llamadas(try Self.lineas(g.nombre)) {
                for k in ["ruta", "oportunidad"] {
                    guard let r = c.entrada[k] as? String, c.nombre != "tls_preparar_borrador" || k == "oportunidad" else { continue }
                    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(r).path), "\(g.nombre): no existe \(r)")
                }
                if let carpeta = c.entrada["carpeta"] as? String {
                    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(carpeta).path), "\(g.nombre): \(carpeta)")
                }
                if let m = c.entrada["movimiento"] as? String { #expect(movimientos.contains(m + ","), "\(g.nombre): \(m)") }
                if let f = c.entrada["factura"] as? String { #expect(emitidas.contains(f + ","), "\(g.nombre): \(f)") }
            }
        }
        // El seguimiento del día 7 es de una propuesta enviada el 12/10 (el lunes 19, siete días).
        let javier = try String(contentsOf: root.appendingPathComponent("2 · Ventas/Oportunidades/javier-ortega-renta/Propuesta v1.md"), encoding: .utf8)
        #expect(javier.contains("fecha: 2026-10-12"))
    }

    @Test("Lo que se enseña (textos, resúmenes, borradores y preguntas) no usa jerga")
    func glosario() throws {
        let indice = try GrabacionesDeEjemplo.indice(en: Self.carpeta)
        var textos: [String] = indice.grabaciones.map(\.titulo) + [indice.nota]
        for g in indice.grabaciones {
            let lineas = try Self.lineas(g.nombre)
            for l in lineas {
                if l["type"] as? String == "result", let r = l["result"] as? String { textos.append(r) }
                let bloques = (l["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
                textos += bloques.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            }
            for c in Self.llamadas(lineas) {
                for k in ["resumen", "titulo", "problema", "por_que", "pregunta", "propuesta", "asunto", "cuerpo", "notas", "descripcion", "anadir"] {
                    if let s = c.entrada[k] as? String { textos.append(s) }
                }
                textos += (c.entrada["opciones"] as? [String]) ?? []
            }
        }
        for t in textos { #expect(ApoyoRoles.palabrasDeJerga(t).isEmpty, "«\(t)» → \(ApoyoRoles.palabrasDeJerga(t))") }
    }

    @Test("Se reproducen enteras con SimulatedRuntime: terminan bien, marcadas «Simulado», y la pregunta queda pendiente")
    func reproducir() async throws {
        let estado = try ApoyoRoles.temporal("simulado")
        defer { try? FileManager.default.removeItem(at: estado) }
        let carpeta = try #require(GrabacionesDeEjemplo.carpeta)
        let runtime = SimulatedRuntime(grabaciones: carpeta)
        let indice = try GrabacionesDeEjemplo.indice(en: carpeta)
        for g in indice.grabaciones {
            let slug = g.asistente.isEmpty ? "mika" : g.asistente
            let disparo = TipoDeDisparo(rawValue: g.disparo) ?? .accion
            let p = PeticionDeEjecucion(
                contexto: ContextoDeEjecucion(ejecucion: "sim-\(g.nombre)", agente: slug, disparo: disparo, simulado: true),
                paths: try AgentPaths(vaultState: estado, slug: slug), sesion: .new(UUID()), maxBudgetUSD: 0.5,
                mensaje: "Simulado", grabaciones: [g.nombre], variables: ["respuesta": "1", "hoy": "2026-10-19"])
            let contador = Contador()
            let r = await runtime.ejecutar(p, alEvento: { _ in contador.sumar() }, alArrancar: { _ in })
            #expect(r.simulado, "\(g.nombre)")
            #expect(r.estado == .completada, "\(g.nombre): \(r.estado) \(r.avisos)")
            #expect(r.veredicto == .permitido, "\(g.nombre)")
            #expect(contador.valor >= 3, "\(g.nombre)")
            #expect((r.costeUSD) > 0, "\(g.nombre)")
            if g.disparo != "chat" { #expect(r.finalizo && !(r.resumen ?? "").isEmpty, "\(g.nombre)") }
            if g.nombre == "contable-extracto-importado" { #expect(!r.preguntas.isEmpty, "La pregunta tiene que quedar pendiente") }
        }
    }

    final class Contador: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func sumar() { lock.withLock { n += 1 } }
        var valor: Int { lock.withLock { n } }
    }
}
