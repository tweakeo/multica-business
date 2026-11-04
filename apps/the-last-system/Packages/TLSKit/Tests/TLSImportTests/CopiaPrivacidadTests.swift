import Foundation
import Synchronization
import Testing
import TLSCore
@testable import TLSImport

/// `privado` declarado en `.tls/` del origen, en formatos válidos que el núcleo (VaultLayout/Yams)
/// entiende: la copia debe dejarlo fuera sin listarlo. (Revisión adversarial de F0, casos B1–B5.)
@Suite(.serialized) struct CopiaPrivacidadTests {
    struct Caso: Sendable, CustomStringConvertible {
        let nombre: String, fichero: String, texto: String, privada: String
        var description: String { nombre }
    }

    static let casos: [Caso] = [
        Caso(nombre: "B1 lista en flujo de varias líneas", fichero: ".tls/config.yaml",
             texto: "privado: [\n  \"Privado\"\n]\n", privada: "Privado"),
        Caso(nombre: "B2 lista en bloque con CRLF", fichero: ".tls/config.yaml",
             texto: "version: 1\r\nprivado:\r\n  - Privado\r\n", privada: "Privado"),
        Caso(nombre: "B3 plantilla {finanzas} en layout.json", fichero: ".tls/layout.json",
             texto: #"{"preset":"humana","privado":["{finanzas}/Bancos"]}"#, privada: "4 · Finanzas/Bancos"),
        Caso(nombre: "B4 nombre con corchetes", fichero: ".tls/config.yaml",
             texto: "privado:\n  - \"Privado [2026]\"\n", privada: "Privado [2026]"),
        Caso(nombre: "B5 nombre con coma", fichero: ".tls/config.yaml",
             texto: "privado: [\"Privado, Seguros\"]\n", privada: "Privado, Seguros"),
    ]

    @Test(arguments: casos)
    func privadoDeTlsNoSeCopiaNiSeLista(_ caso: Caso) async throws {
        let t = try TempTree(); defer { t.remove() }
        let o = "Origen"
        for code in AreaCode.allCases { try t.write("\(code.numero) · \(code.nombre)/Área.md", "# \(code.nombre)\n", in: o) }
        try t.write("\(caso.privada)/secreto.md", "SECRETO-COPIA\n", in: o)
        try t.write(caso.fichero, caso.texto, in: o)
        let origen = t.dir(o)
        let fs = RecordingFileSystem()
        let (report, entry) = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let destino = URL(fileURLWithPath: report.destino)
        #expect(!FileManager.default.fileExists(atPath: destino.appendingPathComponent("\(caso.privada)/secreto.md").path))
        let privada = RecordingFileSystem.key(origen.appendingPathComponent(caso.privada))
        #expect(!fs.log.withLock { $0.listed }.contains { $0 == privada || $0.hasPrefix(privada + "/") })
        // Se informa con el nombre real y solo porque de verdad se dejó fuera.
        #expect(report.exclusiones.contains(caso.privada))
        #expect(entry.exclusionesCopia.contains(caso.privada))
    }

    /// La exclusión de la persona con otras mayúsculas también se aplica, y se informa con el nombre en disco.
    @Test func exclusionPersonalSinDistinguirMayusculas() async throws {
        let t = try TempTree(); defer { t.remove() }
        try t.write("Privado/secreto.md", "S\n", in: "O")
        try t.write("Empresa.md", "E\n", in: "O")
        let (report, _) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: t.dir("O"), into: t.dir("Empresas"), options: CopyOptions(exclusiones: [VaultPath("privado")])) { _ in }
        #expect(!FileManager.default.fileExists(atPath: report.destino + "/Privado"))
        // Sin Archivo en el origen, no se dice «Sin copiar: Archivo».
        #expect(report.exclusiones == ["Privado"])
    }

    /// La carpeta declara privada una ruta que ya no existe (¿movida, renombrada?): se para sin listar nada.
    @Test func privadoDeclaradoQueNoExisteParaLaCopia() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        try t.write(".tls/config.yaml", "privado:\n  - \"4 · Finanzas/Trámites/Privada Y\"\n", in: "Empresa Prueba")
        let fs = RecordingFileSystem()
        do {
            _ = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
                .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
            Issue.record("Debía parar")
        } catch CopyGuardError.privadoNoEncontrado(let p) {
            #expect(p == "4 · Finanzas/Trámites/Privada Y")
        }
        #expect(fs.log.withLock { $0.listed }.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: t.dir("Empresas").path))
    }

    /// Si no se puede leer qué es privado (aquí: `layout.json` es un enlace), no se copia nada.
    @Test func privadoIlegibleParaLaCopia() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let layout = origen.appendingPathComponent(".tls/layout.json")
        try FileManager.default.removeItem(at: layout)
        let fuera = try t.write("layout.json", #"{"preset":"humana"}"#, in: "Fuera")
        try FileManager.default.createSymbolicLink(at: layout, withDestinationURL: fuera)
        await #expect(throws: CopyGuardError.self) {
            _ = try await DemoCopier(appSupport: t.dir("Soporte"))
                .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: t.dir("Empresas").path))
    }

    /// «Cancelar» de verdad: la copia se para, lo copiado a medias va a la Papelera y no hay entrada.
    @Test func copiaCanceladaNoDejaNada() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let empresas = t.dir("Empresas")
        let fs = RecordingFileSystem()
        let empezo = AsyncStream<Void>.makeStream()
        let cancelada = Bandera()
        fs.onCopy.withLock {
            $0 = {
                empezo.continuation.yield()
                // Espera (en el hilo de copia) a que la prueba pulse «Cancelar».
                for _ in 0..<500 where !cancelada.value { usleep(10_000) }
            }
        }
        let tarea = Task {
            try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
                .copy(from: origen, into: empresas, options: CopyOptions(exclusiones: [DemoCopierTests.privada])) { _ in }
        }
        for await _ in empezo.stream { break }
        tarea.cancel()
        cancelada.value = true
        let resultado = await tarea.result
        guard case .failure(let error) = resultado else { Issue.record("La copia debía cancelarse"); return }
        #expect(error is CancellationError)
        #expect(fs.log.withLock { $0.trashed }.count == 1)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: empresas.path)) ?? []).isEmpty)
    }

    @Test func verificacionFallidaVaALaPapelera() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let empresas = t.dir("Empresas")
        let fs = RecordingFileSystem(corruptUnder: empresas.path)
        await #expect(throws: CopyError.self) {
            _ = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
                .copy(from: origen, into: empresas, options: CopyOptions(exclusiones: [DemoCopierTests.privada])) { _ in }
        }
        #expect(fs.log.withLock { $0.trashed }.count == 1)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: empresas.path)) ?? []).isEmpty)
    }

    @Test func informeConIdentificadorEnMinusculas() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let copier = DemoCopier(appSupport: t.dir("Soporte"))
        let (_, entry) = try await copier
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [DemoCopierTests.privada])) { _ in }
        let data = try Data(contentsOf: copier.stateDirectory(for: entry.id).appendingPathComponent(DemoCopier.reportFileName))
        let texto = String(decoding: data, as: UTF8.self)
        #expect(texto.contains(entry.id.uuidString.lowercased()))
        #expect(!texto.contains(entry.id.uuidString))
        let leido = try JSONDecoder.iso.decode(CopyReport.self, from: data)
        #expect(leido.vaultID == entry.id)
    }

    /// El inventario «completo» ve lo que una app escribiría en la copia (ocultos, Archivo…);
    /// el normal no, y por eso la guía usa el completo para esa comprobación.
    @Test func inventarioCompletoVeEscriturasTipicas() async throws {
        let t = try TempTree(); defer { t.remove() }
        let o = "Copia"
        try t.write("Empresa.md", "E\n", in: o)
        try t.write("1 · Dirección/Área.md", "D\n", in: o)
        try t.write(".tls/config.yaml", "clase: copia\nprivado: []\n", in: o)
        try t.write(".obsidian/app.json", "{}", in: o)
        try t.write("Archivo/viejo.md", "v\n", in: o)
        try t.write("Privado/secreto.md", "s\n", in: o)
        let root = t.dir(o)
        let antes = try await Inventory.make(of: root, exclusiones: [VaultPath("Privado")], completo: true)
        let normalAntes = try await Inventory.make(of: root, exclusiones: [VaultPath("Privado")])
        try t.write(".DS_Store", "x", in: o)
        try t.write("Archivo/escrito-por-la-app.md", "x", in: o)
        try t.write(".obsidian/workspace.json", "{}", in: o)
        try t.write(".tls/escritor.json", "{}", in: o)
        let despues = try await Inventory.make(of: root, exclusiones: [VaultPath("Privado")], completo: true)
        let normalDespues = try await Inventory.make(of: root, exclusiones: [VaultPath("Privado")])
        #expect(antes.hashArbol != despues.hashArbol)
        #expect(Set(antes.diferencias(con: despues)) == [".DS_Store", "Archivo/escrito-por-la-app.md",
                                                          ".obsidian/workspace.json", ".tls/escritor.json"])
        #expect(normalAntes.hashArbol == normalDespues.hashArbol)
        // Lo privado sigue sin mirarse también en el completo.
        #expect(!despues.entradas.contains { $0.ruta.hasPrefix("Privado") })
    }
}

/// Bandera compartida entre la prueba y el hilo de copia.
final class Bandera: Sendable {
    private let state = Mutex(false)
    var value: Bool {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
