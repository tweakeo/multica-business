import ArgumentParser
import Foundation
import Synchronization
import TLSCore
import TLSImport

struct Copiar: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Crea una copia de trabajo de una carpeta de empresa sin tocar el original.",
        discussion: "Lo excluido no se lista ni se copia. Archivo/ queda fuera salvo --incluir-archivo."
    )

    @Option(help: "Carpeta de origen.")
    var origen: String

    @Option(parsing: .upToNextOption, help: "Ruta relativa que no se copia ni se mira (se puede repetir).")
    var excluir: [String] = []

    @Flag(help: "Copia también Archivo/.")
    var incluirArchivo = false

    @Option(help: "Carpeta donde crear la copia (por defecto ~/The Last System/Empresas o TLS_EMPRESAS).")
    var destino: String?

    @Option(help: "Nombre de la copia (por defecto «<origen> (copia AAAA-MM-DD)»).")
    var nombre: String?

    @Flag(help: "Imprime el informe y la entrada en JSON.")
    var json = false

    func run() async throws {
        try CLI.protect()
        let source = CLI.folderURL(origen)
        let empresas = destino.map(CLI.folderURL) ?? AppLocations.empresas
        let options = CopyOptions(exclusiones: excluir.map(VaultPath.init), incluirArchivo: incluirArchivo,
                                  nombre: nombre)
        let lastPhase = Mutex<CopyProgress.Fase?>(nil)
        let (report, entry) = try await CLI.run {
            try await DemoCopier().copy(from: source, into: empresas, options: options) { p in
                let isNew = lastPhase.withLock { last -> Bool in
                    defer { last = p.fase }
                    return last != p.fase
                }
                if isNew || p.total == p.hechos {
                    CLI.printErr("  \(p.fase.rawValue): \(p.hechos)\(p.total.map { " de \($0)" } ?? "")")
                }
            }
        }
        if json {
            struct Salida: Encodable { let informe: CopyReport; let entrada: VaultEntry }
            print(try CLI.json(Salida(informe: report, entrada: entry)))
            return
        }
        print("Copia creada en: \(report.destino)")
        print("Archivos copiados: \(report.copiados) (\(CLI.bytes(report.bytes)))")
        print("Comprobados con SHA-256: \(report.verificados) · diferencias: \(report.diferencias.count)")
        print("Solo en iCloud (no copiados): \(report.soloEnICloud.count)")
        if !report.enlacesOmitidos.isEmpty { print("Enlaces omitidos: \(report.enlacesOmitidos.count)") }
        print("No copiado: \(report.exclusiones.isEmpty ? "nada" : report.exclusiones.joined(separator: ", "))")
        print("Identificador: \(entry.id.uuidString.lowercased())")
        print("Informe: \(DemoCopier().stateDirectory(for: entry.id).appendingPathComponent(DemoCopier.reportFileName).path)")
    }
}
