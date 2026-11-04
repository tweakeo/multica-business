import Foundation
import Testing
import TLSAgents
import TLSCore
@testable import TLSUI

/// Decisiones con los asistentes (PLAN §6.3, §5.2; criterio F4-2): los grupos Para aprobar · Preguntas · Propuestas de
/// mejora; aprobar por la hoja que enseña qué sale, a quién y por cuánto (sin huellas); «Cambió desde que lo preparó el
/// asistente» desactiva «Aprobar» y «Aprobar con mis cambios» aprueba en un gesto; responder reanuda; las propuestas
/// enseñan su diferencia; CRITERIO y los permisos cambiados fuera de la app. Ribera en un temporal; nunca se lanza Claude.
@Suite("Decisiones · lo de los asistentes", .serialized)
@MainActor
struct DecisionesF4Tests {
    @Test("F4-2 · Un borrador de Comercial sale en «Para aprobar»; la hoja enseña qué sale, a quién y por cuánto, y al aprobar queda listo para que lo envíes tú")
    func aprobar() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let (ruta, id) = try await MikaApoyo.borradorPendiente(e)
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion == id } != nil }
        let t = try #require(e.tarjeta { $0.gobierno?.aprobacion == id })
        #expect(t.tipo == .paraAprobar && t.grupoF4 == "Para aprobar" && t.ruta == ruta)
        let d = try #require(e.datos?.detalles[t.id])
        #expect(d.quien == "Lo prepara Comercial (asistente)")
        #expect(d.motivoNoDecidir == nil)
        #expect(d.siSePospone.contains("No sale nada hasta que lo apruebes"))
        // El grupo va el primero.
        let grupos = GrupoDecisiones.agrupar(try #require(e.datos?.decisiones))
        #expect(grupos.first?.grupo == "Para aprobar" && grupos.first?.tarjetas.contains { $0.id == t.id } == true)
        // La tarjeta de la lista lleva a la hoja, nunca aprueba sola (con cualquier opción que le llegue).
        let otra = try #require(await Self.opcionCualquiera(e))
        #expect(await Decidir.elegir(d, opcion: otra, sesion: e.sesion, navegar: .ninguna) == false)
        #expect(e.texto(ruta.raw).contains("estado: Pendiente de tu OK"))

        let m = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor) { await e.asistentes.cambio() }
        await m.cargar()
        let det = try #require(m.detalle)
        #expect(det.accion == "Correo para que lo envíes tú")
        #expect(det.aQuien == ["persona@example.com"])
        #expect(det.asunto == "Seguimiento de la propuesta de la renta")
        #expect(det.queSale.contains("¿Pudiste mirar la propuesta que te mandamos el día 12?"))
        #expect(!det.queSale.contains("Han pasado 7 días"), "«Para ti» no sale")
        #expect(m.motivoNoAprobar == nil && m.puedeAprobarConCambios)
        // Ningún texto de la hoja enseña una huella.
        for s in [det.accion, det.queSale, det.asunto ?? "", m.motivoNoAprobar ?? ""] {
            #expect(!s.contains(det.aprobacion.hash), "sin huellas")
        }
        #expect(await m.aprobar())
        guard case .listoParaEnviar(let r)? = m.resultado else {
            Issue.record("Un correo queda listo para enviar: \(String(describing: m.resultado))")
            return
        }
        #expect(r == ruta)
        #expect(e.texto(ruta.raw).contains("estado: Listo para enviar"))
        #expect(m.motivoNoAprobar == "Ya está aprobado")
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion == id } == nil }
        #expect(e.tarjeta { $0.gobierno?.aprobacion == id } == nil, "sale de la bandeja")
    }

    @Test("F4-2 · Editar el borrador desde fuera: «Aprobar» se desactiva con «Cambió desde que lo preparó el asistente»; «Aprobar con mis cambios» aprueba en un gesto")
    func invalidadaYConMisCambios() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let (ruta, id) = try await MikaApoyo.borradorPendiente(e)
        // Alguien lo toca en Obsidian.
        e.cambiarFuera(ruta.raw, "¿Pudiste mirar la propuesta", "¿Has podido mirar la propuesta")
        let m = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor) { await e.asistentes.cambio() }
        await m.cargar()
        #expect(m.motivoNoAprobar == "Cambió desde que lo preparó el asistente")
        #expect(m.puedeAprobarConCambios)
        #expect(await m.aprobar() == false)
        #expect(m.resultado == nil)
        // En la bandeja, la tarjeta lo dice (y la lista también lo enseña).
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion == id }?.gobierno?.cambio == true }
        #expect(e.tarjeta { $0.gobierno?.aprobacion == id }?.gobierno?.cambio == true)
        // Corrijo el asunto y apruebo, en un solo gesto.
        m.editando = true
        m.asunto = "Seguimiento de tu propuesta"
        #expect(m.cambios.asunto == "Seguimiento de tu propuesta" && m.cambios.cuerpo == nil)
        #expect(await m.aprobarConMisCambios())
        guard case .listoParaEnviar? = m.resultado else {
            Issue.record("Debía quedar listo para enviar: \(String(describing: m.resultado))")
            return
        }
        let texto = e.texto(ruta.raw)
        #expect(texto.contains("asunto: Seguimiento de tu propuesta"))
        #expect(texto.contains("¿Has podido mirar la propuesta"), "lo que veías es lo que se aprobó")
        let estado = try #require(e.asistentes.autorizador?.estado)
        let a = try ApprovalStore(estado: estado).aprobacion(id)
        #expect(a?.conCambios == true && a?.decididaPor == "Manu")
    }

    @Test("Descartar un borrador: no sale nada y queda «Descartado»")
    func descartar() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let (ruta, id) = try await MikaApoyo.borradorPendiente(e)
        let m = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
        await m.cargar()
        #expect(await m.descartar(motivo: "Ya le llamé"))
        #expect(e.texto(ruta.raw).contains("estado: Descartado"))
        let a = try e.asistentes.autorizador.flatMap { try ApprovalStore(estado: $0.estado).aprobacion(id) }
        #expect(a?.estado == .rechazada)
    }

    @Test("Sin escritor no se aprueba nada y se dice por qué; un borrador sin petición se revisa en su ficha")
    func sinGobierno() async throws {
        let m = ModeloAprobacion(id: "apr-x", aprobaciones: nil, persona: .persona("Manu"))
        await m.cargar()
        #expect(m.error == "Para aprobar hace falta que la app pueda escribir en esta carpeta.")
        #expect(m.motivoNoAprobar != nil && !m.puedeAprobarConCambios)
        #expect(await m.aprobar() == false)
        #expect(ModeloAprobacion.centimos("1.250,50") == 125_050)
        #expect(ModeloAprobacion.centimos("39,9 €") == 3_990)
        #expect(ModeloAprobacion.centimos("") == nil)
        #expect(ModeloAprobacion.destinatarios("a@example.com, b@example.com;c@example.com") == ["a@example.com", "b@example.com", "c@example.com"])
    }

    @Test("Una pregunta de Contable: sale en «Preguntas» con lo que propone (1, 2) y, al responder, queda contestada y el asistente sigue")
    func pregunta() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let ruta = MikaApoyo.preguntaDeContable(e)
        await e.esperar { e.tarjeta { $0.ruta?.raw == ruta } != nil }
        let t = try #require(e.tarjeta { $0.ruta?.raw == ruta })
        #expect(t.tipo == .pregunta && t.gobierno?.clase == .pregunta && t.gobierno?.asistente == "contable" && t.grupoF4 == "Preguntas")
        let d = try #require(e.datos?.detalles[t.id])
        #expect(d.quien == "Te lo pregunta Contable (asistente)")
        #expect(d.respuestas.map(\.texto) == ["A la línea del móvil de empresa", "A gastos de oficina"])
        #expect(d.respuestas.first?.recomendada == true)
        #expect(d.siSePospone.contains("El asistente se queda esperando"))
        #expect(await Decidir.responderAlAsistente(t, texto: "A la línea del móvil de empresa", sesion: e.sesion))
        let texto = e.texto(ruta)
        #expect(texto.contains("estado: Hecha") && texto.contains("Respuesta: A la línea del móvil de empresa"))
        // La respuesta es de la persona (el motor la recoge como respuesta y reanuda la misma conversación).
        #expect(texto.contains("· Manu"))
    }

    @Test("Una propuesta de mejora enseña la diferencia; aprobar la 1 aplica el plan como tú; «Dejarlo como está» no cambia nada")
    func propuestaDeMejora() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let sistema = VaultPath(MikaApoyo.sistema(e))
        await e.refrescar()
        let escritura = try #require(e.asistentes.escritura)
        let linea = "- 2026-10-19 · Si no contestan en 7 días, mejor llamar que escribir · propuesta de Comercial"
        let plan = WritePlan(autor: .persona("Manu"), descripcion: "Lo aprendido del seguimiento",
                             ops: [.appendToSection(sistema, section: "Aprendido", text: linea)])
        let (p, tarea) = try await escritura.proponer(plan, agente: "comercial", ejecucion: "r-1", capacidad: nil, clase: .mejora)
        await e.esperar { e.tarjeta { $0.ruta == tarea } != nil }
        let t = try #require(e.tarjeta { $0.ruta == tarea })
        #expect(t.gobierno?.clase == .mejora && t.gobierno?.propuesta == p.id && t.grupoF4 == "Propuestas de mejora")
        #expect(e.datos?.detalles[t.id]?.quien == "La propone Comercial (asistente)")
        // La diferencia, a la vista.
        let dif = DiferenciaDePropuesta.de(plan, foto: e.foto())
        #expect(dif.count == 1 && dif[0].titulo == "Seguimiento de propuestas" && dif[0].resumen == "Se añade a «Aprendido»")
        #expect(dif[0].lineas == [.anadida(linea)])
        // Opción 1 (recomendada): se aplica como la persona y la tarea queda Hecha.
        let uno = try #require(t.opciones.first { $0.recomendada })
        #expect(await Decidir.decidirPropuesta(t, propuesta: p.id, opcion: uno, sesion: e.sesion))
        #expect(e.texto(sistema.raw).contains(linea))
        #expect(e.texto(tarea.raw).contains("estado: Hecha"))
        // Otra con «Dejarlo como está»: no cambia nada ni se apunta.
        let (p2, tarea2) = try await escritura.proponer(
            WritePlan(autor: .persona("Manu"), descripcion: "Otra cosa", ops: [.appendToSection(sistema, section: "Aprendido", text: "- otra")]),
            agente: "comercial", ejecucion: "r-2", capacidad: nil, clase: .mejora)
        await e.esperar { e.tarjeta { $0.ruta == tarea2 } != nil }
        let t2 = try #require(e.tarjeta { $0.ruta == tarea2 })
        let registro = e.texto("1 · Dirección/Decisiones.md")
        let dos = try #require(t2.opciones.first { $0.numero == 2 })
        #expect(await Decidir.decidirPropuesta(t2, propuesta: p2.id, opcion: dos, sesion: e.sesion))
        #expect(!e.texto(sistema.raw).contains("- otra"))
        #expect(e.texto(tarea2.raw).contains("estado: Cancelada"))
        #expect(e.texto("1 · Dirección/Decisiones.md") == registro, "«Dejarlo como está» no se apunta")
    }

    @Test("La diferencia por líneas: lo quitado y lo añadido, con una línea igual alrededor; nada de lo privado")
    func diferencia() {
        let l = DiferenciaDePropuesta.diferencia(antes: "a\nb\nc\nd\ne", despues: "a\nb\nX\nd\ne")
        #expect(l == [.igual("b"), .quitada("c"), .anadida("X"), .igual("d")])
        #expect(DiferenciaDePropuesta.diferencia(antes: "igual", despues: "igual").isEmpty)
        let muchas = DiferenciaDePropuesta.diferencia(antes: "x", despues: (1...60).map { "l\($0)" }.joined(separator: "\n"))
        #expect(muchas.count == 41 && muchas.last == .mas(21))
    }

    @Test("CRITERIO: tres aprobaciones iguales sacan la tarjeta; «Escribir el criterio en su sistema» lo apunta en «Aprendido» y no vuelve")
    func criterio() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let sistema = MikaApoyo.sistema(e)
        for i in 1...3 {
            let (_, id) = try await MikaApoyo.borradorPendiente(e, slug: "seguimiento-\(i)", asunto: "Seguimiento \(i)")
            let m = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
            await m.cargar()
            #expect(await m.aprobar())
        }
        await e.esperar { e.tarjeta { $0.gobierno?.clase == .criterio } != nil }
        let t = try #require(e.tarjeta { $0.gobierno?.clase == .criterio })
        #expect(t.grupoF4 == "Propuestas de mejora" && t.gobierno?.asistente == "comercial")
        #expect(e.datos?.detalles[t.id]?.quien.contains("tres veces igual con Comercial (asistente)") == true)
        let sugerido = Decidir.criterioSugerido(t)
        #expect(sugerido.contains("Comercial") && sugerido.contains("enviar un correo"))
        let sistemas = Decidir.sistemas(de: "comercial", foto: e.foto())
        #expect(sistemas.map(\.raw) == [sistema])
        #expect(await Decidir.escribirCriterio(t, criterio: "Los seguimientos de Comercial salen como los deja", en: sistemas.first,
                                               sesion: e.sesion))
        #expect(e.texto(sistema).contains("Los seguimientos de Comercial salen como los deja (criterio de Comercial, tras tres veces igual) · lo aprobó Manu"))
        await e.esperar { e.tarjeta { $0.id == t.id } == nil }
        #expect(e.tarjeta { $0.id == t.id } == nil, "no vuelve")
    }

    @Test("Permisos cambiados fuera de la app: tarjeta con lo que cambió en palabras; «Confirmar» la quita")
    func permisos() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        e.cambiarFuera(".tls/config.yaml", "max_tareas_por_ejecucion: 10", "max_tareas_por_ejecucion: 9")
        await e.esperar { e.tarjeta { $0.gobierno?.clase == .cambioDePermisos } != nil }
        let t = try #require(e.tarjeta { $0.gobierno?.clase == .cambioDePermisos })
        #expect(t.grupoF4 == "Para aprobar" && t.titulo.hasPrefix("Cambiaron los permisos de"))
        #expect(e.datos?.detalles[t.id]?.quien == "La deja la app: alguien cambió los permisos de los asistentes fuera de ella")
        let estado = try #require(e.asistentes.autorizador?.estadoDeConfig())
        #expect(!estado.cambios.isEmpty)
        #expect(estado.cambios.map(DetallePermisosVista.enPalabras).allSatisfy { !$0.contains("agente:") })
        #expect(DetallePermisosVista.enPalabras("agente:comercial") == "Lo que puede hacer Comercial")
        // Confirmar con la opción 1 de la tarjeta.
        let d = try #require(e.datos?.detalles[t.id])
        let uno = try #require(t.opciones.first)
        #expect(await Decidir.elegir(d, opcion: uno, sesion: e.sesion, navegar: .ninguna))
        #expect(e.asistentes.autorizador?.estadoDeConfig().cambiadaFuera == false)
        await e.esperar { e.tarjeta { $0.gobierno?.clase == .cambioDePermisos } == nil }
        #expect(e.tarjeta { $0.gobierno?.clase == .cambioDePermisos } == nil)
    }

    @Test("Las respuestas propuestas de una pregunta salen de «Lo que propongo» (como mucho 3)")
    func respuestasPropuestas() {
        let r = RespuestaPropuesta.de("""
        ## Lo que propongo
        Creo que va a la línea del móvil.

        1. A la línea del móvil (recomendada)
        2) A gastos de oficina
        3. Preguntar a la gestoría
        4. Otra más
        """)
        #expect(r.map(\.texto) == ["A la línea del móvil", "A gastos de oficina", "Preguntar a la gestoría"])
        #expect(r.map(\.recomendada) == [true, false, false])
        #expect(RespuestaPropuesta.de("## Pregunta\n¿Algo?").isEmpty)
    }

    /// Una opción cualquiera (de una 1-3-1 escrita en la copia), para comprobar que las aprobaciones no se deciden
    /// desde la lista.
    static func opcionCualquiera(_ e: MikaApoyo.Empresa) async -> OpcionDecision? {
        let (ruta, texto) = HoyApoyo.decision131(77, titulo: "¿Cómo retomamos a Jorge Martín?", area: "2 · Ventas")
        e.escribirFuera(ruta, texto)
        await e.esperar { e.tarjeta { $0.ruta?.raw == ruta } != nil }
        return e.tarjeta { $0.ruta?.raw == ruta }?.opciones.first
    }
}
