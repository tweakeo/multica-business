import Foundation
import Testing
@testable import TLSCore

@Suite("Dominio · Decisiones.md y la bandeja de decisiones")
struct DecisionesTests {
    typealias A = DominioApoyo

    // MARK: Decisiones.md

    @Test("Lee las líneas de Ribera con su marcador, sus campos y su área")
    func leeRibera() throws {
        let texto = try String(contentsOf: A.decisiones.url(in: A.ribera), encoding: .utf8)
        let r = RegistroDecisiones.leer(texto)
        #expect(r.lineas.count == 2)
        let precio = r.lineas[0]
        #expect(precio.id == "05803184-b15d-4a8f-99aa-58247c3c806e")
        #expect(precio.fecha?.description == "2026-10-19")
        #expect(precio.decision == "La oferta de Renta pasa de 80 € a 90 € + IVA desde la campaña 2026.")
        #expect(precio.porque == "Más deducciones autonómicas y tiempo medio de 2,1 h por declaración.")
        #expect(precio.area == "Ventas")
        #expect(precio.origen == "[Precio Renta 2026: 90 €](Decisiones/precio-renta-2026-90.md)")
        #expect(precio.marcador["origen"] == "importacion")
        #expect(!precio.sustituida)
        #expect(r.lineas[1].area == "Dirección")
        // La guía de la plantilla (en una cita) y lo que hay en un bloque de código no son decisiones.
        let conGuia = """
        # Decisiones
        > `- AAAA-MM-DD · qué se decide · por qué · alcance · fuente`

        ```
        - 2026-01-01 · Esto es un ejemplo · nada
        ```
        - 2026-10-20 · Sí cuenta · porque sí
        """
        #expect(RegistroDecisiones.leer(conGuia).lineas.map(\.decision) == ["Sí cuenta"])
    }

    @Test("Añadir una decisión solo añade su línea: el resto de bytes no cambia (ida y vuelta)")
    func anadirSinTocarLoAjeno() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let motor = try await c.motor()
        let original = c.texto(A.decisiones)
        let d = NuevaDecision(fecha: LocalDate(year: 2026, month: 10, day: 19)!, decision: "Trimestrales sube a 165 € desde T1 2027",
                              porque: "El margen no da", area: "Ventas", origen: "[[t-0001-subir-trimestrales-a-165-desde-t1-2027|T-0001]]")
        let (plan, id) = try RegistroDecisiones.anadir(d, en: c.foto(), id: "aaaaaaaa-0000-4000-8000-000000000001")
        let r = try await motor.ejecutar(plan)
        #expect(r.eventos.map(\.clave) == ["decision.registrada:aaaaaaaa-0000-4000-8000-000000000001"])
        let linea = "- 2026-10-19 · Trimestrales sube a 165 € desde T1 2027 · El margen no da · Ventas · [[t-0001-subir-trimestrales-a-165-desde-t1-2027|T-0001]] <!-- tls:decision {\"id\":\"aaaaaaaa-0000-4000-8000-000000000001\",\"origen\":\"app\"} -->"
        let nuevo = c.texto(A.decisiones)
        #expect(nuevo == original + linea + "\n")
        // Leer y quitar la línea añadida devuelve exactamente lo que había.
        #expect(nuevo.replacingOccurrences(of: linea + "\n", with: "") == original)
        let leido = RegistroDecisiones.leer(nuevo)
        #expect(leido.lineas.count == 3)
        #expect(leido.linea(id: id)?.decision == "Trimestrales sube a 165 € desde T1 2027")
        // Sin porqué ni área: no se inventa nada y no quedan campos vacíos.
        let corto = try RegistroDecisiones.textoDeLinea(NuevaDecision(fecha: LocalDate(year: 2026, month: 10, day: 20)!, decision: "Solo esto"),
                                                         id: "x")
        #expect(corto == "- 2026-10-20 · Solo esto <!-- tls:decision {\"id\":\"x\",\"origen\":\"app\"} -->")
        // Lo que podría partir la línea o cerrar el comentario se neutraliza.
        let raro = try RegistroDecisiones.textoDeLinea(NuevaDecision(fecha: LocalDate(year: 2026, month: 10, day: 20)!,
                                                                     decision: "A · B\nC -->", porque: nil, area: "Ventas"), id: "y")
        #expect(raro == "- 2026-10-20 · A, B C --› · — · Ventas <!-- tls:decision {\"id\":\"y\",\"origen\":\"app\"} -->")
        #expect(RegistroDecisiones.leer(raro).lineas.first?.area == "Ventas")
        #expect(RegistroDecisiones.leer(raro).lineas.first?.porque == nil)
        #expect(throws: DecisionError.sinTexto) { try RegistroDecisiones.textoDeLinea(NuevaDecision(fecha: d.fecha, decision: "  "), id: "z") }
    }

    @Test("Corregir es sustituir: la vieja solo gana «(sustituida)» y la nueva dice a cuál sustituye")
    func sustituir() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let bus = try await c.bus()
        let original = c.texto(A.decisiones)
        let vieja = "05803184-b15d-4a8f-99aa-58247c3c806e"
        let d = NuevaDecision(fecha: LocalDate(year: 2026, month: 10, day: 19)!, decision: "Renta a 95 € + IVA", porque: "Más trabajo por declaración",
                              area: "Ventas")
        let (plan, id) = try RegistroDecisiones.sustituir(vieja, por: d, en: c.foto(), id: "bbbbbbbb-0000-4000-8000-000000000002")
        _ = try await bus.ejecutar(plan)
        let nuevo = c.texto(A.decisiones)
        let esperado = original.replacingOccurrences(of: "desde la campaña 2026. · Más", with: "desde la campaña 2026. (sustituida) · Más")
            + "- 2026-10-19 · Renta a 95 € + IVA · Más trabajo por declaración · Ventas <!-- tls:decision {\"id\":\"\(id)\",\"origen\":\"app\",\"sustituye\":\"\(vieja)\"} -->\n"
        #expect(nuevo == esperado)
        let r = RegistroDecisiones.leer(nuevo)
        #expect(r.linea(id: vieja)?.sustituida == true)
        #expect(r.linea(id: vieja)?.decision == "La oferta de Renta pasa de 80 € a 90 € + IVA desde la campaña 2026.")
        #expect(r.linea(id: id)?.sustituye == vieja)
        #expect(r.vigentes.count == 2 && !r.vigentes.contains { $0.id == vieja })
        #expect(throws: DecisionError.yaSustituida(vieja)) { try RegistroDecisiones.sustituir(vieja, por: d, en: c.foto()) }
        #expect(throws: DecisionError.noEncontrada("nada")) { try RegistroDecisiones.sustituir("nada", por: d, en: c.foto()) }
        // Deshacer lo deja como estaba.
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.texto(A.decisiones) == original)
    }

    @Test("Las líneas escritas a mano reciben su marcador sin tocar nada más (también con \\r\\n)")
    func marcarSinMarcador() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let bus = try await c.bus()
        let aMano = "- 2026-10-20 · Escrita en Obsidian · porque sí · Marca\r\n"
        let original = c.texto(A.decisiones).replacingOccurrences(of: "\n", with: "\r\n") + aMano + "Una nota suelta.\r\n"
        try c.escribir(A.decisiones, original)
        let plan = try #require(RegistroDecisiones.marcarSinMarcador(en: c.foto()))
        #expect(plan.autor == .sistema)
        _ = try await bus.ejecutar(plan)
        let nuevo = c.texto(A.decisiones)
        let r = RegistroDecisiones.leer(nuevo)
        let marcada = try #require(r.lineas.first { $0.decision == "Escrita en Obsidian" })
        let id = try #require(marcada.id)
        #expect(marcada.marcador["origen"] == "texto")
        let conMarca = "- 2026-10-20 · Escrita en Obsidian · porque sí · Marca <!-- tls:decision {\"id\":\"\(id)\",\"origen\":\"texto\"} -->\r\n"
        #expect(nuevo == original.replacingOccurrences(of: aMano, with: conMarca))
        #expect(RegistroDecisiones.marcarSinMarcador(en: c.foto()) == nil)
    }

    @Test("Sin registro, la primera decisión lo crea con la plantilla")
    func creaElRegistro() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try FileManager.default.removeItem(at: A.decisiones.url(in: c.root))
        let (plan, id) = try RegistroDecisiones.anadir(NuevaDecision(fecha: LocalDate(year: 2026, month: 10, day: 19)!, decision: "Empezamos"),
                                                       en: c.foto(), id: "cccccccc-0000-4000-8000-000000000003")
        guard case .create(let p, let data) = try #require(plan.ops.first) else { Issue.record("Debía crear el registro"); return }
        #expect(p == A.decisiones)
        let texto = String(decoding: data, as: UTF8.self)
        #expect(texto.contains("registro: decisiones"))
        #expect(texto.contains("## 2026\n- 2026-10-19 · Empezamos <!-- tls:decision"))
        #expect(RegistroDecisiones.leer(texto).linea(id: id)?.decision == "Empezamos")
    }

    // MARK: Bandeja

    static let pregunta = VaultPath("2 · Ventas/Tareas/t-0003-que-precio-pongo-a-nexo.md")
    static let textoPregunta = """
    ---
    tls_type: task
    id: 44444444-0000-4000-8000-000000000003
    numero: T-0003
    titulo: ¿Qué precio pongo a Nexo?
    estado: En revisión
    tipo: pregunta
    responsable: Manu
    vence: 2026-10-19
    origen: agente:comercial
    creada: 2026-10-19
    ---
    # ¿Qué precio pongo a Nexo?

    ## Pregunta
    > Guía: una sola pregunta.
    ¿Le mantengo los 150 € de la Oferta?

    ## Lo que propongo
    Mantenerlo: se baja de alcance, no de precio.
    """

    static let propuesta = VaultPath("1 · Dirección/Tareas/t-0004-cambiar-de-banco.md")
    static let textoPropuesta = """
    ---
    tls_type: task
    id: 44444444-0000-4000-8000-000000000004
    numero: T-0004
    titulo: ¿Cambiar de banco?
    estado: En revisión
    tipo: decision
    responsable: Manu
    prioridad: Alta
    creada: 2026-10-18
    ---
    # ¿Cambiar de banco?

    ## Problema
    Las comisiones suben en enero.

    ## Opciones
    | # | Opción | A favor | En contra | Coste o riesgo |
    |---|---|---|---|---|
    | 1 | Quedarnos y negociar | Sin papeleo | Puede no salir | Bajo |
    | 2 | Cambiar (recomendada) | Sin comisiones | Papeleo | Medio |
    | 3 | Abrir una segunda cuenta | | | |

    ## Por qué recomiendo la 2
    Ahorra 240 € al año.
    """

    @Test("La bandeja junta preguntas, propuestas 1-3-1, borradores para aprobar y archivos en conflicto")
    func bandeja() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try c.escribir(Self.pregunta, Self.textoPregunta)
        try c.escribir(Self.propuesta, Self.textoPropuesta)
        try c.escribir(VaultPath("2 · Ventas/Borradores/seguimiento-nexo.md"), """
        ---
        tls_type: draft
        id: 55555555-0000-4000-8000-000000000001
        tipo: correo
        accion: enviar_correo
        estado: Pendiente de tu OK
        asunto: Seguimiento de la propuesta
        creado_por: agente:comercial
        creada: 2026-10-19
        ---
        # Seguimiento de la propuesta
        """)
        // Una tarea de un asistente, una cerrada y una privada no entran.
        try c.escribir(VaultPath("2 · Ventas/Tareas/t-0005-para-el-asistente.md"),
                       Self.textoPregunta.replacingOccurrences(of: "responsable: Manu", with: "responsable: agente:comercial"))
        try c.escribir(VaultPath("2 · Ventas/Tareas/t-0006-cerrada.md"),
                       Self.textoPregunta.replacingOccurrences(of: "En revisión", with: "Hecha"))
        let privada = VaultPath("4 · Finanzas/Trámites/Expediente privado/Tareas/t-0007-privada.md")
        try c.escribir(privada, Self.textoPregunta)
        try c.escribir(VaultPath(".tls/config.yaml"),
                       c.texto(VaultPath(".tls/config.yaml")).replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Trámites/Expediente privado\"]"))
        let conflicto = ConflictRecord(tipo: .edicion, ruta: VaultPath("2 · Ventas/Productos/Oferta.md"),
                                       fecha: LocalDate(year: 2026, month: 10, day: 19)!.date(), titulo: "La Oferta cambió fuera mientras la editabas",
                                       detalle: "Elige con qué versión te quedas.", versiones: [])
        let conflictoPrivado = ConflictRecord(tipo: .edicion, ruta: privada, titulo: "x", detalle: "x", versiones: [])
        let l = c.lectura()
        #expect(l.layout.isPrivate(privada))
        let b = BandejaDeDecisiones.consultar(l, conflictos: [conflicto, conflictoPrivado], persona: "Manu")
        #expect(b.tarjetas.count == 6)
        #expect(!b.tarjetas.contains { $0.ruta.map(l.layout.isPrivate) == true })
        #expect(b.grupos.map(\.tipo.grupo) == ["Para aprobar", "Preguntas", "Por decidir", "Archivos en conflicto"])
        // La pregunta vence hoy: roja y la primera.
        let primera = try #require(b.tarjetas.first)
        #expect(primera.tipo == .pregunta && primera.prioridad == .roja && primera.motivo == "Vence hoy")
        #expect(primera.problema == "¿Le mantengo los 150 € de la Oferta?")
        #expect(primera.porque == "Mantenerlo: se baja de alcance, no de precio.")
        // La propuesta 1-3-1: tres opciones, la recomendada es la 2 (con su porqué).
        let p = try #require(b.tarjetas.first { $0.ruta == Self.propuesta })
        #expect(p.prioridad == .alta)
        #expect(p.problema == "Las comisiones suben en enero.")
        #expect(p.opciones.map(\.texto) == ["Quedarnos y negociar", "Cambiar", "Abrir una segunda cuenta"])
        #expect(p.recomendada?.numero == 2 && p.recomendada?.enContra == "Papeleo")
        #expect(p.porque == "Ahorra 240 € al año.")
        // Las de Ribera sin opciones escritas también salen (sin inventar opciones).
        let ribera = try #require(b.tarjetas.first { $0.titulo == "¿Subir Trimestrales a 165 € desde T1 2027?" })
        #expect(ribera.opciones.isEmpty && ribera.tipo == .propuesta)
        // El conflicto, con sus tres salidas y «Combinar» recomendada.
        let conf = try #require(b.tarjetas.first { $0.tipo == .conflicto })
        #expect(conf.conflicto == conflicto.id)
        #expect(conf.opciones.map(\.texto) == ["Combinar las dos", "Quedarme con la mía", "Quedarme con la de fuera"])
        // El borrador, para aprobar.
        #expect(b.tarjetas.first { $0.tipo == .paraAprobar }?.problema == "Enviar un correo")
        for t in b.tarjetas {
            for s in [t.titulo, t.problema ?? "", t.porque ?? "", t.motivo ?? ""] + t.opciones.map(\.texto) {
                #expect(DominioApoyo.conJerga(s).isEmpty, "«\(s)»")
            }
        }
    }

    @Test("Presupuesto: como mucho 5 nuevas al día que no sean rojas; las rojas siempre; el resto al resumen semanal")
    func presupuesto() throws {
        let hoy = LocalDate(year: 2026, month: 10, day: 19)!
        func t(_ n: Int, _ p: TarjetaDecision.Prioridad, _ tipo: TarjetaDecision.Tipo = .propuesta, creada: LocalDate? = hoy) -> TarjetaDecision {
            TarjetaDecision(id: "t\(n)", tipo: tipo, prioridad: p, motivo: nil, titulo: "T\(n)", problema: nil, opciones: [], porque: nil,
                            ruta: nil, conflicto: nil, area: nil, responsable: nil, creada: creada, vence: nil)
        }
        let tarjetas = [t(1, .roja), t(2, .roja)] + (3...9).map { t($0, .normal, $0 % 2 == 0 ? .pregunta : .propuesta) }
            + [t(10, .normal, creada: hoy.adding(days: -1))]
        let b = BandejaDeDecisiones.presupuesto(tarjetas, tope: 5)
        #expect(b.visibles.map(\.id) == ["t1", "t2", "t3", "t4", "t5", "t6", "t7", "t10"])
        #expect(b.alResumen.map(\.id) == ["t8", "t9"])
        #expect(b.resumenPorTipo == [.pregunta: 1, .propuesta: 1])
        #expect(b.pendientes == 8)
        // El tope sale de `.tls/config.yaml` (avisos.tope_tarjetas_dia).
        #expect(ConfigDominio.leer(yaml: "avisos: {tope_tarjetas_dia: 2, tope_notificaciones_no_rojas_dia: 3}\n").topeTarjetasDia == 2)
        #expect(ConfigDominio.leer(yaml: "version: 1\n").topeTarjetasDia == 5)
    }

    @Test("Catorce días sin decidir es rojo (DIR-DEC14)")
    func catorceDias() {
        let hoy = LocalDate(year: 2026, month: 11, day: 2)!
        let (p, m) = BandejaDeDecisiones.prioridad(vence: nil, creada: LocalDate(year: 2026, month: 10, day: 19)!, prioridad: nil, hoy: hoy)
        #expect(p == .roja && m == "Lleva 14 días sin decidir")
        #expect(BandejaDeDecisiones.prioridad(vence: nil, creada: LocalDate(year: 2026, month: 10, day: 20)!, prioridad: nil, hoy: hoy).0 == .normal)
        #expect(BandejaDeDecisiones.prioridad(vence: LocalDate(year: 2026, month: 10, day: 30)!, creada: nil, prioridad: nil, hoy: hoy).1
                == "Venció el 30 oct")
    }
}
