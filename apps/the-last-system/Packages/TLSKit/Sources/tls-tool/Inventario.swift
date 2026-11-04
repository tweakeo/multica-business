import ArgumentParser
import Foundation
import TLSCore
import TLSImport

struct Inventario: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inventario de una carpeta con la misma poda que la copia, sin descargar nada de iCloud.",
        discussion: "Dos inventarios con el mismo hash de árbol tienen las mismas rutas, tamaños y contenidos."
    )

    @Argument(help: "Carpeta.")
    var carpeta: String

    @Option(parsing: .upToNextOption, help: "Ruta relativa que no se mira (se puede repetir).")
    var excluir: [String] = []

    @Flag(help: "Incluye Archivo/.")
    var incluirArchivo = false

    @Flag(help: "No calcula el SHA-256 de cada fichero (más rápido; el hash de árbol solo cubre tamaños).")
    var sinHashes = false

    @Flag(help: "Mira también lo oculto (.tls, .obsidian, .DS_Store) y Archivo/: para comprobar que nada ha escrito en una copia. Lo privado sigue sin mirarse.")
    var completo = false

    @Flag(help: "Imprime el inventario completo en JSON.")
    var json = false

    func run() async throws {
        try CLI.protect()
        let root = CLI.folderURL(carpeta)
        let inventory = try await CLI.runAsync {
            try await Inventory.make(of: root, exclusiones: excluir.map(VaultPath.init),
                                     incluirArchivo: incluirArchivo, conHashes: !sinHashes, completo: completo)
        }
        if json {
            print(try CLI.json(inventory))
            return
        }
        print("Carpeta: \(inventory.raiz)")
        print("Ficheros: \(inventory.ficheros) · carpetas: \(inventory.carpetas) · enlaces: \(inventory.enlaces)")
        print("Bytes: \(inventory.bytes) (\(CLI.bytes(inventory.bytes)))")
        print("Solo en iCloud: \(inventory.dataless)")
        print("Rutas excluidas (no listadas): \(inventory.excluidas)")
        print("Hash del árbol\(inventory.conHashes ? "" : " (sin contenidos)"): \(inventory.hashArbol)")
    }
}
