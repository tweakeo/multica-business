import Darwin
import Foundation
import MCP
import Testing
@testable import TLSCore
@testable import TLSMCPHost
@testable import TLSMCPShared

/// Apoyo de las pruebas de `tls-mcp`: una copia de Asesoría Ribera (ficticia, `hoy: 2026-10-19`) en un temporal de
/// ruta corta (el socket no pasa de 103 bytes), con una carpeta privada de nombre neutro y ficheros de secretos de
/// mentira. Nunca se toca el ejemplo del repositorio ni se lanza Claude.
enum ApoyoMCP {
    static var riberaRepo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    static let privada = "4 · Finanzas/Expediente privado"
    static let notaPrivada = "4 · Finanzas/Expediente privado/nota.md"
    /// Palabra que solo está en la nota privada (para la búsqueda).
    static let palabraPrivada = "zarzaparrillaprivada"

    /// `tls-mcp-dev` compilado junto a las pruebas (o `TLS_MCP_HELPER`).
    static var helper: URL? {
        if let e = ProcessInfo.processInfo.environment["TLS_MCP_HELPER"], FileManager.default.isExecutableFile(atPath: e) {
            return URL(fileURLWithPath: e)
        }
        let candidatos = [Bundle(for: Empresa.self).bundleURL] + Bundle.allBundles.map(\.bundleURL) + [Bundle.main.bundleURL]
        for b in candidatos where b.pathExtension == "xctest" || b.lastPathComponent.hasSuffix(".xctest") {
            let url = b.deletingLastPathComponent().appendingPathComponent("tls-mcp-dev")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        // `swift test` con Swift Testing: el ejecutable vive junto al bundle de pruebas.
        let args = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        for dir in [args.deletingLastPathComponent(), args.deletingLastPathComponent().deletingLastPathComponent()] {
            let url = dir.appendingPathComponent("tls-mcp-dev")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Una empresa de prueba abierta, con índice, escritor y servidor de herramientas.
    final class Empresa: @unchecked Sendable {
        let base: URL
        let root: URL
        let service: VaultService
        let writer: VaultWriter
        let bus: CommandBus
        let auditoria = AuditoriaEnMemoria()
        let servicios = ServiciosEnMemoria()
        let aprobaciones = AprobacionesEnMemoria()
        let propuestas = PropuestasEnMemoria()
        var autorizador: any AutorizadorDeHerramientas

        init(base: URL, root: URL, service: VaultService, writer: VaultWriter, autorizador: any AutorizadorDeHerramientas) {
            self.base = base; self.root = root; self.service = service; self.writer = writer
            self.bus = CommandBus(writer: writer); self.autorizador = autorizador
        }

        var appSupport: URL { base.appendingPathComponent("asup", isDirectory: true) }

        func servidor(autorizador otro: (any AutorizadorDeHerramientas)? = nil) -> ServidorDeHerramientas {
            ServidorDeHerramientas(.de(service: service, bus: bus, autorizador: otro ?? autorizador, servicios: servicios,
                                       aprobaciones: aprobaciones, propuestas: propuestas, auditoria: auditoria))
        }

        func url(_ p: String) -> URL { VaultPath(p).url(in: root) }
        func texto(_ p: String) -> String? { try? String(contentsOf: url(p), encoding: .utf8) }
        func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: url(p).path) }

        func cerrar() async {
            await service.desconectar(writer)
            await writer.close()
            service.close()
            try? FileManager.default.removeItem(at: base)
        }
    }

    /// Carpeta temporal corta (`/var/folders/…/T/tm-xxxxxx`).
    static func baseCorta() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tm-" + String(UUID().uuidString.lowercased().prefix(6)), isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copia de Ribera con lo privado de prueba, índice construido y escritor abierto.
    static func empresa(autorizador: any AutorizadorDeHerramientas = AutorizadorBasico(modoPorDefecto: .autonomo)) async throws -> Empresa {
        let base = baseCorta()
        let root = base.appendingPathComponent("Ribera", isDirectory: true)
        try FileManager.default.copyItem(at: riberaRepo, to: root)
        let fm = FileManager.default
        // Lo privado de los ajustes (no de `.tls/`): una carpeta de nombre neutro.
        try fm.createDirectory(at: VaultPath(privada).url(in: root), withIntermediateDirectories: true)
        try "---\ntitulo: Nota privada\n---\n# Nota privada\nContenido \(palabraPrivada) que ningún asistente debe ver.\n"
            .write(to: VaultPath(notaPrivada).url(in: root), atomically: true, encoding: .utf8)
        // Secretos de mentira (patrones denegados siempre).
        try "CLAVE=nada\n".write(to: VaultPath("4 · Finanzas/secrets.env").url(in: root), atomically: true, encoding: .utf8)
        try "# cookies\n".write(to: VaultPath("Buzón/cookies.txt").url(in: root), atomically: true, encoding: .utf8)
        try "clave\n".write(to: VaultPath("2 · Ventas/certificado.key").url(in: root), atomically: true, encoding: .utf8)
        // Un enlace simbólico que saca de la carpeta.
        let fuera = base.appendingPathComponent("fuera.md")
        try "# Fuera\n".write(to: fuera, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: VaultPath("2 · Ventas/enlace.md").url(in: root), withDestinationURL: fuera)

        let entry = VaultEntry(nombre: "Asesoría Ribera", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida)
        let estado = base.appendingPathComponent("estado", isDirectory: true)
        let service = try VaultService(entry: entry, root: root,
                                       options: .init(privado: [VaultPath(privada)], stateDirectory: estado, vigilar: false))
        _ = try await service.open { _ in }
        let writer = try await VaultWriter.open(entry: entry, root: root, options: .init(
            stateDirectory: estado, appSupport: base.appendingPathComponent("asup"), app: "The Last System pruebas"))
        _ = await service.conectar(writer)
        return Empresa(base: base, root: root, service: service, writer: writer, autorizador: autorizador)
    }

    /// Abre una empresa, ejecuta el cuerpo y la cierra siempre (también si falla).
    static func conEmpresa(autorizador: any AutorizadorDeHerramientas = AutorizadorBasico(modoPorDefecto: .autonomo),
                           _ cuerpo: (Empresa) async throws -> Void) async throws {
        let e = try await empresa(autorizador: autorizador)
        do {
            try await cuerpo(e)
        } catch {
            await e.cerrar()
            throw error
        }
        await e.cerrar()
    }

    static func contexto(_ slug: String = "mika", coordinador: Bool = true, areas: [AreaCode] = [.direccion],
                         leeTodas: Bool = true, profundidad: Int = 0, origen: String? = nil, maxTareas: Int = 10,
                         ejecucion: String = "r-prueba") -> ContextoDelAsistente {
        ContextoDelAsistente(ejecucion: ejecucion, asistente: slug, coordinador: coordinador, areas: areas,
                             leeAreas: leeTodas ? AreaCode.allCases : [], profundidad: profundidad, origen: origen,
                             maxTareas: maxTareas)
    }

    /// Texto y datos de una respuesta.
    static func objeto(_ r: ToolResult) -> [String: Value] {
        r.estructurado?.objectValue ?? [:]
    }
}

/// Autorizador roto a propósito: lo deja todo. Sirve para probar los cerrojos que no dependen de él.
struct AutorizadorQueDejaTodo: AutorizadorDeHerramientas {
    func autorizar(_ p: PeticionDeAccion) async -> VeredictoDeAccion { .permitido }
}

/// Reloj que se puede adelantar.
final class RelojDePrueba: @unchecked Sendable {
    private let lock = NSLock()
    private var _ahora = Date()
    var ahora: Date { lock.withLock { _ahora } }
    func adelantar(_ s: TimeInterval) { lock.withLock { _ahora += s } }
}
