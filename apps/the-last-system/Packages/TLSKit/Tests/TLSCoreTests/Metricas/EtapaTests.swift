import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · etapa por área con lo declarado en config.yaml")
struct EtapaTests {
    static let esencialesFIN = ["FIN-01", "FIN-02", "FIN-03", "FIN-04", "FIN-05", "FIN-10"]

    /// Carpeta con estas capacidades declaradas (y, si se pide, un rol de Finanzas con ocupante).
    func carpeta(_ declaradas: [String: String], ocupante: String? = nil) -> MetricasApoyo.Carpeta {
        var yaml = "capacidades:\n"
        for (codigo, resto) in declaradas.sorted(by: { $0.key < $1.key }) { yaml += "  \(codigo): {declarada: si\(resto)}\n" }
        var ficheros: [String: String] = [:]
        if let ocupante {
            ficheros["6 · Equipo/Roles/financiero.md"] = "---\ntls_type: role\nnombre: Financiero\nclase: humano\nareas: [finanzas]\nocupante: \(ocupante)\n---\n# Financiero\n"
        }
        return MetricasApoyo.vacia(config: yaml, ficheros: ficheros)
    }

    func etapaFIN(_ c: MetricasApoyo.Carpeta) -> EtapaArea {
        EtapaCalculador(foto: FotoMetricas(snapshot: c.foto(), hoy: MetricasApoyo.dia("2026-10-19"))).area(.finanzas)
    }

    @Test("Ribera no declara nada: las seis áreas en la etapa 1 (el sistema no se cree lo que no declaras)")
    func ribera() {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let p = c.panel()
        #expect(p.etapas.map(\.etapa) == [1, 1, 1, 1, 1, 1])
        #expect(p.etapas.allSatisfy { $0.cobertura == 0 && $0.pctAuto == nil && $0.progreso == 1 })
        #expect(p.etapaEmpresa.etapa == 1)
        // A igualdad de etapa y cobertura, la más floja es la primera en el orden de las áreas.
        #expect(p.etapaEmpresa.masFloja == .direccion)
        #expect(p.etapaEmpresa.porque == "La empresa está en la etapa 1 porque la etapa es la del área más floja, Dirección: le faltan 7 funciones esenciales por encender.")
        #expect(p.etapaEmpresa.actual?.nombre == "Validación")
        #expect(p.etapaEmpresa.siguiente?.num == 2)
        let fin = p.etapa(.finanzas)!
        #expect(fin.paso.que == "Encender las 6 funciones esenciales que faltan")
        #expect(fin.faltanEtapas == 4)
        #expect(fin.sistemas.count == 4)
        #expect(fin.sistemas.allSatisfy { $0.estado == .falta })
        // Hacen falta ya los de la etapa 2 (Facturación y cobro, Control de caja); los de la 3 aún no.
        #expect(fin.sistemas.filter(\.haceFalta).map(\.sistema.codigo) == ["FIN-1", "FIN-2"])
    }

    @Test("Cobertura < 50 % → 1; < 100 % → 2; todo a mano → 3; automático sin dueño → 4; con dueño → 6; a medias → 5")
    func escalera() {
        // 2 de 6 esenciales: 33 % → etapa 1, a un tercio del camino a la 2 (1 + 33/50 = 1,66).
        do {
            let c = carpeta(["FIN-01": "", "FIN-02": ""])
            defer { c.limpiar() }
            let e = etapaFIN(c)
            #expect(e.cobertura == 33 && e.etapa == 1 && e.progreso == 1.66)
        }
        // 3 de 6: 50 % → etapa 2 justo al empezarla.
        do {
            let c = carpeta(["FIN-01": "", "FIN-02": "", "FIN-03": ""])
            defer { c.limpiar() }
            let e = etapaFIN(c)
            #expect(e.cobertura == 50 && e.etapa == 2 && e.progreso == 2)
        }
        // Las 6 esenciales, todas hechas por una persona: 0 % automático → etapa 3.
        do {
            let c = carpeta(Dictionary(uniqueKeysWithValues: Self.esencialesFIN.map { ($0, ", ejecutor: H") }))
            defer { c.limpiar() }
            let e = etapaFIN(c)
            #expect(e.cobertura == 100 && e.pctAuto == 0 && e.etapa == 3 && e.manuales == 6)
            #expect(e.paso.que == "Bajar de escalón 6 funciones que aún se hacen a mano")
            #expect(e.porque == "lo tiene escrito pero solo el 0 % funciona sin ti")
        }
        // Con su ejecutor recomendado (regla fija o automatización): 100 % automático, pero sin dueño → 4 (4,5).
        do {
            let c = carpeta(Dictionary(uniqueKeysWithValues: Self.esencialesFIN.map { ($0, "") }))
            defer { c.limpiar() }
            let e = etapaFIN(c)
            #expect(e.pctAuto == 100 && !e.tieneDueno && e.etapa == 4 && e.progreso == 4.5)
            #expect(e.sistemas.first { $0.sistema.codigo == "FIN-1" }?.estado == .montado)   // FIN-02, 03, 04 y 10
            #expect(e.sistemas.first { $0.sistema.codigo == "FIN-2" }?.estado == .aMedias)   // FIN-01 y 05, sin FIN-12
        }
        // Con dueño distinto de ti: 6.
        do {
            let c = carpeta(Dictionary(uniqueKeysWithValues: Self.esencialesFIN.map { ($0, "") }), ocupante: "Lucía Ferrer")
            defer { c.limpiar() }
            #expect(etapaFIN(c).etapa == 6)
        }
        // Tú no eres un dueño distinto de ti.
        do {
            let c = carpeta(Dictionary(uniqueKeysWithValues: Self.esencialesFIN.map { ($0, "") }), ocupante: "Manu")
            defer { c.limpiar() }
            #expect(etapaFIN(c).etapa == 4)
        }
        // Con dueño y la mitad a mano: 50 % automático → 5 (5 + (50 − 40)/40 = 5,25).
        do {
            var d = Dictionary(uniqueKeysWithValues: Self.esencialesFIN.map { ($0, "") })
            for x in ["FIN-01", "FIN-02", "FIN-03"] { d[x] = ", ejecutor: humano" }
            let c = carpeta(d, ocupante: "Lucía Ferrer")
            defer { c.limpiar() }
            let e = etapaFIN(c)
            #expect(e.pctAuto == 50 && e.etapa == 5 && e.progreso == 5.25)
        }
    }

    @Test("Una declaración con fecha posterior a hoy aún no cuenta")
    func declaradaDespues() {
        let c = carpeta(["FIN-01": ", desde: 2026-11-01", "FIN-02": ", desde: 2026-10-01", "FIN-03": ""])
        defer { c.limpiar() }
        let e = etapaFIN(c)
        #expect(e.esencialesOk == 2)
        #expect(e.cobertura == 33)
    }
}
