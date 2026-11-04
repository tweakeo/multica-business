import AppKit
import Foundation
import Testing
@testable import TLSAgents
import TLSCore
@testable import TLSUI

/// Escribir la configuración de los asistentes desde la interfaz: el interruptor general, la pausa por área y la
/// ficha de un asistente. Siempre como la persona, por `CommandBus`, con Deshacer; con el gobierno, lo escrito queda
/// confirmado (y al deshacer, también lo que queda).
@Suite("Asistentes · escribir su configuración", .serialized)
@MainActor
struct EscrituraAsistentesTests {
    /// Pulsa «Deshacer» del aviso y espera a que el fichero vuelva.
    func deshacer(_ a: ApoyoAsistentes, hasta datos: Data) async throws {
        let aviso = try #require(a.sesion.aviso)
        aviso.accion?()
        await SesionEscrituraTests().esperar({ a.configDatos == datos })
    }

    @Test("Interruptor: «apagado» como la persona, aviso con Deshacer y, deshecho, los mismos bytes")
    func interruptor() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        // F5 · corrector: con la máquina cargada, la sesión aún puede estar terminando de escribir su configuración al
        // abrir; se espera a que el fichero esté quieto antes de tomar «antes» (si no, «Deshacer» vuelve a una versión
        // posterior y la prueba fallaba de vez en cuando).
        var antes = a.configDatos
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(150))
            let ahora = a.configDatos
            if ahora == antes { break }
            antes = ahora
        }
        let modelo = ModeloInterruptorAsistentes(sesion: a.sesion)
        modelo.cargar()
        #expect(modelo.encendido && modelo.titulo == "Asistentes encendidos")
        await modelo.poner(false)
        #expect(a.config.contains("interruptor: apagado"))
        #expect(!modelo.encendido && modelo.titulo == "Asistentes en pausa")
        #expect(a.sesion.aviso?.texto == "Asistentes en pausa: no harán nada hasta que los enciendas")
        let undo = try #require(await a.sesion.bus?.ultimoDeshacible())
        #expect(undo.autor == .persona("Manu") && undo.descripcion == "Apagar los asistentes")
        try await deshacer(a, hasta: antes)
        #expect(a.configDatos == antes)
    }

    @Test("Con el gobierno: lo que escribe la app queda confirmado y, al deshacerlo, no parece un cambio de fuera")
    func confirmadaAlDeshacer() async throws {
        let a = try await ApoyoAsistentes.abrir(gobierno: true)
        defer { a.cerrar() }
        let g = try #require(a.sesion.bus?.autorizador)
        #expect(!g.estadoDeConfig().cambiadaFuera)  // primera lectura: confirmada
        let antes = a.configDatos
        try await EscrituraAsistentes.ponerInterruptor(false, sesion: a.sesion)
        #expect(!g.estadoDeConfig().cambiadaFuera && !g.estadoDeConfig().efectiva.encendido)
        try await deshacer(a, hasta: antes)
        await SesionEscrituraTests().esperar({ g.estadoDeConfig().efectiva.encendido })
        #expect(!g.estadoDeConfig().cambiadaFuera)
        #expect(g.estadoDeConfig().efectiva.encendido)
    }

    @Test("Pausa por área: `pausa_areas` con el área y vuelta atrás")
    func pausaPorArea() async throws {
        let a = try await ApoyoAsistentes.abrir()
        defer { a.cerrar() }
        try await EscrituraAsistentes.pausar(.ventas, true, actuales: [], sesion: a.sesion)
        #expect(a.config.contains("pausa_areas: [ventas]"))
        try await EscrituraAsistentes.pausar(.ventas, false, actuales: [.ventas], sesion: a.sesion)
        #expect(a.config.contains("pausa_areas: []"))
    }

    @Test("La ficha guarda varios cambios en un solo paso que se deshace; con el gobierno, quedan confirmados")
    func guardarFicha() async throws {
        let a = try await ApoyoAsistentes.abrir(gobierno: true)
        defer { a.cerrar() }
        let g = try #require(a.sesion.bus?.autorizador)
        let antes = a.configDatos
        let cambios: [CambioDeAsistente] = [.rutinaHora("cobros-pendientes", hora: 10, minuto: 0), .modo("FIN-05", .supervisado),
                                            .maxTareas(6)]
        try await EscrituraAsistentes.guardar(cambios, slug: "contable", nombre: "Contable", perfil: .contable, sesion: a.sesion)
        let texto = a.config
        #expect(texto.contains("dia_mes: 5, hora: \"10:00\""))
        #expect(a.sesion.aviso?.texto == "Guardé los ajustes de Contable")
        let e = g.estadoDeConfig()
        #expect(!e.cambiadaFuera && e.efectiva.modo("FIN-05") == .supervisado && e.efectiva.asistente("contable")?.maxTareasPorEjecucion == 6)
        let undo = try #require(await a.sesion.bus?.ultimoDeshacible())
        #expect(undo.descripcion == "Ajustes de Contable (asistente)" && undo.autor == .persona("Manu"))
        try await deshacer(a, hasta: antes)
        await SesionEscrituraTests().esperar({ g.estadoDeConfig().efectiva.modo("FIN-05") == nil })
        #expect(!g.estadoDeConfig().cambiadaFuera)
    }

    @Test("Con permisos cambiados fuera de la app sin confirmar, la ficha no escribe y lo dice")
    func cambiosDeFuera() async throws {
        let a = try await ApoyoAsistentes.abrir(gobierno: true)
        defer { a.cerrar() }
        let g = try #require(a.sesion.bus?.autorizador)
        _ = g.estadoDeConfig()
        try a.cambiarConfig("  marca:\n    activo: false", "  marca:\n    activo: true")
        #expect(g.estadoDeConfig().cambiadaFuera)
        let antes = a.configDatos
        await #expect(throws: ErrorDeGobierno.self) {
            try await EscrituraAsistentes.guardar([.maxTareas(3)], slug: "contable", nombre: "Contable", perfil: .contable, sesion: a.sesion)
        }
        #expect(a.configDatos == antes)
        let l = try await a.leer()
        #expect(l.cambiosDeFuera == "Cambiaron los permisos de Marca fuera de la app: confirmar")
        // Lo que restringe vale ya; lo que amplía, no: Marca sigue apagado.
        #expect(l.asistente("marca")?.activo == false)
    }

    @Test("En solo lectura no se escribe nada")
    func soloLectura() async throws {
        let a = try await ApoyoAsistentes.abrir(escritura: .bloqueada)
        defer { a.cerrar() }
        let antes = a.configDatos
        let modelo = ModeloInterruptorAsistentes(sesion: a.sesion)
        modelo.cargar()
        #expect(modelo.motivoNoSePuede?.hasPrefix("Solo lectura") == true)
        await modelo.poner(false)
        await #expect(throws: (any Error).self) {
            try await EscrituraAsistentes.guardar([.maxTareas(3)], slug: "contable", nombre: "Contable", perfil: .contable, sesion: a.sesion)
        }
        #expect(a.configDatos == antes)
    }
}
