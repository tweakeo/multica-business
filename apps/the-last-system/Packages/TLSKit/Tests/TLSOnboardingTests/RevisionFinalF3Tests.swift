import Foundation
import Testing
import TLSCore
import TLSImport
import TLSUI
@testable import TLSOnboarding

/// Corrector final de F3: lo que arregló de la revisión de experiencia en las pantallas de la puesta en marcha. Todo en
/// temporales propios; nunca se lanza Claude.
@Suite("Revisión final F3 · pantallas", .serialized)
@MainActor
struct RevisionFinalF3PantallasTests {
    @Test("P1 · En «Completar las fichas» el botón del pie es «Aplicar» (no «Siguiente» sin aplicar) y aplica de verdad")
    func aplicarEnElPie() async throws {
        let e = try PasoOrdenarTests.entorno(copiaDe: PasoOrdenarTests.fixtureG3, exclusiones: ["Privado"])
        defer { e.limpiar() }
        let ordenar = try #require(ConexionOrdenar.modelo(para: e.puesta, app: nil))
        ordenar.ocr = nil
        await ordenar.arrancar()
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        #expect(ConexionOrdenar.pantalla(para: e.puesta, ordenar: ordenar) == .completarFichas)
        // Sin vista previa todavía: «Aplicar», desactivado con su motivo (no «Siguiente»).
        #expect(e.puesta.accionPrincipal == .aplicarOrdenar)
        #expect(e.puesta.motivoSinPrincipal == "Falta preparar la vista previa")
        await ordenar.prepararVista()
        let vista = try #require(ordenar.vista)
        #expect(vista.hayCambios)
        #expect(e.puesta.accionPrincipal == .aplicarOrdenar)
        #expect(e.puesta.accionPrincipal.titulo == "Aplicar")
        #expect(e.puesta.motivoSinPrincipal == nil)
        // ↩ aplica: un plan, comprobado.
        await e.puesta.pulsarPrincipal()
        let hecho = try #require(ordenar.hecho, "\(ordenar.error ?? "")")
        #expect(hecho.sinDiferencias)
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        #expect(e.puesta.motor.estado.paso(.ordenar).fase == .aplicado)
        // Ya aplicado: «Siguiente».
        #expect(e.puesta.accionPrincipal == .siguiente)
    }

    @Test("P1 · Un resumen enseña lo premarcado; lo que no, en «Lo que falta» con «Lo contesto luego» (PENDIENTE)")
    func loQueFalta() async throws {
        let env = PuestaRutas.g3()
        defer { env.limpiar() }
        let m = env.puesta
        m.actualizar { $0.ir(a: "conocer.resumen") }
        let p = try #require(m.pantalla)
        #expect(p.tipo == .resumen)
        let blancas = m.motor.enBlanco(p)
        #expect(!blancas.isEmpty)
        #expect(blancas.allSatisfy { $0.premarcada == nil })
        let antes = m.motor.minutos(de: p)
        // «Siguiente» sin contestar: faltan justo esas.
        _ = m.siguiente()
        #expect(Set(m.faltan) == Set(blancas.filter { !$0.esOpcional }.map(\.id)))
        m.contestarLuego(blancas.map(\.id))
        #expect(m.faltan.isEmpty)
        #expect(blancas.allSatisfy { m.motor.estado.respuesta($0.id)?.valor == .noLoSe })
        #expect(m.motor.minutos(de: p) < antes, "Los minutos se cuentan por pregunta")
        // La explicación dice de dónde sale lo premarcado (y no nombra lo que no hay).
        #expect(["Lo he sacado de", "Lo he calculado", "No he encontrado"].contains { p.explicacion.hasPrefix($0) }, "\(p.explicacion)")
        #expect(!p.explicacion.contains("Rumbo"), "La fixture no tiene Rumbo: no se nombra")
    }
}

/// Una puesta en marcha de la copia de G3 (fixture) en temporales propios, en la pantalla que se pida.
@MainActor
struct PuestaRutas {
    let base: URL
    let puesta: ModeloPuesta

    static func g3() -> PuestaRutas {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-revision-final-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let raiz = base.appendingPathComponent("Empresa", isDirectory: true)
        let asup = base.appendingPathComponent("asup", isDirectory: true)
        try? FileManager.default.createDirectory(at: asup, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: PasoOrdenarTests.fixtureG3, to: raiz)
        let entry = VaultEntry(nombre: "Empresa", ruta: raiz.path, bookmark: nil, clase: .copia, escritura: .permitida,
                               exclusionesCopia: ["Privado"])
        let contexto = ContextoCarpeta.leer(raiz, entrada: entry, reloj: Reloj(hoy: PasoOrdenarTests.hoy))
        let motor = OnboardingEngine.abrir(vaultID: entry.id, contexto: contexto, almacen: AlmacenPuesta(vaultID: entry.id, appSupport: asup))
        return PuestaRutas(base: base, puesta: ModeloPuesta(motor: motor))
    }

    func limpiar() { try? FileManager.default.removeItem(at: base) }
}
