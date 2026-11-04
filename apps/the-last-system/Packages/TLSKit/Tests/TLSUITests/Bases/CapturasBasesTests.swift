import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas de las bases fuera de pantalla (sin abrir la app): «Todas las bases» y Oportunidades en Tabla y
/// Tablero, en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>`; dejan los PNG en `<carpeta>/bases/`.
@Suite("Capturas de las bases", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasBasesTests {
    @Test("Todas las bases y Oportunidades en Tabla, Tablero y ⌘K, claro y oscuro")
    func bases() async throws {
        let capturas = CapturasTests()
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        // Ribera no trae reuniones: unas cuantas en su copia temporal, para ver la semana con sus horas.
        let reuniones: [(String, String, String?, String, Int, String)] = [
            ("Diagnóstico · Arquitectura Nexo SLP", "2026-10-19", "10:00", "descubrimiento", 60, "arquitectura-nexo|Arquitectura Nexo SLP"),
            ("Seguimiento · Talleres Martín", "2026-10-20", "12:30", "seguimiento", 45, "talleres-martin-e-hijos|Talleres Martín e Hijos SL"),
            ("Sesión trimestral · Clínica Sonrisa", "2026-10-22", "9:00", "sesion", 90, "clinica-dental-sonrisa|Clínica Dental Sonrisa SLP"),
            ("Revisión semanal", "2026-10-23", "17:00", "interna", 30, ""),
            ("Llamada a la gestoría", "2026-10-21", nil, "interna", 30, ""),
        ]
        let dirReuniones = e.carpeta.appendingPathComponent("2 · Ventas/Reuniones", isDirectory: true)
        try FileManager.default.createDirectory(at: dirReuniones, withIntermediateDirectories: true)
        for (i, r) in reuniones.enumerated() {
            let texto = "---\ntls_type: meeting\ntitulo: \"\(r.0)\"\ntipo: \(r.3)\nestado: Prevista\nfecha: \(r.1)\nhora: \(r.2 ?? "")\n"
                + "duracion_min: \(r.4)\n" + (r.5.isEmpty ? "" : "empresa: \"[[\(r.5)]]\"\n") + "area: ventas\n---\n# \(r.0)\n"
            try Data(texto.utf8).write(to: dirReuniones.appendingPathComponent("reunion-\(i).md"))
        }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        await AlmacenBases.de(sesion).cargarTodas(forzar: true)
        let ops = try #require(CatalogoBases.coleccion("oportunidades"))

        func pantalla(_ destino: Destino, _ nav: Navegacion) -> some View {
            PantallaDestino(destino: destino, sesion: sesion)
                .environment(e.model)
                .environment(\.navegacion, nav)
        }
        func navBase(_ vista: TipoVista) -> Navegacion {
            let nav = Navegacion(raiz: .base("oportunidades"))
            var config = ConfigVista(vista: vista, agrupar: vista == .tablero ? "estado" : nil, columnas: ops.columnasDeSerie,
                                     fechaCalendario: ops.fechaCalendario, plegados: ops.plegadas)
            if vista == .tabla { config.agrupar = nil }
            let json = String(data: try! JSONEncoder().encode(config), encoding: .utf8)
            nav.actualizarRecuerdo(de: .base("oportunidades")) { $0.extra["config"] = json }
            return nav
        }
        let carpeta = "bases/"
        try FileManager.default.createDirectory(at: capturas.destino.appendingPathComponent("bases"), withIntermediateDirectories: true)
        for oscuro in [false, true] {
            try await capturas.capturar(pantalla(.todasLasBases, Navegacion(raiz: .todasLasBases)), ancho: 1240, alto: 1500,
                                        oscuro: oscuro, nombre: carpeta + "todas-las-bases", ventana: true)
            try await capturas.capturar(pantalla(.base("oportunidades"), navBase(.tabla)), ancho: 1360, alto: 860,
                                        oscuro: oscuro, nombre: carpeta + "oportunidades-tabla", ventana: true)
            try await capturas.capturar(pantalla(.base("oportunidades"), navBase(.tablero)), ancho: 1360, alto: 860,
                                        oscuro: oscuro, nombre: carpeta + "oportunidades-tablero", ventana: true)
            try await capturas.capturar(pantalla(.base("reuniones"), Navegacion(raiz: .base("reuniones"))), ancho: 1360, alto: 1000,
                                        oscuro: oscuro, nombre: carpeta + "reuniones-semana", ventana: true)
        }
        // Algunas más, solo en claro: la paleta ⌘K con «nexo», Facturas, Contactos en Lista y el calendario.
        try await capturas.capturar(PaletaConTexto(sesion: sesion, texto: "nexo").environment(e.model),
                                    ancho: 640, alto: 620, oscuro: false, nombre: carpeta + "paleta-nexo", ventana: true)
        try await capturas.capturar(pantalla(.base("facturas"), Navegacion(raiz: .base("facturas"))), ancho: 1360, alto: 760,
                                    oscuro: false, nombre: carpeta + "facturas", ventana: true)
        func navCon(_ id: String, _ vista: TipoVista) throws -> Navegacion {
            let c = try #require(CatalogoBases.coleccion(id))
            let nav = Navegacion(raiz: .base(id))
            let config = ConfigVista(vista: vista, agrupar: vista == .lista ? c.agruparPor : nil, columnas: c.columnasDeSerie,
                                     fechaCalendario: c.fechaCalendario)
            let json = String(data: try JSONEncoder().encode(config), encoding: .utf8)
            nav.actualizarRecuerdo(de: .base(id)) { $0.extra["config"] = json }
            return nav
        }
        try await capturas.capturar(pantalla(.base("contenidos"), try navCon("contenidos", .calendario)), ancho: 1360, alto: 900,
                                    oscuro: false, nombre: carpeta + "contenidos-calendario", ventana: true)
        try await capturas.capturar(pantalla(.base("contactos"), try navCon("contactos", .lista)), ancho: 1360, alto: 900,
                                    oscuro: false, nombre: carpeta + "contactos-lista", ventana: true)
        try await capturas.capturar(pantalla(.base("empresas"), Navegacion(raiz: .base("empresas"))), ancho: 1360, alto: 900,
                                    oscuro: false, nombre: carpeta + "empresas", ventana: true)
        let abiertas = Navegacion(raiz: .base("oportunidades"))
        abiertas.actualizarRecuerdo(de: .base("oportunidades")) { $0.extra["vistaGuardada"] = "serie:abiertas" }
        try await capturas.capturar(pantalla(.base("oportunidades"), abiertas), ancho: 1360, alto: 900,
                                    oscuro: false, nombre: carpeta + "oportunidades-abiertas-agrupada", ventana: true)
        try await capturas.capturar(pantalla(.base("gastos"), Navegacion(raiz: .base("gastos"))), ancho: 1360, alto: 760,
                                    oscuro: true, nombre: carpeta + "gastos", ventana: true)
    }
}

/// La paleta ⌘K con un texto ya escrito (para la captura).
private struct PaletaConTexto: View {
    let sesion: VaultSession
    let texto: String

    var body: some View {
        PaletaBusqueda(sesion: sesion, textoInicial: texto)
            .background(TLSPaleta.fondo.color)
    }
}
