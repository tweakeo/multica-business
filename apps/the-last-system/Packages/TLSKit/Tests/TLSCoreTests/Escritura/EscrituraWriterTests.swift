import Foundation
import Testing
@testable import TLSCore

/// Protocolo de escritura (PLAN §4.8): planes atómicos, diario, copia previa, deshacer,
/// reglas por autor, guardarraíles, escritor único y política de clases.
@Suite(.serialized) struct EscrituraWriterTests {
    static let manu = Autor.persona("Manu")
    static let lucia = "2 · Ventas/Contactos/Lucía Prueba.md"
    static let rumbo = "1 · Dirección/Rumbo.md"

    // MARK: Operaciones

    @Test func cambiarPropiedadesSoloTocaEsasLineas() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let antes = try #require(e.texto(Self.lucia))
        let r = try await bus.ejecutar(.cambiarPropiedades(VaultPath(Self.lucia),
                                                           poner: [Property(key: "importe", value: .number("1500")),
                                                                   Property(key: "tls_type", value: .text("contact"))],
                                                           quitar: ["activo"]), autor: Self.manu)
        #expect(r.hecho)
        #expect(r.cambiadas == [VaultPath(Self.lucia)])
        let despues = try #require(e.texto(Self.lucia))
        #expect(despues == antes.replacingOccurrences(of: "---\ntipo: persona", with: "---\ntls_type: contact\ntipo: persona")
                                .replacingOccurrences(of: "activo: true\n", with: "")
                                .replacingOccurrences(of: "importe: 1200", with: "importe: 1500"))
        // Diario, copia previa y huella de la app.
        let diario = try String(contentsOf: e.state.appendingPathComponent("diario.jsonl"), encoding: .utf8)
        #expect(diario.contains("\"estado\":\"pendiente\"") && diario.contains("\"estado\":\"hecho\""))
        #expect(diario.contains("\"base_hashes\"") && diario.contains("\"hash_resultante\""))
        let copias = e.state.appendingPathComponent("copias")
        let dia = try #require(try FileManager.default.contentsOfDirectory(atPath: copias.path).first)
        let copia = copias.appendingPathComponent("\(dia)/\(r.planID.uuidString.lowercased())/\(Self.lucia)")
        #expect(try String(contentsOf: copia, encoding: .utf8) == antes)
        #expect(await bus.writer.appHash(VaultPath(Self.lucia)) == ContentHash.of(Data(despues.utf8)))
        // Ninguna línea de staging se queda.
        #expect((try? FileManager.default.contentsOfDirectory(atPath: e.state.appendingPathComponent("diario").path))?.isEmpty ?? true)
    }

    @Test func crearNuncaPisa() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let antes = e.datos(Self.rumbo)
        let r = try await bus.ejecutar(.crear(VaultPath(Self.rumbo), texto: "# Otro rumbo\n"), autor: Self.manu)
        #expect(r.creadas == [VaultPath("1 · Dirección/Rumbo (2).md")])
        #expect(e.datos(Self.rumbo) == antes)
        #expect(e.texto("1 · Dirección/Rumbo (2).md") == "# Otro rumbo\n")
        let r3 = try await bus.ejecutar(.crear(VaultPath(Self.rumbo), texto: "# Tercero\n"), autor: Self.manu)
        #expect(r3.creadas == [VaultPath("1 · Dirección/Rumbo (3).md")])
        // En una carpeta nueva.
        let r4 = try await bus.ejecutar(.crear(VaultPath("2 · Ventas/Tareas/t-0002-llamar.md"), texto: "---\ntls_type: task\n---\n"), autor: .sistema)
        #expect(r4.creadas == [VaultPath("2 · Ventas/Tareas/t-0002-llamar.md")])
    }

    @Test func moverSinSobrescribirYRetirarAlArchivo() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let antes = e.huella()
        await esperaErrorAsync(.destinoOcupado("2 · Ventas/Contactos/José Núñez.md")) {
            try await bus.ejecutar(.mover(VaultPath(Self.lucia), a: VaultPath("2 · Ventas/Contactos/José Núñez.md")), autor: Self.manu)
        }
        #expect(e.huella() == antes)
        let datos = e.datos(Self.lucia)
        let r = try await bus.ejecutar(.retirar(VaultPath(Self.lucia)), autor: Self.manu)
        #expect(r.movidas == [Movimiento(de: VaultPath(Self.lucia), a: VaultPath("Archivo/" + Self.lucia))])
        #expect(!e.existe(Self.lucia))
        #expect(e.datos("Archivo/" + Self.lucia) == datos)
        // Retirar otra con el mismo nombre no pisa la primera.
        e.escribir(Self.lucia, "# Otra Lucía\n")
        let r2 = try await bus.ejecutar(.retirar(VaultPath(Self.lucia)), autor: Self.manu)
        #expect(r2.movidas.first?.a == VaultPath("Archivo/2 · Ventas/Contactos/Lucía Prueba (2).md"))
        #expect(e.datos("Archivo/" + Self.lucia) == datos)
        await esperaErrorAsync(.yaRetirada("Archivo/" + Self.lucia)) {
            try await bus.ejecutar(.retirar(VaultPath("Archivo/" + Self.lucia)), autor: Self.manu)
        }
        // Mover una carpeta entera.
        let rc = try await bus.ejecutar(.mover(VaultPath("2 · Ventas/Empresas"), a: VaultPath("2 · Ventas/Clientes")), autor: Self.manu)
        #expect(rc.cambiadas == [VaultPath("2 · Ventas/Clientes"), VaultPath("2 · Ventas/Empresas")])
        #expect(e.existe("2 · Ventas/Clientes/Ferretería Ejemplo.md"))
    }

    @Test func renombrarSoloMayusculas() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let datos = e.datos(Self.rumbo)
        let r = try await bus.ejecutar(.mover(VaultPath(Self.rumbo), a: VaultPath("1 · Dirección/RUMBO.md")), autor: Self.manu)
        #expect(r.hecho)
        let nombres = try FileManager.default.contentsOfDirectory(atPath: e.url("1 · Dirección").path)
        #expect(nombres.contains("RUMBO.md") && !nombres.contains("Rumbo.md"))
        #expect(!nombres.contains { $0.hasPrefix(".tls-") })
        #expect(e.datos("1 · Dirección/RUMBO.md") == datos)
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.url("1 · Dirección").path).contains("Rumbo.md"))
    }

    /// Un plan de varios ficheros es todo o nada: si un paso falla, los anteriores se deshacen.
    @Test func planAtomicoSeRevierte() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let antes = e.huellaSinEscritor()
        // Falla al calcular (un fichero no existe): no se escribe nada.
        await esperaErrorAsync(.noExiste("no-existe.md")) {
            try await bus.ejecutar(WritePlan(autor: Self.manu, descripcion: "x", ops: [
                .appendLine(VaultPath(Self.rumbo), line: "Línea"), .appendLine(VaultPath("no-existe.md"), line: "x")]))
        }
        #expect(e.huellaSinEscritor() == antes)
        // Falla a mitad: alguien cambia el segundo fichero (Rumbo, por orden) justo antes de escribirlo.
        // El primero (Decisiones), ya escrito, vuelve a como estaba.
        let otro = e.url(Self.rumbo)
        await bus.writer.setBeforeStep { n in
            if n == 1 { try? Data("# Cambiado fuera\n".utf8).write(to: otro) }
        }
        await esperaErrorAsync(.cambioExterno(Self.rumbo)) {
            try await bus.ejecutar(WritePlan(autor: Self.manu, descripcion: "x", ops: [
                .appendLine(VaultPath(Self.rumbo), line: "Línea"),
                .appendLine(VaultPath("1 · Dirección/Decisiones.md"), line: "- 2026-10-22 · Otra")]))
        }
        await bus.writer.setBeforeStep(nil)
        var esperado = antes
        esperado[Self.rumbo] = ContentHash.of(Data("# Cambiado fuera\n".utf8))
        #expect(e.huellaSinEscritor() == esperado)
        let diario = try String(contentsOf: e.state.appendingPathComponent("diario.jsonl"), encoding: .utf8)
        #expect(diario.contains("\"estado\":\"revertido\""))
    }

    // MARK: Deshacer

    /// Renombrar con sus enlaces y deshacer deja los mismos bytes (SISTEMAS §5.11, criterio 1).
    @Test func renombrarConEnlacesYDeshacer() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let antes = e.huellaSinEscritor()
        let empresa = "2 · Ventas/Empresas/Ferretería Ejemplo.md"
        let lucia = try #require(e.datos(Self.lucia))
        let texto = String(decoding: lucia, as: UTF8.self)
        func edits(_ t: String, _ old: String, _ new: String) -> [TextEdit] {
            var out: [TextEdit] = []
            var from = t.startIndex
            while let r = t.range(of: old, range: from..<t.endIndex) {
                out.append(TextEdit(offset: t.utf8.distance(from: t.utf8.startIndex, to: r.lowerBound),
                                    length: old.utf8.count, replacement: new))
                from = r.upperBound
            }
            return out
        }
        let plan = WritePlan(autor: Self.manu, descripcion: "Renombrar «Ferretería Ejemplo»", ops: [
            .move(VaultPath(empresa), to: VaultPath("2 · Ventas/Empresas/ferreteria-ejemplo.md")),
            .editRanges(VaultPath(Self.lucia), edits: edits(texto, "[[Ferretería Ejemplo]]", "[[ferreteria-ejemplo|Ferretería Ejemplo]]"),
                        baseHash: ContentHash.of(lucia)),
            .mergeFrontmatter(VaultPath("2 · Ventas/Empresas/ferreteria-ejemplo.md"),
                              set: [Property(key: "aliases", value: .list(["Ferretería Ejemplo"]))], unset: []),
        ])
        let r = try await bus.ejecutar(plan)
        #expect(r.hecho)
        #expect(e.texto(Self.lucia)?.contains("[[ferreteria-ejemplo|Ferretería Ejemplo]]") == true)
        #expect(e.texto("2 · Ventas/Empresas/ferreteria-ejemplo.md")?.contains("aliases: [Ferretería Ejemplo]") == true)
        #expect(await bus.ultimoDeshacible()?.descripcion == "Renombrar «Ferretería Ejemplo»")
        let d = try await bus.deshacer(autor: Self.manu)
        #expect(d.hecho)
        #expect(e.huellaSinEscritor() == antes)
        // A → B → A también.
        _ = try await bus.ejecutar(.mover(VaultPath(empresa), a: VaultPath("2 · Ventas/Empresas/b.md")), autor: Self.manu)
        _ = try await bus.ejecutar(.mover(VaultPath("2 · Ventas/Empresas/b.md"), a: VaultPath(empresa)), autor: Self.manu)
        #expect(e.huellaSinEscritor() == antes)
        // Deshacer va hacia atrás, plan a plan.
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(e.existe("2 · Ventas/Empresas/b.md"))
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(e.huellaSinEscritor() == antes)
    }

    @Test func deshacerNoPisaCambiosPosteriores() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        #expect(await bus.ultimoDeshacible() == nil)
        await esperaErrorAsync(.nadaQueDeshacer) { try await bus.deshacer(autor: Self.manu) }
        // Sustituir todo el texto, con compare-and-swap sobre lo leído.
        let leido = try #require(e.datos(Self.rumbo))
        let op = try #require(WriteOp.replaceText(VaultPath(Self.rumbo), base: leido, text: "# Rumbo nuevo\n"))
        #expect(try await bus.ejecutar(WritePlan(autor: Self.manu, descripcion: "Reescribir", ops: [op])).hecho)
        #expect(e.texto(Self.rumbo) == "# Rumbo nuevo\n")
        await esperaErrorAsync(.cambioExterno(Self.rumbo)) {
            try await bus.ejecutar(WritePlan(autor: Self.manu, descripcion: "Otra vez", ops: [op]))
        }
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(e.datos(Self.rumbo) == leido)
        _ = try await bus.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Más rumbo."), autor: Self.manu)
        e.escribir(Self.rumbo, "# Rumbo cambiado en Obsidian\n")
        let antes = e.huella()
        await esperaErrorAsync(.noSePuedeDeshacer(Self.rumbo)) { try await bus.deshacer(autor: Self.manu) }
        #expect(e.huella() == antes)
        // Lo creado se retira al Archivo al deshacer: no se borra.
        let c = try await bus.ejecutar(.crear(VaultPath("Buzón/Nota rápida.md"), texto: "Idea\n"), autor: Self.manu)
        #expect(c.hecho)
        _ = try await bus.deshacer(autor: Self.manu)
        #expect(!e.existe("Buzón/Nota rápida.md"))
        #expect(e.texto("Archivo/Buzón/Nota rápida.md") == "Idea\n")
    }

    // MARK: Quién puede sustituir el cuerpo

    @Test func cuerpoSegunAutor() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let path = VaultPath(Self.lucia)
        let datos = try #require(e.datos(Self.lucia))
        // Sistema y asistentes: una nota de G3 que la app nunca escribió no se reescribe.
        await esperaErrorAsync(.soloAnadidos(Self.lucia)) {
            try await bus.ejecutar(.sustituirCuerpo(path, cuerpo: "Nuevo\n", baseHash: nil), autor: .sistema)
        }
        await esperaErrorAsync(.soloAnadidos(Self.lucia)) {
            try await bus.ejecutar(.sustituirCuerpo(path, cuerpo: "Nuevo\n", baseHash: nil), autor: .agente("comercial"))
        }
        // Pero sí añadir y cambiar propiedades.
        #expect(try await bus.ejecutar(.anadirASeccion(path, seccion: "Actividad", texto: "### 2026-10-22 · sistema\nNota."), autor: .sistema).hecho)
        // La persona no necesita `hash_app`: compare-and-swap contra lo que abrió su editor.
        // Editar el cuerpo no toca las propiedades (ni un byte).
        let actual = try #require(e.datos(Self.lucia))
        let propiedades = try #require(FrontmatterDocument(data: actual)).frontmatterBlock
        #expect(try await bus.ejecutar(.sustituirCuerpo(path, cuerpo: "\n# Lucía\n", baseHash: ContentHash.of(actual)), autor: Self.manu).hecho)
        #expect(FrontmatterDocument(data: try #require(e.datos(Self.lucia)))?.frontmatterBlock == propiedades)
        #expect(e.texto(Self.lucia)?.hasSuffix("---\n\n# Lucía\n") == true)
        #expect(e.datos(Self.lucia) != datos)
        // Ahora la app la dejó así: el sistema sí puede sustituir el cuerpo.
        #expect(try await bus.ejecutar(.sustituirCuerpo(path, cuerpo: "\n# Lucía (sistema)\n", baseHash: nil), autor: .sistema).hecho)
        // Hasta que alguien la cambie fuera.
        e.escribir(Self.lucia, e.texto(Self.lucia)! + "Añadido en Obsidian.\n")
        await esperaErrorAsync(.soloAnadidos(Self.lucia)) {
            try await bus.ejecutar(.sustituirCuerpo(path, cuerpo: "Otra vez\n", baseHash: nil), autor: .sistema)
        }
    }

    @Test func guardarraileYAsistentes() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let path = VaultPath(Self.lucia)
        // Nunca una lista vacía encima de una con contenido (salvo que lo haga una persona).
        await esperaErrorAsync(.listaVacia("etiquetas")) {
            try await bus.ejecutar(.cambiarPropiedades(path, poner: [Property(key: "etiquetas", value: .list([]))], quitar: []), autor: .sistema)
        }
        await esperaErrorAsync(.listaVacia("etiquetas")) {
            try await bus.ejecutar(.cambiarPropiedades(path, poner: [], quitar: ["etiquetas"]), autor: .agente("comercial"))
        }
        #expect(try await bus.ejecutar(.cambiarPropiedades(path, poner: [Property(key: "etiquetas", value: .list([]))], quitar: []),
                                       autor: Self.manu).hecho)
        // Filas manuales: intocables para procesos automáticos.
        e.escribir("4 · Finanzas/Fechas de documentos.csv", "ruta,fecha,fuente,nota\r\nA.pdf,2026-01-01,manual,\r\n")
        let fechas = VaultPath("4 · Finanzas/Fechas de documentos.csv")
        await esperaErrorAsync(.filaManual("A.pdf")) {
            try await bus.ejecutar(.guardarFila(fechas, fila: ["ruta": "A.pdf", "fecha": "2026-02-02"], clave: "ruta"), autor: .sistema)
        }
        #expect(try await bus.ejecutar(.guardarFila(fechas, fila: ["ruta": "B.pdf", "fecha": "2026-02-02", "fuente": "ocr"], clave: "ruta"),
                                       autor: .sistema).hecho)
        #expect(e.texto("4 · Finanzas/Fechas de documentos.csv") == "ruta,fecha,fuente,nota\r\nA.pdf,2026-01-01,manual,\r\nB.pdf,2026-02-02,ocr,\r\n")
        // Los asistentes no mueven fichas fuera del Buzón ni tocan `.tls/`.
        await esperaErrorAsync(.noPermitidoAsistente(Self.lucia)) {
            try await bus.ejecutar(.mover(path, a: VaultPath("2 · Ventas/Contactos/lucia.md")), autor: .agente("ordenador"))
        }
        #expect(try await bus.ejecutar(.mover(VaultPath("Buzón/Correspondencia.md"), a: VaultPath("Buzón/Correo.md")),
                                       autor: .agente("ordenador")).hecho)
        await esperaErrorAsync(.rutaNoPermitida(".tls/config.yaml")) {
            try await bus.ejecutar(.crear(VaultPath(".tls/config.yaml"), texto: "version: 1\n"), autor: .agente("x"))
        }
        // El sistema sí escribe sus ajustes, pero nunca `escritor.json` ni otros ocultos.
        #expect(try await bus.ejecutar(.crear(VaultPath(".tls/secuencias.json"), texto: "{\"tarea\":2}\n"), autor: .sistema).hecho)
        await esperaErrorAsync(.rutaNoPermitida(".tls/escritor.json")) {
            try await bus.ejecutar(.crear(VaultPath(".tls/escritor.json"), texto: "{}"), autor: .sistema)
        }
        await esperaErrorAsync(.rutaNoPermitida(".obsidian/app.json")) {
            try await bus.ejecutar(.crear(VaultPath(".obsidian/app.json"), texto: "{}"), autor: Self.manu)
        }
        // Lo que dejaría las propiedades ilegibles no se guarda.
        await esperaErrorAsync(.propiedadesIlegibles("1 · Dirección/Rota.md")) {
            try await bus.ejecutar(.crear(VaultPath("1 · Dirección/Rota.md"), texto: "---\nclave: [sin cerrar\n---\n"), autor: Self.manu)
        }
    }

    @Test func rutasPeligrosas() async throws {
        let e = EntornoEscritura(exclusiones: ["Privado"])
        defer { e.limpiar() }
        let bus = try await e.bus()
        // Lo excluido de la copia no se escribe.
        await esperaErrorAsync(.rutaNoPermitida("Privado/nuevo.md")) {
            try await bus.ejecutar(.crear(VaultPath("Privado/nuevo.md"), texto: "x"), autor: Self.manu)
        }
        // A través de un enlace simbólico, nunca.
        let fuera = Apoyo.tempDir("fuera")
        defer { Apoyo.limpiar(fuera) }
        try FileManager.default.createSymbolicLink(at: e.url("Atajo"), withDestinationURL: fuera)
        await esperaErrorAsync(.enlaceSimbolico("Atajo/x.md")) {
            try await bus.ejecutar(.crear(VaultPath("Atajo/x.md"), texto: "x"), autor: Self.manu)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fuera.path).isEmpty)
        await esperaErrorAsync(.rutaNoPermitida("../fuera.md")) {
            try await bus.ejecutar(.crear(VaultPath("../fuera.md"), texto: "x"), autor: Self.manu)
        }
    }

    // MARK: Vigilancia y reindexado

    @Test func escriturasPropiasNoCuentanComoExternas() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let avisadas = Caja<[[VaultPath]]>([])
        await bus.writer.setOnApplied { paths in avisadas.update { $0.append(paths) } }
        let r = try await bus.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Más."), autor: Self.manu)
        #expect(avisadas.value == [r.cambiadas])
        let recent = bus.writer.recentWrites
        #expect(recent.isOwn(VaultPath(Self.rumbo), root: e.root))
        #expect(recent.filterExternal([VaultPath(Self.rumbo), VaultPath(Self.lucia)], root: e.root) == [VaultPath(Self.lucia)])
        e.escribir(Self.rumbo, "# Cambiado fuera\n")
        #expect(!recent.isOwn(VaultPath(Self.rumbo), root: e.root))
        let m = try await bus.ejecutar(.mover(VaultPath(Self.lucia), a: VaultPath("2 · Ventas/Contactos/lucia.md")), autor: Self.manu)
        #expect(m.hecho)
        #expect(recent.isOwn(VaultPath(Self.lucia), root: e.root))
        #expect(recent.isOwn(VaultPath("2 · Ventas/Contactos/lucia.md"), root: e.root))
    }

    // MARK: Escritor único

    @Test func escritorUnico() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let a = try await e.bus()
        // Abrir no deja rastro en la carpeta.
        #expect(!e.existe(".tls/escritor.json"))
        _ = try await a.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Uno."), autor: Self.manu)
        let attrs = try FileManager.default.attributesOfItem(atPath: e.url(".tls/escritor.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let info = try #require(try WriterClaim.read(root: e.root))
        #expect(info.vault_id == e.entry.id.uuidString.lowercased())
        #expect(info.instalacion == VaultRegistry(directory: e.appSupport).installationID().uuidString.lowercased())
        #expect(info.empresa == "Estudio Ejemplo")
        // Otro escritor de este Mac (otra ventana): no puede mientras el primero tenga la carpeta.
        let b = try await e.bus()
        await esperaErrorAsync(.otroProceso) { try await b.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Dos."), autor: Self.manu) }
        await a.writer.close()
        #expect(try await b.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Dos."), autor: Self.manu).hecho)
        await b.writer.close()
        // Otra instalación (otro Mac): solo lee.
        var otra = info
        otra.instalacion = UUID().uuidString.lowercased()
        otra.equipo = "Mac de otra persona"
        let c = try await e.bus()
        try FileManager.default.removeItem(at: e.url(".tls/escritor.json"))
        try WriterClaim.write(otra, root: e.root)
        let antes = e.huella()
        await esperaErrorAsync(.otroEscritor(equipo: "Mac de otra persona", desde: otra.desde)) {
            try await c.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Tres."), autor: Self.manu)
        }
        // La carpeta del fork (con `workspace_id`): solo lectura.
        try FileManager.default.removeItem(at: e.url(".tls/escritor.json"))
        e.escribir(".tls/escritor.json", #"{"instalacion":"x","equipo":"server","workspace_id":"ws-1","empresa":"The Last","desde":"2026-10-01"}"#)
        await esperaErrorAsync(.carpetaDelFork("The Last")) {
            try await c.ejecutar(.anadirLinea(VaultPath(Self.rumbo), linea: "Tres."), autor: Self.manu)
        }
        var esperado = antes
        esperado[".tls/escritor.json"] = e.huella()[".tls/escritor.json"]
        #expect(e.huella() == esperado)
    }

    // MARK: Política: la carpeta real nunca se escribe

    @Test func laCarpetaRealNuncaSeEscribe() async throws {
        let e = EntornoEscritura(clase: .real, escritura: .permitida)
        defer { e.limpiar() }
        let antes = Apoyo.huellaDeArbol(e.root)
        await esperaErrorAsync(.carpetaReal) { try await e.writer() }
        // Una copia que dice ser real en su `.tls/config.yaml` tampoco.
        let f = EntornoEscritura(clase: .copia)
        defer { f.limpiar() }
        f.escribir(".tls/config.yaml", "version: 1\nclase: real\n")
        let antesF = Apoyo.huellaDeArbol(f.root)
        await esperaErrorAsync(.carpetaReal) { try await f.writer() }
        // En solo lectura, tampoco.
        let g = EntornoEscritura(clase: .copia, escritura: .bloqueada)
        defer { g.limpiar() }
        await esperaErrorAsync(.soloLectura) { try await g.writer() }
        #expect(Apoyo.huellaDeArbol(e.root) == antes)
        #expect(Apoyo.huellaDeArbol(f.root) == antesF)
        // Ni escritor.json ni cerrojos ni estado.
        #expect(!e.existe(".tls/escritor.json"))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: e.appSupport.appendingPathComponent("locks").path)) == nil)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: e.state.path))?.isEmpty ?? true)
        #expect(WritePolicy.escrituraInicial(para: .real) == .bloqueada)
        #expect(WritePolicy.escrituraInicial(para: .copia) == .permitida)
        #expect(WritePolicy.escrituraInicial(para: .demo) == .permitida)
    }

    @Test func registroPermiteEscribirEnCopias() throws {
        let dir = Apoyo.tempDir("registro")
        defer { Apoyo.limpiar(dir) }
        let reg = VaultRegistry(directory: dir)
        let copia = VaultEntry(nombre: "Copia", ruta: "/x", bookmark: nil, clase: .copia, escritura: .bloqueada)
        let demo = VaultEntry(nombre: "Demo", ruta: "/y", bookmark: nil, clase: .demo, escritura: .bloqueada)
        let real = VaultEntry(nombre: "Real", ruta: "/z", bookmark: nil, clase: .real, escritura: .permitida)
        for v in [copia, demo, real] { try reg.upsert(v) }
        #expect(Set(try reg.permitirEscrituraEnCopias()) == [copia.id, demo.id, real.id])
        let byID = Dictionary(uniqueKeysWithValues: reg.load().map { ($0.id, $0) })
        #expect(byID[copia.id]?.escritura == .permitida)
        #expect(byID[demo.id]?.escritura == .permitida)
        #expect(byID[real.id]?.escritura == .bloqueada)
        // Si la persona pone la copia en solo lectura, se queda así.
        var bloqueada = byID[copia.id]!
        bloqueada.escritura = .bloqueada
        try reg.upsert(bloqueada)
        #expect(try reg.permitirEscrituraEnCopias().isEmpty)
        #expect(reg.load().first { $0.id == copia.id }?.escritura == .bloqueada)
        // Después del primer arranque, una copia en solo lectura («Ver sin tocar») se queda así.
        let nueva = VaultEntry(nombre: "Nueva", ruta: "/w", bookmark: nil, clase: .copia, escritura: .bloqueada)
        try reg.upsert(nueva)
        #expect(try reg.permitirEscrituraEnCopias().isEmpty)
        #expect(reg.load().first { $0.id == nueva.id }?.escritura == .bloqueada)
    }
}
