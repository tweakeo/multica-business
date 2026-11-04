import ArgumentParser
import Foundation
import TLSCore
import TLSImport

struct ConvertirG2: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "convertir-g2",
        abstract: "Convierte una carpeta G2 (la demo antigua) a la estructura v2 en una carpeta nueva.",
        discussion: """
        No toca el origen y nunca escribe encima: el destino no debe existir. Dos conversiones de la misma \
        carpeta dan el mismo hash de árbol. Lo que no tiene sitio queda en el informe del Buzón y, si es un \
        fichero entero, en Archivo/Importación <fecha>/.
        """
    )

    @Argument(help: "Carpeta G2 de origen.")
    var origen: String

    @Argument(help: "Carpeta nueva (no debe existir).")
    var destino: String

    @Option(help: "Clase de la carpeta nueva: copia o demo.")
    var clase: String = "copia"

    @Option(help: "Reloj fijo de la demo (AAAA-MM-DD), que se guarda en .tls/config.yaml.")
    var hoy: String?

    @Flag(help: "Imprime el informe completo en JSON.")
    var json = false

    func run() async throws {
        try CLI.protect()
        guard let c = VaultClass(rawValue: clase), c != .real else {
            CLI.printErr("La clase debe ser «copia» o «demo».")
            throw ExitCode.failure
        }
        let informe = try await CLI.runAsync {
            try await ConversorG2.convertir(origen: CLI.folderURL(origen), destino: CLI.folderURL(destino),
                                            opciones: OpcionesConversionG2(clase: c, hoy: hoy))
        }
        if json {
            print(try CLI.json(informe))
            return
        }
        print("Carpeta nueva: \(informe.destino ?? destino)")
        print("Ficheros de origen: \(informe.ficherosOrigen) · registros convertidos: \(informe.porTipo.values.reduce(0, +))")
        print("Notas: \(informe.notas) · tablas CSV: \(informe.tablas) · copiados: \(informe.copiados) · tareas: \(informe.tareas)")
        print("Justificantes comprobados: \(informe.verificados) · guardados sin convertir: \(informe.archivados.count)")
        print("Avisos: \(informe.avisos.count) · campos sin convertir: \(informe.camposNoConvertidos.count)")
        print("Informe: \(informe.informe)")
        print("Hash del árbol: \(informe.hashArbol ?? "")")
    }
}
