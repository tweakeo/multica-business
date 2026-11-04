import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// Corrector final de F3: «Poner fecha…» en Calidad (antes pedía editar «Fechas de documentos.csv» a mano). Todo en
/// temporales propios.
@Suite("Revisión final F3 · calidad", .serialized)
struct RevisionFinalF3CalidadTests {
    @Test("«Poner fecha…»: el documento sin fecha queda con su fila «manual» y deja de salir en Calidad; se deshace")
    func ponerFecha() async throws {
        let t = try TempTree()
        defer { t.remove() }
        try t.write(".tls/layout.json", "{\"preset\": \"humana\"}", in: "Empresa")
        try t.write("Empresa.md", "# Empresa\n", in: "Empresa")
        try t.write("4 · Finanzas/Fiscal/2026/T1/Gastos/recibo sin fecha.pdf", "%PDF-1.4 recibo", in: "Empresa")
        let raiz = t.dir("Empresa")
        let foto = VaultSnapshot.read(root: raiz)
        let aviso = try #require(InformeCalidad.revisar(snapshot: foto).avisos.first { $0.tipo == .sinFecha })
        #expect(aviso.queHacer.contains("Poner fecha"))
        #expect(!aviso.queHacer.contains(".csv"), "No se pide editar un CSV a mano")
        let plan = try InformeCalidad.ponerFecha(aviso, fecha: LocalDate(year: 2026, month: 2, day: 3)!, snapshot: foto)
        let writer = try await VaultWriter.open(
            entry: VaultEntry(nombre: "Empresa", ruta: raiz.path, bookmark: nil, clase: .copia, escritura: .permitida),
            root: raiz, options: .init(stateDirectory: t.dir("estado"), appSupport: t.dir("asup"), app: "pruebas"))
        let bus = CommandBus(writer: writer)
        let r = try await bus.ejecutar(plan)
        #expect(r.hecho)
        let csv = try String(contentsOf: VaultPath("4 · Finanzas/Fechas de documentos.csv").url(in: raiz), encoding: .utf8)
        let filas = FechasDeDocumentos.leer(csv)
        #expect(filas.contains { $0.ruta == "Fiscal/2026/T1/Gastos/recibo sin fecha.pdf" && $0.fecha == "2026-02-03" && $0.esManual }, "\(csv)")
        #expect(!InformeCalidad.revisar(snapshot: VaultSnapshot.read(root: raiz)).avisos.contains { $0.tipo == .sinFecha })
        // Con el CSV ya creado, otra fecha cambia la fila (no la duplica).
        let otra = try InformeCalidad.ponerFecha(aviso, fecha: LocalDate(year: 2026, month: 2, day: 4)!, snapshot: VaultSnapshot.read(root: raiz))
        #expect(try await bus.ejecutar(otra).hecho)
        let filas2 = FechasDeDocumentos.leer(try String(contentsOf: VaultPath("4 · Finanzas/Fechas de documentos.csv").url(in: raiz), encoding: .utf8))
        #expect(filas2.filter { $0.ruta == "Fiscal/2026/T1/Gastos/recibo sin fecha.pdf" }.map(\.fecha) == ["2026-02-04"])
        await writer.close()
    }
}
