import Darwin
import Foundation
@testable import TLSAgents

/// Utilidades comunes de las pruebas de asistentes.
enum Apoyo {
    /// Pruebas que lanzan Claude Code de verdad (sesión de la suscripción): solo con `TLS_SONDA_REAL=1`.
    static var real: Bool { ProcessInfo.processInfo.environment["TLS_SONDA_REAL"] == "1" }

    /// Raíz del repositorio (este fichero está en `Packages/TLSKit/Tests/TLSAgentsTests/`).
    static var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Estado de pruebas (hace de `<ASUP>/<vault-id>`): dentro de la carpeta personal, como en la app,
    /// para que las reglas de permiso del perfil se prueben de verdad. `build/` no se versiona.
    static var estadoBase: URL {
        if let e = ProcessInfo.processInfo.environment["TLS_SONDA_ESTADO"], !e.isEmpty {
            return URL(fileURLWithPath: e, isDirectory: true)
        }
        return repo.appendingPathComponent("build/sonda-agentes", isDirectory: true)
    }

    /// `tls-mcp` de F0 (servidor MCP sin herramientas).
    static var tlsMCP: URL? {
        var candidatos: [String] = []
        if let e = ProcessInfo.processInfo.environment["TLS_SONDA_MCP"], !e.isEmpty { candidatos.append(e) }
        for conf in ["Release", "Debug"] {
            candidatos.append(repo.appendingPathComponent(
                "build/DerivedData/Build/Products/\(conf)/The Last System.app/Contents/Helpers/tls-mcp").path)
        }
        return candidatos.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Bundle `.app` que contiene `tls-mcp` (para la regla de lectura del perfil).
    static func bundle(de mcp: URL) -> URL? {
        var u = mcp
        while u.path != "/" {
            if u.pathExtension == "app" { return u }
            u.deleteLastPathComponent()
        }
        return nil
    }

    static func grabacion(_ nombre: String) -> Data {
        let url = Bundle.module.url(forResource: "Grabaciones", withExtension: nil)!.appendingPathComponent(nombre)
        return try! Data(contentsOf: url)
    }

    /// Carpeta temporal nueva con su ruta real (`/private/tmp/...`).
    static func tempDir(_ nombre: String = "tls") -> URL {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("\(nombre)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func escribir(_ texto: String, en url: URL) {
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(texto.utf8).write(to: url)
    }

    static func limpiar(_ urls: URL...) {
        for u in urls { try? FileManager.default.removeItem(at: u) }
    }

    /// Carpeta de empresa de prueba en `/tmp` con un secreto en la carpeta privada de Finanzas.
    static func vaultDePrueba() -> (raiz: URL, secreto: URL) {
        let raiz = tempDir("tls-sonda-vault")
        let secreto = raiz.appendingPathComponent("4 · Finanzas/privado/secreto.md")
        escribir("secreto de prueba (sintético)\n", en: secreto)
        escribir("# Nota\n", en: raiz.appendingPathComponent("nota.md"))
        return (raiz, secreto)
    }

    /// Ejecuta `programa` dentro del perfil y devuelve la salida.
    static func enSandbox(_ perfil: URL, _ programa: String, _ args: [String], stdin: Data? = nil) async throws -> ProcessOutput {
        try await ProcessRunner.run(ProcessSpec(
            executable: SandboxProfileBuilder.sandboxExec, arguments: ["-f", perfil.path, programa] + args,
            environment: AgentEnvironment.minimal(home: home), directory: "/", stdin: stdin, timeout: 20))
    }

    /// Conexión a un socket local con perl (programa del sistema): «conectado» o «error <errno>».
    static let perlConectar = """
    use Socket; socket(my $s, AF_UNIX, SOCK_STREAM, 0) or die; \
    if (connect($s, pack_sockaddr_un($ARGV[0]))) { print "conectado\\n" } else { printf "error %d\\n", $!+0 }
    """

    /// Socket local escuchando (sin aceptar: basta con la cola). Devuelve el descriptor.
    static func escuchar(_ path: String) -> Int32 {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        precondition(bytes.count < MemoryLayout.size(ofValue: addr.sun_path), "ruta de socket demasiado larga")
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in bytes.enumerated() { raw[i] = b }
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        precondition(ok == 0, "bind: \(String(cString: strerror(errno)))")
        precondition(listen(fd, 16) == 0)
        return fd
    }
}
