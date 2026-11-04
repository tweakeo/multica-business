import Foundation
import Testing
import TLSCore
@testable import TLSUI

/// Equipo › Operación (F2 · rol areas-b): los roles de Ribera sin ocupante, los asistentes vacíos y explicados hasta F4
/// («Sin dato», nunca 0), la rejilla de rutinas ✓ ✕ – desde los registros de `Rutinas/` (también una rutina con ficha que
/// se cae dos semanas seguidas), el uso del mes frente al tope con bitácora y lo privado fuera.
@Suite("Equipo · roles, asistentes y rejilla de rutinas", .serialized)
@MainActor
struct EquipoOperacionTests {
    let apoyo = ApoyoAreasB()

    @Test("Ribera: 6 roles de personas sin ocupante, los de sus asistentes (F4) con su bitácora, y dos rutinas con su rejilla")
    func riberaSeLee() async throws {
        let (e, sesion) = try await apoyo.abrir()
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloEquipo(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        // Desde F4, Ribera trae la ficha de rol de cada uno de sus 8 asistentes (`asistente-<slug>.md`, ocupada por él).
        #expect(l.roles.count == 14)
        #expect(l.roles.filter { !$0.esAsistente }.allSatisfy { $0.ocupante == nil })
        #expect(l.personas.count == 5)
        #expect(l.rolesDeAsistente.map(\.nombre).sorted() == ["Cartero", "Comercial", "Contable", "Equipo", "Implementador", "Marca",
                                                              "Mika", "Ordenador", "Responsable de Marca"])
        #expect(l.roles.first { $0.nombre == "Comercial" && $0.esAsistente }?.ocupante == "Comercial (asistente)")
        // Primero las personas, luego los roles de asistente.
        #expect(l.roles.last?.esAsistente == true)
        let fin = try #require(l.roles.first { $0.nombre == "Financiero" })
        #expect(fin.areas == [.finanzas] && fin.numeros == ["FIN-RUNWAY", "FIN-AR"])
        #expect(fin.mision == "Caja predecible, cobros a tiempo y trimestre preparado sin sustos.")
        // Asistentes (F4): los 8 de su configuración, 5 activos, y la Bitácora de octubre (simulada).
        #expect(l.asistentes.count == 8 && l.asistentes.filter(\.activo).count == 5 && l.hayBitacora)
        #expect(l.usoMesUSD.map { abs($0 - 0.38) < 0.001 } == true)
        // Rejilla: seis semanas, la última la de hoy (lunes 19).
        #expect(l.semanas.count == 6 && l.semanas.last?.description == "2026-10-19" && l.semanas.first?.description == "2026-09-14")
        #expect(l.rutinas.map(\.nombre).sorted() == ["Rutina diaria", "Rutina semanal"])
        let semanal = try #require(l.rutinas.first { $0.nombre == "Rutina semanal" })
        #expect(semanal.cadencia == .semanal)
        #expect(semanal.celdas.map(\.marca) == [.noToca, .noToca, .noToca, .noToca, .hecha, .pendiente])
        #expect(semanal.celdas[4].detalle == "Hecha el 12 oct")
        let diaria = try #require(l.rutinas.first { $0.nombre == "Rutina diaria" })
        #expect(diaria.cadencia == .diaria)
        #expect(diaria.celdas[4].marca == .hecha && diaria.celdas[4].detalle == "1 de 1 día" && diaria.celdas[4].fraccion == "1/1")
        #expect(diaria.celdas[5].marca == .pendiente)
        #expect(l.rutinasCaidas.isEmpty)
    }

    @Test("Una rutina con ficha que no se hace dos semanas seguidas sale con ✕ y con aviso")
    func rutinaQueSeCae() async throws {
        let ficha = """
        ---
        tls_type: routine
        tls_schema: 1
        id: 0f0f0f0f-0000-4000-8000-000000000001
        nombre: Cierre de semana
        area: direccion
        cadencia: semanal
        dia: viernes
        creada: 2026-09-01
        activa: true
        ---
        # Cierre de semana
        """
        let log = "---\ntls_type: routine_log\nrutina: \"[[cierre-de-semana|Cierre de semana]]\"\ntipo: cierre_semana\nfecha: 2026-09-18\n---\n# Cierre\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [
            "1 · Dirección/Rutinas/cierre-de-semana.md": ficha,
            "1 · Dirección/Rutinas/cierre-de-semana/2026-09-18.md": log,
        ])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloEquipo(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        let r = try #require(l.rutinas.first { $0.nombre == "Cierre de semana" })
        #expect(r.ficha?.raw == "1 · Dirección/Rutinas/cierre-de-semana.md")
        #expect(r.registros.map(\.description) == ["2026-09-18"])
        // 14 sep: hecha (18); del 21 sep al 12 oct, no se hizo; esta semana, aún a tiempo (toca el viernes).
        #expect(r.celdas.map(\.marca) == [.hecha, .noHecha, .noHecha, .noHecha, .noHecha, .pendiente])
        #expect(l.rutinasCaidas.map(\.nombre) == ["Cierre de semana"])
    }

    @Test("Con bitácora y tope en la configuración, el uso del mes es su porcentaje del tope")
    func usoFrenteAlTope() async throws {
        // Ribera ya trae asistentes desde F4: se queda con lo de antes de ellos y se le ponen estos dos.
        let ribera = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
        let config = (ribera.components(separatedBy: "\n# Asistentes:").first ?? ribera)
            + "agentes:\n  mika:\n    activo: true\n    presupuesto_mes_usd: 10\n  comercial:\n    activo: false\n    presupuesto_mes_usd: 5\n"
        let bitacora = "# Bitácora de octubre\n\n- 2026-10-15 09:00 · mika · DIR-02 · revisé la semana · uso 1,50 USD\n"
            + "- 2026-10-16 09:00 · mika · VEN-08 · preparé un seguimiento · uso 2,00 USD\n"
            + "- 2026-09-30 09:00 · mika · DIR-02 · revisé el mes · uso 9,00 USD\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [".tls/config.yaml": config, "6 · Equipo/Bitácora/2026-10.md": bitacora])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloEquipo(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(l.asistentes.map(\.slug) == ["mika", "comercial"])
        #expect(l.topeMesUSD == 10)
        #expect(l.hayBitacora && l.usoMesUSD == 3.5)
        #expect(l.textoUso == "35 % de tu tope")
        #expect(l.bitacora.first?.fecha.description == "2026-10-16")
        #expect(l.bitacora.count == 3)
    }

    @Test("Lo privado no aparece: ni roles ni registros de rutinas de una carpeta privada")
    func privado() async throws {
        let privada = "6 · Equipo/Expediente privado"
        let config = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent(".tls/config.yaml"), encoding: .utf8)
            .replacingOccurrences(of: "privado: []", with: "privado:\n  - \"\(privada)\"")
        let rol = "---\ntls_type: role\nnombre: Rol reservado\nclase: humano\nareas: [equipo]\nocupante: Alguien\n---\n# Rol reservado\n"
        let log = "---\ntls_type: routine_log\ntipo: semana\nfecha: 2026-10-05\n---\n# Semana\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [".tls/config.yaml": config, privada + "/rol.md": rol,
                                                           privada + "/semana/2026-10-05.md": log])
        defer { sesion.close(); e.limpiar() }
        let modelo = ModeloEquipo(sesion: sesion)
        await modelo.cargar()
        let l = try #require(modelo.lectura)
        #expect(l.roles.count == 14 && !l.roles.contains { $0.nombre == "Rol reservado" })
        #expect(l.rutinas.count == 2)
        #expect(l.rutinas.allSatisfy { !$0.registros.contains { $0.description == "2026-10-05" } })
    }
}
