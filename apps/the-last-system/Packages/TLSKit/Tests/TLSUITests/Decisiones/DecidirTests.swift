import Foundation
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Decisiones (PLAN §6.3): la bandeja agrupada, el detalle 1-3-1 y lo que escribe decidir (una línea en
/// `Decisiones.md` con su origen y la tarea cerrada), que se deshace dejando los mismos bytes.
@Suite("Decisiones · detalle 1-3-1, decidir en Decisiones.md y deshacer", .serialized)
@MainActor
struct DecidirTests {
    static func lineas(_ texto: String) -> [String] { texto.components(separatedBy: "\n") }

    @Test("Decidir con tus palabras (sin opciones): una línea en Decisiones.md con su origen y la tarea Hecha; deshacer deja los mismos bytes")
    func decidirSinOpciones() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let d = c.hoy()
        let t = try #require(d.decisiones.first { $0.titulo.hasPrefix("¿Subir Trimestrales") })
        #expect(t.tipo == .propuesta)
        #expect(t.opciones.isEmpty)
        let antes = c.huella()
        let registroAntes = c.texto(HoyApoyo.registro)

        let (plan, id) = try AccionesDecision.planDecidir(t, decision: "Sí, a 165 € desde T1 2027 para clientes nuevos",
                                                          porque: "El margen no aguanta 150 €", opcion: nil, foto: c.foto(),
                                                          reloj: HoyApoyo.reloj(), persona: "Manu")
        #expect(plan.autor == .persona("Manu"))
        let bus = try await c.bus()
        _ = try await bus.ejecutar(plan)

        let registro = c.texto(HoyApoyo.registro)
        let nuevas = Self.lineas(registro).filter { !Self.lineas(registroAntes).contains($0) }
        #expect(nuevas.count == 1)
        let linea = try #require(nuevas.first)
        #expect(linea.hasPrefix("- 2026-10-19 · Sí, a 165 € desde T1 2027 para clientes nuevos · El margen no aguanta 150 € · Dirección · "))
        #expect(linea.contains("[¿Subir Trimestrales a 165 € desde T1 2027? (T-0001)](Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md)"))
        #expect(linea.contains("<!-- tls:decision {\"id\":\"\(id)\",\"origen\":\"app\"} -->"))
        // Solo se añadió esa línea (en «## 2026»): lo de antes sigue igual, byte a byte.
        #expect(registro.replacingOccurrences(of: linea + "\n", with: "") == registroAntes)
        let leido = RegistroDecisiones.leer(registro)
        #expect(leido.linea(id: id)?.area == "Dirección")

        let tarea = c.texto(HoyApoyo.t1)
        #expect(tarea.contains("estado: Hecha"))
        #expect(tarea.contains("cerrada: 2026-10-19"))
        #expect(tarea.contains("Estado: En revisión → Hecha. Decidido: Sí, a 165 € desde T1 2027 para clientes nuevos. Queda en el registro de decisiones."))
        // Sale de la bandeja.
        #expect(!c.hoy().decisiones.contains { $0.id == t.id })

        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.huella() == antes)
    }

    @Test("Una 1-3-1 con sus opciones: la recomendada y su porqué, las evidencias enlazadas; decidir la 2 la apunta en su área")
    func decidirConOpciones() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let (ruta, texto) = HoyApoyo.decision131(7, titulo: "¿Cómo retomamos a Jorge Martín?", area: "2 · Ventas")
        c.escribir(ruta, texto)
        let d = c.hoy()
        let t = try #require(d.decisiones.first { $0.ruta == VaultPath(ruta) })
        #expect(t.opciones.map(\.texto) == ["Llamarle el lunes", "Escribirle un correo", "Esperar a que conteste"])
        #expect(t.recomendada?.numero == 1)
        #expect(t.porque == "Es el que más rápido responde por teléfono.")
        let det = try #require(d.detalles[t.id])
        #expect(det.evidencias.map(\.titulo) == ["Jorge Martín", "Jorge Martín · Trimestrales"])
        #expect(det.quien == "Una decisión tuya")
        #expect(det.desde == "hoy")
        #expect(det.siSePospone == "Sigue esperando. A los 14 días sin decidir se pone en rojo (le quedan 14).")
        #expect(det.motivoNoDecidir == nil)
        #expect(Destino.decision(de: VaultPath(ruta)).rutaDeDecision == VaultPath(ruta))
        guard case .decision(let idDestino) = Decidir.destino(t) else { Issue.record("No es una decisión"); return }
        #expect(DecisionDetalle.buscar(idDestino, en: d)?.tarjeta.id == t.id)

        let antes = c.huella()
        let o = t.opciones[1]
        let (plan, _) = try AccionesDecision.planDecidir(t, decision: o.texto, porque: nil, opcion: o, foto: c.foto(),
                                                         reloj: HoyApoyo.reloj(), persona: "Manu")
        let bus = try await c.bus()
        _ = try await bus.ejecutar(plan)
        let registro = c.texto(HoyApoyo.registro)
        let linea = try #require(Self.lineas(registro).first { $0.contains("Escribirle un correo") })
        #expect(linea.hasPrefix("- 2026-10-19 · Escribirle un correo · — · Ventas · [¿Cómo retomamos a Jorge Martín? (T-0007)](../2%20·%20Ventas/Tareas/t-0007-decision-7.md)"))
        #expect(c.texto(ruta).contains("Decidido (opción 2): Escribirle un correo."))
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.huella() == antes)
    }

    @Test("Responder una pregunta la cierra con tu respuesta; no va al registro de decisiones")
    func responderPregunta() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let ruta = "2 · Ventas/Tareas/t-0010-pregunta.md"
        c.escribir(ruta, """
        ---
        tls_type: task
        tls_schema: 1
        id: pregunta-10
        numero: T-0010
        titulo: ¿A qué hora llamo a Sergio?
        estado: En revisión
        tipo: pregunta
        creada: 2026-10-18
        ---
        # ¿A qué hora llamo a Sergio?

        ## Pregunta
        Sergio pidió que le llamáramos esta semana: ¿mañana o tarde?

        ## Lo que propongo
        Mañana a las 10:00.

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        """)
        let d = c.hoy()
        let t = try #require(d.decisiones.first { $0.ruta == VaultPath(ruta) })
        #expect(t.tipo == .pregunta)
        #expect(t.problema == "Sergio pidió que le llamáramos esta semana: ¿mañana o tarde?")
        #expect(t.porque == "Mañana a las 10:00.")
        #expect(d.detalles[t.id]?.desde == "desde ayer")
        let registro = c.datos(HoyApoyo.registro)
        let plan = try AccionesDecision.planResponder(t, respuesta: "Mañana a las 10:00", foto: c.foto(), reloj: HoyApoyo.reloj(), persona: "Manu")
        let bus = try await c.bus()
        _ = try await bus.ejecutar(plan)
        #expect(c.texto(ruta).contains("estado: Hecha"))
        #expect(c.texto(ruta).contains("Respuesta: Mañana a las 10:00"))
        #expect(c.datos(HoyApoyo.registro) == registro)
        #expect(throws: ErrorDecision.sinTexto) {
            try AccionesDecision.planResponder(t, respuesta: "  ", foto: c.foto(), reloj: HoyApoyo.reloj(), persona: "Manu")
        }
    }

    @Test("Descartar deja la tarea Cancelada con el motivo; no toca el registro")
    func descartar() async throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let t = try #require(c.hoy().decisiones.first { $0.titulo.hasPrefix("¿Dejar que Comercial") })
        let registro = c.datos(HoyApoyo.registro)
        let plan = try AccionesDecision.planDescartar(t, motivo: "Lo veremos con los asistentes", foto: c.foto(),
                                                      reloj: HoyApoyo.reloj(), persona: "Manu")
        let bus = try await c.bus()
        _ = try await bus.ejecutar(plan)
        #expect(c.texto(HoyApoyo.t2).contains("estado: Cancelada"))
        #expect(c.texto(HoyApoyo.t2).contains("Descartada: Lo veremos con los asistentes."))
        #expect(c.datos(HoyApoyo.registro) == registro)
    }

    @Test("«Para aprobar» sin petición de aprobación (un borrador escrito a mano): se ve, se revisa en su ficha y aquí no se escribe nada")
    func paraAprobar() throws {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let ruta = "2 · Ventas/Borradores/seguimiento-jorge.md"
        c.escribir(ruta, """
        ---
        tls_type: draft
        tls_schema: 1
        id: borrador-1
        tipo: correo
        accion: enviar_correo
        asunto: Seguimiento de la propuesta a Jorge
        creado_por: agente:comercial
        estado: Pendiente de tu OK
        creada: 2026-10-19
        ---
        # Seguimiento de la propuesta a Jorge

        """)
        let d = c.hoy()
        let t = try #require(d.decisiones.first { $0.tipo == .paraAprobar })
        let det = try #require(d.detalles[t.id])
        // F4 · rol mika: lo que pide aprobar un asistente va por su registro de aprobaciones (DecisionesF4Tests); un
        // borrador «Pendiente de tu OK» sin petición no se aprueba aquí.
        // F5 · corrector (P1-1): un correo de un asistente sin petición se prepara para aprobar aquí («Revisar y aprobar…»).
        #expect(det.motivoNoDecidir == nil && det.correoParaPreparar)
        #expect(det.quien == "Lo prepara Comercial (asistente)")
        #expect(throws: ErrorDecision.noSeDecideAqui) {
            try AccionesDecision.planDecidir(t, decision: "Enviar", porque: nil, opcion: nil, foto: c.foto(),
                                             reloj: HoyApoyo.reloj(), persona: "Manu")
        }
    }

    @Test("Archivos en conflicto entran en su grupo con sus opciones (y la recomendada)")
    func conflictos() {
        let c = HoyApoyo.ribera()
        defer { c.limpiar() }
        let r = ConflictRecord(tipo: .duplicado, ruta: VaultPath("2 · Ventas/Contactos/jorge-martin.md"),
                               otraRuta: VaultPath("2 · Ventas/Contactos/jorge-martin 2.md"),
                               fecha: Date(), titulo: "Jorge Martín está repetido", detalle: "Hay dos fichas con el mismo id.", versiones: [])
        let d = c.hoy(conflictos: [r])
        let t = d.decisiones.first { $0.tipo == .conflicto }
        #expect(t?.opciones.map(\.texto) == ["Apartar el repetido al Archivo", "Quedarme con el repetido"])
        #expect(t?.recomendada?.numero == 1)
        #expect(t.map(Decidir.destino) == .decision("conflicto:" + r.id.uuidString.lowercased()))
        #expect(d.bandeja.grupos.map { $0.tipo } == [.propuesta, .conflicto])
        #expect(d.detalles[t?.id ?? ""]?.evidencias.map(\.ruta) == [VaultPath("2 · Ventas/Contactos/jorge-martin.md")])
    }

    @Test("Desde la sesión: decidir pasa por el dominio, deja el aviso y se deshace con los mismos bytes")
    func desdeLaSesion() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        defer { s.close() }
        let almacen = AlmacenHoy.de(s)
        await almacen.actualizar()
        let copia = HoyApoyo.Copia(base: e.base, root: e.carpeta)
        let antes = copia.huella()
        let t = try #require(almacen.datos?.decisiones.first { $0.titulo.hasPrefix("¿Subir Trimestrales") })
        let ok = await Decidir.decidir(t, opcion: nil, texto: "Mantener 150 € hasta junio", porque: nil, sesion: s)
        #expect(ok)
        #expect(s.aviso?.texto == "Decidido: «Mantener 150 € hasta junio». Queda en el registro de decisiones")
        #expect(copia.texto(HoyApoyo.registro).contains("- 2026-10-19 · Mantener 150 € hasta junio · — · Dirección · [¿Subir Trimestrales a 165 € desde T1 2027? (T-0001)]"))
        #expect(copia.texto(HoyApoyo.t1).contains("estado: Hecha"))
        // La bandeja y la insignia se ponen al día en cuanto se decide (sin esperar al índice).
        #expect(almacen.datos?.decisiones.contains { $0.id == t.id } == false)
        #expect(s.barraLateral.datos[.decisiones]?.insignia == 1)
        // ⌘Z / «Deshacer» del aviso.
        let ultimo = try #require(await s.bus?.ultimoDeshacible())
        await s.deshacer(plan: ultimo.planID)
        #expect(copia.huella().filter { !$0.key.hasPrefix(".tls/") } == antes.filter { !$0.key.hasPrefix(".tls/") })
        #expect(copia.datos(HoyApoyo.registro) == (try? Data(contentsOf: HoyApoyo.riberaRepo.appendingPathComponent(HoyApoyo.registro))))
    }

    @Test("En solo lectura no se decide: la escritura se niega con su motivo")
    func soloLectura() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .bloqueada)
        defer { e.limpiar() }
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        defer { s.close() }
        #expect(!s.puedeEscribir)
        #expect(Decidir.motivoSoloLectura(s) != nil)
        await AlmacenHoy.de(s).actualizar()
        let t = try #require(AlmacenHoy.de(s).datos?.decisiones.first)
        let antes = HoyApoyo.Copia(base: e.base, root: e.carpeta).huella()
        let ok = await Decidir.decidir(t, opcion: nil, texto: "Algo", porque: nil, sesion: s)
        #expect(!ok)
        #expect(HoyApoyo.Copia(base: e.base, root: e.carpeta).huella() == antes)
    }
}
