import Foundation
import Testing
@testable import TLSCore

@Suite("Métricas · Metas.md: leer la tabla y cambiar solo Meta y Alerta", .serialized)
struct MetasTests {
    @Test("Umbrales tal como se escriben: con unidad, con millares, con coma, sin cifra o vacíos")
    func umbrales() {
        #expect(Umbral(texto: "80 %").numero == 80)
        #expect(Umbral(texto: "1000 €").numero == 1000)
        #expect(Umbral(texto: "1.000 €").numero == 1000)
        #expect(Umbral(texto: "3 meses").numero == 3)
        #expect(Umbral(texto: "2,5 meses").numero == 2.5)
        #expect(Umbral(texto: "0").numero == 0)
        #expect(Umbral(texto: "0 €").numero == 0)
        #expect(Umbral(texto: "-5").numero == -5)
        // Sin cifra no hay umbral fijado (como en Programa: «Todos», «Con histórico propio»…).
        #expect(Umbral(texto: "Todos").numero == nil)
        #expect(Umbral(texto: "Por debajo de 3").numero == nil)
        #expect(!Umbral(texto: "").fijado && Umbral(texto: "").vacioDeTexto)
        let rango = Umbral(texto: "3–6")
        #expect(rango.numero == 3 && rango.maximo == 6)
    }

    @Test("La tabla de Ribera: 21 filas en su orden, umbrales y «Cómo se mide»")
    func leerRibera() throws {
        let metas = try #require(MetasDocumento.leer(VaultSnapshot.read(root: MetricasApoyo.riberaRepo)))
        #expect(metas.ruta == VaultPath("1 · Dirección/Metas.md"))
        #expect(metas.tieneTabla)
        #expect(metas.codigos.first == "DIR-APR" && metas.codigos.last == "VEN-WON")
        let runway = try #require(metas.fila("FIN-RUNWAY"))
        #expect(runway.indicador == "Meses de caja")
        #expect(runway.meta.numero == 3 && runway.alerta.numero == 2)
        let caja = try #require(metas.fila("fin-cash"))
        #expect(!caja.meta.fijado && caja.meta.vacioDeTexto)
        // Sin meta en Ribera: ENT-ACTIVE, EQU-COST, FIN-CASH, VEN-FCST y VEN-PIPE.
        #expect(metas.filas.filter { !$0.meta.fijado }.map(\.codigo) == ["ENT-ACTIVE", "EQU-COST", "FIN-CASH", "VEN-FCST", "VEN-PIPE"])
        #expect(metas.comoSeMide["DIR-APR"]?.sentido == .menos)
        #expect(metas.comoSeMide["VEN-WON"]?.sentido == .mas)
        #expect(metas.comoSeMide["ENT-ACTIVE"]?.sentido == .rango)
        #expect(metas.comoSeMide["FIN-RUNWAY"]?.periodo == "ahora")
    }

    @Test("Fijar meta y alerta cambia solo esa línea, con su unidad; deshacer deja los mismos bytes")
    func fijarYDeshacer() async throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let ruta = "1 · Dirección/Metas.md"
        let antes = try #require(c.datos(ruta))
        let metas = try #require(MetasDocumento.leer(c.foto()))
        let bus = try await c.bus()
        let r = try await MetasEscritor.fijar(codigo: "FIN-RUNWAY", meta: "4", alerta: "1,5", en: metas, bus: bus, autor: .persona("Manu"))
        #expect(r.hecho)
        let viejas = String(decoding: antes, as: UTF8.self).components(separatedBy: "\n")
        let nuevas = c.texto(ruta).components(separatedBy: "\n")
        #expect(viejas.count == nuevas.count)
        let distintas = zip(viejas, nuevas).filter { $0 != $1 }
        #expect(distintas.count == 1)
        #expect(distintas.first?.1 == "| FIN-RUNWAY | Meses de caja | 4 meses | 1,5 meses |  |")
        // La app lo vuelve a leer igual.
        let releidas = try #require(MetasDocumento.leer(c.foto()))
        #expect(releidas.fila("FIN-RUNWAY")?.meta.numero == 4)
        #expect(releidas.fila("FIN-RUNWAY")?.alerta.numero == 1.5)
        // Una fila sin meta: la celda vacía recibe la cifra (ENT-ACTIVE se cuenta en número de proyectos).
        try await MetasEscritor.fijar(codigo: "ENT-ACTIVE", meta: "3", alerta: "", en: releidas, bus: bus, autor: .persona("Manu"))
        #expect(c.texto(ruta).contains("| ENT-ACTIVE | Proyectos activos | 3 |  |  |"))
        _ = try await bus.deshacer(autor: .persona("Manu"))
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.datos(ruta) == antes)
    }

    @Test("Un asistente no fija metas; un código que no está o un valor sin cifra se rechazan sin tocar nada")
    func rechazos() async throws {
        let c = MetricasApoyo.ribera()
        defer { c.limpiar() }
        let ruta = "1 · Dirección/Metas.md"
        let antes = try #require(c.datos(ruta))
        let metas = try #require(MetasDocumento.leer(c.foto()))
        let bus = try await c.bus()
        await #expect(throws: MetasError.soloPersonas) {
            try await MetasEscritor.fijar(codigo: "FIN-RUNWAY", meta: "4", alerta: "2", en: metas, bus: bus, autor: .agente("mika"))
        }
        await #expect(throws: MetasError.codigoDesconocido("XXX-1")) {
            try await MetasEscritor.fijar(codigo: "XXX-1", meta: "4", alerta: "2", en: metas, bus: bus, autor: .persona("Manu"))
        }
        await #expect(throws: MetasError.valorNoValido("muchos")) {
            try await MetasEscritor.fijar(codigo: "FIN-RUNWAY", meta: "muchos", alerta: "2", en: metas, bus: bus, autor: .persona("Manu"))
        }
        #expect(c.datos(ruta) == antes)
        // La orden es solo de Meta y Alerta.
        if case .cambiarCeldas(_, _, let clave, let valor, let celdas) = try MetasEscritor.comando(metas, codigo: "VEN-WON", meta: "1 €", alerta: "") {
            #expect(clave == "Código" && valor == "VEN-WON")
            #expect(Set(celdas.keys) == ["Meta", "Alerta"])
        } else {
            Issue.record("La orden no es cambiarCeldas")
        }
    }

    @Test("Texto de un umbral con su unidad, sin millares para que se relea igual")
    func textoUmbral() {
        #expect(MetasEscritor.texto(6000, unidad: "€") == "6000 €")
        #expect(MetasEscritor.texto(80, unidad: "%") == "80 %")
        #expect(MetasEscritor.texto(1, unidad: "meses") == "1 mes")
        #expect(MetasEscritor.texto(2.5, unidad: "meses") == "2,5 meses")
        #expect(MetasEscritor.texto(3, unidad: "n") == "3")
        #expect(Umbral(texto: MetasEscritor.texto(12500, unidad: "€")).numero == 12500)
    }
}
