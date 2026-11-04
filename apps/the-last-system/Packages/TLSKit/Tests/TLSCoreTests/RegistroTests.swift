import Foundation
import Testing
@testable import TLSCore

@Suite struct RegistroTests {
    @Test func altaCambioYBaja() throws {
        let dir = Apoyo.tempDir("asup")
        defer { Apoyo.limpiar(dir) }
        let reg = VaultRegistry(directory: dir)
        #expect(reg.load().isEmpty)
        let vieja = VaultEntry(nombre: "Copia", ruta: dir.path, bookmark: nil, clase: .copia, escritura: .permitida,
                               exclusionesCopia: ["4 · Finanzas/Privado"], creada: Date(timeIntervalSince1970: 1_000))
        let nueva = VaultEntry(nombre: "Ejemplo", ruta: dir.path, bookmark: nil, clase: .demo, escritura: .permitida,
                               creada: Date(timeIntervalSince1970: 2_000))
        try reg.upsert(vieja)
        try reg.upsert(nueva)
        #expect(reg.load().map(\.nombre) == ["Ejemplo", "Copia"])
        var cambiada = vieja
        cambiada.nombre = "Copia renombrada"
        try reg.upsert(cambiada)
        #expect(reg.load().count == 2)
        #expect(reg.load().last?.nombre == "Copia renombrada")
        #expect(reg.load().last?.exclusionesCopia == ["4 · Finanzas/Privado"])
        // Formato en disco: claves en español, exclusiones con guion bajo.
        let json = try String(contentsOf: dir.appendingPathComponent("vaults.json"), encoding: .utf8)
        #expect(json.contains("\"exclusiones_copia\""))
        try reg.remove(id: vieja.id)
        #expect(reg.load().map(\.id) == [nueva.id])
        // Sin temporales sueltos.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["vaults.json"])
    }

    @Test func ficheroDanadoSeAparta() throws {
        let dir = Apoyo.tempDir("asup")
        defer { Apoyo.limpiar(dir) }
        try Data("{roto".utf8).write(to: dir.appendingPathComponent("vaults.json"))
        let reg = VaultRegistry(directory: dir)
        #expect(reg.load().isEmpty)
        try reg.upsert(VaultEntry(nombre: "Nueva", ruta: "/", bookmark: nil, clase: .demo, escritura: .permitida))
        #expect(reg.load().count == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("vaults.json.dañado-") })
    }

    @Test func bookmarkYRuta() throws {
        let dir = Apoyo.tempDir("asup")
        let carpeta = Apoyo.tempDir("empresa")
        defer { Apoyo.limpiar(dir, carpeta) }
        let reg = VaultRegistry(directory: dir)
        let bm = try VaultRegistry.makeBookmark(for: carpeta)
        let e = VaultEntry(nombre: "X", ruta: "/no/existe", bookmark: bm, clase: .copia, escritura: .permitida)
        try reg.upsert(e)
        #expect(reg.resolveURL(e)?.standardizedFileURL.resolvingSymlinksInPath().path
                == carpeta.standardizedFileURL.resolvingSymlinksInPath().path)
        // Sin bookmark: la ruta, si existe.
        let soloRuta = VaultEntry(nombre: "Y", ruta: carpeta.path, bookmark: nil, clase: .copia, escritura: .permitida)
        #expect(reg.resolveURL(soloRuta) != nil)
        let perdida = VaultEntry(nombre: "Z", ruta: "/no/existe", bookmark: nil, clase: .copia, escritura: .permitida)
        #expect(reg.resolveURL(perdida) == nil)
    }

    @Test func idDeInstalacionEstable() {
        let dir = Apoyo.tempDir("asup")
        defer { Apoyo.limpiar(dir) }
        let a = VaultRegistry(directory: dir).installationID()
        let b = VaultRegistry(directory: dir).installationID()
        #expect(a == b)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("instalacion.json").path))
    }
}
