import Foundation
import Testing
import TLSAgents
import TLSCore
@testable import TLSUI

/// ⌘J con Mika (PLAN §6.1, §5.3 «Chat»): el contexto de la pantalla, sin nada privado; el enrutador sin Claude, que lo
/// dice; la respuesta que se va escribiendo; lo que hizo Mika como tarjetas enlazadas (sale de la auditoría); las
/// acciones rápidas por área; y las propuestas, que aplica la persona. Nunca se lanza Claude.
@Suite("Mika · ⌘J", .serialized)
@MainActor
struct MikaTests {
    @Test("El contexto de la pantalla: «Estás en Ventas › …», la ruta para Mika y nada privado")
    func contexto() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let opo = VaultPath("2 · Ventas/Oportunidades/javier-ortega-renta.md")
        let c = ContextoPantalla.de(camino: [.area(.ventas), .ficha(opo)], sesion: e.sesion)
        #expect(c.frase.hasPrefix("Estás en Ventas › "))
        #expect(c.area == .ventas && c.ruta == opo)
        #expect(c.paraMika.contains(opo.raw) && c.paraMika.contains("Oportunidad"))
        // Lo privado: ni su nombre ni su ruta, y a Mika ni se le dice que existe.
        e.cambiarFuera(".tls/config.yaml", "privado: []", "privado: [\"1 · Dirección/Expediente privado\"]")
        e.escribirFuera("1 · Dirección/Expediente privado/Nota delicada.md", "# Nota delicada\n\nNada de esto sale.\n")
        try await e.sesion.rebuildIndexForTests(e.entorno.model)
        let privada = VaultPath("1 · Dirección/Expediente privado/Nota delicada.md")
        #expect(e.sesion.esPrivado(privada))
        let p = ContextoPantalla.de(camino: [.area(.direccion), .nota(privada)], sesion: e.sesion)
        #expect(p.frase == "Estás en Dirección › una nota privada")
        #expect(!p.paraMika.contains("Expediente") && !p.paraMika.contains("delicada") && !p.paraMika.contains("privad"))
        #expect(p.ruta == nil && p.tarea == nil)
        // Sin camino: Hoy.
        #expect(ContextoPantalla.de(nil, sesion: e.sesion).frase == "Estás en Hoy")
    }

    @Test("Acciones rápidas por área: Ventas trae las de Comercial y la de Mika; sin área, también «Revisar cobros»")
    func accionesRapidas() {
        let ventas = ContextoPantalla(frase: "", paraMika: "", area: .ventas, ruta: nil, tarea: nil).accionesRapidas()
        #expect(ventas.map(\.titulo).contains("Preparar seguimiento"))
        #expect(ventas.map(\.titulo).contains("Plan de 4 semanas para el cuello"))
        #expect(ventas.first?.asistente == "comercial")
        let general = ContextoPantalla.general.accionesRapidas()
        #expect(general.map(\.titulo).contains("Plan de 4 semanas para el cuello"))
        #expect(general.contains { $0.titulo.hasPrefix("Revisar cobros") && $0.asistente == "contable" })
        let finanzas = ContextoPantalla(frase: "", paraMika: "", area: .finanzas, ruta: nil, tarea: nil).accionesRapidas()
        #expect(finanzas.first?.titulo == "Revisar cobros pendientes")
        #expect(finanzas.count <= 4)
    }

    @Test("Sin Claude Code contesta el enrutador con datos de la carpeta, y lo dice")
    func sinClaude() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let c = ConversacionMika(sesion: e.sesion)
        c.ritmo = nil
        #expect(c.modo == .sinClaude)
        c.abrir(contexto: .general)
        c.borrador = "¿Cómo estamos de dinero?"
        await c.enviar()
        #expect(c.mensajes.count == 2)
        let r = try #require(c.mensajes.last)
        #expect(r.quien == .mika && r.modo == .sinClaude && !r.completo.isEmpty && r.texto == r.completo)
        #expect(r.ir == .area(.finanzas))
        #expect(c.modo == .sinClaude && c.modo.explicacion.contains("sin inventar nada"))
        #expect(!c.pensando && c.borrador.isEmpty)
        // «Qué tengo hoy» lleva a Hoy.
        await c.enviar("Qué tengo hoy", mostrar: "Qué tengo hoy")
        #expect(c.mensajes.last?.ir == .hoy)
        // Nada escrito en la carpeta.
        #expect(e.asistentes.autorizador.map { (try? $0.estado.auditoria().filter { $0.autor.esAgente }.count) ?? 0 } == 0)
    }

    @Test("Una propuesta del enrutador (apuntar una tarea) la aplica la persona, con su tarjeta enlazada")
    func propuestaDelEnrutador() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let c = ConversacionMika(sesion: e.sesion)
        c.ritmo = nil
        await c.enviar("apunta llamar a la gestoría por el modelo 303", mostrar: "apunta llamar a la gestoría")
        let m = try #require(c.mensajes.last)
        guard case .crearTarea(let titulo, _)? = m.propuesta?.accion else {
            Issue.record("Debía proponer crear una tarea: \(m.completo)")
            return
        }
        #expect(titulo.lowercased().contains("gestoría"))
        let antes = Set(e.foto().notes)
        #expect(await c.aplicar(m.id))
        let hecho = try #require(c.mensajes.last)
        #expect(hecho.propuestaHecha?.hasPrefix("Hecho: tarea creada") == true)
        let tarjeta = try #require(hecho.tarjetas.first)
        #expect(tarjeta.clase == .tarea && tarjeta.etiqueta == "Tarea creada")
        let nueva = try #require(tarjeta.ruta)
        #expect(!antes.contains(nueva) && e.existe(nueva.raw))
        // Como la persona (no un asistente) y se puede deshacer.
        #expect(!e.texto(nueva.raw).contains("agente:"))
        #expect(await c.aplicar(m.id) == false, "una vez")
    }

    @Test("Lo que hace Mika con sus herramientas sale como tarjeta enlazada (de la auditoría, no del texto)")
    func tarjetasDeLaAuditoria() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let escritura = try #require(e.asistentes.escritura)
        let raiz = e.carpeta
        let canal = CanalFalso(respuestas: [RespuestaDeChat(texto: "Hecho: el Comercial te prepara mañana la llamada con Amparo Ribera.",
                                                            modo: .claude)],
                               acciones: [CanalFalso.crearTarea(escritura, titulo: "Preparar la llamada con Amparo Ribera",
                                                                foto: { VaultSnapshot.read(root: raiz) })])
        let c = ConversacionMika(sesion: e.sesion)
        c.ritmo = nil
        c.canalDePrueba = canal
        let opo = VaultPath("2 · Ventas/Oportunidades/amparo-ribera-trimestrales.md")
        c.abrir(contexto: ContextoPantalla.de(camino: [.area(.ventas), .ficha(opo)], sesion: e.sesion))
        await c.enviar("prepárame la llamada con Amparo Ribera", mostrar: "prepárame la llamada con Amparo Ribera")
        // El contexto de la pantalla llega a Mika.
        #expect(canal.recibidos.first?.pantalla?.contains(opo.raw) == true)
        let m = try #require(c.mensajes.last)
        #expect(m.modo == .claude && c.modo == .claude)
        let t = try #require(m.tarjetas.first)
        #expect(t.clase == .tarea && t.etiqueta == "Tarea creada" && t.titulo == "Preparar la llamada con Amparo Ribera")
        #expect(e.existe(try #require(t.ruta).raw))
        // Mika no crea ninguna tarjeta en Decisiones por una tarea interna (criterio F4-1).
        await e.refrescar()
        #expect(e.datos?.bandeja.tarjetas.contains { $0.ruta == t.ruta } == false)
        // Otro chat (otra ejecución) no ve las tarjetas de este.
        let todos: [EstadoGobierno.Apunte] = (try? e.asistentes.autorizador?.estado.auditoria()) ?? []
        let otras = TarjetasEnlazadas.de(todos, ejecucion: "chat-otro",
                                         desde: .distantPast, titulo: { $0.stem }, privado: { _ in false })
        #expect(otras.isEmpty)
    }

    @Test("Las tarjetas enlazadas: cada decisión del Autorizador en palabras, sin repetir y sin lo privado")
    func tarjetasEnPalabras() {
        func apunte(_ accion: String, _ decision: String, _ ruta: String, ejecucion: String = "chat-a-1") -> ApunteDeAsistente {
            ApunteDeAsistente(fecha: Date(), accion: accion, rutas: [VaultPath(ruta)], ejecucion: ejecucion, decision: decision)
        }
        let apuntes = [apunte("leer", "permitido", "a.md"), apunte("tarea.crear", "permitido", "t.md"),
                       apunte("tarea.crear", "permitido", "t.md"), apunte("borrador.preparar", "permitido", "b.md"),
                       apunte("preguntar", "permitido", "p.md"), apunte("externa", "aprobacion_requerida", "b2.md"),
                       apunte("contacto.registrar", "propuesta", "c.md"), apunte("tarea.crear", "no_encontrado", "x.md"),
                       apunte("comentar", "permitido", "secreto.md"), apunte("tarea.crear", "permitido", "otra.md", ejecucion: "chat-b-1")]
        let t = TarjetasEnlazadas.de(apuntes, ejecucion: "chat-a", desde: Date().addingTimeInterval(-60), titulo: { $0.stem },
                                     privado: { $0.raw == "secreto.md" })
        #expect(t.map(\.etiqueta) == ["Tarea creada", "Borrador preparado", "Pregunta para ti", "Pide tu OK", "Propuesta"])
        #expect(t.first { $0.clase == .borrador }?.espera == "No sale nada sin tu OK")
        #expect(t.first { $0.clase == .aprobacion }?.espera?.contains("Para aprobar") == true)
    }

    @Test("La respuesta aparece poco a poco; «Reducir movimiento» (sin ritmo) la enseña de golpe")
    func escribirPocoAPoco() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let largo = String(repeating: "Esto es una respuesta larga de Mika. ", count: 12)
        let c = ConversacionMika(sesion: e.sesion)
        c.canalDePrueba = CanalFalso(respuestas: [RespuestaDeChat(texto: largo, modo: .claude), RespuestaDeChat(texto: largo, modo: .claude)])
        c.ritmo = .milliseconds(5)
        await c.enviar("hola", mostrar: "hola")
        let id = try #require(c.mensajes.last?.id)
        #expect(c.mensajes.last!.escribiendo, "al principio solo se ve una parte")
        // Con la máquina cargada (toda la batería a la vez) el hilo principal va más lento: margen amplio.
        let fin = Date().addingTimeInterval(60)
        while c.mensajes.first(where: { $0.id == id })?.escribiendo == true, Date() < fin { try await Task.sleep(for: .milliseconds(20)) }
        #expect(c.mensajes.last?.texto == largo)
        c.ritmo = nil
        await c.enviar("otra", mostrar: "otra")
        #expect(c.mensajes.last?.texto == largo)
        // Cerrar el panel termina de escribir; empezar otra conversación cierra el chat.
        c.completar()
        await c.nuevaConversacion()
        #expect(c.mensajes.isEmpty)
    }

    @Test("Una acción rápida sin el motor se le pregunta a Mika con su texto; abrir desde otro asistente lo dirige a él")
    func accionRapidaSinMotor() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let canal = CanalFalso(respuestas: [RespuestaDeChat(texto: "Te lo preparo.", modo: .claude)])
        let c = ConversacionMika(sesion: e.sesion)
        c.ritmo = nil
        c.canalDePrueba = canal
        c.abrir(contexto: ContextoPantalla(frase: "Estás en Ventas", paraMika: "2 · Ventas", area: .ventas, ruta: nil, tarea: nil))
        let a = try #require(c.accionesRapidas.first { $0.accion == "preparar-seguimiento" })
        await c.pedir(a)
        #expect(c.mensajes.first?.texto == "Preparar seguimiento")
        #expect(canal.recibidos.first?.texto == a.peticion)
        c.borrador = ""
        c.abrir(contexto: .general, para: "comercial")
        #expect(c.borrador == "Para Comercial: ")
        // ⌘J dos veces: abre y cierra.
        c.alternar(contexto: .general)
        #expect(!c.abierto)
        c.alternar(contexto: .general)
        #expect(c.abierto)
    }

    @Test("Los textos de ⌘J no usan jerga (asistente, no agente; sin ejecuciones ni otros nombres técnicos)")
    func textos() {
        var textos = [ModoMika.claude, .simulado, .sinClaude].flatMap { [$0.titulo, $0.explicacion] }
        textos += ["Tarea creada", "Borrador preparado", "Pregunta para ti", "Pide tu OK"]
        for t in textos {
            #expect(GlosarioTests.jerga(t).isEmpty, "«\(t)»")
            #expect(!t.lowercased().contains("agente"), "«\(t)»")
            #expect(!t.contains("USD"), "«\(t)»")
        }
    }
}

extension VaultSession {
    /// Vuelve a leer la estructura y el índice tras cambiar lo privado (solo pruebas).
    func rebuildIndexForTests(_ model: AppModel) async throws {
        await rebuildIndex(using: model)
        let fin = Date().addingTimeInterval(10)
        while !isReady, Date() < fin { try await Task.sleep(for: .milliseconds(50)) }
    }
}
