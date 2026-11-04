import Foundation
import GRDB
import Testing
@testable import TLSCore

@Suite(.serialized) struct IndiceTests {
    /// Cambios fuera de la app entre dos aperturas: el índice incremental debe ser igual
    /// que uno reconstruido desde cero.
    @Test func reconstruidoIgualQueIncremental() async throws {
        let root = Apoyo.copiaDeFixture()
        let s1 = Apoyo.tempDir("estado"), s2 = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), s1, s2) }

        let a = try Apoyo.servicio(root, state: s1)
        _ = try await a.open { _ in }
        a.close()

        // Edición, nota nueva, borrado y carpeta nueva.
        let rumbo = root.appendingPathComponent("1 · Dirección/Rumbo.md")
        try "# Rumbo\n\nAhora enlaza al [[Embudo]] y menciona kiwis.\n".write(to: rumbo, atomically: true, encoding: .utf8)
        try "---\ntipo: persona\nnombre: Marta Nueva\n---\nTrabaja en [[Ferretería Ejemplo]].\n"
            .write(to: root.appendingPathComponent("2 · Ventas/Contactos/Marta Nueva.md"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: root.appendingPathComponent("1 · Dirección/Decisiones.md"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("5 · Marca/Contenidos"), withIntermediateDirectories: true)
        try "# Pieza\n\nTexto de [[Identidad]].\n".write(to: root.appendingPathComponent("5 · Marca/Contenidos/pieza.md"),
                                                      atomically: true, encoding: .utf8)

        let b = try Apoyo.servicio(root, state: s1)
        _ = try await b.open { _ in }
        let incremental = try b.indexDump()
        #expect(b.search("kiwis").count == 1)
        #expect(b.summary(of: VaultPath("1 · Dirección/Decisiones.md")) == nil)
        #expect(b.summary(of: VaultPath("5 · Marca/Contenidos/pieza.md"))?.kind == .content)
        b.close()

        let c = try Apoyo.servicio(root, state: s2)
        _ = try await c.open { _ in }
        let frio = try c.indexDump()
        c.close()

        #expect(incremental.count > 40)
        #expect(incremental == frio)
    }

    /// En caliente solo se vuelve a leer lo que cambió (tamaño o fecha), y decide el hash.
    @Test func incrementalPorHash() throws {
        let root = Apoyo.copiaDeFixture()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let layout = VaultLayout.load(root: root).layout
        let index = try VaultIndex(directory: state)
        let builder = IndexBuilder(root: root, layout: layout, index: index, excluded: [], indexArchivoContent: false)
        let cold = try builder.fullScan(progress: nil)
        #expect(cold.changed.count == cold.stats.notes)
        #expect(try builder.fullScan(progress: nil).changed.isEmpty)

        // Misma contenido, fecha nueva: no cuenta como cambio.
        let embudo = root.appendingPathComponent("2 · Ventas/Sistemas/Embudo.md")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: embudo.path)
        #expect(try builder.fullScan(progress: nil).changed.isEmpty)

        // Contenido distinto: cuenta.
        try "# Embudo\n\nOtro texto.\n".write(to: embudo, atomically: true, encoding: .utf8)
        #expect(try builder.fullScan(progress: nil).changed == [VaultPath("2 · Ventas/Sistemas/Embudo.md")])
        index.close()
    }

    /// Si cambia la configuración (privado en layout.json), se releen también las notas sin cambios.
    @Test func cambioDeConfiguracionReindexa() async throws {
        let root = Apoyo.copiaDeFixture()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let lucia = VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")
        let a = try VaultService(entry: Apoyo.entrada(root), root: root, options: .init(stateDirectory: state, vigilar: false))
        _ = try await a.open { _ in }
        #expect(a.summary(of: lucia)?.privado == false)
        a.close()
        try #"{"preset":"humana","privado":["{ventas}/Contactos"]}"#
            .write(to: root.appendingPathComponent(".tls/layout.json"), atomically: true, encoding: .utf8)
        let b = try VaultService(entry: Apoyo.entrada(root), root: root, options: .init(stateDirectory: state, vigilar: false))
        _ = try await b.open { _ in }
        #expect(b.layout.privado == [VaultPath("2 · Ventas/Contactos")])
        #expect(b.summary(of: lucia)?.privado == true)
        #expect(b.summary(of: VaultPath("2 · Ventas/Sistemas/Embudo.md"))?.privado == false)
        #expect(b.children(of: VaultPath("2 · Ventas")).first { $0.path.name == "Contactos" }?.privado == true)
        b.close()
    }

    @Test func esquemaDistintoSeReconstruye() throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        do {
            let index = try VaultIndex(directory: state)
            try index.db.write { db in
                try db.execute(sql: "INSERT INTO notes(path, name, title, kind) VALUES ('x.md', 'x', 'x', 'note')")
                try db.execute(sql: "PRAGMA user_version = 99")
            }
            index.close()
        }
        let again = try VaultIndex(directory: state)
        #expect(try again.db.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == VaultIndex.schemaVersion)
        #expect(again.counts().notes == 0)
        again.close()
    }

    /// Índice antiguo con la misma versión pero sin la tabla `meta` («no such table: meta»).
    @Test func tablaQueFaltaSeReconstruye() async throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        do {
            let index = try VaultIndex(directory: state)
            try await index.db.write { db in try db.execute(sql: "DROP TABLE meta") }
            index.close()
        }
        let service = try Apoyo.servicio(Apoyo.empresaMinima, state: state)
        let stats = try await service.open { _ in }
        #expect(stats.notes > 0)
        service.close()
    }

    @Test func ficheroDanadoSeReconstruye() throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        try Data("esto no es SQLite".utf8).write(to: state.appendingPathComponent(VaultIndex.fileName))
        let index = try VaultIndex(directory: state)
        #expect(index.counts().notes == 0)
        index.close()
    }

    /// Criterio F0: ~1.000 notas en frío en menos de 20 s; en caliente, menos de 1,5 s.
    @Test func rendimientoMilNotas() async throws {
        let root = Apoyo.tempDir("mil")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        try Data(#"{"preset":"humana"}"#.utf8).write(to: { () -> URL in
            let d = root.appendingPathComponent(".tls"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d.appendingPathComponent("layout.json")
        }())
        let parrafo = String(repeating: "Texto de relleno con tildes: acción, gestión, información y decisión. ", count: 12)
        for i in 0..<1000 {
            let area = AreaCode.allCases[i % 6]
            let dir = root.appendingPathComponent("\(area.numero) · \(area.nombre)/Notas \(i % 10)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let text = """
            ---
            tipo: persona
            nombre: Persona \(i)
            alta: 2026-10-\(String(format: "%02d", i % 28 + 1))
            etiquetas: [prueba, lote\(i % 7)]
            ---

            # Nota número \(i)

            \(parrafo)
            Enlaza a [[Nota número \((i + 1) % 1000)]] y a [la anterior](Nota%20\(max(i - 1, 0)).md).
            """
            try text.write(to: dir.appendingPathComponent("Nota \(i).md"), atomically: false, encoding: .utf8)
        }
        let svc = try Apoyo.servicio(root, state: state)
        let t0 = Date()
        let stats = try await svc.open { _ in }
        let frio = Date().timeIntervalSince(t0)
        svc.close()
        #expect(stats.notes == 1000)
        #expect(frio < 20)

        let svc2 = try Apoyo.servicio(root, state: state)
        let t1 = Date()
        _ = try await svc2.open { _ in }
        let caliente = Date().timeIntervalSince(t1)
        #expect(caliente < 1.5)
        #expect(svc2.quickOpen("nota número 99", limit: 3).first?.title == "Nota número 99")
        svc2.close()
        print("Rendimiento 1.000 notas: frío \(String(format: "%.2f", frio)) s · caliente \(String(format: "%.3f", caliente)) s")
    }
}
