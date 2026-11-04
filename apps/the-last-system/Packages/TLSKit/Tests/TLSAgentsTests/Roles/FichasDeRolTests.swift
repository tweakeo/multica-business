import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// PLAN §4.3 `role`: la ficha de rol de cada asistente (`clase: agente`) es descriptiva; los permisos viven en
/// `config.yaml`. La puesta en marcha las crea con la configuración de serie, sin pisar nada.
@Suite("Asistentes de serie · fichas de rol y lo que escribe la puesta en marcha", .serialized)
struct FichasDeRolTests {
    @Test("La ficha: propiedades legibles, clase agente, ocupante y las secciones de la plantilla «Rol de asistente»")
    func ficha() throws {
        for p in PerfilDeAsistente.deSerie {
            let t = FichaDeRolDeAsistente.texto(p, rolHumano: p.area.flatMap(FichaDeRolDeAsistente.rolHumanoDeSerie))
            let doc = NoteDocument(text: t)
            let fm = doc.frontmatter
            #expect(fm.isValid, "\(p.slug)")
            #expect(fm.text("tls_type") == "role" && fm.text("tls_schema") == "1" && fm.text("clase") == "agente")
            #expect(fm.text("ocupante") == "agente:\(p.slug)" && fm.titleText == p.nombre)
            #expect(fm.text("id") == FichaDeRolDeAsistente.id(p.slug))
            #expect(UUID(uuidString: fm.text("id") ?? "") != nil)
            #expect((fm.text("rol")?.hasPrefix("[[") ?? false) == (p.area != nil), "\(p.slug)")
            #expect(doc.heading == "\(p.nombre) (asistente)")
            for s in ["Misión", "Decide sin preguntar", "Puede solo", "Puede con tu OK", "Nunca", "Qué recibe y qué entrega",
                      "Cuándo te pregunta", "Escalera de autonomía", "Coste", "Números", "Sistemas", "Rutinas", "Instrucciones"] {
                #expect(MarkdownSections.content(of: s, in: doc.body) != nil, "\(p.slug): falta «\(s)»")
            }
            let nunca = try #require(MarkdownSections.content(of: "Nunca", in: doc.body))
            #expect(nunca.contains("Enviar, publicar, facturar, pagar o escribir a clientes sin tu OK"))
            #expect(doc.body.contains("cambiar esta ficha no le da permisos"))
            // El cuerpo se enseña tal cual: sin jerga (la propiedad `ocupante` es un identificador, no se enseña así).
            #expect(ApoyoRoles.palabrasDeJerga(doc.body).isEmpty, "\(p.slug): \(ApoyoRoles.palabrasDeJerga(doc.body))")
        }
        // Las rutinas, en palabras.
        let mika = FichaDeRolDeAsistente.texto(.mika)
        #expect(mika.contains("- ¿Algo rojo? · de lunes a viernes a las 08:45 (solo si hay algo en rojo)"))
        #expect(mika.contains("- Resumen de la semana · los lunes a las 08:00"))
        #expect(FichaDeRolDeAsistente.texto(.contable).contains("el día 1 de enero, abril, julio y octubre a las 09:00"))
        #expect(FichaDeRolDeAsistente.texto(.contable).contains("el día 5 de cada mes a las 09:00"))
        #expect(FichaDeRolDeAsistente.ruta("mika", layout: .humana).raw == "6 · Equipo/Roles/asistente-mika.md")
    }

    @Test("En una empresa nueva: la configuración y las ocho fichas, en un solo plan de la persona; la segunda vez, nada")
    func empresaNueva() async throws {
        let root = try ApoyoRoles.temporal("nueva")
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".tls"), withIntermediateDirectories: true)
        try "{\"preset\":\"humana\"}\n".write(to: root.appendingPathComponent(".tls/layout.json"), atomically: true, encoding: .utf8)
        let config = "version: 1\nid: 11111111-2222-4333-8444-555555555555\nclase: copia\nprivado: []\n"
        try config.write(to: root.appendingPathComponent(".tls/config.yaml"), atomically: true, encoding: .utf8)
        let estados: [AreaCode: AreaStatus] = [.direccion: .activa, .ventas: .activa, .entrega: .preparada, .finanzas: .activa,
                                               .marca: .reposo, .equipo: .reposo]
        let cambios = AsistentesDeSerie.cambios(root: root, estados: estados, semilla: "11111111")
        #expect(cambios.count == 9)
        let configNueva = try #require(cambios.first { $0.ruta.raw == ".tls/config.yaml" })
        #expect(configNueva.antes == config && configNueva.despues.hasPrefix(config))
        let c = ConfigAgentes.leer(yaml: configNueva.despues)
        #expect(c.activos.map(\.slug) == ["comercial", "contable", "mika", "ordenador"])   // Entrega solo preparada
        #expect(Set(cambios.filter { $0.antes == nil }.map(\.ruta.raw)) == Set(PerfilDeAsistente.deSerie.map { "6 · Equipo/Roles/asistente-\($0.slug).md" }))
        // Sin la ficha del rol de la persona, la del asistente no enlaza a nada (no deja enlaces rotos).
        #expect(cambios.allSatisfy { !$0.despues.contains("rol: \"[[") })

        // Se escribe como la persona, con el escritor de la carpeta.
        let estado = try ApoyoRoles.temporal("estado")
        let asup = try ApoyoRoles.temporal("asup")
        defer { try? fm.removeItem(at: estado); try? fm.removeItem(at: asup) }
        let plan = try #require(AsistentesDeSerie.plan(root: root, persona: "Manu", estados: estados, semilla: "11111111"))
        #expect(plan.autor == .persona("Manu") && plan.ops.count == 9)
        let entry = VaultEntry(nombre: "Nueva", ruta: root.path, bookmark: nil, clase: .copia, escritura: .permitida)
        let writer = try await VaultWriter.open(entry: entry, root: root,
                                                options: VaultWriter.Options(stateDirectory: estado, appSupport: asup, app: "The Last System pruebas"))
        _ = try await CommandBus(writer: writer).ejecutar(plan)
        await writer.close()
        #expect(AsistentesDeSerie.cambios(root: root, estados: estados, semilla: "11111111").isEmpty)
        #expect(fm.fileExists(atPath: root.appendingPathComponent("6 · Equipo/Roles/asistente-contable.md").path))
        // Una ficha que ya está no se toca, aunque la persona la haya cambiado.
        let url = root.appendingPathComponent("6 · Equipo/Roles/asistente-mika.md")
        try (ApoyoRoles.texto(url)! + "\nNota mía.\n").write(to: url, atomically: true, encoding: .utf8)
        #expect(AsistentesDeSerie.cambios(root: root, estados: estados).isEmpty)
    }
}
