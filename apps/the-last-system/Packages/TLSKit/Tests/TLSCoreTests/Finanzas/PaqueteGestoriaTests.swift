import Foundation
import Testing
@testable import TLSCore

@Suite("Finanzas: paquete para la gestoría")
struct PaqueteGestoriaTests {
    typealias A = FinanzasApoyo

    static let paqueteT3 = "4 · Finanzas/Fiscal/2026/T3/Modelos/Paquete gestoría"

    @Test func elPaqueteQueYaExisteNoSeToca() throws {
        let prep = PreparadorPaquete(snapshot: VaultSnapshot.read(root: RutasRepo.ribera), reloj: A.relojRibera)
        let p = prep.preparar(PeriodoTrimestre(anio: 2026, numero: 3)!)
        #expect(p.yaExiste)
        #expect(p.plan(autor: A.manu) == nil)
        #expect(p.resumen == "El paquete del T3 2026 ya está preparado: no lo toco.")
    }

    @Test func prepararElTrimestreTresDeRibera() async throws {
        let env = A.ribera()
        defer { env.limpiar() }
        // En la copia temporal se aparta el paquete que trae Ribera para volver a prepararlo.
        try FileManager.default.removeItem(at: env.url(Self.paqueteT3))
        let bus = try await env.bus()
        let antes = env.huella()
        let prep = PreparadorPaquete(snapshot: env.foto(), reloj: A.relojRibera)
        let p = prep.preparar(PeriodoTrimestre(anio: 2026, numero: 3)!)
        #expect(!p.yaExiste)
        #expect(p.ficheros.map(\.ruta.name) == ["indice.md", "libro-ingresos.csv", "libro-gastos.csv", "movimientos.csv", "diferencias.csv"])
        #expect(p.ficheros.map(\.registros) == [0, 3, 9, 26, 1])
        // Como el paquete original: lo único que falta es el justificante de ML-08-2026.
        #expect(p.diferencias.map(\.tipo) == ["gasto sin justificante"])
        #expect(p.diferencias.first?.descripcion == "ML-08-2026")
        #expect(!p.listo)
        #expect(p.documentos.count == 11)
        #expect(p.documentos.filter { !$0.registrado }.isEmpty)
        #expect(p.documentosPrivados == 0)
        let r = try await bus.ejecutar(try #require(p.plan(autor: A.manu)))
        #expect(r.hecho)
        #expect(A.cambiados(antes, env.huella()) == Set(p.ficheros.map(\.ruta.raw)))
        let indice = try #require(env.texto(Self.paqueteT3 + "/indice.md"))
        #expect(indice.contains("| Ingresos | 390,00 € | 81,90 € | 0,00 € | 471,90 € |"))
        #expect(indice.contains("| Gastos | 2.505,00 € | 526,05 € | 370,50 € | 2.660,55 € |"))
        #expect(indice.contains("listo: false"))
        #expect(indice.contains("- gasto sin justificante · 2026-08-10 · ML-08-2026 · 78,65 €"))
        #expect(indice.contains("La app no lo envía"))
        let ingresos = try #require(env.texto(Self.paqueteT3 + "/libro-ingresos.csv"))
        #expect(ingresos.hasPrefix("numero;fecha;cliente;nif;base;iva;retencion;total;estado;id\n"
            + "F-2026-0004;2026-07-05;Panadería Horno Sol SL;;150,00;31,50;0,00;181,50;cobrada;F-2026-0004\n"))
        let gastos = try #require(env.texto(Self.paqueteT3 + "/libro-gastos.csv"))
        #expect(gastos.contains("ML-08-2026;2026-08-10;Movil Levante SL;;Suministros;;65,00;13,65;0,00;78,65;FALTA;REC-20260810-001\n"))
        #expect(gastos.contains(";Fiscal/2026/T3/Gastos/inmobiliaria-centro/2026-07-01 Inmobiliaria Centro ALQ-2026-07 663,00€.pdf;"))
        let movs = try #require(env.texto(Self.paqueteT3 + "/movimientos.csv"))
        #expect(movs.contains("2026-07-12;TRANSFERENCIA DE PANADERIA HORNO SOL F-2026-0004;181,50;ingreso;;conciliado;F-2026-0004;MOV-80e6c895d220;cuenta-corriente-banco-demo\n"))
        // Los enlaces del índice a los originales resuelven.
        let foto = env.foto()
        let enlaces = LinkScanner.scan(indice).filter { $0.link.style == .markdown }
        #expect(enlaces.count == 11)
        for e in enlaces {
            #expect(foto.resolver.resolve(e.link.resolvable, from: VaultPath(Self.paqueteT3 + "/indice.md")) != nil, "\(e.link.raw)")
        }
        // Volver a prepararlo no toca nada.
        #expect(PreparadorPaquete(snapshot: foto, reloj: A.relojRibera).preparar(PeriodoTrimestre(anio: 2026, numero: 3)!).plan(autor: A.manu) == nil)
    }

    @Test func trimestreCuatroDeRiberaConLoQueFalta() {
        let prep = PreparadorPaquete(snapshot: VaultSnapshot.read(root: RutasRepo.ribera), reloj: A.relojRibera)
        let p = prep.preparar(PeriodoTrimestre(anio: 2026, numero: 4)!)
        let tipos = Dictionary(grouping: p.diferencias, by: \.tipo).mapValues(\.count)
        #expect(tipos == ["ingreso sin cobrar": 1, "gasto sin justificante": 1, "movimiento sin conciliar": 1])
        #expect(p.ficheros.map(\.registros) == [0, 1, 2, 4, 3])
        #expect(p.resumen == "Paquete del T4 2026: 2 documentos, falta resolver 3 cosas.")
    }

    @Test func loPrivadoNoEntraNiPorSuNombre() {
        let base = "4 · Finanzas/Fiscal/2026/T3/Gastos/"
        let env = A.empresa([
            ".tls/config.yaml": "version: 1\nclase: copia\nprivado:\n  - \"4 · Finanzas/Fiscal/2026/T3/Gastos/Expediente privado\"\n",
            base + "proveedor/2026-07-01 Proveedor 12,10€.pdf": "%PDF-1.4",
            base + "Expediente privado/2026-07-02 Documento reservado 99,00€.pdf": "%PDF-1.4",
            "4 · Finanzas/Registros/recibidas.csv": A.cabRecibidas
                + "R1,2026-07-01,Proveedor,P1,EUR,12.10,\"Fiscal/2026/T3/Gastos/proveedor/2026-07-01 Proveedor 12,10€.pdf\",,,,,10.00,2.10,,,\n"
                + "R2,2026-07-02,Reservado,P2,EUR,99.00,\"Fiscal/2026/T3/Gastos/Expediente privado/2026-07-02 Documento reservado 99,00€.pdf\",,,,,,,,,\n",
        ])
        defer { env.limpiar() }
        let p = PreparadorPaquete(snapshot: env.foto(), reloj: relojDePrueba()).preparar(PeriodoTrimestre(anio: 2026, numero: 3)!)
        #expect(p.documentos.count == 1)
        #expect(p.documentosPrivados == 1)
        let todo = p.ficheros.map(\.texto).joined()
        #expect(!todo.contains("Documento reservado"))
        #expect(!todo.contains("Expediente privado"))
        #expect(!todo.contains("privad"))
        #expect(todo.contains("P2;2026-07-02;Reservado;;;;;;;99,00;;R2\n"))
    }
}
