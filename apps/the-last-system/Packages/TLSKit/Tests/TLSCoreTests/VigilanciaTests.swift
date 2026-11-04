import Foundation
import Testing
@testable import TLSCore

@Suite(.serialized) struct VigilanciaTests {
    /// Criterio F0: una edición externa (TextEdit) aparece en 3 s o menos.
    @Test func edicionExternaEnTresSegundos() async throws {
        let root = Apoyo.copiaDeFixture()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let svc = try Apoyo.servicio(root, state: state, vigilar: true)
        let cambios = Caja<[VaultPath]>([])
        let llegada = Caja<Date?>(nil)
        svc.onExternalChange = { paths in
            cambios.update { $0 += paths }
            if llegada.value == nil { llegada.value = Date() }
        }
        _ = try await svc.open { _ in }
        try await Task.sleep(nanoseconds: 300_000_000)

        // Escritura «como TextEdit»: fichero nuevo y sustitución atómica.
        let rumbo = root.appendingPathComponent("1 · Dirección/Rumbo.md")
        let inicio = Date()
        try "# Rumbo\n\nEditado fuera con la palabra mandarina.\n".write(to: rumbo, atomically: true, encoding: .utf8)

        let llego = await Apoyo.esperar(6) { cambios.value.contains(VaultPath("1 · Dirección/Rumbo.md")) }
        #expect(llego)
        if let t = llegada.value {
            let segundos = t.timeIntervalSince(inicio)
            print("Vigilancia: cambio visible en \(String(format: "%.2f", segundos)) s")
            #expect(segundos <= 3.0)
        }
        // Ya reindexado cuando llega el aviso.
        #expect(svc.search("mandarina").first?.note.path == VaultPath("1 · Dirección/Rumbo.md"))

        // Nota nueva y borrada.
        cambios.value = []
        let nueva = root.appendingPathComponent("2 · Ventas/Contactos/Nuevo Contacto.md")
        try "# Nuevo Contacto\n\nConoce a [[Lucía Prueba]].\n".write(to: nueva, atomically: true, encoding: .utf8)
        #expect(await Apoyo.esperar(6) { cambios.value.contains(VaultPath("2 · Ventas/Contactos/Nuevo Contacto.md")) })
        #expect(svc.quickOpen("nuevo con", limit: 1).first?.path.name == "Nuevo Contacto.md")
        #expect(svc.backlinks(to: VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")).contains { $0.path.name == "Nuevo Contacto.md" })

        cambios.value = []
        try FileManager.default.removeItem(at: nueva)
        #expect(await Apoyo.esperar(6) { cambios.value.contains(VaultPath("2 · Ventas/Contactos/Nuevo Contacto.md")) })
        #expect(svc.summary(of: VaultPath("2 · Ventas/Contactos/Nuevo Contacto.md")) == nil)
        svc.close()
    }

    @Test func tocarSinCambiarNoAvisa() async throws {
        let root = Apoyo.copiaDeFixture()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root.deletingLastPathComponent(), state) }
        let svc = try Apoyo.servicio(root, state: state, vigilar: true)
        let cambios = Caja<[VaultPath]>([])
        svc.onExternalChange = { paths in cambios.update { $0 += paths } }
        _ = try await svc.open { _ in }
        try await Task.sleep(nanoseconds: 300_000_000)
        let embudo = root.appendingPathComponent("2 · Ventas/Sistemas/Embudo.md")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: embudo.path)
        try await Task.sleep(nanoseconds: 2_800_000_000)
        #expect(!cambios.value.contains(VaultPath("2 · Ventas/Sistemas/Embudo.md")))
        svc.close()
    }
}

@Suite struct UbiquityTests {
    @Test func politicaSoloDuranteElBloque() {
        let antes = UbiquityInspector.currentThreadPolicy
        let dentro = UbiquityInspector.withoutMaterializing { UbiquityInspector.currentThreadPolicy }
        #expect(dentro == Int32(IOPOL_MATERIALIZE_DATALESS_FILES_OFF))
        #expect(UbiquityInspector.currentThreadPolicy == antes)
    }

    @Test func ficheroLocalNoEsDataless() {
        let url = Apoyo.empresaMinima.appendingPathComponent("Empresa.md")
        let info = UbiquityInspector.info(url)
        #expect(info?.dataless == false)
        #expect(info?.isDirectory == false)
        #expect((info?.size ?? 0) > 0)
    }
}
