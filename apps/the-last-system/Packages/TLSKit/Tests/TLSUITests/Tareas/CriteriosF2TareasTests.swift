import CryptoKit
import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Criterios de F2 de las tareas con Ribera copiada a una carpeta temporal y una sesión con escritura:
/// F2-1 (⌘N, título y ⏎ crean `…/Tareas/t-NNNN-slug.md` con el orden de PLAN §4.2 y solo cambia además
/// `secuencias.json`), F2-2 (arrastrar o ⌘→ cambian solo `estado` y lo apuntan en la Actividad; un número repetido
/// se renumera y se renombra), lo privado fuera de Tareas, `Tareas.md` heredados, «Adoptar», «Mover a…», ENT-04 al
/// planificar y las menciones guardadas.
@Suite("Tareas · criterios F2-1 y F2-2 con Ribera", .serialized)
@MainActor
struct CriteriosF2TareasTests {
    let pruebas = SesionEscrituraTests()

    /// Huella de cada fichero de la carpeta (rutas relativas), sin `.DS_Store` ni `.tls/escritor.json`: este último no
    /// es contenido, es la marca de qué instalación escribe la carpeta, y el escritor la toma en la primera escritura de
    /// la sesión (F1-CONTRATOS: el único fichero que la app crea en la carpeta por su cuenta).
    static func huellas(_ raiz: URL) -> [String: String] {
        var out: [String: String] = [:]
        let fm = FileManager.default
        guard let e = fm.enumerator(at: raiz, includingPropertiesForKeys: [.isRegularFileKey]) else { return out }
        for case let u as URL in e {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true, u.lastPathComponent != ".DS_Store",
                  let d = try? Data(contentsOf: u) else { continue }
            let rel = String(u.standardizedFileURL.path.dropFirst(raiz.standardizedFileURL.path.count + 1))
            if rel == WriterClaim.file { continue }
            out[rel] = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
        }
        return out
    }

    static func cambiados(_ a: [String: String], _ b: [String: String]) -> Set<String> {
        Set(a.keys).union(b.keys).filter { a[$0] != b[$0] }
    }

    /// Las claves del frontmatter en orden.
    static func claves(_ texto: String) -> [String] {
        let lineas = texto.components(separatedBy: "\n")
        guard lineas.first == "---", let fin = lineas.dropFirst().firstIndex(of: "---") else { return [] }
        return lineas[1..<fin].compactMap { l in
            guard let i = l.firstIndex(of: ":"), !l.hasPrefix(" "), !l.hasPrefix("#") else { return nil }
            return String(l[..<i])
        }
    }

    func abrir(_ preparar: (URL) throws -> Void = { _ in }) async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        try preparar(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        #expect(sesion.puedeEscribir)
        return (e, sesion)
    }

    static func escribir(_ texto: String, en ruta: String, _ raiz: URL) throws {
        let u = raiz.appendingPathComponent(ruta)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: u)
    }

    // MARK: F2-1

    @Test("F2-1: ⌘N, título y ⏎ crean …/Tareas/t-0003-slug.md con el orden de §4.2, sin claves vacías, y solo cambia además secuencias.json")
    func criterio1() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let antes = Self.huellas(e.carpeta)
        // Lo que hace la hoja con el título y ⏎ (área de la pantalla: Ventas; la lleva la persona; sin día).
        let ruta = try await NuevaTareaHoja.crear(titulo: "Preparar propuesta económica para NEXO", area: .ventas, proyecto: nil,
                                                  responsable: "Manu", planificada: nil, sesion: sesion)
        #expect(ruta.raw == "2 · Ventas/Tareas/t-0003-preparar-propuesta-economica-para-nexo.md")
        let despues = Self.huellas(e.carpeta)
        #expect(Self.cambiados(antes, despues) == [ruta.raw, ".tls/secuencias.json"])
        #expect(try String(contentsOf: e.carpeta.appendingPathComponent(".tls/secuencias.json"), encoding: .utf8).contains("\"tarea\":3"))
        let texto = try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)
        let claves = Self.claves(texto)
        // Orden de PLAN §4.2 con los nombres de la v2 (SISTEMAS: `proyecto`, `oportunidad`…) y lo que añade la plantilla
        // (`area`, `plantilla`): lo escrito va en ese orden y sin claves vacías.
        let orden = ["tls_type", "tls_schema", "id", "numero", "titulo", "estado", "prioridad", "tipo", "responsable", "planificada",
                     "vence", "estimacion_h", "dedicadas_h", "area", "proyecto", "oportunidad", "empresa", "padre", "bloqueada_por",
                     "capacidad", "despertar", "origen", "creada", "creada_por", "cerrada", "fecha_corte", "plantilla"]
        #expect(claves.allSatisfy { orden.contains($0) }, "Claves fuera del orden conocido: \(claves)")
        #expect(claves == orden.filter { claves.contains($0) }, "Orden escrito: \(claves)")
        #expect(Array(claves.prefix(6)) == ["tls_type", "tls_schema", "id", "numero", "titulo", "estado"])
        let fm = NoteDocument(text: texto).frontmatter
        for p in fm.properties { #expect(!p.value.displayText.isEmpty, "«\(p.key)» se escribió vacía") }
        #expect(fm.text("numero") == "T-0003")
        #expect(fm.text("estado") == "Sin programar")
        #expect(fm.text("responsable") == "Manu")
        #expect(fm.text("area") == "ventas")
        #expect(texto.contains("## Descripción") && texto.contains("## Actividad"))
        // Con día en sábado: nace Por hacer y el lunes (ENT-04).
        let otra = try await NuevaTareaHoja.crear(titulo: "Llamar a Lucía", area: .ventas, proyecto: nil, responsable: nil,
                                                  planificada: LocalDate(year: 2026, month: 10, day: 24)!, sesion: sesion)
        let fm2 = NoteDocument(text: try String(contentsOf: otra.url(in: e.carpeta), encoding: .utf8)).frontmatter
        #expect(otra.name.hasPrefix("t-0004-"))
        #expect(fm2.text("planificada") == "2026-10-26")
        #expect(fm2.text("estado") == "Por hacer")
        #expect(fm2.text("responsable") == nil)
    }

    // MARK: F2-2

    @Test("F2-2: soltar en otra columna cambia solo la línea `estado` (ni `cerrada` ni el sitio) y lo apunta en la Actividad")
    func criterio2Arrastrar() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let ruta = VaultPath("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md")
        let url = ruta.url(in: e.carpeta)
        let antes = try String(contentsOf: url, encoding: .utf8)
        let huellas = Self.huellas(e.carpeta)
        let modelo = ModeloTareas(sesion: sesion)
        await modelo.cargar()
        #expect(modelo.fila(ruta)?.estado == .enRevision)
        // Lo que hace soltar la tarjeta en la columna Hecha (o «Mover a…» o VoiceOver).
        #expect(await modelo.mover(ruta, a: .hecha))
        let despues = try String(contentsOf: url, encoding: .utf8)
        #expect(Self.cambiados(huellas, Self.huellas(e.carpeta)) == [ruta.raw])
        // Propiedades: una sola línea cambia, la de `estado`; nada de `cerrada`.
        let fmAntes = antes.components(separatedBy: "\n---\n")[0].components(separatedBy: "\n")
        let fmDespues = despues.components(separatedBy: "\n---\n")[0].components(separatedBy: "\n")
        #expect(fmAntes.count == fmDespues.count)
        let distintas = zip(fmAntes, fmDespues).filter { $0 != $1 }
        #expect(distintas.count == 1)
        #expect(distintas.first?.1 == "estado: Hecha")
        #expect(!despues.contains("cerrada:"))
        // El cuerpo solo crece al final de la Actividad.
        let cuerpoAntes = antes.components(separatedBy: "\n---\n").dropFirst().joined(separator: "\n---\n")
        let cuerpoDespues = despues.components(separatedBy: "\n---\n").dropFirst().joined(separator: "\n---\n")
        #expect(cuerpoDespues.hasPrefix(cuerpoAntes.trimmingCharacters(in: .newlines)))
        let ultima = try #require(ActividadDeTarea.leer(despues).last)
        #expect(ultima.autor == "Manu")
        #expect(ultima.texto == "Estado: En revisión → Hecha.")
        #expect(despues.contains("\"desde\":\"tablero\""))
        // Ya está ahí: no escribe.
        #expect(!(await modelo.mover(ruta, a: .hecha)))
    }

    @Test("F2-2: ⌘→ y ⌘← con la tarjeta elegida van a la columna de al lado; Deshacer deja los mismos bytes")
    func criterio2Teclado() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let ruta = VaultPath("6 · Equipo/Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md")
        let url = ruta.url(in: e.carpeta)
        let antes = try Data(contentsOf: url)
        let modelo = ModeloTareas(sesion: sesion)
        modelo.consulta.vista = .tablero
        await modelo.cargar()
        modelo.elegida = ruta
        #expect(await modelo.moverAlLado(ruta, paso: 1)) // En revisión → Bloqueada
        #expect(modelo.fila(ruta)?.estado == .bloqueada)
        #expect(await modelo.moverAlLado(ruta, paso: -1)) // → En revisión
        #expect(modelo.fila(ruta)?.estado == .enRevision)
        let texto = try String(contentsOf: url, encoding: .utf8)
        #expect(ActividadDeTarea.leer(texto).count == 2)
        // Deshacer las dos deja el fichero como estaba.
        for _ in 0..<2 {
            let ultimo = try #require(await sesion.bus?.ultimoDeshacible())
            await sesion.deshacer(plan: ultimo.planID)
        }
        await pruebas.esperar { (try? Data(contentsOf: url)) == antes }
        #expect(try Data(contentsOf: url) == antes)
    }

    @Test("F2-2: un número repetido se renumera y su fichero se renombra en la misma operación")
    func renumerar() async throws {
        let (e, sesion) = try await abrir { raiz in
            // Una tarea copiada de otra carpeta con el mismo número (creada después: es la que cambia).
            try Self.escribir("""
            ---
            tls_type: task
            tls_schema: 1
            id: 7c1d2e3f-0000-4000-8000-000000000001
            numero: T-0001
            titulo: Revisar precios de la competencia
            estado: Por hacer
            creada: 2026-10-20
            ---
            # Revisar precios de la competencia

            ## Descripción
            Mirar tres asesorías online.

            ## Actividad
            """, en: "2 · Ventas/Tareas/t-0001-revisar-precios-de-la-competencia.md", raiz)
            try Self.escribir("Ver [[t-0001-revisar-precios-de-la-competencia]].\n", en: "2 · Ventas/Nota de precios.md", raiz)
        }
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloTareas(sesion: sesion)
        await modelo.cargar()
        #expect(modelo.revision.duplicados.count == 1)
        #expect(modelo.revision.duplicados.first?.first?.titulo == "¿Subir Trimestrales a 165 € desde T1 2027?")
        await modelo.renumerarRepetidas()
        let nueva = e.carpeta.appendingPathComponent("2 · Ventas/Tareas/t-0003-revisar-precios-de-la-competencia.md")
        #expect(FileManager.default.fileExists(atPath: nueva.path))
        #expect(!FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("2 · Ventas/Tareas/t-0001-revisar-precios-de-la-competencia.md").path))
        #expect(NoteDocument(text: try String(contentsOf: nueva, encoding: .utf8)).frontmatter.text("numero") == "T-0003")
        #expect(try String(contentsOf: e.carpeta.appendingPathComponent("2 · Ventas/Nota de precios.md"), encoding: .utf8)
            .contains("[[t-0003-revisar-precios-de-la-competencia]]"))
        #expect(try String(contentsOf: e.carpeta.appendingPathComponent(".tls/secuencias.json"), encoding: .utf8).contains("\"tarea\":3"))
        // La que se quedó con su número no cambió.
        #expect(FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md").path))
        #expect(modelo.revision.duplicados.isEmpty)
    }

    // MARK: Privado, heredados, Adoptar, mover, ENT-04 y menciones

    @Test("Lo privado no sale en Tareas ni en «Revisar», ni se renumera")
    func privado() async throws {
        let (e, sesion) = try await abrir { raiz in
            let config = raiz.appendingPathComponent(".tls/config.yaml")
            let t = try String(contentsOf: config, encoding: .utf8)
                .replacingOccurrences(of: "privado: []", with: "privado: [\"4 · Finanzas/Trámites/Expediente privado\"]")
            try Data(t.utf8).write(to: config)
            try Self.escribir("""
            ---
            tls_type: task
            numero: T-0001
            titulo: Renovar el documento
            estado: Por hacer
            responsable: gestor-del-tramite
            ---
            # Renovar el documento
            """, en: "4 · Finanzas/Trámites/Expediente privado/Tareas/t-0001-renovar-el-documento.md", raiz)
            try Self.escribir("- [ ] Llevar la copia · @area:FIN\n", en: "4 · Finanzas/Trámites/Expediente privado/Tareas.md", raiz)
        }
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloTareas(sesion: sesion)
        await modelo.cargar()
        #expect(modelo.filas.count == 2)
        #expect(!modelo.filas.contains { $0.ruta.raw.contains("privado") })
        #expect(modelo.revision.duplicados.isEmpty)
        #expect(modelo.revision.legados.isEmpty)
        modelo.consulta.busqueda = "documento"
        #expect(modelo.visibles.isEmpty)
        // Quien lleva algo privado tampoco sale para elegir responsable.
        #expect(!ResponsablesTarea.opciones(grafo: modelo.almacen.grafo, persona: "Manu").contains { $0.id == "gestor-del-tramite" })
        #expect(ResponsablesTarea.opciones(grafo: modelo.almacen.grafo, persona: "Manu").first?.id == "Manu")
    }

    @Test("Tareas.md heredado: tarjeta en «Revisar» y, con tu OK, una ficha por tarea y el fichero al Archivo")
    func heredados() async throws {
        let (e, sesion) = try await abrir { raiz in
            try Self.escribir("""
            # Tareas

            - [ ] Llamar a Jorge por la renovación · 2026-10-24 · vence 2026-10-30 · Urgente · 2h · @area:VEN · #a1
            - [x] Enviar el presupuesto a Panadería Sol · @area:VEN · #a2
            - [ ] Revisar objeciones · @est:Esperando respuesta · responsable Ana
            """, en: "2 · Ventas/Tareas.md", raiz)
        }
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloTareas(sesion: sesion)
        await modelo.cargar()
        let legado = try #require(modelo.revision.legados.first)
        #expect(legado.fichero.raw == "2 · Ventas/Tareas.md")
        #expect(legado.titulos.count == 3)
        // Nada se escribe sin el clic.
        #expect(FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("2 · Ventas/Tareas.md").path))
        await modelo.aplicar(RevisionTareas.planHeredados, aviso: "Pasé a fichas 3 tareas heredadas")
        #expect(!FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("2 · Ventas/Tareas.md").path))
        #expect(FileManager.default.fileExists(atPath: e.carpeta.appendingPathComponent("Archivo/2 · Ventas/Tareas.md").path))
        let nuevas = modelo.filas.filter { $0.area == .ventas }
        #expect(nuevas.count == 3)
        #expect(Set(nuevas.map(\.numero)) == ["T-0003", "T-0004", "T-0005"])
        let llamar = try #require(nuevas.first { $0.titulo.hasPrefix("Llamar a Jorge") })
        #expect(llamar.tarea.planificada?.description == "2026-10-26") // el sábado pasa al lunes
        #expect(llamar.estimacionH == 2)
        #expect(nuevas.contains { $0.estado == .hecha })
        #expect(modelo.revision.legados.isEmpty)
    }

    @Test("Adoptar: identidad y relaciones propuestas en una sola tarjeta y un solo plan")
    func adoptar() async throws {
        let (e, sesion) = try await abrir { raiz in
            // Una tarea de G3 sin identidad, con el enlace a su oportunidad en el texto.
            try Self.escribir("""
            ---
            numero: T-0007
            titulo: Llamar a Jorge
            estado: Pendiente
            ---
            # Llamar a Jorge

            Para [[javier-ortega-renta]].
            """, en: "2 · Ventas/Tareas/t-0007-llamar-a-jorge.md", raiz)
        }
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloTareas(sesion: sesion)
        await modelo.cargar()
        let a = modelo.revision.adopcion
        #expect(a.identidades >= 1)
        let ruta = "2 · Ventas/Tareas/t-0007-llamar-a-jorge.md"
        await modelo.aplicar(RevisionTareas.planAdoptar, aviso: "Adopté la carpeta")
        let fm = NoteDocument(text: try String(contentsOf: e.carpeta.appendingPathComponent(ruta), encoding: .utf8)).frontmatter
        #expect(fm.text("tls_type") == "task")
        #expect(fm.text("id") != nil)
        #expect(modelo.revision.adopcion.identidades == 0)
        // El estado heredado se lee con su nombre de ahora.
        #expect(modelo.fila(VaultPath(ruta))?.estado == .porHacer)
    }

    @Test("Ficha: «Mover a…» otra área, ENT-04 al planificar, «Empezar ahora» y comentario con mención guardada")
    func ficha() async throws {
        let (e, sesion) = try await abrir()
        defer { sesion.close(); e.limpiar() }
        let ruta = try await NuevaTareaHoja.crear(titulo: "Pedir la documentación del trimestre", area: .direccion, proyecto: nil,
                                                  responsable: "agente:comercial", planificada: nil, sesion: sesion)
        let modelo = ModeloTarea(ruta: ruta, sesion: sesion)
        await modelo.cargar()
        #expect(modelo.tarea?.estado == .sinProgramar)
        #expect(EstadoAsistenteTarea.de(try #require(modelo.tarea), hoy: modelo.hoy) == .sinEmpezar)
        // ENT-04: el sábado 24 pasa al lunes 26 y se dice.
        await modelo.planificar(LocalDate(year: 2026, month: 10, day: 24)!)
        #expect(modelo.tarea?.planificada?.description == "2026-10-26")
        #expect(modelo.avisoPlanificada?.contains("lunes") == true)
        // «Empezar ahora» con un asistente: Por hacer y planificada hoy (la coge en cuanto estén encendidos).
        await modelo.planificar(nil)
        await modelo.empezarAhora()
        #expect(modelo.tarea?.estado == .porHacer)
        #expect(modelo.tarea?.planificada == modelo.hoy)
        #expect(EstadoAsistenteTarea.de(try #require(modelo.tarea), hoy: modelo.hoy) == .enCola)
        // Comentario con @: se guarda la mención en el evento.
        #expect(await modelo.comentar("Usa la plantilla nueva, @agente:comercial"))
        let texto = try String(contentsOf: ruta.url(in: e.carpeta), encoding: .utf8)
        #expect(texto.contains("\"menciones\":\"agente:comercial\""))
        // La lectura de la ficha se rehace con la revisión de la sesión (como hace la pantalla).
        for _ in 0..<40 where modelo.entradas.last?.menciones != ["agente:comercial"] {
            try await Task.sleep(for: .milliseconds(100))
            await modelo.cargar()
        }
        #expect(modelo.entradas.last?.menciones == ["agente:comercial"])
        // «Mover a…» Ventas: el fichero cambia de carpeta y `area` dice la nueva, en un solo plan.
        let nueva = try #require(await modelo.mover(a: .area(.ventas)))
        #expect(nueva.raw == "2 · Ventas/Tareas/" + ruta.name)
        #expect(!FileManager.default.fileExists(atPath: ruta.url(in: e.carpeta).path))
        let fm = NoteDocument(text: try String(contentsOf: nueva.url(in: e.carpeta), encoding: .utf8)).frontmatter
        #expect(fm.text("area") == "ventas")
        #expect(fm.text("numero") == "T-0003")
    }
}
