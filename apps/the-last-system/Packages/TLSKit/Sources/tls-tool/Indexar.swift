import ArgumentParser
import CryptoKit
import Foundation
import Synchronization
import TLSCore
import TLSImport

struct Indexar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Abre una carpeta con el núcleo, construye el índice y muestra las seis áreas.",
        discussion: "El índice va a TLS_APP_SUPPORT (o Application Support)/<id>/index.sqlite. No escribe en la carpeta."
    )

    @Argument(help: "Carpeta de la empresa.")
    var carpeta: String

    @Option(parsing: .upToNextOption, help: "Ruta relativa que no se lista ni se indexa (se puede repetir).")
    var excluir: [String] = []

    func run() async throws {
        try CLI.protect()
        let root = CLI.folderURL(carpeta).resolvingSymlinksInPath()
        let peek = try await CLI.run { try await CopyConfig.peek(root) }
        // Si la app ya conoce esta carpeta, se heredan sus exclusiones (las carpetas privadas elegidas).
        let registrada = VaultRegistry().load().first {
            URL(fileURLWithPath: $0.ruta).standardizedFileURL.resolvingSymlinksInPath().path == root.path
        }
        let exclusiones = (registrada?.exclusionesCopia ?? []) + excluir.map { VaultPath($0).raw }
        let entry = VaultEntry(id: registrada?.id ?? peek.id ?? Self.stableID(for: root.path),
                               nombre: root.lastPathComponent, ruta: root.path, bookmark: nil,
                               clase: registrada?.clase ?? peek.clase ?? .real, escritura: .bloqueada,
                               exclusionesCopia: Array(Set(exclusiones)).sorted())
        if !entry.exclusionesCopia.isEmpty {
            CLI.printErr("  sin mirar: \(entry.exclusionesCopia.joined(separator: ", "))")
        }
        let service = try CLI.run { try VaultService(entry: entry, root: root) }
        defer { service.close() }
        let shown = Mutex(0)
        let stats = try await CLI.runAsync {
            try await service.open { p in
                let show = shown.withLock { last -> Bool in
                    guard p.processed - last >= 500 || p.processed == p.total else { return false }
                    last = p.processed
                    return true
                }
                if show { CLI.printErr("  indexadas \(p.processed)\(p.total.map { " de \($0)" } ?? "")") }
            }
        }
        print("Carpeta: \(root.path) (\(entry.clase.rawValue), id \(entry.id.uuidString.lowercased()))")
        print("Notas: \(stats.notes) · solo en iCloud: \(stats.dataless) · \(String(format: "%.2f", stats.seconds)) s")
        let areas = service.areas()
        if areas.isEmpty {
            print("Áreas: ninguna (el núcleo aún no las lee o la carpeta no tiene las seis áreas)")
        }
        for a in areas {
            var line = "\(a.code.numero) · \(a.titulo) — \(a.estado.etiqueta)"
            if !a.estadoTexto.isEmpty { line += " («\(a.estadoTexto)»)" }
            if !a.tieneFicha { line += " · sin Área.md" }
            print(line)
        }
    }

    /// UUID estable a partir de la ruta, para no dejar un índice nuevo en cada ejecución.
    static func stableID(for path: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(("tls-tool:" + path.precomposedStringWithCanonicalMapping).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50  // versión 5 (por nombre)
        bytes[8] = (bytes[8] & 0x3f) | 0x80  // variante RFC 4122
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
