import Foundation
import Testing
@testable import TLSCore

/// Garantías de privacidad de F0 en la lectura (revisión adversarial): lo excluido no se lee, no se
/// lista, no se enlaza y no entra en el índice, ni con otras mayúsculas ni a través de enlaces.
@Suite(.serialized) struct PrivacidadTests {
    /// Carpeta con «Privado/secreto.md» y una nota que enlaza con otras mayúsculas.
    static func carpeta(_ marca: String) -> URL {
        let root = Apoyo.tempDir("priv").resolvingSymlinksInPath()
        escribir("Privado/secreto.md", "# Secreto\n\(marca)\n", en: root)
        escribir("Notas/a.md", "Ver [esto](../privado/secreto.md) y [[privado/secreto]].\n", en: root)
        return root
    }

    static func escribir(_ rel: String, _ texto: String, en root: URL) {
        let url = root.appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(texto.utf8).write(to: url)
    }

    static func entrada(_ root: URL, exclusiones: [String] = [], clase: VaultClass = .real) -> VaultEntry {
        VaultEntry(nombre: "Prueba", ruta: root.path, bookmark: nil, clase: clase, escritura: .bloqueada,
                   exclusionesCopia: exclusiones)
    }

    static func texto(_ c: NoteContent) -> String? {
        switch c {
        case .markdown(let text, _, _, _, _): text
        case .plain(let text): text
        case .csv(_, _, let text): text
        default: nil
        }
    }

    /// Ficheros de `dir` cuyos bytes contienen `needle` (p. ej. páginas libres de SQLite o el WAL).
    static func bytesContienen(_ needle: String, dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { n in
            FileManager.default.contents(atPath: dir.appendingPathComponent(n).path)?.range(of: Data(needle.utf8)) != nil
        }
    }

    @Test func exclusionConOtrasMayusculas() async throws {
        let root = Self.carpeta("SECRETO-A1")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        let svc = try VaultService(entry: Self.entrada(root), root: root,
                                   options: .init(excluidas: [VaultPath("Privado")], stateDirectory: state, vigilar: false))
        _ = try await svc.open { _ in }
        defer { svc.close() }
        #expect(Self.texto(svc.read(VaultPath("Privado/secreto.md"))) == nil)
        #expect(Self.texto(svc.read(VaultPath("privado/secreto.md"))) == nil)
        #expect(Self.texto(svc.read(VaultPath("PRIVADO/SECRETO.MD"))) == nil)
        #expect(svc.resolveLink("../privado/secreto.md", from: VaultPath("Notas/a.md")) == nil)
        #expect(svc.resolveLink("[[privado/secreto]]", from: VaultPath("Notas/a.md")) == nil)
        #expect(svc.children(of: VaultPath("privado")).isEmpty)
        #expect(svc.children(of: VaultPath("PRIVADO")).isEmpty)
        #expect(!svc.children(of: .root).contains { $0.path.name == "Privado" })
        // Control: lo no excluido sí se lee con otras mayúsculas (APFS no las distingue).
        #expect(Self.texto(svc.read(VaultPath("notas/A.md"))) != nil)
    }

    @Test func exclusionGuardadaConOtrasMayusculasNoSeIndexa() async throws {
        let root = Self.carpeta("SECRETO-A2")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        let svc = try VaultService(entry: Self.entrada(root, exclusiones: ["privado"]), root: root,
                                   options: .init(stateDirectory: state, vigilar: false))
        _ = try await svc.open { _ in }
        let raiz = svc.children(of: .root).map(\.path.raw)
        let hits = svc.search("SECRETO-A2")
        svc.close()
        await svc.waitUntilIdle()
        #expect(!raiz.contains("Privado"))
        #expect(hits.isEmpty)
        #expect(Self.bytesContienen("SECRETO-A2", dir: state).isEmpty)
    }

    @Test func enlaceSimbolicoAMitadDeRuta() async throws {
        let root = Self.carpeta("SECRETO-A3")
        let fuera = Apoyo.tempDir("fuera").resolvingSymlinksInPath()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, fuera, state) }
        Self.escribir("externo.md", "FUERA-A4\n", en: fuera)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("Atajo").path,
                                                   withDestinationPath: "Privado")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Fuera"), withDestinationURL: fuera)
        let svc = try VaultService(entry: Self.entrada(root), root: root,
                                   options: .init(excluidas: [VaultPath("Privado")], stateDirectory: state, vigilar: false))
        _ = try await svc.open { _ in }
        defer { svc.close() }
        #expect(Self.texto(svc.read(VaultPath("Atajo/secreto.md"))) == nil)
        #expect(svc.resolveLink("../Atajo/secreto.md", from: VaultPath("Notas/a.md")) == nil)
        #expect(svc.children(of: VaultPath("Atajo")).isEmpty)
        #expect(Self.texto(svc.read(VaultPath("Fuera/externo.md"))) == nil)
        #expect(svc.children(of: VaultPath("Fuera")).isEmpty)
        #expect(svc.search("FUERA").isEmpty)
    }

    /// «Ver sin tocar»: lo que `.tls/` declara privado no se lista, no se lee ni se indexa.
    @Test func privadoDeTlsEnLaCarpetaReal() async throws {
        let root = Self.carpeta("SECRETO-A6")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        Self.escribir(".tls/config.yaml", "privado:\n  - Privado\n", en: root)
        let svc = try VaultService(entry: Self.entrada(root, clase: .real), root: root,
                                   options: .init(stateDirectory: state, vigilar: false))
        _ = try await svc.open { _ in }
        defer { svc.close() }
        #expect(svc.layout.privado == [VaultPath("Privado")])
        #expect(svc.search("SECRETO-A6").isEmpty)
        #expect(!svc.children(of: .root).contains { $0.path.name == "Privado" })
        #expect(Self.texto(svc.read(VaultPath("Privado/secreto.md"))) == nil)
        // En una copia (o la demo) lo privado se marca, pero se ve.
        let state2 = Apoyo.tempDir("estado2")
        defer { Apoyo.limpiar(state2) }
        let copia = try VaultService(entry: Self.entrada(root, clase: .copia), root: root,
                                     options: .init(stateDirectory: state2, vigilar: false))
        #expect(copia.children(of: .root).first { $0.path.name == "Privado" }?.privado == true)
    }

    /// La carpeta privada elegida se renombró: no se abre en silencio.
    @Test func exclusionQueYaNoExisteNoAbre() async throws {
        let root = Apoyo.tempDir("ren").resolvingSymlinksInPath()
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        Self.escribir("Privado 2026/secreto.md", "SECRETO-A9\n", en: root)
        let svc = try VaultService(entry: Self.entrada(root, exclusiones: ["Privado"]), root: root,
                                   options: .init(stateDirectory: state, vigilar: false))
        await #expect(throws: VaultServiceError.self) { _ = try await svc.open { _ in } }
        #expect(svc.search("SECRETO-A9").isEmpty)
        svc.close()
        // Solo cambian las mayúsculas: es la misma carpeta, abre bien.
        let otra = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(otra) }
        let svc2 = try VaultService(entry: Self.entrada(root, exclusiones: ["privado 2026"]), root: root,
                                    options: .init(stateDirectory: otra, vigilar: false))
        _ = try await svc2.open { _ in }
        #expect(svc2.search("SECRETO-A9").isEmpty)
        svc2.close()
        // En una copia lo excluido no existe por diseño: abre.
        let svc3 = try VaultService(entry: Self.entrada(root, exclusiones: ["No está"], clase: .copia), root: root,
                                    options: .init(stateDirectory: otra, vigilar: false))
        _ = try await svc3.open { _ in }
        svc3.close()
    }

    /// Lo que se excluye después no se queda en bruto en el índice ni en su diario.
    @Test func sinRestosEnElIndiceTrasExcluir() async throws {
        let root = Self.carpeta("SECRETO-A7")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        let a = try VaultService(entry: Self.entrada(root), root: root, options: .init(stateDirectory: state, vigilar: false))
        _ = try await a.open { _ in }
        #expect(a.search("SECRETO-A7").count == 1)  // control
        a.close()
        await a.waitUntilIdle()
        let b = try VaultService(entry: Self.entrada(root, exclusiones: ["Privado"]), root: root,
                                 options: .init(stateDirectory: state, vigilar: false))
        _ = try await b.open { _ in }
        #expect(b.search("SECRETO-A7").isEmpty)
        b.close()
        await b.waitUntilIdle()
        #expect(Self.bytesContienen("SECRETO-A7", dir: state).isEmpty)
    }

    @Test func estadoNuncaDentroDeLaCarpetaNiEnICloud() throws {
        let root = Self.carpeta("X")
        defer { Apoyo.limpiar(root) }
        #expect(throws: VaultServiceError.self) {
            _ = try VaultService(entry: Self.entrada(root), root: root,
                                 options: .init(stateDirectory: root.appendingPathComponent(".tls/estado"), vigilar: false))
        }
        // Escrita con otras mayúsculas o por /tmp en vez de /private/tmp: también.
        #expect(throws: VaultServiceError.self) {
            _ = try VaultService(entry: Self.entrada(root), root: root,
                                 options: .init(stateDirectory: URL(fileURLWithPath: root.path.uppercased() + "/estado"),
                                                vigilar: false))
        }
        let icloud = URL(fileURLWithPath: AppLocations.iCloudDrivePath).appendingPathComponent("x/estado")
        #expect(throws: VaultServiceError.self) {
            _ = try VaultService(entry: Self.entrada(root), root: root, options: .init(stateDirectory: icloud, vigilar: false))
        }
        #expect(AppLocations.isInICloudDrive(icloud.path))
        #expect(!AppLocations.isInICloudDrive(root.path))
    }

    /// Un PDF (o cualquier cosa que el visor no muestra) no se lee: devuelve `.binary` sin abrirlo.
    @Test func loQueNoSeVeNoSeLee() async throws {
        let root = Self.carpeta("X")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        Self.escribir("Notas/factura.pdf", "%PDF-1.4", en: root)
        let svc = try VaultService(entry: Self.entrada(root), root: root,
                                   options: .init(stateDirectory: state, vigilar: false))
        guard case .binary(let size) = svc.read(VaultPath("Notas/factura.pdf")) else {
            Issue.record("debería ser .binary"); return
        }
        #expect(size == 8)
    }
}

/// Cambios en `.tls/` con la carpeta abierta: se relee la estructura y se revisa todo.
@Suite(.serialized) struct PrivacidadEnCalienteTests {
    @Test func privadoDeclaradoConLaCarpetaAbierta() async throws {
        let root = PrivacidadTests.carpeta("SECRETO-CALIENTE")
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        let svc = try VaultService(entry: PrivacidadTests.entrada(root, clase: .real), root: root,
                                   options: .init(stateDirectory: state, vigilar: true))
        let avisos = Caja<[[VaultPath]]>([])
        svc.onExternalChange = { paths in avisos.update { $0.append(paths) } }
        _ = try await svc.open { _ in }
        #expect(svc.search("SECRETO-CALIENTE").count == 1)  // control: aún no es privado
        try await Task.sleep(for: .milliseconds(300))
        PrivacidadTests.escribir(".tls/config.yaml", "privado:\n  - privado\n", en: root)
        // Llega un aviso de «revisa todo» (lista vacía) y lo privado ya no se ve ni se busca.
        #expect(await Apoyo.esperar(6) { avisos.value.contains { $0.isEmpty } })
        #expect(svc.search("SECRETO-CALIENTE").isEmpty)
        #expect(!svc.children(of: .root).contains { $0.path.name == "Privado" })
        svc.close()
        await svc.waitUntilIdle()
        #expect(PrivacidadTests.bytesContienen("SECRETO-CALIENTE", dir: state).isEmpty)
    }
}

/// Cierre y apertura concurrentes del mismo índice (ventana cerrada y abierta, o `tls-tool` a la vez).
@Suite(.serialized) struct ConcurrenciaIndiceTests {
    static func carpetaGrande(_ n: Int) throws -> URL {
        let root = Apoyo.tempDir("grande")
        for i in 0..<n {
            let dir = root.appendingPathComponent("1 · Dirección/Notas \(i / 200)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "# Nota \(i)\n\nTexto [[Nota \(i + 1)]] con algo de contenido.\n"
                .write(to: dir.appendingPathComponent("Nota \(i).md"), atomically: false, encoding: .utf8)
        }
        return root
    }

    @Test func cerrarDuranteLaAperturaNoDejaVigilancia() async throws {
        let root = try Self.carpetaGrande(3000)
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        let svc = try VaultService(entry: Apoyo.entrada(root), root: root, options: .init(stateDirectory: state, vigilar: true))
        let apertura = Task { try await svc.open { _ in } }
        try await Task.sleep(for: .milliseconds(60))
        svc.close()
        let resultado = await apertura.result
        await svc.waitUntilIdle()
        #expect(svc.debugState.watching == false)
        #expect(svc.debugState.indexOpen == false)
        if case .success = resultado {
            // Terminó antes del cierre: también vale, pero sin vigilancia.
        } else if case .failure(let error) = resultado {
            #expect(error is CancellationError)
        }
    }

    @Test func segundoServicioEsperaAlPrimero() async throws {
        let root = try Self.carpetaGrande(3000)
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(root, state) }
        let a = try VaultService(entry: Apoyo.entrada(root), root: root, options: .init(stateDirectory: state, vigilar: false))
        let ta = Task { try await a.open { _ in } }
        try await Task.sleep(for: .milliseconds(100))
        a.close()
        let b = try VaultService(entry: Apoyo.entrada(root), root: root, options: .init(stateDirectory: state, vigilar: false))
        let stats = try await b.open { _ in }
        #expect(stats.notes == 3000)
        _ = await ta.result
        b.close()
    }

    @Test func reabrirTrasCerrarFunciona() async throws {
        let state = Apoyo.tempDir("estado")
        defer { Apoyo.limpiar(state) }
        let svc = try Apoyo.servicio(Apoyo.empresaMinima, state: state)
        _ = try await svc.open { _ in }
        svc.close()
        let stats = try await svc.open { _ in }
        #expect(stats.notes > 30)
        #expect(!svc.search("facturacion").isEmpty)
        svc.close()
    }
}

/// Lectores frente a textos raros.
@Suite struct LectoresRobustosTests {
    @Test func tituloConAlmohadillaFinal() {
        #expect(NoteDocument(text: "# Lenguaje C#\n\nTexto\n").heading == "Lenguaje C#")
        #expect(NoteDocument(text: "# Nota #\n").heading == "Nota")
        #expect(NoteDocument(text: "# Nota ##   \n").heading == "Nota")
        #expect(NoteDocument(text: "# #\n").heading == nil)
    }

    @Test func bombaDeAliasNoCuelgaLaLectura() {
        var bomba = "---\na: &a [\"x\",\"x\",\"x\",\"x\",\"x\",\"x\",\"x\",\"x\",\"x\"]\n"
        var prev = "a"
        for n in ["b", "c", "d", "e", "f", "g", "h"] {
            bomba += "\(n): &\(n) [" + Array(repeating: "*\(prev)", count: 9).joined(separator: ",") + "]\n"
            prev = n
        }
        bomba += "---\nx\n"
        let t0 = Date()
        let fm = NoteDocument(text: bomba).frontmatter
        _ = fm.json
        #expect(Date().timeIntervalSince(t0) < 2)
        #expect(!fm.isValid)
        // Un alias normal sigue leyéndose.
        let normal = NoteDocument(text: "---\nbase: &b {x: 1}\notro: *b\ntitle: Hola\n---\nx\n").frontmatter
        #expect(normal.isValid)
        #expect(normal.titleText == "Hola")
    }

    @Test func privadoConPlantillasYFormatosValidos() throws {
        let root = Apoyo.tempDir("layout")
        defer { Apoyo.limpiar(root) }
        for name in ["1 · Dirección", "4 · Finanzas y Fiscal"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        PrivacidadTests.escribir(".tls/layout.json", #"{"preset":"humana","privado":["{finanzas}/Bancos"]}"#, en: root)
        PrivacidadTests.escribir(".tls/config.yaml", "version: 1\r\nprivado:\r\n  - \"Privado [2026]\"\r\n  - \"Privado, Seguros\"\r\n", en: root)
        let privado = try VaultLayout.declaredPrivado(root: root)
        // La plantilla se expande con la carpeta real del área, no con el nombre del preset.
        #expect(Set(privado.map(\.raw)) == ["4 · Finanzas y Fiscal/Bancos", "Privado [2026]", "Privado, Seguros"])
        #expect(VaultLayout.load(root: root).layout.isPrivate(VaultPath("privado [2026]/x.md")))

        // Ajustes que existen pero no se pueden leer: `declaredPrivado` para; `load` avisa sin jerga.
        PrivacidadTests.escribir(".tls/config.yaml", "privado: [sin cerrar\n", en: root)
        #expect(throws: VaultLayoutError.self) { _ = try VaultLayout.declaredPrivado(root: root) }
        #expect(VaultLayout.load(root: root).aviso == VaultLayout.avisoIlegible)
        #expect(!VaultLayout.avisoIlegible.contains(".tls"))
    }
}
