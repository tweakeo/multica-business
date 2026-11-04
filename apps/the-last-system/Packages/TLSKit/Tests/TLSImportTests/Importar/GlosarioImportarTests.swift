import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// Lint del glosario (PLAN §6.9) para todo lo que el paso 2 enseña: errores, nombres, colecciones y motivos.
@Suite("Ordenar lo que tienes · glosario")
struct GlosarioImportarTests {
    @Test("Ningún texto para la persona usa jerga")
    func sinJerga() {
        var textos: [String] = []
        textos += HerramientaOrigen.allCases.map(\.nombre)
        textos += TipoDocumento.allCases.map(\.nombre)
        textos += ColeccionV2.catalogo.flatMap { [$0.nombre, $0.descripcion] }
        textos += AvisoCalidad.Tipo.allCases.map(\.titulo)
        textos += [AlcanceImportacion.todo.nombre, AlcanceImportacion.nada.nombre,
                   AlcanceImportacion.loActivo(desde: LocalDate(year: 2026, month: 1, day: 1)!).nombre]
        let errores: [ImportError] = [.fuenteNoAccesible("X"), .fuenteDentroDeLaCarpeta("X"), .aliasRepetido("X"), .enlacesEnRiesgo(2),
                                      .demasiadoGrande(3 << 30), .deshacerNoDisponible, .cambioDesdeLaVistaPrevia("X"),
                                      .sinNadaQueHacer, .mapaIlegible("X"), .verificacionFallida(1)]
        textos += errores.compactMap(\.errorDescription)
        textos += [OCRError.imagenIlegible("x").errorDescription!, OCRError.paginaIlegible("x").errorDescription!]
        let v = ResultadoVerificacion(total: 3, identicos: 2, editadosAProposito: 1, creados: 0, diferencias: [],
                                      recuentoAntes: 3, recuentoDespues: 4, recuentoEsperado: 3)
        textos.append(v.texto)
        for t in textos {
            #expect(jerga(t).isEmpty, "«\(t)» → \(jerga(t))")
            #expect(!t.contains(".tls/"))
        }
        #expect(v.texto == "3 de 3 (recuento + SHA-256) · el recuento no cuadra: hay 4 y esperaba 3")
    }
}
