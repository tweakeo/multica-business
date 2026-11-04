import Foundation
import Testing
@testable import TLSCore

@Suite("Dominio · expediente de una empresa")
struct ExpedienteTests {
    typealias A = DominioApoyo
    static let talleres = VaultPath("2 · Ventas/Empresas/talleres-martin-e-hijos.md")

    @Test("Talleres Martín: lo facturado, lo pendiente y su línea de tiempo; tras el cobro, cobrado y ganada")
    func talleres() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let e = try #require(Expediente.de(Self.talleres, en: c.lectura()))
        #expect(e.contactos.map(\.nombre) == ["Jorge Martín"])
        #expect(e.oportunidades.map(\.ruta) == [A.opoJorge])
        #expect(e.facturas.map(\.ruta) == [A.facturaJorge])
        #expect(e.numeros.facturado == 18150 && e.numeros.cobrado == 0 && e.numeros.pendiente == 18150 && e.numeros.vencido == 0)
        #expect(e.numeros.abiertas == 1 && e.numeros.valorAbierto == 15000)
        #expect(e.numeros.conversion == nil)
        // La factura del 15 oct es anterior al alta (19 oct, el día de la copia): el alta se cae.
        #expect(!e.linea.contains { $0.clase == .alta })
        #expect(e.linea.last?.clase == .factura && e.linea.last?.detalle == "181,50 €")
        #expect(e.numeros.desde?.description == "2026-10-15" && e.numeros.diasSinContacto == 0)
        #expect(e.alertas.isEmpty)

        let motor = try await c.motor()
        _ = try await motor.ejecutar(A.confirmarCobroJorge())
        let d = try #require(Expediente.de(Self.talleres, en: c.lectura()))
        #expect(d.numeros.cobrado == 18150 && d.numeros.pendiente == 0)
        #expect(d.numeros.ganadas == 1 && d.numeros.conversion == 100 && d.numeros.proyectosActivos == 1)
        #expect(d.cobros.map(\.id) == ["PAG-20261017-001"])
        #expect(d.tareas.count == 6)
        #expect(d.linea.contains { $0.clase == .cobro && $0.detalle == "181,50 €" })
        #expect(d.linea.contains { $0.clase == .ganada })
        #expect(d.linea.first { $0.clase == .factura }?.detalle == "181,50 € · cobrada")
    }

    @Test("Sin facturas ni oportunidades cerradas no hay cifras: «Sin dato», nunca 0")
    func sinDato() throws {
        let l = LecturaDominio(snapshot: VaultSnapshot.read(root: A.ribera))
        let e = try #require(Expediente.de(VaultPath("2 · Ventas/Empresas/movil-levante.md"), en: l))
        #expect(e.numeros.facturado == nil && e.numeros.cobrado == nil && e.numeros.pendiente == nil && e.numeros.vencido == nil)
        #expect(e.numeros.conversion == nil && e.numeros.valorAbierto == nil)
        // Lo único que se sabe es cuándo entró: el alta se queda.
        #expect(e.linea.map(\.clase) == [.alta])
        // Es un proveedor: no pide contacto.
        #expect(e.alertas.isEmpty)
        // Una ficha que no es una empresa no tiene expediente.
        #expect(Expediente.de(A.opoJorge, en: l) == nil)
    }

    @Test("Alertas: lo vencido sin cobrar, la oportunidad quieta y el cliente sin contacto")
    func alertas() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        // Ribera al 20 de noviembre: la factura de Jorge ya venció y su oportunidad lleva un mes quieta.
        let reloj = Reloj(hoy: LocalDate(year: 2026, month: 11, day: 20)!)
        let l = LecturaDominio(snapshot: c.foto(), reloj: reloj)
        let e = try #require(Expediente.de(Self.talleres, en: l))
        #expect(e.numeros.vencido == 18150)
        #expect(e.alertas.map(\.texto) == ["181,50 € vencidos sin cobrar", "«Jorge Martín · Trimestrales» lleva 32 días quieta"])
        #expect(e.alertas.first?.nivel == .mal && e.alertas.first?.que == "Reclamar hoy")
        // Un cliente sin contactos.
        try c.escribir(VaultPath("2 · Ventas/Empresas/sin-nadie.md"), "---\ntls_type: organization\nnombre: Sin Nadie SL\nrelacion: [cliente]\n---\n# Sin Nadie SL\n")
        let sin = try #require(Expediente.de(VaultPath("2 · Ventas/Empresas/sin-nadie.md"), en: c.lectura()))
        #expect(sin.alertas.map(\.texto) == ["No hay ningún contacto ligado a esta empresa"])
        #expect(sin.linea.isEmpty)
        for a in e.alertas + sin.alertas { #expect(A.conJerga(a.texto + " " + a.que).isEmpty) }
    }
}
