import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Marca › Operación con Ribera (F2 · rol areas-b): las piezas en el calendario y el tablero, la distribución por canal
/// con las conversaciones atribuidas (sin cifras inventadas: «Sin dato»), mover una pieza cambia solo su estado (o su día)
/// y se deshace, y «Proponer a Ventas» deja una tarea en Ventas y la conversación propuesta en un solo cambio. Lo privado
/// no aparece.
@Suite("Marca · calendario, tablero, distribución y conversaciones", .serialized)
@MainActor
struct MarcaOperacionTests {
    let apoyo = ApoyoAreasB()

    static let contenidos = "5 · Marca/Contenidos/"
    static let conversaciones = "5 · Marca/Conversaciones/"

    @Test("Ribera: 7 piezas, 4 conversaciones con su pieza, canales y calendario de octubre")
    func riberaSeLee() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloMarca(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(l.piezas.count == 7)
        #expect(l.publicadas.count == 3)
        #expect(l.piezas(en: .idea).count == 1 && l.piezas(en: .borrador).count == 1 && l.piezas(en: .enRevision).count == 1)
        #expect(l.piezas(en: .aprobado).count == 1 && l.piezas(en: .programado).isEmpty)
        // Calendario: las tres publicadas el 19 de octubre; las demás, sin fecha.
        let octubre = l.calendario(anio: 2026, mes: 10)
        #expect(octubre.keys.map(\.description) == ["2026-10-19"])
        #expect(octubre.values.first?.count == 3)
        #expect(l.sinFecha.count == 4)
        #expect(CalendarioMarca.semanas(de: LocalDate(year: 2026, month: 10, day: 1)!).map(\.description)
                == ["2026-09-28", "2026-10-05", "2026-10-12", "2026-10-19", "2026-10-26"])
        // Conversaciones: cada una con la pieza que la trajo.
        #expect(l.conversaciones.count == 4)
        #expect(l.conversaciones.allSatisfy { $0.pieza != nil })
        let irene = try #require(l.conversaciones.first { $0.quien == "Irene Lúcuma" })
        #expect(irene.estado == .cualificada && irene.piezaTitulo == "5 gastos que los autónomos olvidan deducir")
        #expect(irene.loQueDijo?.hasPrefix("Pregunta si llevamos trimestrales") == true)
        let gastos = try #require(l.piezas.first { $0.titulo == "5 gastos que los autónomos olvidan deducir" })
        #expect(l.conversaciones(de: gastos).count == 2)
        // Distribución: Instagram con 2 piezas y 3 conversaciones (2 cualificadas); sin alcance escrito, «Sin dato».
        let ig = try #require(l.canales.first { $0.canal == "instagram" })
        #expect(ig.publicadas == 2 && ig.conversaciones == 3 && ig.cualificadas == 2)
        #expect(ig.alcance == nil && LecturaMarca.cifra(ig.alcance) == "Sin dato")
        let li = try #require(l.canales.first { $0.canal == "linkedin" })
        #expect(li.publicadas == 1 && li.conversaciones == 1 && li.cualificadas == 0)
        #expect(LecturaMarca.nombreCanal("linkedin") == "LinkedIn")
    }

    @Test("Mover una pieza en el tablero cambia solo su estado; a Publicado, también su día de publicación; Deshacer")
    func moverEnElTablero() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloMarca(sesion: sesion)
        await modelo.cargar()
        let ruta = Self.contenidos + "que-es-el-modelo-303-en-60-segundos.md"
        let antes = apoyo.huella(e.carpeta)
        let pieza = try #require(modelo.lectura?.piezas.first { $0.ruta.raw == ruta })
        #expect(pieza.estado == .aprobado)
        let um = ApoyoAreasB.undo()
        um.beginUndoGrouping()
        #expect(await modelo.mover(pieza, a: .programado, deshacer: um))
        um.endUndoGrouping()
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [ruta])
        let lineas = Self.lineasCambiadas(String(decoding: antes[ruta]!, as: UTF8.self), apoyo.texto(e, ruta)!)
        #expect(lineas == ["estado: Programado"])
        #expect(modelo.lectura?.piezas(en: .programado).count == 1)
        await apoyo.deshacer(um, e, hasta: antes)
        #expect(apoyo.huella(e.carpeta) == antes)

        // A Publicado: estado y el día de hoy como publicación.
        await modelo.cargar(forzar: true)
        let otra = try #require(modelo.lectura?.piezas.first { $0.ruta.raw == ruta })
        #expect(await modelo.mover(otra, a: .publicado, deshacer: nil))
        let t = try #require(apoyo.texto(e, ruta))
        #expect(t.contains("estado: Publicado") && t.contains("publicado: 2026-10-19"))
    }

    @Test("Cambiar el día en el calendario escribe `publicar`; lo publicado no se mueve; quitar la fecha; Deshacer")
    func cambiarDia() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloMarca(sesion: sesion)
        await modelo.cargar()
        let ruta = Self.contenidos + "checklist-facturas-que-tu-gestoria-necesita-cada-trimestre.md"
        let antes = apoyo.huella(e.carpeta)
        let pieza = try #require(modelo.lectura?.piezas.first { $0.ruta.raw == ruta })
        let um = ApoyoAreasB.undo()
        um.beginUndoGrouping()
        #expect(await modelo.cambiarDia(pieza, a: LocalDate(year: 2026, month: 10, day: 23), deshacer: um))
        um.endUndoGrouping()
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == [ruta])
        #expect(apoyo.texto(e, ruta)?.contains("publicar: 2026-10-23") == true)
        #expect(sesion.aviso?.texto == "«Checklist: facturas que tu gestoría necesita cada trimestre» se publicará el vie 23 oct")
        let movida = try #require(modelo.lectura?.piezas.first { $0.ruta.raw == ruta })
        #expect(movida.dia?.description == "2026-10-23")
        #expect(modelo.lectura?.calendario(anio: 2026, mes: 10)[movida.dia!]?.count == 1)
        // Lo publicado no se mueve.
        let publicada = try #require(modelo.lectura?.publicadas.first)
        #expect(!publicada.movible)
        #expect(await modelo.cambiarDia(publicada, a: LocalDate(year: 2026, month: 10, day: 24), deshacer: nil) == false)
        // Quitar la fecha.
        #expect(await modelo.cambiarDia(movida, a: nil, deshacer: nil))
        #expect(apoyo.texto(e, ruta)?.contains("publicar:") == false)
        await apoyo.deshacer(um, e, hasta: antes)
    }

    @Test("«Proponer a Ventas» crea la tarea en Ventas y deja la conversación propuesta en un solo cambio; Marca no cualifica")
    func proponerAVentas() async throws {
        let nueva = """
        ---
        tls_type: conversation
        tls_schema: 1
        id: 5a0e1c2d-0000-4000-8000-000000000001
        perfil: "@estudio.demo"
        canal: instagram
        contenido: "[[reserva-tu-renta-2026-y-olvidate-en-abril|Reserva tu Renta 2026 y olvídate en abril]]"
        fecha: 2026-10-19
        estado: Nueva
        ---
        # @estudio.demo en instagram
        > Nueva · 19 oct

        ## Lo que dijo
        Pregunta cuánto cuesta la Renta con dos pisos alquilados.

        ## Contexto

        ## Decisión de Ventas
        """
        let ruta = Self.conversaciones + "instagram-estudio-demo.md"
        let (e, sesion) = try await apoyo.abrir(preparar: [ruta: nueva])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloMarca(sesion: sesion)
        await modelo.cargar()
        let c = try #require(modelo.lectura?.conversaciones.first { $0.ruta.raw == ruta })
        #expect(c.estado == .nueva && c.quien == "@estudio.demo")
        #expect(c.piezaTitulo == "Reserva tu Renta 2026 y olvídate en abril")
        let antes = apoyo.huella(e.carpeta)
        let um = ApoyoAreasB.undo()
        um.beginUndoGrouping()
        #expect(await modelo.proponerAVentas(c, deshacer: um))
        um.endUndoGrouping()
        #expect(modelo.error == nil)
        let cambios = apoyo.cambiados(antes, apoyo.huella(e.carpeta))
        #expect(cambios.contains(".tls/secuencias.json"))
        #expect(cambios.contains(ruta))
        let tarea = try #require(cambios.first { $0.hasPrefix("2 · Ventas/Tareas/t-") })
        #expect(cambios.count == 3)
        let t = try #require(apoyo.texto(e, tarea))
        #expect(t.contains("Decidir si cualifica la conversación con @estudio.demo"))
        #expect(t.contains("conversacion: \"[[instagram-estudio-demo|@estudio.demo]]\""))
        #expect(t.contains("Pregunta cuánto cuesta la Renta con dos pisos alquilados."))
        #expect(apoyo.texto(e, ruta)?.contains("estado: Propuesta a Ventas") == true)
        #expect(modelo.lectura?.conversaciones.first { $0.ruta.raw == ruta }?.estado == .propuesta)
        // Ya propuesta: no se vuelve a proponer.
        let propuesta = try #require(modelo.lectura?.conversaciones.first { $0.ruta.raw == ruta })
        #expect(await modelo.proponerAVentas(propuesta, deshacer: nil) == false)
        // Un solo Deshacer lo quita todo; nunca se borra: la tarea creada pasa a Archivo.
        um.undo()
        await apoyo.esperar { self.apoyo.huella(e.carpeta)[ruta] == antes[ruta] }
        #expect(apoyo.cambiados(antes, apoyo.huella(e.carpeta)) == ["Archivo/" + tarea])
    }

    @Test("Lo privado no aparece: ni sus piezas ni sus conversaciones")
    func privado() async throws {
        let privada = "5 · Marca/Expediente privado"
        let config = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
            .replacingOccurrences(of: "privado: []", with: "privado:\n  - \"\(privada)\"")
        let pieza = "---\ntls_type: content\ntitulo: Pieza reservada\nestado: Publicado\ncanales: [instagram]\npublicado: 2026-10-18\n---\n# Pieza reservada\n"
        let conv = "---\ntls_type: conversation\nperfil: \"@reservado\"\ncanal: instagram\nestado: Nueva\n---\n# @reservado\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [".tls/config.yaml": config, privada + "/pieza.md": pieza, privada + "/conv.md": conv])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloMarca(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(l.piezas.count == 7 && !l.piezas.contains { $0.titulo == "Pieza reservada" })
        #expect(l.conversaciones.count == 4 && !l.conversaciones.contains { $0.quien == "@reservado" })
        #expect(l.canales.first { $0.canal == "instagram" }?.publicadas == 2)
    }

    static func lineasCambiadas(_ antes: String, _ despues: String) -> [String] {
        let a = antes.components(separatedBy: "\n"), d = despues.components(separatedBy: "\n")
        guard a.count == d.count else { return ["(cambia el número de líneas)"] }
        return zip(a, d).filter { $0 != $1 }.map(\.1)
    }
}
