import AppKit
import Foundation
import SwiftUI
import Testing
import TLSAgents
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas fuera de pantalla del rol mika (F4), en claro y en oscuro: ⌘J con una conversación, Decisiones con una
/// aprobación sensible, la aprobación cambiada desde que la preparó el asistente, una pregunta, una propuesta de mejora
/// con su diferencia, Hoy con la línea de Mika y el menú de la barra. Solo con `TLS_CAPTURAS=<carpeta>`
/// (`build/capturas/f4-mika/`). Nunca se abre la app en pantalla ni se lanza Claude.
@Suite("Capturas de Mika y Decisiones (F4)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasMikaTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, nombre: String, pasadas: Int = 14) async throws {
        for oscuro in [false, true] {
            let png = try await HoyApoyo.png(vista, ancho: ancho, alto: alto, oscuro: oscuro, pasadas: pasadas)
            try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
            try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        }
    }

    func pantalla(_ d: Destino, _ e: MikaApoyo.Empresa) -> some View {
        PantallaDestino(destino: d, sesion: e.sesion).environment(e.entorno.model)
            .environment(\.navegacion, Navegacion(raiz: d))
            .background(TLSPaleta.fondo.color)
    }

    @Test("⌘J con una conversación (con lo que hizo Mika) y sin Claude Code")
    func mika() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let escritura = try #require(e.asistentes.escritura)
        let raiz = e.carpeta
        // Con Claude (un canal falso que hace lo que haría Mika por el gobierno).
        let c = ConversacionMika.de(e.sesion)
        c.ritmo = nil
        c.canalDePrueba = CanalFalso(
            respuestas: [RespuestaDeChat(texto: "Hecho: el Comercial te prepara mañana, martes 20, la llamada con Amparo Ribera: lo que sabemos de Frutas Ribera, tres preguntas para el diagnóstico y el precio de Trimestrales de la Oferta. La tienes en Tareas.",
                                         modo: .claude)],
            acciones: [CanalFalso.crearTarea(escritura, titulo: "Preparar la llamada con Amparo Ribera", foto: { VaultSnapshot.read(root: raiz) })])
        let opo = VaultPath("2 · Ventas/Oportunidades/amparo-ribera-trimestrales.md")
        let nav = Navegacion(raiz: .area(.ventas))
        nav.entrar(.ficha(opo))
        c.abrir(contexto: .de(nav, sesion: e.sesion))
        await c.enviar("Prepárame la llamada con Amparo Ribera del miércoles", mostrar: "Prepárame la llamada con Amparo Ribera del miércoles")
        try await capturar(PanelMika(sesion: e.sesion, conversacion: c).environment(e.entorno.model).padding(16).background(TLSPaleta.fondo.color),
                           ancho: 432, alto: 760, nombre: "mika-conversacion")
        c.abierto = false

        // Sin Claude Code: el enrutador, que lo dice.
        let sin = ConversacionMika(sesion: e.sesion)
        sin.ritmo = nil
        sin.abrir(contexto: .general)
        await sin.enviar("¿Cómo estamos de dinero?", mostrar: "¿Cómo estamos de dinero?")
        await sin.enviar("apunta llamar a la gestoría por el modelo 303", mostrar: "apunta llamar a la gestoría por el modelo 303")
        try await capturar(PanelMika(sesion: e.sesion, conversacion: sin).environment(e.entorno.model).padding(16).background(TLSPaleta.fondo.color),
                           ancho: 432, alto: 760, nombre: "mika-sin-claude")
        // Vacío: el saludo y las acciones rápidas de Hoy.
        let vacia = ConversacionMika(sesion: e.sesion)
        vacia.abrir(contexto: .general)
        try await capturar(PanelMika(sesion: e.sesion, conversacion: vacia).environment(e.entorno.model).padding(16).background(TLSPaleta.fondo.color),
                           ancho: 432, alto: 640, nombre: "mika-vacio")
    }

    @Test("Decisiones con una aprobación sensible, una pregunta y una propuesta de mejora; la hoja y la aprobación invalidada")
    func decisiones() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        let (ruta, id) = try await MikaApoyo.borradorPendiente(e)
        let pregunta = MikaApoyo.preguntaDeContable(e)
        let sistema = VaultPath(MikaApoyo.sistema(e))
        let escritura = try #require(e.asistentes.escritura)
        let plan = WritePlan(autor: .persona("Manu"), descripcion: "Lo aprendido del seguimiento de Javier Ortega",
                             ops: [.appendToSection(sistema, section: "Aprendido",
                                                    text: "- 2026-10-19 · Si no contestan en 7 días, mejor llamar que escribir · propuesta de Comercial")])
        let (_, tarea) = try await escritura.proponer(plan, agente: "comercial", ejecucion: "r-1", capacidad: nil, clase: .mejora,
                                                      problema: "Comercial aprendió algo al preparar el seguimiento de Javier Ortega: ¿lo añadimos a su sistema?")
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion == id } != nil && e.tarjeta { $0.ruta == tarea } != nil
            && e.tarjeta { $0.ruta?.raw == pregunta } != nil }
        try await capturar(pantalla(.decisiones, e), ancho: 1240, alto: 2000, nombre: "decisiones-f4")
        let t = try #require(e.tarjeta { $0.gobierno?.aprobacion == id })
        try await capturar(pantalla(Decidir.destino(t), e), ancho: 1240, alto: 1100, nombre: "decision-aprobacion")
        // La hoja: qué sale, a quién y por cuánto.
        let m = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
        await m.cargar()
        try await capturar(SensitiveConfirmSheet(modelo: m) { _ in }, ancho: 600, alto: 620, nombre: "aprobacion-sensible")
        // Con mis cambios.
        m.editando = true
        try await capturar(SensitiveConfirmSheet(modelo: m) { _ in }, ancho: 600, alto: 620, nombre: "aprobacion-con-mis-cambios")
        // Alguien lo cambia fuera: «Aprobar» desactivado.
        e.cambiarFuera(ruta.raw, "¿Pudiste mirar la propuesta", "¿Has podido mirar la propuesta")
        let inv = ModeloAprobacion(id: id, aprobaciones: e.asistentes.aprobaciones, persona: e.sesion.autor)
        await inv.cargar()
        #expect(inv.motivoNoAprobar == "Cambió desde que lo preparó el asistente")
        try await capturar(SensitiveConfirmSheet(modelo: inv) { _ in }, ancho: 600, alto: 620, nombre: "aprobacion-invalidada")
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion == id }?.gobierno?.cambio == true }
        try await capturar(pantalla(Decidir.destino(t), e), ancho: 1240, alto: 1100, nombre: "decision-aprobacion-invalidada")
        // La pregunta y la propuesta de mejora con su diferencia.
        try await capturar(pantalla(.decision(de: VaultPath(pregunta)), e), ancho: 1240, alto: 1000, nombre: "decision-pregunta")
        try await capturar(pantalla(.decision(de: tarea), e), ancho: 1240, alto: 1200, nombre: "decision-propuesta-mejora")
    }

    @Test("Hoy con la línea de Mika y el menú de la barra")
    func hoyYBarra() async throws {
        let e = try await MikaApoyo.ribera()
        defer { e.cerrar() }
        _ = try await MikaApoyo.borradorPendiente(e)
        await e.esperar { e.tarjeta { $0.gobierno?.aprobacion != nil } != nil }
        await e.asistentes.actualizar()
        try await capturar(pantalla(.hoy, e), ancho: 1240, alto: 2300, nombre: "hoy-con-mika")
        let d = try #require(e.datos)
        try await capturar(LineaMikaHoy(datos: d, sesion: e.sesion).environment(e.entorno.model).padding(16).background(TLSPaleta.fondo.color),
                           ancho: 1100, alto: 104, nombre: "hoy-linea-mika")
        let (p, _, _) = PresenciaTests.preferencias()
        p.ventanaCerrada = false
        e.entorno.model.ultimaEmpresa = e.sesion.entry.id
        let s = e.sesion
        try await capturar(MenuBarraAsistentes(model: e.entorno.model, preferencias: p, sesiones: { [s] }).environment(e.entorno.model),
                           ancho: 340, alto: 300, nombre: "barra-de-menus", pasadas: 10)
        // Ajustes › Asistentes es un `Form` agrupado: fuera de pantalla no se pinta (se ve en la app).
    }
}
