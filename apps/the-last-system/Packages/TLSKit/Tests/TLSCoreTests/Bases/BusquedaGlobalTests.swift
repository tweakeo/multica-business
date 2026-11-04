import Foundation
import Testing
@testable import TLSCore

@Suite("⌘K · buscar en todas las bases", .serialized)
struct BusquedaGlobalTests {
    @Test("Encuentra por número, por nombre, por otro nombre y por propiedades; nunca lo privado")
    func ribera() async throws {
        let e = try EntornoBases { root in
            let privada = VaultPath("4 · Finanzas/Trámites/Expediente privado/documento.md").url(in: root)
            try FileManager.default.createDirectory(at: privada.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("---\ntls_type: contact\nnombre: Doctora Privada\naliases: [Dra. Secreta]\n---\n# Doctora Privada\n".utf8).write(to: privada)
            let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md").url(in: root)
            var t = try String(contentsOf: jorge, encoding: .utf8)
            t = t.replacingOccurrences(of: "nombre: Jorge Martín\n", with: "nombre: Jorge Martín\naliases: [El del taller]\n")
            try Data(t.utf8).write(to: jorge)
        }
        defer { e.limpiar() }
        let s = try await e.servicio(privado: [VaultPath("4 · Finanzas/Trámites")])
        defer { s.close() }
        let catalogo = CatalogoBusqueda.construir(s.todasLasFichas())

        let porNumero = catalogo.buscar("T-0001")
        #expect(porNumero.first?.entrada.codigos == ["T-0001"])
        #expect(porNumero.first?.lugar == .codigo)
        #expect(catalogo.buscar("t0001").first?.entrada.codigos == ["T-0001"])
        #expect(catalogo.buscar("F-2026-0007").first?.entrada.base == "facturas")

        let porNombre = catalogo.buscar("talleres")
        #expect(porNombre.first?.entrada.titulo == "Talleres Martín e Hijos SL")
        #expect(porNombre.first?.entrada.base == "empresas")
        #expect(catalogo.buscar("martin").contains { $0.entrada.titulo == "Jorge Martín" })

        let alias = catalogo.buscar("del taller")
        #expect(alias.first?.entrada.titulo == "Jorge Martín")
        #expect(alias.first?.lugar == .otroNombre)
        #expect(alias.first?.coincidencia == "El del taller")

        // Por una propiedad de texto: el canal o el sector.
        #expect(catalogo.buscar("arquitectura").contains { $0.entrada.titulo == "Arquitectura Nexo SLP" })

        // Lo privado no sale ni por nombre ni por otro nombre.
        #expect(catalogo.buscar("doctora").isEmpty)
        #expect(catalogo.buscar("secreta").isEmpty)
        #expect(!catalogo.entradas.contains { $0.titulo == "Doctora Privada" })
    }

    @Test("Con 5.000 fichas, por número, por otro nombre y por texto en menos de 100 ms (criterio §11.7)")
    func rendimiento() async throws {
        let e = try EntornoBases { root in
            let dir = root.appendingPathComponent("1 · Dirección/Tareas", isDirectory: true)
            let contactos = root.appendingPathComponent("2 · Ventas/Contactos/Sinteticos", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: contactos, withIntermediateDirectories: true)
            let palabras = ["presupuesto", "trimestre", "nómina", "alquiler", "proveedor", "gestoría", "cliente", "factura",
                            "reunión", "contrato", "renta", "modelo", "cobro", "banco", "recibo", "seguro"]
            for i in 1...2500 {
                let n = String(format: "%04d", i + 100)
                let w = palabras[i % palabras.count], w2 = palabras[(i * 7) % palabras.count]
                let texto = """
                ---
                tls_type: task
                numero: T-\(n)
                titulo: Revisar \(w) \(i)
                estado: Por hacer
                area: direccion
                ---
                # Revisar \(w) \(i)
                Hay que mirar el \(w2) de este mes con calma.\(i == 1777 ? " Ojo con la zarzamora del patio." : "")
                """
                try Data(texto.utf8).write(to: dir.appendingPathComponent("t-\(n)-revisar-\(w)-\(i).md"))
            }
            for i in 1...2500 {
                let texto = """
                ---
                tls_type: contact
                nombre: Persona \(i) Sintética
                aliases: [\(i == 2424 ? "Pepe Gotera" : "Contacto \(i)")]
                estado: Interesado
                canal: \(palabras[i % palabras.count])
                ---
                # Persona \(i) Sintética
                """
                try Data(texto.utf8).write(to: contactos.appendingPathComponent("persona-\(i).md"))
            }
        }
        defer { e.limpiar() }
        let s = try await e.servicio()
        defer { s.close() }
        let reloj = ContinuousClock()
        var catalogo = CatalogoBusqueda.vacio
        let construir = reloj.measure { catalogo = CatalogoBusqueda.construir(s.todasLasFichas()) }
        #expect(catalogo.entradas.count >= 5000)
        // Construirlo se hace una vez por cambio y en segundo plano; aun así, rápido.
        #expect(construir < .seconds(2), "Construir el catálogo: \(construir)")

        // El criterio se comprueba con el tiempo de CPU del hilo que busca (como la latencia del editor): con las 144
        // suites del paquete a la vez, el reloj de pared mide sobre todo la espera a la CPU. El reloj de pared se mira
        // aparte, con margen, para que una búsqueda lenta de verdad no pase.
        var paredes: [String: Duration] = [:]
        func medir(_ consulta: String, _ comprobar: () -> Bool) -> Duration {
            var mejor = Duration.seconds(10), mejorPared = Duration.seconds(10)
            for _ in 0..<5 {
                let c0 = Self.cpuHiloMs()
                let pared = reloj.measure { _ = comprobar() }
                mejor = min(mejor, .microseconds(Int((Self.cpuHiloMs() - c0) * 1000)))
                mejorPared = min(mejorPared, pared)
            }
            paredes[consulta] = mejorPared
            return mejor
        }
        let numero = medir("T-1877") { catalogo.buscar("T-1877").first?.entrada.codigos == ["T-1877"] }
        #expect(catalogo.buscar("T-1877").first?.entrada.codigos == ["T-1877"])
        let alias = medir("gotera") { catalogo.buscar("gotera").first?.entrada.titulo == "Persona 2424 Sintética" }
        #expect(catalogo.buscar("gotera").first?.entrada.titulo == "Persona 2424 Sintética")
        let texto = medir("zarzamora") { s.search("zarzamora", limit: 8).count == 1 }
        #expect(s.search("zarzamora", limit: 8).first?.note.title == "Revisar \(["presupuesto", "trimestre", "nómina", "alquiler", "proveedor", "gestoría", "cliente", "factura", "reunión", "contrato", "renta", "modelo", "cobro", "banco", "recibo", "seguro"][1777 % 16]) 1777")
        let nombre = medir("persona 3") { !catalogo.buscar("persona 3").isEmpty }
        #expect(numero < .milliseconds(100), "Por número: \(numero)")
        #expect(alias < .milliseconds(100), "Por otro nombre: \(alias)")
        #expect(texto < .milliseconds(100), "Por texto: \(texto)")
        #expect(nombre < .milliseconds(100), "Por nombre: \(nombre)")
        for (consulta, pared) in paredes { #expect(pared < .milliseconds(400), "«\(consulta)» en reloj de pared: \(pared)") }
        print("⌘K con \(catalogo.entradas.count) fichas · construir \(construir) · CPU: número \(numero) · otro nombre \(alias) · texto \(texto) · nombre \(nombre) · pared: \(paredes)")
    }

    /// Tiempo de CPU del hilo actual, en milisegundos.
    static func cpuHiloMs() -> Double {
        var t = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
        return Double(t.tv_sec) * 1000 + Double(t.tv_nsec) / 1_000_000
    }
}
