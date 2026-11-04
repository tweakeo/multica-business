import Testing
@testable import TLSVisores

// Cimientos: el rol «visores» añade aquí sus pruebas.
@Suite("TLSVisores · tipo de fichero")
struct TipoFicheroTests {
    @Test("Cada extensión va a su visor; el texto, al editor")
    func clasificacion() {
        #expect(TipoFichero.de(extension: "md") == .texto)
        #expect(TipoFichero.de(extension: "CSV") == .texto)
        #expect(TipoFichero.de(extension: "pdf") == .pdf)
        #expect(TipoFichero.de(extension: "HEIC") == .imagen)
        #expect(TipoFichero.de(extension: "m4a") == .audio)
        #expect(TipoFichero.de(extension: "mov") == .video)
        #expect(TipoFichero.de(extension: "numbers") == .otro)
        #expect(TipoFichero.de(extension: "") == .otro)
        #expect(!TipoFichero.texto.esVisor && TipoFichero.pdf.esVisor)
    }
}
