import Foundation
import Testing
@testable import TLSCore

@Suite("Adoptar una carpeta G3")
struct AdoptarTests {
    @Test func identidadSoloEnFichasSinId() throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let p = Adopter(snapshot: env.foto()).proponer()
        let porRuta = Dictionary(uniqueKeysWithValues: p.identidades.map { ($0.ruta.raw, $0) })
        #expect(porRuta["2 · Ventas/Contactos/Lucía Prueba.md"]?.tipo == "contact")
        #expect(porRuta["2 · Ventas/Contactos/José Núñez.md"]?.tipo == "contact")
        #expect(porRuta["2 · Ventas/Empresas/Ferretería Ejemplo.md"]?.tipo == "organization")
        let proyecto = try #require(porRuta["3 · Entrega/Proyectos/web-ferreteria/Proyecto.md"])
        #expect(proyecto.anadir.map(\.key) == ["tls_type", "tls_schema", "id", "clase"])
        #expect(proyecto.anadir.last?.value == .text("entrega"))
        // La tarea ya tiene tipo: solo le falta `tls_schema` e `id`.
        #expect(porRuta["3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md"]?.anadir.map(\.key) == ["tls_schema", "id"])
        // La oportunidad ya tiene id; las notas índice, de área, de sistema, el Archivo y lo privado no se tocan.
        #expect(porRuta["2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md"] == nil)
        #expect(porRuta["2 · Ventas/Contactos/Contactos.md"] == nil)
        #expect(porRuta["2 · Ventas/Área.md"] == nil)
        #expect(porRuta["2 · Ventas/Sistemas/Embudo.md"] == nil)
        #expect(porRuta["Archivo/2025/Propuesta antigua.md"] == nil)
        #expect(porRuta["Empresa.md"] == nil)
        #expect(p.identidades.count == 5)
    }

    @Test func aplicarIdentidadSoloAnadeEsasLineas() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let antes = env.huella()
        let textoAntes = env.texto("2 · Ventas/Contactos/Lucía Prueba.md")!
        let p = Adopter(snapshot: env.foto()).proponer()
        _ = try await (try await env.bus()).ejecutar(try #require(p.planIdentidad()))
        let cambiados = Set(env.huella().filter { antes[$0.key] != $0.value }.keys)
        #expect(cambiados == Set(p.identidades.map(\.ruta.raw)))
        let lucia = env.texto("2 · Ventas/Contactos/Lucía Prueba.md")!
        // Las líneas añadidas van arriba (orden canónico) y el resto queda igual, byte a byte.
        let sinNuevas = lucia.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("tls_type:") && !$0.hasPrefix("tls_schema:") && !$0.hasPrefix("id:") }
            .joined(separator: "\n")
        #expect(sinNuevas == textoAntes)
        #expect(lucia.hasPrefix("---\ntls_type: contact\ntls_schema: 1\nid: "))
        // `tipo: persona` heredado se conserva.
        #expect(lucia.contains("\ntipo: persona\n"))
        // Ya adoptada: nada más que proponer.
        #expect(Adopter(snapshot: env.foto()).proponer().identidades.isEmpty)
    }

    @Test func relacionesDeducidasEnUnaTarjeta() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        let bus = try await env.bus()
        _ = try await bus.ejecutar(try #require(Adopter(snapshot: env.foto()).proponer().planIdentidad()))
        let p = Adopter(snapshot: env.foto()).proponer()
        func rel(_ ruta: String, _ clave: String) -> PropuestaAdopcion.Relacion? {
            p.relaciones.first { $0.ruta.raw == ruta && $0.clave == clave }
        }
        let opEmpresa = try #require(rel("2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md", "empresa"))
        #expect(opEmpresa.valor == "[[Ferretería Ejemplo]]")
        #expect(opEmpresa.quitar == ["empresa_id"])
        #expect(rel("2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md", "contacto")?.valor == "[[Lucía Prueba]]")
        #expect(rel("3 · Entrega/Proyectos/web-ferreteria/Proyecto.md", "oportunidad")?.destino.raw == "2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md")
        let tarea = try #require(rel("3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md", "proyecto"))
        #expect(tarea.fuente == .ruta)
        // Lucía ya tiene `empresa`: no se propone nada.
        #expect(rel("2 · Ventas/Contactos/Lucía Prueba.md", "empresa") == nil)
        let plan = try #require(p.planRelaciones())
        _ = try await bus.ejecutar(plan)
        let op = env.texto("2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md")!
        #expect(op.contains("empresa: \"[[Ferretería Ejemplo]]\"\n"))
        #expect(!op.contains("empresa_id"))
        #expect(Adopter(snapshot: env.foto()).proponer().relaciones.isEmpty)
    }

    @Test func idHeredadoPasaAEnlace() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("2 · Ventas/Contactos/Ana Ruiz.md", "---\ntls_type: contact\nid: c-ana\nempresa_id: 6f1c2a9e-0000-4000-8000-000000000001\n---\n# Ana Ruiz\n")
        env.escribir("2 · Ventas/Empresas/Otra.md", "---\ntls_type: organization\nid: org-otra\n---\n# Otra SL\n")
        env.escribir("2 · Ventas/Oportunidades/dos-empresas.md", "---\ntls_type: opportunity\nid: o-2\n---\nCon [[Otra]] y [[Ferretería Ejemplo]].\n")
        let p = Adopter(snapshot: env.foto()).proponer()
        // `empresa_id` apunta a la oportunidad, que no es una empresa: igualmente es lo que dice la ficha.
        let ana = try #require(p.relaciones.first { $0.ruta.raw == "2 · Ventas/Contactos/Ana Ruiz.md" })
        #expect(ana.fuente == .idHeredado("empresa_id"))
        #expect(ana.destino.raw == "2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md")
        #expect(ana.quitar == ["empresa_id"])
        // Dos empresas en el cuerpo: no se elige ninguna.
        #expect(p.ambiguas.contains { $0.ruta.raw == "2 · Ventas/Oportunidades/dos-empresas.md" && $0.clave == "empresa" && $0.candidatos.count == 2 })
        #expect(!p.relaciones.contains { $0.ruta.raw == "2 · Ventas/Oportunidades/dos-empresas.md" && $0.clave == "empresa" })
    }

    @Test func tareasHeredadasEnLaPropuesta() {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima)
        defer { env.limpiar() }
        env.escribir("3 · Entrega/Tareas.md", "# Tareas\n")
        let p = Adopter(snapshot: env.foto()).proponer()
        #expect(p.tareasHeredadas.map(\.raw) == ["3 · Entrega/Tareas.md"])
        #expect(p.resumen.hasPrefix("5 fichas por identificar"))
    }

    @Test func riberaYaEstaAdoptada() {
        let p = Adopter(snapshot: VaultSnapshot.read(root: RutasRepo.ribera)).proponer()
        #expect(p.identidades.isEmpty, "\(p.identidades.map(\.ruta.raw))")
    }
}
