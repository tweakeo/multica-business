import Foundation
import Testing
@testable import TLSCore

/// Lectura de la fixture EmpresaMinima a través del servicio completo.
@Suite(.serialized) struct VaultServiceTests {
    /// Abre la fixture del bundle con el índice en una carpeta temporal.
    func abrir(_ body: (VaultService) async throws -> Void) async throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        let svc = try Apoyo.servicio(Apoyo.empresaMinima, state: state)
        _ = try await svc.open { _ in }
        try await body(svc)
        svc.close()
    }

    @Test func areasConSuEstado() async throws {
        try await abrir { svc in
            let areas = svc.areas()
            #expect(areas.map(\.code) == AreaCode.allCases)
            #expect(areas.map(\.estado) == [.activa, .preparada, .preparada, .activa, .reposo, .reposo])
            let dir = areas[0]
            #expect(dir.titulo == "Dirección")
            #expect(dir.folder == VaultPath("1 · Dirección"))
            #expect(dir.lleva == "Ana, con el asistente coordinador")
            #expect(dir.rol == "Ana elige; el asistente ordena las notas.")
            #expect(dir.transforma == "Las ideas sueltas del estudio en prioridades claras para el trimestre, con una persona al frente de cada una.")
            #expect(dir.sistemas.map(\.nombre) == ["Plan del estudio", "Elegir proyectos"])
            #expect(dir.sistemas[0].path == VaultPath("1 · Dirección/Sistemas/Plan del estudio.md"))
            #expect(dir.sistemas[0].resumen == "ordena el Rumbo y la portada de Empresa.")
            let ven = areas[1]
            #expect(ven.estadoTexto == "preparada, sin activar (se activa en enero)")
            #expect(ven.sistemas[1].nombre == "Registro de contactos")
            #expect(ven.sistemas[1].path == VaultPath("2 · Ventas/Sistemas/Registro de contactos.md"))
            let fin = areas[3]
            #expect(fin.lleva == "Ana y el asistente Contable")
            #expect(fin.sistemas[0].resumen == nil)
            #expect(fin.sistemas[1].resumen == "con sus pasos: anotar ticket.")
            #expect(fin.transforma?.contains("los CSV de Registros.") == true)
            let equ = areas[5]
            #expect(equ.sistemas.map(\.nombre) == ["Colaboradores", "Asistentes"])
            #expect(equ.sistemas.allSatisfy { $0.path != nil && $0.resumen == nil })
        }
    }

    @Test func childrenOrdenadoYSinOcultos() async throws {
        try await abrir { svc in
            let root = svc.children(of: .root)
            let names = root.map(\.path.name)
            #expect(!names.contains(".tls"))
            #expect(names == ["1 · Dirección", "2 · Ventas", "3 · Entrega", "4 · Finanzas", "5 · Marca", "6 · Equipo",
                              "Archivo", "Buzón", "Privado", "AGENTS.md", "Empresa.md"])
            #expect(root.first { $0.path.name == "Privado" }?.privado == true)
            #expect(root.first { $0.path.name == "Empresa.md" }?.size ?? 0 > 0)
            let contactos = svc.children(of: VaultPath("2 · Ventas/Contactos"))
            // El nombre en NFD se devuelve en NFC.
            #expect(contactos.map(\.path.name) == ["Contactos.md", "José Núñez.md", "Lucía Prueba.md"])
            #expect(svc.children(of: VaultPath("../")).isEmpty)
            #expect(svc.children(of: VaultPath(".tls")).isEmpty)
        }
    }

    @Test func leerMarkdownCSVyOtros() async throws {
        try await abrir { svc in
            guard case .markdown(_, let props, let body, let title, let kind) = svc.read(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")) else {
                Issue.record("debería ser Markdown"); return
            }
            #expect(title == "Lucía Prueba")
            #expect(kind == .contact)
            #expect(props.first?.key == "tipo")
            #expect(props.first { $0.key == "alta" }?.value == .text("2026-10-21"))
            #expect(body.hasPrefix("\n# Lucía Prueba"))

            guard case .csv(let header, let rows, _) = svc.read(VaultPath("4 · Finanzas/Registros/emitidas.csv")) else {
                Issue.record("debería ser CSV"); return
            }
            #expect(header == ["id", "fecha", "cliente", "concepto", "importe"])
            #expect(rows.count == 2)
            #expect(rows[0][2] == "Ferretería Ejemplo, S.L.")
            #expect(rows[0][3] == "Web \"básica\"")
            #expect(rows[1][3].contains("mensual"))

            guard case .plain = svc.read(VaultPath("../Empresa.md")) else {
                if case .unreadable = svc.read(VaultPath("../Empresa.md")) {} else { Issue.record("no debe salir de la carpeta") }
                return
            }
            Issue.record("no debe salir de la carpeta")
        }
    }

    @Test func notaEnNFD() async throws {
        try await abrir { svc in
            let nfc = VaultPath("2 · Ventas/Contactos/José Núñez.md")
            #expect(svc.summary(of: nfc)?.title == "José Núñez")
            #expect(svc.summary(of: nfc)?.kind == .contact)
            if case .markdown(_, _, _, let title, _) = svc.read(VaultPath("2 · Ventas/Contactos/Jose\u{301} Nu\u{301}n\u{303}ez.md")) {
                #expect(title == "José Núñez")
            } else {
                Issue.record("la ruta en NFD también debe leerse")
            }
        }
    }

    @Test func tiposYPropiedadesEnElIndice() async throws {
        try await abrir { svc in
            func kind(_ p: String) -> NoteKind? { svc.summary(of: VaultPath(p))?.kind }
            #expect(kind("Empresa.md") == .company)
            #expect(kind("1 · Dirección/Área.md") == .area)
            #expect(kind("2 · Ventas/Sistemas/Embudo.md") == .system)
            #expect(kind("2 · Ventas/Empresas/Ferretería Ejemplo.md") == .organization)
            #expect(kind("2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md") == .opportunity)
            #expect(kind("3 · Entrega/Proyectos/web-ferreteria/Proyecto.md") == .project)
            #expect(kind("3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md") == .task)
            #expect(kind("4 · Finanzas/Registros/emitidas.csv") == .csv)
            #expect(svc.summary(of: VaultPath("3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md"))?.title
                    == "Preparar la reunión de arranque")
            #expect(svc.summary(of: VaultPath("2 · Ventas/Sistemas/Embudo.md"))?.area == .ventas)
            #expect(svc.summary(of: VaultPath("Privado/Expediente personal.md"))?.privado == true)
            #expect(svc.summary(of: VaultPath("Empresa.md"))?.privado == false)
        }
    }

    @Test func enlacesYBacklinks() async throws {
        try await abrir { svc in
            let lucia = VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")
            #expect(svc.resolveLink("[[Ferretería Ejemplo]]", from: lucia) == VaultPath("2 · Ventas/Empresas/Ferretería Ejemplo.md"))
            #expect(svc.resolveLink("Jos%C3%A9%20N%C3%BA%C3%B1ez.md", from: lucia) == VaultPath("2 · Ventas/Contactos/José Núñez.md"))
            #expect(svc.resolveLink("[[Embudo#Etapas]]", from: lucia) == VaultPath("2 · Ventas/Sistemas/Embudo.md"))
            #expect(svc.resolveLink("https://example.com", from: lucia) == nil)
            let fin = VaultPath("4 · Finanzas/Área.md")
            #expect(svc.resolveLink("<Gestoría/Asesor (Ejemplo).md>", from: fin) == VaultPath("4 · Finanzas/Gestoría/Asesor (Ejemplo).md"))

            let ferreteria = svc.backlinks(to: VaultPath("2 · Ventas/Empresas/Ferretería Ejemplo.md")).map(\.path.raw)
            // El cuerpo y la propiedad `empresa` de Lucía, y la oportunidad. Archivo/ no cuenta.
            #expect(Set(ferreteria) == ["2 · Ventas/Contactos/Lucía Prueba.md", "2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md"])
            let luciaBack = Set(svc.backlinks(to: lucia).map(\.path.raw))
            #expect(luciaBack == ["2 · Ventas/Contactos/Contactos.md", "2 · Ventas/Contactos/José Núñez.md",
                                  "2 · Ventas/Empresas/Ferretería Ejemplo.md", "2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md",
                                  "3 · Entrega/Proyectos/web-ferreteria/Tareas/t-0001-preparar-arranque.md"])
            let oportunidad = Set(svc.backlinks(to: VaultPath("2 · Ventas/Oportunidades/web-ferreteria-ejemplo.md")).map(\.path.raw))
            #expect(oportunidad == ["2 · Ventas/Contactos/Lucía Prueba.md", "3 · Entrega/Proyectos/web-ferreteria/Proyecto.md"])
        }
    }

    @Test func quickOpenTresLetras() async throws {
        try await abrir { svc in
            func top3(_ q: String) -> [String] { svc.quickOpen(q, limit: 3).map(\.path.name) }
            #expect(top3("fer").contains("Ferretería Ejemplo.md"))
            #expect(top3("nun").contains("José Núñez.md"))
            #expect(top3("emb").first == "Embudo.md")
            #expect(top3("FAC").contains("Facturación y cobros.md"))
            #expect(top3("luc").first == "Lucía Prueba.md")
            #expect(top3("arr").contains("t-0001-preparar-arranque.md"))
            // Archivo/: por nombre sí.
            #expect(svc.quickOpen("propuesta antigua", limit: 3).first?.path.raw == "Archivo/2025/Propuesta antigua.md")
            #expect(svc.quickOpen("", limit: 3).isEmpty)
        }
    }

    @Test func busquedaSinTildes() async throws {
        try await abrir { svc in
            let hits = svc.search("facturacion")
            #expect(hits.first?.note.path == VaultPath("4 · Finanzas/Sistemas/Facturación y cobros.md"))
            #expect(hits.first?.snippet.contains("‹Facturación›") == true)
            #expect(svc.search("nunez").contains { $0.note.path.raw == "2 · Ventas/Contactos/José Núñez.md" })
            #expect(svc.search("tipografias").count >= 2)
            // Prefijo: «arranq» encuentra «arranque».
            #expect(svc.search("arranq").contains { $0.note.kind == .task })
            // Lo que está en las propiedades también se encuentra.
            #expect(svc.search("lucia@example").contains { $0.note.path.raw == "2 · Ventas/Contactos/Lucía Prueba.md" })
            // Archivo/ no entra en el índice de contenido.
            #expect(svc.search("zanahoria").isEmpty)
            // Texto con sintaxis FTS no rompe.
            #expect(svc.search("\"(*").isEmpty)
        }
    }

    @Test func exclusionesNoSeListanNiSeLeen() async throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        let svc = try VaultService(entry: Apoyo.entrada(Apoyo.empresaMinima), root: Apoyo.empresaMinima,
                                   options: .init(excluidas: [VaultPath("Privado")], stateDirectory: state, vigilar: false))
        _ = try await svc.open { _ in }
        #expect(!svc.children(of: .root).contains { $0.path.name == "Privado" })
        #expect(svc.children(of: VaultPath("Privado")).isEmpty)
        #expect(svc.summary(of: VaultPath("Privado/Expediente personal.md")) == nil)
        if case .unreadable = svc.read(VaultPath("Privado/Expediente personal.md")) {} else {
            Issue.record("una ruta excluida no se lee")
        }
        #expect(svc.quickOpen("expediente").isEmpty)
        svc.close()
    }

    @Test func ningunaLecturaModificaLaFixture() async throws {
        let root = Apoyo.empresaMinima
        let antes = Apoyo.huellaDeArbol(root)
        #expect(antes.count > 30)
        #expect(antes.contains { $0.contains("/.tls/layout.json") })
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        let svc = try Apoyo.servicio(root, state: state, vigilar: true)
        let progreso = Caja<[IndexProgress]>([])
        let stats = try await svc.open { p in progreso.update { $0.append(p) } }
        #expect(stats.notes >= 30)
        #expect(stats.dataless == 0)
        #expect(progreso.value.last?.processed == progreso.value.last?.total)
        _ = svc.areas()
        var stack: [VaultPath] = [.root]
        while let f = stack.popLast() {
            for e in svc.children(of: f) {
                if e.isDirectory { stack.append(e.path) } else {
                    _ = svc.read(e.path)
                    _ = svc.backlinks(to: e.path)
                    _ = svc.summary(of: e.path)
                }
            }
        }
        _ = svc.quickOpen("a"); _ = svc.search("a")
        _ = svc.resolveLink("[[Embudo]]", from: VaultPath("Empresa.md"))
        // Reabrir en caliente tampoco escribe.
        svc.close()
        let svc2 = try Apoyo.servicio(root, state: state)
        _ = try await svc2.open { _ in }
        svc2.close()
        #expect(Apoyo.huellaDeArbol(root) == antes)
    }
}
