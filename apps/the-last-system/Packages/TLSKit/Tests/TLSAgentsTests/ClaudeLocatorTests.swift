import Foundation
import Testing
@testable import TLSAgents

@Suite struct ClaudeLocatorTests {
    @Test func pathEntreMarcas() {
        let salida = "Bienvenido a zsh\nalias raro\n\n__TLS_PATH__/a/bin:/b/bin::relativo:/c__TLS_PATH__\nadiós\n"
        #expect(ClaudeLocator.parsePATH(salida) == ["/a/bin", "/b/bin", "/c"])
        #expect(ClaudeLocator.parsePATH("sin marcas") == nil)
        #expect(ClaudeLocator.parsePATH("__TLS_PATH____TLS_PATH__") == nil)
    }

    @Test func candidatosEnOrdenYSinRepetir() {
        let home = URL(fileURLWithPath: "/Users/prueba")
        let loc = ClaudeLocator(home: home, shell: "/bin/zsh")
        let c = loc.candidates(path: ["/Users/prueba/.local/bin", "/usr/bin", "/opt/homebrew/bin/"]).map(\.path)
        #expect(c == ["/Users/prueba/.local/bin/claude", "/usr/bin/claude", "/opt/homebrew/bin/claude",
                      "/usr/local/bin/claude"])
    }

    /// Se ejecuta el binario real (enlaces resueltos), nunca lo que diga un alias de la shell.
    @Test func binarioRealTrasElEnlace() throws {
        let raiz = Apoyo.tempDir("loc")
        defer { Apoyo.limpiar(raiz) }
        let fm = FileManager.default
        // a/claude existe pero no es ejecutable; b/claude es un enlace a versions/9.9.9.
        Apoyo.escribir("no", en: raiz.appendingPathComponent("a/claude"))
        let real = raiz.appendingPathComponent("share/claude/versions/9.9.9")
        Apoyo.escribir("#!/bin/sh\necho '9.9.9 (Claude Code)'\n", en: real)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real.path)
        try fm.createDirectory(at: raiz.appendingPathComponent("b"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: raiz.appendingPathComponent("b/claude"), withDestinationURL: real)
        try fm.createDirectory(at: raiz.appendingPathComponent("c/claude"), withIntermediateDirectories: true)

        let cands = ["c", "a", "b"].map { raiz.appendingPathComponent($0).appendingPathComponent("claude") }
        let hit = try #require(ClaudeLocator.firstExecutable(in: cands))
        #expect(hit.found.lastPathComponent == "claude" && hit.found.deletingLastPathComponent().lastPathComponent == "b")
        #expect(hit.binary.path == real.path)
        #expect(!ClaudeLocator.isMachO(hit.binary))
        #expect(ClaudeLocator.isMachO(URL(fileURLWithPath: "/bin/ls")))
    }

    @Test func versiones() {
        let v = ClaudeVersion("2.1.307 (Claude Code)\n")
        #expect(v?.description == "2.1.307")
        #expect(ClaudeVersion("2.1.306")! < ClaudeVersion("2.1.307")!)
        #expect(ClaudeVersion("2.2")! > ClaudeVersion("2.1.999")!)
        #expect(ClaudeVersion("Claude Code") == nil)
        #expect(ClaudeLocator.versionWarning(ClaudeLocator.verifiedVersion) == nil)
        #expect(ClaudeLocator.versionWarning(ClaudeVersion("2.1.306"))?.contains("no es la versión comprobada") == true)
        #expect(ClaudeLocator.versionWarning(nil) != nil)
    }

    /// De `auth status` solo se guarda si hay sesión y de qué tipo (ni correo ni organización).
    @Test func estadoDeSesion() throws {
        let json = #"{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","email":"x@y.z","orgId":"o","orgName":"Org","subscriptionType":"max"}"#
        let s = try ClaudeAuthStatus.parse(Data(json.utf8))
        #expect(s == ClaudeAuthStatus(loggedIn: true, authMethod: "claude.ai", apiProvider: "firstParty", subscriptionType: "max"))
        #expect(try ClaudeAuthStatus.parse(Data("aviso\n{\"loggedIn\": false}\n".utf8)).loggedIn == false)
        #expect(throws: ClaudeLocatorError.self) { try ClaudeAuthStatus.parse(Data("Not logged in".utf8)) }
    }

    @Test func entornoMinimoSinClaves() {
        let env = AgentEnvironment.minimal(home: URL(fileURLWithPath: "/Users/prueba"), tmp: URL(fileURLWithPath: "/r/tmp"),
                                           user: "prueba", lang: "es_ES.UTF-8")
        #expect(Set(env.keys) == ["PATH", "HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "DISABLE_AUTOUPDATER",
                                  "CLAUDE_CODE_DISABLE_CLAUDE_MDS", "CLAUDE_CODE_DISABLE_AUTO_MEMORY",
                                  "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"])
        #expect(env["TMPDIR"] == "/r/tmp")
        #expect(env["ANTHROPIC_API_KEY"] == nil)
    }

    /// El PATH de la shell de login se lee con `-ilc` y marcas (aquí con `/bin/sh` y una carpeta personal vacía).
    @Test func pathDeLaShellDeLogin() async {
        let home = Apoyo.tempDir("home")
        defer { Apoyo.limpiar(home) }
        let path = await ClaudeLocator(home: home, shell: "/bin/sh").loginShellPATH()
        #expect(path.contains("/usr/bin"))
    }
}
