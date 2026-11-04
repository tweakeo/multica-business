import Foundation
import Testing
import TLSCore
@testable import TLSImport

@Suite("Conversor G2 · piezas")
struct PiezasConversor {
    @Test("Lee mapas y listas de mapas anidados del frontmatter de G2")
    func yamlAnidado() throws {
        let yaml = """
        name: Trimestrales
        template:
          done_when: Modelos presentados antes del día 20.
          phases:
            - name: Recogida
              tasks:
                - acceptance: Inventario de documentos.
                  assignee: agent:entrega
                  duration: 3
                  offset: 0
            - name: Modelos
              tasks:
                - title: 'Borradores: 303 y 111'
                  due_slack: 0
        areas:
            - code: ventas
              transforms: Desconocidos en clientes
        refs: []
        balance: 1.84e+06
        """
        let m = try #require(G2YAML.leer(yaml))
        let plantilla = try #require(m.mapa("template"))
        #expect(plantilla.texto("done_when") == "Modelos presentados antes del día 20.")
        let fases = plantilla.lista("phases").compactMap(\.mapa)
        #expect(fases.map { $0.texto("name") } == ["Recogida", "Modelos"])
        let tarea = try #require(fases[0].lista("tasks").first?.mapa)
        #expect(tarea.texto("assignee") == "agent:entrega")
        #expect(tarea.entero("duration") == 3)
        #expect(fases[1].lista("tasks").first?.mapa?.texto("title") == "Borradores: 303 y 111")
        #expect(m.lista("areas").first?.mapa?.texto("transforms") == "Desconocidos en clientes")
        #expect(m.lista("refs").isEmpty)
        #expect(m.entero("balance") == 1_840_000)
    }

    @Test("Fechas de G2 en hora de Madrid")
    func fechas() {
        #expect(G2Fecha.dia("2026-10-19T23:52:07.147465+02:00") == "2026-10-19")
        #expect(G2Fecha.dia("2026-10-19T22:30:00Z") == "2026-10-20")
        #expect(G2Fecha.dia("2026-03-29T00:30:00Z") == "2026-03-29")
        #expect(G2Fecha.dia("2026-10-30") == "2026-10-30")
        #expect(G2Fecha.lunes(semanaISO: "2026-W42") == "2026-10-12")
        #expect(G2Fecha.corta("2026-09-05") == "5 sept")
        #expect(G2Fecha.limites(anio: 2028, trimestre: 1).hasta == "2028-03-31")
    }

    @Test("Nombres de fichero, formas jurídicas y enlaces relativos")
    func nombres() {
        #expect(Nombres.kebab("Talleres Martín e Hijos SL") == "talleres-martin-e-hijos-sl")
        #expect(Nombres.kebab("¿Subir Trimestrales a 165 € desde T1 2027?") == "subir-trimestrales-a-165-desde-t1-2027")
        #expect(Nombres.kebab(String(repeating: "palabra ", count: 20)).count <= 60)
        #expect(Nombres.sinHuellaG2("jorge-martin--bcceae65") == "jorge-martin")
        #expect(Nombres.sinHuellaG2("trim-v1") == "trim-v1")
        #expect(Nombres.sinFormaJuridica(slug: "clinica-dental-sonrisa-slp") == "clinica-dental-sonrisa")
        #expect(Nombres.sinFormaJuridica(slug: "sl") == "sl")
        #expect(Nombres.sinFormaJuridica(nombre: "Inmobiliaria Centro S.L.") == "Inmobiliaria Centro")
        let desde = VaultPath("6 · Equipo/Roles/comercial.md")
        #expect(Nombres.rutaRelativa(desde: desde, a: VaultPath("2 · Ventas/Activos/guion.md"))
                == "../../2%20·%20Ventas/Activos/guion.md")
        #expect(Nombres.rutaRelativa(desde: VaultPath("Empresa.md"), a: VaultPath("1 · Dirección/Área.md"))
                == "1%20·%20Dirección/Área.md")
        // El enlace que escribimos lo resuelve el núcleo.
        let resolver = LinkResolver(paths: [desde, VaultPath("2 · Ventas/Activos/guion.md")])
        #expect(resolver.resolve(Nombres.rutaRelativa(desde: desde, a: VaultPath("2 · Ventas/Activos/guion.md")), from: desde)?.raw
                == "2 · Ventas/Activos/guion.md")
    }

    @Test("Identificadores derivados: estables y con forma de UUID v5")
    func ids() {
        let a = IDsDerivados.id("area:ventas")
        #expect(a == IDsDerivados.id("area:ventas"))
        #expect(a != IDsDerivados.id("area:entrega"))
        #expect(UUID(uuidString: a) != nil)
        #expect(Array(a)[14] == "5")
    }

    @Test("Importes exactos")
    func dinero() {
        #expect(Dinero.texto(15000) == "150.00")
        #expect(Dinero.texto(-7865) == "-78.65")
        #expect(Dinero.legible(1_840_000) == "18.400,00 €")
        #expect(Dinero.coma(66300) == "663,00")
        #expect(Dinero.porcentaje(puntosBasicos: 2100) == "21")
        #expect(Dinero.porcentaje(puntosBasicos: 1050) == "10.5")
        #expect(Dinero.porcentaje(parte: 12350, base: 65000) == "19")
        #expect(Dinero.porcentaje(parte: 1, base: 3) == nil)
        #expect(ConversionG2.centimos("-1.234,56", coma: true) == -123_456)
        #expect(ConversionG2.centimos("181.50", coma: false) == 18150)
    }

    /// Lo que escribimos en las propiedades lo vuelve a leer el núcleo con el mismo valor y el mismo tipo.
    @Test("Las propiedades escritas se leen igual", arguments: [
        "Asesoría Ribera (DEMO)", "Precio Renta 2026: 90 €", "¿Subir Trimestrales a 165 €?", "5 gastos que olvidan",
        "2026-10-19", "150.00", "true", "no", "null", "#hashtag", "- guion", "@lucuma.estudio", "a: b", "texto #con almohadilla",
        "79f8cc54-0e5c-4f4e-8991-da6ff86d9f6d", "0x1F", "1e3", "10:30", " espacio", "comillas \"dobles\"", "barra \\ invertida",
        "[[comercial|Comercial]]", "línea\nnueva", "B00000000 (ficticio)", "{{numero}}", "~", "4821",
    ])
    func propiedadesIdaYVuelta(_ texto: String) {
        var fm = FrontmatterNuevo(tipo: "contact", id: "x")
        fm.poner("valor", .texto(texto))
        fm.poner("lista", .lista([.texto(texto), .texto("otro")]))
        let leido = FrontmatterReader.read(fm.yaml)
        #expect(leido.isValid)
        #expect(leido.value("valor") == .text(texto), "\(fm.yaml)")
        #expect(leido.value("lista") == .list([texto, "otro"]), "\(fm.yaml)")
    }

    @Test("Un CSV escrito se vuelve a leer igual")
    func csv() {
        let filas = [["F-1", "Ferretería, S.L.", "Web \"básica\"", "línea\nnueva", " x", "a\r\nb"]]
        let texto = EscrituraCSV.texto(cabecera: ["id", "a", "b", "c", "d", "e"], filas: filas)
        let t = CSVTable.parse(texto)
        #expect(t.header == ["id", "a", "b", "c", "d", "e"])
        #expect(t.rows == filas)
    }
}

@Suite("Conversor G2 · seguridad y determinismo")
struct SeguridadConversor {
    static var minimo: URL { RutasConformidad.casos.appendingPathComponent("convertir-g2-minimo/entrada", isDirectory: true) }

    @Test("Dos planes del mismo origen son idénticos byte a byte")
    func determinista() throws {
        let a = try ConversorG2.planificar(origen: Self.minimo, opciones: .init(clase: .demo, hoy: "2026-10-19"))
        let b = try ConversorG2.planificar(origen: Self.minimo, opciones: .init(clase: .demo, hoy: "2026-10-19"))
        #expect(a.ficheros.map(\.ruta) == b.ficheros.map(\.ruta))
        for (x, y) in zip(a.ficheros, b.ficheros) { #expect(x.contenido == y.contenido) }
        #expect(a.informe == b.informe)
    }

    @Test("Escribe la carpeta entera, sin restos, y no toca el origen")
    func escribe() async throws {
        let base = RutasConformidad.temporal("convertir")
        defer { try? FileManager.default.removeItem(at: base) }
        let antes = try Arbol.leer(Self.minimo)
        let destino = base.appendingPathComponent("Ribera mínima", isDirectory: true)
        let informe = try await ConversorG2.convertir(origen: Self.minimo, destino: destino, opciones: .init(clase: .demo, hoy: "2026-10-19"))
        #expect(try Arbol.leer(Self.minimo) == antes)
        #expect(informe.hashArbol?.count == 64)
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path) == ["Ribera mínima"])
        let escrito = try Arbol.leer(destino)
        #expect(ValidadorV2.validar(escrito).isEmpty)
        #expect(escrito["Buzón/Informe de importación 2026-10-19.md"] != nil)
        #expect(escrito["Archivo/Importación 2026-10-19/LEEME.md"] == antes["LEEME.md"])
    }

    @Test("Nunca escribe encima ni dentro del origen, ni crea la carpeta real")
    func rechazos() async throws {
        let base = RutasConformidad.temporal("rechazos")
        defer { try? FileManager.default.removeItem(at: base) }
        let existente = base.appendingPathComponent("ya-existe", isDirectory: true)
        try FileManager.default.createDirectory(at: existente, withIntermediateDirectories: true)
        await #expect(throws: ErrorConversionG2.destinoExiste(existente.path)) {
            try await ConversorG2.convertir(origen: Self.minimo, destino: existente)
        }
        await #expect(throws: ErrorConversionG2.destinoDentroDelOrigen) {
            try await ConversorG2.convertir(origen: Self.minimo, destino: Self.minimo.appendingPathComponent("v2"))
        }
        await #expect(throws: ErrorConversionG2.claseNoPermitida) {
            try await ConversorG2.convertir(origen: Self.minimo, destino: base.appendingPathComponent("x"), opciones: .init(clase: .real))
        }
        let icloud = URL(fileURLWithPath: AppLocations.iCloudDrivePath).appendingPathComponent("No existe G2")
        await #expect(throws: ErrorConversionG2.enICloud(icloud.path)) {
            try await ConversorG2.convertir(origen: icloud, destino: base.appendingPathComponent("y"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: base.path) == ["ya-existe"])
    }

    @Test("Tampoco dentro del origen si una de las rutas se escribe con o sin «/private»")
    func rechazosConPrivate() async throws {
        // La carpeta temporal se escribe `/var/folders/…`, pero su ruta real es `/private/var/folders/…`.
        let base = RutasConformidad.temporal("private")
        defer { try? FileManager.default.removeItem(at: base) }
        let origen = base.appendingPathComponent("entrada", isDirectory: true)
        try FileManager.default.copyItem(at: Self.minimo, to: origen)
        let real = try #require(realpath(origen.path, nil).map { p in defer { free(p) }; return String(cString: p) })
        let larga = URL(fileURLWithPath: real, isDirectory: true)
        let corta = URL(fileURLWithPath: real.hasPrefix("/private/") ? String(real.dropFirst("/private".count)) : real,
                        isDirectory: true)
        #expect(larga.path != corta.path)
        let antes = try Arbol.leer(origen)
        for o in [larga, corta] {
            for d in [larga, corta] {
                await #expect(throws: ErrorConversionG2.destinoDentroDelOrigen) {
                    try await ConversorG2.convertir(origen: o, destino: d.appendingPathComponent("v2"),
                                                    opciones: .init(clase: .demo, hoy: "2026-10-19"))
                }
            }
        }
        #expect(try Arbol.leer(origen) == antes)
    }

    @Test("Una ficha por tarea: las tareas de G2 conservan su número y sus relaciones")
    func tareasDeG2() throws {
        let base = RutasConformidad.temporal("tareas")
        defer { try? FileManager.default.removeItem(at: base) }
        let origen = base.appendingPathComponent("g2", isDirectory: true)
        try FileManager.default.copyItem(at: Self.minimo, to: origen)
        let tarea = """
        ---
        assignee: agent:ventas
        created_at: "2026-10-18T10:00:00+02:00"
        due_date: "2026-10-30"
        id: 7a1d0c3e-1111-4c2b-9a51-0f4d7c2e9b10
        number: T-0042
        opportunity_id: 79f8cc54-0e5c-4f4e-8991-da6ff86d9f6d
        priority: high
        sprint: S43
        status: in_progress
        title: Preparar la propuesta de Trimestrales
        tls_schema: 1
        tls_type: task
        ---

        Con la oferta vigente.
        """
        let carpeta = origen.appendingPathComponent("Ventas/Tareas", isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        try Data(tarea.utf8).write(to: carpeta.appendingPathComponent("preparar-la-propuesta--7a1d0c3e.md"))
        let plan = try ConversorG2.planificar(origen: origen, opciones: .init(clase: .demo, hoy: "2026-10-19"))
        let ruta = VaultPath("2 · Ventas/Tareas/t-0042-preparar-la-propuesta-de-trimestrales.md")
        let texto = try #require(try plan.datos(ruta).map { String(decoding: $0, as: UTF8.self) })
        let fm = NoteDocument(text: texto).frontmatter
        #expect(fm.text("numero") == "T-0042")
        #expect(fm.text("estado") == "En curso")
        #expect(fm.text("prioridad") == "Alta")
        #expect(fm.text("responsable") == "agente:comercial")
        #expect(fm.text("vence") == "2026-10-30")
        #expect(fm.text("oportunidad") == "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]")
        #expect(texto.contains("## Descripción\nCon la oferta vigente."))
        // La decisión abierta del caso toma el número siguiente; el contador queda en el mayor.
        #expect(plan.ficheros.contains { $0.ruta.raw.hasPrefix("1 · Dirección/Tareas/t-0043-") })
        #expect(try plan.datos(VaultPath(".tls/secuencias.json")) == Data("{\"tarea\":43}\n".utf8))
        #expect(plan.informe.camposNoConvertidos.contains { $0.campo == "task.sprint" })
        #expect(plan.informe.tareas == 2)
    }

    @Test("Informe: avisa de las referencias que faltan y no las escribe")
    func referenciasRotas() throws {
        let plan = try ConversorG2.planificar(origen: Self.minimo, opciones: .init(clase: .demo, hoy: "2026-10-19"))
        let avisos = plan.informe.avisos.map(\.texto)
        #expect(avisos.contains { $0.hasPrefix("Referencias a fichas que no están en la exportación") })
        let lola = try #require(try plan.datos(VaultPath("2 · Ventas/Contactos/lola-plaza.md")).map { String(decoding: $0, as: UTF8.self) })
        #expect(!lola.contains("empresa:"))
        #expect(plan.informe.tareas == 1)
        #expect(plan.informe.archivados == ["LEEME.md"])
    }
}
