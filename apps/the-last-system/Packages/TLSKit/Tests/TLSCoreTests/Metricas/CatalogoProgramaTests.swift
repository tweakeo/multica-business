import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · el estándar de Programa dentro de la app")
struct CatalogoProgramaTests {
    let c = CatalogoPrograma.deSerie

    @Test("capacidades.yaml: 78 capacidades (37 esenciales, 30 recomendables, 11 opcionales) con su licencia Apache-2.0")
    func capacidades() throws {
        #expect(c.cargado)
        #expect(c.capacidades.count == 78)
        #expect(c.capacidades.filter { $0.nivel == .esencial }.count == 37)
        #expect(c.capacidades.filter { $0.nivel == .recomendable }.count == 30)
        #expect(c.capacidades.filter { $0.nivel == .opcional }.count == 11)
        // Esenciales por área (las que mueven la cobertura): DIR 7, VEN 7, ENT 6, FIN 6, MAR 4, EQU 7.
        let esenciales = Dictionary(grouping: c.capacidades.filter { $0.nivel == .esencial }, by: \.area).mapValues(\.count)
        #expect(esenciales == [.direccion: 7, .ventas: 7, .entrega: 6, .finanzas: 6, .marca: 4, .equipo: 7])
        // Los códigos son estables y no se repiten.
        #expect(Set(c.capacidades.map(\.codigo)).count == 78)
        let carpeta = try #require(RecursosPrograma.carpeta)
        let licencia = try String(contentsOf: carpeta.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(licencia.contains("Apache License"))
        #expect(licencia.contains("Version 2.0"))
        let yaml = try String(contentsOf: carpeta.appendingPathComponent("capacidades.yaml"), encoding: .utf8)
        #expect(yaml.contains("Licencia: Apache-2.0"))
    }

    @Test("Semillas: 6 áreas, 6 roles, 6 etapas con qué toca, 29 módulos y 7 rutinas")
    func semillas() {
        #expect(c.areas.map(\.codigo) == AreaCode.allCases)
        #expect(c.areas.first { $0.codigo == .finanzas }?.convierte == "Actividad en caja y margen")
        #expect(c.roles.count == 6)
        #expect(c.etapas.map(\.num) == [1, 2, 3, 4, 5, 6])
        #expect(c.etapa(5)?.verbo == "Delegar")
        #expect(c.etapa(1)?.queToca.isEmpty == false)
        #expect(c.etapa(6)?.senal == nil)
        #expect(c.modulos.count == 29)
        #expect(c.rutinas.count == 7)
    }

    @Test("Sistemas estándar: 24, cuatro por área, y cada capacidad que nombran existe")
    func sistemas() {
        #expect(c.sistemas.count == 24)
        for a in AreaCode.allCases { #expect(c.sistemas(de: a).count == 4) }
        let codigos = Set(c.capacidades.map(\.codigo))
        for s in c.sistemas {
            #expect(!s.capacidades.isEmpty)
            for cap in s.capacidades { #expect(codigos.contains(cap), "\(s.codigo) nombra \(cap), que no existe") }
            // Cada sistema solo lleva capacidades de su área.
            #expect(s.capacidades.allSatisfy { $0.hasPrefix(s.area.rawValue) })
        }
    }

    @Test("Catálogo de números: los 21 códigos de Metas.md de Ribera están, con área, unidad y fuentes")
    func catalogoNumeros() throws {
        let metas = try #require(MetasDocumento.leer(VaultSnapshot.read(root: MetricasApoyo.riberaRepo)))
        // Recuento real comprobado contra Metas.md de Ribera.
        #expect(metas.filas.count == 21)
        #expect(c.recuentoRibera == metas.filas.count)
        #expect(c.kpis.filter { $0.origen == "ribera" }.count == 21)
        for f in metas.filas {
            let k = try #require(c.kpi(f.codigo), "\(f.codigo) no está en kpi.json")
            #expect(k.origen == "ribera")
            #expect(!k.fuentes.isEmpty && !k.calculo.isEmpty)
            #expect(["n", "%", "€", "meses", "h", "USD"].contains(k.unidad))
            // El sentido del catálogo es el mismo que dice «Cómo se mide».
            if let s = metas.comoSeMide[f.codigo]?.sentido { #expect(s == k.sentido, "\(f.codigo)") }
        }
        // Los nuevos de la propuesta v2 también están.
        for codigo in ["DIR-DEC14", "VEN-STALE7", "BUZ-PEND", "FIN-FISCAL", "ENT-INC", "ENT-ARR48", "VEN-REF", "EQU-RUT"] {
            #expect(c.kpi(codigo)?.origen == "propuesta-v2")
        }
        #expect(c.kpis.count == 29)
        #expect(Set(c.kpis.map(\.codigo)).count == c.kpis.count)
    }

    @Test("Rangos de fechas sin pasar por horas: meses, trimestres y días entre fechas")
    func rangos() {
        let d = MetricasApoyo.dia
        #expect(RangoFechas.mes(de: d("2026-10-19")) == RangoFechas(desde: d("2026-10-01"), hasta: d("2026-10-31")))
        #expect(RangoFechas.mes(de: d("2028-02-10")).hasta == d("2028-02-29"))
        #expect(RangoFechas.trimestre(de: d("2026-10-19")) == RangoFechas(desde: d("2026-10-01"), hasta: d("2026-12-31")))
        #expect(RangoFechas.diasEntre(d("2026-10-01"), d("2026-12-31")) == 91)
        // Cruza el cambio de hora del 25 de octubre sin perder ni ganar un día.
        #expect(RangoFechas.diasEntre(d("2026-10-19"), d("2026-10-26")) == 7)
        #expect(PeriodoKPI.dias30.rango(hoy: d("2026-10-19")).dias == 30)
    }
}
