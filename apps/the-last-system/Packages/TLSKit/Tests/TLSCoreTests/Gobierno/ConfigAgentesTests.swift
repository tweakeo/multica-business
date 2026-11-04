import Foundation
import Testing
@testable import TLSCore

/// `config.yaml` de los asistentes: lectura, escritura solo como persona y configuración confirmada por SHA-256.
@Suite("Gobierno · configuración de los asistentes", .serialized)
struct ConfigAgentesTests {
    static let manu = Autor.persona("Manu")

    @Test("Lee agentes, interruptor, pausas, funciones (declarada ≠ modo) y avisos")
    func lectura() {
        let c = ConfigAgentes.leer(yaml: EntornoGobierno.config)
        #expect(c.encendido && c.pausaAreas.isEmpty)
        let mika = try! #require(c.asistente("mika"))
        #expect(mika.activo && mika.coordinador && mika.leeTodas && mika.areas == [.direccion])
        let com = try! #require(c.asistente("agente:Comercial"))
        #expect(com.maxTareasPorEjecucion == 2 && com.leeAreas == [.direccion] && com.capacidades.contains("VEN-08"))
        #expect(c.asistente("equipo")?.activo == false)
        #expect(c.modo("ven-02") == .supervisado && c.capacidades["VEN-02"]?.declarada == true)
        #expect(c.modo("VEN-09") == .manual && c.capacidades["VEN-09"]?.declarada == false, "modo sin declarar")
        #expect(c.avisos.topeTarjetasDia == 5 && c.avisos.topeNotificacionesNoRojasDia == 3)
        // Formato del PLAN §4.5 (con `…` en la lista de funciones y una rutina).
        let plan = ConfigAgentes.leer(yaml: """
            interruptor: encendido
            agentes:
              mika:
                activo: true
                coordinador: true
                areas: [direccion]
                lee_areas: [todas]
                capacidades: [DIR-02, DIR-05, …]
                modelo: sonnet
                presupuesto_ejecucion_usd: 0.5
                rutinas:
                  - {id: algo-rojo, nombre: "¿Algo rojo?", dias: [lun,mar,mie,jue,vie], hora: "08:45", ventana_perdida_h: 6, activa: true}
            """)
        let m = try! #require(plan.asistente("mika"))
        #expect(m.capacidades == ["DIR-02", "DIR-05"] && m.presupuestoEjecucionUSD == 0.5 && m.modelo == "sonnet")
        #expect(m.rutinas.first?.hora == "08:45" && m.rutinas.first?.dias.count == 5)
        // Lo que no se entiende: nadie trabaja.
        let rota = ConfigAgentes.leer(yaml: "agentes: [\n  - :")
        #expect(rota.ilegible && !rota.encendido && rota.agentes.isEmpty)
    }

    @Test("Escribir la entrada de un asistente: solo una persona, solo su bloque; queda confirmado")
    func escribirComoPersona() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        _ = a.estadoDeConfig()
        var equipo = try #require(a.estadoDeConfig().efectiva.asistente("equipo"))
        equipo.activo = true
        equipo.presupuestoMesUSD = 15
        #expect(throws: ErrorDeGobierno.soloPersonas) { try EditorConfigAgentes.plan(poner: equipo, root: e.root, autor: .agente("mika")) }
        let antes = e.texto(".tls/config.yaml")!
        let plan = try EditorConfigAgentes.plan(poner: equipo, root: e.root, autor: Self.manu)
        #expect(try await bus.ejecutar(plan).hecho)
        let despues = e.texto(".tls/config.yaml")!
        #expect(despues.hasPrefix(antes.components(separatedBy: "  equipo:")[0]), "lo de antes, byte a byte")
        #expect(despues.hasSuffix("avisos: {tope_tarjetas_dia: 5, tope_notificaciones_no_rojas_dia: 3}\n"))
        let estado = a.estadoDeConfig()
        #expect(!estado.cambiadaFuera, "lo escribió la app: confirmado")
        #expect(estado.efectiva.asistente("equipo")?.activo == true && estado.efectiva.asistente("equipo")?.presupuestoMesUSD == 15)
        #expect(try a.estado.configConfirmada()?.por == "Manu")
        // Interruptor, pausas y modos.
        _ = try await bus.ejecutar(try EditorConfigAgentes.plan(pausaAreas: [.ventas, .marca], root: e.root, autor: Self.manu))
        _ = try await bus.ejecutar(try EditorConfigAgentes.plan(modo: .autonomo, capacidad: "ven-03", root: e.root, autor: Self.manu))
        _ = try await bus.ejecutar(try EditorConfigAgentes.plan(modo: .supervisado, capacidad: "MAR-08", root: e.root, autor: Self.manu))
        _ = try await bus.ejecutar(try EditorConfigAgentes.plan(interruptor: .apagado, root: e.root, autor: Self.manu))
        let c = a.estadoDeConfig()
        #expect(!c.cambiadaFuera)
        #expect(Set(c.efectiva.pausaAreas) == [.ventas, .marca] && !c.efectiva.encendido)
        #expect(c.efectiva.modo("VEN-03") == .autonomo && c.efectiva.capacidades["VEN-03"]?.declarada == true, "declarada no cambia")
        #expect(c.efectiva.modo("MAR-08") == .supervisado)
        // Un asistente no la escribe por el bus.
        await esperaDenegado(paso: 3) {
            try await bus.ejecutar(.crear(VaultPath(".tls/config.yaml"), texto: "x"), autor: .agente("mika"))
        }
    }

    @Test("Cambiar los permisos fuera de la app: siguen los confirmados y sale la tarjeta; lo que restringe vale ya")
    func cambiadaFuera() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        #expect(!a.estadoDeConfig().cambiadaFuera, "la primera lectura queda confirmada")
        let original = e.texto(".tls/config.yaml")!
        // En Obsidian: se activa Equipo y se sube el tope de Comercial.
        e.escribir(".tls/config.yaml", original
            .replacingOccurrences(of: "  equipo:\n    activo: false", with: "  equipo:\n    activo: true")
            .replacingOccurrences(of: "max_tareas_por_ejecucion: 2", with: "max_tareas_por_ejecucion: 50"))
        let c = a.estadoDeConfig()
        #expect(c.cambiadaFuera && Set(c.asistentesCambiados) == ["equipo", "comercial"])
        #expect(c.tituloTarjeta == "Cambiaron los permisos de Comercial y Equipo fuera de la app: confirmar")
        #expect(c.efectiva.asistente("equipo")?.activo == false, "sigue la confirmada")
        #expect(c.efectiva.asistente("comercial")?.maxTareasPorEjecucion == 2)
        #expect(a.decidir(.de("equipo", .leer, ["6 · Equipo/Área.md"])).paso == 6)
        // La tarjeta, en Decisiones › Para aprobar.
        let lectura = LecturaDominio(snapshot: e.foto())
        let bandeja = BandejaDeDecisiones.consultar(lectura, persona: "Manu", gobierno: .de(a), estado: a.estado)
        let t = try #require(bandeja.visibles.first { $0.gobierno?.clase == .cambioDePermisos })
        #expect(t.titulo == c.tituloTarjeta && t.grupoF4 == "Para aprobar" && t.opciones.map(\.texto) == ["Confirmar los cambios", "Volver a los de antes"])
        // Un asistente no confirma.
        #expect(throws: ErrorDeGobierno.soloPersonas) { try DecisionesDeGobierno.confirmarPermisos(a, autor: .agente("mika")) }
        // Lo que restringe vale sin confirmar.
        let conRestriccion = e.texto(".tls/config.yaml")!.replacingOccurrences(of: "pausa_areas: []", with: "pausa_areas: [ventas]")
        e.escribir(".tls/config.yaml", conRestriccion)
        #expect(a.estadoDeConfig().efectiva.enPausa(.ventas))
        // «Volver a los de antes».
        _ = try await DecisionesDeGobierno.volverALosDeAntes(a, bus: bus, autor: Self.manu)
        #expect(e.texto(".tls/config.yaml") == original)
        #expect(!a.estadoDeConfig().cambiadaFuera)
        // Otra vez fuera, y ahora se confirma.
        e.escribir(".tls/config.yaml", conRestriccion)
        try DecisionesDeGobierno.confirmarPermisos(a, autor: Self.manu)
        let d = a.estadoDeConfig()
        #expect(!d.cambiadaFuera && d.efectiva.asistente("equipo")?.activo == true && d.efectiva.asistente("comercial")?.maxTareasPorEjecucion == 50)
        #expect(a.puedeLanzar("equipo").paso == 6, "pero su área está en reposo")
    }

    @Test("Si hay cambios de fuera sin confirmar, un cambio desde la app no los confirma de paso")
    func cambioDeLaAppConPendientes() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        _ = a.estadoDeConfig()
        e.escribir(".tls/config.yaml", e.texto(".tls/config.yaml")!.replacingOccurrences(of: "  equipo:\n    activo: false",
                                                                                       with: "  equipo:\n    activo: true"))
        #expect(a.estadoDeConfig().asistentesCambiados == ["equipo"])
        // Con el bus a secas, el fichero cambia pero no queda confirmado (sigue la tarjeta).
        _ = try await bus.ejecutar(try EditorConfigAgentes.plan(pausaAreas: [.marca], root: e.root, autor: Self.manu))
        #expect(a.estadoDeConfig().asistentesCambiados == ["equipo"])
        // Con `aplicar`, lo que cambias tú queda confirmado; lo de fuera, no.
        try await EditorConfigAgentes.aplicar(.interruptor(.apagado), bus: bus, autor: Self.manu)
        let c = a.estadoDeConfig()
        #expect(c.cambios == ["pausa", "agente:equipo"], "la pausa que puse por el bus a secas y lo de fuera")
        #expect(c.confirmada.interruptor == .apagado && c.efectiva.asistente("equipo")?.activo == false)
        await esperaGobierno(.soloPersonas) { try await EditorConfigAgentes.aplicar(.interruptor(.encendido), bus: bus, autor: .agente("mika")) }
        // Sin pendientes, `aplicar` deja todo confirmado.
        try DecisionesDeGobierno.confirmarPermisos(a, autor: Self.manu)
        try await EditorConfigAgentes.aplicar(.modo(.manual, capacidad: "VEN-08"), bus: bus, autor: Self.manu)
        #expect(!a.estadoDeConfig().cambiadaFuera && a.estadoDeConfig().efectiva.modo("VEN-08") == .manual)
    }

    @Test("Un cambio fuera que no toca a los asistentes se acepta solo; uno ilegible no cambia nada")
    func cambiosSinPermisos() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        _ = a.estadoDeConfig()
        let original = e.texto(".tls/config.yaml")!
        e.escribir(".tls/config.yaml", original.replacingOccurrences(of: "hoy: 2026-10-19", with: "hoy: 2026-10-20"))
        #expect(!a.estadoDeConfig().cambiadaFuera)
        #expect(try a.estado.configConfirmada()?.por == "sin cambios de permisos")
        e.escribir(".tls/config.yaml", "agentes: [\n  - :")
        let c = a.estadoDeConfig()
        #expect(c.ilegible && c.cambiadaFuera && c.efectiva.asistente("mika")?.activo == true, "sigue con la confirmada")
        #expect(throws: ErrorDeGobierno.configIlegible) { try a.config.confirmar(por: .persona("Manu")) }
    }

    @Test("Lo más restrictivo de dos configuraciones")
    func masRestrictiva() {
        let a = ConfigAgentes.leer(yaml: EntornoGobierno.config)
        var b = a
        b.interruptor = .apagado
        b.agentes["comercial"]?.areas = [.ventas, .marca]
        b.agentes["comercial"]?.maxTareasPorEjecucion = 1
        b.capacidades["VEN-08"] = CapacidadConfigurada(codigo: "VEN-08", modo: .asistido)
        b.privado = ["4 · Finanzas/Nóminas"]
        let c = ConfigAgentes.masRestrictiva(a, b)
        #expect(!c.encendido && c.privado == ["4 · Finanzas/Nóminas"])
        #expect(c.asistente("comercial")?.areas == [.ventas] && c.asistente("comercial")?.maxTareasPorEjecucion == 1)
        #expect(c.modo("VEN-08") == .asistido)
    }
}
