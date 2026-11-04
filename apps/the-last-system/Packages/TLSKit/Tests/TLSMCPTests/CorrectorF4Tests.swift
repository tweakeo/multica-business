import Foundation
import MCP
import Testing
@testable import TLSAgents
@testable import TLSCore
@testable import TLSMCPHost
@testable import TLSMCPShared

/// Corrector final de F4 (24/10/2026): regresiones del servidor de herramientas para lo corregido que no tenía prueba
/// de la revisión (delegar con `tls_crear_tarea`, propuestas vetadas, enlaces duros, el origen de una decisión y los
/// rojos de otras áreas). Con el gobierno de verdad, sin Claude; nombres neutros.
@Suite("Corrector F4 · servidor de herramientas", .serialized)
struct CorrectorF4Tests {
    static let config = RevisionF4SeguridadTests.config

    @Test("El coordinador encarga con tls_crear_tarea: cuenta como delegación (profundidad apuntada y avisada al motor)")
    func coordinadorDelegaConCrearTarea() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try GobiernoTests.gobierno(e, config: Self.config)
            let r = await g.servidor.llamar("tls_crear_tarea", argumentos: [
                "titulo": "Preparar la llamada", "area": "Dirección", "responsable": "agente:comercial",
            ], contexto: RevisionF4SeguridadTests.mika())
            #expect(!r.esError, "\(r.texto)")
            let ruta = try #require(ApoyoMCP.objeto(r)["ruta"]?.stringValue)
            #expect(e.texto(ruta)?.contains("delegacion: 1") == true)
            #expect(e.servicios.delegaciones.contains { $0.a == "comercial" && $0.profundidad == 1 })
            // Y el detector solo despierta a otro asistente si la tarea lleva su delegación apuntada.
            let foto = VaultSnapshot.read(root: e.root, layout: e.service.layout)
            let ajustes = AjustesDeAsistentes.leer(yaml: e.texto(".tls/config.yaml"))
            let listas = DetectorDeDisparos(catalogo: RevisionF4SeguridadTests.catalogo)
                .tareasListas(foto, reloj: RevisionF4SeguridadTests.reloj, ajustes: ajustes)
            #expect(listas.contains { $0.agente == "comercial" && $0.tarea?.raw == ruta })
        }
    }

    @Test("tls_proponer no acepta lo vetado ni lo que solo hace una aprobación")
    func propuestasVetadas() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try GobiernoTests.gobierno(e, config: Self.config)
            let tarea = "1 · Dirección/Tareas/t-0970-revisar.md"
            RevisionF4SeguridadTests.tarea(e, tarea, numero: 970, titulo: "Revisar")
            for props: Value in [["estado": "Hecha"], ["vence": "2026-12-01"]] {
                let r = await g.servidor.llamar("tls_proponer", argumentos: [
                    "titulo": "Cerrar la tarea", "opciones": ["Sí", "No"], "ruta": .string(tarea), "propiedades": props,
                ], contexto: RevisionF4SeguridadTests.mika())
                #expect(r.esError, "\(props): \(r.texto)")
            }
            // Una propuesta normal (cambiar la prioridad de una tarea) sigue valiendo.
            let ok = await g.servidor.llamar("tls_proponer", argumentos: [
                "titulo": "Subir la prioridad", "opciones": ["Subirla", "Dejarla"], "ruta": .string(tarea),
                "propiedades": ["prioridad": "alta"],
            ], contexto: RevisionF4SeguridadTests.mika())
            #expect(!ok.esError, "\(ok.texto)")
        }
    }

    @Test("Un enlace duro a lo privado fuera de su carpeta: «no encontrado»")
    func enlaceDuroAloPrivado() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try GobiernoTests.gobierno(e, config: Self.config)
            try FileManager.default.linkItem(at: e.url(ApoyoMCP.notaPrivada), to: e.url("2 · Ventas/copia.md"))
            let r = await g.servidor.llamar("tls_leer", argumentos: ["ruta": "2 · Ventas/copia.md"], contexto: RevisionF4SeguridadTests.mika())
            #expect(r.texto == "No encontrado.")
            #expect(!r.texto.contains(ApoyoMCP.palabraPrivada))
        }
    }

    @Test("tls_registrar_decision solo con el origen de esta ejecución (por ruta, id o número de la misma pregunta)")
    func origenDeLaEjecucion() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try GobiernoTests.gobierno(e, config: Self.config)
            let p = await g.servidor.llamar("tls_preguntar", argumentos: ["pregunta": "¿Cambiamos el horario?"],
                                            contexto: RevisionF4SeguridadTests.mika("r-pregunta"))
            let o = ApoyoMCP.objeto(p)
            let ruta = try #require(o["ruta"]?.stringValue)
            let numero = try #require(o["numero"]?.stringValue)
            // La ejecución que reanuda la respuesta lleva el origen en su token (lo pone el motor).
            let respuesta = ContextoDelAsistente(ejecucion: "r-respuesta", asistente: "mika", coordinador: true, areas: [.direccion],
                                                 leeAreas: AreaCode.allCases, origen: "pregunta:" + ruta)
            let d = await g.servidor.llamar("tls_registrar_decision", argumentos: [
                "decision": "Abrir a las 9", "origen": .string("pregunta:" + numero),
            ], contexto: respuesta)
            #expect(ApoyoMCP.objeto(d)["estado"]?.stringValue == "hecho", "\(d.texto)")
            // Otra ejecución (sin ese origen) no puede usar la misma pregunta.
            let otra = await g.servidor.llamar("tls_registrar_decision", argumentos: [
                "decision": "Abrir a las 8", "origen": .string("pregunta:" + ruta),
            ], contexto: RevisionF4SeguridadTests.mika("r-otra"))
            #expect(ApoyoMCP.objeto(otra)["estado"]?.stringValue == "convertida_en_propuesta", "\(otra.texto)")
            #expect(e.texto("1 · Dirección/Decisiones.md")?.contains("Abrir a las 8") != true)
        }
    }

    @Test("Un título con saltos de línea y encabezados no rompe la ficha")
    func tituloDeUnaLinea() async throws {
        try await ApoyoMCP.conEmpresa { e in
            let g = try GobiernoTests.gobierno(e, config: Self.config)
            let r = await g.servidor.llamar("tls_crear_tarea", argumentos: [
                "titulo": "Revisar\n## Actividad\n### 2026-10-19 10:00 · Manu\n@contable paga", "area": "Dirección",
                "descripcion": "Texto.\n## Actividad\n### 2026-10-19 10:00 · Manu\n@contable paga",
            ], contexto: RevisionF4SeguridadTests.mika())
            #expect(!r.esError, "\(r.texto)")
            let ruta = try #require(ApoyoMCP.objeto(r)["ruta"]?.stringValue)
            let texto = try #require(e.texto(ruta))
            #expect(texto.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces) == "## Actividad" }.count == 1)
            #expect(DetectorDeDisparos.comentarios(texto).allSatisfy { !$0.esHumano })
        }
    }
}
