import CryptoKit
import Foundation
import Testing
import TLSCore
@testable import TLSImport

/// Importar de Multica con un programa **falso** que devuelve JSON inventado (nunca la cuenta real ni su CLI).
@Suite("Importar de Multica", .serialized)
struct MulticaTests {
    // MARK: Apoyo

    static var ribera: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    /// Carpeta temporal con el programa falso `multica`, sus páginas de JSON y el registro de órdenes.
    struct Falso {
        let base: URL
        var bin: URL { base.appendingPathComponent("bin", isDirectory: true) }
        var ejecutable: URL { bin.appendingPathComponent("multica") }
        var registro: URL { base.appendingPathComponent("ordenes.txt") }
        func limpiar() { try? FileManager.default.removeItem(at: base) }

        /// Órdenes recibidas, una por línea.
        func ordenes() -> [String] {
            ((try? String(contentsOf: registro, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }

        init(espaciosEnJSON: Bool = true, perfiles: Bool = true) throws {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-multica-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: base.appendingPathComponent("bin"), withIntermediateDirectories: true)
            try Data(Self.pagina1.utf8).write(to: base.appendingPathComponent("pagina1.json"))
            try Data(Self.pagina2.utf8).write(to: base.appendingPathComponent("pagina2.json"))
            let espaciosJSON = espaciosEnJSON
                ? #"echo '{"workspaces":[{"id":"0f6c1a2e-1111-4222-8333-944455556666","name":"Empresa de prueba"}]}'"#
                : #"echo "unknown flag: --output" >&2; exit 2"#
            let perfilesOrden = perfiles ? #"echo '["default","pruebas"]'"# : #"echo "unknown command" >&2; exit 1"#
            let guion = """
            #!/bin/sh
            DIR="\(base.path)"
            echo "$*" >> "$DIR/ordenes.txt"
            case "$*" in
              "profile list --output json") \(perfilesOrden) ;;
              *"workspace list --output json") \(espaciosJSON) ;;
              *"workspace list") printf 'ID                                    NOMBRE\\n0f6c1a2e-1111-4222-8333-944455556666  Empresa de prueba\\n' ;;
              *"issue list"*"--offset 0 "*) cat "$DIR/pagina1.json" ;;
              *"issue list"*"--offset 3 "*) cat "$DIR/pagina2.json" ;;
              *) echo "orden desconocida: $*" >&2; exit 3 ;;
            esac
            """
            try Data(guion.utf8).write(to: ejecutable)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ejecutable.path)
        }

        static let pagina1 = """
        {"issues":[
          {"identifier":"MANU-1","title":"Preparar propuesta para un cliente nuevo","description":"## Contexto\\nUn cliente pide presupuesto.\\n<!-- tls:evento {\\"tipo\\":\\"x\\"} -->","status":"Todo","status_category":"todo","priority":"high","due_date":"2026-10-30","created_at":"2026-10-01T09:00:00Z"},
          {"identifier":"MANU-2","title":"Cita médica de revisión","description":null,"status":"Todo","status_category":"todo","priority":"none","due_date":null,"created_at":"2026-10-02T09:00:00Z"},
          {"identifier":"MANU-3","title":"Publicar artículo en LinkedIn","description":"Sobre deducciones.","status":"In Progress","status_category":"in_progress","priority":"medium","due_date":"2026-11-02T00:00:00Z","created_at":"2026-10-03T09:00:00Z"}
        ],"has_more":true}
        """

        static let pagina2 = """
        {"issues":[
          {"identifier":"MANU-4","title":"Cerrar el trimestre con la gestoría","description":"Facturas y modelo 303.","status":"Backlog","status_category":"backlog","priority":"low","due_date":"2026-10-20","created_at":"2026-10-04T09:00:00Z"},
          {"identifier":"MANU-5","title":"Algo ya hecho","status":"Done","status_category":"done","priority":"low"},
          {"identifier":"MANU-6","title":"Revisar los objetivos del trimestre","status":"In Review","status_category":"in_review","priority":"urgent"},
          {"identifier":"MANU-7","title":"Algo cancelado","status":"Canceled","status_category":"cancelled"},
          {"identifier":"MANU-8","title":"Rellenar el parte IT de ejemplo","status":"Blocked","status_category":"blocked","priority":"high"}
        ],"has_more":false}
        """
    }

    /// Copia de Ribera con su escritor; opcionalmente con una carpeta privada neutra («Expediente privado»).
    struct Copia {
        let base: URL
        let root: URL
        let entry: VaultEntry
        var estado: URL { base.appendingPathComponent("estado") }

        init(conPrivada: Bool = false) throws {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-multica-copia-\(UUID().uuidString)", isDirectory: true)
            root = base.appendingPathComponent("Ribera", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: MulticaTests.ribera, to: root)
            if conPrivada {
                let config = root.appendingPathComponent(".tls/config.yaml")
                let texto = try String(contentsOf: config, encoding: .utf8)
                    .replacingOccurrences(of: "privado: []", with: "privado: [\"Expediente privado\"]")
                try Data(texto.utf8).write(to: config)
                let carpeta = root.appendingPathComponent("Expediente privado", isDirectory: true)
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                try Data("# Nota\n".utf8).write(to: carpeta.appendingPathComponent("nota.md"))
            }
            entry = VaultEntry(nombre: "Ribera", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida)
        }

        func bus() async throws -> CommandBus {
            let options = VaultWriter.Options(stateDirectory: estado, appSupport: base.appendingPathComponent("asup"),
                                              app: "The Last System pruebas")
            return CommandBus(writer: try await VaultWriter.open(entry: entry, root: root, options: options))
        }

        func foto() -> VaultSnapshot { VaultSnapshot.read(root: root) }
        func texto(_ p: VaultPath) -> String { (try? String(contentsOf: p.url(in: root), encoding: .utf8)) ?? "" }
        func limpiar() { try? FileManager.default.removeItem(at: base) }

        /// Rutas y SHA-256 de todo el árbol (también lo oculto).
        func huella() -> [String: String] {
            var out: [String: String] = [:]
            let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
            while let u = e?.nextObject() as? URL {
                guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                      let d = try? Data(contentsOf: u) else { continue }
                out[String(u.resolvingSymlinksInPath().path.dropFirst(root.resolvingSymlinksInPath().path.count))] = SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
            }
            return out
        }
    }

    func tareasDePrueba() async throws -> [TareaMultica] {
        let falso = try Falso()
        defer { falso.limpiar() }
        return try await LectorMultica(ejecutor: ProcesoMultica(cli: MulticaCLI(ejecutable: falso.ejecutable)))
            .tareasAbiertas(perfil: "default", espacio: "0f6c1a2e-1111-4222-8333-944455556666")
    }

    // MARK: Programa y lectura

    @Test("Encuentra el programa en el PATH o dentro de Multica.app, sin lanzarlo")
    func localizar() throws {
        let falso = try Falso()
        defer { falso.limpiar() }
        let enPath = MulticaCLI.localizar(path: "/no/existe:\(falso.bin.path)", extra: [], enLaApp: [])
        #expect(enPath?.ejecutable.standardizedFileURL == falso.ejecutable.standardizedFileURL)
        let enApp = MulticaCLI.localizar(path: "/no/existe", extra: [], enLaApp: [falso.ejecutable.path])
        #expect(enApp?.ejecutable.path == falso.ejecutable.path)
        #expect(MulticaCLI.localizar(path: "/no/existe", extra: [], enLaApp: ["/no/existe/multica"]) == nil)
        #expect(falso.ordenes().isEmpty, "localizar no lanza nada")
        // Un fichero sin permiso de ejecución no cuenta.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: falso.ejecutable.path)
        #expect(MulticaCLI.localizar(path: falso.bin.path, extra: [], enLaApp: []) == nil)
    }

    @Test("Solo órdenes de listar: perfiles, espacios y tareas con sus campos")
    func ordenesDeSoloLectura() {
        #expect(OrdenMultica.perfiles.argumentos == ["profile", "list", "--output", "json"])
        #expect(OrdenMultica.espacios(perfil: "p", json: false).argumentos == ["--profile", "p", "workspace", "list"])
        let t = OrdenMultica.tareas(perfil: "p", espacio: "w", desde: 100, limite: 100).argumentos
        #expect(t == ["--profile", "p", "--workspace-id", "w", "issue", "list", "--output", "json", "--limit", "100",
                      "--offset", "100", "--fields", "identifier,title,description,status,status_category,priority,due_date,created_at"])
        for o in [OrdenMultica.perfiles, .espacios(perfil: "p", json: true), .tareas(perfil: "p", espacio: "w", desde: 0, limite: 1)] {
            let a = Set(o.argumentos)
            #expect(a.contains("list"))
            #expect(a.isDisjoint(with: ["create", "update", "delete", "close", "assign", "comment", "move", "edit", "set"]))
        }
    }

    @Test("Perfiles, espacios (JSON o texto) y tareas abiertas página a página")
    func lectura() async throws {
        let falso = try Falso()
        defer { falso.limpiar() }
        let lector = LectorMultica(ejecutor: ProcesoMultica(cli: MulticaCLI(ejecutable: falso.ejecutable)))
        #expect(await lector.perfiles().map(\.nombre) == ["default", "pruebas"])
        let espacios = try await lector.espacios(perfil: "default")
        #expect(espacios == [EspacioMultica(id: "0f6c1a2e-1111-4222-8333-944455556666", nombre: "Empresa de prueba")])
        let tareas = try await lector.tareasAbiertas(perfil: "default", espacio: espacios[0].id)
        // MANU-5 (done) y MANU-7 (cancelled) no entran.
        #expect(tareas.map(\.identificador) == ["MANU-1", "MANU-2", "MANU-3", "MANU-4", "MANU-6", "MANU-8"])
        let ordenes = falso.ordenes()
        #expect(ordenes.filter { $0.contains("issue list") }.count == 2)
        #expect(ordenes.contains { $0.contains("--offset 3 ") })
        for o in ordenes { #expect(o.contains(" list"), "solo órdenes de listar: \(o)") }

        let m1 = try #require(tareas.first)
        #expect(m1.estadoFicha == .porHacer)
        #expect(m1.prioridadFicha == "Alta")
        #expect(m1.vence == LocalDate(year: 2026, month: 10, day: 30))
        #expect(tareas[2].vence == LocalDate(year: 2026, month: 11, day: 2))
        #expect(tareas[3].estadoFicha == .sinProgramar)
        #expect(tareas[4].estadoFicha == .enRevision && tareas[4].prioridadFicha == "Urgente")
        #expect(tareas[5].estadoFicha == .bloqueada)
        #expect(tareas[2].estadoFicha == .enCurso && tareas[2].prioridadFicha == "Media")
    }

    @Test("Sin JSON para los espacios, lee la tabla de texto; sin lista de perfiles, vacío")
    func espaciosEnTexto() async throws {
        let falso = try Falso(espaciosEnJSON: false, perfiles: false)
        defer { falso.limpiar() }
        let lector = LectorMultica(ejecutor: ProcesoMultica(cli: MulticaCLI(ejecutable: falso.ejecutable)))
        #expect(await lector.perfiles().isEmpty)
        let espacios = try await lector.espacios(perfil: "default")
        #expect(espacios.map(\.id) == ["0f6c1a2e-1111-4222-8333-944455556666"])
        #expect(espacios.first?.nombre == "Empresa de prueba")
        await #expect(throws: ErrorMultica.perfilVacio) { try await lector.espacios(perfil: "  ") }
    }

    @Test("Un error del programa se dice en llano y lleva el detalle aparte")
    func errorDelPrograma() async throws {
        let falso = try Falso()
        defer { falso.limpiar() }
        let p = ProcesoMultica(cli: MulticaCLI(ejecutable: falso.ejecutable))
        do {
            _ = try await p.ejecutar(.tareas(perfil: "x", espacio: "y", desde: 7, limite: 1))
            Issue.record("Debía fallar")
        } catch let e as ErrorMultica {
            guard case .fallo(let codigo, let detalle) = e else { Issue.record("Error inesperado: \(e)"); return }
            #expect(codigo == 3)
            #expect(detalle.contains("orden desconocida"))
            #expect(e.errorDescription?.contains("Multica") == true)
        }
        // Un programa que no contesta se para al pasar el tiempo máximo.
        let dormido = falso.base.appendingPathComponent("dormido")
        try Data("#!/bin/sh\nexec sleep 5\n".utf8).write(to: dormido)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dormido.path)
        let lento = ProcesoMultica(cli: MulticaCLI(ejecutable: dormido), tiempoMaximo: .milliseconds(300))
        let inicio = Date()
        await #expect(throws: ErrorMultica.sinRespuesta) { try await lento.ejecutar(.perfiles) }
        #expect(Date().timeIntervalSince(inicio) < 4)
    }

    @Test("Lee formas distintas de JSON: lista suelta, `data` y estado anidado")
    func formasDeJSON() throws {
        let suelta = Data(#"[{"identifier":"A-1","title":"Uno","status":{"name":"Doing","category":"in_progress"},"priority":2}]"#.utf8)
        let r = try LecturaMultica.tareas(suelta)
        #expect(r.hayMas == nil)
        #expect(r.tareas.first?.categoria == .enCurso)
        #expect(r.tareas.first?.prioridadFicha == "Alta")
        let data = Data(#"{"data":[{"key":"B-2","name":"Dos","status_category":"todo"}],"meta":{"has_more":false}}"#.utf8)
        let r2 = try LecturaMultica.tareas(data)
        #expect(r2.tareas.map(\.identificador) == ["B-2"])
        #expect(r2.hayMas == false)
        #expect(throws: ErrorMultica.respuestaIlegible) { try LecturaMultica.tareas(Data("no es json".utf8)) }
    }

    // MARK: Vista previa

    @Test("Personal o de salud: desmarcada y con su nota; el resto, marcada y con área sugerida")
    func vistaPrevia() async throws {
        let tareas = try await tareasDePrueba()
        let copia = try Copia()
        defer { copia.limpiar() }
        let previa = ImportadorMultica(snapshot: copia.foto()).previa(tareas)
        let porId = Dictionary(uniqueKeysWithValues: previa.candidatas.map { ($0.id, $0) })
        #expect(porId["MANU-2"]?.marcada == false)
        #expect(porId["MANU-2"]?.personal == "medica")
        #expect(porId["MANU-2"]?.nota == "Parece personal: no se importa salvo que la marques; si la marcas, va a la carpeta privada que elijas")
        #expect(porId["MANU-8"]?.marcada == false)
        #expect(porId["MANU-8"]?.personal == "IT")
        #expect(porId["MANU-1"]?.marcada == true && porId["MANU-1"]?.areaSugerida == .ventas)
        #expect(porId["MANU-3"]?.areaSugerida == .marca)
        #expect(porId["MANU-4"]?.areaSugerida == .finanzas)
        #expect(porId["MANU-6"]?.areaSugerida == .direccion)
        #expect(previa.fechaCorte == LocalDate(year: 2026, month: 10, day: 19), "reloj de la carpeta de ejemplo")
        #expect(previa.resumen == "6 tareas abiertas · 4 para importar · 2 parecen personales")
    }

    @Test("Palabras personales: sin tildes ni mayúsculas, salvo «IT»; «prioridad baja» no cuenta")
    func clasificadorPersonal() {
        #expect(ClasificadorPersonal.motivo("Comprar AirPods nuevos") == "airpods")
        #expect(ClasificadorPersonal.motivo("Llamar a FREMAP") == "fremap")
        #expect(ClasificadorPersonal.motivo("Recoger la medicación") == "medicacion")
        #expect(ClasificadorPersonal.motivo("Tarea", "con prioridad baja") == nil)
        #expect(ClasificadorPersonal.motivo("Revisar el sistema de facturas") == nil)
        #expect(ClasificadorPersonal.motivo("Hablar de it en la reunión") == nil)
        #expect(ClasificadorPersonal.motivo("Parte de IT") == "IT")
        #expect(ClasificadorPersonal.motivo("Pedir cita médica") == "medica")
    }

    @Test("El texto de fuera es un dato: los encabezados bajan y los comentarios no pasan")
    func descripcionSegura() {
        let d = ImportadorMultica.descripcion("# Uno\n## Dos\ntexto\n#### Cuatro\n#etiqueta\n<!-- tls:evento {} -->")
        #expect(d == "#### Uno\n#### Dos\ntexto\n#### Cuatro\n#etiqueta\n&lt;!-- tls:evento {} --&gt;")
        #expect(ImportadorMultica.descripcion("   \n ") == nil)
    }

    // MARK: Aplicar

    @Test("Nada se escribe antes de aplicar; aplicar crea las fichas; una segunda vez no repite; Deshacer deja el árbol igual")
    func aplicarYNoRepetir() async throws {
        let tareas = try await tareasDePrueba()
        let copia = try Copia()
        defer { copia.limpiar() }
        let bus = try await copia.bus()
        let antes = copia.huella()

        let importador = ImportadorMultica(snapshot: copia.foto())
        let previa = importador.previa(tareas)
        let plan = try importador.plan(previa, autor: .persona("Manu"))
        #expect(copia.huella() == antes, "preparar no escribe nada")
        #expect(plan.fichas.count == 4)
        #expect(plan.resumen == "Crear 4 fichas de tarea. No se borra ni se cambia nada más.")
        #expect(plan.plan.autor == .persona("Manu"))

        let r = try await ImportadorMultica.aplicar(plan, con: bus)
        #expect(r.hecho)
        // Numeración seguida desde el contador (Ribera tiene T-0001 y T-0002).
        #expect(plan.fichas.map(\.ruta.name).map { String($0.prefix(6)) } == ["t-0003", "t-0004", "t-0005", "t-0006"])
        #expect(copia.texto(VaultPath(".tls/secuencias.json")).contains("\"tarea\":6") || copia.texto(VaultPath(".tls/secuencias.json")).contains("\"tarea\": 6"))

        let m1 = try #require(plan.fichas.first { $0.identificador == "MANU-1" })
        #expect(m1.ruta.raw.hasPrefix("2 · Ventas/Tareas/"))
        let t1 = copia.texto(m1.ruta)
        #expect(t1.contains("numero: T-0003"))
        #expect(t1.contains("estado: Por hacer"))
        #expect(t1.contains("prioridad: Alta"))
        #expect(t1.contains("vence: 2026-10-30"))
        #expect(t1.contains("origen: importacion"))
        #expect(t1.contains("fecha_corte: 2026-10-19"))
        #expect(t1.contains("externo: ext:multica:MANU-1") || t1.contains("externo: \"ext:multica:MANU-1\""))
        #expect(t1.contains("## Descripción\n#### Contexto\nUn cliente pide presupuesto."))
        #expect(!t1.contains("<!-- tls:evento {\"tipo\":\"x\"}"), "el comentario de fuera no pasa como marca de la app")
        #expect(t1.contains("Importada de Multica (MANU-1)."))
        #expect(t1.contains("\"externo\":\"ext:multica:MANU-1\""))
        let m6 = try #require(plan.fichas.first { $0.identificador == "MANU-6" })
        let t6 = copia.texto(m6.ruta)
        #expect(t6.contains("estado: En revisión") && t6.contains("prioridad: Urgente"))
        #expect(!t6.contains("vence:"))

        // La tienda las lee como tareas normales.
        let store = TaskStore(snapshot: copia.foto())
        let leida = try #require(store.tarea(m1.ruta))
        #expect(leida.estado == .porHacer && leida.origen == "importacion" && leida.area == .ventas)

        // Segunda importación: las mismas salen como ya importadas y no hay nada que hacer.
        let otra = ImportadorMultica(snapshot: copia.foto()).previa(tareas)
        #expect(otra.candidatas.filter { $0.yaImportada != nil }.map(\.id).sorted() == ["MANU-1", "MANU-3", "MANU-4", "MANU-6"])
        #expect(otra.marcadas.isEmpty)
        #expect(otra.candidatas.first { $0.id == "MANU-1" }?.nota?.hasPrefix("Ya la importaste") == true)
        #expect(throws: ErrorImportacionMultica.nadaMarcado) { try ImportadorMultica(snapshot: copia.foto()).plan(otra, autor: .persona("Manu")) }

        // Deshacer deja la carpeta como estaba (mismas rutas y mismos SHA-256); lo creado no se borra: se retira al
        // Archivo, como todo lo que se deshace. Solo cambia además la marca del escritor (`.tls/escritor.json`).
        _ = try await bus.deshacer(autor: .persona("Manu"))
        let despues = copia.huella()
        let distintas = Set(antes.keys).union(despues.keys).filter { antes[$0] != despues[$0] }.sorted()
            .filter { !$0.hasPrefix("/Archivo/") && $0 != "/.tls/escritor.json" }
        #expect(distintas.isEmpty, "Cambiaron: \(distintas)")
        let retiradas = despues.keys.filter { $0.hasPrefix("/Archivo/") && $0.contains("/Tareas/t-") }
        #expect(retiradas.count == 4)
    }

    @Test("Una personal marcada necesita carpeta privada y va a su Tareas; sin privada, no se prepara")
    func personalesAPrivada() async throws {
        let tareas = try await tareasDePrueba()
        let copia = try Copia(conPrivada: true)
        defer { copia.limpiar() }
        let importador = ImportadorMultica(snapshot: copia.foto())
        var previa = importador.previa(tareas)
        previa.marcar("MANU-2", true)
        #expect(throws: ErrorImportacionMultica.faltaCarpetaPrivada) { try importador.plan(previa, autor: .persona("Manu")) }
        #expect(throws: ErrorImportacionMultica.carpetaNoPrivada("1 · Dirección")) {
            try importador.plan(previa, carpetaPrivada: VaultPath("1 · Dirección"), autor: .persona("Manu"))
        }
        let plan = try importador.plan(previa, carpetaPrivada: VaultPath("Expediente privado"), autor: .persona("Manu"))
        let m2 = try #require(plan.fichas.first { $0.identificador == "MANU-2" })
        #expect(m2.privada)
        #expect(m2.ruta.raw.hasPrefix("Expediente privado/Tareas/t-"))
        #expect(plan.resumen == "Crear 5 fichas de tarea (1 en tu carpeta privada). No se borra ni se cambia nada más.")
        let bus = try await copia.bus()
        #expect(try await ImportadorMultica.aplicar(plan, con: bus).hecho)
        #expect(copia.foto().layout.isPrivate(m2.ruta))
        // Una ya importada no se puede volver a marcar.
        var otra = ImportadorMultica(snapshot: copia.foto()).previa(tareas)
        otra.marcar("MANU-2", true)
        #expect(otra.marcadas.isEmpty)
    }

    @Test("A través del dominio, en modo importación: no salta ninguna regla")
    func porElDominio() async throws {
        let tareas = try await tareasDePrueba()
        let copia = try Copia()
        defer { copia.limpiar() }
        let motor = try MotorDeDominio(bus: try await copia.bus())
        let importador = ImportadorMultica(snapshot: copia.foto())
        let plan = try importador.plan(importador.previa(tareas), autor: .persona("Manu"))
        let r = try await ImportadorMultica.aplicar(plan, con: motor)
        #expect(r.hecho)
        #expect(try motor.estado.pendientes().isEmpty)
        #expect(try motor.estado.eventos().isEmpty, "lo importado (fecha_corte) no da eventos")
    }
}
