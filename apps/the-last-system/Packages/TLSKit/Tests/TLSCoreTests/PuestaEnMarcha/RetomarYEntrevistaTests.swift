import Foundation
import Testing
@testable import TLSCore

/// Criterio F3-3 («Seguir más tarde», cerrar y abrir: se retoma en la misma pregunta con todas las respuestas), el
/// entrevistador (repregunta una vez; con el asistente solo con consentimiento y nunca con lo privado) y el lint del
/// glosario de los textos del motor (criterio F3-10).
@Suite("Puesta en marcha · retomar, entrevistador y glosario")
struct RetomarYEntrevistaTests {
    @Test("Seguir más tarde, cerrar y abrir: misma pantalla y las mismas respuestas")
    func retomar() async throws {
        let env = PuestaApoyo.g3()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        let id = UUID()
        let ctx = PuestaApoyo.contexto(env, entrada: PuestaApoyo.entradaG3(env))
        var m = PuestaApoyo.motor(ctx, vaultID: id, asup: asup)
        try await PuestaApoyo.recorrer(&m, respuesta: { q in q.id == .camino ? .opcion("soltar") : nil }) { m, paso in
            PuestaApoyo.aplicarSinEscribir(&m, paso)
            if paso == .conocer { m.seguirMasTarde() }
        }
        // Se recorre otra vez hasta la mitad: se para en Organizar, con una respuesta a medias.
        var a = PuestaApoyo.motor(ctx, vaultID: UUID(), asup: asup)
        a.marcarAplicado(.bienvenida, plan: nil, resumen: "Prueba")
        a.ir(a: "conocer.resumen")
        await a.responder(.fraseCliente, .texto("autónomos que facturan menos de cien mil euros"))
        await a.responder(.funciona(.ventas), .noLoSe)
        a.seguirMasTarde()
        let pantalla = a.pantallaActual?.id
        let respuestas = a.estado.respuestas
        #expect(a.estado.enPausa)
        // «Cerrar y abrir»: otro motor con el mismo almacén.
        let b = OnboardingEngine.abrir(vaultID: a.estado.vaultID, contexto: ctx, almacen: a.almacen)
        #expect(b.pantallaActual?.id == pantalla)
        #expect(b.estado.respuestas.mapValues(\.valor) == respuestas.mapValues(\.valor))
        #expect(b.estado.respuestas.mapValues(\.origen) == respuestas.mapValues(\.origen))
        #expect(!b.estado.enPausa)
        #expect(b.respuesta(.funciona(.ventas))?.valor == .noLoSe)
        // El fichero está fuera de la carpeta, en el estado de la app.
        let url = try #require(a.almacen?.url)
        #expect(url.path.hasPrefix(asup.path))
        #expect(!url.path.hasPrefix(env.root.path))
        #expect(url.lastPathComponent == "onboarding.json")
        // El arranque la encuentra y Hoy la recuerda.
        #expect(AlmacenPuesta.pendientes(appSupport: asup).contains { $0.vaultID == a.estado.vaultID })
        let aviso = try #require(PuertaPuestaEnMarcha.avisoDeHoy(vaultID: a.estado.vaultID, appSupport: asup))
        #expect(aviso.texto.hasPrefix("Seguir con la puesta en marcha · paso "))
        // La terminada no sale en pendientes.
        #expect(!AlmacenPuesta.pendientes(appSupport: asup).contains { $0.vaultID == id })
    }

    @Test("El estado se guarda tras cada respuesta")
    func guardaTrasCadaRespuesta() async throws {
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(), asup: asup)
        await m.responder(.como, .opcion("cero"))
        #expect(m.almacen?.leer()?.respuesta(.como)?.valor == .opcion("cero"))
        m.noLoSe(.sector)
        #expect(m.almacen?.leer()?.respuesta(.sector)?.valor == .noLoSe)
        // Un fichero de una versión anterior, sin claves nuevas, se sigue leyendo.
        let minimo = #"{"vault_id":"\#(m.estado.vaultID.uuidString)","respuestas":{}}"#
        try Data(minimo.utf8).write(to: try #require(m.almacen?.url))
        #expect(m.almacen?.leer()?.vaultID == m.estado.vaultID)
    }

    @Test("La copia: la puesta en marcha sigue en la carpeta nueva")
    func registrarCopia() async throws {
        let env = PuestaApoyo.g3()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(), asup: asup)
        await m.responder(.como, .opcion("carpeta"))
        let viejo = try #require(m.almacen?.url)
        m.registrarCopia(PuestaApoyo.entradaG3(env), root: env.root, appSupport: asup)
        #expect(m.estado.vaultID == env.entry.id)
        #expect(m.ruta == .copiaG3)
        #expect(m.estado.paso(.bienvenida).fase == .aplicado)
        #expect(!FileManager.default.fileExists(atPath: viejo.path))
        #expect(AlmacenPuesta(vaultID: env.entry.id, appSupport: asup).leer()?.respuesta(.como)?.valor == .opcion("carpeta"))
    }

    // MARK: Entrevistador

    static func pregunta(_ id: PreguntaID) -> Pregunta {
        OnboardingEngine(estado: EstadoPuestaEnMarcha(), contexto: .vacio()).pregunta(id)!
    }

    @Test("Sin asistente: repregunta una vez si es vaga (lista fija)")
    func determinista() async {
        let destino = Self.pregunta(.destino)
        #expect(InterviewEngine.determinista(destino, respuesta: "crecer") == .repreguntar(destino.repregunta!))
        #expect(InterviewEngine.determinista(destino, respuesta: "Que la empresa vaya mejor y tener más clientes") != .aceptar,
                "Sin un número, la frase destino es vaga")
        #expect(InterviewEngine.determinista(destino, respuesta: "Facturar 200.000 € en 2028 con 30 horas a la semana") == .aceptar)
        let cliente = Self.pregunta(.fraseCliente)
        #expect(InterviewEngine.determinista(cliente, respuesta: "de todo") != .aceptar)
        #expect(InterviewEngine.determinista(cliente, respuesta: "autónomos de Valencia") == .aceptar)
        #expect(InterviewEngine.determinista(Self.pregunta(.camino), respuesta: "x") == .aceptar, "Las elecciones no se repreguntan")

        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(.vacio(), asup: asup)
        let r1 = await m.responder(.destino, .texto("crecer"))
        #expect(r1 == .repreguntar(destino.repregunta!))
        #expect(m.estado.respuesta(.destino)?.repreguntada == true)
        let r2 = await m.responder(.destino, .texto("más"))
        #expect(r2 == .guardada, "Solo se repregunta una vez")
        #expect(m.estado.respuesta(.destino)?.valor == .texto("más"))
    }

    @Test("Con asistente: solo con consentimiento, sin nada privado y, si falla, la lista fija")
    func conAsistente() async {
        let destino = Self.pregunta(.destino)
        let falso = LanzadorFalso(salida: #"{"vaga":true,"repregunta":"¿Cuánto quieres facturar y para cuándo?"}"#)
        let e = InterviewEngine(lanzador: falso)
        // Sin consentimiento no se llama.
        _ = await e.valorar(destino, respuesta: "crecer", conAsistente: false)
        #expect(falso.mensajes.isEmpty)
        // Con consentimiento: su repregunta (una sola llamada, con la pregunta y la respuesta).
        let r = await e.valorar(destino, respuesta: "Facturar 200.000 € en 2028", conAsistente: true)
        #expect(r == .repreguntar("¿Cuánto quieres facturar y para cuándo?"))
        #expect(falso.mensajes.count == 1)
        #expect(falso.mensajes[0].contains("Facturar 200.000 € en 2028"))
        // Si la respuesta nombra una carpeta privada, no sale del Mac.
        _ = await e.valorar(destino, respuesta: "Lo que pone en Expediente privado", conAsistente: true,
                            privado: ["Expediente privado"])
        #expect(falso.mensajes.count == 1)
        // Si el asistente contesta mal, decide la lista fija.
        let roto = InterviewEngine(lanzador: LanzadorFalso(salida: "no es JSON"))
        #expect(await roto.valorar(destino, respuesta: "Facturar 200.000 € en 2028", conAsistente: true) == .aceptar)
        #expect(await roto.valorar(destino, respuesta: "crecer", conAsistente: true) == .repreguntar(destino.repregunta!))
        // El JSON dentro de un texto también se lee.
        #expect(InterviewEngine.leer("Aquí va: {\"vaga\": false}") == ValoracionEntrevista(vaga: false, repregunta: nil))
        // El motor solo usa el asistente si la persona dijo que sí.
        let asup = PuestaApoyo.appSupport()
        defer { Apoyo.limpiar(asup) }
        let contador = LanzadorFalso(salida: #"{"vaga":false}"#)
        var m = PuestaApoyo.motor(.vacio(), asup: asup, entrevista: InterviewEngine(lanzador: contador))
        await m.responder(.destino, .texto("Facturar 90.000 € en 2027"))
        #expect(contador.mensajes.isEmpty)
        m.usarAsistente(true)
        await m.responder(.cita(.ventas), .texto("Me llaman y no sé qué precio dar cada vez"))
        #expect(contador.mensajes.count == 1)
    }

    // MARK: Glosario

    static let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash",
                             "kpi", "capacidad", "capacidades", "agente", "agentes", "csv", "onboarding"]

    static func jerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return prohibidas.filter { palabras.contains($0) }
    }

    @Test("Ningún texto que enseña la puesta en marcha usa jerga")
    func glosario() async throws {
        var textos: [String] = []
        for p in PasoPuesta.allCases { textos.append(p.titulo) }
        for r in RutaPuesta.allCases { textos.append(r.titulo) }
        for a in AlcancePuesta.allCases { textos.append(a.titulo) }
        for c in ConexionPuesta.allCases { textos += [c.titulo, c.detalle] }
        for h in HitoRecorrido.allCases { textos.append(h.titulo) }
        for e in [ErrorPuesta.estadoEnICloud, .carpetaReal, .soloLectura, .sinCarpeta, .nombreVacio, .logoDemasiadoGrande("x"),
                  .logoIlegible("x"), .ajustesIlegibles, .cambioFuera("x"), .nadaQueDeshacer, .otroPlanDespues("x")] {
            textos.append(e.localizedDescription)
        }
        // Todas las pantallas y preguntas de las rutas, con lo premarcado (Ribera) y sin nada.
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        for ctx in [ContextoCarpeta.vacio(), PuestaApoyo.contexto(env)] {
            var m = PuestaApoyo.motor(ctx, asup: asup)
            try await PuestaApoyo.recorrer(&m) { m, paso in
                let v = try m.vistaPrevia(paso)
                textos += [v.resumen] + v.avisos + v.fueraDeLaCarpeta + (v.entendido.map { [$0.porQue] } ?? [])
                PuestaApoyo.aplicarSinEscribir(&m, paso)
            }
            for p in m.pantallas {
                textos += [p.titulo, p.explicacion]
                for id in p.preguntas {
                    guard let q = m.pregunta(id) else { continue }
                    textos += [q.texto, q.ayuda, q.repregunta, q.premarcada?.origen.texto, q.referencia].compactMap { $0 }
                    textos += q.tipo.opciones.flatMap { [$0.texto, $0.detalle].compactMap { $0 } }
                }
            }
            textos.append(m.progreso.texto)
        }
        #expect(textos.count > 300)
        let malas = textos.filter { !Self.jerga($0).isEmpty || $0.contains(".tls/") }
        #expect(malas.isEmpty, "Jerga en pantalla: \(malas)")
    }
}
