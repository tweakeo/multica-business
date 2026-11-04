import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// PLAN §4.5: los valores de serie de los asistentes en `.tls/config.yaml` (Mika activo y coordinador; el Contable si
/// Finanzas está activa; Comercial e Implementador solo si su área lo está; Marca y Equipo en reposo; Cartero
/// inactivo hasta Mail; Ordenador activo), que leen igual el motor y gobierno y que el Autorizador acepta.
@Suite("Asistentes de serie · config.yaml por defecto", .serialized)
struct ConfigDeSerieTests {
    static let todasActivas = Dictionary(uniqueKeysWithValues: AreaCode.allCases.map { ($0, AreaStatus.activa) })

    @Test("Quién queda activo según el estado de las áreas")
    func activos() {
        let todas = ConfigDeSerie.activos(estados: Self.todasActivas)
        #expect(todas == ["mika": true, "comercial": true, "implementador": true, "contable": true, "marca": false,
                          "equipo": false, "cartero": false, "ordenador": true])
        var est = Self.todasActivas
        est[.finanzas] = .preparada
        est[.ventas] = .reposo
        est[.entrega] = .desconocido
        let algunas = ConfigDeSerie.activos(estados: est)
        #expect(algunas["contable"] == false && algunas["comercial"] == false && algunas["implementador"] == false)
        #expect(algunas["mika"] == true && algunas["ordenador"] == true)
        #expect(ConfigDeSerie.activos(estados: Self.todasActivas, mailConectado: true)["cartero"] == true)
        // Ribera: Marca preparada y Equipo en reposo.
        let ribera = ConfigDeSerie.activos(estados: ApoyoRoles.estadosRibera)
        #expect(ribera.filter(\.value).keys.sorted() == ["comercial", "contable", "implementador", "mika", "ordenador"])
    }

    @Test("El motor lee lo mismo que dice el catálogo (rutinas incluidas)")
    func leeElMotor() throws {
        let yaml = ConfigDeSerie.completar("version: 1\nclase: copia\n", estados: Self.todasActivas)
        let a = AjustesDeAsistentes.leer(yaml: yaml)
        #expect(a.interruptor && a.pausaAreas.isEmpty && a.topeTarjetasDia == 5)
        #expect(a.agentes.count == 8)
        for p in PerfilDeAsistente.deSerie {
            let g = try #require(a.agente(p.slug), "\(p.slug)")
            #expect(g.activo == p.activoDeSerie(estados: Self.todasActivas))
            #expect(g.coordinador == p.coordinador)
            #expect(g.areas == (p.area.map { [$0] } ?? []))
            #expect(g.leeAreas == (p.leeTodas ? AreaCode.allCases : p.leeAreas))
            #expect(g.capacidades == p.capacidades)
            #expect(g.modelo == p.ajustes.modelo && g.esfuerzo == p.ajustes.esfuerzo)
            #expect(g.maxTareasPorEjecucion == 10 && g.presupuestoEjecucionUSD == 0.5 && g.presupuestoMesUSD == 15)
            // Las rutinas, iguales salvo la instrucción (que es del catálogo y no se copia a la configuración).
            let sinInstruccion = p.rutinas.map { r -> TLSAgents.RutinaDeAsistente in var x = r; x.instruccion = nil; return x }
            #expect(g.rutinas == sinInstruccion, "\(p.slug)")
        }
    }

    @Test("Gobierno lee lo mismo: buzón para los del sistema, todas para Mika y el Ordenador")
    func leeGobierno() throws {
        let yaml = ConfigDeSerie.completar("version: 1\n", estados: ApoyoRoles.estadosRibera)
        let c = ConfigAgentes.leer(yaml: yaml)
        #expect(!c.ilegible && c.encendido)
        #expect(c.avisos.topeTarjetasDia == 5 && c.avisos.topeNotificacionesNoRojasDia == 3)
        #expect(c.activos.map(\.slug) == ["comercial", "contable", "implementador", "mika", "ordenador"])
        let mika = try #require(c.asistente("mika"))
        #expect(mika.coordinador && mika.leeTodas && mika.areas == [.direccion] && mika.escribeEn(.ventas))
        let ordenador = try #require(c.asistente("ordenador"))
        #expect(ordenador.buzon && ordenador.areas.isEmpty && ordenador.leeTodas && !ordenador.escribeEn(.ventas))
        let cartero = try #require(c.asistente("cartero"))
        #expect(cartero.buzon && !cartero.activo && cartero.leeAreas == [.ventas, .finanzas])
        let contable = try #require(c.asistente("contable"))
        #expect(contable.areas == [.finanzas] && contable.leeEn(.ventas) && !contable.escribeEn(.ventas))
        #expect(contable.presupuestoMesUSD == 15 && contable.presupuestoEjecucionUSD == 0.5 && contable.maxTareasPorEjecucion == 10)
        #expect(contable.rutinas.map(\.id) == ["cobros-pendientes", "paquete-gestoria"])
        #expect(c.capacidades.isEmpty)   // las funciones declaradas son del paso 4, no de aquí
    }

    @Test("Completar nunca cambia lo que ya está y es idempotente")
    func completar() throws {
        let base = "# Mi configuración\nversion: 1\nid: 1234\nclase: copia\nprivado: []\ncapacidades:\n  FIN-05: {declarada: si, modo: supervisado, ejecutor: IA}\n"
        let una = ConfigDeSerie.completar(base, estados: Self.todasActivas)
        #expect(una.hasPrefix(base + "\n" + ConfigDeSerie.comentario + "\n"))
        #expect(ConfigDeSerie.completar(una, estados: Self.todasActivas) == una)
        // Si ya hay asistentes (aunque estén distintos), no se tocan; solo se añade lo que falte.
        let suya = "version: 1\ninterruptor: apagado\nagentes:\n  mika:\n    activo: false\n"
        let completada = ConfigDeSerie.completar(suya, estados: Self.todasActivas)
        #expect(completada.hasPrefix(suya))
        #expect(!completada.dropFirst(suya.count).contains("agentes:") && !completada.dropFirst(suya.count).contains("interruptor:"))
        #expect(completada.contains("pausa_areas: []") && completada.contains("avisos: {"))
        let leida = ConfigAgentes.leer(yaml: completada)
        #expect(leida.interruptor == .apagado && leida.asistente("mika")?.activo == false && leida.agentes.count == 1)
        // Sin fichero: solo lo de los asistentes.
        let vacia = ConfigDeSerie.completar("", estados: Self.todasActivas)
        #expect(vacia.hasPrefix(ConfigDeSerie.comentario) && ConfigAgentes.leer(yaml: vacia).agentes.count == 8)
        #expect(ConfigDeSerie.clavesDePrimerNivel(una).isSuperset(of: ["version", "id", "clase", "privado", "capacidades"] + ConfigDeSerie.claves))
    }

    @Test("Válida para el Autorizador: el suelo vale, lo externo pide aprobación y lo inactivo no trabaja")
    func autorizador() throws {
        let root = try ApoyoRoles.copiaDeRibera("autorizador")
        let estado = try ApoyoRoles.temporal("estado")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: estado) }
        let az = try Autorizador(root: root, stateDirectory: estado)
        #expect(!az.estadoDeConfig().cambiadaFuera)
        for slug in ["mika", "comercial", "implementador", "contable", "ordenador"] {
            #expect(az.puedeLanzar(slug).permitido, "\(slug): \(az.puedeLanzar(slug).motivo)")
        }
        for slug in ["marca", "equipo", "cartero"] { #expect(!az.puedeLanzar(slug).permitido, "\(slug)") }
        // Mika crea una tarea interna en cualquier área (suelo, coordinador).
        let t = SolicitudAutorizacion(autor: .agente("mika"), tipo: .tareaCrear,
                                      rutas: [VaultPath("2 · Ventas/Tareas/t-0009-preparar-la-llamada.md")])
        #expect(az.decidir(t).resultado == .permitido)
        // El Contable no escribe en Ventas, pero sí en Finanzas.
        let fuera = SolicitudAutorizacion(autor: .agente("contable"), tipo: .tareaCrear, rutas: [VaultPath("2 · Ventas/Tareas/t-0010-x.md")])
        #expect(az.decidir(fuera).resultado != .permitido)
        let dentro = SolicitudAutorizacion(autor: .agente("contable"), tipo: .conciliacionProponer,
                                           rutas: [VaultPath("4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv")])
        #expect(az.decidir(dentro).resultado == .permitido)
        // Enviar un correo: aprobación siempre.
        let enviar = SolicitudAutorizacion(autor: .agente("comercial"), tipo: .externa,
                                           rutas: [VaultPath("2 · Ventas/Borradores/seguimiento.md")], externa: .enviarCorreo)
        #expect(az.decidir(enviar).resultado == .requiereAprobacion)
        // Lo vetado sigue vetado con la configuración de serie.
        for tipo in [TipoDeAccion.config, .metasFijar, .capacidadDeclarar, .rolesEscribir, .venceMover, .tareaCerrar] {
            let s = SolicitudAutorizacion(autor: .agente("mika"), tipo: tipo, rutas: [VaultPath("1 · Dirección/Metas.md")])
            #expect(az.decidir(s).resultado == .denegado, "\(tipo)")
        }
        // .tls/ no existe para un asistente.
        #expect(az.decidirLectura(VaultPath(".tls/config.yaml"), asistente: "mika").resultado == .noEncontrado)
    }
}
