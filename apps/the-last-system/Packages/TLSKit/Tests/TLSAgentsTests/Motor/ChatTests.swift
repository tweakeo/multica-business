import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// ⌘J: el enrutador de 14 intenciones sin Claude y el chat vivo con un `claude` falso.
@Suite("Motor · chat ⌘J", .serialized)
struct ChatTests {
    @Test("Las 14 intenciones de Programa, en su orden")
    func intenciones() {
        let casos: [(String, Intencion)] = [
            ("¿Qué tengo hoy?", .hoy),
            ("Cómo viene la semana", .semana),
            ("¿Qué llevo atrasado?", .atrasado),
            ("¿Cómo va Talleres Martín?", .cliente),
            ("¿Cómo va el pipeline?", .pipeline),
            ("¿Cómo estamos de caja?", .dinero),
            ("¿Vamos a llegar al objetivo del trimestre?", .ritmo),
            ("¿Qué me frena?", .cuello),
            ("¿Cómo van los proyectos?", .proyectos),
            ("¿Quién lleva qué?", .equipo),
            ("¿Qué toca publicar?", .contenido),
            ("Apunta llamar a la gestoría", .crearTarea),
            ("Mueve preparar la propuesta a mañana", .mover),
            ("Busca Ribera", .buscar),
        ]
        for (texto, esperada) in casos {
            #expect(EnrutadorDeIntenciones.reconocer(texto)?.intencion == esperada, "«\(texto)»")
        }
        #expect(Set(casos.map(\.1)).count == 14)
        #expect(EnrutadorDeIntenciones.reconocer("¿Cómo va Talleres Martín?")?.argumentos["quien"] == "Talleres Martín")
        // Las que escriben ganan: «crea una tarea de seguimiento del cliente X» no es «cliente».
        #expect(EnrutadorDeIntenciones.reconocer("Crea una tarea de seguimiento del cliente Martín")?.intencion == .crearTarea)
        let m = EnrutadorDeIntenciones.reconocer("aplaza revisar el contrato a la semana que viene")
        #expect(m?.argumentos["que"] == "revisar el contrato" && m?.argumentos["cuando"] == "la semana que viene")
        #expect(EnrutadorDeIntenciones.reconocer("hola, qué tal") == nil)
    }

    @Test("Sin Claude: responde con los datos del núcleo y propone en vez de escribir")
    func sinClaude() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        e.tarea(1, titulo: "Preparar propuesta", responsable: "Manu")
        let raiz = e.raiz
        let chat = SesionDeChat(.init(estadoDeCarpeta: e.estadoDir, raiz: e.raiz, claude: nil,
                                      ajustes: AjustesFijos(e.ajustes), catalogo: EntornoMotor.catalogo, reloj: e.reloj,
                                      foto: { VaultSnapshot.read(root: raiz) }))
        let antes = e.leer("2 · Ventas/Tareas/t-0001-preparar-propuesta.md")
        let r = await chat.enviar("Apunta llamar a la gestoría")
        #expect(r.modo == .sinClaude)
        #expect(r.intencion == .crearTarea)
        #expect(r.texto.contains("«llamar a la gestoría»"))
        guard case .crearTarea(let titulo, let dia)? = r.propuesta?.accion else { Issue.record("sin propuesta"); return }
        #expect(titulo == "llamar a la gestoría" && dia.description == "2026-10-19")
        let mover = await chat.enviar("Mueve preparar propuesta a 2026-10-24")
        guard case .moverPlanificada(_, let a)? = mover.propuesta?.accion else { Issue.record("sin propuesta"); return }
        #expect(a.description == "2026-10-26")  // sábado → lunes (ENT-04)
        #expect(mover.texto.contains("fin de semana"))
        let dinero = await chat.enviar("¿cómo estamos de dinero?")
        #expect(dinero.texto.contains("Sin dato"))  // sin banco: nunca un 0 inventado
        let nada = await chat.enviar("hola, qué tal")
        #expect(nada.filas.count == 14)
        // Nada se escribió.
        #expect(e.leer("2 · Ventas/Tareas/t-0001-preparar-propuesta.md") == antes)
        // Lo privado no sale en la búsqueda.
        let busca = await chat.enviar("busca expediente")
        #expect(busca.filas.isEmpty)
    }

    @Test("En Ribera, ¿cómo estamos de dinero? da las cifras de verdad")
    func ribera() throws {
        let ribera = Apoyo.repo.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera")
        guard FileManager.default.fileExists(atPath: ribera.path) else { return }
        let snapshot = VaultSnapshot.read(root: ribera)
        let reloj = Reloj(hoy: LocalDate(year: 2026, month: 10, day: 19)!, ahora: EntornoMotor.lunes9,
                          zona: TimeZone(identifier: "Europe/Madrid")!)
        let r = RespuestasSinClaude(snapshot: snapshot, reloj: reloj)
        let dinero = r.responder("¿Cómo estamos de dinero?")
        #expect(dinero.texto.contains("26.664"))
        #expect(dinero.ir == "area:FIN")
        let ventas = r.responder("¿Cómo van las oportunidades?")
        #expect(ventas.intencion == .pipeline)
        #expect(!ventas.filas.isEmpty)
    }

    @Test("Con Claude: proceso vivo con la entrada abierta, dos turnos y cierre por inactividad")
    func conClaude() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        // Claude falso conversacional: un `result` por cada mensaje que le llega.
        let guion = """
        #!/bin/sh
        D='\(e.claude.dir.path)'
        printf '%s\\n' "$@" > "$D/argv-chat.txt"
        echo '\(Flujo.inicio(sesion: "chat"))'
        N=0
        while IFS= read -r L; do
          N=$((N+1))
          echo "$L" >> "$D/entrada-chat.txt"
          echo '{"type":"assistant","session_id":"chat","message":{"role":"assistant","content":[{"type":"text","text":"Respuesta '$N'"}]}}'
          echo '{"type":"result","subtype":"success","is_error":false,"result":"Respuesta '$N'","total_cost_usd":0.0'$N',"session_id":"chat"}'
        done
        echo fin > "$D/fin-chat.txt"

        """
        let bin = e.claude.dir.appendingPathComponent("claude-chat")
        try Data(guion.utf8).write(to: bin)
        chmod(bin.path, 0o755)
        let runtime = ClaudeCodeRuntime(claude: bin, help: EntornoMotor.help, home: Apoyo.home)
        let raiz = e.raiz
        let estado = try e.estado()
        let chat = SesionDeChat(.init(estadoDeCarpeta: e.estadoDir, raiz: e.raiz, claude: runtime, puerta: e.puerta,
                                      ajustes: AjustesFijos(e.ajustes), catalogo: EntornoMotor.catalogo, reloj: e.reloj,
                                      foto: { VaultSnapshot.read(root: raiz) }, estado: estado, inactividad: 1.5))
        let uno = await chat.enviar("¿Qué hay en rojo?", pantalla: "Hoy")
        #expect(uno.modo == .claude && uno.texto == "Respuesta 1")
        let dos = await chat.enviar("¿Y en Ventas?")
        #expect(dos.texto == "Respuesta 2")
        #expect(await chat.vivo)
        let entrada = e.claude.texto("entrada-chat.txt")
        #expect(entrada.contains("Lo que tiene en pantalla: Hoy"))
        #expect(entrada.contains("¿Y en Ventas?"))
        #expect(e.claude.texto("argv-chat.txt").contains("--session-id"))
        #expect(e.puerta.abiertas.first?.origen?.hasPrefix("chat:") == true)
        // Tras la inactividad se cierra la entrada, el proceso termina y se revoca el token.
        #expect(await esperarA(10) { e.claude.texto("fin-chat.txt") == "fin\n" })
        #expect(await esperarA(5) { await !chat.vivo })
        #expect(await esperarA(5) { e.puerta.revocadas.count == 1 })
        // El uso del chat cuenta en el mes.
        #expect(CostLedger(estado: estado, reloj: e.reloj, zona: e.zona).usado(agente: "mika") > 0)
    }

    @Test("Demo sin Claude: el chat reproduce la grabación de Mika, marcada «Simulado»")
    func chatSimulado() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        let dir = Apoyo.tempDir("tls-grabaciones-chat")
        defer { Apoyo.limpiar(dir) }
        let lineas = [Flujo.inicio(sesion: "s"), Flujo.texto("Hoy tienes poco: {{mensaje}}"),
                      Flujo.herramienta("tls_finalizar", id: "f", entrada: ["resumen": "Hoy, nada urgente."]),
                      Flujo.resultadoHerramienta(id: "f", texto: "{}"), Flujo.resultado("ok")]
        try Data((lineas.joined(separator: "\n") + "\n").replacingOccurrences(of: "__SESION__", with: "s").utf8)
            .write(to: dir.appendingPathComponent("mika-chat.jsonl"))
        let raiz = e.raiz
        let chat = SesionDeChat(.init(estadoDeCarpeta: e.estadoDir, raiz: e.raiz, claude: nil, puerta: e.puerta,
                                      ajustes: AjustesFijos(e.ajustes), catalogo: EntornoMotor.catalogo, reloj: e.reloj,
                                      foto: { VaultSnapshot.read(root: raiz) },
                                      simulacion: SimulatedRuntime(grabaciones: dir, servidor: e.puerta)))
        let r = await chat.enviar("¿Qué tengo hoy?")
        #expect(r.simulado && r.texto == "Hoy, nada urgente.")
        #expect(e.puerta.abiertas.first?.simulado == true)
        #expect(e.puerta.revocadas.count == 1)
    }

    @Test("Con el interruptor apagado el chat contesta sin Claude")
    func chatConInterruptorApagado() async throws {
        let e = EntornoMotor()
        defer { e.limpiar() }
        var a = e.ajustes
        a.interruptor = false
        let raiz = e.raiz
        let chat = SesionDeChat(.init(estadoDeCarpeta: e.estadoDir, raiz: e.raiz, claude: e.runtime(),
                                      ajustes: AjustesFijos(a), catalogo: EntornoMotor.catalogo, reloj: e.reloj,
                                      foto: { VaultSnapshot.read(root: raiz) }))
        let r = await chat.enviar("¿Qué tengo hoy?")
        #expect(r.modo == .sinClaude)
        #expect(e.claude.llamadas == 0)
    }
}
