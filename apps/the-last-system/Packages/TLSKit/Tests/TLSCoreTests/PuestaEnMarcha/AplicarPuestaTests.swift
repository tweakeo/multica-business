import Foundation
import Testing
@testable import TLSCore

/// Criterios F3-1 (nada se escribe antes de «Aplicar», con un vigilante de escrituras) y F3-5 («No lo sé» se escribe
/// PENDIENTE), y la vista previa de cada paso con Ribera y con la fixture G3: lo que enseña es exactamente lo que queda
/// escrito, y «Deshacer» lo quita.
@Suite("Puesta en marcha · aplicar y vista previa", .serialized)
struct AplicarPuestaTests {
    // MARK: F3-1

    @Test("Ribera y G3: ninguna escritura en la carpeta en todo el recorrido hasta pulsar «Aplicar»")
    func nadaAntesDeAplicar() async throws {
        for nombre in ["Ribera", "G3"] {
            let env = nombre == "G3" ? PuestaApoyo.g3() : PuestaApoyo.ribera()
            let asup = PuestaApoyo.appSupport()
            defer { env.limpiar(); Apoyo.limpiar(asup) }
            await VigilanteEscrituras.esperar(1.0)
            let vigilante = VigilanteEscrituras(env.root)
            vigilante.empezar()
            await VigilanteEscrituras.esperar(0.5)
            let antes = PuestaApoyo.huella(env.root)
            let ctx = PuestaApoyo.contexto(env, entrada: nombre == "G3" ? PuestaApoyo.entradaG3(env) : nil)
            var m = PuestaApoyo.motor(ctx, asup: asup)
            var vistas = 0
            // Se contesta todo, también «No lo sé», y se prepara la vista previa de cada paso, sin aplicar.
            try await PuestaApoyo.recorrer(&m, respuesta: { q in q.id == .destino ? .noLoSe : nil }) { m, paso in
                let v = try m.vistaPrevia(paso)
                if v.plan != nil { vistas += 1 }
                if paso == .organizar { m.seguirMasTarde() }
                PuestaApoyo.aplicarSinEscribir(&m, paso)
            }
            await VigilanteEscrituras.esperar(1.5)
            #expect(vistas >= 4, "\(nombre): solo \(vistas) pasos con algo que escribir")
            #expect(PuestaApoyo.huella(env.root) == antes, "\(nombre): la carpeta cambió antes de «Aplicar»")
            #expect(vigilante.eventos.isEmpty, "\(nombre): el vigilante vio \(vigilante.eventos)")
            // Y al aplicar, sí.
            var m2 = PuestaApoyo.motor(ctx, asup: asup)
            await m2.responder(.destino, .texto("Llegar a 200 clientes al año en 2028"))
            let v = try m2.vistaPrevia(.conocer)
            let bus = try await env.bus()
            try await m2.aplicar(v, bus: bus)
            await VigilanteEscrituras.esperar(1.5)
            vigilante.parar()
            #expect(PuestaApoyo.huella(env.root) != antes)
            #expect(!vigilante.eventos.isEmpty, "\(nombre): el vigilante no vio la escritura de «Aplicar»")
            #expect(m2.estado.paso(.conocer).fase == .aplicado)
            await bus.writer.close()
        }
    }

    @Test("Empresa nueva: no existe nada en el disco hasta «Aplicar» del paso 0")
    func empresaNuevaNadaAntes() async throws {
        let asup = PuestaApoyo.appSupport()
        let empresas = Apoyo.tempDir("empresas")
        defer { Apoyo.limpiar(asup, empresas) }
        let registro = VaultRegistry(directory: asup)
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), asup: asup)
        await m.responder(.como, .opcion("cero"))
        _ = m.siguiente()
        await m.responder(.nombreEmpresa, .texto("Estudio Prueba"))
        await m.responder(.yo, .texto("Ana"))
        await m.responder(.sector, .noLoSe)
        _ = m.siguiente()
        let v = try m.vistaPrevia(.bienvenida)
        #expect(try FileManager.default.contentsOfDirectory(atPath: empresas.path).isEmpty)
        #expect(registro.load().isEmpty)
        let rutas = Set(v.cambios.map(\.ruta.raw))
        #expect(rutas.isSuperset(of: ["Empresa.md", "AGENTS.md", ".tls/layout.json", ".tls/config.yaml"]))
        #expect(v.cambios.filter { $0.ruta.name == "Área.md" }.count == 6)
        #expect(v.cambios.allSatisfy { $0.clase == .crear })
        #expect(v.resumen == "Crear 10 ficheros · No se borra nada")
        let entrada = try await m.aplicarEmpezarDeCero(v, empresas: empresas, registro: registro, appSupport: asup)
        #expect(entrada.id == m.estado.vaultID)
        #expect(registro.load().map(\.id) == [entrada.id])
        let root = URL(fileURLWithPath: entrada.ruta)
        for c in v.cambios {
            let t = try String(contentsOf: c.ruta.url(in: root), encoding: .utf8)
            #expect(t == c.despues, "\(c.ruta.raw) no es lo que enseñó la vista previa")
        }
        // La carpeta nueva se lee como una empresa: seis áreas, la estructura de serie y su configuración.
        let ctx = ContextoCarpeta.leer(root, entrada: entrada, reloj: PuestaApoyo.relojRibera)
        #expect(ctx.areas.count == 6)
        #expect(ctx.organizada)
        #expect(ctx.nombreEmpresa == "Estudio Prueba")
        #expect(WritePolicy.clase(declaradaEn: root) == .copia)
        let empresa = try String(contentsOf: root.appendingPathComponent("Empresa.md"), encoding: .utf8)
        #expect(empresa.contains("- PENDIENTE · A qué se dedica"), "«No lo sé» se escribe PENDIENTE")
        #expect(m.estado.paso(.bienvenida).fase == .aplicado)
    }

    // MARK: Vista previa de cada paso

    /// Aplica de verdad cada paso y comprueba que lo escrito es la vista previa.
    static func aplicarYComprobar(_ env: EntornoCarpeta, _ m: inout OnboardingEngine, _ paso: PasoPuesta, bus: CommandBus,
                                  vistas: inout [PasoPuesta: VistaPreviaPaso]) async throws {
        if paso == .bienvenida || paso == .ordenar { PuestaApoyo.aplicarSinEscribir(&m, paso); return }
        let v = try m.vistaPrevia(paso)
        vistas[paso] = v
        try await m.aplicar(v, bus: bus)
        for c in v.cambios {
            let url = c.ruta.url(in: env.root)
            #expect(FileManager.default.fileExists(atPath: url.path), "\(paso): no está \(c.ruta.raw)")
            if let d = c.despues {
                let t = try String(contentsOf: url, encoding: .utf8)
                #expect(t == d, "\(paso): \(c.ruta.raw) no es lo que enseñó la vista previa")
            }
        }
        // Lo que lee la app sigue leyéndose.
        if let c = env.texto(".tls/config.yaml") { #expect(TextoPuesta.yamlValido(c)) }
        // El motor se queda con la carpeta como queda.
        m.cambiarContexto(PuestaApoyo.contexto(env, entrada: m.contexto.entrada))
    }

    @Test("Ribera: cada paso escribe lo que enseña su vista previa")
    func riberaPasoAPaso() async throws {
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        let bus = try await env.bus()
        var vistas: [PasoPuesta: VistaPreviaPaso] = [:]
        let elegidas: [PreguntaID: ValorRespuesta] = [
            .destino: .texto("Llegar a 300 declaraciones al año en 2028"),
            // Ribera trae Marca preparada desde F4: se activa para que Organizar escriba el estado y AGENTS.md.
            .estadoArea(.marca): .opcion("activa"),
            .automatizar("FI1"): .siNo(true),
            .rutinaDia: .opcion("martes"),
            .topeHoras: .numero(5),
            .meta(.ventas): .numero(2000),
            .alerta(.ventas): .opcion("sin-meta"),
        ]
        try await PuestaApoyo.recorrer(&m, respuesta: { elegidas[$0.id] }) { m, paso in try await Self.aplicarYComprobar(env, &m, paso, bus: bus, vistas: &vistas) }
        // 1 · Diagnóstico y Rumbo.
        let diag = try #require(env.texto("1 · Dirección/Diagnóstico.md"))
        #expect(diag.contains("## Frase destino\n\n«Llegar a 300 declaraciones al año en 2028»"))
        #expect(diag.contains("| 2 · Ventas |"))
        #expect(vistas[.conocer]?.entendido?.filas.count == 6)
        let rumbo = try #require(env.texto("1 · Dirección/Rumbo.md"))
        #expect(rumbo.contains("## Adónde vamos\n\nLlegar a 300 declaraciones al año en 2028"))
        // 3 · Organizar: el estado de Marca, sus esqueletos y la tarea del logo.
        let marca = try #require(env.texto("5 · Marca/Área.md"))
        #expect(marca.contains("estado: activa"))
        #expect(env.existe("2 · Ventas/Sistemas/Embudo.md"))
        #expect(env.texto("2 · Ventas/Sistemas/Embudo.md")?.contains("tls_type: system") == true)
        #expect(env.texto("AGENTS.md")?.contains("- Activas: Dirección, Ventas, Entrega, Finanzas, Marca.") == true)
        #expect(env.texto("AGENTS.md")?.contains("- En reposo: Equipo.") == true)
        // 4 · Qué funciona sin ti: funciones declaradas y la tarea de revisión a los 7 días (el lunes 26/10).
        let config = try #require(env.texto(".tls/config.yaml"))
        #expect(config.contains("  FIN-02: {declarada: si, modo: supervisado, ejecutor: IA, declarada_por: Manu, desde: 2026-10-19}"))
        #expect(config.contains("hoy: 2026-10-19"), "Lo que había en la configuración se conserva")
        let tareas = vistas[.sinTi]?.cambios.filter { $0.ruta.raw.contains("/Tareas/t-") } ?? []
        #expect(tareas.count == 1)
        #expect(tareas.first?.despues?.contains("planificada: 2026-10-26") == true)
        // 5 · Tu día a día: la rutina del martes y el tope de 5 horas.
        #expect(config.contains("tope_horas_dia: 5"))
        let rutina = try #require(vistas[.diaADia]?.cambios.first { $0.ruta.raw.contains("/Rutinas/") })
        #expect(rutina.despues?.contains("dia: martes") == true)
        // 6 · Tus números: solo las celdas Meta y Alerta de la fila.
        let metas = try #require(vistas[.numeros]?.cambios.first { $0.ruta.name == "Metas.md" })
        #expect(metas.clase == .cambiar)
        #expect(metas.despues?.contains("| VEN-WON | Ventas cobradas del mes | 2000 € | Sin alerta |") == true)
        // La foto de métricas lee lo declarado: la etapa de Finanzas ya no es la de nada declarado.
        let foto = FotoMetricas(snapshot: env.foto(), hoy: PuestaApoyo.relojRibera.hoy)
        #expect(foto.config.capacidades["FIN-02"]?.declarada == true)
        #expect(foto.config.topeHorasDia == 5)
        await bus.writer.close()
    }

    @Test("Fixture G3: lo premarcado de la carpeta no se reescribe y «Deshacer» quita lo de un paso")
    func g3PasoAPaso() async throws {
        let env = PuestaApoyo.g3()
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env, entrada: PuestaApoyo.entradaG3(env)), asup: asup)
        let bus = try await env.bus()
        let antes = env.huella()
        var vistas: [PasoPuesta: VistaPreviaPaso] = [:]
        var huellaAntesDeOrganizar: [String: String] = [:]
        try await PuestaApoyo.recorrer(&m) { m, paso in
            if paso == .organizar { huellaAntesDeOrganizar = env.huella() }
            try await Self.aplicarYComprobar(env, &m, paso, bus: bus, vistas: &vistas)
            if paso == .organizar {
                // «Deshacer» del paso: lo cambiado vuelve a sus bytes y lo creado sale de su sitio (a Archivo).
                let v = try #require(vistas[.organizar])
                try await m.deshacer(.organizar, bus: bus)
                #expect(m.estado.paso(.organizar).fase == .pendiente)
                let despues = env.huella()
                for (ruta, hash) in huellaAntesDeOrganizar { #expect(despues[ruta] == hash, "\(ruta) no volvió a sus bytes") }
                for c in v.cambios where c.clase == .crear { #expect(!env.existe(c.ruta.raw)) }
                // Y se vuelve a aplicar para seguir.
                m.cambiarContexto(PuestaApoyo.contexto(env, entrada: m.contexto.entrada))
                try await Self.aplicarYComprobar(env, &m, .organizar, bus: bus, vistas: &vistas)
            }
        }
        // Las áreas de G3 no tenían propiedades: confirmar su estado no lo reescribe. Solo se añade (el enlace al rol y
        // la fila de los sistemas de serie que faltaban); ninguna línea que había cambia.
        let original = try String(contentsOf: VaultPath("1 · Dirección/Área.md").url(in: Apoyo.empresaMinima), encoding: .utf8)
        let ahora = try #require(env.texto("1 · Dirección/Área.md"))
        #expect(!ahora.contains("estado: activa"))
        #expect(ahora.contains("**Estado:** activa"))
        for l in original.components(separatedBy: "\n") where !l.isEmpty { #expect(ahora.contains(l), "Cambió «\(l)»") }
        #expect(ahora.contains("| DI2 | [Revisión y replanificación](Sistemas/Revisión%20y%20replanificación.md) |"))
        // Lo privado no aparece en ninguna vista previa.
        for v in vistas.values { #expect(!v.cambios.contains { $0.ruta.raw.hasPrefix("Privado") }) }
        #expect(antes["Privado/Expediente personal.md"] == env.huella()["Privado/Expediente personal.md"])
        // Los sistemas que faltan nacen como esqueleto con las secciones de la ficha de sistema v2.
        let oferta = try #require(env.texto("2 · Ventas/Sistemas/Oferta.md"))
        for s in ["## Para qué", "## Cuándo se usa", "## Entradas", "## Pasos", "## Salida esperada y criterio de «bien hecho»",
                  "## Lo que nunca hace", "## Referencias y ejemplos", "## Aprendido"] {
            #expect(oferta.contains(s), "Falta «\(s)» en el esqueleto")
        }
        // El área con sistemas en lista conserva la lista y gana la tabla con los nuevos.
        let ventas = try #require(env.texto("2 · Ventas/Área.md"))
        #expect(ventas.contains("- [Embudo](Sistemas/Embudo.md)"))
        #expect(ventas.contains("| VE1 | [Oferta](Sistemas/Oferta.md) |"))
        await bus.writer.close()
    }

    @Test("El logo: «Ya lo tengo» lo copia a Marca y lo enlaza; «Está en mi web» deja una tarea; más de 10 MB, no")
    func logo() async throws {
        let env = PuestaApoyo.ribera()
        let asup = PuestaApoyo.appSupport()
        let fuera = Apoyo.tempDir("logo")
        defer { env.limpiar(); Apoyo.limpiar(asup, fuera) }
        let png = fuera.appendingPathComponent("logo-ribera.png")
        let bytes = Data((0..<2048).map { UInt8($0 % 251) })
        try bytes.write(to: png)
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        await m.responder(.logo, .opcion("tengo"))
        // Más de 10 MB: no se prepara.
        let grande = fuera.appendingPathComponent("enorme.png")
        try Data(count: 10 * 1024 * 1024 + 1).write(to: grande)
        await m.responder(.logoFichero, .rutas([grande.path]))
        #expect(throws: ErrorPuesta.logoDemasiadoGrande("enorme.png")) { _ = try m.vistaPrevia(.organizar) }
        await m.responder(.logoFichero, .rutas([png.path]))
        let v = try m.vistaPrevia(.organizar)
        let copia = try #require(v.cambios.first { $0.clase == .copiar })
        #expect(copia.ruta.raw == "5 · Marca/Activos/Logo/original/logo-ribera.png")
        #expect(v.resumen.contains("Copiar 1 fichero"))
        let marca = try #require(v.cambios.first { $0.ruta.raw == "5 · Marca/Marca.md" })
        #expect(marca.despues?.contains("logo: \"[[5 · Marca/Activos/Logo/original/logo-ribera.png|Logo]]\"") == true)
        #expect(!FileManager.default.fileExists(atPath: copia.ruta.url(in: env.root).path), "Antes de aplicar no hay copia")
        let bus = try await env.bus()
        try await m.aplicar(v, bus: bus)
        #expect(try Data(contentsOf: copia.ruta.url(in: env.root)) == bytes)
        // «Está en mi web»: una tarea en Marca con la dirección.
        await m.responder(.logo, .opcion("web"))
        await m.responder(.logoWeb, .texto("https://www.ribera.example"))
        m.cambiarContexto(PuestaApoyo.contexto(env))
        let w = try m.vistaPrevia(.organizar)
        let tarea = try #require(w.cambios.first { $0.ruta.raw.hasPrefix("5 · Marca/Tareas/t-") })
        #expect(tarea.despues?.contains("https://www.ribera.example") == true)
        await bus.writer.close()
    }

    // MARK: F3-5

    @Test("«No lo sé» se escribe PENDIENTE donde iba la respuesta")
    func pendiente() async throws {
        let asup = PuestaApoyo.appSupport()
        let empresas = Apoyo.tempDir("empresas")
        defer { Apoyo.limpiar(asup, empresas) }
        let registro = VaultRegistry(directory: asup)
        var m = PuestaApoyo.motor(.vacio(reloj: PuestaApoyo.relojRibera), asup: asup)
        let noSe: Set<PreguntaID> = [.destino, .funciona(.ventas), .cita(.direccion), .ocupante(.ventas), .sistema("VE1"),
                                     .sistema("DI3"), .rutinaDia, .topeHoras, .meta(.finanzas), .fraseDolor]
        var bus: CommandBus?
        var root: URL?
        try await PuestaApoyo.recorrer(&m, respuesta: { q in noSe.contains(q.id) ? .noLoSe : nil }) { m, paso in
            if paso == .bienvenida {
                let e = try await m.aplicarEmpezarDeCero(try m.vistaPrevia(.bienvenida), empresas: empresas, registro: registro,
                                                         appSupport: asup)
                let r = URL(fileURLWithPath: e.ruta)
                root = r
                bus = CommandBus(writer: try await VaultWriter.open(entry: e, root: r, options: .init(
                    stateDirectory: asup.appendingPathComponent(e.id.uuidString.lowercased()), appSupport: asup)))
                return
            }
            try await m.aplicar(try m.vistaPrevia(paso), bus: try #require(bus))
            m.cambiarContexto(ContextoCarpeta.leer(try #require(root), entrada: m.contexto.entrada, reloj: PuestaApoyo.relojRibera))
        }
        let r = try #require(root)
        func texto(_ p: String) throws -> String { try String(contentsOf: VaultPath(p).url(in: r), encoding: .utf8) }
        let diag = try texto("1 · Dirección/Diagnóstico.md")
        #expect(diag.contains("## Frase destino\n\nPENDIENTE"))
        #expect(diag.contains("sin PENDIENTE."))
        let filaVentas = try #require(TextoPuesta.filas(con: "Funciona (1–5)", en: diag).first { $0["Área"] == "2 · Ventas" })
        #expect(filaVentas["Funciona (1–5)"] == "PENDIENTE")
        let filaDir = try #require(TextoPuesta.filas(con: "Funciona (1–5)", en: diag).first { $0["Área"] == "1 · Dirección" })
        #expect(filaDir["Lo que dijiste"] == "PENDIENTE")
        let ventas = try texto("2 · Ventas/Área.md")
        #expect(ventas.contains("- PENDIENTE · ¿Quién lleva Ventas?"))
        #expect(ventas.contains("| VE1 | [Oferta](Sistemas/Oferta.md) | PENDIENTE |"))
        let config = try texto(".tls/config.yaml")
        #expect(config.contains("  DIR-02: {declarada: PENDIENTE}"))
        #expect(config.contains("tope_horas_dia: PENDIENTE"))
        #expect(TextoPuesta.yamlValido(config))
        let rutinas = try FileManager.default.contentsOfDirectory(atPath: VaultPath("1 · Dirección/Rutinas").url(in: r).path)
        let rutina = try texto("1 · Dirección/Rutinas/" + (try #require(rutinas.first)))
        #expect(rutina.contains("dia: PENDIENTE"))
        let metas = try texto("1 · Dirección/Metas.md")
        #expect(TextoPuesta.filas(con: "Código", en: metas).first { $0["Código"] == "FIN-RUNWAY" }?["Meta"] == "PENDIENTE")
        // Un PENDIENTE en Metas cuenta como meta sin fijar (nunca un 0 inventado).
        #expect(MetasDocumento(texto: metas).fila("FIN-RUNWAY")?.meta.fijado == false)
        await bus?.writer.close()
    }

    @Test("En la carpeta real no se aplica nada")
    func carpetaReal() async throws {
        let env = EntornoCarpeta(copiando: Apoyo.empresaMinima, nombre: "Real", clase: .real)
        let asup = PuestaApoyo.appSupport()
        defer { env.limpiar(); Apoyo.limpiar(asup) }
        var m = PuestaApoyo.motor(PuestaApoyo.contexto(env), asup: asup)
        await m.responder(.destino, .texto("Ganar 100.000 € al año en 2028"))
        let v = try m.vistaPrevia(.conocer)
        #expect(v.plan != nil)
        await #expect(throws: WriteError.carpetaReal) { _ = try await env.bus() }
    }
}
