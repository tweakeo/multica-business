import Foundation
import Testing
@testable import TLSCore

/// `VaultService` con su `VaultWriter` conectado: lo escrito se reindexa al momento y no llega
/// como cambio de fuera; lo que cambia fuera, sí.
@Suite(.serialized) struct EscrituraServicioTests {
    @Test func loEscritoSeReindexaYNoEsDeFuera() async throws {
        let env = EntornoEscritura()
        defer { env.limpiar() }
        let svc = try VaultService(entry: env.entry, root: env.root,
                                   options: .init(privado: [VaultPath("Privado")], stateDirectory: env.state, vigilar: true))
        let externos = Caja<[VaultPath]>([])
        svc.onExternalChange = { paths in externos.update { $0 += paths } }
        _ = try await svc.open { _ in }
        try await Task.sleep(nanoseconds: 300_000_000)

        let writer = try await env.writer()
        let escritas = Caja<[VaultPath]>([])
        #expect(await svc.conectar(writer) { paths in escritas.update { $0 += paths } })
        let bus = CommandBus(writer: writer)

        // Nota nueva: en el índice en cuanto llega el aviso, sin esperar a la vigilancia.
        let nueva = VaultPath("2 · Ventas/Contactos/Nora Pomelo.md")
        let r = try await bus.ejecutar(.crear(nueva, texto: "# Nora Pomelo\n\nConoce a [[Lucía Prueba]] y vende pomelos.\n"),
                                       autor: .persona("Prueba"))
        #expect(r.hecho)
        #expect(await Apoyo.esperar(3) { escritas.value.contains(nueva) })
        #expect(svc.search("pomelos").first?.note.path == nueva)
        #expect(svc.backlinks(to: VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")).contains { $0.path == nueva })

        // Renombrar con enlaces: el índice sigue a la nota y los enlaces siguen resolviendo.
        let previa = try LinkRefactor(root: env.root, excluidas: [VaultPath("Privado")])
            .renombrar(VaultPath("2 · Ventas/Contactos/Lucía Prueba.md"), a: "Lucía Prueba Sanz")
        #expect(previa.esSeguro)
        #expect(previa.enlaces > 0)
        escritas.value = []
        let rr = try await LinkRefactor.aplicar(previa, con: bus)
        #expect(rr.hecho)
        let renombrada = VaultPath("2 · Ventas/Contactos/Lucía Prueba Sanz.md")
        #expect(await Apoyo.esperar(3) { escritas.value.contains(renombrada) })
        #expect(svc.summary(of: VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")) == nil)
        #expect(svc.summary(of: renombrada) != nil)
        #expect(svc.backlinks(to: renombrada).contains { $0.path == nueva })

        // La vigilancia ve esas escrituras, pero no las avisa como cambios de fuera.
        try await Task.sleep(nanoseconds: 2_800_000_000)
        let propias: Set<VaultPath> = [nueva, renombrada, VaultPath("2 · Ventas/Contactos/Lucía Prueba.md")]
        #expect(externos.value.filter { propias.contains($0) }.isEmpty, "\(externos.value)")

        // Un cambio de fuera sí llega.
        try "# Rumbo\n\nEditado fuera con la palabra mandarina.\n"
            .write(to: env.url("1 · Dirección/Rumbo.md"), atomically: true, encoding: .utf8)
        #expect(await Apoyo.esperar(6) { externos.value.contains(VaultPath("1 · Dirección/Rumbo.md")) })

        // Desconectado, lo que escribe la app vuelve a contar como de fuera (no hay a quién atribuirlo).
        await svc.desconectar(writer)
        #expect(svc.escriturasPropias == nil)
        await writer.close()
        svc.close()
    }

    @Test func noConectaElEscritorDeOtraCarpeta() async throws {
        let env = EntornoEscritura()
        let otra = EntornoEscritura()
        defer { env.limpiar(); otra.limpiar() }
        let svc = try VaultService(entry: env.entry, root: env.root,
                                   options: .init(stateDirectory: env.state, vigilar: false))
        let writer = try await otra.writer()
        #expect(await svc.conectar(writer) == false)
        #expect(svc.escriturasPropias == nil)
        await writer.close()
        svc.close()
    }
}
