import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// La ruta «Tu carpeta ya está organizada» (PLAN §6.7): una copia con formato G3 y el ejemplo de Ribera, copiados a
/// temporales propios (nunca se tocan los del repositorio).
@Suite("Ordenar lo que tienes · carpeta ya ordenada (G3 y Ribera)", .serialized)
struct RutaG3Tests {
    static let paquete = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL
    static let fixture = paquete.appendingPathComponent("Tests/TLSCoreTests/Fixtures/EmpresaMinima")
    static let ribera = paquete.appendingPathComponent("../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL

    func copiar(_ origen: URL) throws -> EmpresaDePrueba {
        let e = try EmpresaDePrueba(nombre: "Copia")
        try FileManager.default.removeItem(at: e.raiz)
        try FileManager.default.copyItem(at: origen, to: e.raiz)
        return e
    }

    @Test("Copia de G3: no se mueve nada, solo se adoptan fichas; se comprueba y se deshace")
    func g3() async throws {
        let e = try copiar(Self.fixture)
        defer { e.limpiar() }
        let privado = FuenteImportacion.carpetaDeLaEmpresa(e.raiz, privado: [VaultPath("Privado")])
        let antes = try await Inventory.make(of: e.raiz, exclusiones: [VaultPath("Privado")])
        let inv = try await InventarioImportacion.hacer([privado], opciones: .init(hoy: EmpresaDePrueba.hoy))
        #expect(!inv.elementos.contains { $0.clave.contains("Privado/") })
        #expect(inv.porHerramienta.keys.allSatisfy { $0 == .ordenada })
        let zona = ZonaPreparacion(inventario: inv, layout: VaultLayout.load(root: e.raiz).layout, hoy: EmpresaDePrueba.hoy)
        let vista = try await applier(e).preparar(zona)
        #expect(vista.mover == 0 && vista.archivar == 0)
        #expect(vista.propiedades > 0)
        #expect(vista.resumen == "Mover 0 · Propiedades a \(vista.propiedades) · Archivar 0 · No se borra nada")
        let r = try await applier(e).aplicar(vista, con: try await e.bus())
        #expect(r.verificacion.sinDiferencias, "\(r.verificacion.diferencias)")
        #expect(r.verificacion.editadosAProposito == vista.propiedades)
        let lucia = try #require(e.texto("2 · Ventas/Contactos/Lucía Prueba.md"))
        #expect(lucia.contains("tls_type: contact") && lucia.contains("tipo: persona"))
        #expect(try String(contentsOf: Self.fixture.appendingPathComponent("Privado/Expediente personal.md"), encoding: .utf8)
                == e.texto("Privado/Expediente personal.md"))
        try await ImportApplier.deshacer(r, con: try await e.bus())
        let despues = try await Inventory.make(of: e.raiz, exclusiones: [VaultPath("Privado")])
        #expect(despues.hashArbol == antes.hashArbol, "\(antes.diferencias(con: despues))")
    }

    @Test("«Nada» para lo ya ordenado: ni se adopta ni se fecha (no se toca)")
    func nadaNoTocaNada() async throws {
        let e = try copiar(Self.fixture)
        defer { e.limpiar() }
        let inv = try await InventarioImportacion.hacer([.carpetaDeLaEmpresa(e.raiz, privado: [VaultPath("Privado")])],
                                                        opciones: .init(hoy: EmpresaDePrueba.hoy))
        var zona = ZonaPreparacion(inventario: inv, layout: VaultLayout.load(root: e.raiz).layout, hoy: EmpresaDePrueba.hoy)
        zona.fijarAlcance(.ordenada, .nada)
        let vista = try await applier(e).preparar(zona)
        #expect(vista.propiedades == 0 && vista.mover == 0 && !vista.hayCambios)
        #expect(vista.plan.ops.count == 1)   // solo el informe, que no se escribe si no hay nada que hacer
    }

    @Test("El ejemplo de Ribera ya está ordenado: nada que mover, nada que aplicar")
    func ribera() async throws {
        let e = try copiar(Self.ribera)
        defer { e.limpiar() }
        let inv = try await InventarioImportacion.hacer([.carpetaDeLaEmpresa(e.raiz)], opciones: .init(hoy: EmpresaDePrueba.hoy))
        #expect(inv.elementos.count > 100)
        let zona = ZonaPreparacion(inventario: inv, layout: VaultLayout.load(root: e.raiz).layout, hoy: EmpresaDePrueba.hoy)
        let vista = try await applier(e).preparar(zona)
        #expect(vista.mover == 0 && vista.archivar == 0 && vista.propiedades == 0, "\(vista.resumen)")
        await #expect(throws: ImportError.sinNadaQueHacer) { try await applier(e).aplicar(vista, con: try await e.bus()) }
        let calidad = InformeCalidad.revisar(snapshot: VaultSnapshot.read(root: e.raiz), huellas: try await Inventory.make(of: e.raiz))
        #expect(calidad.avisos.allSatisfy { jerga($0.detalle).isEmpty })
    }
}
