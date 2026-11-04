import Darwin
import Foundation
import Testing
@testable import TLSAgents

/// Revisión adversarial de F4 (rol revisión-seguridad): la caja de los asistentes con `sandbox-exec` de verdad y una
/// carpeta personal **de mentira** en un temporal (nunca la del usuario). Sin Claude: `/bin/sh` hace de proceso de dentro.
@Suite("Revisión F4 · caja de los asistentes", .serialized)
struct RevisionF4SandboxTests {
    /// R7: la caja deja escribir toda `~/.claude` (la necesita Claude Code para sus sesiones), también lo que Claude Code
    /// lee **fuera** de la caja en las sesiones normales de la persona: `settings.json` (ganchos que ejecutan órdenes),
    /// `commands/`, `agents/`, `CLAUDE.md`. Un proceso de dentro que pudiera escribir (un fallo del CLI, un complemento)
    /// dejaría algo que se ejecuta sin caja la próxima vez que la persona use Claude Code.
    @Test("R7 · Desde la caja se puede escribir ~/.claude/settings.json y ~/.claude/commands")
    func escribirAjustesDeClaudeDesdeLaCaja() async throws {
        let base = Apoyo.tempDir("rev-caja")
        defer { Apoyo.limpiar(base) }
        let home = base.appendingPathComponent("casa", isDirectory: true)
        let vault = base.appendingPathComponent("Empresa", isDirectory: true)
        let estado = home.appendingPathComponent("Library/Application Support/The Last System/v", isDirectory: true)
        let fm = FileManager.default
        for d in [home.appendingPathComponent(".claude/commands"), vault, estado] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        let paths = try AgentPaths(vaultState: estado, slug: "comercial", runID: "r-caja")
        try paths.create()
        let perfil = try SandboxProfileBuilder(home: home, deniedRoots: [vault], agentDirectory: paths.agentDirectory,
                                               runDirectory: paths.runDirectory).write(to: paths.profile)
        let ajustes = home.appendingPathComponent(".claude/settings.json")
        let orden = home.appendingPathComponent(".claude/commands/abrir.md")
        let guion = "printf '{\"hooks\":{}}' > '\(ajustes.path)'; printf 'x' > '\(orden.path)'"
        let r = try await ProcessRunner.run(ProcessSpec(executable: SandboxProfileBuilder.sandboxExec,
                                                        arguments: ["-f", perfil.path, "/bin/sh", "-c", guion], timeout: 20))
        // Control: lo de la carpeta personal fuera de `.claude` sí está cerrado.
        let fuera = try await ProcessRunner.run(ProcessSpec(
            executable: SandboxProfileBuilder.sandboxExec,
            arguments: ["-f", perfil.path, "/bin/sh", "-c", "printf x > '\(home.appendingPathComponent("Documents.txt").path)'"],
            timeout: 20))
        #expect(fuera.status != 0)
        // Corregido (corrector final F4): R7: la caja abre toda ~/.claude para escribir; bastaría con sus sesiones y su estado
        do {
            #expect(r.status != 0, "salida \(r.status)")
            #expect(!fm.fileExists(atPath: ajustes.path), "se escribió settings.json desde la caja")
            #expect(!fm.fileExists(atPath: orden.path), "se escribió una orden de Claude Code desde la caja")
        }
    }
}
