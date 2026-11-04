import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSOnboarding

/// Capturas PNG de cada paso de la puesta en marcha, en claro y en oscuro, fuera de pantalla: solo con
/// `TLS_CAPTURAS=<carpeta>` (van a `<carpeta>/f3-pasos/`). Empresa nueva de principio a fin, la bienvenida con carpeta
/// (con una carpeta privada de nombre neutro y la pantalla de recuperación) y los resúmenes de la copia de Ribera.
@Suite("Capturas de la puesta en marcha", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasPasosTests {
    var destino: URL {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
        return base.lastPathComponent == "f3-pasos" ? base : base.appendingPathComponent("f3-pasos", isDirectory: true)
    }

    /// Pinta la pantalla actual en claro y en oscuro y guarda los dos PNG.
    func capturar(_ m: ModeloPuesta, _ nombre: String, alto: CGFloat = 1180) async throws {
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        for oscuro in [false, true] {
            let v = VentanaDePrueba(m, ancho: 920, alto: alto, oscuro: oscuro)
            await v.pintar(6)
            let png = try #require(v.png(), "No se pinta \(nombre)")
            try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
            v.cerrar()
        }
    }

    static let nombresEmpresaNueva: [String: String] = [
        "bienvenida.como": "01-bienvenida-como-empiezas",
        "bienvenida.empresa": "02-bienvenida-tu-empresa",
        "bienvenida.vista": "03-bienvenida-lo-que-voy-a-crear",
        "alcance.cual": "04-alcance",
        "conocer.encuadre": "05-conocer-encuadre",
        "conocer.frase": "06-conocer-frase-del-negocio",
        "conocer.destino": "07-conocer-adonde-quieres-llegar",
        "conocer.area.VEN": "08-conocer-area-ventas",
        "conocer.entendido": "09-conocer-lo-que-he-entendido",
        "organizar.estados": "10-organizar-estados",
        "organizar.area.VEN": "11-organizar-ventas",
        "organizar.area.MAR": "12-organizar-marca-y-logo",
        "organizar.vista": "13-organizar-vista-previa",
        "sin-ti.1": "14-sin-ti",
        "sin-ti.vista": "15-sin-ti-vista-previa",
        "dia-a-dia.rutina": "16-dia-a-dia",
        "numeros.1": "17-numeros",
        "numeros.vista": "18-numeros-vista-previa",
        "conectar": "19-conectar",
        "recorrido": "20-recorrido",
    ]

    @Test("Empresa nueva: cada paso, en claro y en oscuro")
    func empresaNueva() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        var hechas: Set<String> = []
        _ = try await Recorrido.hasta(fin: m, ventana: nil, banco: b, usar: { q in
            q.id == .sector ? .noLoSe : nil
        }, alAplicar: { m in
            if m.aplicado?.paso == .diaADia { hechas.insert("aplicado") }
        }, enPantalla: { m, _ in
            guard let id = m.pantalla?.id, let nombre = Self.nombresEmpresaNueva[id], !hechas.contains(id) else { return }
            hechas.insert(id)
            // Con algo contestado, para que se vea elegido (lo que falte lo contesta el recorrido después).
            if id == "conocer.area.VEN" { await Respuestas.contestarPantalla(m) }
            if id == "dia-a-dia.rutina" { await Respuestas.contestarPantalla(m); m.prepararVistaPrevia() }
            try await capturar(m, nombre)
        })
        #expect(hechas.count >= Self.nombresEmpresaNueva.count - 1, "Faltan: \(Set(Self.nombresEmpresaNueva.keys).subtracting(hechas))")
    }

    @Test("Bienvenida con carpeta: carpeta elegida con lo privado, la copia hecha y la pantalla de recuperación")
    func bienvenidaConCarpeta() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let o = BienvenidaPasosTests.origen(b)
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m.contestar(.como, .opcion("carpeta"))
        await m.pulsarPrincipal()
        try await capturar(m, "30-bienvenida-tu-carpeta-sin-elegir", alto: 980)
        b.paneles.carpeta = o
        await m.elegirCarpetaDeOrigen()
        await m.contestar(.modo, .opcion("copia"))
        b.paneles.dentro = [VaultPath("Expediente privado")]
        await m.elegirPrivadas()
        try await capturar(m, "31-bienvenida-tu-carpeta-con-lo-privado", alto: 1080)
        await m.pulsarPrincipal()
        try await capturar(m, "32-bienvenida-copia-lista", alto: 1180)
        // Recuperación.
        let m2 = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        await m2.contestar(.como, .opcion("carpeta"))
        await m2.pulsarPrincipal()
        b.acceso = .sinPermiso
        await m2.elegirCarpetaDeOrigen()
        try await capturar(m2, "33-bienvenida-recuperacion", alto: 760)
    }

    @Test("Copia de Ribera: los resúmenes premarcados y un paso aplicado con «Deshacer»")
    func ribera() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let e = b.carpeta(copiando: PasosApoyo.ribera, nombre: "Ribera")
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        var hechas: Set<String> = []
        let nombres = ["bienvenida.carpeta": "40-ribera-tu-carpeta", "conocer.resumen": "41-ribera-lo-que-ya-se",
                       "organizar.resumen": "42-ribera-como-esta-organizada", "sin-ti.1": "43-ribera-sin-ti",
                       "numeros.1": "44-ribera-tus-numeros"]
        _ = try await Recorrido.hasta(fin: m, ventana: nil, banco: b, alAplicar: { m in
            if m.aplicado?.paso == .numeros { hechas.insert("numeros-aplicado") }
        }, enPantalla: { m, _ in
            guard let id = m.pantalla?.id else { return }
            if let n = nombres[id], !hechas.contains(id) {
                hechas.insert(id)
                try await capturar(m, n, alto: id.hasSuffix("resumen") ? 2200 : 1180)
            }
            if id == "conectar", !hechas.contains("aplicado") {
                // El resumen de un paso aplicado, con «Deshacer», volviendo a Tus números.
                hechas.insert("aplicado")
                await m.atras()
                try await capturar(m, "45-ribera-numeros-aplicado", alto: 1180)
                await m.pulsarPrincipal()
            }
        })
        #expect(hechas.isSuperset(of: Set(nombres.keys)))
    }
}
