import Testing
@testable import TLSCore

@Suite struct VaultPathTests {
    @Test func normalizaNFC() {
        let nfd = "1 · Direccio\u{301}n/A\u{301}rea.md"
        #expect(VaultPath(nfd) == VaultPath("1 · Dirección/Área.md"))
    }

    @Test func resuelveRelativosConEspacios() {
        let from = VaultPath("2 · Ventas/Área.md")
        #expect(from.resolvingRelative("Sistemas/Registro%20de%20contactos.md") == VaultPath("2 · Ventas/Sistemas/Registro de contactos.md"))
        #expect(from.resolvingRelative("../Empresa.md") == VaultPath("Empresa.md"))
    }

    @Test func fechasLocales() {
        #expect(LocalDate(parsing: "2026-10-21")?.description == "2026-10-21")
        #expect(LocalDate(parsing: "21/10/2026")?.description == "2026-10-21")
        #expect(LocalDate(parsing: "2026-02-30") == nil)
    }
}
