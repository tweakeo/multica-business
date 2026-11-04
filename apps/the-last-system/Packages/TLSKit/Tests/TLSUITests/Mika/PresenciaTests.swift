import Foundation
import Testing
import TLSAgents
import TLSCore
@testable import TLSUI

/// La app fuera de la ventana (todo apagado de serie), los avisos (solo lo rojo y lo que espera tu OK, con el tope
/// del día), la línea de Mika en Hoy y Claude Code en palabras llanas. Nada toca el Mac: preferencias en memoria, ítem
/// de inicio y avisos falsos, y un comprobador de Claude que nunca lanza nada.
@Suite("Mika · fuera de la ventana, avisos, Hoy y Claude Code", .serialized)
@MainActor
struct PresenciaTests {
    static func preferencias() -> (PreferenciasPresencia, ItemDeInicioEnMemoria, NotificadorEnMemoria) {
        let item = ItemDeInicioEnMemoria()
        let n = NotificadorEnMemoria()
        return (PreferenciasPresencia(defaults: nil, item: item, notificador: n), item, n)
    }

    @Test("Todo apagado de serie; «Trabajar con la ventana cerrada» registra el ítem de inicio y enciende la barra de menús")
    func apagadoDeSerie() async {
        let (p, item, _) = Self.preferencias()
        #expect(!p.barraDeMenus && !p.avisos && !p.ventanaCerrada)
        #expect(!item.activo)
        p.ventanaCerrada = true
        #expect(item.activo && item.cambios == [true])
        #expect(p.barraDeMenus, "sin barra de menús no habría cómo volver a la app")
        // Quitar la barra de menús apaga también «ventana cerrada» (y el ítem de inicio).
        p.barraDeMenus = false
        #expect(!p.ventanaCerrada && !item.activo && item.cambios == [true, false])
        // Las de las pruebas nunca son las de la app.
        #expect(!PreferenciasPresencia.esLaApp)
        #expect(!PresenciaDeLaApp.barraDeMenus && !PresenciaDeLaApp.avisos && !PresenciaDeLaApp.trabajaConLaVentanaCerrada)
    }

    @Test("Encender los avisos pide permiso al Mac; si lo niega, se quedan apagados y se dice por qué")
    func permisoDeAvisos() async {
        let (p, _, n) = Self.preferencias()
        n.permiso = false
        await p.encenderAvisos(true)
        #expect(!p.avisos && p.problema?.contains("Notificaciones") == true)
        n.permiso = true
        await p.encenderAvisos(true)
        #expect(p.avisos && p.problema == nil)
        await p.encenderAvisos(false)
        #expect(!p.avisos)
    }

    @Test("Avisos: solo lo rojo y lo que espera tu OK, cada cosa una vez y nada si están apagados")
    func avisos() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let (p, _, n) = Self.preferencias()
        let avisos = AvisosDeAsistentes(sesion: e.sesion, preferencias: p)
        let (_, id) = try await MikaApoyo.borradorPendiente(e)
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion == id } != nil }
        #expect(avisos.revisar().isEmpty, "apagados de serie: no se avisa nada")
        #expect(n.avisados.isEmpty)
        p.avisos = true
        let elegidas = avisos.revisar()
        #expect(elegidas.contains { $0.gobierno?.aprobacion == id })
        #expect(elegidas.allSatisfy(AvisosDeAsistentes.seAvisa))
        let aviso = try #require(n.avisados.first { $0.id == elegidas.first { $0.gobierno?.aprobacion == id }?.id })
        #expect(aviso.titulo == "Asesoría Ribera · Espera tu OK")
        #expect(aviso.texto.hasPrefix("Comercial prepara «Seguimiento de la propuesta de la renta»"))
        #expect(!aviso.texto.contains("¿Pudiste mirar"), "el aviso no lleva lo que sale")
        // Cada cosa una vez.
        let antes = n.avisados.count
        #expect(avisos.revisar().isEmpty && n.avisados.count == antes)
        // Lo que no es rojo ni espera tu OK no se avisa.
        #expect(e.datos?.bandeja.visibles.filter { !AvisosDeAsistentes.seAvisa($0) }.allSatisfy { t in !n.avisados.contains { $0.id == t.id } } == true)
    }

    @Test("La línea de Mika: sin revisión de hoy, la de los chequeos; con la de Mika, la suya; y lo que espera al resumen semanal")
    func lineaDeMika() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let d = try #require(e.datos)
        let sin = LineaMikaHoy.texto(datos: d, sesion: e.sesion)
        #expect(sin.texto == d.lineaMika && !sin.deMika && sin.rojo == d.hayRojo)
        #expect(sin.texto.hasPrefix("Revisé a las 8:45"))
        let madrid = TimeZone(identifier: "Europe/Madrid")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        let hoy845 = cal.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8, minute: 45))!
        let con = LineaMikaHoy.texto(datos: d, sesion: e.sesion, revision: (hoy845, "Revisé a las 8:45: 2 cosas en rojo (Ventas y Finanzas)."))
        #expect(con.texto == "Revisé a las 8:45: 2 cosas en rojo (Ventas y Finanzas)." && con.deMika)
        // Una revisión de otro día no vale para hoy.
        let ayer = LineaMikaHoy.texto(datos: d, sesion: e.sesion, revision: (hoy845.addingTimeInterval(-86_400), "Revisé ayer."))
        #expect(!ayer.deMika && ayer.texto == d.lineaMika)
        // Lo que dejan hoy los asistentes y lo que espera al resumen semanal (el presupuesto de interrupciones).
        for i in 1...6 { _ = try await MikaApoyo.borradorPendiente(e, slug: "s-\(i)", asunto: "Seguimiento \(i)") }
        await e.esperar { (e.datos?.bandeja.alResumen.count ?? 0) > 0 }
        let lleno = try #require(e.datos)
        #expect(lleno.decisiones.count <= lleno.bandeja.visibles.count)
        let t = LineaMikaHoy.texto(datos: lleno, sesion: e.sesion)
        if lleno.bandeja.alResumen.count > 0 {
            #expect(t.detalle?.contains("resumen semanal para no interrumpirte") == true)
        }
    }

    @Test("Claude Code en palabras llanas: encontrado, sin sesión, otra versión y la prueba; nunca se lanza nada")
    func claudeCode() async {
        let c = ComprobacionClaude(comprobador: ComprobadorClaudeFijo(.encontrado(version: "2.1.307", sesion: true)))
        #expect(c.estado == .sinMirar)
        await c.buscar()
        #expect(c.texto == "Claude Code está en este Mac y tienes la sesión iniciada.")
        #expect(c.consejo == nil)
        await c.probar(estado: URL(fileURLWithPath: NSTemporaryDirectory()), negadas: [])
        #expect(c.estado == .probado(ok: true) && c.texto.hasPrefix("Funciona"))

        let sinSesion = ComprobacionClaude(comprobador: ComprobadorClaudeFijo(.encontrado(version: "2.1.307", sesion: false)))
        await sinSesion.buscar()
        #expect(sinSesion.texto.contains("no has iniciado sesión"))
        #expect(sinSesion.consejo?.contains("Abre Terminal, escribe claude") == true)

        let otra = ComprobacionClaude(comprobador: ComprobadorClaudeFijo(.encontrado(version: "2.2.0", sesion: true), prueba: false))
        await otra.buscar()
        #expect(otra.consejo?.contains("comprobada con la versión 2.1.307") == true)
        await otra.probar(estado: URL(fileURLWithPath: NSTemporaryDirectory()), negadas: [])
        #expect(otra.estado == .probado(ok: false) && otra.texto.hasPrefix("No ha contestado"))

        let nada = ComprobacionClaude(comprobador: ComprobadorClaudeFijo(.noEncontrado))
        await nada.buscar()
        #expect(nada.texto == TextosClaude.noEncontrado)
        await nada.probar(estado: URL(fileURLWithPath: NSTemporaryDirectory()), negadas: [])
        #expect(nada.estado == .noEncontrado, "sin programa no se prueba")
        // En pruebas, la compartida nunca busca de verdad.
        #expect(!(ComprobacionClaude.compartida.comprobador is ComprobadorClaudeCode))
        // Sin jerga.
        for t in [TextosClaude.noEncontrado, TextosClaude.buscando, TextosClaude.probando, TextosClaude.probado(true),
                  TextosClaude.probado(false), TextosClaude.encontrado(version: nil, sesion: nil),
                  TextosClaude.consejo(version: nil, sesion: false) ?? ""] {
            #expect(GlosarioTests.jerga(t).isEmpty, "«\(t)»")
        }
    }

    @Test("El estado de los asistentes en la barra de menús, en frases cortas")
    func estadoEnLaBarra() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        await e.asistentes.actualizar()
        #expect(e.asistentes.encendidos == true)
        #expect(e.asistentes.activos.contains("mika") && e.asistentes.activos.contains("comercial"))
        #expect(!e.asistentes.activos.contains("marca"), "Marca está en reposo en Ribera")
        let lineas = EstadoDeAsistentes.lineas(sesion: e.sesion)
        #expect(lineas == ["\(e.asistentes.activos.count) asistentes activos, nada en marcha"])
    }
}
