import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
import TLSImport
@testable import TLSUI

/// Capturas del tutorial (velo con hueco y burbuja), del manual y de la hoja de Multica, fuera de pantalla: solo con
/// `TLS_CAPTURAS=<carpeta>` (van a `<carpeta>/f3-tutorial/`, como las de los otros roles de F3; `make capturas`). Nunca se
/// abre la app ni se toca el ratón.
@Suite("Capturas del tutorial y del manual", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasTutorialTests {
    var destino: URL {
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
        return base.lastPathComponent == "f3-tutorial" ? base : base.appendingPathComponent("f3-tutorial", isDirectory: true)
    }

    let pruebas = SesionEscrituraTests()

    /// Pinta la vista en una ventana que nunca se enseña y guarda el PNG.
    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String,
                           antes: (@MainActor (NSWindow) async -> Void)? = nil) async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let hosting = NSHostingView(rootView: vista.frame(width: ancho, height: alto))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        hosting.appearance = apariencia
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable],
                         backing: .buffered, defer: false)
        w.appearance = apariencia
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        defer { w.close() }
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        if let antes { await antes(w) }
        for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
    }

    @Test("Tutorial sobre Ribera: bienvenida, foco de Hoy con hueco, mapa con hueco y final")
    func tutorial() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let almacen = AlmacenTutorial(archivo: e.base.appendingPathComponent("tutorial.json"))
        let c = ControladorTutorial.de(sesion, almacen: almacen, appSupport: e.base)
        await c.empezar()

        func pantalla(_ nav: Navegacion) -> some View {
            ContenidoEmpresa(sesion: sesion, nav: nav)
                .environment(e.model)
                .environment(\.navegacion, nav)
        }
        let hoy = Navegacion(raiz: .hoy)
        for oscuro in [false, true] {
            try await capturar(pantalla(hoy), ancho: 1280, alto: 860, oscuro: oscuro, nombre: "tutorial-bienvenida")
        }
        c.irA(1)
        for oscuro in [false, true] {
            try await capturar(pantalla(Navegacion(raiz: .hoy)), ancho: 1280, alto: 860, oscuro: oscuro,
                               nombre: "tutorial-foco-con-hueco") { w in
                let presentes = TutorialAnclas.compartidas.presentes(en: w)
                #expect(presentes.contains(.hoyFoco), "el foco de Hoy tiene su ancla en pantalla")
            }
        }
        // Un paso cuyo sitio no está en pantalla: solo la burbuja, sin velo, con «Llévame».
        c.irA(3)
        for oscuro in [false, true] {
            try await capturar(pantalla(Navegacion(raiz: .hoy)), ancho: 1280, alto: 860, oscuro: oscuro, nombre: "tutorial-sin-ancla")
        }
        // El mapa de Dirección: al aparecer, el paso queda hecho solo (sin hueco ya) y ofrece «Siguiente».
        c.irA(8)
        let mapa = Navegacion(raiz: .area(.direccion, pestana: PestanaArea.operacion.rawValue))
        mapa.actualizarRecuerdo(de: .area(.direccion)) { $0.extra["direccion.vista"] = "Mapa" }
        for oscuro in [false, true] {
            try await capturar(pantalla(mapa), ancho: 1280, alto: 900, oscuro: oscuro, nombre: "tutorial-mapa-hecho")
        }
        // El final, con la lista de hitos (algunos hechos).
        for parte in ["foco", "decision", "oportunidad", "editar", "finder"] {
            almacen.cambiar(.ejemplo) { $0.partes[parte] = Date() }
        }
        c.registrar(.mapaVisto)
        c.irA(11)
        for oscuro in [false, true] {
            try await capturar(pantalla(Navegacion(raiz: .hoy)), ancho: 1280, alto: 900, oscuro: oscuro, nombre: "tutorial-final")
        }
    }

    @Test("La burbuja sola, en claro y en oscuro")
    func burbuja() async throws {
        let paso = TutorialPasoVisible(
            id: "x", ancla: nil, rotulo: "Conoce la app", titulo: "Edita una ficha y mírala en Finder",
            texto: "Cambia un dato de esta ficha. Después pulsa «Mostrar en Finder»: es un fichero normal de tu Mac.",
            marca: .porHacer, progreso: "3 de 8 hitos · Quedan ~9 min",
            botones: [TutorialBoton(id: "llevarme", titulo: "Llévame", tipo: .principal),
                      TutorialBoton(id: "finder", titulo: "Mostrar en Finder"),
                      TutorialBoton(id: "saberMas", titulo: "Saber más", tipo: .enlace),
                      TutorialBoton(id: "saltar", titulo: "Saltar", tipo: .enlace),
                      TutorialBoton(id: "anterior", titulo: "Atrás", tipo: .enlace),
                      TutorialBoton(id: "seguirMasTarde", titulo: "Seguir más tarde", tipo: .enlace)])
        for oscuro in [false, true] {
            try await capturar(TutorialBurbuja(paso: paso) { _ in }.padding(24).background(TLSPaleta.fondo.color),
                               ancho: 440, alto: 340, oscuro: oscuro, nombre: "tutorial-burbuja")
        }
    }

    @Test("El manual: una sección, la búsqueda y las ideas")
    func manual() async throws {
        let carpeta = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Manual").standardizedFileURL
        let biblioteca = ManualBiblioteca.cargar(carpeta)
        for oscuro in [false, true] {
            let n = ManualNavegacion()
            n.abrir("sistema")
            try await capturar(ManualVentana(biblioteca: biblioteca, navegacion: n), ancho: 1000, alto: 700, oscuro: oscuro,
                               nombre: "manual-sistema")
        }
        let busca = ManualNavegacion()
        busca.abrir("etapas")
        busca.busqueda = "cuello"
        for oscuro in [false, true] {
            try await capturar(ManualVentana(biblioteca: biblioteca, navegacion: busca), ancho: 1000, alto: 700, oscuro: oscuro,
                               nombre: "manual-busqueda")
        }
        let ideas = ManualNavegacion()
        ideas.abrir("idea-1-3-1")
        for oscuro in [false, true] {
            try await capturar(ManualVentana(biblioteca: biblioteca, navegacion: ideas), ancho: 1000, alto: 760, oscuro: oscuro,
                               nombre: "manual-ideas")
        }
    }

    /// Multica falso en memoria: JSON inventado, nunca la cuenta real.
    struct MulticaEnMemoria: EjecutorMultica {
        func ejecutar(_ orden: OrdenMultica) async throws -> Data {
            switch orden {
            case .perfiles: Data(#"["default"]"#.utf8)
            case .espacios: Data(#"{"workspaces":[{"id":"0f6c1a2e-1111-4222-8333-944455556666","name":"Empresa de prueba"}]}"#.utf8)
            case .tareas: Data("""
                {"issues":[
                {"identifier":"MANU-1","title":"Preparar propuesta para un cliente nuevo","status":"Todo","status_category":"todo","priority":"high","due_date":"2026-10-30"},
                {"identifier":"MANU-2","title":"Cita médica de revisión","status":"Todo","status_category":"todo"},
                {"identifier":"MANU-3","title":"Publicar artículo en LinkedIn","status":"In Progress","status_category":"in_progress","priority":"medium"},
                {"identifier":"MANU-4","title":"Cerrar el trimestre con la gestoría","status":"Backlog","status_category":"backlog","priority":"low"},
                {"identifier":"MANU-6","title":"Revisar los objetivos del trimestre","status":"In Review","status_category":"in_review","priority":"urgent"}
                ],"has_more":false}
                """.utf8)
            }
        }
    }

    @Test("Importar de Multica: la vista previa con casillas")
    func multica() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        await sesion.start(using: e.model)
        defer { sesion.close() }
        for oscuro in [false, true] {
            let modelo = ModeloImportarMultica(sesion: sesion, ejecutor: MulticaEnMemoria())
            await modelo.arrancar()
            await modelo.leer()
            #expect(modelo.fase == .previa)
            try await capturar(ImportarMulticaHoja(modelo: modelo), ancho: 780, alto: 620, oscuro: oscuro, nombre: "multica-previa")
        }
    }
}
