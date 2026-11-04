import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas fuera de pantalla de Hoy, Decisiones y el Resumen de las áreas con Ribera, en claro y en oscuro. Solo con
/// `TLS_CAPTURAS=<carpeta>`; las deja en esa carpeta (`make capturas` o a mano: `build/capturas/f2-hoy/`).
@Suite("Capturas de Hoy y Decisiones (F2)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasHoyTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String) async throws {
        let png = try await HoyApoyo.png(vista, ancho: ancho, alto: alto, oscuro: oscuro)
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
    }

    func sesion(_ e: SesionEscrituraTests.Entorno, _ entry: VaultEntry) async -> VaultSession {
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        await AlmacenHoy.de(s).actualizar()
        return s
    }

    func pantalla(_ d: Destino, _ s: VaultSession, _ e: SesionEscrituraTests.Entorno) -> some View {
        PantallaDestino(destino: d, sesion: s).environment(e.model).environment(\.navegacion, Navegacion(raiz: d))
            .background(TLSPaleta.fondo.color)
    }

    @Test("Hoy con Ribera, Decisiones, una decisión 1-3-1 y el Resumen de Finanzas y Dirección")
    func ribera() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        // Una decisión con sus tres opciones y una tarea para hoy, solo en la copia temporal (para ver las opciones y
        // «Lo que cabe hoy» con algo dentro).
        let c = HoyApoyo.Copia(base: e.base, root: e.carpeta)
        let (ruta, texto) = HoyApoyo.decision131(7, titulo: "¿Cómo retomamos a Jorge Martín?", area: "2 · Ventas")
        c.escribir(ruta, texto)
        c.escribir("3 · Entrega/Tareas/t-0008-preparar-el-kit-de-la-sesion.md", """
        ---
        tls_type: task
        tls_schema: 1
        id: t8-kit
        numero: T-0008
        titulo: Preparar el kit de la sesión de Clínica Dental Sonrisa
        estado: Por hacer
        tipo: tarea
        planificada: 2026-10-19
        vence: 2026-10-19
        estimacion_h: 1.5
        creada: 2026-10-19
        ---
        # Preparar el kit de la sesión

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        """)
        let s = await sesion(e, entry)
        defer { s.close() }
        for oscuro in [false, true] {
            try await capturar(pantalla(.hoy, s, e), ancho: 1240, alto: 2300, oscuro: oscuro, nombre: "hoy")
            try await capturar(pantalla(.decisiones, s, e), ancho: 1240, alto: 1500, oscuro: oscuro, nombre: "decisiones")
            try await capturar(pantalla(.decision(de: VaultPath(ruta)), s, e), ancho: 1240, alto: 1100, oscuro: oscuro,
                               nombre: "decision-131")
            try await capturar(pantalla(.decision(de: VaultPath(HoyApoyo.t1)), s, e), ancho: 1240, alto: 900, oscuro: oscuro,
                               nombre: "decision-sin-opciones")
            try await capturar(pantalla(.area(.finanzas), s, e), ancho: 1240, alto: 1250, oscuro: oscuro, nombre: "resumen-finanzas")
            try await capturar(pantalla(.area(.direccion), s, e), ancho: 1240, alto: 1250, oscuro: oscuro, nombre: "resumen-direccion")
        }
        // Editar el inicio (con un módulo oculto) en el Resumen de Finanzas, y Hoy en una ventana estrecha.
        let inicios = AlmacenInicios.de(s)
        inicios.cambiar(.area(.finanzas)) { $0.ocultar(.pendientes) }
        inicios.alternarEdicion(.area(.finanzas), true)
        try await capturar(pantalla(.area(.finanzas), s, e), ancho: 1240, alto: 1400, oscuro: false, nombre: "resumen-finanzas-editar")
        inicios.alternarEdicion(.area(.finanzas), false)
        try await capturar(pantalla(.hoy, s, e), ancho: 860, alto: 3400, oscuro: false, nombre: "hoy-estrecho")
    }

    @Test("Hoy sin nada en rojo: no hay sección de alertas")
    func sinRojo() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let c = HoyApoyo.Copia(base: e.base, root: e.carpeta)
        try await HoyApoyo.quitarRojos(c)
        let s = await sesion(e, entry)
        defer { s.close() }
        try await capturar(pantalla(.hoy, s, e), ancho: 1240, alto: 2100, oscuro: false, nombre: "hoy-sin-rojo")
    }

    @Test("Con los registros vacíos: Sin dato, nunca 0")
    func sinDatos() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        HoyApoyo.vaciarRegistros(HoyApoyo.Copia(base: e.base, root: e.carpeta))
        let s = await sesion(e, entry)
        defer { s.close() }
        try await capturar(pantalla(.hoy, s, e), ancho: 1240, alto: 2100, oscuro: false, nombre: "hoy-sin-datos")
        try await capturar(pantalla(.area(.finanzas), s, e), ancho: 1240, alto: 1250, oscuro: true, nombre: "resumen-finanzas-sin-datos")
    }
}
