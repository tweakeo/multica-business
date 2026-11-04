import Foundation
import Testing
@testable import TLSCore

/// Lo que Finanzas enseña a la persona (errores, avisos, motivos, resúmenes, el paquete) va sin jerga (PLAN §6.9).
@Suite("Finanzas: textos sin jerga")
struct GlosarioFinanzasTests {
    typealias A = FinanzasApoyo
    static let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash"]

    static func jerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return prohibidas.filter { palabras.contains($0) }
    }

    @Test func ningunTextoVisibleConJerga() throws {
        var textos: [String] = []
        let errores: [any LocalizedError] = [
            ErrorExtracto.ilegible, ErrorExtracto.vacio, ErrorExtracto.sinCabecera, ErrorExtracto.sinColumna("Fecha"),
            ErrorImportacion.sinCuenta, ErrorConciliacion.soloUnaPersona, ErrorConciliacion.nadaQueConfirmar,
            ErrorConciliacion.movimientoNoEncontrado("x"), ErrorConciliacion.yaConciliado("x"),
            ErrorConciliacion.facturaNoEncontrada("x"), ErrorConciliacion.importeNoCoincide("x"), ErrorConciliacion.repetida("x"),
        ]
        textos += errores.compactMap(\.errorDescription)
        textos += RangoCaja.allCases.map(\.titulo)
        textos += [ConciliationMatcher.motivoNumero, ConciliationMatcher.motivoContraparte]

        let snap = VaultSnapshot.read(root: RutasRepo.ribera)
        let registros = RegistrosFinanzas(snapshot: snap)
        textos += registros.avisos
        let imp = ImportadorExtracto(snapshot: snap, reloj: A.relojRibera)
        let cuenta = try #require(imp.registros.cuentas.first { $0.id == A.idCorriente })
        textos.append(try imp.vistaPrevia(A.datosRibera(A.extractoRibera), nombre: "x.csv", cuenta: cuenta).resumen)
        let c = Conciliador(registros: registros, reloj: A.relojRibera)
        textos += c.propuestas.map(\.motivo)
        textos.append(try c.confirmar(try #require(c.propuestas.first), autor: A.manu).resumen)
        textos.append(try c.confirmar(try #require(c.propuestas.first), autor: A.manu).plan.descripcion)
        let tes = Tesoreria(registros: registros, hoy: A.relojRibera.hoy)
        textos += [tes.runway.motivo].compactMap { $0 }
        let t = TrimestreFiscal(registros: registros, hoy: A.relojRibera.hoy)
        for n in 1...4 {
            let r = t.resumen(PeriodoTrimestre(anio: 2026, numero: n)!)
            for m in [r.modelo303, r.modelo130, r.modelo111, r.modelo115] {
                textos += m.notas + m.lineas.map(\.concepto) + m.faltan.flatMap { [$0.tipo, $0.descripcion] }
                switch m.aplica {
                case .si: break
                case .no(let s), .sinDato(let s): textos.append(s)
                }
            }
            let p = PreparadorPaquete(registros: registros, reloj: A.relojRibera).preparar(PeriodoTrimestre(anio: 2026, numero: n)!)
            textos.append(p.resumen)
            textos += p.ficheros.filter { $0.ruta.ext == "md" }.map { NoteDocument(text: $0.texto).body }
        }
        // Sin datos.
        let vacia = A.empresa([:])
        defer { vacia.limpiar() }
        textos += [Tesoreria(snapshot: vacia.foto(), reloj: relojDePrueba()).runway.motivo].compactMap { $0 }
        textos += TrimestreFiscal(snapshot: vacia.foto(), reloj: relojDePrueba()).modelo303(PeriodoTrimestre(anio: 2026, numero: 4)!).notas

        #expect(textos.count > 40)
        let malos = textos.filter { !Self.jerga($0).isEmpty }
        #expect(malos.isEmpty, "Con jerga: \(malos)")
    }
}
