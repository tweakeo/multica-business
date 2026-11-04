import Foundation
import GRDB
import Testing
@testable import TLSCore

/// Hallazgo 9 de fidelidad (F1-CONTRATOS «Pendiente para la interfaz»): los 47 `tls_type` de las
/// plantillas tienen su `NoteKind`, y un índice de antes se rehace solo.
@Suite("Tipos de ficha", .serialized)
struct TiposDeFichaTests {
    /// `tls_type` de las plantillas de serie, leídos de los ficheros (sin `fragment`, que no es una nota).
    static var tiposEnPlantillas: Set<String> {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/TLSCore/Recursos/Plantillas").standardizedFileURL
        var out = Set<String>()
        let ficheros = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
        for f in ficheros where f.hasSuffix(".md") {
            guard let texto = try? String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8) else { continue }
            for linea in texto.split(separator: "\n") where linea.hasPrefix("tls_type:") {
                let valor = linea.dropFirst("tls_type:".count).trimmingCharacters(in: .whitespaces)
                if !valor.isEmpty { out.insert(valor) }
            }
        }
        out.remove("fragment")
        return out
    }

    @Test("Un NoteKind por cada tls_type de las plantillas (47)")
    func todosLosTipos() {
        let enPlantillas = Self.tiposEnPlantillas
        #expect(enPlantillas.count == 47)
        #expect(Set(NoteKind.tiposDePlantilla.map(\.rawValue)) == enPlantillas)
        #expect(NoteKind.tiposDePlantilla.count == 47)
        #expect(NoteKind.allCases.count == 50)
    }

    @Test("Cada tls_type se lee como su tipo (antes, 26 eran «Nota»)")
    func resolverPorPropiedad() {
        let layout = VaultLayout.humana
        for raw in Self.tiposEnPlantillas {
            let fm = FrontmatterReader.read("tls_type: \(raw)")
            let kind = NoteKindResolver.kind(of: VaultPath("2 · Ventas/x.md"), frontmatter: fm, layout: layout)
            #expect(kind.rawValue == raw, "\(raw) → \(kind)")
        }
        // Las plantillas siguen sin ser fichas.
        let fm = FrontmatterReader.read("tls_type: invoice")
        #expect(NoteKindResolver.kind(of: VaultPath("4 · Finanzas/Sistemas/Plantillas/Factura.md"), frontmatter: fm, layout: layout) == .note)
        // Un plan de entrega en su carpeta, sin propiedad, ya no es «Archivo».
        #expect(NoteKindResolver.kind(of: VaultPath("3 · Entrega/Plantillas/trimestrales.md"), frontmatter: nil, layout: layout) == .deliveryTemplate)
        #expect(NoteKind(rawValue: "editorial_plan") == .editorialPlan)
        #expect(NoteKind.rootCause.rawValue == "root_cause")
    }

    @Test("Un índice de la versión 1 se rehace con los tipos nuevos")
    func indiceDeAntesSeRehace() async throws {
        // 2 en F1 (los 47 tipos); 3 desde F2 (texto de los PDF en la búsqueda). Un índice anterior se rehace igual.
        #expect(VaultIndex.schemaVersion >= 2)
        let root = Apoyo.copiaDeFixture()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let factura = root.appendingPathComponent("4 · Finanzas/Factura de prueba.md")
        try Data("---\ntls_type: invoice\nestado: Borrador\n---\n# Factura de prueba\n".utf8).write(to: factura)

        let a = try Apoyo.servicio(root, state: state)
        _ = try await a.open { _ in }
        a.close()
        await a.waitUntilIdle()
        // Se simula un índice de F0: versión 1 y la factura guardada como nota.
        var config = Configuration()
        config.busyMode = .timeout(10)
        let pool = try DatabasePool(path: state.appendingPathComponent(VaultIndex.fileName).path, configuration: config)
        try await pool.write { db in
            try db.execute(sql: "UPDATE notes SET kind = 'note' WHERE path = '4 · Finanzas/Factura de prueba.md'")
            try db.execute(sql: "PRAGMA user_version = 1")
        }
        try pool.close()

        let b = try Apoyo.servicio(root, state: state)
        _ = try await b.open { _ in }
        #expect(b.summary(of: VaultPath("4 · Finanzas/Factura de prueba.md"))?.kind == .invoice)
        b.close()
    }
}
