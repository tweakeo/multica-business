import Foundation
import Testing

/// Botones, chips, pestañas e insignias van en cápsula (§1.10). Con el estilo de esquina continuo, el borde
/// de una cápsula se pinta con dos rayitas en sus extremos (se veía en todas las capturas): se usan circulares.
@Suite("Formas · cápsulas circulares")
struct FormasTests {
    @Test("Ninguna vista usa Capsule() con su estilo por defecto")
    func capsulasCirculares() throws {
        let fuentes = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../Sources").standardizedFileURL
        var usos: [String] = []
        for modulo in ["TLSUI", "TLSDesign", "TLSEditor", "TLSVisores"] {
            let dir = fuentes.appendingPathComponent(modulo)
            let ficheros = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
            for f in ficheros where f.hasSuffix(".swift") {
                let texto = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                for (n, l) in texto.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                    where l.contains("Capsule()") || l.contains("Capsule(style: .continuous)") {
                    usos.append("\(modulo)/\(f):\(n + 1)")
                }
            }
        }
        #expect(usos.isEmpty, "Cápsulas con esquina continua: \(usos)")
    }
}
