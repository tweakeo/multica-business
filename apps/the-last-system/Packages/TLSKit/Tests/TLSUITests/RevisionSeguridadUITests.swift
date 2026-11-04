import Foundation
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

/// Revisión de seguridad de datos (F1): lo que hoy falla va en `withKnownIssue` (ver
/// `RevisionSeguridadTests`). Al corregirlo, se quita el envoltorio.
@Suite("Revisión de seguridad · registro")
@MainActor
struct RevisionSeguridadUITests {
    /// Hallazgo 10. «Ver sin tocar» sobre una copia hecha por la app (su `.tls/config.yaml` dice
    /// `clase: copia`) la registra `.copia` + `bloqueada`. En el siguiente arranque,
    /// `permitirEscrituraEnCopias()` la ve por primera vez y la pasa a `permitida`: la carpeta que la
    /// persona abrió para no tocarla se puede escribir.
    @Test("«Ver sin tocar» sigue en solo lectura tras volver a arrancar")
    func verSinTocarSigueBloqueada() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("revision-vst-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let origen = base.appendingPathComponent("Origen", isDirectory: true)
        try FileManager.default.createDirectory(at: origen, withIntermediateDirectories: true)
        try Data("# E\n".utf8).write(to: origen.appendingPathComponent("Empresa.md"))
        // Una copia hecha en otra instalación (o antes de perder `vaults.json`).
        let (report, _) = try await DemoCopier(appSupport: base.appendingPathComponent("otra-asup"))
            .copy(from: origen, into: base.appendingPathComponent("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let copia = URL(fileURLWithPath: report.destino, isDirectory: true)

        let asup = base.appendingPathComponent("asup", isDirectory: true)
        let registry = VaultRegistry(directory: asup)
        _ = try registry.permitirEscrituraEnCopias()            // primer arranque con F1
        let app = AppModel(registry: registry)
        let entry = try app.registerReadOnly(url: copia, privadas: [], config: try await CopyConfig.peek(copia))
        #expect(entry.clase == .copia && entry.escritura == .bloqueada)
        _ = try registry.permitirEscrituraEnCopias()            // siguiente arranque
        let despues = try #require(registry.load().first { $0.id == entry.id })
        let opciones = VaultWriter.Options(stateDirectory: base.appendingPathComponent("estado"), appSupport: asup)
        do {
            #expect(despues.escritura == .bloqueada)
            await #expect(throws: WriteError.soloLectura) {
                try await VaultWriter.open(entry: despues, root: copia, options: opciones)
            }
        }
    }
}
