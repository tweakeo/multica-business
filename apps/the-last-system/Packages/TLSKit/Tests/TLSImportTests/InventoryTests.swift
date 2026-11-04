import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite struct InventoryTests {
    @Test func reglasEnNFCySinMayusculas() {
        let rules = ExclusionRules.forCopy(personales: [VaultPath("4 · Finanzas/Tra\u{301}mites/Privada X")],
                                           incluirArchivo: false)
        #expect(rules.excludes(VaultPath("4 · Finanzas/Trámites/Privada X")))
        #expect(rules.excludes(VaultPath("4 · finanzas/trámites/privada x/secreto.md")))
        #expect(!rules.excludes(VaultPath("4 · Finanzas/Trámites")))
        #expect(!rules.excludes(VaultPath("4 · Finanzas/Trámites/Privada XY")))
        #expect(rules.excludes(VaultPath("Archivo")))
        #expect(rules.excludes(VaultPath("Archivo/x.md")))
        #expect(!rules.excludes(VaultPath("2 · Ventas/Archivo")))
        #expect(rules.excludes(VaultPath(".tls/escritor.json")))
        #expect(!rules.excludes(VaultPath(".tls/layout.json")))
        #expect(rules.excludes(VaultPath("2 · Ventas/.DS_Store")))
        #expect(!rules.excludes(.root))
    }

    @Test func patronesDePrivado() {
        var rules = ExclusionRules()
        rules.addEntry("*.key")
        rules.addEntry("4 · Finanzas/Banco*")
        #expect(rules.excludes(VaultPath("a/b/firma.key")))
        #expect(rules.excludes(VaultPath("4 · Finanzas/Bancos/x.csv")))
        #expect(!rules.excludes(VaultPath("4 · Finanzas/Registros/x.csv")))
    }

    @Test func leeListasDeConfig() {
        let yaml = """
        version: 1
        id: "ABC"   # comentario
        privado:
          - "4 · Finanzas/Trámites/Privada X"
          - Otra # nota
        agentes: {}
        """
        #expect(CopyConfig.topLevelScalar("id", in: yaml) == "ABC")
        #expect(CopyConfig.topLevelList("privado", in: yaml) == ["4 · Finanzas/Trámites/Privada X", "Otra"])
        #expect(CopyConfig.topLevelList("privado", in: "privado: [a, \"b c\"]\n") == ["a", "b c"])
        #expect(CopyConfig.topLevelList("privado", in: "privado: []\n").isEmpty)
        #expect(CopyConfig.quoted("a\"b\\c") == "\"a\\\"b\\\\c\"")
    }

    @Test func inventarioConPodaYHashEstable() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let privada = VaultPath("4 · Finanzas/Trámites/Privada X")
        let fs = RecordingFileSystem()
        let a = try await Inventory.make(of: origen, exclusiones: [privada], fileSystem: fs)
        let b = try await Inventory.make(of: origen, exclusiones: [privada])
        #expect(a.hashArbol == b.hashArbol)
        #expect(!a.entradas.contains { VaultPath($0.ruta).isDescendant(of: privada) })
        #expect(!a.entradas.contains { $0.ruta.hasPrefix("Archivo") })
        let excluded = RecordingFileSystem.key(privada.url(in: origen))
        #expect(!fs.log.withLock { $0.listed }.contains { $0 == excluded || $0.hasPrefix(excluded + "/") })
        #expect(fs.log.withLock { $0.unprotectedCalls }.isEmpty)
        let grande = try #require(a.entradas.first { $0.ruta == "5 · Marca/Recursos/grande.bin" })
        let esperado: Int64 = 3 * 1024 * 1024 + 17
        #expect(grande.tamano == esperado)
        #expect(grande.sha256 == (try sha(origen.appendingPathComponent("5 · Marca/Recursos/grande.bin"))))
        #expect(a.entradas.contains { $0.ruta == "6 · Equipo/Vacía" && $0.tipo == .carpeta })
        #expect(a.dataless == 0)

        // Un cambio de contenido cambia el hash del árbol y aparece en las diferencias.
        try Data("cambio\n".utf8).write(to: origen.appendingPathComponent("Empresa.md"))
        let c = try await Inventory.make(of: origen, exclusiones: [privada])
        #expect(c.hashArbol != a.hashArbol)
        #expect(a.diferencias(con: c) == ["Empresa.md"])
    }

    @Test func inventarioCuentaSoloEnICloud() async throws {
        let t = try TempTree(); defer { t.remove() }
        let origen = try t.makeOrigin()
        let nota = origen.appendingPathComponent("2 · Ventas/Área.md")
        let fs = RecordingFileSystem(datalessPaths: [nota.path])
        let inv = try await Inventory.make(of: origen, fileSystem: fs)
        #expect(inv.dataless == 1)
        let e = try #require(inv.entradas.first { $0.ruta == "2 · Ventas/Área.md" })
        #expect(e.dataless && e.sha256 == nil && e.tamano != nil)
        #expect(!fs.log.withLock { $0.hashed }.contains(RecordingFileSystem.key(nota)))
    }

    @Test func sha256PorBloques() throws {
        let t = try TempTree(); defer { t.remove() }
        let url = try t.write("vacio.txt", "", in: "x")
        #expect(try sha(url) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let abc = try t.write("abc.txt", "abc", in: "x")
        #expect(try sha(abc) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
