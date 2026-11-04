import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// Revisión de seguridad de datos (F1): lo que hoy falla va en `withKnownIssue` (ver
/// `RevisionSeguridadTests`). Al corregirlo, se quita el envoltorio.
@Suite struct RevisionSeguridadCopiaTests {
    /// Hallazgo 11. La copia de una carpeta con `Archivo/` (como The Last) se registra con
    /// `exclusionesCopia: ["Archivo"]` (no se copia por defecto). El escritor trata lo excluido como
    /// prohibido, así que en esa copia no se puede retirar nada (ni apartar duplicados ni guardar la
    /// otra versión de un conflicto en `Archivo/Conflictos`): la única alternativa a borrar no funciona.
    @Test func retirarFuncionaEnUnaCopiaSinArchivo() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let (report, entry) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        #expect(entry.exclusionesCopia.contains("Archivo"))
        let root = URL(fileURLWithPath: report.destino, isDirectory: true)
        let writer = try await VaultWriter.open(entry: entry, root: root,
                                                options: .init(stateDirectory: t.dir("Estado"), appSupport: t.dir("Soporte")))
        let bus = CommandBus(writer: writer)
        do {
            let r = try await bus.ejecutar(.retirar(VaultPath("1 · Dirección/Área.md")), autor: .persona("Manu"))
            #expect(r.hecho)
        }
        await writer.close()
    }
}
