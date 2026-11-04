import Foundation
import Synchronization
import Testing
import TLSCore
import TLSDesign
import TLSImport
@testable import TLSUI

/// Correcciones de la revisión adversarial de F0 (experiencia y privacidad en la interfaz).
@Suite("Interfaz · correcciones de la revisión", .serialized)
@MainActor
struct CorreccionesUITests {
    private func tmp(_ name: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-ui-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u.resolvingSymlinksInPath()
    }

    private func escribir(_ rel: String, _ texto: String, en root: URL) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: url)
    }

    @Test("Cambiar de carpeta de origen vuelve a pedir la respuesta sobre lo privado")
    func cambiarOrigenReinicia() {
        let model = CreateCopyModel()
        model.cambiarOrigen(URL(fileURLWithPath: "/tmp/A"))
        model.privadas = .no
        #expect(model.puedeCrear)
        model.cambiarOrigen(URL(fileURLWithPath: "/tmp/B"))
        #expect(model.privadas == .sinResponder)
        #expect(!model.puedeCrear, "«No hay» era la respuesta para otra carpeta")
        model.privadas = .si
        model.exclusiones = [VaultPath("4 · Finanzas/Privado")]
        model.cambiarOrigen(URL(fileURLWithPath: "/tmp/C"))
        #expect(model.privadas == .sinResponder && model.exclusiones.isEmpty)
        // La misma carpeta otra vez no borra la respuesta.
        model.privadas = .no
        model.cambiarOrigen(URL(fileURLWithPath: "/tmp/C"))
        #expect(model.privadas == .no)
    }

    @Test("«Cancelar» en la hoja para la copia: no se registra y no queda carpeta")
    func cancelarCopiaDesdeLaHoja() async throws {
        let base = try tmp("cancelar")
        defer { try? FileManager.default.removeItem(at: base) }
        let origen = base.appendingPathComponent("Origen", isDirectory: true)
        for i in 0..<40 { try escribir("1 · Dirección/nota-\(i).md", "Nota \(i)\n", en: origen) }
        let empresas = base.appendingPathComponent("Empresas", isDirectory: true)
        let fs = PausableFileSystem()
        let app = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup")))
        let copy = CreateCopyModel()
        copy.cambiarOrigen(origen)
        copy.privadas = .no
        copy.crear(model: app, copier: DemoCopier(fileSystem: fs, appSupport: base.appendingPathComponent("asup")),
                   empresas: empresas)
        // Espera a que empiece a copiar ficheros y pulsa «Cancelar».
        for _ in 0..<500 where !fs.started.value { try await Task.sleep(for: .milliseconds(10)) }
        #expect(fs.started.value)
        copy.cancelar()
        guard case .cancelando = copy.paso else { Issue.record("debería decir «Cancelando…»"); return }
        fs.release.value = true
        await copy.esperar()
        guard case .cancelada = copy.paso else { Issue.record("debería quedar cancelada: \(copy.paso)"); return }
        app.reload()
        #expect(app.entries.isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: empresas.path)) ?? []).isEmpty)
        #expect(fs.trashed.value == 1)
    }

    @Test("Una copia que vuelve con «Ver sin tocar» sigue siendo copia")
    func copiaVueltaAAbrir() async throws {
        let base = try tmp("readonly-copia")
        defer { try? FileManager.default.removeItem(at: base) }
        let origen = base.appendingPathComponent("Origen", isDirectory: true)
        try escribir("Empresa.md", "# E\n", en: origen)
        let asup = base.appendingPathComponent("asup", isDirectory: true)
        let (report, entry) = try await DemoCopier(appSupport: asup)
            .copy(from: origen, into: base.appendingPathComponent("Empresas"), options: CopyOptions(exclusiones: [])) { _ in }
        let app = AppModel(registry: VaultRegistry(directory: asup))
        try app.register(entry)
        try app.remove(id: entry.id)
        let url = URL(fileURLWithPath: report.destino)
        let config = try await CopyConfig.peek(url)
        let vuelta = try app.registerReadOnly(url: url, privadas: [], config: config)
        #expect(vuelta.clase == .copia)
        #expect(vuelta.id == entry.id, "reutiliza su índice")
        #expect(vuelta.clase.badge == .copia)
        #expect(vuelta.bannerText.hasPrefix("Copia del"))
        #expect(vuelta.origen == origen.path)
        // La carpeta real sigue entrando como real.
        let real = try app.registerReadOnly(url: origen, privadas: [], config: try await CopyConfig.peek(origen))
        #expect(real.clase == .real)
    }

    @Test("Volver a elegir una carpeta privada que ya no está")
    func sustituirExclusionPerdida() throws {
        let base = try tmp("perdida")
        defer { try? FileManager.default.removeItem(at: base) }
        let app = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup")))
        let e = try app.registerReadOnly(url: base, privadas: [VaultPath("Privado"), VaultPath("Otra")])
        try app.replaceExclusion(id: e.id, missing: "privado", with: [VaultPath("Privado 2026")])
        #expect(app.entry(id: e.id)?.exclusionesCopia == ["Otra", "Privado 2026"])
    }

    @Test("Errores del sistema en castellano llano")
    func errorDeCarpetaEnCastellano() throws {
        let base = try tmp("eloop")
        defer { try? FileManager.default.removeItem(at: base) }
        let a = base.appendingPathComponent("a"), b = base.appendingPathComponent("b")
        try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: b.path)
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: a.path)
        guard case .otro = FolderAccess.checkSync(a) else { Issue.record("un bucle de enlaces es .otro"); return }
        #expect(FolderAccess.mensajeOtro.hasPrefix("No he podido abrir esa carpeta"))
    }

    @Test("El botón de abrir no dice «copia» si lo elegido es la carpeta real")
    func tituloDeAbrir() {
        let real = VaultEntry(nombre: "R", ruta: "/x", bookmark: nil, clase: .real, escritura: .bloqueada)
        let copia = VaultEntry(nombre: "C", ruta: "/y", bookmark: nil, clase: .copia, escritura: .bloqueada)
        #expect(LauncherView.openTitle(for: real) == "Abrir")
        #expect(LauncherView.openTitle(for: copia) == "Abrir copia")
    }

    @Test("Notas con saltos de Windows (CRLF) o de Mac antiguo (CR): mismos enlaces y estilos")
    func saltosDeLinea() {
        let lf = "# Título\n\nVer [Embudo](Sistemas/Embudo.md) y **negrita**.\n- [x] hecha\n"
        func kinds(_ t: String) -> [String] {
            MarkdownSpans.compute(t).map { s in
                let ns = t as NSString
                return "\(s.kind)=" + ns.substring(with: s.range)
                    .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            }.sorted()
        }
        let esperado = kinds(lf)
        #expect(esperado.contains { $0.hasPrefix("link(target: \"Sistemas/Embudo.md\")") })
        #expect(kinds(lf.replacingOccurrences(of: "\n", with: "\r\n")) == esperado)
        #expect(kinds(lf.replacingOccurrences(of: "\n", with: "\r")) == esperado)
        // Con tildes y emojis antes del enlace (UTF-16 ≠ UTF-8).
        let raro = "Ñandú 😀\r\n[[Ferretería]] y [a](b.md)\r\n"
        let spans = MarkdownSpans.compute(raro)
        let ns = raro as NSString
        #expect(spans.contains { $0.kind == .link(target: "b.md") && ns.substring(with: $0.range) == "[a](b.md)" })
    }

    @Test("Una nota grande se muestra sin estilo; el estilo se calcula fuera del hilo principal")
    func notaGrande() {
        let grande = String(repeating: "Texto **n** [a](b.md)\n", count: 20_000)
        #expect(grande.utf16.count > MarkdownStyler.maxStyledLength)
        #expect(MarkdownStyler.spans(forMarkdown: grande) == nil)
        #expect(MarkdownStyler.spans(forMarkdown: "**a**")?.isEmpty == false)
    }

    /// Lint del glosario (§6.9) sobre los textos literales de las vistas y los mensajes de error.
    @Test("Ningún texto visible usa jerga prohibida")
    func glosarioEnFuentes() throws {
        let prohibidas = ["frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "vault", "hash"]
        var textos: [String] = []
        // Mensajes de error y avisos de TLSCore/TLSImport que llegan a la pantalla.
        textos += [VaultServiceError.carpetaNoEncontrada("/x"), .exclusionNoEncontrada("x"), .estadoNoPermitido("/x")]
            .compactMap(\.errorDescription)
        textos += [CopyError.origenNoAccesible("/x"), .destinoExiste("/x"), .verificacionFallida(2)].compactMap(\.errorDescription)
        textos += [CopyGuardError.proteccionICloud, .destinoDentroDelOrigen("/x"), .exclusionNoEncontrada("x"),
                   .privadoNoEncontrado("x"), .privadoIlegible].compactMap(\.errorDescription)
        textos += [VaultLayoutError.ajustesIlegibles("x").errorDescription ?? "", VaultLayout.avisoIlegible,
                   FolderAccess.mensajeOtro]
        // Literales de las vistas (los que tienen un espacio: frases, no identificadores).
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources").standardizedFileURL
        let carpetas = ["TLSUI", "TLSDesign"]
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        for carpeta in carpetas {
            let dir = sources.appendingPathComponent(carpeta)
            let ficheros = FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []
            for f in ficheros where f.hasSuffix(".swift") {
                let texto = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                for linea in texto.split(separator: "\n") {
                    let l = linea.trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("//") || l.contains("Logger(") || l.contains("log.") || l.contains("accessibilityIdentifier") {
                        continue
                    }
                    let ns = l as NSString
                    for m in literal.matches(in: l, range: NSRange(location: 0, length: ns.length)) {
                        let s = ns.substring(with: m.range(at: 1))
                        if s.contains(" ") { textos.append(s) }
                    }
                }
            }
        }
        // Mensajes de lectura de notas (VaultService.read).
        let servicio = try String(contentsOf: sources.appendingPathComponent("TLSCore/VaultService.swift"), encoding: .utf8)
        for linea in servicio.split(separator: "\n") where linea.contains("message: \"") {
            if let r = linea.range(of: #"message: "[^"]*""#, options: .regularExpression) { textos.append(String(linea[r])) }
        }
        #expect(textos.count > 100)
        for texto in textos {
            let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            for p in prohibidas {
                #expect(!palabras.contains(p), "«\(texto)» contiene «\(p)»")
            }
            #expect(!texto.contains(".tls/"), "«\(texto)» enseña una ruta técnica")
        }
    }
}

/// Disco que se detiene antes de copiar el primer fichero hasta que la prueba lo suelte.
final class PausableFileSystem: FileSystemAccess, Sendable {
    final class Flag: Sendable {
        private let m = Mutex(false)
        var value: Bool { get { m.withLock { $0 } } set { m.withLock { $0 = newValue } } }
    }
    final class Counter: Sendable {
        private let m = Mutex(0)
        var value: Int { m.withLock { $0 } }
        func increment() { m.withLock { $0 += 1 } }
    }

    let inner = LocalFileSystem()
    let started = Flag()
    let release = Flag()
    let trashed = Counter()

    func contentsOfDirectory(at url: URL) throws -> [URL] { try inner.contentsOfDirectory(at: url) }
    func isDirectory(_ url: URL) -> Bool { inner.isDirectory(url) }
    func isDataless(_ url: URL) -> Bool { inner.isDataless(url) }
    func fileSize(_ url: URL) -> Int64? { inner.fileSize(url) }
    func sha256(of url: URL) throws -> String { try inner.sha256(of: url) }
    func copyItem(at src: URL, to dst: URL) throws {
        started.value = true
        for _ in 0..<500 where !release.value { usleep(10_000) }
        try inner.copyItem(at: src, to: dst)
    }
    func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
    func write(_ data: Data, to url: URL) throws { try inner.write(data, to: url) }
    func fileExists(_ url: URL) -> Bool { inner.fileExists(url) }
    func isSymbolicLink(_ url: URL) -> Bool { inner.isSymbolicLink(url) }
    func contents(of url: URL) throws -> Data { try inner.contents(of: url) }
    func modificationDate(_ url: URL) -> Date? { inner.modificationDate(url) }
    func setModificationDate(_ date: Date, for url: URL) throws { try inner.setModificationDate(date, for: url) }
    /// En pruebas, nada de Papelera de verdad: se borra la carpeta temporal.
    func trashItem(_ url: URL) throws {
        trashed.increment()
        try FileManager.default.removeItem(at: url)
    }
}
