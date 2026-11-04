import Foundation
import Synchronization
import Testing
import TLSCore
@testable import TLSImport

@Suite struct DemoCopierTests {
    static let privada = VaultPath("4 · Finanzas/Trámites/Privada X")

    @Test func exclusionesSiempre() {
        #expect(CopyOptions.siempre.contains(".tls/escritor.json"))
    }

    /// Criterio F0 §3: la carpeta excluida no se lista nunca y no llega nada de ella a la copia.
    @Test func carpetaExcluidaNiSeListaNiSeCopia() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let fs = RecordingFileSystem()
        let copier = DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))

        let (report, entry) = try await copier.copy(from: origen, into: t.dir("Empresas"),
                                                    options: CopyOptions(exclusiones: [Self.privada])) { _ in }

        let log = fs.log.withLock { $0 }
        let excludedAbs = RecordingFileSystem.nfc(Self.privada.url(in: origen).path)
        #expect(!log.listed.contains { $0 == excludedAbs || $0.hasPrefix(excludedAbs + "/") })
        #expect(!log.hashed.contains { $0.hasPrefix(excludedAbs + "/") })
        #expect(!log.copied.contains { $0.hasPrefix(excludedAbs + "/") })
        // La carpeta que la contiene sí se listó (si no, la prueba no demostraría nada).
        #expect(log.listed.contains(RecordingFileSystem.nfc(origen.appendingPathComponent("4 · Finanzas/Trámites").path)))
        #expect(log.unprotectedCalls.isEmpty)

        let destino = URL(fileURLWithPath: report.destino, isDirectory: true)
        let files = relativeFiles(under: destino)
        #expect(!files.contains { VaultPath($0).isDescendant(of: Self.privada) })
        #expect(files.contains("4 · Finanzas/Trámites/Público/nota.md"))
        #expect(!FileManager.default.fileExists(atPath: destino.appendingPathComponent("4 · Finanzas/Trámites/Privada X").path))
        #expect(entry.exclusionesCopia.contains(Self.privada.raw))
        #expect(report.exclusiones.contains(Self.privada.raw))
    }

    /// Criterio F0 §3: SHA-256 igual, sin escritor.json, config.yaml de copia y origen intacto.
    @Test func copiaFielYOrigenIntacto() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let before = try await Inventory.make(of: origen, exclusiones: [], incluirArchivo: true)

        let (report, entry) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [Self.privada])) { _ in }
        let destino = URL(fileURLWithPath: report.destino, isDirectory: true)

        // Mismo contenido, fichero a fichero.
        let copiedFiles = relativeFiles(under: destino).filter { $0 != ".tls/config.yaml" }
        #expect(copiedFiles.count == report.copiados)
        #expect(report.copiados == report.verificados)
        #expect(report.diferencias.isEmpty)
        for rel in copiedFiles {
            #expect(try sha(VaultPath(rel).url(in: destino)) == sha(VaultPath(rel).url(in: origen)), "\(rel)")
        }
        #expect(copiedFiles.contains("5 · Marca/Recursos/grande.bin"))
        #expect(copiedFiles.contains(".tls/layout.json"))
        #expect(copiedFiles.contains(".obsidian/app.json"))
        // Lo que nunca se copia.
        #expect(!copiedFiles.contains(".tls/escritor.json"))
        #expect(!copiedFiles.contains(".obsidian/workspace.json"))
        #expect(!copiedFiles.contains { $0.hasSuffix(".DS_Store") })
        // Carpeta vacía conservada.
        #expect(LocalFileSystem().isDirectory(destino.appendingPathComponent("6 · Equipo/Vacía")))

        // config.yaml propio de la copia.
        let yaml = try String(contentsOf: destino.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
        let hoy = LocalDate.today().description
        #expect(yaml.contains("\nversion: 1\n"))
        #expect(yaml.contains("\nid: \(entry.id.uuidString.lowercased())\n"))
        #expect(yaml.contains("\nclase: copia\n"))
        #expect(yaml.contains("\norigen: \"\(origen.path)\"\n"))
        #expect(yaml.contains("\ncreada: \(hoy)\n"))
        #expect(yaml.contains("\nprivado: []\n"))
        #expect(yaml.hasPrefix("#"))
        #expect(CopyConfig.topLevelScalar("id", in: yaml) == entry.id.uuidString.lowercased())
        #expect(CopyConfig.topLevelScalar("origen", in: yaml) == origen.path)
        #expect(CopyConfig.topLevelList("privado", in: yaml).isEmpty)

        // Entrada a registrar.
        #expect(entry.id == report.vaultID)
        #expect(entry.clase == .copia)
        // F1: las copias nacen con escritura (la carpeta real sigue en solo lectura).
        #expect(entry.escritura == .permitida)
        #expect(entry.origen == origen.path)
        #expect(entry.ruta == destino.path)
        #expect(entry.nombre == "Empresa Prueba (copia \(hoy))")
        #expect(entry.bookmark != nil)
        #expect(entry.exclusionesCopia == [Self.privada.raw, "Archivo"])

        // Informe guardado en el estado de la carpeta.
        let informe = t.dir("Soporte").appendingPathComponent(entry.id.uuidString.lowercased())
            .appendingPathComponent("copia-informe.json")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(CopyReport.self, from: Data(contentsOf: informe))
        #expect(saved.vaultID == entry.id)
        #expect(saved.copiados == report.copiados)

        // Origen idéntico antes y después (rutas, tamaños y contenidos).
        let after = try await Inventory.make(of: origen, exclusiones: [], incluirArchivo: true)
        #expect(before.hashArbol == after.hashArbol)
        #expect(before.diferencias(con: after).isEmpty)
        #expect(FileManager.default.fileExists(atPath: origen.appendingPathComponent(".tls/escritor.json").path))
        #expect(!FileManager.default.fileExists(atPath: origen.appendingPathComponent(".tls/config.yaml").path))
    }

    @Test func archivoExcluidoPorDefecto() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let fs = RecordingFileSystem()
        let (report, _) = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let archivo = RecordingFileSystem.nfc(origen.appendingPathComponent("Archivo").path)
        #expect(!fs.log.withLock { $0.listed }.contains { $0 == archivo || $0.hasPrefix(archivo + "/") })
        let files = relativeFiles(under: URL(fileURLWithPath: report.destino))
        #expect(!files.contains { $0.hasPrefix("Archivo/") })
        #expect(report.exclusiones == ["Archivo"])

        // Con incluirArchivo sí se copia.
        let (con, _) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"),
                  options: CopyOptions(exclusiones: [], incluirArchivo: true)) { _ in }
        let conFiles = relativeFiles(under: URL(fileURLWithPath: con.destino))
        #expect(conFiles.contains("Archivo/viejo.md"))
        #expect(conFiles.contains("Archivo/Importación 2026-09-01/a.md"))
    }

    @Test func destinoExistenteRecibeSufijo() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let empresas = t.dir("Empresas")
        let hoy = LocalDate.today().description
        // Una copia previa con contenido propio: no se toca.
        let previa = try t.write("mio.md", "no tocar\n", in: "Empresas/Empresa Prueba (copia \(hoy))")
        let copier = DemoCopier(appSupport: t.dir("Soporte"))
        let options = CopyOptions(exclusiones: [Self.privada])

        let (r2, e2) = try await copier.copy(from: origen, into: empresas, options: options) { _ in }
        #expect(e2.nombre == "Empresa Prueba (copia \(hoy)) 2")
        #expect(r2.destino == empresas.appendingPathComponent("Empresa Prueba (copia \(hoy)) 2").path)
        let (_, e3) = try await copier.copy(from: origen, into: empresas, options: options) { _ in }
        #expect(e3.nombre == "Empresa Prueba (copia \(hoy)) 3")
        #expect(try String(contentsOf: previa, encoding: .utf8) == "no tocar\n")
        #expect(relativeFiles(under: previa.deletingLastPathComponent()) == ["mio.md"])
    }

    /// Los ficheros solo en iCloud no se pueden fabricar en un test: se simulan con el disco instrumentado.
    @Test func soloEnICloudNoSeLeeNiSeCopia() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let fichero = origen.appendingPathComponent("1 · Dirección/Área.md")
        let carpeta = origen.appendingPathComponent("4 · Finanzas/Registros")
        let fs = RecordingFileSystem(datalessPaths: [fichero.path, carpeta.path])

        let recorder = ProgressRecorder()
        let (report, _) = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [Self.privada])) {
                recorder.add($0.fase)
            }
        let fases = recorder.fases

        #expect(Set(report.soloEnICloud) == ["1 · Dirección/Área.md", "4 · Finanzas/Registros"])
        let log = fs.log.withLock { $0 }
        let keyFile = RecordingFileSystem.key(fichero)
        let keyDir = RecordingFileSystem.key(carpeta)
        #expect(!log.hashed.contains(keyFile))
        #expect(!log.copied.contains(keyFile))
        #expect(!log.listed.contains(keyDir))
        let destino = URL(fileURLWithPath: report.destino)
        #expect(!FileManager.default.fileExists(atPath: destino.appendingPathComponent("1 · Dirección/Área.md").path))
        #expect(!FileManager.default.fileExists(atPath: destino.appendingPathComponent("4 · Finanzas/Registros").path))
        // La carpeta que lo contiene sí existe en la copia.
        #expect(LocalFileSystem().isDirectory(destino.appendingPathComponent("1 · Dirección")))
        #expect(fases.first == .inventario)
        #expect(fases.last == .terminado)
        #expect(fases.contains(.copia) && fases.contains(.verificacion))
    }

    @Test func verificacionFallidaNoDevuelveEntrada() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let empresas = t.dir("Empresas")
        let fs = RecordingFileSystem(corruptUnder: empresas.path)
        do {
            _ = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
                .copy(from: origen, into: empresas, options: CopyOptions(exclusiones: [Self.privada])) { _ in }
            Issue.record("Debía fallar la verificación")
        } catch CopyError.verificacionFallida(let n) {
            #expect(n > 0)
        }
    }

    @Test func enlacesNoSeSiguenNiSeCopian() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let fuera = try t.write("fuera.md", "fuera del origen\n", in: "Fuera")
        try FileManager.default.createSymbolicLink(at: origen.appendingPathComponent("enlace.md"), withDestinationURL: fuera)
        try FileManager.default.createSymbolicLink(at: origen.appendingPathComponent("enlace-carpeta"),
                                                   withDestinationURL: fuera.deletingLastPathComponent())
        let fs = RecordingFileSystem()
        let (report, _) = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [Self.privada])) { _ in }
        #expect(Set(report.enlacesOmitidos) == ["enlace.md", "enlace-carpeta"])
        let destino = URL(fileURLWithPath: report.destino)
        #expect(!LocalFileSystem().fileExists(destino.appendingPathComponent("enlace.md")))
        #expect(!fs.log.withLock { $0.listed }.contains { $0.hasSuffix("/enlace-carpeta") })
    }

    @Test func privadoDeLayoutSeRespeta() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        try FileManager.default.removeItem(at: origen.appendingPathComponent(".tls/layout.json"))
        try t.write(".tls/layout.json", "{\"preset\": \"humana\", \"privado\": [\"2 · Ventas\"]}", in: "Empresa Prueba")
        let fs = RecordingFileSystem()
        let (report, entry) = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let ventas = RecordingFileSystem.key(origen.appendingPathComponent("2 · Ventas"))
        #expect(!fs.log.withLock { $0.listed }.contains(ventas))
        #expect(!relativeFiles(under: URL(fileURLWithPath: report.destino)).contains { $0.hasPrefix("2 · Ventas/") })
        #expect(entry.exclusionesCopia.contains("2 · Ventas"))
        // layout.json se conserva tal cual.
        let destino = URL(fileURLWithPath: report.destino)
        #expect(try sha(destino.appendingPathComponent(".tls/layout.json")) == sha(origen.appendingPathComponent(".tls/layout.json")))
    }

    @Test func configDelOrigenSeSustituye() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let viejo = UUID().uuidString.lowercased()
        try t.write(".tls/config.yaml", "version: 1\nid: \(viejo)\nclase: real\nprivado:\n  - \"5 · Marca\"\n",
                    in: "Empresa Prueba")
        let (report, entry) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let yaml = try String(contentsOf: URL(fileURLWithPath: report.destino).appendingPathComponent(".tls/config.yaml"),
                              encoding: .utf8)
        #expect(CopyConfig.topLevelScalar("clase", in: yaml) == "copia")
        #expect(CopyConfig.topLevelScalar("id", in: yaml) == entry.id.uuidString.lowercased())
        #expect(entry.id.uuidString.lowercased() != viejo)
        #expect(entry.exclusionesCopia.contains("5 · Marca"))
        // El del origen no cambia.
        let original = try String(contentsOf: origen.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
        #expect(original.contains("clase: real"))
    }

    @Test func conservaFechasDeModificacion() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let antigua = Date(timeIntervalSince1970: 1_700_000_000)
        let nota = origen.appendingPathComponent("2 · Ventas/Área.md")
        let carpeta = origen.appendingPathComponent("6 · Equipo")
        try FileManager.default.setAttributes([.modificationDate: antigua], ofItemAtPath: nota.path)
        try FileManager.default.setAttributes([.modificationDate: antigua], ofItemAtPath: carpeta.path)
        let (report, _) = try await DemoCopier(appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let destino = URL(fileURLWithPath: report.destino)
        let fs = LocalFileSystem()
        #expect(fs.modificationDate(destino.appendingPathComponent("2 · Ventas/Área.md")) == antigua)
        let dirDate = try #require(fs.modificationDate(destino.appendingPathComponent("6 · Equipo")))
        #expect(abs(dirDate.timeIntervalSince(antigua)) < 0.001)
    }

    @Test func origenInexistente() async throws {
        let t = try TempTree(); defer { t.remove() }
        await #expect(throws: CopyError.self) {
            _ = try await DemoCopier(appSupport: t.dir("Soporte"))
                .copy(from: t.dir("No existe"), into: t.dir("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        }
    }

    @Test func destinoDentroDelOrigenSeRechaza() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        await #expect(throws: CopyGuardError.self) {
            _ = try await DemoCopier(appSupport: t.dir("Soporte"))
                .copy(from: origen, into: origen.appendingPathComponent("Copias"),
                      options: CopyOptions(exclusiones: [])) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: origen.appendingPathComponent("Copias").path))
    }

    @Test func rutasRealesAunqueNoExistan() throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        // /var → /private/var: con o sin «/private», y con la carpeta aún sin crear.
        let conPrivate = URL(fileURLWithPath: CopyJob.canonicalPath(origen))
        #expect(CopyJob.isInside(conPrivate.appendingPathComponent("No existe/Copias"), origen))
        #expect(CopyJob.isInside(origen.appendingPathComponent("Nueva"), conPrivate))
        #expect(!CopyJob.isInside(t.dir("Empresas"), origen))
        #expect(!CopyJob.isInside(t.dir("Empresa Prueba 2"), origen))
    }

    @Test func nombreDeDestino() {
        let d = LocalDate(year: 2026, month: 10, day: 21)!
        let o = URL(fileURLWithPath: "/x/The Last", isDirectory: true)
        #expect(CopyJob.destinationName(origen: o, nombre: nil, date: d) == "The Last (copia 2026-10-21)")
        #expect(CopyJob.destinationName(origen: o, nombre: "Mi copia/rara", date: d) == "Mi copia-rara")
        #expect(CopyJob.destinationName(origen: o, nombre: "  ", date: d) == "The Last (copia 2026-10-21)")
    }

    @Test func elHiloDeCopiaEstaProtegido() async throws {
        let protegido = try await DatalessGuard.run("prueba") { _ in DatalessGuard.currentThreadIsProtected }
        #expect(protegido)
    }
}

/// Fases recibidas, desde el hilo de copia.
final class ProgressRecorder: Sendable {
    private let state = Mutex<[CopyProgress.Fase]>([])
    func add(_ f: CopyProgress.Fase) { state.withLock { $0.append(f) } }
    var fases: [CopyProgress.Fase] { state.withLock { $0 } }
}

@Suite struct ExclusionGuardTests {
    /// Una errata en la exclusión no debe acabar copiando la carpeta privada.
    @Test func exclusionInexistenteParaLaCopia() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let fs = RecordingFileSystem()
        do {
            _ = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
                .copy(from: origen, into: t.dir("Empresas"),
                      options: CopyOptions(exclusiones: [VaultPath("4 · Finanzas/Trámites/Privda X")])) { _ in }
            Issue.record("Debía parar")
        } catch CopyGuardError.exclusionNoEncontrada(let p) {
            #expect(p == "4 · Finanzas/Trámites/Privda X")
        }
        // No se creó nada, no se copió nada y ni siquiera se listó la carpeta privada real.
        #expect(!FileManager.default.fileExists(atPath: t.dir("Empresas").path))
        #expect(fs.log.withLock { $0.copied }.isEmpty)
        #expect(fs.log.withLock { $0.listed }.isEmpty)
        await #expect(throws: CopyGuardError.self) {
            _ = try await Inventory.make(of: origen, exclusiones: [VaultPath("No existe")])
        }
    }

    @Test func exclusionDentroDeArchivoOSoloICloudCuenta() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        // Dentro de Archivo (ya excluido): coincide por la carpeta podada.
        _ = try await Inventory.make(of: origen, exclusiones: [VaultPath("Archivo/viejo.md")])
        // Dentro de una carpeta solo en iCloud: tampoco se copia, así que vale.
        let fs = RecordingFileSystem(datalessPaths: [origen.appendingPathComponent("4 · Finanzas/Registros").path])
        _ = try await Inventory.make(of: origen, exclusiones: [VaultPath("4 · Finanzas/Registros/x")], fileSystem: fs)
    }

    @Test func exclusionEscritaComoRutaAbsoluta() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let absoluta = VaultPath(origen.appendingPathComponent(DemoCopierTests.privada.raw).path)
        let fs = RecordingFileSystem()
        let (report, _) = try await DemoCopier(fileSystem: fs, appSupport: t.dir("Soporte"))
            .copy(from: origen, into: t.dir("Empresas"), options: CopyOptions(exclusiones: [absoluta])) { _ in }
        #expect(report.exclusiones.first == DemoCopierTests.privada.raw)
        #expect(!relativeFiles(under: URL(fileURLWithPath: report.destino)).contains { $0.contains("Privada X") })
    }
}
