import Foundation
import Testing
@testable import TLSCore

/// Criterio F3-2: la ruta de la copia de G3 tiene 15 pantallas o menos; la de empresa nueva, 40 o menos. Se cuentan
/// recorriendo el motor de verdad (cada pantalla que se ve, una vez), con el peor caso para la empresa nueva (las seis
/// áreas activas y todo contestado).
@Suite("Puesta en marcha · rutas y tope de pantallas")
struct RutasPuestaTests {
    @Test("Copia de G3 (fixture): 15 pantallas o menos, casi todo premarcado y unos 25 minutos")
    func copiaDeG3() async throws {
        let env = PuestaApoyo.g3()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        let ctx = PuestaApoyo.contexto(env, entrada: PuestaApoyo.entradaG3(env))
        #expect(ctx.organizada)
        var m = PuestaApoyo.motor(ctx, asup: asup)
        #expect(m.ruta == .copiaG3)
        // Por pregunta (lo que hay en blanco cuenta más que lo premarcado): unos 25 minutos.
        #expect((15...30).contains(m.quedanMinutos), "Quedan ~\(m.quedanMinutos) min al empezar")
        // Lo premarcado sale con su origen.
        let estadoDir = try #require(m.pregunta(.estadoArea(.direccion))?.premarcada)
        #expect(estadoDir.valor == .opcion("activa"))
        #expect(estadoDir.origen.texto == "Lo saqué de Área.md")
        #expect(m.pregunta(.estadoArea(.marca))?.premarcada?.valor == .opcion("en reposo"))
        #expect(m.pregunta(.sistema("VE2"))?.premarcada?.valor == .opcion("montado"))
        let vistas = try await PuestaApoyo.recorrer(&m) { m, paso in PuestaApoyo.aplicarSinEscribir(&m, paso) }
        #expect(vistas.count <= 15, "La copia de G3 tiene \(vistas.count) pantallas: \(vistas.map(\.id))")
        #expect(vistas.count >= 10)
        #expect(m.estado.terminada)
        // Pasa por los nueve pasos (0 a 8), con el 0b dentro del 0.
        #expect(Set(vistas.map(\.paso)) == Set(PasoPuesta.allCases))
        #expect(m.progreso.total == 9)
    }

    @Test("Copia de Ribera: también 15 pantallas o menos")
    func copiaDeRibera() async throws {
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        #expect(m.ruta == .copiaG3)
        let vistas = try await PuestaApoyo.recorrer(&m) { m, paso in PuestaApoyo.aplicarSinEscribir(&m, paso) }
        #expect(vistas.count <= 15, "\(vistas.count): \(vistas.map(\.id))")
    }

    @Test("Empresa nueva, peor caso (todo y las seis áreas activas): 40 pantallas o menos")
    func empresaNueva() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), asup: asup)
        #expect(m.ruta == .empresaNueva)
        var minutos: [Int] = []
        let vistas = try await PuestaApoyo.recorrer(&m) { m, paso in
            minutos.append(m.quedanMinutos)
            PuestaApoyo.aplicarSinEscribir(&m, paso)
        }
        #expect(vistas.count <= 40, "La empresa nueva tiene \(vistas.count) pantallas")
        #expect(vistas.count >= 25)
        #expect(!vistas.contains { $0.paso == .ordenar }, "Sin carpeta no hay nada que ordenar")
        // «Quedan ~N min» solo baja.
        #expect(minutos == minutos.sorted(by: >))
        // Cada paso, en 2–3 líneas: ninguna explicación pasa de 3 frases.
        for p in vistas {
            #expect(p.explicacion.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count <= 3,
                    "Explicación larga en \(p.id)")
            #expect(p.explicacion.count <= 260, "Explicación de más de tres líneas en \(p.id)")
        }
        // El texto libre va en su propia pantalla.
        for p in vistas where p.preguntas.contains(.destino) { #expect(p.tipo == .textoLibre && p.preguntas.count == 1) }
        // Por paso, como dice la tabla: S1 unas 9-10, Organizar ≤ 8, Qué funciona sin ti ≤ 6, números ≤ 4.
        let porPaso = Dictionary(grouping: vistas, by: \.paso).mapValues(\.count)
        #expect((porPaso[.organizar] ?? 0) <= 8)
        #expect((porPaso[.sinTi] ?? 0) <= 6)
        #expect((porPaso[.numeros] ?? 0) <= 4)
        #expect((porPaso[.bienvenida] ?? 0) <= 3)
        #expect((porPaso[.diaADia] ?? 0) <= 2)
    }

    @Test("Carpeta por ordenar, peor caso: 40 pantallas o menos (con las 7 de ordenar)")
    func carpetaPorOrdenar() async throws {
        let env = EntornoCarpeta(vacia: false)
        env.escribir("Clientes/Panadería.md", "# Panadería\n")
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        let ctx = PuestaApoyo.contexto(env)
        #expect(!ctx.organizada)
        var m = PuestaApoyo.motor(ctx, asup: asup)
        #expect(m.ruta == .carpetaPorOrdenar)
        let vistas = try await PuestaApoyo.recorrer(&m, raiz: env.root) { m, paso in PuestaApoyo.aplicarSinEscribir(&m, paso) }
        #expect(vistas.count <= 40, "\(vistas.count)")
        #expect(vistas.filter { $0.paso == .ordenar }.count == 7)
    }

    @Test("Ver un ejemplo: una pantalla y a Hoy; Ribera llega con la puesta en marcha hecha")
    func verUnEjemplo() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), asup: asup)
        await m.responder(.como, .opcion("ejemplo"))
        #expect(m.ruta == .ejemplo)
        #expect(m.pantallas.count == 1)
        #expect(m.quedanMinutos <= 2)
        let fin = m.siguiente()
        #expect(fin == .terminada)
        // El ejemplo, completado y para repasar.
        let env = PuestaApoyo.ribera()
        defer { env.limpiar() }
        var demo = env.entry
        demo.clase = .demo
        let ctx = PuestaApoyo.contexto(env, entrada: demo)
        let id = UUID()
        let e = OnboardingEngine.ejemploCompletado(contexto: ctx, vaultID: id, almacen: AlmacenPuesta(vaultID: id, appSupport: asup))
        #expect(e.estado.terminada)
        #expect(PasoPuesta.allCases.allSatisfy { e.estado.paso($0).fase == .aplicado })
        #expect(e.pantallas.count > 5, "Se puede repasar paso a paso")
        #expect(e.estado.respuesta(.etapa(.ventas))?.valor == .escala(1), "La etapa que calcula la app, confirmada")
        #expect(PuertaPuestaEnMarcha.avisoDeHoy(vaultID: id, appSupport: asup) == nil, "Terminada: Hoy no la recuerda")
    }

    @Test("El alcance decide cuántos pasos siguen")
    func alcance() async {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(), asup: asup)
        await m.responder(.como, .opcion("cero"))
        let todo = m.pasosIncluidos
        #expect(todo == [.bienvenida, .alcance, .conocer, .organizar, .sinTi, .diaADia, .numeros, .conectar, .recorrido])
        let pantallasTodo = m.pantallas.count
        await m.responder(.alcance, .opcion("area"))
        await m.responder(.alcanceArea, .opcion("VEN"))
        #expect(m.areasDelAlcance == [.ventas])
        #expect(m.pantallas.count < pantallasTodo)
        #expect(m.pantallas(de: .conocer).filter { $0.id.hasPrefix("conocer.area.") }.map(\.id) == ["conocer.area.VEN"])
        await m.responder(.alcance, .opcion("proceso"))
        await m.responder(.alcanceProceso, .opcion("FIN-1"))
        #expect(!m.pasosIncluidos.contains(.conocer))
        #expect(m.sistemasSinTi.map(\.codigo) == ["FI1"])   // el de Organizar que cubre FIN-1
        #expect(m.pantallas.count < 12)
    }

    @Test("«Paso N de M»: Organizar es el paso 4 de 9 en una copia")
    func progreso() async throws {
        let env = PuestaApoyo.g3()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env, entrada: PuestaApoyo.entradaG3(env)), asup: asup)
        m.ir(a: "organizar.resumen")
        #expect(m.progreso.numero == 4)
        #expect(m.progreso.total == 9)
        #expect(m.progreso.texto == "Seguir con la puesta en marcha · paso 4 de 9")
        #expect(m.progreso.textoMinutos.hasPrefix("Quedan ~"))
    }
}
