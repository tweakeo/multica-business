import Darwin
import Foundation
import Testing
@testable import TLSAgents

/// Perfil de sandbox: texto y comportamiento real con `sandbox-exec` (sin Claude: no gasta nada).
@Suite(.serialized) struct SandboxProfileTests {
    /// Escenario: carpeta de empresa en `/tmp`, estado del agente dentro de la carpeta personal (como en la app).
    struct Escenario {
        let vault: URL, secreto: URL, estado: URL, paths: AgentPaths, perfil: URL, socket: URL, fuera: URL

        init() throws {
            (vault, secreto) = Apoyo.vaultDePrueba()
            estado = Apoyo.estadoBase.appendingPathComponent("p-\(UUID().uuidString.prefix(6).lowercased())", isDirectory: true)
            paths = try AgentPaths(vaultState: estado, slug: "sonda", runID: "prueba")
            try paths.create()
            socket = estado.appendingPathComponent("s/v.sock")
            try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
            fuera = estado.appendingPathComponent("fuera/secreto.md")
            Apoyo.escribir("fuera del agente\n", en: fuera)
            perfil = try SandboxProfileBuilder(deniedRoots: [vault], agentDirectory: paths.agentDirectory,
                                               runDirectory: paths.runDirectory, socket: socket)
                .write(to: paths.profile)
        }

        func limpiar() { Apoyo.limpiar(vault, estado) }
    }

    @Test func textoDelPerfil() throws {
        let home = URL(fileURLWithPath: "/Users/prueba")
        let b = SandboxProfileBuilder(home: home, deniedRoots: [URL(fileURLWithPath: "/tmp/Empresa")],
                                      agentDirectory: URL(fileURLWithPath: "/tmp/estado/agentes/mika"),
                                      runDirectory: URL(fileURLWithPath: "/tmp/estado/ejecuciones/r1"),
                                      socket: URL(fileURLWithPath: "/tmp/estado/s/abcd1234.sock"),
                                      readOnly: [URL(fileURLWithPath: "/Applications/The Last System.app")])
        let t = try b.build()
        let lineas = t.split(separator: "\n").map(String.init).filter { !$0.hasPrefix(";;") }
        #expect(lineas == [
            "(version 1)",
            "(allow default)",
            #"(deny file-read* file-write* (subpath "/Users/prueba") (subpath "/private/tmp/Empresa") (subpath "/Volumes"))"#,
            "(allow file-read-metadata)",
            #"(allow file-read* (literal "/Users/prueba") (subpath "/Users/prueba/.local/share/claude") (subpath "/Users/prueba/.local/bin") (subpath "/Applications/The Last System.app"))"#,
            ##"(allow file-read* file-write* (subpath "/Users/prueba/.claude") (regex #"^/Users/prueba/\.claude\.json") (subpath "/Users/prueba/Library/Keychains") (subpath "/private/tmp/estado/agentes/mika") (subpath "/private/tmp/estado/ejecuciones/r1"))"##,
            // F4 · corrector (R7): lo de `~/.claude` que se ejecuta fuera de la caja no se escribe desde dentro.
            #"(deny file-write* (literal "/Users/prueba/.claude/settings.json") (literal "/Users/prueba/.claude/settings.local.json") (literal "/Users/prueba/.claude/CLAUDE.md") (literal "/Users/prueba/.claude/keybindings.json") (subpath "/Users/prueba/.claude/commands") (subpath "/Users/prueba/.claude/agents") (subpath "/Users/prueba/.claude/hooks") (subpath "/Users/prueba/.claude/skills") (subpath "/Users/prueba/.claude/plugins") (subpath "/Users/prueba/.claude/output-styles"))"#,
            "(deny network-outbound (remote unix-socket))",
            #"(allow network-outbound (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))"#,
            #"(allow network-outbound (remote unix-socket (path-literal "/private/tmp/estado/s/abcd1234.sock")))"#,
            #"(deny process-exec (literal "/usr/bin/osascript"))"#,
            "(deny appleevent-send)",
            #"(deny file-read* file-write* (subpath "/private/tmp/Empresa"))"#,
        ])
        #expect(!t.contains("bypass"))
    }

    @Test func rutasPeligrosasSeRechazan() {
        let b = SandboxProfileBuilder(deniedRoots: [URL(fileURLWithPath: "/tmp/a\")(allow default")],
                                      agentDirectory: URL(fileURLWithPath: "/tmp/x"), runDirectory: URL(fileURLWithPath: "/tmp/y"))
        #expect(throws: SandboxProfileError.self) { try b.build() }
        #expect(SandboxProfileBuilder.regexEscape("/Users/a.b+c") == #"/Users/a\.b\+c"#)
        #expect(throws: (any Error).self) { try AgentPaths(vaultState: URL(fileURLWithPath: "/tmp"), slug: "../x") }
    }

    @Test func claudeInstaladoConNpmSeAbreEntero() {
        let home = URL(fileURLWithPath: "/Users/prueba")
        #expect(SandboxProfileBuilder.claudeReadPaths(
            binary: URL(fileURLWithPath: "/Users/prueba/.npm-global/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe"),
            home: home).map(\.path) == ["/Users/prueba/.npm-global/lib/node_modules/@anthropic-ai/claude-code"])
    }

    /// `cat` del secreto de la carpeta de empresa → EPERM (y sin sandbox sí se lee: el fichero existe).
    @Test func secretoDeLaEmpresaDaEPERM() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let control = try await ProcessRunner.run(ProcessSpec(executable: "/bin/cat", arguments: [e.secreto.path], timeout: 10))
        #expect(control.stdoutText.contains("secreto de prueba"))
        for ruta in [e.secreto.path, e.vault.appendingPathComponent("nota.md").path] {
            let out = try await Apoyo.enSandbox(e.perfil, "/bin/cat", [ruta])
            #expect(out.status != 0)
            #expect(out.stderrText.contains("Operation not permitted"), "\(out.stderrText)")
            #expect(out.stdout.isEmpty)
        }
        let ls = try await Apoyo.enSandbox(e.perfil, "/bin/ls", [e.vault.path])
        #expect(ls.stderrText.contains("Operation not permitted") && ls.stdout.isEmpty)
    }

    /// La carpeta personal: `~/Documents` y cualquier fichero fuera de lo permitido → EPERM.
    /// (Se abre la carpeta como fichero: sin sandbox da «Is a directory», así nunca se lista nada).
    @Test func carpetaPersonalDaEPERM() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let docs = Apoyo.home.appendingPathComponent("Documents").path
        if FileManager.default.fileExists(atPath: docs) {
            let out = try await Apoyo.enSandbox(e.perfil, "/bin/cat", [docs])
            #expect(out.stderrText.contains("Operation not permitted"), "\(out.stderrText)")
        }
        let fuera = try await Apoyo.enSandbox(e.perfil, "/bin/cat", [e.fuera.path])
        #expect(fuera.stderrText.contains("Operation not permitted") && fuera.stdout.isEmpty)
        let escribir = try await Apoyo.enSandbox(e.perfil, "/usr/bin/touch", [e.estado.appendingPathComponent("intruso").path])
        #expect(escribir.status != 0)
        #expect(!FileManager.default.fileExists(atPath: e.estado.appendingPathComponent("intruso").path))
    }

    /// Lo permitido sigue funcionando: escribir en el directorio del agente y leer el de la ejecución.
    @Test func agenteYEjecucionSiSePueden() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let nuevo = e.paths.agentDirectory.appendingPathComponent("nota-del-agente")
        let t = try await Apoyo.enSandbox(e.perfil, "/usr/bin/touch", [nuevo.path])
        #expect(t.status == 0, "\(t.stderrText)")
        let c = try await Apoyo.enSandbox(e.perfil, "/bin/cat", [e.paths.profile.path])
        #expect(c.status == 0 && c.stdoutText.contains("(version 1)"))
    }

    /// Solo el socket de su carpeta (y el de DNS): uno ajeno → EPERM.
    @Test func socketAjenoDaEPERM() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let ajeno = "/private/tmp/tls-otro-\(UUID().uuidString.prefix(6)).sock"
        let a = Apoyo.escuchar(e.socket.path), b = Apoyo.escuchar(ajeno)
        defer { close(a); close(b); unlink(e.socket.path); unlink(ajeno) }

        let propio = try await Apoyo.enSandbox(e.perfil, "/usr/bin/perl", ["-e", Apoyo.perlConectar, e.socket.path])
        #expect(propio.stdoutText == "conectado\n", "\(propio.stdoutText) \(propio.stderrText)")
        let otro = try await Apoyo.enSandbox(e.perfil, "/usr/bin/perl", ["-e", Apoyo.perlConectar, ajeno])
        #expect(otro.stdoutText == "error \(EPERM)\n", "\(otro.stdoutText) \(otro.stderrText)")
        let sinSandbox = try await ProcessRunner.run(ProcessSpec(executable: "/usr/bin/perl", arguments: ["-e", Apoyo.perlConectar, ajeno], timeout: 10))
        #expect(sinSandbox.stdoutText == "conectado\n")
        let dns = try await Apoyo.enSandbox(e.perfil, "/usr/bin/perl", ["-e", Apoyo.perlConectar, SandboxProfileBuilder.dnsSocket])
        #expect(dns.stdoutText == "conectado\n", "sin DNS no hay red")
    }

    @Test func sinOsascript() async throws {
        let e = try Escenario()
        defer { e.limpiar() }
        let out = try await Apoyo.enSandbox(e.perfil, "/usr/bin/osascript", ["-e", "return 1"])
        #expect(out.status != 0)
        #expect(out.stderrText.contains("Operation not permitted"))
    }
}
