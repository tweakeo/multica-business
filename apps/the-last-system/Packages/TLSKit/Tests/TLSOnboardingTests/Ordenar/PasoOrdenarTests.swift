import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
import TLSImport
import TLSUI
@testable import TLSOnboarding

/// El paso 2 dentro de la puesta en marcha (F3 · rol ordenar): sus pantallas cuentan para el tope (3 en la copia de G3),
/// «Aplicar» y «Deshacer» se le cuentan al motor (`registrarOrdenar`) y nada se escribe al recorrerlas. Todo en
/// temporales propios; nunca se lanza Claude.
@Suite("Puesta en marcha · ordenar", .serialized)
@MainActor
struct PasoOrdenarTests {
    static let hoy = LocalDate(year: 2026, month: 10, day: 19)!
    static var paquete: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../..").standardizedFileURL
    }
    static var fixtureG3: URL { paquete.appendingPathComponent("Tests/TLSCoreTests/Fixtures/EmpresaMinima") }

    /// Una carpeta en un temporal propio, registrada como copia, con su puesta en marcha en la primera pantalla del paso 2.
    @MainActor
    struct Entorno {
        let base: URL
        let raiz: URL
        let asup: URL
        let entry: VaultEntry
        let puesta: ModeloPuesta
        func limpiar() {
            ConexionOrdenar.olvidar(entry.id)
            try? FileManager.default.removeItem(at: base)
        }
    }

    static func entorno(copiaDe origen: URL? = nil, exclusiones: [String] = [], preparar: (URL) throws -> Void = { _ in }) throws -> Entorno {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-puesta-ordenar-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let raiz = base.appendingPathComponent("Empresa", isDirectory: true)
        let asup = base.appendingPathComponent("asup", isDirectory: true)
        try FileManager.default.createDirectory(at: asup, withIntermediateDirectories: true)
        if let origen { try FileManager.default.copyItem(at: origen, to: raiz) } else {
            try FileManager.default.createDirectory(at: raiz, withIntermediateDirectories: true)
        }
        try preparar(raiz)
        let entry = VaultEntry(nombre: "Empresa", ruta: raiz.path, bookmark: nil, clase: .copia, escritura: .permitida,
                               exclusionesCopia: exclusiones)
        let contexto = ContextoCarpeta.leer(raiz, entrada: entry, reloj: Reloj(hoy: hoy))
        var motor = OnboardingEngine.abrir(vaultID: entry.id, contexto: contexto, almacen: AlmacenPuesta(vaultID: entry.id, appSupport: asup))
        motor.ir(a: "ordenar.1")
        return Entorno(base: base, raiz: raiz, asup: asup, entry: entry, puesta: ModeloPuesta(motor: motor))
    }

    /// Una carpeta sin la estructura de la app (ruta «por ordenar»).
    static func desordenada(_ raiz: URL) throws {
        func w(_ rel: String, _ t: String) throws {
            let u = VaultPath(rel).url(in: raiz)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(t.utf8).write(to: u)
        }
        try w("Clientes/Ana López.md", "---\ntipo: persona\n---\n# Ana López\n")
        try w("Clientes/Luis Pérez.md", "---\ntipo: persona\n---\n# Luis Pérez\n")
        try w("Facturas/Factura 2025-03-15 Proveedor.pdf", "%PDF-1.4 factura de prueba")
        try w("Notas/Reunión con el banco 2026-09-01.md", "Notas de la reunión.\n")
    }

    static func huella(_ raiz: URL) async throws -> String {
        try await Inventory.make(of: raiz, exclusiones: [VaultPath("Privado")], completo: true).hashArbol
    }

    @Test("Copia de G3: 3 pantallas de ordenar; «Aplicar» y «Deshacer» se le cuentan al motor y el tope de 15 se cumple")
    func copiaDeG3() async throws {
        let e = try Self.entorno(copiaDe: Self.fixtureG3, exclusiones: ["Privado"])
        defer { e.limpiar() }
        let antes = try await Self.huella(e.raiz)
        #expect(e.puesta.ruta == .copiaG3)
        #expect(e.puesta.pantalla?.id == "ordenar.1")
        let ordenar = try #require(ConexionOrdenar.modelo(para: e.puesta, app: nil))
        #expect(ordenar.ruta == .completar)
        #expect(PasoOrdenar(modelo: e.puesta).pantallaActual(ordenar) == .completarFichas)
        ordenar.ocr = nil
        await ordenar.arrancar()
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        #expect(e.puesta.motor.pantallas(de: .ordenar).map(\.titulo) == ["Completar las fichas", "Movimientos del banco", "Calidad"])
        #expect(e.puesta.motor.estado.paso(.ordenar).fase == .pendiente)
        #expect(e.puesta.pantallas.count <= 15, "\(e.puesta.pantallas.count): \(e.puesta.pantallas.map(\.id))")
        await ordenar.prepararVista()
        // Recorrer y preparar no escribe nada.
        #expect(try await Self.huella(e.raiz) == antes)

        await ordenar.aplicar()
        let hecho = try #require(ordenar.hecho, "\(ordenar.error ?? "")")
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        let estado = e.puesta.motor.estado
        #expect(estado.paso(.ordenar).fase == .aplicado)
        #expect(estado.paso(.ordenar).plan == ordenar.planes.last)
        #expect(estado.ordenar?.planes == ordenar.planes)
        #expect(estado.ordenar?.completadas == hecho.propiedades)
        #expect(estado.ordenar?.texto == hecho.textoVerificacion)
        // Se guarda en onboarding.json (fuera de la carpeta) para «Deshacer» tras cerrar y abrir.
        #expect(AlmacenPuesta(vaultID: e.entry.id, appSupport: e.asup).leer()?.ordenar?.planes == ordenar.planes)
        // Desde la última pantalla del paso se sigue sin «falta aplicar».
        e.puesta.actualizar { $0.ir(a: "ordenar.3") }
        if case .faltaAplicar = e.puesta.siguiente() { Issue.record("El paso ya estaba aplicado") }
        #expect(e.puesta.pantalla?.paso == .organizar)

        // «Deshacer» del paso: la carpeta vuelve a estar como antes y el paso, pendiente.
        await ordenar.deshacer()
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        #expect(e.puesta.motor.estado.paso(.ordenar).fase == .pendiente)
        #expect(try await Inventory.make(of: e.raiz, exclusiones: [VaultPath("Privado")]).hashArbol
                == Inventory.make(of: Self.fixtureG3, exclusiones: [VaultPath("Privado")]).hashArbol)
    }

    @Test("Carpeta por ordenar: sin repetidos, 6 pantallas; se registran en el motor con sus títulos")
    func carpetaPorOrdenar() async throws {
        let e = try Self.entorno(preparar: Self.desordenada)
        defer { e.limpiar() }
        #expect(e.puesta.ruta == .carpetaPorOrdenar)
        #expect(e.puesta.motor.pantallas(de: .ordenar).count == 7)
        let ordenar = try #require(ConexionOrdenar.modelo(para: e.puesta, app: nil))
        #expect(ordenar.ruta == .ordenar)
        ordenar.ocr = nil
        await ordenar.arrancar()
        #expect(ordenar.inventario?.elementos.count == 4)
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        #expect(e.puesta.motor.pantallas(de: .ordenar).map(\.titulo)
                == ["Lo que hay", "Preparar", "Por programa", "Vista previa", "Comprobación", "Calidad"])
        // Cada pantalla del motor es una del paso.
        let paso = PasoOrdenar(modelo: e.puesta)
        var vistas: [PantallaOrdenar] = []
        for p in e.puesta.motor.pantallas(de: .ordenar) {
            e.puesta.actualizar { $0.ir(a: p.id) }
            vistas.append(paso.pantallaActual(ordenar))
        }
        #expect(vistas == ordenar.pantallas)
        // «Dejarlo para más tarde» no escribe nada: el paso queda omitido.
        e.puesta.actualizar { m in
            m.omitir(.ordenar)
            if let sig = m.pantallas.first(where: { $0.paso > .ordenar }) { m.ir(a: sig.id) }
        }
        #expect(e.puesta.motor.estado.paso(.ordenar).fase == .omitido)
        #expect(e.puesta.pantalla?.paso == .organizar)
    }

    @Test("Repasar la puesta en marcha: el paso 2 solo se mira y no le cuenta nada al motor")
    func repasar() async throws {
        let e = try Self.entorno(copiaDe: Self.fixtureG3, exclusiones: ["Privado"])
        defer { e.limpiar() }
        e.puesta.peticion = PeticionPuestaEnMarcha(modo: .repasar, vaultID: e.entry.id)
        let ordenar = try #require(ConexionOrdenar.modelo(para: e.puesta, app: nil))
        #expect(ordenar.soloMirar)
        ordenar.ocr = nil
        await ordenar.arrancar()
        await ordenar.prepararVista()
        ConexionOrdenar.sincronizar(e.puesta, ordenar)
        #expect(e.puesta.motor.estado.ordenar == nil)
        #expect(ordenar.motivoNoAplicar == "Repasando: aquí solo se mira")
    }

    @Test("Claude solo con el consentimiento de la puesta en marcha: sin él, ni se busca")
    func claudeConConsentimiento() async throws {
        let e = try Self.entorno(preparar: Self.desordenada)
        defer { e.limpiar() }
        let ordenar = try #require(ConexionOrdenar.modelo(para: e.puesta, app: nil))
        #expect(e.puesta.motor.estado.usarAsistente == nil)
        // Sin consentimiento, la búsqueda de verdad no hace nada (no se mira ni se lanza Claude).
        #expect(await ConexionOrdenar.claudeDeVerdad(e.puesta, ordenar.acceso) == nil)
        e.puesta.actualizar { $0.usarAsistente(false) }
        #expect(await ConexionOrdenar.claudeDeVerdad(e.puesta, ordenar.acceso) == nil)
    }

    @Test("Los textos del paso no usan jerga")
    func glosario() throws {
        let prohibidas = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash"]
        let dir = Self.paquete.appendingPathComponent("Sources/TLSOnboarding/Ordenar")
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        var revisados = 0
        for f in try FileManager.default.contentsOfDirectory(atPath: dir.path) where f.hasSuffix(".swift") {
            let texto = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            for linea in texto.split(separator: "\n") where !linea.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                && !linea.contains("accessibilityIdentifier") {
                let l = String(linea)
                for m in literal.matches(in: l, range: NSRange(l.startIndex..., in: l)) {
                    let s = (l as NSString).substring(with: m.range(at: 1))
                    guard s.contains(" ") else { continue }
                    revisados += 1
                    let palabras = Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                    #expect(prohibidas.allSatisfy { !palabras.contains($0) }, "\(f): «\(s)»")
                }
            }
        }
        #expect(revisados >= 1)
        for p in PantallaOrdenar.allCases {
            let palabras = Set((p.titulo + " " + p.explicacion).lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            #expect(prohibidas.allSatisfy { !palabras.contains($0) })
        }
    }
}

/// Capturas de la ventana de la puesta en marcha en el paso 2, fuera de pantalla: solo con `TLS_CAPTURAS=<carpeta>`
/// (van a `<carpeta>/f3-ordenar/`). Nunca se abre la app ni se toca el ratón.
@Suite("Capturas · puesta en marcha · ordenar", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasPasoOrdenarTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("f3-ordenar", isDirectory: true)
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
        defer { w.close() }
        for _ in 0..<14 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
    }

    @Test("La ventana en «Completar las fichas» (copia de G3) y en «Lo que hay» (carpeta por ordenar)")
    func ventana() async throws {
        for oscuro in [false, true] {
            let g3 = try PasoOrdenarTests.entorno(copiaDe: PasoOrdenarTests.fixtureG3, exclusiones: ["Privado"])
            defer { g3.limpiar() }
            let o = try #require(ConexionOrdenar.modelo(para: g3.puesta, app: nil))
            o.ocr = nil
            await o.arrancar()
            await o.prepararVista()
            ConexionOrdenar.sincronizar(g3.puesta, o)
            try await capturar(OnboardingFlujo(modelo: g3.puesta).background(TLSPaleta.fondo.color), ancho: 900, alto: 820,
                               oscuro: oscuro, nombre: "puesta-completar-fichas")

            let suelta = try PasoOrdenarTests.entorno(preparar: PasoOrdenarTests.desordenada)
            defer { suelta.limpiar() }
            let s = try #require(ConexionOrdenar.modelo(para: suelta.puesta, app: nil))
            s.ocr = nil
            await s.arrancar()
            ConexionOrdenar.sincronizar(suelta.puesta, s)
            try await capturar(OnboardingFlujo(modelo: suelta.puesta).background(TLSPaleta.fondo.color), ancho: 900, alto: 820,
                               oscuro: oscuro, nombre: "puesta-lo-que-hay")
        }
    }
}
