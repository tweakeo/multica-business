import Foundation
import MCP
import Testing
@testable import TLSCore
@testable import TLSMCPHost

/// Lo que ve un asistente (PLAN §8, capas 1, 2, 3 y 7): lo privado, `.tls/`, los secretos y los enlaces simbólicos
/// responden «no encontrado», igual que lo que no existe.
@Suite(.serialized)
struct AgentViewTests {
    @Test func loPrivadoNoSeEncuentraPorNingunCamino() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let vista = AgentView(service: e.service)
            #expect(e.existe(ApoyoMCP.notaPrivada), "la nota privada existe en disco")
            let variantes = [
                ApoyoMCP.notaPrivada,
                "./" + ApoyoMCP.notaPrivada,
                ApoyoMCP.notaPrivada.lowercased(),
                ApoyoMCP.notaPrivada.decomposedStringWithCanonicalMapping,  // NFD
                "4 · Finanzas/Registros/../Expediente privado/nota.md",
                "/" + ApoyoMCP.notaPrivada,
                ApoyoMCP.privada,
            ]
            for v in variantes {
                if case .texto = vista.leer(v) { Issue.record("se leyó lo privado con «\(v)»") }
                #expect(vista.resolver(v).ruta == nil, "«\(v)» no debe resolverse")
            }
            #expect(vista.resolver(ApoyoMCP.notaPrivada) == .no(.privada))
            // Ni en la lista de su carpeta ni en la búsqueda.
            let finanzas = try #require(vista.listar("4 · Finanzas"))
            #expect(!finanzas.contains { $0.ruta.name == "Expediente privado" })
            #expect(vista.buscar(ApoyoMCP.palabraPrivada).isEmpty)
            #expect(vista.listar(ApoyoMCP.privada) == nil)
        }
    }

    @Test func laCarpetaTlsEsInvisible() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let vista = AgentView(service: e.service)
            #expect(e.existe(".tls/config.yaml"))
            #expect(vista.resolver(".tls/config.yaml") == .no(.oculta))
            if case .texto = vista.leer(".tls/config.yaml") { Issue.record("se leyó .tls/config.yaml") }
            #expect(vista.listar(".tls") == nil)
            let raiz = try #require(vista.listar(""))
            #expect(!raiz.contains { $0.ruta.name.hasPrefix(".") })
            #expect(raiz.contains { $0.ruta.name == "Empresa.md" })
        }
    }

    @Test func secretosYEnlacesSimbolicos() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let vista = AgentView(service: e.service)
            for p in ["4 · Finanzas/secrets.env", "Buzón/cookies.txt", "2 · Ventas/certificado.key"] {
                #expect(e.existe(p))
                #expect(vista.resolver(p) == .no(.patronDenegado), "«\(p)»")
            }
            #expect(vista.resolver("2 · Ventas/enlace.md") == .no(.enlaceSimbolico))
            #expect(vista.listar("2 · Ventas")?.contains { $0.ruta.name == "enlace.md" || $0.ruta.name == "certificado.key" } == false)
            #expect(vista.resolver("../fuera.md") == .no(.fueraDeLaCarpeta))
        }
    }

    @Test func leeComoMucho64KBSinPartirCaracteres() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let grande = String(repeating: "ñandú ", count: 20_000)  // ~140 KB
            try ("# Grande\n" + grande).write(to: e.url("1 · Dirección/Grande.md"), atomically: true, encoding: .utf8)
            let vista = AgentView(service: e.service)
            guard case .texto(_, let contenido, let recortado, _) = vista.leer("1 · Dirección/Grande.md") else {
                Issue.record("no se leyó"); return
            }
            #expect(recortado)
            #expect(contenido.utf8.count <= AgentView.maximoLectura)
            #expect(!contenido.contains("\u{FFFD}"))
        }
    }

    @Test func fueraDeSusAreas() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let vista = AgentView(service: e.service)
            let soloVentas = Alcance(areas: [.ventas], buzon: false)
            #expect(vista.resolver("2 · Ventas/Contactos/marta-soler.md", alcance: soloVentas).ruta != nil)
            #expect(vista.resolver("4 · Finanzas/Registros/pagos.csv", alcance: soloVentas) == .no(.fueraDeAlcance))
            #expect(vista.resolver("Buzón/Informe de importación 2026-10-19.md", alcance: soloVentas) == .no(.fueraDeAlcance))
            // Lo privado sigue siendo «no encontrado» aunque además esté fuera de su área.
            #expect(vista.resolver(ApoyoMCP.notaPrivada, alcance: soloVentas) == .no(.privada))
        }
    }

    @Test func laHerramientaRespondeNoEncontradoYQuedaAuditado() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let s = e.servidor()
            let c = ApoyoMCP.contexto()
            let r = await s.llamar("tls_leer", argumentos: ["ruta": .string(ApoyoMCP.notaPrivada)], contexto: c)
            #expect(r.esError)
            #expect(r.texto == "No encontrado.")
            let inexistente = await s.llamar("tls_leer", argumentos: ["ruta": "4 · Finanzas/no-existe.md"], contexto: c)
            #expect(inexistente.texto == r.texto, "lo privado y lo que no existe se responden igual")
            let tls = await s.llamar("tls_leer", argumentos: ["ruta": ".tls/config.yaml"], contexto: c)
            #expect(tls.texto == "No encontrado.")
            let eventos = e.auditoria.eventos.filter { $0.accion == "leer" && $0.veredicto == "no_encontrado" }
            #expect(eventos.contains { $0.motivo == "privada" && $0.asistente == "mika" })
            #expect(eventos.contains { $0.motivo == "oculta" })
            // La búsqueda tampoco lo trae.
            let b = await s.llamar("tls_buscar", argumentos: ["consulta": .string(ApoyoMCP.palabraPrivada)], contexto: c)
            #expect(!b.texto.contains(ApoyoMCP.palabraPrivada) || b.texto.hasPrefix("Sin resultados"))
            #expect(ApoyoMCP.objeto(b)["resultados"]?.arrayValue?.isEmpty == true)
        }
    }
}
