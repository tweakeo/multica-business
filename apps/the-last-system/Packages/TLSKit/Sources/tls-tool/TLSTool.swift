import ArgumentParser
import Foundation
import TLSCore
import TLSImport

@main
struct TLSTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tls-tool",
        abstract: "Herramientas de desarrollo de The Last System.",
        discussion: """
        Ninguna orden descarga nada de iCloud: el proceso entero corre con la materialización \
        de ficheros desactivada. Variables útiles: TLS_EMPRESAS y TLS_APP_SUPPORT.
        """,
        subcommands: [Copiar.self, Inventario.self, Indexar.self, ConvertirG2.self, Renombrar.self, Deshacer.self]
    )
}

/// Utilidades comunes de las órdenes.
enum CLI {
    /// Activa la protección de iCloud para todo el proceso o aborta.
    static func protect() throws {
        guard ICloudProtection.protectCurrentProcess() else {
            printErr("No he podido activar la protección que evita descargar archivos de iCloud.")
            throw ExitCode.failure
        }
    }

    static func printErr(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    static func folderURL(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    /// Ejecuta y convierte los errores conocidos en un mensaje claro y código 1.
    static func run<T>(_ body: () async throws -> T) async throws -> T {
        try await runAsync(body)
    }

    static func runAsync<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as ExitCode {
            throw error
        } catch let error as LocalizedError where error.errorDescription != nil {
            printErr(error.errorDescription!)
            throw ExitCode.failure
        }
    }

    /// Igual, para código síncrono.
    static func run<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as LocalizedError where error.errorDescription != nil {
            printErr(error.errorDescription!)
            throw ExitCode.failure
        }
    }
}
