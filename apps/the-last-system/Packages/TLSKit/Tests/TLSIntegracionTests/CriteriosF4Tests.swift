import Darwin
import Foundation
import MCP
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSIntegracion
import TLSMCPHost
import TLSMCPShared
@testable import TLSUI

/// Los 10 criterios de aceptación de F4 (PLAN §9), de punta a punta: la empresa se abre como en la app, la integración
/// monta su motor, su servidor de herramientas y su gobierno, y lo que hacen los asistentes llega a la carpeta por el
/// `CommandBus`. Sin Claude de verdad: Ribera con `SimulatedRuntime` y las copias con un `claude` falso que arranca el
/// `tls-mcp-dev` compilado.
@Suite("F4 · criterios de aceptación de punta a punta", .serialized)
@MainActor
struct CriteriosF4Tests {

    /// Domingo 25 de octubre a mediodía: ninguna rutina de serie toca (para que en una copia solo trabaje lo pedido).
    static let domingo = EntornoF4.fecha(25, 12, 0)

    // MARK: F4-1

    @Test("F4-1 · En la copia recién configurada, Mika crea una tarea interna sin generar ninguna tarjeta")
    func criterio1() async throws {
        let grabaciones = try EntornoF4.grabaciones(["mika-accion": [
            FlujoF4.inicio(),
            FlujoF4.herramienta("tls_crear_tarea", id: "t1", entrada: ["titulo": "Preparar el repaso del trimestre",
                                                                     "descripcion": "Lo que hay que mirar el viernes."]),
            FlujoF4.resultadoHerramienta(id: "t1", texto: "{}"),
            FlujoF4.herramienta("tls_finalizar", id: "t2", entrada: ["resumen": "Te dejé una tarea para el repaso del trimestre."]),
            FlujoF4.resultadoHerramienta(id: "t2", texto: "{}"),
            FlujoF4.resultado("Te dejé una tarea para el repaso del trimestre."),
        ]])
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        // «Recién configurada»: la copia llega sin los asistentes en su configuración y los deja listos la persona (lo
        // mismo que escribe el paso 4 de la puesta en marcha y Ajustes › Asistentes).
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, preparar: { root in
            let url = root.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: url, encoding: .utf8)
            let corte = try #require(t.range(of: "# Asistentes:"))
            try Data(String(t[..<corte.lowerBound]).utf8).write(to: url)
        }, runtime: { puerta in SimulatedRuntime(grabaciones: grabaciones, servidor: puerta) }) { e in
            let sesion = try #require(e.sesion)
            #expect(!(e.texto(".tls/config.yaml") ?? "").contains("agentes:"))
            let plan = try #require(AsistentesDeSerie.plan(root: e.carpeta, persona: "Manu", semilla: e.entry.id.uuidString.lowercased()))
            #expect(try await sesion.escribir(plan: plan, aviso: "").hecho)
            #expect((e.texto(".tls/config.yaml") ?? "").contains("agentes:"))
            #expect(try #require(e.piezas).autorizador.estadoDeConfig().efectiva.asistente("mika")?.activo == true)

            let antes = Set(try e.bandeja().tarjetas.map(\.id))
            let host = try #require(e.host)
            let ej = try #require(try await host.pedir(a: "mika", instruccion: "Deja una tarea para el repaso del trimestre."))
            try await e.esperarTrabajos()
            let hecha = try #require(await host.ejecuciones().first { $0.id == ej.id })
            #expect(hecha.estado == .completada)

            // La ficha, con su Actividad (de Mika) y su línea de Bitácora.
            let f = e.foto()
            let tarea = try #require(f.notes.first { f.text($0)?.contains("Preparar el repaso del trimestre") == true && $0.raw.contains("/Tareas/") })
            let texto = try #require(f.text(tarea))
            #expect(texto.contains("agente:mika"))
            #expect(texto.contains("## Actividad"))
            // El cierre (Actividad y Bitácora) lo escribe la app justo después de terminar.
            try await esperar("la línea de la Bitácora", segundos: 10) { e.bitacora().contains(ej.id) }
            #expect(e.bitacora().contains("agente:mika"))
            // Ninguna tarjeta nueva en Decisiones.
            let despues = Set(try e.bandeja().tarjetas.map(\.id))
            #expect(despues.subtracting(antes).isEmpty, "Tarjetas nuevas: \(despues.subtracting(antes))")
            // El gobierno lo apuntó (permitido).
            let auditoria = try #require(e.piezas).autorizador.estado.auditoria(ejecucion: ej.id)
            #expect(auditoria.contains { $0.accion == "tarea.crear" && $0.decision == "permitido" })
        }
    }

    // MARK: F4-2

    @Test("F4-2 · tls_solicitar_accion {enviar_correo} da «aprobación requerida» en autónomo; editar desde fuera invalida; «Aprobar con mis cambios» en un gesto")
    func criterio2() async throws {
        try await EntornoF4.con(clase: .demo, preparar: { root in
            // El Comercial con su función de seguimiento en modo autónomo: aun así, todo lo externo pide tu OK.
            let url = root.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: url, encoding: .utf8)
            try Data((t + "capacidades:\n  VEN-08: {declarada: si, modo: autonomo, ejecutor: IA}\n").utf8).write(to: url)
        }) { e in
            let host = try #require(e.host)
            let p = try #require(e.piezas)
            #expect(p.autorizador.estadoDeConfig().efectiva.modo("VEN-08") == .autonomo)
            let ej = try #require(try await host.pedir(a: "comercial", instruccion: "Repasa el embudo", accion: "repaso-embudo"))
            try await e.esperarTrabajos()
            // Lo que vio el asistente al pedirlo: «aprobación requerida».
            let stream = try String(contentsOf: p.estadoDeCarpeta.appendingPathComponent("ejecuciones/\(ej.id)/stream.jsonl"), encoding: .utf8)
            #expect(stream.contains("aprobacion_requerida"))
            let borrador = VaultPath("2 · Ventas/Borradores/tu-declaracion-de-la-renta-2026.md")
            #expect(e.existe(borrador.raw))
            let apr = try #require(try ApprovalStore(estado: p.autorizador.estado).abiertas(ahora: .distantPast).first { $0.ruta == borrador })
            #expect(apr.estado.abierta)
            #expect(e.texto(borrador.raw)?.contains("Pendiente de tu OK") == true)

            // Editar el borrador desde fuera (Obsidian, Finder): «Aprobar» ya no vale.
            let url = borrador.url(in: e.carpeta)
            let t = try String(contentsOf: url, encoding: .utf8)
            try Data(t.replacingOccurrences(of: "diez minutos", with: "un cuarto de hora").utf8).write(to: url)
            await #expect(throws: ErrorDeGobierno.cambioDesdeQueLoPreparo) {
                _ = try await p.aprobaciones.aprobar(apr.id, autor: .persona("Manu"))
            }
            // «Aprobar con mis cambios»: aprueba lo que hay ahora en un solo gesto. Queda «Listo para enviar»: lo envías tú.
            let r = try await p.aprobaciones.aprobarConMisCambios(apr.id, autor: .persona("Manu"),
                                                                 cambios: CambiosDeAprobacion(asunto: "Tu Renta 2026"))
            guard case .listoParaEnviar = r else { Issue.record("Esperaba «Listo para enviar»: \(r)"); return }
            let fin = try #require(try ApprovalStore(estado: p.autorizador.estado).aprobacion(apr.id))
            #expect(fin.estado == .aprobada || fin.estado == .ejecutada)
            #expect(e.texto(borrador.raw)?.contains("Tu Renta 2026") == true)
        }
    }

    // MARK: F4-3

    @Test("F4-3 · Un asistente no ve lo privado (no encontrado, con auditoría), no fija metas ni funciones ni ajustes, no mueve vence ni cierra")
    func criterio3() async throws {
        try await EntornoF4.con(clase: .demo, preparar: { root in
            let dir = root.appendingPathComponent("4 · Finanzas/Expediente privado")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("# Nota privada\nNada que ver.\n".utf8).write(to: dir.appendingPathComponent("nota.md"))
            let url = root.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: url, encoding: .utf8)
            try Data(t.replacingOccurrences(of: "privado: []", with: "privado:\n  - \"4 · Finanzas/Expediente privado\"").utf8).write(to: url)
        }) { e in
            let m = try #require(e.motor)
            let servidor = try #require(m.servidor)
            let p = try #require(e.piezas)
            let c = ContextoDelAsistente(ejecucion: "r-criterio3", asistente: "contable", areas: [.finanzas], leeAreas: [.ventas, .entrega],
                                         maxTareas: 10)
            let leer = await servidor.llamar("tls_leer", argumentos: ["ruta": .string("4 · Finanzas/Expediente privado/nota.md")], contexto: c)
            #expect(leer.esError)
            #expect(leer.texto.lowercased().contains("no encontrad"))
            let lista = await servidor.llamar("tls_listar", argumentos: ["carpeta": .string("4 · Finanzas")], contexto: c)
            #expect(!lista.texto.contains("Expediente privado"))
            #expect(try p.autorizador.estado.auditoria(ejecucion: "r-criterio3").contains { $0.decision == "no_encontrado" })

            // El bus de la app (el mismo de la persona) deniega lo vetado a un asistente.
            // Una tarea de la persona (así ningún asistente la coge mientras tanto).
            let tarea = try await e.tareaPara(nil, titulo: "Revisar el banco de octubre", area: .finanzas)
            let antes = e.texto(tarea.raw)
            let vetos: [CommandBus.Comando] = [
                .cambiarPropiedades(tarea, poner: [Property(key: "estado", value: .text("Hecha"))], quitar: []),
                .cambiarPropiedades(tarea, poner: [Property(key: "estado", value: .text("Cancelada"))], quitar: []),
                .cambiarPropiedades(tarea, poner: [Property(key: "vence", value: .text("2026-12-31"))], quitar: []),
                .anadirLinea(VaultPath("1 · Dirección/Metas.md"), linea: "| VEN-WON | 99.000 € | meta fijada por el asistente |"),
                .crear(VaultPath(".tls/config.yaml"), texto: "interruptor: encendido\n"),
                .anadirLinea(VaultPath("6 · Equipo/Roles/financiero.md"), linea: "Puede todo."),
            ]
            for v in vetos {
                await #expect(throws: (any Error).self) { _ = try await p.bus.ejecutar(v, autor: .agente("contable")) }
            }
            #expect(e.texto(tarea.raw) == antes)
            // `capacidad.declarar`: una función declarada por un asistente en `capacidades:` tampoco.
            let config = try #require(e.texto(".tls/config.yaml"))
            let declarar = WritePlan(autor: .agente("contable"), descripcion: "Declarar FIN-02",
                                     ops: [try #require(WriteOp.replaceText(VaultPath(".tls/config.yaml"), base: Data(config.utf8),
                                                                           text: config + "capacidades:\n  FIN-02: {declarada: si}\n"))])
            await #expect(throws: (any Error).self) { _ = try await p.bus.ejecutar(declarar) }
            // Por las herramientas: cerrar su tarea tampoco.
            let cerrar = await servidor.llamar("tls_actualizar_tarea", argumentos: ["tarea": .string(tarea.raw), "estado": .string("Hecha")],
                                               contexto: c)
            #expect(cerrar.esError)
            #expect(e.texto(tarea.raw)?.contains("estado: Hecha") == false)
        }
    }

    // MARK: F4-4

    @Test("F4-4 · Con el interruptor apagado no sale nada; lo que estaba en marcha pierde sus herramientas y termina en ≤ 5 s")
    func criterio4() async throws {
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, abrir: false) { e in
            e.claude.stream([FlujoF4.inicio(), FlujoF4.texto("Miro el banco…")])
            e.claude.marcar("con-mcp")
            e.claude.marcar("colgar")
            try await e.abrir()
            let host = try #require(e.host)
            let p = try #require(e.piezas)
            let ej = try #require(try await host.pedir(a: "contable", instruccion: "Revisa los cobros"))
            try await esperar("trabajo en curso con tls-mcp conectado", segundos: 20) {
                let enCurso = await host.ejecuciones().first { $0.id == ej.id }?.estado == .enCurso
                return enCurso && !procesos(e.appSupport.path).isEmpty
            }
            let token = try #require(try? String(contentsOf: p.estadoDeCarpeta.appendingPathComponent("ejecuciones/\(ej.id)/token"),
                                                 encoding: .utf8))
            let socket = try #require(e.motor?.puerta?.host.socket.path)
            // Con el token del trabajo, la app acepta la conexión.
            let antes = try IPCCliente.conectar(socket: socket, token: token, timeout: 5)
            antes.cerrar()

            let t0 = Date()
            try await EscrituraAsistentes.ponerInterruptor(false, sesion: try #require(e.sesion))
            // La siguiente llamada se deniega: el token ya no vale.
            #expect(throws: (any Error).self) { _ = try IPCCliente.conectar(socket: socket, token: token, timeout: 5) }
            try await esperar("el proceso termina", segundos: 8) {
                procesos(e.claude.dir.path).isEmpty && procesos(e.appSupport.path).isEmpty
            }
            let tardo = Date().timeIntervalSince(t0)
            print("F4-4 · el trabajo en marcha terminó \(String(format: "%.2f", tardo)) s después de apagar el interruptor")
            #expect(tardo <= 5.5, "Tardó \(tardo) s")
            let parada = try #require(await host.ejecuciones().first { $0.id == ej.id })
            #expect(parada.estado != .enCurso && parada.estado != .completada)

            // Con el interruptor apagado, una tarea lista entra en la cola pero no sale.
            e.claude.quitar("colgar")
            e.claude.stream([FlujoF4.inicio(), FlujoF4.resultado()])
            let llamadas = e.claude.llamadas
            try await e.tareaPara("contable", titulo: "Mirar los recibos de la luz", area: .finanzas)
            _ = await host.revisar()
            await host.cola.procesar()
            try await Task.sleep(for: .milliseconds(800))
            #expect(e.claude.llamadas == llamadas)
            #expect(!(await host.ejecuciones()).contains { $0.estado == .enCurso || ($0.estado == .completada && $0.id != ej.id) })
        }
    }

    // MARK: F4-5

    @Test("F4-5 · Presupuesto mínimo: fallida(.presupuesto) sin reintentos")
    func criterio5() async throws {
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, abrir: false) { e in
            e.claude.stream([FlujoF4.inicio(), FlujoF4.resultado("", subtipo: "error_max_budget_usd", error: true, coste: 0.5)])
            try await e.abrir()
            let host = try #require(e.host)
            let ej = try #require(try await host.pedir(a: "contable", instruccion: "Revisa los cobros"))
            try await e.esperarTrabajos()
            e.reloj.avanzar(3600)
            _ = await host.revisar()
            await host.cola.procesar()
            try await e.esperarTrabajos()
            let x = try #require(await host.ejecuciones().first { $0.id == ej.id })
            #expect(x.estado == .fallida)
            #expect(x.motivo == .presupuesto)
            #expect(x.intento == 0)
            #expect(e.claude.llamadas == 1)
            try await esperar("la línea de la Bitácora", segundos: 10) { e.bitacora().contains(ej.id) }
        }
    }

    // MARK: F4-6

    @Test("F4-6 · tls_preguntar deja el trabajo esperando; al contestar se reanuda la misma sesión y la tarea recibe otra entrada en Actividad")
    func criterio6() async throws {
        // La tarea del Contable sigue la grabación de la pregunta del extracto; la respuesta, la suya.
        let grabaciones = try EntornoF4.grabaciones(copias: ["contable-tarea": "contable-extracto-importado"])
        defer { try? FileManager.default.removeItem(at: grabaciones) }
        try await EntornoF4.con(clase: .demo, inicio: Self.domingo, grabaciones: grabaciones) { e in
            let host = try #require(e.host)
            let p = try #require(e.piezas)
            let tarea = try await e.tareaPara("contable", titulo: "Revisar el extracto de octubre", area: .finanzas)
            _ = await host.revisar()
            await host.cola.procesar()
            try await e.esperarTrabajos()
            let primero = try #require(await host.ejecuciones().first { $0.tarea == tarea })
            #expect(primero.estado == .esperandoRespuesta)
            let pregunta = try #require(primero.pregunta)
            #expect(e.existe(pregunta))
            let sesion = try #require(primero.sesion)
            let entradas = { (e.texto(tarea.raw) ?? "").components(separatedBy: "\n### ").count - 1 }
            let antes = entradas()
            #expect(antes >= 1)

            let segundo = try #require(try await host.responder(pregunta: pregunta, texto: "Sí, pídesela.", autor: "Manu"))
            try await e.esperarTrabajos()
            let reanudado = try #require(await host.ejecuciones().first { $0.id == segundo.id })
            #expect(reanudado.estado == .completada)
            #expect(reanudado.sesion == sesion)
            let stream = try String(contentsOf: p.estadoDeCarpeta.appendingPathComponent("ejecuciones/\(segundo.id)/stream.jsonl"), encoding: .utf8)
            #expect(stream.contains("\"session_id\":\"\(sesion.uuidString.lowercased())\""))
            try await esperar("otra entrada en la Actividad de la tarea", segundos: 10) { entradas() > antes }
            // Lo que preparó al seguir (un correo) espera tu OK.
            #expect(try ApprovalStore(estado: p.autorizador.estado).abiertas(ahora: .distantPast).contains {
                $0.ruta?.raw.contains("factura-de-agosto") == true
            })
        }
    }

    // MARK: F4-7

    @Test("F4-7 · Dos disparos del mismo hueco dan un trabajo; reiniciar con la cola llena no pierde ni duplica nada")
    func criterio7() async throws {
        // Lunes 19, 10:05: le toca a la rutina del Comercial (10:00).
        try await EntornoF4.con(clase: .demo, inicio: EntornoF4.fecha(19, 10, 5)) { e in
            let host = try #require(e.host)
            let p = try #require(e.piezas)
            _ = await host.revisar()
            _ = await host.revisar()
            let rutina = { (h: AgentHost) async -> [Ejecucion] in
                await h.ejecuciones().filter { $0.disparo.rutina == "repaso-embudo" }
            }
            #expect(await rutina(host).count == 1)
            await host.cola.procesar()
            try await e.esperarTrabajos()

            // La cola llena: Dirección y Finanzas en pausa, y tres tareas para sus asistentes.
            _ = try await EditorConfigAgentes.aplicar(.pausaAreas([.direccion, .finanzas]), bus: p.bus, autor: .persona("Manu"))
            await host.ajustesCambiaron()
            try await e.tareaPara("contable", titulo: "Mirar el seguro del local", area: .finanzas)
            try await e.tareaPara("contable", titulo: "Mirar la cuota de autónomos", area: .finanzas)
            try await e.tareaPara("mika", titulo: "Pensar el plan de noviembre", area: .direccion)
            _ = await host.revisar()
            await host.cola.procesar()
            let enCola = await host.ejecuciones().filter { $0.estado == .enCola || $0.estado == .pendiente }
            #expect(enCola.count == 3)

            // Reiniciar (cerrar los asistentes y volver a montarlos) con la cola llena.
            let sesion = try #require(e.sesion)
            await e.app.escritorSeVa(sesion)
            await e.app.escritorListo(sesion)
            #expect(e.motor?.listo == true)
            let host2 = try #require(e.host)
            #expect(host2 !== host)
            _ = await host2.revisar()
            _ = await host2.revisar()
            let tras = await host2.ejecuciones().filter { $0.estado == .enCola || $0.estado == .pendiente }
            #expect(Set(tras.map(\.id)) == Set(enCola.map(\.id)), "ni se pierde ni se duplica")
            #expect(await rutina(host2).count == 1)

            // Al quitar la pausa, cada uno sale una vez.
            _ = try await EditorConfigAgentes.aplicar(.pausaAreas([]), bus: try #require(e.piezas).bus, autor: .persona("Manu"))
            await host2.ajustesCambiaron()
            _ = await host2.revisar()
            await host2.cola.procesar()
            try await e.esperarTrabajos(segundos: 60)
            let fin = await host2.ejecuciones().filter { Set(enCola.map(\.id)).contains($0.id) }
            #expect(fin.count == 3)
            #expect(fin.allSatisfy { $0.estado.esFinal || $0.estado == .esperandoRespuesta })
            #expect(await host2.ejecuciones().filter { $0.disparo.tipo == .tarea }.count == 3)
        }
    }

    // MARK: F4-8

    @Test("F4-8 · En Ribera, 14 días simulados dan 5 tarjetas nuevas al día o menos de media")
    func criterio8() async throws {
        try await EntornoF4.con(clase: .demo, inicio: EntornoF4.fecha(19, 7, 0)) { e in
            let host = try #require(e.host)
            var vistas = Set(try e.bandeja().tarjetas.map(\.id))
            var nuevasPorDia: [Int] = []
            for d in 0..<14 {
                let dia = 19 + d
                let (mes, diaDelMes) = dia > 31 ? (11, dia - 31) : (10, dia)
                for (h, m) in [(8, 1), (8, 31), (8, 46), (9, 1), (10, 1), (11, 1), (18, 0)] {
                    e.reloj.fijar(EntornoF4.fecha(diaDelMes, h, m, mes: mes))
                    _ = await host.revisar()
                    await host.cola.procesar()
                    try await e.esperarTrabajos(segundos: 60)
                }
                let ids = Set(try e.bandeja().tarjetas.map(\.id))
                nuevasPorDia.append(ids.subtracting(vistas).count)
                vistas.formUnion(ids)
            }
            let trabajos = await host.ejecuciones(limite: 2000).filter { $0.estado.esFinal || $0.estado == .esperandoRespuesta }
            let media = Double(nuevasPorDia.reduce(0, +)) / 14
            print("F4-8 · 14 días en Ribera: \(trabajos.count) trabajos; tarjetas nuevas por día \(nuevasPorDia); media \(String(format: "%.2f", media))")
            #expect(trabajos.count >= 14, "Los asistentes trabajaron (\(trabajos.count) trabajos)")
            #expect(media <= 5, "Media de tarjetas nuevas al día: \(media) (\(nuevasPorDia))")
        }
    }

    // MARK: F4-9

    @Test("F4-9 · Al salir no queda ningún tls-mcp vivo, y ~/.claude.json no gana más proyectos que asistentes activos")
    func criterio9() async throws {
        try await EntornoF4.con(clase: .copia, inicio: Self.domingo, abrir: false) { e in
            e.claude.stream([FlujoF4.inicio(), FlujoF4.texto("Trabajando…")])
            e.claude.marcar("con-mcp")
            e.claude.marcar("colgar")
            e.app.instalar(en: e.model)
            try await e.abrir()
            let host = try #require(e.host)
            let piezas = try #require(e.piezas)
            let socket = try #require(e.motor?.puerta?.host.socket)
            #expect(FileManager.default.fileExists(atPath: socket.path))
            // Primero el Contable (se cancela), después Mika (sigue trabajando al salir). Cada uno, en su carpeta.
            let contable = try #require(try await host.pedir(a: "contable", instruccion: "Revisa los cobros"))
            try await esperar("Contable en marcha con su tls-mcp", segundos: 20) {
                await host.ejecuciones().first { $0.id == contable.id }?.estado == .enCurso && !procesos(socket.path).isEmpty
            }
            await host.cancelar(contable.id)
            try await esperar("el Contable termina", segundos: 8) { procesos(e.claude.dir.path).isEmpty }
            let mika = try #require(try await host.pedir(a: "mika", instruccion: "Mira el día"))
            try await esperar("Mika en marcha con su tls-mcp", segundos: 20) {
                await host.ejecuciones().first { $0.id == mika.id }?.estado == .enCurso && !procesos(socket.path).isEmpty
            }

            // ⌘Q: la app para los asistentes antes de salir.
            let salir = try #require(TLSAppDelegate.alSalir)
            let t0 = Date()
            await salir()
            let tardo = Date().timeIntervalSince(t0)
            print("F4-9 · parar al salir: \(String(format: "%.2f", tardo)) s")
            #expect(tardo < 9)
            try await esperar("ningún tls-mcp vivo", segundos: 8) { procesos(socket.path).isEmpty && procesos(e.claude.dir.path).isEmpty }
            #expect(procesos(socket.path).isEmpty)
            #expect(!FileManager.default.fileExists(atPath: socket.path), "el socket se borra")
            #expect(e.motor == nil)

            // Claude apunta un proyecto por carpeta de trabajo: una por asistente (agentes/<slug>), nunca una por trabajo.
            let proyectos = Set(((try? String(contentsOf: e.home.appendingPathComponent(".claude-proyectos.txt"), encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init))
            let activos = piezas.autorizador.estadoDeConfig().efectiva.activos.count
            #expect(proyectos.count <= activos)
            #expect(proyectos.count == 2, "\(proyectos)")
            #expect(proyectos.allSatisfy { $0.hasSuffix("/agentes/contable") || $0.hasSuffix("/agentes/mika") })
        }
    }

    // MARK: F4-10

    @Test("F4-10 · Un asistente de un área preparada o en reposo no se lanza")
    func criterio10() async throws {
        // Ribera: Marca preparada y Equipo en reposo. Sus asistentes, activos en la configuración: aun así no trabajan.
        try await EntornoF4.con(clase: .demo, inicio: EntornoF4.fecha(23, 11, 5), preparar: { root in
            let url = root.appendingPathComponent(".tls/config.yaml")
            var t = try String(contentsOf: url, encoding: .utf8)
            for slug in ["marca", "equipo"] {
                let r = try #require(t.range(of: "  \(slug):\n    activo: false"))
                t.replaceSubrange(r, with: "  \(slug):\n    activo: true")
            }
            try Data(t.utf8).write(to: url)
        }) { e in
            let host = try #require(e.host)
            let p = try #require(e.piezas)
            #expect(p.autorizador.estadoDeConfig().efectiva.asistente("marca")?.activo == true)
            #expect(try await host.pedir(a: "marca", instruccion: "Prepara una pieza") == nil)
            #expect(try await host.pedir(a: "equipo", instruccion: "Revisa el mes") == nil)
            try await e.tareaPara("equipo", titulo: "Revisar los roles", area: .equipo)
            // Viernes 23, 11:05: la rutina de Marca (11:00) toca, pero su área está preparada.
            _ = await host.revisar()
            await host.cola.procesar()
            try await e.esperarTrabajos()
            let suyos = await host.ejecuciones().filter { ["marca", "equipo"].contains($0.agente) }
            #expect(!suyos.contains { $0.estado == .completada || $0.estado == .enCurso })
            #expect(!p.autorizador.puedeLanzar("marca").permitido)
            #expect(!p.autorizador.puedeLanzar("equipo").permitido)
        }
    }
}
