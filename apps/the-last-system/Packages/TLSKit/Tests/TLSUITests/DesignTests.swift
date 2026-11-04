import Foundation
import Testing
@testable import TLSDesign

@Suite("TLSDesign · formatos y tokens")
struct DesignTests {
    @Test("Enteros con punto de millares, también con 4 cifras")
    func enteros() {
        #expect(TLSFormat.entero(0) == "0")
        #expect(TLSFormat.entero(999) == "999")
        #expect(TLSFormat.entero(1_034) == "1.034")
        #expect(TLSFormat.entero(10_340) == "10.340")
        #expect(TLSFormat.entero(1_234_567) == "1.234.567")
        #expect(TLSFormat.entero(-1_034) == "-1.034")
    }

    @Test("Progreso «340 de 1.034»")
    func progreso() {
        #expect(TLSFormat.progreso(340, de: 1_034) == "340 de 1.034")
        #expect(TLSFormat.progreso(12, de: nil) == "12")
    }

    @Test("Plurales")
    func cuenta() {
        #expect(TLSFormat.cuenta(1, "fila", "filas") == "1 fila")
        #expect(TLSFormat.cuenta(1_034, "fila", "filas") == "1.034 filas")
    }

    @Test("Fecha corta: sin año si es de este año")
    func fechaCorta() throws {
        let cal = Calendar.tlsGregoriano
        let fecha = try #require(cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 9)))
        let mismoAnio = try #require(cal.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let otroAnio = try #require(cal.date(from: DateComponents(year: 2027, month: 1, day: 5)))
        #expect(TLSFormat.fechaCorta(fecha, now: mismoAnio, calendar: cal) == "21/10")
        #expect(TLSFormat.fechaCorta(fecha, now: otroAnio, calendar: cal) == "21/10/2026")
        #expect(TLSFormat.fecha(fecha, calendar: cal) == "21/10/2026")
    }

    @Test("Ruta corta con ~")
    func rutaCorta() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(TLSFormat.rutaCorta(home + "/The Last System/Empresas") == "~/The Last System/Empresas")
        #expect(TLSFormat.rutaCorta("/Volumes/Disco") == "/Volumes/Disco")
        // iCloud Drive con su nombre del Finder (F3: la carpeta de origen de la puesta en marcha suele estar ahí).
        #expect(TLSFormat.rutaCorta(home + "/Library/Mobile Documents/com~apple~CloudDocs/Empresa") == "iCloud Drive/Empresa")
    }

    @Test("Fragmentos: ‹›→ negrita")
    func snippet() {
        let partes = Snippet.partes("la ‹factura› de ‹octubre›.")
        #expect(partes.map(\.text) == ["la ", "factura", " de ", "octubre", "."])
        #expect(partes.map(\.match) == [false, true, false, true, false])
        #expect(Snippet.plain("la ‹factura›") == "la factura")
        // Marca sin cerrar: texto normal, sin perder caracteres.
        #expect(Snippet.plain("abc ‹def") == "abc ‹def")
        #expect(Snippet.partes("abc ‹def").allSatisfy { !$0.match })

        #expect(Snippet.compacto("# Título\n\nla  ‹factura›\tde") == "# Título la ‹factura› de")

        let attributed = Snippet.attributed("a ‹b› c")
        let negritas = attributed.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
        #expect(negritas.count == 1)
        #expect(String(attributed[negritas[0].range].characters) == "b")
    }

    @Test("Colores: hex y variante aclarada para oscuro")
    func colores() throws {
        let dir = try #require(TLSTokens.RGBA(hex: "#8B5CF6"))
        #expect(dir.hex == "#8B5CF6")
        let claro = dir.aclarado(0.28)
        #expect(claro.r > dir.r && claro.g > dir.g && claro.b >= dir.b)
        #expect(TLSTokens.RGBA(hex: "zz") == nil)
        #expect(TLSTokens.RGBA(hex: "E6007E")?.hex == "#E6007E")
        #expect(TLSTokens.RGBA(hex: "#E6007E80")?.a ?? 0 > 0.49)
    }

    @Test("Insignias en mayúsculas y con texto para VoiceOver")
    func insignias() {
        #expect(BadgeKind.copia.text == "COPIA")
        #expect(BadgeKind.ejemplo.text == "EJEMPLO")
        #expect(BadgeKind.soloLectura.text == "SOLO LECTURA")
        #expect(BadgeKind.allCases.allSatisfy { !$0.accessibilityText.isEmpty && !$0.systemImage.isEmpty })
    }
}
