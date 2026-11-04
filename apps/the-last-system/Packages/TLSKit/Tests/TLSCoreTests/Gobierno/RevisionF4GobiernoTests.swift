import Foundation
import Testing
@testable import TLSCore

/// Revisión adversarial de F4 (rol revisión-seguridad): aprobaciones. Los fallos se corrigieron en el corrector final de F4: las pruebas quedan como regresión.
@Suite("Revisión F4 · gobierno", .serialized)
struct RevisionF4GobiernoTests {
    /// R8: «Aprobar con mis cambios» escribe solo los campos que la persona tocó y aprueba **lo que haya en el fichero
    /// en ese momento**, sin comprobar que sea lo que la hoja le enseñó. Si el borrador cambia mientras la hoja está
    /// abierta (otra copia sincronizada, otro programa, otro asistente), se aprueba un destinatario, un importe o un texto
    /// que la persona nunca vio. «Aprobar» tal cual sí lo para (huella de la petición); este camino, no.
    @Test("R8 · «Aprobar con mis cambios» aprueba un destinatario que cambió después de abrir la hoja")
    func aprobarConCambiosNoAtaLoVisto() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let ruta = try await AprobacionesTests.borrador(e, bus: bus)
        let espia = AprobacionesTests.Espia()
        let apr = Aprobaciones(bus: bus, autorizador: a,
                               ejecutor: EjecutorDeAprobaciones(correo: espia, pasarela: espia, facturacion: espia),
                               snapshot: { e.foto() })
        let id = try #require(try await apr.solicitar(accion: .enviarCorreo, borrador: ruta, asistente: "comercial").id)

        // La hoja carga lo que ve la persona.
        let visto = try await apr.detalle(id)
        #expect(visto.aQuien == ["persona@example.com"])

        // Mientras la mira, el borrador cambia por fuera: otro destinatario.
        let texto = try #require(e.texto(ruta.raw))
        #expect(texto.contains("persona@example.com"))
        e.escribir(ruta.raw, texto.replacingOccurrences(of: "persona@example.com", with: "otra@example.net"))

        // Corrige solo el asunto y pulsa «Aprobar con mis cambios» (la hoja manda solo lo que tocó).
        let r = try? await apr.aprobarConMisCambios(id, autor: .persona("Manu"),
                                                    cambios: CambiosDeAprobacion(asunto: "Seguimiento de la propuesta (2)"))
        let fin = try apr.store.aprobacion(id)
        // Corregido (corrector final F4): R8: aprobarConMisCambios no recibe ni compara la huella de lo que enseñó la hoja
        do {
            #expect(r == nil, "se aprobó: \(String(describing: r))")
            #expect(fin?.carga.destinatarios != ["otra@example.net"], "se aprobó un destinatario que no se vio")
            #expect(espia.llamadas.value.isEmpty)
        }
    }
}
