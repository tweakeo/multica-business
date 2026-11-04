import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas fuera de pantalla de la Operación de Finanzas (Caja, Cobros, Banco con la vista previa de un extracto y los
/// heredados, Trimestre), del Banco, de Marca (Calendario, Contenido, Distribución, Conversaciones) y de Equipo (Roles,
/// Asistentes, Rutinas) con Ribera, en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>`; las deja en esa carpeta.
@Suite("Capturas de Finanzas, Marca y Equipo (F2)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasAreasBTests {
    let apoyo = ApoyoAreasB()

    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String) async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let hosting = NSHostingView(rootView: vista.frame(width: ancho, height: alto))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        hosting.appearance = apariencia
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable], backing: .buffered, defer: false)
        w.appearance = apariencia
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        for _ in 0..<16 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        w.close()
    }

    /// Una sección de la pestaña Operación de un área, a través del andamio.
    func operacion(_ area: AreaCode, clave: String, seccion: String?, sesion: VaultSession, model: AppModel) -> some View {
        let nav = Navegacion(raiz: .area(area, pestana: PestanaArea.operacion.rawValue))
        nav.actualizarRecuerdo(de: .area(area)) { $0.extra[clave] = seccion }
        return PantallaDestino(destino: .area(area, pestana: PestanaArea.operacion.rawValue), sesion: sesion)
            .environment(model).environment(\.navegacion, nav)
    }

    @Test("Finanzas: Caja, Cobros, Banco (con vista previa y heredados), Trimestre y la pantalla del Banco")
    func finanzas() async throws {
        let (e, sesion) = try await apoyo.abrir(preparar: FinanzasOperacionTests.heredadosSinteticos())
        defer { sesion.close(); e.limpiar() }
        for s in SeccionFinanzas.allCases where s != .banco {
            for oscuro in [false, true] {
                try await capturar(operacion(.finanzas, clave: FinanzasOperacion.claveSeccion, seccion: s.rawValue, sesion: sesion, model: e.model),
                                   ancho: 1240, alto: s == .trimestre ? 1240 : 1100, oscuro: oscuro,
                                   nombre: "finanzas-\(TextFolding.fold(s.rawValue))")
            }
        }
        // Banco con un extracto soltado (vista previa: 2 nuevos) dentro de la Operación de Finanzas.
        let modelo = ModeloFinanzas(sesion: sesion)
        await modelo.cargar()
        let original = try Data(contentsOf: e.carpeta.appendingPathComponent(ApoyoAreasB.extracto))
        let nuevo = String(decoding: original, as: UTF8.self)
            + "19/10/2026;19/10/2026;RECIBO MODELO 111 AEAT;-120,00;19544,65\n"
            + "19/10/2026;19/10/2026;TRANSFERENCIA DE CLIENTE NUEVO;300,00;19844,65\n"
        await modelo.previsualizar(datos: Data(nuevo.utf8), nombre: "cuenta-corriente-hasta-19-oct.csv")
        let l = try #require(modelo.lectura)
        for oscuro in [false, true] {
            let vista = VStack(alignment: .leading, spacing: 0) {
                BancoContenido(modelo: modelo, lectura: l, elegirExtracto: {})
                Spacer(minLength: 0)
            }
            .padding(TLSEspacio.e24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TLSPaleta.fondo.color)
            .environment(e.model).environment(\.navegacion, Navegacion(raiz: .area(.finanzas)))
            try await capturar(vista, ancho: 1240, alto: 1500, oscuro: oscuro, nombre: "finanzas-banco")
        }
        for oscuro in [false, true] {
            let nav = Navegacion(raiz: .banco(VaultPath(ApoyoAreasB.corriente)))
            let vista = PantallaDestino(destino: .banco(VaultPath(ApoyoAreasB.corriente)), sesion: sesion)
                .environment(e.model).environment(\.navegacion, nav)
            try await capturar(vista, ancho: 1240, alto: 1100, oscuro: oscuro, nombre: "banco-cuenta-corriente")
        }
    }

    @Test("Marca: Calendario, Contenido, Distribución y Conversaciones (con una nueva para «Proponer a Ventas»)")
    func marca() async throws {
        let nueva = "---\ntls_type: conversation\ntls_schema: 1\nperfil: \"@estudio.demo\"\ncanal: instagram\n"
            + "contenido: \"[[reserva-tu-renta-2026-y-olvidate-en-abril|Reserva tu Renta 2026 y olvídate en abril]]\"\n"
            + "fecha: 2026-10-19\nestado: Nueva\n---\n# @estudio.demo en instagram\n\n## Lo que dijo\nPregunta cuánto cuesta la Renta con dos pisos alquilados.\n"
        let programada = try String(contentsOf: SesionEscrituraTests.ribera.appendingPathComponent("5 · Marca/Contenidos/que-es-el-modelo-303-en-60-segundos.md"),
                                    encoding: .utf8)
            .replacingOccurrences(of: "estado: Aprobado", with: "estado: Programado\npublicar: 2026-10-22")
        let (e, sesion) = try await apoyo.abrir(preparar: [
            "5 · Marca/Conversaciones/instagram-estudio-demo.md": nueva,
            "5 · Marca/Contenidos/que-es-el-modelo-303-en-60-segundos.md": programada,
        ])
        defer { sesion.close(); e.limpiar() }
        for s in SeccionMarca.allCases {
            for oscuro in [false, true] {
                try await capturar(operacion(.marca, clave: MarcaOperacion.claveSeccion, seccion: s.rawValue, sesion: sesion, model: e.model),
                                   ancho: 1240, alto: 1100, oscuro: oscuro, nombre: "marca-\(TextFolding.fold(s.rawValue))")
            }
        }
    }

    @Test("Equipo: Roles, Asistentes (vacío explicado) y la rejilla de Rutinas")
    func equipo() async throws {
        let ficha = "---\ntls_type: routine\ntls_schema: 1\nnombre: Cierre de semana\ncadencia: semanal\ndia: viernes\ncreada: 2026-09-01\nactiva: true\n---\n# Cierre de semana\n"
        let log = "---\ntls_type: routine_log\nrutina: \"[[cierre-de-semana|Cierre de semana]]\"\ntipo: cierre_semana\nfecha: 2026-09-18\n---\n# Cierre\n"
        let (e, sesion) = try await apoyo.abrir(preparar: [
            "1 · Dirección/Rutinas/cierre-de-semana.md": ficha,
            "1 · Dirección/Rutinas/cierre-de-semana/2026-09-18.md": log,
        ])
        defer { sesion.close(); e.limpiar() }
        for s in SeccionEquipo.allCases {
            for oscuro in [false, true] {
                try await capturar(operacion(.equipo, clave: EquipoOperacion.claveSeccion, seccion: s.rawValue, sesion: sesion, model: e.model),
                                   ancho: 1240, alto: 1000, oscuro: oscuro, nombre: "equipo-\(TextFolding.fold(s.rawValue))")
            }
        }
    }
}
