import Foundation
import Testing
@testable import TLSCore

@Suite("Dominio · eventos, outbox y reglas", .serialized)
struct ReglasTests {
    typealias A = DominioApoyo

    // MARK: VEN-07 de punta a punta (criterio 3 de F2)

    @Test("Confirmar la conciliación de una emitida pagada deja Ganada y 1 proyecto; repetirlo deja 1")
    func cobroGanaYAbreUnProyecto() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let pagosAntes = c.texto(A.pagos)
        let r = try await motor.ejecutar(A.confirmarCobroJorge())
        #expect(r.escritura.hecho)
        #expect(r.eventos.map(\.clave) == ["cobro.confirmado:PAG-20261017-001"])
        // Ganada, con su fecha de cierre (la del cobro).
        let opo = c.lectura().ficha(A.opoJorge)!
        #expect(opo.estado == "Ganada")
        #expect(opo.texto("cerrada") == "2026-10-17")
        // Un proyecto de entrega, ligado a la oportunidad, en curso desde hoy (lunes 19 oct en Ribera).
        let proyectos = c.proyectos()
        #expect(proyectos == [VaultPath("3 · Entrega/Proyectos/talleres-martin-e-hijos-trimestrales/Proyecto.md")])
        let p = try #require(c.lectura().ficha(proyectos[0]))
        #expect(p.texto("clase") == "entrega" && p.estado == "En curso" && p.texto("inicio") == "2026-10-19")
        #expect(p.texto("oportunidad") == "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]")
        #expect(p.texto("origen") == "regla:cobro.confirmado")
        // Las tareas del plan de entrega (6), en días laborables y numeradas seguidas.
        let tareas = c.tareas().filter { $0.ruta.isDescendant(of: proyectos[0].parent!) }.sorted { $0.numeroEntero! < $1.numeroEntero! }
        #expect(tareas.map(\.titulo) == ["Solicitar facturas emitidas, recibidas y extractos del trimestre",
                                         "Contabilizar facturas y clasificar gastos", "Conciliar bancos y listar diferencias",
                                         "Preparar borradores de los modelos 303 y 111", "Validación del cliente y aviso del cargo",
                                         "Presentar modelos y archivar justificantes"])
        #expect(tareas.map(\.numero) == ["T-0003", "T-0004", "T-0005", "T-0006", "T-0007", "T-0008"])
        #expect(tareas.map { $0.planificada?.description } == ["2026-10-19", "2026-10-22", "2026-10-27", "2026-10-29", "2026-11-02", "2026-11-03"])
        #expect(tareas.allSatisfy { $0.planificada.map { !$0.isWeekend } == true })
        #expect(tareas.allSatisfy { $0.origen == "regla:proyecto.creado" && $0.estado == .porHacer })
        #expect(tareas[0].responsable == "agente:implementador" && tareas[3].responsable == "Manu")
        #expect(c.texto(VaultPath(".tls/secuencias.json")).contains("\"tarea\":8"))
        // Contrato en borrador; la factura ya existía (F-2026-0007): no se prepara otra.
        let contrato = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales/Contrato.md")
        #expect(c.existe(contrato))
        #expect(c.lectura().ficha(contrato)?.estado == "Borrador")
        #expect(c.lectura().que(apuntan: A.opoJorge, por: "oportunidad", tipo: .invoice).map(\.ruta) == [A.facturaJorge])
        // Las reglas no tocaron pagos.csv: la única fila nueva es la de la persona.
        let lineasAntes = Set(pagosAntes.components(separatedBy: "\n"))
        let nuevas = c.texto(A.pagos).components(separatedBy: "\n").filter { !lineasAntes.contains($0) }
        #expect(nuevas.count == 1, "\(nuevas)")
        #expect(nuevas.first?.hasPrefix("PAG-20261017-001,") == true)
        // Lo que hicieron las reglas, en orden (cadena de 2 pasos).
        let escritas = r.reglas.filter(\.escribio).map(\.regla)
        #expect(escritas == ["VEN-07·ganada", "FIN-10·contrato·oportunidad.ganada", "ENT-02·tareas"])
        let guardados = try motor.estado.eventos()
        #expect(guardados.map(\.estado).allSatisfy { $0 == .procesado })
        #expect(Set(guardados.map(\.evento.tipo)) == [.cobroConfirmado, .oportunidadGanada, .proyectoCreado])
        #expect(guardados.first { $0.evento.tipo == .proyectoCreado }?.evento.profundidad == 1)

        // Repetir: procesar otra vez, volver a confirmar la misma fila o un segundo cobro de la misma factura.
        let huella = c.huella()
        #expect(await motor.procesarPendientes().isEmpty)
        let otraVez = try await motor.ejecutar(A.confirmarCobroJorge())
        #expect(otraVez.escritura.hecho == false)
        #expect(c.huella() == huella)
        let segundo = try await motor.ejecutar(WritePlan(autor: .persona("Manu"), descripcion: "Segundo cobro",
                                                         ops: [.upsertCSVRow(A.pagos, row: A.filaCobroJorge(id: "PAG-20261020-001"), key: "id")]))
        #expect(segundo.eventos.map(\.clave) == ["cobro.confirmado:PAG-20261020-001"])
        #expect(segundo.reglas.allSatisfy { !$0.escribio })
        #expect(c.proyectos().count == 1)
        #expect(c.tareas().count == 8)
    }

    @Test("Aunque se pierda el estado (o se cierre a mitad), volver a procesar el cobro no duplica nada")
    func idempotenteSinEstado() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        do {
            let motor = try await c.motor()
            _ = try await motor.ejecutar(A.confirmarCobroJorge())
            motor.estado.cerrar()
        }
        let huella = c.huella()
        // Otro motor con el mismo estado: nada pendiente.
        do {
            let motor = try await c.motor()
            #expect(await motor.procesarPendientes().isEmpty)
            motor.estado.cerrar()
        }
        // Sin estado (borrado): el mismo cobro vuelve a llegar y las reglas ven que ya está hecho.
        try FileManager.default.removeItem(at: c.estado.appendingPathComponent(EstadoDominio.fileName))
        let motor = try await c.motor()
        let antes = c.texto(A.pagos).replacingOccurrences(of: "\n" + "PAG-20261017-001,2026-10-17,cobro,181.50,EUR,F-2026-0007,,Talleres Martín e Hijos SL,transferencia,Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv#MOV-11e4d44973fd,confirmado", with: "")
        let hechas = try await motor.registrar([CambioAplicado(ruta: A.pagos, antes: antes, despues: c.texto(A.pagos))], autor: .persona("Manu"))
        #expect(!hechas.isEmpty)
        #expect(hechas.allSatisfy { !$0.escribio })
        #expect(c.huella() == huella)
        #expect(c.proyectos().count == 1)
    }

    @Test("Un cobro que escribe el sistema o un asistente no gana nada")
    func cobroSinPersona() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let deriver = EventDeriver(layout: c.foto().layout)
        let antes = c.texto(A.pagos)
        let despues = antes + "PAG-20261017-001,2026-10-17,cobro,181.50,EUR,F-2026-0007,,Talleres,transferencia,x,confirmado\n"
        let cambio = [CambioAplicado(ruta: A.pagos, antes: antes, despues: despues)]
        #expect(deriver.derivar(cambio, autor: .sistema).isEmpty)
        #expect(deriver.derivar(cambio, autor: .agente("contable")).isEmpty)
        #expect(deriver.derivar(cambio, autor: .persona("Manu")).map(\.clave) == ["cobro.confirmado:PAG-20261017-001"])
        // Una fila «propuesta» tampoco.
        let propuesta = antes + "PAG-20261017-001,2026-10-17,cobro,181.50,EUR,F-2026-0007,,Talleres,transferencia,x,propuesta\n"
        #expect(deriver.derivar([CambioAplicado(ruta: A.pagos, antes: antes, despues: propuesta)], autor: .persona("Manu")).isEmpty)
    }

    // MARK: Reglas de alta

    @Test("contacto.creado deja la tarea «Preparar diagnóstico» para la persona, en un día laborable")
    func contactoNuevo() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let nota = try PlantillaMotor(snapshot: c.foto()).preparar(.init(plantilla: "contacto", valores: ["titulo": "Rosa Llop"]))
        let r = try await motor.ejecutar(nota.plan)
        #expect(r.eventos.map(\.tipo) == [.contactoCreado])
        let tarea = try #require(c.tareas().first { $0.origen == "regla:contacto.creado" })
        #expect(tarea.titulo == "Preparar diagnóstico de Rosa Llop")
        #expect(tarea.ruta.raw.hasPrefix("2 · Ventas/Tareas/t-0003-"))
        #expect(tarea.responsable == "Manu" && tarea.estado == .porHacer)
        #expect(tarea.planificada?.description == "2026-10-20")
        let fm = c.lectura().ficha(tarea.ruta)!
        #expect(fm.texto("contacto") == "[[rosa-llop|Rosa Llop]]" && fm.texto("capacidad") == "VEN-04" && fm.texto("creada_por") == "sistema")
        // Un contacto importado (con `fecha_corte`) no dispara nada.
        let importado = try PlantillaMotor(snapshot: c.foto()).preparar(.init(plantilla: "contacto", valores: ["titulo": "Pepe Antiguo"],
                                                                              poner: [Property(key: "fecha_corte", value: .text("2026-10-01"))]))
        let ri = try await motor.ejecutar(importado.plan)
        #expect(ri.eventos.isEmpty)
        #expect(c.tareas().filter { $0.origen == "regla:contacto.creado" }.count == 1)
    }

    @Test("conversacion.cualificada da de alta empresa y contacto, y la cadena prepara su diagnóstico")
    func conversacionCualificada() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let conv = VaultPath("5 · Marca/Conversaciones/linkedin-pedro-llorens.md")
        let r = try await motor.ejecutar(.cambiarPropiedades(conv, poner: [Property(key: "estado", value: .text("Cualificada"))], quitar: []),
                                         autor: .persona("Manu"))
        #expect(r.eventos.map(\.tipo) == [.conversacionCualificada])
        #expect(r.reglas.filter(\.escribio).map(\.regla) == ["MAR-07·contacto", "VEN-04·diagnostico"])
        let l = c.lectura()
        let contacto = try #require(l.fichas(.contact).first { $0.nombre == "Pedro Llorens" })
        let empresa = try #require(l.fichas(.organization).first { $0.nombre == "Pedro Llorens" })
        #expect(l.relacion(contacto, "empresa") == empresa.ruta)
        #expect(l.relacion(contacto, "conversacion") == conv)
        #expect(contacto.texto("origen") == "regla:conversacion.cualificada" && contacto.texto("canal") == "linkedin")
        #expect(l.relacion(l.ficha(conv)!, "contacto") == contacto.ruta)
        #expect(c.tareas().contains { $0.titulo == "Preparar diagnóstico de Pedro Llorens" })
        // Una conversación que ya tiene contacto no crea otro.
        let lucuma = VaultPath("5 · Marca/Conversaciones/instagram-lucuma-estudio.md")
        try c.escribir(lucuma, c.texto(lucuma).replacingOccurrences(of: "estado: Cualificada", with: "estado: Nueva"))
        let r2 = try await motor.ejecutar(.cambiarPropiedades(lucuma, poner: [Property(key: "estado", value: .text("Cualificada"))], quitar: []),
                                          autor: .persona("Manu"))
        #expect(r2.reglas.map(\.resultado) == [.nada("La conversación ya tiene su contacto.")])
    }

    @Test("proyecto.cerrado deja testimonio y caso para Marca como idea")
    func proyectoCerrado() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        _ = try await motor.ejecutar(A.confirmarCobroJorge())
        let proyecto = try #require(c.proyectos().first)
        let r = try await motor.ejecutar(.cambiarPropiedades(proyecto, poner: [Property(key: "estado", value: .text("Cerrado"))], quitar: []),
                                         autor: .persona("Manu"))
        #expect(r.eventos.map(\.tipo) == [.proyectoCerrado])
        let contenidos = c.lectura().que(apuntan: proyecto, por: "proyecto", tipo: .content)
        #expect(Set(contenidos.map { $0.texto("titulo") ?? "" }) == ["Testimonio de Talleres Martín e Hijos SL", "Caso: Talleres Martín e Hijos SL · Trimestrales"])
        #expect(contenidos.allSatisfy { $0.estado == "Idea" && $0.ruta.raw.hasPrefix("5 · Marca/Contenidos/") })
    }

    @Test("oportunidad.aceptada prepara factura y contrato en borrador; al ganarla no se repiten")
    func aceptadaPreparaBorradores() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let r = try await motor.ejecutar(.cambiarPropiedades(A.opoSergio, poner: [Property(key: "estado", value: .text("Aceptada"))], quitar: []),
                                         autor: .persona("Manu"))
        #expect(r.reglas.filter(\.escribio).map(\.regla) == ["FIN-02·factura·oportunidad.aceptada", "FIN-10·contrato·oportunidad.aceptada"])
        let l = c.lectura()
        let factura = try #require(l.que(apuntan: A.opoSergio, por: "oportunidad", tipo: .invoice).first)
        #expect(factura.ruta == VaultPath("4 · Finanzas/Fiscal/Borradores/arquitectura-nexo-2026-10-19.md"))
        #expect(factura.estado == "Borrador" && factura.texto("numero") == nil)
        // La línea sale de la Oferta (150,00 €), sin inventar totales.
        let texto = c.texto(factura.ruta)
        #expect(texto.contains("| Trimestrales | 1 | 150,00 € |"))
        #expect(!texto.contains("| 0,00 €") && !texto.contains(" 0 €"))
        // Se cobra (la persona confirma un cobro de esa factura): Ganada y proyecto, sin otra factura ni otro contrato.
        let plan = WritePlan(autor: .persona("Manu"), descripcion: "Cobro", ops: [
            .upsertCSVRow(A.pagos, row: ["id": "PAG-20261019-009", "fecha": "2026-10-19", "direccion": "cobro", "importe": "181.50",
                                         "moneda": "EUR", "documento_id": try #require(factura.uid), "proyecto_id": "",
                                         "tercero": "Arquitectura Nexo SLP", "metodo": "transferencia", "evidencia": "x",
                                         "verificacion": "confirmado"], key: "id"),
        ])
        let cobro = try await motor.ejecutar(plan)
        #expect(cobro.reglas.filter(\.escribio).map(\.regla) == ["VEN-07·ganada", "ENT-02·tareas"])
        let despues = c.lectura()
        #expect(despues.ficha(A.opoSergio)?.estado == "Ganada")
        #expect(despues.que(apuntan: A.opoSergio, por: "oportunidad", tipo: .invoice).count == 1)
        #expect(despues.que(apuntan: A.opoSergio, por: "oportunidad", tipo: .agreement).count == 1)
        #expect(despues.proyectosDeEntrega(de: A.opoSergio).count == 1)
    }

    // MARK: Profundidad, importación, funciones en manos de una persona y guarda

    @Test("Una cadena tiene como mucho 3 pasos: lo que sale del tercero se guarda y no dispara nada")
    func profundidadMaxima() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        // Una regla que se llama a sí misma: cada contacto nuevo crea otro.
        let eco = Regla(id: "PRUEBA·eco", evento: .contactoCreado, capacidad: "VEN-99", nombre: "Eco") { ctx in
            let n = (ctx.evento.carga["nombre"] ?? "x") + " bis"
            let nota = try PlantillaMotor(snapshot: ctx.lectura.snapshot, opciones: .init(yo: "sistema", reloj: ctx.lectura.reloj))
                .preparar(.init(plantilla: "contacto", valores: ["titulo": n], autor: .sistema))
            return .plan(nota.plan, resumen: n)
        }
        let motor = try await c.motor(.init(reglas: [eco]))
        let nota = try PlantillaMotor(snapshot: c.foto()).preparar(.init(plantilla: "contacto", valores: ["titulo": "Ana"]))
        let r = try await motor.ejecutar(nota.plan)
        #expect(r.reglas.filter(\.escribio).count == 3)
        let nombres = Set(c.lectura().fichas(.contact).map(\.nombre))
        #expect(nombres.isSuperset(of: ["Ana", "Ana bis", "Ana bis bis", "Ana bis bis bis"]))
        #expect(!nombres.contains("Ana bis bis bis bis"))
        let ultimo = try #require(try motor.estado.eventos().first { $0.evento.profundidad == 3 })
        #expect(ultimo.estado == .omitido)
        #expect(ultimo.motivo == "La cadena ya lleva 3 pasos: como mucho son 3.")
    }

    @Test("El modo importación apaga todas las reglas (y no se disparan después)")
    func modoImportacion() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        await motor.setModoImportacion(true)
        let nota = try PlantillaMotor(snapshot: c.foto()).preparar(.init(plantilla: "contacto", valores: ["titulo": "Importada"]))
        let r = try await motor.ejecutar(nota.plan)
        #expect(r.eventos.map(\.tipo) == [.contactoCreado])
        #expect(r.reglas.isEmpty)
        let cobro = try await motor.ejecutar(A.confirmarCobroJorge())
        #expect(cobro.reglas.isEmpty)
        #expect(c.proyectos().isEmpty)
        #expect(try motor.estado.eventos().allSatisfy { $0.estado == .omitido && $0.motivo?.hasPrefix("Importación") == true })
        await motor.setModoImportacion(false)
        #expect(await motor.procesarPendientes().isEmpty)
        #expect(c.tareas().count == 2)
        #expect(c.lectura().ficha(A.opoJorge)?.estado == "Aceptada")
    }

    @Test("Si la función está en «manual» u «off», la regla deja una tarea para una persona")
    func funcionManual() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let config = VaultPath(".tls/config.yaml")
        try c.escribir(config, c.texto(config) + "capacidades:\n  ENT-02: {declarada: si, modo: manual, ejecutor: persona}\n  FIN-10: {modo: \"off\"}\n")
        let motor = try await c.motor()
        let r = try await motor.ejecutar(A.confirmarCobroJorge())
        let proyecto = try #require(c.proyectos().first)
        let carpeta = proyecto.parent!
        #expect(c.tareas().filter { $0.ruta.isDescendant(of: carpeta) }.isEmpty)
        let tareas = c.tareas().filter { $0.origen == "regla:proyecto.creado" || $0.origen == "regla:oportunidad.ganada" }
        #expect(Set(tareas.map(\.titulo)) == ["Crear las tareas del plan de entrega de «Talleres Martín e Hijos SL · Trimestrales»",
                                             "Preparar el contrato de «Jorge Martín · Trimestrales»"])
        #expect(tareas.allSatisfy { $0.responsable == "Manu" && $0.estado == .porHacer })
        #expect(r.reglas.contains { if case .tareaParaPersona = $0.resultado { return $0.regla == "ENT-02·tareas" } else { return false } })
        #expect(!c.existe(VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales/Contrato.md")))
    }

    @Test("Una regla nunca confirma cobros ni emite: la guarda la bloquea y lo apunta")
    func guardaDeReglas() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let tramposa = Regla(id: "PRUEBA·emite", evento: .contactoCreado, capacidad: "FIN-02", nombre: "Emite") { _ in
            .plan(WritePlan(autor: .sistema, descripcion: "x",
                            ops: [.mergeFrontmatter(A.facturaJorge, set: [Property(key: "estado", value: .text("Cobrada"))], unset: [])]),
                  resumen: "x")
        }
        let cobradora = Regla(id: "PRUEBA·cobra", evento: .contactoCreado, capacidad: "FIN-05", nombre: "Cobra") { _ in
            .plan(WritePlan(autor: .sistema, descripcion: "x", ops: [.upsertCSVRow(A.pagos, row: A.filaCobroJorge(), key: "id")]), resumen: "x")
        }
        let motor = try await c.motor(.init(reglas: [tramposa, cobradora]))
        let antes = c.huella()
        let nota = try PlantillaMotor(snapshot: c.foto()).preparar(.init(plantilla: "contacto", valores: ["titulo": "Quien sea"]))
        let r = try await motor.ejecutar(nota.plan)
        #expect(r.reglas.map(\.resultado) == [
            .bloqueado("Una regla no emite facturas: «f-2026-0007» se queda en borrador hasta que lo revise una persona."),
            .bloqueado("Una regla no confirma cobros: «pagos» lo confirma siempre una persona."),
        ])
        var despues = c.huella()
        despues = despues.filter { antes[$0.key] != nil }
        #expect(despues == antes)
        #expect(try motor.estado.reglasAplicadas().map(\.resultado).allSatisfy { $0.hasPrefix("bloqueado: ") })
    }

    @Test("Un fallo de una regla deja el evento pendiente y se reintenta")
    func reintento() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let falla = Caja(true)
        let fragil = Regla(id: "PRUEBA·fragil", evento: .contactoCreado, capacidad: "VEN-04", nombre: "Frágil") { ctx in
            if falla.value { throw WriteError.cambioExterno("x") }
            return .nada("bien")
        }
        let motor = try await c.motor(.init(reglas: [fragil]))
        let nota = try PlantillaMotor(snapshot: c.foto()).preparar(.init(plantilla: "contacto", valores: ["titulo": "Luz"]))
        let r = try await motor.ejecutar(nota.plan)
        #expect(r.reglas.count == 1)
        if case .fallido = r.reglas[0].resultado {} else { Issue.record("Debía fallar") }
        #expect(try motor.estado.eventos().first?.estado == .fallido)
        falla.value = false
        let otra = await motor.procesarPendientes()
        #expect(otra.map(\.resultado) == [.nada("bien")])
        #expect(try motor.estado.eventos().first?.estado == .procesado)
    }

    @Test("Lo privado no dispara reglas: nada suyo sale a una tarea, un proyecto ni una tarjeta")
    func privadoNoDispara() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let config = VaultPath(".tls/config.yaml")
        try c.escribir(config, c.texto(config).replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Trámites/Expediente privado\"]"))
        let motor = try await c.motor()
        let ruta = VaultPath("4 · Finanzas/Trámites/Expediente privado/persona-del-tramite.md")
        let r = try await motor.ejecutar(WritePlan(autor: .persona("Manu"), descripcion: "x", ops: [
            .create(ruta, text: "---\ntls_type: contact\nnombre: Persona del trámite\n---\n# Persona del trámite\n"),
        ]))
        #expect(r.escritura.hecho)
        #expect(r.eventos.isEmpty && r.reglas.isEmpty)
        #expect(!c.tareas().contains { $0.titulo.contains("Persona del trámite") })
    }

    @Test("Los textos del dominio (reglas, eventos, errores y motivos) no usan jerga")
    func textosSinJerga() {
        var textos = ReglasDeSerie.todas.map(\.nombre) + TipoEvento.allCases.map(\.etiqueta)
        textos += [DecisionError.sinTexto, .noEncontrada("x"), .yaSustituida("x"), .sinRegistro].map(\.localizedDescription)
        textos += [GuardaDeReglas.Motivo.cobro("x"), .emision("x"), .salida("x")].map(\.localizedDescription)
        textos += TarjetaDecision.Tipo.allCases.map(\.grupo)
        textos += ["Importación: lo importado no dispara reglas.", "La cadena ya lleva 3 pasos: como mucho son 3."]
        for t in textos { #expect(A.conJerga(t).isEmpty, "«\(t)»") }
    }

    // MARK: Eventos

    @Test("Los eventos salen del antes y el después de cada fichero")
    func eventosDeducidos() throws {
        let layout = VaultSnapshot.read(root: A.ribera).layout
        let d = EventDeriver(layout: layout)
        let opo = try String(contentsOf: A.opoJorge.url(in: A.ribera), encoding: .utf8)
        let ganada = opo.replacingOccurrences(of: "estado: Aceptada", with: "estado: Ganada")
        #expect(d.derivar([CambioAplicado(ruta: A.opoJorge, antes: opo, despues: ganada)], autor: .sistema).map(\.clave)
                == ["oportunidad.ganada:79f8cc54-0e5c-4f4e-8991-da6ff86d9f6d"])
        // Sin cambio de estado, nada; mover (antes = después) tampoco.
        #expect(d.derivar([CambioAplicado(ruta: A.opoJorge, antes: opo, despues: opo + "\nmás\n")], autor: .sistema).isEmpty)
        // Un proyecto nuevo y uno que se cierra.
        let p = "---\ntls_type: project\nid: P1\nclase: entrega\nestado: En curso\n---\n# P\n"
        let ruta = VaultPath("3 · Entrega/Proyectos/p/Proyecto.md")
        #expect(d.derivar([CambioAplicado(ruta: ruta, antes: nil, despues: p)], autor: .persona("Manu")).map(\.clave) == ["proyecto.creado:p1"])
        #expect(d.derivar([CambioAplicado(ruta: ruta, antes: p, despues: p.replacingOccurrences(of: "En curso", with: "Completado"))],
                          autor: .persona("Manu")).map(\.clave) == ["proyecto.cerrado:p1"])
        // Un extracto nuevo.
        let extracto = VaultPath("4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/Extractos/2026-10-23 extracto.csv")
        #expect(d.derivar([CambioAplicado(ruta: extracto, antes: nil, despues: "a;b\n")], autor: .persona("Manu")).map(\.tipo) == [.extractoImportado])
        // Lo retirado al Archivo no dispara nada.
        #expect(d.derivar([CambioAplicado(ruta: VaultPath("Archivo/3 · Entrega/Proyectos/p/Proyecto.md"), antes: nil, despues: p)],
                          autor: .persona("Manu")).isEmpty)
    }

    @Test("La bandeja de salida no guarda dos veces el mismo evento")
    func outboxIdempotente() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tls-estado-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let estado = try EstadoDominio(directory: dir)
        let e = EventoDominio(tipo: .cobroConfirmado, entidad: "PAG-1", ruta: A.pagos, carga: ["importe": "10.00"], autor: .persona("Manu"))
        #expect(try estado.encolar(e))
        #expect(try !estado.encolar(e))
        #expect(try estado.pendientes().map(\.clave) == ["cobro.confirmado:PAG-1"])
        #expect(try estado.pendientes().first?.carga == ["importe": "10.00"])
        try estado.marcar(e.clave, .procesado)
        #expect(try estado.pendientes().isEmpty)
        #expect(try estado.apuntar("r:1", regla: "r", evento: e.clave, resultado: "hecho", plan: nil))
        #expect(try !estado.apuntar("r:1", regla: "r", evento: e.clave, resultado: "otra vez", plan: nil))
        #expect(try estado.yaAplicada("r:1"))
        // Vuelve a abrir: todo sigue ahí.
        estado.cerrar()
        let otra = try EstadoDominio(directory: dir)
        #expect(try otra.eventos().count == 1 && otra.reglasAplicadas().map(\.resultado) == ["hecho"])
    }
}
