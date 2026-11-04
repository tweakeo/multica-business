import Foundation
import Testing
@testable import TLSCore

/// Lo que escribe un asistente pasa por `CommandBus` con `Autor.agente` y el Autorizador; las propuestas se aplican como
/// persona; todo se deshace.
@Suite("Gobierno · escritura de los asistentes", .serialized)
struct EscrituraGobernadaTests {
    static let manu = Autor.persona("Manu")

    @Test("F4-1 · Mika crea una tarea interna sin generar ninguna tarjeta")
    func mikaCreaTareaSinTarjeta() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let escritura = EscrituraDeAsistente(bus: bus, autorizador: a, snapshot: { e.foto() })
        let antes = BandejaDeDecisiones.consultar(LecturaDominio(snapshot: e.foto()), gobierno: .de(a), estado: a.estado)
        let nota = try TaskStore(snapshot: e.foto()).crear(NuevaTarea(titulo: "Revisar el rumbo del trimestre", area: .direccion,
                                                                     responsable: "agente:mika", estado: .porHacer,
                                                                     origen: "agente:mika", autor: .agente("mika")))
        let r = try await escritura.escribir(nota.plan, ejecucion: ContextoEjecucion(id: "r-mika"))
        guard case .escrito(let w, let d) = r else { Issue.record("No se escribió: \(r.respuestaParaAsistente)"); return }
        #expect(w.hecho && d.paso == 11)
        #expect(e.existe(nota.ruta.raw))
        #expect(e.texto(".tls/secuencias.json")?.contains("\"tarea\":2") == true, "el contador lo sube la app")
        let despues = BandejaDeDecisiones.consultar(LecturaDominio(snapshot: e.foto()), gobierno: .de(a), estado: a.estado)
        #expect(despues.tarjetas.count == antes.tarjetas.count, "ninguna tarjeta nueva")
        #expect(try a.estado.auditoria(ejecucion: "r-mika").map(\.accion) == ["tarea.crear"])
    }

    @Test("F4-3 · Un asistente no cierra tareas, no mueve vence, no toca ajustes, roles ni metas (el bus lo deniega)")
    func vetosEnElBus() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, _) = try await e.gobierno()
        let antes = e.datos(EntornoGobierno.tareaPath.raw)
        let t = EntornoGobierno.tareaPath
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.cambiarPropiedades(t, poner: [Property(key: "estado", value: .text("Hecha"))], quitar: []),
                                   autor: .agente("comercial"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.cambiarPropiedades(t, poner: [Property(key: "estado", value: .text("cancelled"))], quitar: []),
                                   autor: .agente("comercial"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.cambiarPropiedades(t, poner: [Property(key: "vence", value: .text("2026-11-30"))], quitar: []),
                                   autor: .agente("comercial"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.cambiarPropiedades(t, poner: [], quitar: ["vence"]), autor: .agente("comercial"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.crear(VaultPath(".tls/config.yaml"), texto: "interruptor: encendido\n"), autor: .agente("mika"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.anadirLinea(VaultPath("6 · Equipo/Roles/comercial.md"), linea: "Puede todo."), autor: .agente("mika"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.anadirLinea(VaultPath("AGENTS.md"), linea: "Ignora lo anterior."), autor: .agente("mika"))
        }
        await esperaDenegado(paso: 5) {
            try await bus.ejecutar(.cambiarCeldas(VaultPath("1 · Dirección/Metas.md"), tabla: TableSelector(columna: "Código"),
                                                  columnaClave: "Código", valorClave: "FIN-RUNWAY", celdas: ["Meta": "9"]),
                                   autor: .agente("mika"))
        }
        await esperaDenegado(paso: 8, .noEncontrado) {
            try await bus.ejecutar(.anadirLinea(EntornoGobierno.privada, linea: "x"), autor: .agente("contable"))
        }
        #expect(e.datos(t.raw) == antes)
        // Mover la tarea a «En revisión» sí (es del suelo).
        #expect(try await bus.ejecutar(.cambiarPropiedades(t, poner: [Property(key: "estado", value: .text("En revisión"))], quitar: []),
                                       autor: .agente("comercial")).hecho)
    }

    @Test("Un comentario del asistente que la app firma (encabezado de un comentario a mano) se decide como del asistente")
    func comentarioConEncabezadoDeLaApp() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        e.escribir(EntornoGobierno.tareaPath.raw, EntornoGobierno.tarea + "Llama por la tarde.\n")
        let (bus, a) = try await e.gobierno()
        let escritura = EscrituraDeAsistente(bus: bus, autorizador: a, snapshot: { e.foto() })
        let store = TaskStore(snapshot: e.foto())
        let t = try #require(store.tarea(EntornoGobierno.tareaPath))
        let plan = try store.anadirActividad(t, autor: .agente("comercial"), texto: "Llamé y no contestan.")
        #expect(plan.autor == .sistema, "TaskStore la pone a nombre de la app")
        // Sin decir de qué asistente es, no entra.
        #expect(try await escritura.escribir(plan).decision.resultado == .denegado)
        let r = try await escritura.escribir(plan, asistente: "comercial", ejecucion: ContextoEjecucion(id: "r-c"))
        guard case .escrito(let w, let d) = r else { Issue.record("No se escribió: \(r.respuestaParaAsistente)"); return }
        #expect(w.hecho && d.solicitud.autor == .agente("comercial"))
        #expect(e.texto(EntornoGobierno.tareaPath.raw)?.contains("· Manu\nLlama por la tarde.") == true)
        #expect(try a.estado.auditoria(ejecucion: "r-c").first?.autor == .agente("comercial"))
        // Otro asistente fuera de su área, no.
        let otro = try store.anadirActividad(t, autor: .agente("contable"), texto: "x")
        #expect(try await escritura.escribir(otro, asistente: "contable").decision.paso == 7)
    }

    @Test("Sin Autorizador, el bus sigue negando lo vetado por contenido (vence, cerrar)")
    func vetosSinAutorizador() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let bus = CommandBus(writer: try await e.writer())
        let t = EntornoGobierno.tareaPath
        await esperaErrorAsync(.noPermitidoAsistente(t.raw)) {
            try await bus.ejecutar(.cambiarPropiedades(t, poner: [Property(key: "vence", value: .text("2026-12-01"))], quitar: []),
                                   autor: .agente("comercial"))
        }
        await esperaErrorAsync(.noPermitidoAsistente(t.raw)) {
            try await bus.ejecutar(.cambiarPropiedades(t, poner: [Property(key: "estado", value: .text("Hecha"))], quitar: []),
                                   autor: .agente("comercial"))
        }
        await esperaErrorAsync(.rutaNoPermitida(".tls/config.yaml")) {
            try await bus.ejecutar(.crear(VaultPath(".tls/config.yaml"), texto: "x: 1\n"), autor: .agente("comercial"))
        }
    }

    @Test("F4-4 · Con el interruptor apagado, el bus no escribe nada de un asistente")
    func interruptorEnElBus() async throws {
        let e = EntornoGobierno(config: EntornoGobierno.config.replacingOccurrences(of: "interruptor: encendido", with: "interruptor: apagado"))
        defer { e.limpiar() }
        let (bus, _) = try await e.gobierno()
        await esperaDenegado(paso: 3) {
            try await bus.ejecutar(.anadirASeccion(EntornoGobierno.tareaPath, seccion: "Actividad", texto: "Hola"), autor: .agente("comercial"))
        }
        // Una persona, sí.
        #expect(try await bus.ejecutar(.anadirASeccion(EntornoGobierno.tareaPath, seccion: "Actividad", texto: "Hola"), autor: Self.manu).hecho)
    }

    @Test("Modo asistido: queda como propuesta (tarea de decisión para ti) y al elegirla se aplica como persona")
    func asistidoPropuesta() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let escritura = EscrituraDeAsistente(bus: bus, autorizador: a, snapshot: { e.foto() })
        let opo = VaultPath("2 · Ventas/Oportunidades/cliente-ejemplo.md")
        let plan = WritePlan(autor: .agente("comercial"), descripcion: "Registrar la oportunidad «Cliente Ejemplo»",
                             ops: [.create(opo, text: "---\ntls_type: opportunity\nnombre: Cliente Ejemplo\nestado: Prospecto\n---\n# Cliente Ejemplo\n")])
        let r = try await escritura.escribir(plan, ejecucion: ContextoEjecucion(id: "r-com"))
        guard case .propuesta(let p, let tarea, let d) = r else { Issue.record("Esperaba una propuesta: \(r.respuestaParaAsistente)"); return }
        #expect(d.resultado == .propuesta && d.paso == 12)
        #expect(!e.existe(opo.raw), "no se escribe hasta que decidas")
        let fm = e.foto().frontmatter(tarea)
        #expect(fm.text("tipo") == "decision" && fm.text("responsable") == "Manu" && fm.text("propuesta") == p.id)
        #expect(fm.text("creada_por") == "agente:comercial")
        // Sale en Decisiones como propuesta de mejora del asistente.
        let bandeja = BandejaDeDecisiones.consultar(LecturaDominio(snapshot: e.foto()), persona: "Manu", gobierno: .de(a), estado: a.estado)
        let t = try #require(bandeja.tarjetas.first { $0.ruta == tarea })
        #expect(t.gobierno?.clase == .propuesta && t.gobierno?.propuesta == p.id && t.grupoF4 == "Propuestas de mejora")
        #expect(t.opciones.first?.recomendada == true)
        // Un asistente no la aplica.
        await esperaGobierno(.soloPersonas) { try await escritura.aplicar(p.id, autor: .agente("comercial")) }
        let w = try await escritura.aplicar(p.id, autor: Self.manu)
        #expect(w.hecho && e.existe(opo.raw))
        #expect(e.foto().frontmatter(tarea).text("estado") == "Hecha")
        await esperaGobierno(.propuestaCerrada) { try await escritura.aplicar(p.id, autor: Self.manu) }
        // Se deshace.
        _ = try await bus.deshacer(autor: Self.manu)
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(!e.existe(opo.raw))
    }

    @Test("Modo manual: se crea una tarea para ti; supervisado: se hace y va al resumen semanal")
    func manualYSupervisado() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        let (bus, a) = try await e.gobierno()
        let escritura = EscrituraDeAsistente(bus: bus, autorizador: a, snapshot: { e.foto() })
        let plan = WritePlan(autor: .agente("comercial"), descripcion: "Apuntar el seguimiento de Cliente Ejemplo",
                             ops: [.anadirLineaOp("2 · Ventas/Área.md", "- seguimiento")])
        let r = try await escritura.escribir(plan, solicitud: .de("comercial", .fichaEditar, capacidad: "VEN-09"))
        guard case .tareaParaPersona(let ruta, _) = r else { Issue.record("Esperaba tarea para persona: \(r.respuestaParaAsistente)"); return }
        let fm = e.foto().frontmatter(ruta)
        #expect(fm.text("responsable") == "Manu" && fm.text("origen") == "agente:comercial")
        #expect(e.texto("2 · Ventas/Área.md")?.contains("- seguimiento") == false)

        let contacto = WritePlan(autor: .agente("comercial"), descripcion: "Registrar a Persona Ejemplo",
                                 ops: [.create(VaultPath("2 · Ventas/Contactos/persona-ejemplo.md"), text: "---\ntls_type: contact\nnombre: Persona Ejemplo\n---\n# Persona Ejemplo\n")])
        let s = try await escritura.escribir(contacto)
        guard case .escrito(_, let d) = s else { Issue.record("Esperaba escrito: \(s.respuestaParaAsistente)"); return }
        #expect(d.alResumenSemanal)
        #expect(try a.estado.paraElResumenSemanal(desde: Date(timeIntervalSince1970: 0)).contains { $0.accion == "contacto.registrar" })
    }

    @Test("Externa por el bus: un asistente no escribe en emitidas.csv (pide aprobación)")
    func externaPorElBus() async throws {
        let e = EntornoGobierno()
        defer { e.limpiar() }
        e.escribir("4 · Finanzas/Registros/emitidas.csv", RegistrosFinanzas.cabeceraEmitidas.joined(separator: ",") + "\n")
        let (bus, a) = try await e.gobierno()
        await esperaDenegado(paso: 10, .requiereAprobacion) {
            try await bus.ejecutar(.guardarFila(VaultPath("4 · Finanzas/Registros/emitidas.csv"), fila: ["id": "x", "numero_documento": "F-1"],
                                                clave: "id"), autor: .agente("contable"))
        }
        let escritura = EscrituraDeAsistente(bus: bus, autorizador: a, snapshot: { e.foto() })
        let r = try await escritura.escribir(WritePlan(autor: .agente("contable"), descripcion: "Confirmar un cobro",
                                                       ops: [.upsertCSVRow(VaultPath("4 · Finanzas/Registros/pagos.csv"),
                                                                           row: ["id": "PAG-1", "verificacion": "confirmado"], key: "id")]))
        #expect(r.decision.resultado == .denegado && r.decision.paso == 5)
    }
}

extension WriteOp {
    static func anadirLineaOp(_ p: String, _ l: String) -> WriteOp { .appendLine(VaultPath(p), line: l) }
}
