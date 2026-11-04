import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSOnboarding
@testable import TLSUI

/// F3 · integración: por dónde se llega a la puesta en marcha (arranque, Hoy, Ajustes y el menú) y el criterio F3-6
/// («Ver un ejemplo» llega a Hoy en dos minutos o menos) con el instalador de verdad. Todo en temporales propios: el
/// registro, el Application Support y las empresas son carpetas de prueba; nunca se abre la app ni un panel.
@Suite("Puesta en marcha · integración en la app", .serialized)
@MainActor
struct IntegracionPuestaTests {
    @Test("F3-6 · «Ver un ejemplo» desde la bienvenida llega a Hoy de Ribera en dos minutos o menos")
    func verUnEjemploLlegaAHoy() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let app = AppModel(registry: b.registro)
        // El mismo enganche que la app (`EntornoPuesta.deLaApp`), con el ejemplo del repositorio y empresas temporales.
        _ = EntornoPuesta.deLaApp(app, en: b.entorno, ejemplo: PasosApoyo.ribera, empresas: b.empresas)
        let reloj = ContinuousClock()
        let inicio = reloj.now
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        let v = VentanaDePrueba(m)
        defer { v.cerrar() }
        await v.pintar()
        await m.contestar(.como, .opcion("ejemplo"))
        #expect(m.accionPrincipal == .abrirEjemplo)
        #expect(m.pantallas.count == 1, "una sola pantalla")
        await m.pulsarPrincipal()
        #expect(m.error == nil, "\(m.error ?? "")")
        let id = try #require(b.abiertas.first, "no se abrió el ejemplo")
        #expect(b.cerrada == 1, "la ventana de la puesta en marcha se cierra")
        let entrada = try #require(app.entry(id: id))
        #expect(entrada.clase == .demo)
        #expect(entrada.ruta.hasPrefix(b.empresas.path), "el ejemplo va a las empresas de prueba")

        // La ventana de la empresa se abre en Hoy (`VentanaRuta` sin destino): su sesión y Hoy con sus datos.
        let sesion = VaultSession(entry: entrada, estado: b.appSupport.appendingPathComponent(id.uuidString.lowercased()))
        defer { sesion.close() }
        await sesion.start(using: app)
        #expect(sesion.isReady)
        #expect(Navegacion().raiz == .hoy)
        let w = ventanaEmpresa(sesion, app: app)
        defer { w.close() }
        let almacen = AlmacenHoy.de(sesion)
        for _ in 0..<600 where almacen.datos == nil {
            w.contentView?.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
        }
        let datos = try #require(almacen.datos, "Hoy no llegó a tener datos")
        let tardo = reloj.now - inicio
        #expect(tardo < .seconds(120), "tardó \(tardo)")
        #expect(datos.hoy == LocalDate(parsing: "2026-10-19"), "el reloj de Ribera")
        // Ribera llega con su puesta en marcha hecha: Hoy no ofrece seguirla.
        #expect(PuertaPuestaEnMarcha.avisoDeHoy(vaultID: id, appSupport: sesion.appSupportDeLaSesion) == nil)
    }

    @Test("Arranque: «Seguir con la puesta en marcha» por cada una a medias; las abiertas sin contestar nada no cuentan")
    func pendientesDelArranque() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let app = AppModel(registry: b.registro)
        // Una abierta y cerrada sin contestar (como las que deja una ventana cerrada al momento): no es pendiente.
        let vacia = b.modelo(PeticionPuestaEnMarcha(modo: .empezar))
        #expect(AlmacenPuesta(vaultID: vacia.motor.estado.vaultID, appSupport: b.appSupport).leer()?.sinEmpezar == true)
        // «Empiezo de cero» con el nombre contestado y «Seguir más tarde»: sí, con su nombre y su paso.
        let nueva = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, como: "cero"))
        await nueva.contestar(.como, .opcion("cero"))
        await nueva.avanzar()
        await nueva.contestar(.nombreEmpresa, .texto("Estudio Prueba"))
        await nueva.seguirMasTardeYCerrar()
        let pendientes = PuestaDeLaEmpresa.pendientes(app)
        #expect(pendientes.map(\.id) == [nueva.motor.estado.vaultID])
        #expect(pendientes.first?.nombre == "Estudio Prueba")
        #expect(pendientes.first?.progreso.texto.hasPrefix("Seguir con la puesta en marcha · paso 1 de ") == true)
        #expect(pendientes.first?.progreso.textoMinutos.hasPrefix("Quedan ~") == true)
        // Al retomarla, la misma pantalla y lo contestado.
        let otra = b.modelo(PeticionPuestaEnMarcha(modo: .retomar, vaultID: nueva.motor.estado.vaultID))
        #expect(otra.pantalla?.id == nueva.pantalla?.id)
        #expect(otra.motor.valor(.nombreEmpresa)?.texto == "Estudio Prueba")
        // Una copia a medias sale con su nombre; si se quita de la lista, ya no (no se podría seguir).
        let copia = b.carpeta(copiando: PasosApoyo.fixtureG3, nombre: "Copia G3", privadas: ["Privado"])
        app.reload()
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: copia.id))
        await m.avanzar()
        await m.seguirMasTardeYCerrar()
        #expect(PuestaDeLaEmpresa.pendientes(app).map(\.nombre).contains("Copia G3"))
        try app.remove(id: copia.id)
        #expect(!PuestaDeLaEmpresa.pendientes(app).map(\.nombre).contains("Copia G3"))
    }

    @Test("Hoy, Ajustes y el menú: seguir mientras no esté terminada, repasar cuando lo está y empezar si no hay")
    func hoyAjustesYMenu() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let app = AppModel(registry: b.registro)
        let e = b.carpeta(copiando: PasosApoyo.fixtureG3, nombre: "Copia G3", privadas: ["Privado"])
        app.reload()
        let sesion = VaultSession(entry: e, estado: b.appSupport.appendingPathComponent(e.id.uuidString.lowercased()))
        defer { sesion.close() }
        await sesion.start(using: app)
        // Sin puesta en marcha: Hoy no dice nada; Ajustes y el menú, «Empezar».
        #expect(PuertaPuestaEnMarcha.avisoDeHoy(vaultID: e.id, appSupport: sesion.appSupportDeLaSesion) == nil)
        #expect(PuestaDeLaEmpresa.peticion(sesion) == PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        #expect(PuestaDeLaEmpresa.tituloMenu(sesion) == "Empezar la puesta en marcha…")
        #expect(!PuestaDeLaEmpresa.sePuedeActualizarCopia(sesion), "sin carpeta real de la que salió")
        // A medias (empezada sobre la copia y en Organizar): Hoy enseña el paso, Ajustes y el menú, «Seguir».
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        m.actualizar { $0.ir(a: $0.pantallas(de: .organizar).first!.id) }
        m.seguirMasTarde()
        let aviso = try #require(PuertaPuestaEnMarcha.avisoDeHoy(vaultID: e.id, appSupport: sesion.appSupportDeLaSesion))
        #expect(aviso.texto == "Seguir con la puesta en marcha · paso 4 de 9")
        #expect(PuestaDeLaEmpresa.peticion(sesion).modo == .retomar)
        #expect(PuestaDeLaEmpresa.tituloMenu(sesion) == "Seguir con la puesta en marcha…")
        // Terminada: Hoy ya no la enseña y se ofrece repasarla.
        let hecha = OnboardingEngine.ejemploCompletado(contexto: .leer(URL(fileURLWithPath: e.ruta), entrada: e), vaultID: e.id,
                                                       persona: "Manu", almacen: AlmacenPuesta(vaultID: e.id, appSupport: b.appSupport))
        #expect(hecha.estado.terminada)
        #expect(PuertaPuestaEnMarcha.avisoDeHoy(vaultID: e.id, appSupport: sesion.appSupportDeLaSesion) == nil)
        #expect(PuestaDeLaEmpresa.peticion(sesion).modo == .repasar)
        #expect(PuestaDeLaEmpresa.tituloMenu(sesion) == "Repasar la puesta en marcha…")
    }

    @Test("La cabecera del paso 2 dice lo de cada pantalla (no la explicación genérica)")
    func explicacionesDeOrdenar() async throws {
        let b = Banco()
        defer { b.limpiar() }
        let e = b.carpeta(copiando: PasosApoyo.fixtureG3, nombre: "Copia G3", privadas: ["Privado"])
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        let ordenar = m.motor.pantallas(de: .ordenar)
        #expect(ordenar.map(\.titulo) == ["Completar las fichas", "Movimientos del banco", "Calidad"])
        #expect(ordenar.map(\.explicacion) == ordenar.map { ResumenOrdenar.explicacion($0.titulo) })
        #expect(ordenar.allSatisfy { PantallaOrdenar(rawValue: $0.titulo)?.explicacion == $0.explicacion })
        // Y lo que registra el paso al aplicar llega con sus explicaciones.
        m.actualizar {
            $0.registrarOrdenar(ResumenOrdenar(pantallas: 2, titulos: ["Lo que hay", "Calidad"], texto: "x",
                                               explicaciones: ["Una", "Dos"]), aplicado: false)
        }
        #expect(m.motor.pantallas(de: .ordenar).map(\.explicacion) == ["Una", "Dos"])
    }

    @Test("Capturas de la integración: arranque con una a medias y la línea de Hoy", .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
    func capturas() async throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("f3-integracion", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let b = Banco()
        defer { b.limpiar() }
        let app = AppModel(registry: b.registro)
        var e = b.carpeta(copiando: PasosApoyo.ribera, nombre: "Asesoría Ribera (copia)")
        // Una copia que sabe de qué carpeta real salió (para «Actualizar la copia desde la real» en Ajustes).
        e.origen = b.base.appendingPathComponent("Empresa real").path
        try b.registro.upsert(e)
        app.reload()
        let m = b.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e.id))
        m.actualizar { $0.ir(a: $0.pantallas(de: .organizar).first!.id) }
        m.seguirMasTarde()
        let sesion = VaultSession(entry: e, estado: b.appSupport.appendingPathComponent(e.id.uuidString.lowercased()))
        defer { sesion.close() }
        await sesion.start(using: app)
        for oscuro in [false, true] {
            let sufijo = oscuro ? "oscuro" : "claro"
            // La puesta en marcha sobre una copia recién hecha desde el arranque («Ponerla en marcha»).
            let b2 = Banco()
            defer { b2.limpiar() }
            let e2 = b2.carpeta(copiando: PasosApoyo.ribera, nombre: "Asesoría Ribera (copia)")
            let m2 = b2.modelo(PeticionPuestaEnMarcha(modo: .empezar, vaultID: e2.id))
            let v2 = VentanaDePrueba(m2, alto: 820, oscuro: oscuro)
            await v2.pintar(6)
            try #require(v2.png()).write(to: dir.appendingPathComponent("puesta-sobre-copia-\(sufijo).png"))
            v2.cerrar()
            // Ajustes › Esta empresa: puesta en marcha, carpeta real y Multica (las filas tal cual; el `Form` agrupado de
            // Ajustes no se deja pintar fuera de pantalla).
            let ajustes = GroupBox("Esta empresa") {
                VStack(alignment: .leading, spacing: 12) { FilasPuestaEnAjustes(sesion: sesion) }
                    .padding(8)
            }
            .environment(app).padding(24).frame(width: 760, height: 260, alignment: .top).background(TLSPaleta.fondo.color)
            try await guardar(ajustes, ancho: 760, alto: 260, oscuro: oscuro, en: dir.appendingPathComponent("ajustes-esta-empresa-\(sufijo).png"))
            // El arranque con «Seguir con la puesta en marcha».
            let arranque = LauncherView().environment(app).frame(width: 720, height: 560).background(TLSPaleta.fondo.color)
            try await guardar(arranque, ancho: 720, alto: 560, oscuro: oscuro, en: dir.appendingPathComponent("arranque-seguir-\(sufijo).png"))
            // Hoy con la línea de la puesta en marcha.
            // (Como las capturas de F1 y F2: la barra lateral y la pantalla, sin el `NavigationSplitView`, que fuera de pantalla
            // no pinta su columna.)
            let navHoy = Navegacion(raiz: .hoy)
            let hoy = HStack(spacing: 0) {
                BarraLateral(sesion: sesion, nav: navHoy).frame(width: TLSAncho.barraLateral).frame(maxHeight: .infinity)
                    .padding(.top, 52).background(TLSPaleta.superficie.color)
                Rectangle().fill(TLSPaleta.separador.color).frame(width: 1)
                PantallaDestino(destino: .hoy, sesion: sesion).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(TLSPaleta.fondo.color)
            .environment(app).environment(\.navegacion, navHoy).frame(width: 1280, height: 820)
            try await guardar(hoy, ancho: 1280, alto: 820, oscuro: oscuro, en: dir.appendingPathComponent("hoy-seguir-\(sufijo).png"),
                              espera: { AlmacenHoy.de(sesion).datos != nil })
        }
    }

    // MARK: Apoyo

    func ventanaEmpresa(_ sesion: VaultSession, app: AppModel) -> NSWindow {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let nav = Navegacion(raiz: .hoy)
        let hosting = NSHostingView(rootView: ContenidoEmpresa(sesion: sesion, nav: nav).environment(app).frame(width: 1280, height: 820))
        hosting.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        return w
    }

    func guardar(_ vista: some View, ancho: CGFloat, alto: CGFloat, oscuro: Bool, en url: URL,
                 espera: @MainActor () -> Bool = { true }) async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: AnyView(vista))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        hosting.appearance = apariencia
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        w.appearance = apariencia
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        defer { w.close() }
        for i in 0..<120 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
            if i > 8, espera() { break }
        }
        for _ in 0..<6 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try #require(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
