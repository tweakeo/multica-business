import Foundation
import Testing
@testable import TLSCore

/// Ribera (ficticia) leída del repositorio sin tocarla, y copias temporales para escribir.
enum RelacionesApoyo {
    static var ribera: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    static let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")
    static let sergio = VaultPath("2 · Ventas/Contactos/sergio-nexo.md")
    static let talleres = VaultPath("2 · Ventas/Empresas/talleres-martin-e-hijos.md")
    static let nexo = VaultPath("2 · Ventas/Empresas/arquitectura-nexo.md")
    static let opoJorge = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
    static let opoSergio = VaultPath("2 · Ventas/Oportunidades/sergio-nexo-trimestrales.md")
    static let propuestaJorge = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales/Propuesta v1.md")
    static let facturaJorge = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
    static let planTrimestrales = VaultPath("3 · Entrega/Planes de entrega/trimestrales.md")

    static func foto() -> VaultSnapshot { VaultSnapshot.read(root: ribera) }

    /// Copia de Ribera en una carpeta temporal propia, con estado y cerrojos aparte.
    struct Copia {
        let base: URL
        let root: URL
        let entry: VaultEntry
        var options: VaultWriter.Options {
            VaultWriter.Options(stateDirectory: base.appendingPathComponent("estado"), appSupport: base.appendingPathComponent("asup"),
                                app: "The Last System pruebas")
        }
        func bus() async throws -> CommandBus { CommandBus(writer: try await VaultWriter.open(entry: entry, root: root, options: options)) }
        func datos(_ p: VaultPath) -> Data? { try? Data(contentsOf: p.url(in: root)) }
        func texto(_ p: VaultPath) -> String { datos(p).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        func escribirFixture(_ p: VaultPath, _ texto: String) throws {
            let u = p.url(in: root)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(texto.utf8).write(to: u)
        }
        func foto() -> VaultSnapshot { VaultSnapshot.read(root: root) }
        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    static func copia() throws -> Copia {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-relaciones-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Ribera", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: ribera, to: root)
        let entry = VaultEntry(nombre: "Asesoría Ribera", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida)
        return Copia(base: base, root: root, entry: entry)
    }

    /// Líneas distintas entre dos textos con el mismo número de líneas (o `nil` si cambia el número).
    static func lineasDistintas(_ a: String, _ b: String) -> Int? {
        let la = a.components(separatedBy: "\n"), lb = b.components(separatedBy: "\n")
        guard la.count == lb.count else { return nil }
        return zip(la, lb).filter { $0 != $1 }.count
    }

    static let reunion = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales/Reuniones/2026-10-09-descubrimiento-trimestrales.md")
    static let textoReunion = """
    ---
    tls_type: meeting
    tls_schema: 1
    id: 7d6b1c1e-0000-4000-8000-000000000001
    titulo: Descubrimiento · Trimestrales · Talleres Martín
    tipo: descubrimiento
    estado: Hecha
    fecha: 2026-10-09
    personas: []
    empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
    oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
    ---
    # Descubrimiento · Trimestrales · Talleres Martín

    ## Qué se habló
    «Que en enero no me tenga que acordar de nada.»

    """
}

@Suite("Relaciones · grafo de Ribera")
struct GrafoRelacionesTests {
    let grafo = GrafoRelaciones(snapshot: RelacionesApoyo.foto())
    typealias A = RelacionesApoyo

    @Test("Lee las relaciones de las propiedades en los dos sentidos")
    func dosSentidos() {
        #expect(grafo.ficha(A.jorge)?.tipo == .contact)
        #expect(grafo.ficha(A.jorge)?.nombre == "Jorge Martín")
        #expect(grafo.destinos(de: A.jorge, propiedad: "empresa") == [A.talleres])
        let aTalleres = Set((grafo.entrantes[A.talleres] ?? []).map(\.origen))
        #expect(aTalleres.contains(A.jorge))
        #expect(aTalleres.contains(A.opoJorge))
        #expect(aTalleres.contains(A.facturaJorge))
        // `servicio` con ruta (`[[2 · Ventas/Productos/trimestrales|…]]`) va al servicio, no al plan de entrega.
        #expect(grafo.destinos(de: A.opoJorge, propiedad: "servicio") == [VaultPath("2 · Ventas/Productos/trimestrales.md")])
    }

    @Test("Lo relacionado con Jorge: su oportunidad, su factura y su propuesta, por la propiedad que lo guarda")
    func relacionadosDeJorge() {
        let r = grafo.relacionados(de: A.jorge)
        let porRuta = Dictionary(uniqueKeysWithValues: r.map { ($0.ficha.ruta, $0) })
        #expect(porRuta[A.opoJorge]?.via == .directa(propiedad: "contacto"))
        #expect(porRuta[A.facturaJorge]?.via == .directa(propiedad: "contacto"))
        #expect(porRuta[A.propuestaJorge] != nil)
        #expect(!r.contains { $0.ficha.ruta == A.jorge })
        // De la empresa: su persona, su oportunidad y su factura.
        let deTalleres = Set(grafo.relacionados(de: A.talleres).map(\.ficha.ruta))
        #expect(deTalleres.isSuperset(of: [A.jorge, A.opoJorge, A.facturaJorge]))
    }

    @Test("Ganada sin cobro confirmado por una persona: bloqueada, con el motivo")
    func ganadaBloqueada() {
        let jorge = grafo.cobroConfirmado(oportunidad: A.opoJorge)
        #expect(!jorge.confirmado)
        #expect(jorge.motivo.contains("F-2026-0007"))
        #expect(jorge.motivo.contains("cobro confirmado por una persona"))
        let lucia = grafo.cobroConfirmado(oportunidad: VaultPath("2 · Ventas/Oportunidades/lucia-ferrer-renta.md"))
        #expect(lucia.confirmado)
        let sinFactura = grafo.cobroConfirmado(oportunidad: A.opoSergio)
        #expect(!sinFactura.confirmado)
        #expect(sinFactura.motivo.contains("aún no tiene factura"))
    }

    @Test("Esquema: quién guarda cada relación")
    func esquema() {
        #expect(EsquemaRelaciones.quienGuarda(apuntandoA: .project, desde: .task)?.propiedad == "proyecto")
        #expect(EsquemaRelaciones.quienGuarda(apuntandoA: .contact, desde: .meeting)?.propiedad == "personas")
        #expect(EsquemaRelaciones.quienGuarda(apuntandoA: .organization, desde: .project)?.propiedad == "empresa")
        #expect(EsquemaRelaciones.definicion(tipo: .opportunity, propiedad: "empresa_id")?.propiedad == "empresa")
        #expect(EsquemaRelaciones.definicion(tipo: .meeting, propiedad: "personas")?.cardinalidad == .varias)
        #expect(EsquemaRelaciones.definicion(tipo: .project, propiedad: "oportunidad")?.unicaEnDestino == true)
    }
}

@Suite("Relaciones · preparar un cambio (una línea, reglas)")
struct EditorDeRelacionesTests {
    typealias A = RelacionesApoyo
    let editor = EditorDeRelaciones(snapshot: RelacionesApoyo.foto())

    @Test("Cambiar la empresa de Jorge: una línea, con la línea antes y después y confirmación")
    func cambiarEmpresa() throws {
        let p = try editor.preparar(CambioDeRelacion(dueno: A.jorge, propiedad: "empresa", accion: .poner(A.nexo)))
        #expect(p.pideConfirmacion)
        #expect(!p.sinCambios)
        #expect(p.lineas.antes == #"empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]""#)
        #expect(p.lineas.despues == #"empresa: "[[arquitectura-nexo|Arquitectura Nexo SLP]]""#)
        #expect(p.aviso.contains("Arquitectura Nexo SLP"))
        guard case .cambiarPropiedades(let ruta, let poner, let quitar) = p.comando else {
            Issue.record("No es un cambio de propiedades"); return
        }
        #expect(ruta == A.jorge)
        #expect(poner.map(\.key) == ["empresa"])
        #expect(quitar.isEmpty)
    }

    @Test("Poner lo que ya está no cambia nada")
    func sinCambios() throws {
        let p = try editor.preparar(CambioDeRelacion(dueno: A.jorge, propiedad: "empresa", accion: .poner(A.talleres)))
        #expect(p.sinCambios)
    }

    @Test("Una obligatoria no se quita; una opcional sí")
    func obligatoria() throws {
        #expect(throws: ProblemaDeRelacion.self) {
            try editor.preparar(CambioDeRelacion(dueno: A.opoJorge, propiedad: "empresa", accion: .quitar(nil)))
        }
        let p = try editor.preparar(CambioDeRelacion(dueno: A.jorge, propiedad: "empresa", accion: .quitar(A.talleres)))
        #expect(p.lineas.despues == nil)
        #expect(p.aviso == "Quité Talleres Martín e Hijos SL de Jorge Martín")
    }

    @Test("Una relación no admite fichas de otro tipo")
    func tipoNoAdmitido() {
        #expect(throws: ProblemaDeRelacion.self) {
            try editor.preparar(CambioDeRelacion(dueno: A.jorge, propiedad: "empresa", accion: .poner(A.sergio)))
        }
    }

    @Test("Una factura emitida no se cambia")
    func facturaEmitida() {
        #expect(throws: ProblemaDeRelacion.self) {
            try editor.preparar(CambioDeRelacion(dueno: A.facturaJorge, propiedad: "empresa", accion: .poner(A.nexo)))
        }
    }

    @Test("El enlace usa el nombre del fichero si es único y la ruta si se repite")
    func enlaces() {
        #expect(editor.enlace(a: A.talleres) == "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]")
        #expect(editor.enlace(a: VaultPath("2 · Ventas/Productos/trimestrales.md")) == "[[2 · Ventas/Productos/trimestrales|Trimestrales]]")
        let nueva = VaultPath("2 · Ventas/Empresas/clinica-nueva.md")
        #expect(editor.enlace(a: nueva, nombre: "Clínica Nueva", nuevas: [nueva]) == "[[clinica-nueva|Clínica Nueva]]")
    }

    @Test("En cadena: la propuesta cambia; la factura emitida no")
    func colgantes() {
        let c = editor.colgantes(de: A.opoJorge, propiedad: "empresa", viejo: A.talleres)
        #expect(c.cambiables == [A.propuestaJorge])
        #expect(c.fijas == [A.facturaJorge])
    }
}

@Suite("Relaciones · escribir y deshacer en una copia", .serialized)
struct EscribirRelacionesTests {
    typealias A = RelacionesApoyo

    @Test("Añadir desde el lado que no la guarda cambia una línea en la que la guarda; deshacer deja los mismos bytes")
    func unaLineaYDeshacer() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try c.escribirFixture(A.reunion, A.textoReunion)
        let antes = try #require(c.datos(A.reunion))
        let jorgeAntes = try #require(c.datos(A.jorge))
        let editor = EditorDeRelaciones(snapshot: c.foto())
        // Desde la ficha de Jorge, «Añadir existente…» en Reuniones: se escribe en la reunión (`personas`).
        let def = try #require(EsquemaRelaciones.quienGuarda(apuntandoA: .contact, desde: .meeting))
        let p = try editor.preparar(CambioDeRelacion(dueno: A.reunion, propiedad: def.propiedad, accion: .anadir(A.jorge)))
        #expect(p.lineas.antes == "personas: []")
        #expect(p.lineas.despues == #"personas: ["[[jorge-martin|Jorge Martín]]"]"#)
        let bus = try await c.bus()
        let r = try await bus.ejecutar(p.comando, autor: .persona("Manu"))
        #expect(r.hecho)
        #expect(A.lineasDistintas(String(decoding: antes, as: UTF8.self), c.texto(A.reunion)) == 1)
        #expect(c.datos(A.jorge) == jorgeAntes)
        // La relación ya se lee desde Jorge.
        let g = GrafoRelaciones(snapshot: c.foto())
        #expect(g.relacionados(de: A.jorge).contains { $0.ficha.ruta == A.reunion && $0.via == .directa(propiedad: "personas") })
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.datos(A.reunion) == antes)
    }

    @Test("Quitar a una persona de la lista deja la lista sin ella; deshacer, los mismos bytes")
    func quitarDeLista() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        try c.escribirFixture(A.reunion, A.textoReunion.replacingOccurrences(
            of: "personas: []", with: #"personas: ["[[jorge-martin|Jorge Martín]]", "[[sergio-nexo|Sergio Nexo]]"]"#))
        let antes = try #require(c.datos(A.reunion))
        let p = try EditorDeRelaciones(snapshot: c.foto())
            .preparar(CambioDeRelacion(dueno: A.reunion, propiedad: "personas", accion: .quitar(A.jorge)))
        #expect(p.lineas.despues == #"personas: ["[[sergio-nexo|Sergio Nexo]]"]"#)
        let bus = try await c.bus()
        _ = try await bus.ejecutar(p.comando, autor: .persona("Manu"))
        #expect(A.lineasDistintas(String(decoding: antes, as: UTF8.self), c.texto(A.reunion)) == 1)
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.datos(A.reunion) == antes)
    }

    @Test("Una oportunidad tiene como mucho un proyecto")
    func unica() throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let proyecto = """
        ---
        tls_type: project
        nombre: Trimestrales 2026
        clase: entrega
        estado: En curso
        oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
        empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
        ---
        # Trimestrales 2026

        """
        try c.escribirFixture(VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md"), proyecto)
        let otro = VaultPath("3 · Entrega/Proyectos/otro/Proyecto.md")
        try c.escribirFixture(otro, proyecto.replacingOccurrences(of: "oportunidad: \"[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]\"\n", with: ""))
        let editor = EditorDeRelaciones(snapshot: c.foto())
        do {
            _ = try editor.preparar(CambioDeRelacion(dueno: otro, propiedad: "oportunidad", accion: .poner(A.opoJorge)))
            Issue.record("Debía impedir un segundo proyecto")
        } catch let ProblemaDeRelacion.unica(existente, mensaje) {
            #expect(existente == VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md"))
            #expect(mensaje.contains("Como mucho, uno"))
        }
        // El enlace a un `Proyecto.md` (nombre repetido) se escribe con su ruta.
        #expect(editor.enlace(a: otro).hasPrefix("[[3 · Entrega/Proyectos/otro/Proyecto|"))
    }

    @Test("En cadena: un plan, todo o nada, y un solo Deshacer deja los mismos bytes en las dos fichas")
    func enCadena() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let opo = try #require(c.datos(A.opoJorge))
        let prop = try #require(c.datos(A.propuestaJorge))
        let fac = try #require(c.datos(A.facturaJorge))
        let editor = EditorDeRelaciones(snapshot: c.foto())
        let p = try editor.preparar(CambioDeRelacion(dueno: A.opoJorge, propiedad: "empresa", accion: .poner(A.nexo)))
        let colgantes = editor.colgantes(de: A.opoJorge, propiedad: "empresa", viejo: A.talleres)
        let plan = try editor.enCadena(p, colgantes: colgantes.cambiables, autor: .persona("Manu"))
        #expect(plan.ops.count == 2)
        let bus = try await c.bus()
        let r = try await bus.ejecutar(plan)
        #expect(r.hecho)
        #expect(A.lineasDistintas(String(decoding: opo, as: UTF8.self), c.texto(A.opoJorge)) == 1)
        #expect(A.lineasDistintas(String(decoding: prop, as: UTF8.self), c.texto(A.propuestaJorge)) == 1)
        #expect(c.datos(A.facturaJorge) == fac)
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.datos(A.opoJorge) == opo)
        #expect(c.datos(A.propuestaJorge) == prop)
    }

    @Test("Crear al vuelo y enlazar es un solo paso de deshacer")
    func crearAlVuelo() async throws {
        let c = try A.copia()
        defer { c.limpiar() }
        let jorge = try #require(c.datos(A.jorge))
        let foto = c.foto()
        let motor = PlantillaMotor(snapshot: foto, opciones: .init(yo: "Manu"))
        let nota = try motor.preparar(PlantillaMotor.Peticion(plantilla: "empresa", valores: ["titulo": "Clínica Nueva"],
                                                              autor: .persona("Manu")))
        let plan = try EditorDeRelaciones(snapshot: foto)
            .crearYEnlazar(nota, nombre: "Clínica Nueva", dueno: A.jorge, propiedad: "empresa", autor: .persona("Manu"))
        let bus = try await c.bus()
        let r = try await bus.ejecutar(plan)
        #expect(r.hecho)
        #expect(FileManager.default.fileExists(atPath: nota.ruta.url(in: c.root).path))
        #expect(c.texto(A.jorge).contains("empresa: \"[[\(nota.ruta.stem)|Clínica Nueva]]\""))
        #expect(A.lineasDistintas(String(decoding: jorge, as: UTF8.self), c.texto(A.jorge)) == 1)
        _ = try await bus.deshacer(autor: .persona("Manu"))
        #expect(c.datos(A.jorge) == jorge)
        #expect(!FileManager.default.fileExists(atPath: nota.ruta.url(in: c.root).path))
    }
}

@Suite("Relaciones · plan de entrega, actividad, estados y diferencias")
struct LecturasDeFichaTests {
    typealias A = RelacionesApoyo

    @Test("Fases del plan de Trimestrales con sus fechas desde el arranque")
    func fases() throws {
        let foto = A.foto()
        let plan = PlanDeEntrega.leer(try #require(foto.text(A.planTrimestrales)))
        #expect(plan.fases.map(\.nombre) == ["Recogida", "Contabilidad", "Modelos", "Presentación"])
        #expect(plan.fases[0].diaInicio == 0)
        #expect(plan.fases[0].diaFin == 2)
        #expect(plan.fases[1].tareas.count == 2)
        #expect(plan.terminadoCuando?.hasPrefix("Modelos presentados") == true)
        let inicio = try #require(LocalDate(parsing: "2026-10-22"))
        let tarea = FichaGrafo(ruta: VaultPath("3 · Entrega/Proyectos/x/Tareas/t-0042-x.md"), tipo: .task,
                               nombre: "Solicitar facturas emitidas, recibidas y extractos del trimestre",
                               propiedades: Frontmatter(properties: [Property(key: "estado", value: .text("En revisión"))], isValid: true),
                               privada: false)
        let f = FasesDelPlan.delProyecto(plan: plan, inicio: inicio, tareas: [tarea], hoy: inicio)
        #expect(f[0].inicio == inicio)
        #expect(f[0].fin == LocalDate(parsing: "2026-10-26"))
        #expect(f[0].tareas == [tarea.ruta])
        #expect(f[0].situacion == .enCurso)
        #expect(f[1].situacion == .pendiente)
    }

    @Test("Actividad: entradas de Actividad, Historial y lo importado, lo último primero")
    func actividad() throws {
        let foto = A.foto()
        let factura = ActividadDeFicha.leer(try #require(foto.text(A.facturaJorge)))
        #expect(factura.first?.texto == "Emitida como F-2026-0007")
        #expect(factura.first?.fecha == LocalDate(parsing: "2026-10-15"))
        let jorge = ActividadDeFicha.leer(try #require(foto.text(A.jorge)))
        #expect(jorge.first?.texto.hasPrefix("Llegó a la carpeta") == true)
        let tarea = """
        ---
        tls_type: task
        ---
        # Pedir la documentación
        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->
        ### 2026-10-22 09:05 · agente:implementador
        Preparé el correo a Jorge.
        <!-- tls:evento {"id":"ev-1","tipo":"comentario"} -->

        ### 2026-10-22 10:30 · Manu
        Estado: Por hacer → En revisión.
        <!-- tls:evento {"a":"En revisión","de":"Por hacer","id":"ev-2","tipo":"estado"} -->
        """
        let a = ActividadDeFicha.leer(tarea)
        #expect(a.count == 2)
        #expect(a[0].tipo == .cambio)
        #expect(a[0].autor == "Manu")
        #expect(a[1].tipo == .asistente)
        #expect(a[1].autor == "Implementador (asistente)")
        #expect(a[1].texto == "Preparé el correo a Jorge.")
    }

    @Test("Responsables: identificador estable y nombre que se enseña")
    func responsables() {
        #expect(Responsables.nombre(de: "agente:implementador") == "Implementador (asistente)")
        #expect(Responsables.nombre(de: "lucia") == "Lucia")
        #expect(Responsables.identificador(persona: "Lucía Andreu") == "lucia-andreu")
        let g = GrafoRelaciones(snapshot: A.foto())
        let ops = Responsables.opciones(grafo: g, persona: "Manu")
        #expect(ops.first?.id == "Manu")
        #expect(ops.contains { $0.id == "agente:comercial" })
    }

    @Test("Estados: lo abierto cuenta, lo urgente primero y lo cerrado al final")
    func estados() throws {
        #expect(EstadosDeFicha.abierta(.opportunity, estado: "Aceptada"))
        #expect(!EstadosDeFicha.abierta(.opportunity, estado: "Ganada"))
        #expect(EstadosDeFicha.abierta(.invoice, estado: "Emitida"))
        #expect(!EstadosDeFicha.abierta(.invoice, estado: "Cobrada"))
        #expect(!EstadosDeFicha.abierta(.task, estado: "Hecha"))
        #expect(EstadosDeFicha.esperaTuOK(.task, estado: "En revisión"))
        let hoy = try #require(LocalDate(parsing: "2026-10-22"))
        func f(_ n: String, _ estado: String, vence: String? = nil) -> FichaGrafo {
            var p = [Property(key: "estado", value: .text(estado))]
            if let vence { p.append(Property(key: "vence", value: .text(vence))) }
            return FichaGrafo(ruta: VaultPath("\(n).md"), tipo: .task, nombre: n, propiedades: Frontmatter(properties: p, isValid: true), privada: false)
        }
        let orden = EstadosDeFicha.ordenar([f("hecha", "Hecha"), f("luego", "Por hacer", vence: "2026-12-01"),
                                            f("revisar", "En revisión"), f("vencida", "Por hacer", vence: "2026-10-01"),
                                            f("hoy", "Por hacer", vence: "2026-10-22")], hoy: hoy).map(\.nombre)
        #expect(orden == ["revisar", "vencida", "hoy", "luego", "hecha"])
        #expect(EstadosDeFicha.escrito("Montado", como: "a medias") == "montado")
    }

    @Test("Líneas cambiadas: solo las nuevas o distintas")
    func diferencias() {
        let antes = "a\nb\nc\nd"
        let despues = "a\nB\nc\nd\ne"
        #expect(DiferenciaDeLineas.cambiadas(antes: antes, despues: despues) == [1, 4])
        #expect(DiferenciaDeLineas.cambiadas(antes: antes, despues: antes).isEmpty)
    }
}

@Suite("Relaciones · secciones y tablas de una nota")
struct SeccionesYTablasTests {
    @Test("Solo las secciones ##, sin el título de la nota ni las de otro nivel, y sin repetir")
    func titulos() {
        let cuerpo = "# Factura F-1\n> resumen\n\n## Partes\ntexto\n### Detalle\nmás\n## Conceptos\n| a | b |\n|---|---|\n| 1 | 2 |\n## Partes\notra\n"
        #expect(MarkdownSections.titles(in: cuerpo, level: 2) == ["Partes", "Conceptos"])
        #expect(MarkdownSections.titles(in: cuerpo, level: 3) == ["Detalle"])
    }

    @Test("Una tabla Markdown: cabecera, filas, `\\|` dentro de una celda y la negrita del total")
    func tabla() throws {
        let t = try #require(TablaMarkdown.leer(["| Concepto | Importe |", "|---|---:|", "| Base \\| neta | 150,00 € |", "| **Total** | **181,50 €** |"]))
        #expect(t.cabecera == ["Concepto", "Importe"])
        #expect(t.filas == [["Base | neta", "150,00 €"], ["**Total**", "**181,50 €**"]])
        #expect(TablaMarkdown.sinNegrita(t.filas[1][1]) == ("181,50 €", true))
        #expect(TablaMarkdown.leer(["| solo una línea |"]) == nil)
        #expect(TablaMarkdown.leer(["| a |", "| b |"]) == nil)
    }
}
