import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

@Suite("Migas")
@MainActor
struct MigasTests {
    @Test("Nombre corto: código primero, sin el nombre del nivel anterior, 24 caracteres como mucho")
    func nombreCorto() {
        #expect(PlegadoMigas.nombreCorto("Arquitectura Nexo · Trimestrales", anteriores: ["Arquitectura Nexo"]) == "Trimestrales")
        #expect(PlegadoMigas.nombreCorto("Factura a Arquitectura Nexo SLP", anteriores: ["Arquitectura Nexo"]) == "Factura")
        #expect(PlegadoMigas.nombreCorto("Factura de mayo", codigo: "F-2026-0014") == "F-2026-0014")
        #expect(PlegadoMigas.nombreCorto("Revisión trimestral de la estrategia comercial de 2026") == "Revisión trimestral de…")
        #expect(PlegadoMigas.nombreCorto("Revisión trimestral de la estrategia comercial de 2026").count <= 24)
        // Un título que contiene el nombre anterior en medio no se corta.
        #expect(PlegadoMigas.nombreCorto("Visita a Arquitectura Nexo para cerrar el contrato", anteriores: ["Arquitectura Nexo"])
                == PlegadoMigas.nombreCorto("Visita a Arquitectura Nexo para cerrar el contrato"))
    }

    @Test("Códigos al principio del título o del fichero")
    func codigos() {
        #expect(PlegadoMigas.codigo(titulo: "F-2026-0014 Arquitectura Nexo", fichero: nil) == "F-2026-0014")
        #expect(PlegadoMigas.codigo(titulo: "Revisar el contrato", fichero: "t-0042-revisar-el-contrato") == "T-0042")
        #expect(PlegadoMigas.codigo(titulo: "FI1 · Facturación", fichero: nil) == "FI1")
        #expect(PlegadoMigas.codigo(titulo: "Jorge Martín", fichero: "jorge-martin") == nil)
        #expect(PlegadoMigas.codigo(titulo: "2026-10-12", fichero: "2026-10-12") == nil)
    }

    private func migas(_ nombres: [String], origen: [Int: String] = [:]) -> [Miga] {
        nombres.enumerated().map { i, n in
            Miga(id: i, destino: .busqueda(n), nombre: n, completo: n, icono: "doc.text", area: nil, pestanaOrigen: origen[i])
        }
    }

    @Test("Criterio §11.6: con 8 niveles y la ventana a 1.100 pt se ven la raíz, la penúltima y la última")
    func ochoNiveles() {
        TLSFuentes.registrar()
        let m = migas(["2 · Ventas", "Contactos", "Jorge Martín", "Trimestrales 2026", "T-0042",
                       "Talleres Martín e Hijos", "F-2026-0014", "R-2026-0007"], origen: [3: "Proyectos", 5: "Facturas"])
        // Ventana de 1.100 pt con la barra lateral de 248 pt.
        let ancho = PlegadoMigas.anchoParaMigas(anchoDetalle: 1_100 - TLSAncho.barraLateral)
        let e = PlegadoMigas.plegar(m, ancho: ancho) { miga, ultima, origen in
            PlegadoMigas.medirConLetra(miga, ultima: ultima, conOrigen: origen)
        }
        let visibles = e.compactMap { if case .miga(let x, _) = $0 { return x.nombre } else { return nil } }
        #expect(visibles.first == "2 · Ventas")
        #expect(visibles.suffix(2) == ["F-2026-0014", "R-2026-0007"])
        #expect(e.contains { if case .plegadas = $0 { return true }; return false })
    }

    @Test("Plegado por pasos: primero el gris de la pestaña, luego los intermedios, luego la penúltima")
    func pasos() {
        let m = migas(["A", "B", "C", "D", "E"], origen: [2: "Pestaña"])
        let medida: (Miga, Bool, Bool) -> CGFloat = { _, _, origen in origen ? 150 : 100 }
        // Cabe todo con el gris.
        #expect(PlegadoMigas.plegar(m, ancho: 1_000, medir: medida).count == 5)
        // Sin el gris cabe: 5 × 100 + 4 × 21 = 584.
        let sinGris = PlegadoMigas.plegar(m, ancho: 600, medir: medida)
        #expect(sinGris.count == 5)
        #expect(sinGris.allSatisfy { if case .miga(_, let o) = $0 { return !o }; return false })
        // Raíz, «…», penúltima y última: 400 + 30 + 3 × 21 = 493.
        let tres = PlegadoMigas.plegar(m, ancho: 500, medir: medida)
        #expect(tres.count == 4)
        if case .plegadas(let dentro) = tres[1] { #expect(dentro.map(\.nombre) == ["B", "C"]) }
        // Ni así: la penúltima también se pliega; la última, nunca.
        let dos = PlegadoMigas.plegar(m, ancho: 300, medir: medida)
        #expect(dos.count == 3)
        if case .miga(let ultima, _) = dos[2] { #expect(ultima.nombre == "E") }
        if case .plegadas(let dentro) = dos[1] { #expect(dentro.map(\.nombre) == ["B", "C", "D"]) }
    }
}
