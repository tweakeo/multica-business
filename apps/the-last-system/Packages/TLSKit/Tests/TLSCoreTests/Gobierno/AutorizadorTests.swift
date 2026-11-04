import Foundation
import Testing
@testable import TLSCore

/// Los 12 pasos del Autorizador (PLAN §5.2), en su orden, y su auditoría.
@Suite("Gobierno · Autorizador", .serialized)
struct AutorizadorTests {
    @Test("1 · Sin escritor, solo lectura (y queda apuntado); leer sigue permitido")
    func sinEscritor() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador(hayEscritor: false)
        let d = a.decidir(.de("comercial", .comentar, [EntornoGobierno.tareaPath.raw]))
        #expect(d.resultado == .soloLectura && d.paso == 1)
        let p = a.decidir(SolicitudAutorizacion(autor: .persona("Manu"), tipo: .fichaEditar, rutas: [EntornoGobierno.tareaPath]))
        #expect(p.resultado == .soloLectura && p.paso == 1)
        #expect(a.decidir(.de("comercial", .leer, [EntornoGobierno.tareaPath.raw])).permitido)
        let apuntes = try a.estado.auditoria()
        #expect(apuntes.filter { $0.decision == "solo_lectura" }.count == 2)
    }

    @Test("2 y 4 · Una persona y la app pueden; la app nunca hace una acción externa")
    func personaYSistema() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        let p = a.decidir(SolicitudAutorizacion(autor: .persona("Manu"), tipo: .metasFijar, rutas: [VaultPath("1 · Dirección/Metas.md")]))
        #expect(p.permitido && p.paso == 2)
        let s = a.decidir(SolicitudAutorizacion(autor: .sistema, tipo: .tareaCrear, rutas: [VaultPath("2 · Ventas/Tareas/t-0002-x.md")]))
        #expect(s.permitido && s.paso == 4)
        let x = a.decidir(SolicitudAutorizacion(autor: .sistema, tipo: .externa, rutas: [], externa: .enviarCorreo))
        #expect(x.resultado == .denegado && x.paso == 4)
    }

    @Test("3 · Con el interruptor apagado, ningún asistente hace nada (ni leer) y no se lanza")
    func interruptor() throws {
        let e = EntornoGobierno(config: EntornoGobierno.config.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado"))
        defer { e.limpiar() }
        let a = try e.autorizador()
        for t in [TipoDeAccion.leer, .comentar, .tareaCrear] {
            let d = a.decidir(.de("comercial", t, [EntornoGobierno.tareaPath.raw]))
            #expect(d.resultado == .denegado && d.paso == 3, "\(t)")
        }
        #expect(a.puedeLanzar("mika").paso == 3)
        #expect(!a.puedeLanzar("mika").permitido)
        // Una persona sigue pudiendo.
        #expect(a.decidir(SolicitudAutorizacion(autor: .persona("Manu"), tipo: .comentar, rutas: [EntornoGobierno.tareaPath])).permitido)
    }

    @Test("5 · Vetos: ajustes, funciones, metas, aprobaciones, roles, AGENTS.md, Empresa.md, vence y cerrar tareas")
    func vetos() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        let tipos: [TipoDeAccion] = [.config, .capacidadDeclarar, .metasFijar, .aprobacionDecidir, .venceMover, .tareaCerrar,
                                     .oportunidadGanar, .cobroConfirmar, .conciliacionConfirmar]
        for t in tipos {
            let d = a.decidir(.de("mika", t, [EntornoGobierno.tareaPath.raw]))
            #expect(d.resultado == .denegado && d.paso == 5, "\(t)")
        }
        for r in [".tls/config.yaml", ".tls/layout.json", "6 · Equipo/Roles/comercial.md", "AGENTS.md", "Empresa.md", "1 · Dirección/Metas.md"] {
            let d = a.decidir(.de("mika", .fichaEditar, [r]))
            #expect(d.resultado == .denegado && d.paso == 5, "\(r)")
        }
        // Leer `.tls/` no es un veto: es «no encontrado».
        #expect(a.decidir(.de("mika", .leer, [".tls/config.yaml"])).resultado == .noEncontrado)
    }

    @Test("6 · Activo en la configuración confirmada y su área trabajando (ni en pausa, ni preparada, ni en reposo)")
    func rolYArea() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        let inactivo = a.decidir(.de("equipo", .leer, ["6 · Equipo/Área.md"]))
        #expect(inactivo.resultado == .denegado && inactivo.paso == 6)
        #expect(a.decidir(.de("desconocido", .leer, ["Empresa.md"])).paso == 6)
        let preparada = a.decidir(.de("implementador", .comentar, ["3 · Entrega/Tareas/t-0009-kit.md"]))
        #expect(preparada.resultado == .denegado && preparada.paso == 6)
        let reposo = a.decidir(.de("marca", .tareaCrear, ["5 · Marca/Tareas/t-0009-pieza.md"]))
        #expect(reposo.resultado == .denegado && reposo.paso == 6)
        #expect(!a.puedeLanzar("implementador").permitido && !a.puedeLanzar("marca").permitido)
        #expect(a.puedeLanzar("comercial").permitido)
        // La coordinadora no escribe en un área preparada (aunque su alcance sea todo).
        let enEntrega = a.decidir(.de("mika", .tareaCrear, ["3 · Entrega/Tareas/t-0010-x.md"]))
        #expect(enEntrega.resultado == .denegado && enEntrega.paso == 6)
        // La Bitácora (Equipo en reposo) se escribe igual: es de los asistentes.
        #expect(a.decidir(.de("comercial", .bitacoraRegistrar, ["6 · Equipo/Bitácora/2026-10.md"])).permitido)

        // Área en pausa.
        let pausa = EntornoGobierno(config: EntornoGobierno.config.replacingOccurrences(of: "pausa_areas: []", with: "pausa_areas: [ventas]"))
        defer { pausa.limpiar() }
        let b = try pausa.autorizador()
        let d = b.decidir(.de("comercial", .comentar, [EntornoGobierno.tareaPath.raw]))
        #expect(d.resultado == .denegado && d.paso == 6 && d.motivo.contains("pausa"))
        #expect(!b.puedeLanzar("comercial").permitido)
    }

    @Test("7 · Alcance: escribe en su área y en sus tareas; lee lo suyo y lee_areas; la coordinadora, todo")
    func alcance() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        e.escribir("1 · Dirección/Tareas/t-0003-asignada.md", "---\ntls_type: task\nresponsable: agente:comercial\nestado: Por hacer\n---\n# T\n\n## Actividad\n")
        let a = try e.autorizador()
        let fuera = a.decidir(.de("comercial", .tareaCrear, ["4 · Finanzas/Tareas/t-0004-x.md"]))
        #expect(fuera.resultado == .denegado && fuera.paso == 7)
        #expect(a.decidir(.de("comercial", .leer, ["4 · Finanzas/Área.md"])).paso == 7)
        #expect(a.decidir(.de("comercial", .leer, ["1 · Dirección/Área.md"])).permitido, "lee_areas")
        #expect(!a.decidir(.de("comercial", .tareaCrear, ["1 · Dirección/Tareas/t-0005-x.md"])).permitido, "leer no es escribir")
        #expect(a.decidir(.de("comercial", .comentar, ["1 · Dirección/Tareas/t-0003-asignada.md"])).permitido, "su tarea")
        #expect(a.decidir(.de("mika", .leer, ["4 · Finanzas/Área.md"])).permitido, "la coordinadora lee todo")
        #expect(!a.decidir(.de("comercial", .buzonMover, ["Buzón/Correspondencia.md"])).permitido, "el Buzón no es suyo")
    }

    @Test("8 · Lo privado, `.tls/`, los secretos, `..` y los enlaces que salen: «no encontrado», con auditoría")
    func privado() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        e.escribir("4 · Finanzas/secrets.env", "X=1\n")
        try FileManager.default.createSymbolicLink(at: e.url("4 · Finanzas/fuera"), withDestinationURL: e.base)
        let a = try e.autorizador()
        for (slug, r) in [("contable", EntornoGobierno.privada.raw), ("contable", "4 · Finanzas/privado/expediente privado.md"),
                          ("contable", "4 · Finanzas/Privado"), ("comercial", EntornoGobierno.privada.raw),
                          ("mika", EntornoGobierno.privada.raw), ("mika", ".tls/config.yaml"), ("contable", "4 · Finanzas/secrets.env"),
                          ("contable", "4 · Finanzas/../Empresa.md"), ("contable", "4 · Finanzas/fuera/estado/estado.sqlite")] {
            let d = a.decidir(.de(slug, .leer, [r]))
            #expect(d.resultado == .noEncontrado && d.paso == 8, "\(slug) \(r): \(d.motivo)")
            #expect(d.respuestaParaAsistente == "no encontrado")
        }
        // Escribir lo privado: también «no encontrado».
        #expect(a.decidir(.de("contable", .comentar, [EntornoGobierno.privada.raw])).resultado == .noEncontrado)
        // En NFD también.
        let nfd = EntornoGobierno.privada.raw.decomposedStringWithCanonicalMapping
        #expect(a.decidir(.de("contable", .leer, [nfd])).resultado == .noEncontrado)
        let apuntes = try a.estado.auditoria().filter { $0.decision == "no_encontrado" }
        #expect(apuntes.count >= 11)
        #expect(apuntes.allSatisfy { $0.paso == 8 })
        // Filtro de listas.
        let visibles = a.visibles([VaultPath("4 · Finanzas/Área.md"), EntornoGobierno.privada], asistente: "contable")
        #expect(visibles == [VaultPath("4 · Finanzas/Área.md")])
    }

    @Test("8 · Lo privado de los ajustes de la app y lo confirmado también cuentan (aunque lo quiten fuera)")
    func privadoDeAjustesYConfirmado() throws {
        let e = EntornoGobierno(config: EntornoGobierno.config.replacingOccurrences(of: "privado: []", with: "privado:\n  - \"2 · Ventas/Expedientes\""))
        defer { e.limpiar() }
        let a = try Autorizador(root: e.root, stateDirectory: e.state, opciones: .init(privado: [VaultPath("2 · Ventas/Contactos")]))
        #expect(a.decidir(.de("comercial", .leer, ["2 · Ventas/Contactos/persona.md"])).resultado == .noEncontrado)
        #expect(a.decidir(.de("comercial", .leer, ["2 · Ventas/Expedientes/x.md"])).resultado == .noEncontrado)
        _ = a.estadoDeConfig()
        // Alguien lo quita fuera de la app: sigue privado (lo confirmado se une).
        e.escribir(".tls/config.yaml", e.texto(".tls/config.yaml")!.replacingOccurrences(of: "privado:\n  - \"2 · Ventas/Expedientes\"", with: "privado: []"))
        #expect(a.decidir(.de("comercial", .leer, ["2 · Ventas/Expedientes/x.md"])).resultado == .noEncontrado)
        #expect(a.decidir(.de("comercial", .leer, ["2 · Ventas/Área.md"])).permitido)
    }

    @Test("9 · Topes: tareas por ejecución, delegación hasta 2 y tamaño")
    func topes() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        for n in 2...3 {
            #expect(a.decidir(.de("comercial", .tareaCrear, ["2 · Ventas/Tareas/t-000\(n)-x.md"], ejecucion: "r-1")).permitido)
        }
        let tercera = a.decidir(.de("comercial", .tareaCrear, ["2 · Ventas/Tareas/t-0004-x.md"], ejecucion: "r-1"))
        #expect(tercera.resultado == .denegado && tercera.paso == 9)
        #expect(a.decidir(.de("comercial", .tareaCrear, ["2 · Ventas/Tareas/t-0004-x.md"], ejecucion: "r-2")).permitido,
                "el tope es por ejecución")
        #expect(a.decidir(.de("comercial", .delegar)).paso == 9, "solo la coordinadora delega")
        #expect(a.decidir(.de("mika", .delegar, profundidad: 2)).permitido)
        #expect(a.decidir(.de("mika", .delegar, profundidad: 3)).paso == 9)
        let grande = a.decidir(.de("comercial", .comentar, [EntornoGobierno.tareaPath.raw], tamano: PermisoBase.tamanoMaximo + 1))
        #expect(grande.resultado == .denegado && grande.paso == 9)
    }

    @Test("10 · Lo que sale de la empresa pide aprobación siempre, también en modo autónomo; con la función apagada, no")
    func externas() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        for x in AccionExterna.allCases {
            let d = a.decidir(.de("comercial", .externa, ["2 · Ventas/Borradores/b.md"], capacidad: "VEN-08", externa: x))
            #expect(d.resultado == .requiereAprobacion && d.paso == 10, "\(x)")
            #expect(d.respuestaParaAsistente == "aprobación requerida")
        }
        let apagada = a.decidir(.de("comercial", .externa, ["2 · Ventas/Borradores/b.md"], capacidad: "VEN-11", externa: .enviarCorreo))
        #expect(apagada.resultado == .denegado && apagada.paso == 10)
    }

    @Test("11 · El suelo vale sin pedir permiso (salvo con su función apagada)")
    func suelo() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        for t in [TipoDeAccion.comentar, .tareaMover, .avisar, .preguntar, .proponer, .borradorPreparar] {
            let d = a.decidir(.de("comercial", t, [EntornoGobierno.tareaPath.raw]))
            #expect(d.permitido && d.paso == 11, "\(t)")
        }
        let c = a.decidir(.de("contable", .conciliacionProponer, ["4 · Finanzas/Registros/pagos.csv"], capacidad: "FIN-04"))
        #expect(c.resultado == .denegado && c.paso == 11)
    }

    @Test("12 · Modos: off no, manual tarea para ti, asistido propuesta, supervisado al resumen, autónomo sí")
    func modos() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        let ruta = ["2 · Ventas/Contactos/x.md"]
        let sup = a.decidir(.de("comercial", .contactoRegistrar, ruta))
        #expect(sup.permitido && sup.paso == 12 && sup.alResumenSemanal, "VEN-02 supervisado")
        let asis = a.decidir(.de("comercial", .oportunidadRegistrar, ["2 · Ventas/Oportunidades/x.md"]))
        #expect(asis.resultado == .propuesta && asis.paso == 12, "VEN-03 asistido")
        #expect(a.decidir(.de("comercial", .fichaEditar, ruta, capacidad: "VEN-09")).resultado == .tareaParaPersona)
        let auto = a.decidir(.de("comercial", .fichaEditar, ruta, capacidad: "VEN-08"))
        #expect(auto.permitido && !auto.alResumenSemanal)
        #expect(a.decidir(.de("comercial", .fichaEditar, ruta, capacidad: "VEN-11")).resultado == .denegado)
        #expect(a.decidir(.de("comercial", .fichaEditar, ruta)).resultado == .propuesta, "sin función: te lo propone")
        #expect(a.decidir(.de("comercial", .fichaEditar, ruta, capacidad: "VEN-15")).resultado == .denegado, "no es suya")
        #expect(a.decidir(.de("mika", .decisionRegistrar, ["1 · Dirección/Decisiones.md"])).resultado == .propuesta)
        #expect(a.decidir(.de("mika", .decisionRegistrar, ["1 · Dirección/Decisiones.md"], origen: "chat:m-1")).permitido)
        let resumen = try a.estado.paraElResumenSemanal(desde: Date(timeIntervalSince1970: 0))
        #expect(resumen.count == 1 && resumen[0].accion == "contacto.registrar")
    }

    @Test("Cada decisión queda en la auditoría con su paso y su motivo")
    func auditoria() throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let a = try e.autorizador()
        a.decidir(.de("comercial", .comentar, [EntornoGobierno.tareaPath.raw], ejecucion: "r-9"))
        a.decidir(.de("comercial", .venceMover, [EntornoGobierno.tareaPath.raw], ejecucion: "r-9"))
        let l = try a.estado.auditoria(ejecucion: "r-9")
        #expect(l.map(\.decision) == ["permitido", "denegado"])
        #expect(l.map(\.paso) == [11, 5])
        #expect(l[1].accion == "vence.mover" && l[1].autor == .agente("comercial") && !l[1].motivo.isEmpty)
        #expect(l[0].rutas == [EntornoGobierno.tareaPath])
    }
}
