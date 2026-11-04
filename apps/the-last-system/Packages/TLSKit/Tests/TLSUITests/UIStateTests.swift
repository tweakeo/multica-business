import Foundation
import Testing
import TLSCore
import TLSDesign
import TLSImport
@testable import TLSUI

@Suite("Interfaz · textos y estado")
@MainActor
struct UIStateTests {
    private func entry(_ clase: VaultClass, creada: Date = Date()) -> VaultEntry {
        VaultEntry(nombre: "Asesoría Ribera", ruta: "/tmp/no-existe", bookmark: nil, clase: clase,
                   escritura: .bloqueada, creada: creada)
    }

    @Test("Banner de la copia con su fecha; insignias por clase")
    func banner() {
        let copia = entry(.copia)
        #expect(copia.bannerText == "Copia del \(TLSFormat.fechaCorta(copia.creada)): lo que cambies aquí no llega a tu carpeta real")
        #expect(copia.clase.badge == .copia)
        #expect(entry(.demo).clase.badge == .ejemplo)
        #expect(entry(.real).clase.badge == .soloLectura)
        #expect(entry(.real).bannerText.hasPrefix("Solo lectura"))
    }

    @Test("Resumen de la copia")
    func resumenCopia() {
        let report = CopyReport(vaultID: UUID(), destino: "/tmp/x", copiados: 1_034, bytes: 0,
                                soloEnICloud: (0..<12).map { "f\($0).pdf" }, verificados: 1_034,
                                diferencias: [], exclusiones: ["Archivo"], fecha: Date())
        #expect(CreateCopyModel.resumen(report)
                == "1.034 archivos copiados y verificados · 12 solo en iCloud, no se han descargado")

        let uno = CopyReport(vaultID: UUID(), destino: "/tmp/x", copiados: 1, bytes: 0, soloEnICloud: [],
                             verificados: 1, diferencias: [], exclusiones: [], fecha: Date())
        #expect(CreateCopyModel.resumen(uno) == "1 archivo copiado y verificado")
    }

    @Test("La pregunta de carpetas privadas es obligatoria")
    func privadasObligatoria() {
        let model = CreateCopyModel()
        #expect(!model.puedeCrear)
        model.origen = URL(fileURLWithPath: "/tmp")
        #expect(!model.puedeCrear)
        model.privadas = .si
        #expect(!model.puedeCrear, "«Sí» sin elegir ninguna carpeta no basta")
        model.exclusiones = [VaultPath("4 · Finanzas/Privado")]
        #expect(model.puedeCrear)
        model.quitar(VaultPath("4 · Finanzas/Privado"))
        #expect(model.privadas == .sinResponder)
        model.privadas = .no
        #expect(model.puedeCrear)
    }

    @Test("«Ver sin tocar»: lo privado se guarda y no se lista ni se indexa")
    func verSinTocarPrivado() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-ui-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("Empresa", isDirectory: true)
        let privada = root.appendingPathComponent("4 · Finanzas/Privada X", isDirectory: true)
        try FileManager.default.createDirectory(at: privada, withIntermediateDirectories: true)
        try Data("# Secreto\nnada".utf8).write(to: privada.appendingPathComponent("Secreto.md"))
        try Data("# Pública\nhola".utf8).write(to: root.appendingPathComponent("4 · Finanzas/Pública.md"))

        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup")))
        let first = try model.registerReadOnly(url: root, privadas: [VaultPath("4 · Finanzas/Privada X")])
        #expect(first.clase == .real && first.escritura == .bloqueada)
        #expect(first.exclusionesCopia == ["4 · Finanzas/Privada X"])
        // Volver a elegir «No hay» no quita lo privado ya guardado.
        let again = try model.registerReadOnly(url: root, privadas: [])
        #expect(again.id == first.id && again.exclusionesCopia == first.exclusionesCopia)
        #expect(model.registry.load().first?.exclusionesCopia == ["4 · Finanzas/Privada X"])

        let service = try VaultService(entry: again, root: root,
                                       options: .init(stateDirectory: base.appendingPathComponent("estado"),
                                                      vigilar: false))
        _ = try await service.open { _ in }
        #expect(!service.children(of: VaultPath("4 · Finanzas")).contains { $0.path.name == "Privada X" })
        #expect(service.search("Secreto", limit: 10).isEmpty)
        #expect(service.quickOpen("Secreto", limit: 10).isEmpty)
        service.close()
    }

    @Test("Paleta: filtra sin tildes ni mayúsculas")
    func paleta() {
        let session = VaultSession(entry: entry(.copia))
        let all = PaletteAction.all(session: session)
        #expect(all.count >= 6 + 4)
        let dir = PaletteAction.filtered(all, query: "direccion")
        #expect(dir.map(\.id) == ["area.DIR"])
        #expect(PaletteAction.filtered(all, query: "  ").count == all.count)
        #expect(PaletteAction.filtered(all, query: "FINDER").map(\.id) == ["finder"])
    }

    @Test("Árbol perezoso: sin datos no hay filas y las carpetas se despliegan a demanda")
    func arbol() {
        let session = VaultSession(entry: entry(.copia))
        #expect(session.folderRows.isEmpty)
        #expect(!session.isLoaded(.root))
        session.collapse(VaultPath("2 · Ventas"))
        #expect(session.expanded.isEmpty)
    }

    @Test("Nombre visible de un enlace sin destino")
    func linkName() {
        #expect(VaultSession.visibleLinkName("[[Rumbo]]") == "Rumbo")
        #expect(VaultSession.visibleLinkName("Sistemas/Diagn%C3%B3stico%20y.md") == "Sistemas/Diagnóstico y.md")
    }

    @Test("Comprobación de permisos sin leer el contenido")
    func access() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tls-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        #expect(FolderAccess.checkSync(tmp) == .ok)
        #expect(FolderAccess.checkSync(tmp.appendingPathComponent("no-existe")) == .noExiste)

        let eperm = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        #expect(FolderAccess.isPermissionError(eperm))
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: eperm])
        #expect(FolderAccess.isPermissionError(wrapped))
        #expect(!FolderAccess.isPermissionError(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
    }

    @Test("Textos visibles sin jerga prohibida (§6.9)")
    func glosario() {
        let prohibidas = ["frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "vault", "hash"]
        var textos = [
            entry(.copia).bannerText, entry(.real).bannerText, entry(.demo).bannerText,
            entry(.copia).claseDescripcion, entry(.real).claseDescripcion,
        ]
        textos += NoteKind.allCases.map(\.etiqueta)
        textos += [AreaStatus.activa, .preparada, .reposo, .desconocido].map(\.etiqueta)
        textos += PaletteAction.all(session: VaultSession(entry: entry(.copia))).map(\.title)
        for texto in textos {
            let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            for p in prohibidas {
                #expect(!palabras.contains(p), "«\(texto)» contiene «\(p)»")
            }
        }
    }
}
