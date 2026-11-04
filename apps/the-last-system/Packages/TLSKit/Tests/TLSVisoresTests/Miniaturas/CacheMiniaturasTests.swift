import Foundation
import Testing
@testable import TLSVisores

/// R1 en F2: miniatura de la primera página de los PDF para la Galería, con caché en el estado de la carpeta
/// (fuera de ella), sin descargar nunca de iCloud.
@Suite("Caché de miniaturas (R1, F2)", .serialized)
struct CacheMiniaturasTests {
    /// Acceso falso: todo «solo en iCloud».
    struct TodoEnICloud: AccesoICloud {
        func estado(de url: URL) -> EstadoICloud { .soloEnICloud(tamano: 1_000) }
        func pedirDescarga(de url: URL) throws { Issue.record("No debe pedir ninguna descarga") }
    }

    @Test("No acepta una caché dentro de la carpeta de la empresa ni en iCloud Drive")
    func fueraDeLaCarpeta() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let empresa = f.carpeta.appendingPathComponent("Empresa", isDirectory: true)
        try FileManager.default.createDirectory(at: empresa, withIntermediateDirectories: true)
        #expect(CacheMiniaturas(directorio: empresa.appendingPathComponent("miniaturas"), carpetaEmpresa: empresa) == nil)
        #expect(CacheMiniaturas(directorio: empresa, carpetaEmpresa: empresa) == nil)
        let icloud = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/x")
        #expect(CacheMiniaturas(directorio: icloud, carpetaEmpresa: empresa) == nil)
        #expect(CacheMiniaturas(directorio: f.carpeta.appendingPathComponent("estado/miniaturas"), carpetaEmpresa: empresa) != nil)
    }

    @Test("Pinta la primera página una vez, la guarda en la caché y otra caché la lee del disco")
    func guardaYLee() async throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let pdf = try f.pdf("factura.pdf", paginas: [["Factura F-2026-0007", "Total 290,40 €"], ["Página 2"]])
        let dir = f.carpeta.appendingPathComponent("estado/miniaturas", isDirectory: true)
        let cache = try #require(CacheMiniaturas(directorio: dir, carpetaEmpresa: f.carpeta.appendingPathComponent("Empresa")))
        let a = try #require(await cache.miniatura(url: pdf, lado: 200))
        #expect(max(a.tamano.width, a.tamano.height) == 200)
        let clave = try #require(CacheMiniaturas.clave(url: pdf, pagina: 1, lado: 200))
        #expect(FileManager.default.fileExists(atPath: cache.ruta(de: clave).path))
        // Otra caché sobre el mismo directorio (otra pestaña, o tras reabrir la app): la lee del disco.
        let otra = try #require(CacheMiniaturas(directorio: dir, carpetaEmpresa: nil))
        let b = try #require(await otra.miniatura(url: pdf, lado: 200))
        #expect(b.tamano == a.tamano)
        // Si el fichero cambia, la clave también (no se enseña la miniatura vieja).
        try f.pdf("factura.pdf", paginas: [["Otra factura distinta, más larga", "Total 1.000,00 €", "Vence el 30"]])
        #expect(CacheMiniaturas.clave(url: pdf, pagina: 1, lado: 200) != clave)
    }

    @Test("Lo que está solo en iCloud no se pinta, no se guarda y no se descarga")
    func soloEnICloud() async throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let pdf = try f.pdf("en-icloud.pdf", paginas: [["Hola"]])
        let dir = f.carpeta.appendingPathComponent("estado/miniaturas", isDirectory: true)
        let cache = try #require(CacheMiniaturas(directorio: dir, carpetaEmpresa: nil))
        #expect(await cache.miniatura(url: pdf, lado: 120, acceso: TodoEnICloud()) == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("Podar deja como mucho el máximo, quitando las que hace más que no se usan")
    func podar() throws {
        let f = try FicherosDePrueba()
        defer { f.limpiar() }
        let dir = f.carpeta.appendingPathComponent("miniaturas", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("ab"), withIntermediateDirectories: true)
        for i in 0..<6 {
            let u = dir.appendingPathComponent("ab/\(i).png")
            try Data([0]).write(to: u)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1_000 * i))], ofItemAtPath: u.path)
        }
        CacheMiniaturas.podar(dir, maximo: 4)
        let quedan = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("ab").path).sorted()
        #expect(quedan == ["2.png", "3.png", "4.png", "5.png"])
    }
}
