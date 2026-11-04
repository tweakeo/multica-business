import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// «Ver un ejemplo»: instala Asesoría Ribera con un `id` nuevo, la reutiliza y «Reiniciar ejemplo» la manda a la
/// Papelera y la vuelve a instalar. Todo en carpetas temporales: nunca en el `~/The Last System` de Manu.
@Suite("Arranque · ejemplo", .serialized)
@MainActor
struct EjemploTests {
    struct Entorno {
        let base: URL
        let empresas: URL
        let papelera: URL
        let model: AppModel
        let instalador: InstaladorEjemplo
        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    func entorno() throws -> Entorno {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-ejemplo-\(UUID().uuidString)", isDirectory: true)
        let empresas = base.appendingPathComponent("Empresas", isDirectory: true)
        let papelera = base.appendingPathComponent("Papelera", isDirectory: true)
        try FileManager.default.createDirectory(at: papelera, withIntermediateDirectories: true)
        let model = AppModel(registry: VaultRegistry(directory: base.appendingPathComponent("asup", isDirectory: true)))
        let instalador = InstaladorEjemplo(origen: SesionEscrituraTests.ribera, empresas: empresas) { url in
            try FileManager.default.moveItem(at: url, to: papelera.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
        }
        return Entorno(base: base, empresas: empresas, papelera: papelera, model: model, instalador: instalador)
    }

    static let idOriginal = "80456a26-5841-5c15-9279-32593cdf7291"

    static func id(en carpeta: URL) throws -> String? {
        let texto = try String(contentsOf: carpeta.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
        return texto.split(separator: "\n").first { $0.hasPrefix("id:") }.map { $0.dropFirst(3).trimmingCharacters(in: .whitespaces) }
    }

    @Test("Instala el ejemplo con un id nuevo, como ejemplo con escritura, y el resto de bytes iguales")
    func instalar() async throws {
        let e = try entorno()
        defer { e.limpiar() }
        #expect(e.instalador.destino.path.hasPrefix(e.base.path))
        #expect(e.instalador.destino.lastPathComponent == "Asesoría Ribera (ejemplo)")
        let r = try await e.instalador.instalarOAbrir(en: e.model)
        guard case .instalado(let entrada) = r else { Issue.record("Esperaba instalarlo"); return }
        #expect(entrada.clase == .demo)
        #expect(entrada.escritura == .permitida)
        #expect(entrada.nombre == "Asesoría Ribera")
        #expect(e.model.entry(id: entrada.id) != nil)
        let id = try Self.id(en: e.instalador.destino)
        #expect(id == entrada.id.uuidString.lowercased())
        #expect(id != Self.idOriginal)
        // El ejemplo de la app no cambia.
        #expect(try Self.id(en: SesionEscrituraTests.ribera) == Self.idOriginal)
        // Lo demás, idéntico (y `config.yaml` solo cambia en la línea del id).
        let origen = try CarpetaTests.contenido(SesionEscrituraTests.ribera)
        let instalado = try CarpetaTests.contenido(e.instalador.destino)
        #expect(Set(origen.keys) == Set(instalado.keys))
        for (ruta, datos) in origen where ruta != ".tls/config.yaml" { #expect(instalado[ruta] == datos, "\(ruta)") }
        let a = String(decoding: origen[".tls/config.yaml"] ?? Data(), as: UTF8.self).components(separatedBy: "\n")
        let b = String(decoding: instalado[".tls/config.yaml"] ?? Data(), as: UTF8.self).components(separatedBy: "\n")
        #expect(a.count == b.count && zip(a, b).filter { $0 != $1 }.count == 1)
        // No queda ninguna carpeta temporal de la instalación.
        let restos = try FileManager.default.contentsOfDirectory(atPath: e.empresas.path)
        #expect(restos == ["Asesoría Ribera (ejemplo)"])
    }

    @Test("Si ya está, lo abre (también si se quitó de la lista); si el nombre lo ocupa otra cosa, no la toca")
    func yaEstaba() async throws {
        let e = try entorno()
        defer { e.limpiar() }
        let primero = try await e.instalador.instalarOAbrir(en: e.model).entrada
        let segundo = try await e.instalador.instalarOAbrir(en: e.model)
        guard case .yaEstaba(let mismo) = segundo else { Issue.record("Esperaba reutilizarlo"); return }
        #expect(mismo.id == primero.id)
        try e.model.remove(id: primero.id)
        let tercero = try await e.instalador.instalarOAbrir(en: e.model)
        guard case .yaEstaba(let vuelta) = tercero else { Issue.record("Esperaba reutilizarlo"); return }
        #expect(vuelta.id == primero.id)
        #expect(e.model.entries.filter { $0.clase == .demo }.count == 1)

        let otro = try entorno()
        defer { otro.limpiar() }
        try FileManager.default.createDirectory(at: otro.instalador.destino, withIntermediateDirectories: true)
        try Data("mío".utf8).write(to: otro.instalador.destino.appendingPathComponent("nota.md"))
        await #expect(throws: ErrorEjemplo.ocupado("Asesoría Ribera (ejemplo)")) {
            try await otro.instalador.instalarOAbrir(en: otro.model)
        }
        #expect(try String(contentsOf: otro.instalador.destino.appendingPathComponent("nota.md"), encoding: .utf8) == "mío")
    }

    @Test("Reiniciar ejemplo: el de antes va a la Papelera y se instala otro con id nuevo")
    func reiniciar() async throws {
        let e = try entorno()
        defer { e.limpiar() }
        let primero = try await e.instalador.instalarOAbrir(en: e.model).entrada
        try Data("cambio mío".utf8).write(to: e.instalador.destino.appendingPathComponent("Buzón/apunte.md"))
        let nuevo = try await e.instalador.reiniciar(en: e.model)
        #expect(nuevo.id != primero.id)
        #expect(e.model.entry(id: primero.id) == nil)
        #expect(e.model.entry(id: nuevo.id)?.clase == .demo)
        #expect(!FileManager.default.fileExists(atPath: e.instalador.destino.appendingPathComponent("Buzón/apunte.md").path))
        let enPapelera = try FileManager.default.contentsOfDirectory(atPath: e.papelera.path)
        #expect(enPapelera.count == 1)
        let tirada = e.papelera.appendingPathComponent(enPapelera[0])
        #expect(try String(contentsOf: tirada.appendingPathComponent("Buzón/apunte.md"), encoding: .utf8) == "cambio mío")
        #expect(try Self.id(en: e.instalador.destino) == nuevo.id.uuidString.lowercased())
    }

    @Test("Sin el ejemplo dentro de la app, lo dice en llano")
    func sinOrigen() async throws {
        let e = try entorno()
        defer { e.limpiar() }
        let roto = InstaladorEjemplo(origen: e.base.appendingPathComponent("no-esta"), empresas: e.empresas) { _ in }
        await #expect(throws: ErrorEjemplo.sinOrigen) { try await roto.instalarOAbrir(en: e.model) }
        #expect(!FileManager.default.fileExists(atPath: roto.destino.path))
    }
}
