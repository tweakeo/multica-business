import CryptoKit
import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Manual (PLAN §6.8): el manual corto, «De dónde salen las ideas», «Saber más» de cada paso y la búsqueda.
@Suite("Manual")
@MainActor
struct ManualTests {
    static var carpeta: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Manual").standardizedFileURL
    }

    let biblioteca = ManualBiblioteca.cargar(ManualTests.carpeta)

    @Test("Dos documentos: el manual corto y «De dónde salen las ideas»; el método largo viaja pero no se enseña")
    func documentos() {
        #expect(biblioteca.documentos.map(\.titulo) == ["Manual corto", "De dónde salen las ideas"])
        #expect(!biblioteca.documentos.contains { $0.titulo.contains("TLB") })
        #expect(FileManager.default.fileExists(atPath: Self.carpeta.appendingPathComponent(ManualBiblioteca.ficheroMetodo).path))
        // Ids únicos.
        let ids = biblioteca.secciones.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("El manual corto explica las áreas, qué es un sistema, decidir, relaciones y asistentes")
    func manualCorto() throws {
        for id in ["empezar", "hoy", "areas", "sistema", "etapas", "decidir", "relaciones", "tareas", "ventas", "banco",
                   "carpeta", "privado", "asistentes", "palabras", "conexiones", "relevo"] {
            #expect(biblioteca.seccion(id) != nil, "Falta la sección «\(id)»")
        }
        let sistema = try #require(biblioteca.seccion("sistema"))
        #expect(sistema.texto.contains("una carpeta con el qué, el cómo, ejemplos y una forma de comprobarlo"))
        let areas = try #require(biblioteca.seccion("areas"))
        for a in AreaCode.allCases { #expect(areas.texto.contains(a.nombre)) }
        let asistentes = try #require(biblioteca.seccion("asistentes"))
        #expect(asistentes.texto.contains("Lo que **sí** hacen") && asistentes.texto.contains("Lo que **no** hacen nunca"))
    }

    @Test("«Saber más»: cada paso del tutorial y de la puesta en marcha abre una sección que existe")
    func saberMas() {
        for p in Recorridos.pasos(.ejemplo) + Recorridos.pasos(.tuEmpresa, contexto: .init(ficha: nil, cuello: .ventas)) {
            #expect(biblioteca.seccion(p.manual) != nil, "«\(p.titulo)» abre «\(p.manual)», que no existe")
        }
        for paso in PasoPuesta.allCases {
            #expect(biblioteca.seccion("paso-\(paso.rawValue)") != nil, "Falta «paso-\(paso.rawValue)»")
        }
        #expect(biblioteca.seccion(ManualNavegacion.seccionIdeas) != nil)
    }

    @Test("«De dónde salen las ideas»: las cinco ideas, reformuladas, con qué cambia en la app")
    func ideas() throws {
        for id in ["idea-1-3-1", "idea-entrevistador", "idea-seguimiento", "idea-transferencia", "idea-una-coleccion"] {
            let s = try #require(biblioteca.seccion(id), "Falta «\(id)»")
            #expect(s.texto.contains("reformulada"))
            #expect(s.texto.contains("**Qué hace la app:**"))
            #expect(s.texto.contains("**Qué cambia aquí:**"))
        }
        let doc = try #require(biblioteca.documentos.last)
        #expect(doc.entradilla.contains("no se copia ningún texto de ningún curso"))
    }

    @Test("Buscar: sin tildes ni mayúsculas, primero lo que lo tiene en el título")
    func buscar() throws {
        let r = biblioteca.buscar("CUELLO")
        #expect(r.first?.seccion.id == "etapas")
        #expect(r.allSatisfy { $0.seccion.plegado.contains("cuello") })
        #expect(biblioteca.buscar("decision registro").contains { $0.seccion.id == "decidir" })
        #expect(biblioteca.buscar("palabraquenoexiste").isEmpty)
        #expect(biblioteca.buscar("   ").isEmpty)
        let extracto = try #require(r.first?.extracto)
        #expect(extracto.lowercased().contains("cuello"))
    }

    @Test("Bloques: subtítulos, listas numeradas y con viñeta, citas y párrafos")
    func bloques() {
        let b = ManualBiblioteca.bloques("Un párrafo\nque sigue.\n\n### Sub\n- uno\n- dos\n  y más\n\n1. a\n2. b\n\n> cita")
        #expect(b == [.parrafo("Un párrafo que sigue."), .subtitulo("Sub"), .lista(["uno", "dos y más"], numerada: false),
                      .lista(["a", "b"], numerada: true), .cita("cita")])
        #expect(ManualBiblioteca.encabezado("Qué es un sistema {#sistema}") == ("Qué es un sistema", "sistema"))
        #expect(ManualBiblioteca.encabezado("Sin ancla") == ("Sin ancla", nil))
        #expect(ManualBiblioteca.slug("Cómo decidir") == "como-decidir")
    }

    @Test("Español llano: ningún texto del manual usa jerga del glosario")
    func glosario() throws {
        let prohibidas = ["frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "vault", "hash", "kpi", "csv",
                          "agente", "agentes"]
        for s in biblioteca.secciones {
            let palabras = Set(TextFolding.fold(s.titulo + " " + s.texto).split(whereSeparator: { !$0.isLetter }).map(String.init))
            for p in prohibidas { #expect(!palabras.contains(p), "«\(s.titulo)» usa «\(p)»") }
        }
        for d in biblioteca.documentos {
            let palabras = Set(TextFolding.fold(d.entradilla).split(whereSeparator: { !$0.isLetter }).map(String.init))
            for p in prohibidas { #expect(!palabras.contains(p), "La entradilla de «\(d.titulo)» usa «\(p)»") }
        }
    }

    @Test("MANUAL-TLB.md se copió una vez, sin cambios (su SHA-256 está en PROCEDENCIA)")
    func copiaDelMetodo() throws {
        let datos = try Data(contentsOf: Self.carpeta.appendingPathComponent(ManualBiblioteca.ficheroMetodo))
        let h = SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
        #expect(h == "1ac9ec4f5623d254aac40ce9195027712e7abdc4314612d59b5e564e9791e9a6")
        let procedencia = try String(contentsOf: Self.carpeta.appendingPathComponent("../../../docs/PROCEDENCIA.md").standardizedFileURL,
                                     encoding: .utf8)
        #expect(procedencia.contains(h))
    }

    @Test("La navegación del manual abre la sección pedida y vacía la búsqueda")
    func navegacion() {
        let n = ManualNavegacion()
        n.busqueda = "cuello"
        n.abrir("sistema")
        #expect(n.seccion == "sistema")
        #expect(n.busqueda.isEmpty)
        n.abrir("")
        #expect(n.seccion == nil)
    }
}
