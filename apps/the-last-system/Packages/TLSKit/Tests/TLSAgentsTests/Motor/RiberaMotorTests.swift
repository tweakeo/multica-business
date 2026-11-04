import Foundation
import Testing
import TLSCore
@testable import TLSAgents

/// Ribera (copia temporal) con el motor entero en simulación: reloj de la demo, grabaciones del paquete, cierre por
/// `CommandBus` con el Autorizador y marca «Simulado». Nunca se lanza Claude.
@Suite("Motor · Ribera simulada", .serialized)
struct RiberaMotorTests {
    @Test("Un lunes de Ribera: «¿Algo rojo?» y el resumen semanal de Mika, simulados y apuntados en la Bitácora")
    func lunesSimulado() async throws {
        let origen = Apoyo.repo.appendingPathComponent("App/Recursos/Ejemplos/Asesoria-Ribera")
        guard FileManager.default.fileExists(atPath: origen.path), let grabaciones = GrabacionesDeEjemplo.carpeta else { return }
        let base = Apoyo.tempDir("tls-ribera-motor")
        defer { Apoyo.limpiar(base) }
        let raiz = base.appendingPathComponent("Asesoría Ribera (ejemplo)")
        try FileManager.default.copyItem(at: origen, to: raiz)
        let estadoDir = base.appendingPathComponent("estado")
        let entry = VaultEntry(nombre: "Asesoría Ribera (ejemplo)", ruta: raiz.path, bookmark: nil, clase: .demo, escritura: .permitida)
        let writer = try await VaultWriter.open(entry: entry, root: raiz, options: VaultWriter.Options(
            stateDirectory: estadoDir, appSupport: base.appendingPathComponent("asup"), app: "The Last System pruebas"))
        let zona = TimeZone(identifier: "Europe/Madrid")!
        let reloj = RelojManual(DisparosTests.fecha(19, 8, 50))
        let autorizador = try Autorizador(writer: writer, opciones: .init(ahora: { reloj.ahora() }))
        let bus = CommandBus(writer: writer, autorizador: autorizador)
        let foto: @Sendable () async -> VaultSnapshot = { VaultSnapshot.read(root: raiz) }
        let puerta = PuertaFalsa()
        let host = try AgentHost(.init(
            raiz: raiz, estadoDeCarpeta: estadoDir, runtime: SimulatedRuntime(grabaciones: grabaciones, servidor: puerta),
            puerta: puerta, registro: ActivityWriter(bus: bus, foto: foto, zona: zona),
            ajustes: AjustesDeGobierno(autorizador: autorizador), catalogo: CatalogoAsistentesTLS.soloPerfiles, reloj: reloj,
            foto: foto, empresa: "Asesoría Ribera", intervalo: 3600, leerEventos: false,
            permisoDeLanzamiento: { autorizador.permisoDeLanzamiento($0) }))
        let nuevas = await host.revisar()
        #expect(Set(nuevas.compactMap(\.disparo.rutina)) == ["algo-rojo", "resumen-semana"])
        await host.cola.procesar()
        let hechas = try host.estado.ejecuciones()
        #expect(hechas.count == 2)
        for e in hechas {
            #expect(e.estado == .completada, "\(e.disparo.clave): \(e.estado) \(e.nota ?? "")")
            #expect(e.simulado)
        }
        let bitacora = (try? String(contentsOf: VaultPath("6 · Equipo/Bitácora/2026-10.md").url(in: raiz), encoding: .utf8)) ?? ""
        let deHoy = bitacora.components(separatedBy: "\n").filter { $0.hasPrefix("- 2026-10-19 ") && $0.contains("agente:mika") }
        #expect(deHoy.count == 2)
        #expect(deHoy.allSatisfy { $0.contains("Simulado: ") })
        // El uso simulado no gasta el tope del mes.
        let uso = await host.uso("mika")
        #expect(uso?.hasPrefix("uso del mes: ") == true && uso?.hasSuffix("% de tu tope (Simulado)") == true)
        #expect(CostLedger(estado: host.estado, reloj: reloj, zona: zona).usado(agente: "mika") == 0)
        await writer.close()
    }
}
