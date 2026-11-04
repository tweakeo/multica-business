import Foundation
import Testing
import TLSCore
import TLSImport
@testable import TLSUI

/// La hoja «Importar tareas de Multica» con un Multica falso en memoria: nada se escribe hasta «Importar», va en un
/// solo plan (un solo Deshacer) y con las reglas del dominio apagadas.
@Suite("Importar de Multica · hoja", .serialized)
@MainActor
struct MulticaHojaTests {
    let pruebas = SesionEscrituraTests()

    @Test("Sin el programa de Multica, la hoja lo dice y no hace nada")
    func sinPrograma() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        struct Roto: EjecutorMultica {
            func ejecutar(_ orden: OrdenMultica) async throws -> Data { throw ErrorMultica.fallo(codigo: 1, detalle: "x") }
        }
        let m = ModeloImportarMultica(sesion: sesion, ejecutor: Roto())
        await m.arrancar()
        #expect(m.fase == .elegir)
        #expect(m.espacios.isEmpty)
        #expect(m.error != nil)
    }

    @Test("Vista previa → Importar: crea las fichas marcadas, avisa y se deshace de una vez")
    func importar() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let m = ModeloImportarMultica(sesion: sesion, ejecutor: CapturasTutorialTests.MulticaEnMemoria())
        await m.arrancar()
        #expect(m.perfil == "default")
        #expect(m.espacio == "0f6c1a2e-1111-4222-8333-944455556666")
        let antes = try FileManager.default.contentsOfDirectory(atPath: e.carpeta.appendingPathComponent("2 · Ventas").path)
        await m.leer()
        #expect(m.fase == .previa)
        let previa = try #require(m.previa)
        #expect(previa.candidatas.count == 5)
        #expect(previa.marcadas.count == 4, "la de salud sale desmarcada")
        // Leer no escribe nada.
        #expect(try FileManager.default.contentsOfDirectory(atPath: e.carpeta.appendingPathComponent("2 · Ventas").path) == antes)
        // Cambiar el área de una antes de importar.
        m.previa?.cambiarArea("MANU-6", .equipo)
        guard case .success(let plan)? = m.plan else { Issue.record("Debía poder importarse"); return }
        #expect(plan.fichas.count == 4)

        let um = UndoManager()
        um.groupsByEvent = false
        um.beginUndoGrouping()
        await m.aplicar(deshacer: um)
        um.endUndoGrouping()
        guard case .hecho(let resumen) = m.fase else { Issue.record("No terminó: \(m.fase) \(m.error ?? "")"); return }
        #expect(resumen.hasPrefix("Crear 4 fichas de tarea"))
        #expect(sesion.aviso?.texto == "Importé 4 tareas de Multica")
        for f in plan.fichas {
            #expect(FileManager.default.fileExists(atPath: f.ruta.url(in: e.carpeta).path))
        }
        #expect(plan.fichas.first { $0.identificador == "MANU-6" }?.ruta.raw.hasPrefix("6 · Equipo/Tareas/") == true)
        // Ninguna regla escribió nada más (modo importación): solo las fichas y el contador.
        if let motor = DominioEmpresa.motor(de: sesion) {
            #expect(try motor.estado.eventos().isEmpty)
        }
        // Deshacer las quita de una vez (al Archivo: nunca se borra).
        #expect(um.canUndo)
        um.undo()
        await pruebas.esperar { !FileManager.default.fileExists(atPath: plan.fichas[0].ruta.url(in: e.carpeta).path) }
        for f in plan.fichas {
            #expect(!FileManager.default.fileExists(atPath: f.ruta.url(in: e.carpeta).path))
        }
    }
}
