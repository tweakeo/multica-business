import Foundation
import Testing
@testable import TLSCore

/// Criterio F1 3: tras 200 operaciones aleatorias, el índice reconstruido desde cero es igual
/// que el incremental (el que se actualiza con las rutas que avisa el escritor tras cada plan).
@Suite(.serialized) struct EscrituraIndiceTests {
    static let manu = Autor.persona("Manu")

    @Test func doscientasOperacionesAleatorias() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let estadoIndice = Apoyo.tempDir("indice"), estadoFrio = Apoyo.tempDir("indice-frio")
        defer { Apoyo.limpiar(estadoIndice, estadoFrio) }
        let layout = VaultLayout.load(root: e.root).layout
        let index = try VaultIndex(directory: estadoIndice)
        let builder = IndexBuilder(root: e.root, layout: layout, index: index, excluded: [], indexArchivoContent: false)
        _ = try UbiquityInspector.withoutMaterializing { try builder.fullScan(progress: nil) }

        let bus = try await e.bus()
        // Una tabla para cambiar celdas.
        _ = try await bus.ejecutar(.crear(VaultPath("1 · Dirección/Metas.md"),
                                          texto: "# Metas\n\n| Código | Meta | Alerta |\n|---|---|---|\n| DIR-01 | 1 | 2 |\n"), autor: .sistema)
        var g = Semilla(200)
        var hechas = 0, rechazadas = 0, conflictos = 0, deshechas = 0
        var creadasPorLaApp: [VaultPath] = []
        func notas() -> [VaultPath] {
            ficherosDeTexto(e.root, extensiones: ["md"]).compactMap { VaultPath(url: $0, root: e.root) }
                .filter { !$0.components.contains { $0.hasPrefix(".") } && !layout.isArchived($0) }
        }
        func carpetas() -> [VaultPath] {
            Array(Set(notas().compactMap(\.parent))).sorted()
        }
        let palabras = ["kiwi", "naranja", "Ribera", "propuesta", "cobro", "tarea", "sesión", "Núñez", "web"]
        for i in 0..<200 {
            let todas = notas()
            let nota = todas.aleatorio(&g)
            let palabra = palabras.aleatorio(&g)
            var comando: CommandBus.Comando?
            var plan: WritePlan?
            var autor: Autor = Bool.random(using: &g) ? Self.manu : .sistema
            switch Int.random(in: 0..<14, using: &g) {
            case 0, 1:
                let dir = carpetas().aleatorio(&g)
                comando = .crear(dir.appending("nota-\(i).md"),
                                 texto: "---\ntls_type: note\nid: n-\(i)\n---\n# Nota \(i) \(palabra)\n\nEnlaza a [[\(todas.aleatorio(&g).stem)]].\n")
            case 2, 3:
                comando = .cambiarPropiedades(nota, poner: [Property(key: "estado", value: .text(palabra)),
                                                            Property(key: "titulo", value: .text("Título \(i) \(palabra)"))], quitar: [])
            case 4:
                comando = .anadirASeccion(nota, seccion: "Actividad", texto: "### 2026-10-22 · Manu\n\(palabra) \(i)")
            case 5:
                comando = .anadirLinea(VaultPath("1 · Dirección/Decisiones.md"), linea: "- 2026-10-22 · \(palabra) \(i) · Dirección")
            case 6:
                comando = .guardarFila(VaultPath("4 · Finanzas/Registros/emitidas.csv"),
                                       fila: ["id": "F-2026-\(100 + i % 7)", "concepto": "\(palabra) \(i)", "importe": "\(i).00"], clave: "id")
            case 7:
                let destino = carpetas().aleatorio(&g)
                comando = .mover(nota, a: destino.appending("movida-\(i).md"))
            case 8:
                comando = .retirar(nota)
            case 9:
                if let texto = e.texto(nota.raw) {
                    autor = Self.manu
                    comando = .guardarNota(nota, base: texto, texto: texto + "\n\(palabra) desde el editor \(i).\n")
                }
            case 10:
                if let p = creadasPorLaApp.last(where: { e.existe($0.raw) }) {
                    autor = .sistema
                    comando = .sustituirCuerpo(p, cuerpo: "\n# Reescrita \(i)\n\n[\(palabra)](../Rumbo.md)\n", baseHash: nil)
                }
            case 11:
                comando = .cambiarCeldas(VaultPath("1 · Dirección/Metas.md"), tabla: TableSelector(columna: "Código"),
                                         columnaClave: "Código", valorClave: "DIR-01", celdas: ["Meta": "\(i)"])
            case 12:
                // Renombrar una carpeta entera con sus notas.
                let dir = carpetas().filter { $0.components.count >= 2 }.aleatorio(&g)
                plan = WritePlan(autor: Self.manu, descripcion: "Renombrar carpeta",
                                 ops: [.move(dir, to: (dir.parent ?? .root).appending("\(dir.name) \(i)"))])
            default:
                if Int.random(in: 0..<3, using: &g) == 0 {
                    do {
                        let r = try await bus.deshacer(autor: Self.manu)
                        try reindexar(r.cambiadas, builder)
                        deshechas += 1
                    } catch { rechazadas += 1 }
                    continue
                }
                comando = .crear(VaultPath("Buzón/captura-\(i).md"), texto: "Captura \(palabra)\n")
            }
            guard comando != nil || plan != nil else { continue }
            do {
                let r: WriteResult
                if let plan { r = try await bus.ejecutar(plan) } else { r = try await bus.ejecutar(comando!, autor: autor) }
                if r.conflicto != nil { conflictos += 1 }
                if r.hecho { hechas += 1 }
                creadasPorLaApp += r.creadas
                try reindexar(r.cambiadas, builder)
            } catch is WriteError {
                rechazadas += 1
            }
        }
        print("200 operaciones: \(hechas) hechas, \(deshechas) deshechas, \(rechazadas) rechazadas (por diseño), \(conflictos) conflictos")
        #expect(hechas > 120)
        #expect(conflictos == 0)

        let incremental = try index.dump()
        index.close()
        let frio = try VaultIndex(directory: estadoFrio)
        let frioBuilder = IndexBuilder(root: e.root, layout: layout, index: frio, excluded: [], indexArchivoContent: false)
        _ = try UbiquityInspector.withoutMaterializing { try frioBuilder.fullScan(progress: nil) }
        let reconstruido = try frio.dump()
        frio.close()
        #expect(incremental.count > 60)
        #expect(incremental == reconstruido)
        // Nada a medias ni restos del escritor en la carpeta.
        for url in ficherosDeTexto(e.root, extensiones: ["md"]) {
            let doc = try #require(FrontmatterDocument(data: try Data(contentsOf: url)))
            if doc.hasFrontmatter, url.lastPathComponent.hasPrefix("nota-") { #expect(doc.frontmatter.isValid) }
        }
        let todo = e.huella().keys
        #expect(!todo.contains { $0.contains(".tls-renombrar") })
        #expect(Set(todo.filter { $0.hasPrefix(".tls/") }) == [".tls/layout.json", ".tls/escritor.json"])
    }

    /// Lo que hace la vigilancia con un aviso: reindexar esas rutas.
    func reindexar(_ paths: [VaultPath], _ builder: IndexBuilder) throws {
        guard !paths.isEmpty else { return }
        _ = try UbiquityInspector.withoutMaterializing { try builder.update(paths) }
    }
}
