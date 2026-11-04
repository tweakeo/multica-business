import Foundation
import Testing
@testable import TLSCore

/// Vistas guardadas de las bases en `.tls/vistas/<base>.json` (Mosaico v2 §4.6, pregunta 7): solo personas,
/// un nivel y en JSON; Deshacer las lleva al Archivo con un nombre visible (nunca se borra).
@Suite("Escritura · vistas guardadas en la carpeta")
struct EscrituraVistasTests {
    static let manu = Autor.persona("Manu")

    @Test("Una persona guarda .tls/vistas/<base>.json; otras rutas ocultas y los asistentes, no")
    func soloVistasYSoloPersonas() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let ruta = VaultPath(".tls/vistas/oportunidades.json")
        #expect(PlanCompiler.esVistaGuardada(ruta))
        #expect(!PlanCompiler.esVistaGuardada(VaultPath(".tls/vistas/a/b.json")))
        #expect(!PlanCompiler.esVistaGuardada(VaultPath(".tls/vistas/.oculta.json")))
        #expect(!PlanCompiler.esVistaGuardada(VaultPath(".tls/vistas/notas.yaml")))
        #expect(try await bus.ejecutar(.crear(ruta, texto: "{\"version\":1,\"vistas\":[]}\n"), autor: Self.manu).hecho)
        #expect(e.texto(ruta.raw) == "{\"version\":1,\"vistas\":[]}\n")
        await esperaErrorAsync(.rutaNoPermitida(".tls/vistas/a/b.json")) {
            try await bus.ejecutar(.crear(VaultPath(".tls/vistas/a/b.json"), texto: "{}"), autor: Self.manu)
        }
        await esperaErrorAsync(.rutaNoPermitida(".tls/vistas/x.json")) {
            try await bus.ejecutar(.crear(VaultPath(".tls/vistas/x.json"), texto: "{}"), autor: .agente("ordenador"))
        }
        // Un JSON que no se lee no se guarda.
        await esperaErrorAsync(.contenidoIlegible(".tls/vistas/rota.json")) {
            try await bus.ejecutar(.crear(VaultPath(".tls/vistas/rota.json"), texto: "{ sin cerrar"), autor: Self.manu)
        }
    }

    @Test("Deshacer la primera vista la retira a «Archivo/Ajustes de la app/vistas/» y deja la carpeta como estaba")
    func deshacerAlArchivo() async throws {
        let e = EntornoEscritura()
        defer { e.limpiar() }
        let bus = try await e.bus()
        let ruta = VaultPath(".tls/vistas/contactos.json")
        let texto = "{\"version\":1,\"vistas\":[]}\n"
        #expect(try await bus.ejecutar(.crear(ruta, texto: texto), autor: Self.manu).hecho)
        #expect(try await bus.deshacer(autor: Self.manu).hecho)
        #expect(!e.existe(ruta.raw))
        #expect(e.texto("Archivo/Ajustes de la app/vistas/contactos.json") == texto)
        #expect(VaultWriter.componentesVisibles(VaultPath(".obsidian/app.json")) == ["Ajustes de Obsidian", "app.json"])
    }
}
