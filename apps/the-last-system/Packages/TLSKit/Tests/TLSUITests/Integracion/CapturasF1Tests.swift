import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSEditor
@testable import TLSUI

/// `make capturas`: las pantallas principales de F1 con Asesoría Ribera, en claro y en oscuro, pintadas fuera de
/// pantalla (sin abrir la app ni tocar el ratón). Deja los PNG y un `index.html` en `TLS_CAPTURAS`
/// (`build/capturas/`).
///
/// La ventana se compone a mano (barra lateral + barra de la ventana + la pantalla), porque el
/// `NavigationSplitView`, la barra de herramientas y el `.inspector` de macOS no se pintan fuera de pantalla. Las
/// pantallas, la barra lateral, las migas y el botón «Buscar o hacer…» son los de la app.
@Suite("Capturas de F1 (make capturas)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasF1Tests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    struct Captura {
        let nombre: String
        let titulo: String
        let detalle: String
    }

    /// Las capturas de F1 (las usa también el índice de F2).
    static let lista: [Captura] = [
        Captura(nombre: "01-hoy", titulo: "Hoy", detalle: "Saludo, foco (F2) y tus áreas"),
        Captura(nombre: "02-todas-las-bases", titulo: "Todas las bases", detalle: "Las 24 colecciones por área, con sus números"),
        Captura(nombre: "03-oportunidades-tabla", titulo: "Oportunidades · Tabla", detalle: "Vista «Abiertas», agrupada por etapa, con tres cifras arriba"),
        Captura(nombre: "04-oportunidades-tablero", titulo: "Oportunidades · Tablero", detalle: "Columnas por etapa"),
        Captura(nombre: "05-contacto", titulo: "Contacto · Jorge Martín", detalle: "Bases › Contactos › Jorge"),
        Captura(nombre: "06-proyecto", titulo: "Proyecto · Trimestrales 2026", detalle: "Jorge › Proyectos › proyecto, con su tablero de tareas"),
        Captura(nombre: "07-nota-editor", titulo: "Nota en el editor", detalle: "2 · Ventas/Área con casillas, aviso y un PDF incrustado"),
        Captura(nombre: "08-visor-pdf", titulo: "Visor de PDF", detalle: "Un gasto de Móvil Levante, dentro de la app"),
        Captura(nombre: "09-carpeta", titulo: "Carpeta", detalle: "Carpeta › 2 · Ventas"),
        Captura(nombre: "10-barra-lateral-edicion", titulo: "Barra lateral en edición", detalle: "Ordenar, ocultar y restaurar"),
        Captura(nombre: "11-buscar-o-hacer", titulo: "Buscar o hacer (⌘K)", detalle: "«jorge»: mejores resultados, por base y acciones"),
        Captura(nombre: "12-contacto-mas-contraste", titulo: "Contacto con «Aumentar contraste»",
                detalle: "Variantes de contraste de la paleta y anillo de 3 pt"),
        Captura(nombre: "13-tabla-mas-contraste", titulo: "Oportunidades · Tabla con «Aumentar contraste»",
                detalle: "Etapas con sus puntos de avance, bordes de control más oscuros"),
    ]

    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")
    let proyecto = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md")
    let area = VaultPath("2 · Ventas/Área.md")
    let pdf = VaultPath("4 · Finanzas/Fiscal/2026/T3/Gastos/movil-levante/2026-07-10 Movil Levante ML-07-2026 78,65€.pdf")

    @Test("Hoy, Todas las bases, Oportunidades (Tabla y Tablero), Contacto, Proyecto, Nota, PDF, Carpeta y la barra en edición")
    func pantallasPrincipales() async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        // En la copia temporal: el proyecto de Jorge con sus tareas (Ribera no trae proyectos) y, en la nota de
        // Ventas, lo que se escribiría a mano con un PDF incrustado (por CommandBus).
        try CapturasFichasTests.prepararProyecto(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        try await sesion.escribir(.anadirASeccion(area, seccion: "Pendiente", texto: """
        - [ ] Llamar a [[sergio-nexo|Sergio Nexo]] por la propuesta de **trimestrales**
        - [x] Revisar el [guion de diagnóstico](Activos/guion-de-diagnostico-v1.md) #ventas

        > [!tip] Antes de enviar una propuesta
        > Comprueba que el cobro inicial está confirmado.

        ![[\(pdf.name)#page=1]]
        """), aviso: "")
        sesion.aviso = nil
        await AlmacenBases.de(sesion).cargarTodas(forzar: true)
        sesion.registrarVisita(.ficha(jorge))
        sesion.registrarVisita(.ficha(proyecto))

        func nav(_ raiz: Destino, _ niveles: [Destino] = []) -> Navegacion {
            let n = Navegacion(raiz: raiz)
            for d in niveles { n.entrar(d) }
            return n
        }

        var hechas: [Captura] = []
        for oscuro in [false, true] {
            func foto(_ nombre: String, _ n: Navegacion, alto: CGFloat = 900, editor: Bool = false, contraste: Bool = false) async throws {
                n.inspector = false
                sesion.navegacionActiva = n
                try await capturar(VentanaParaCaptura(sesion: sesion, nav: n, model: e.model), ancho: 1440, alto: alto,
                                   oscuro: oscuro, nombre: nombre, editor: editor, contraste: contraste)
            }
            try await foto("01-hoy", nav(.hoy))
            try await foto("02-todas-las-bases", nav(.todasLasBases), alto: 1240)
            // Tabla: la vista de serie «Abiertas» (agrupada por etapa); Tablero: la de su nota índice.
            try await foto("03-oportunidades-tabla", nav(.todasLasBases, [.base("oportunidades", vista: "Abiertas")]))
            try await foto("04-oportunidades-tablero", nav(.todasLasBases, [.base("oportunidades")]))
            try await foto("05-contacto", nav(.base("contactos"), [.ficha(jorge)]), alto: 1100)
            try await foto("06-proyecto", nav(.base("contactos"), [.ficha(jorge, pestana: "Proyectos"), .ficha(proyecto)]), alto: 1100)
            try await foto("07-nota-editor", nav(.area(.ventas), [.nota(area)]), alto: 1640, editor: true)
            try await foto("08-visor-pdf", nav(.base("gastos"), [.fichero(pdf)]))
            try await foto("09-carpeta", nav(.carpeta(nil), [.carpeta(VaultPath("2 · Ventas"))]))
            sesion.barraLateral.editando = true
            try await foto("10-barra-lateral-edicion", nav(.hoy), alto: 1500)
            sesion.barraLateral.editando = false
            // ⌘K con «jorge» escrito, sobre la ventana (como la hoja flotante de la app).
            let n = nav(.hoy)
            n.inspector = false
            sesion.navegacionActiva = n
            try await capturar(ConPaleta(sesion: sesion, nav: n, model: e.model, texto: "jorge"), ancho: 1440, alto: 900,
                               oscuro: oscuro, nombre: "11-buscar-o-hacer", editor: false)
            // «Aumentar contraste» (§10): la ficha y la tabla con las variantes de contraste de la paleta.
            try await foto("12-contacto-mas-contraste", nav(.base("contactos"), [.ficha(jorge)]), alto: 1100, contraste: true)
            try await foto("13-tabla-mas-contraste", nav(.todasLasBases, [.base("oportunidades", vista: "Abiertas")]), contraste: true)
        }
        hechas = Self.lista
        try escribirIndice(hechas)
        for c in hechas {
            for modo in ["claro", "oscuro"] {
                #expect(FileManager.default.fileExists(atPath: destino.appendingPathComponent("\(c.nombre)-\(modo).png").path))
            }
        }
    }

    /// Pinta la vista en una ventana que nunca se enseña y guarda el PNG.
    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String, editor: Bool,
                           contraste: Bool = false) async throws {
        // «Aumentar contraste» sin tocar el ajuste del Mac: la paleta lo fuerza y SwiftUI lo recibe en su entorno.
        TLSApariencia.contrasteForzado = contraste ? true : nil
        defer { TLSApariencia.contrasteForzado = nil }
        let hosting = NSHostingView(rootView: vista.frame(width: ancho, height: alto)
            .environment(\._colorSchemeContrast, contraste ? .increased : .standard))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        hosting.appearance = apariencia
        // Sin barra de título: la del sistema se pintaba encima de la barra dibujada a mano (velo blanco sobre las
        // migas en las capturas altas) y añadía 32 pt a la imagen.
        let ventana = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        ventana.appearance = apariencia
        ventana.isReleasedWhenClosed = false
        ventana.contentView = hosting
        defer { ventana.close() }
        await esperar(1.5, hosting)
        if editor, let texto = hosting.buscar(VistaTextoMarkdown.self), let c = texto.controlador {
            // Como hace la pantalla al acabar de pintar: las incrustaciones (el PDF) en su sitio.
            await c.esperarPintado()
            c.colocarIncrustaciones()
            await esperar(1, hosting)
        }
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
    }

    func esperar(_ segundos: Double, _ vista: NSView) async {
        let fin = Date().addingTimeInterval(segundos)
        while Date() < fin {
            vista.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(60))
        }
    }

    /// `index.html` con las capturas en claro y oscuro, una al lado de otra.
    func escribirIndice(_ capturas: [Captura], titulo: String = "The Last System · capturas de F1") throws {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let fecha = ISO8601DateFormatter().string(from: Date())
        var html = """
        <!doctype html>
        <html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(esc(titulo))</title>
        <style>
        :root { --bg:#F3F5FA; --sf:#FFFFFF; --tx:#0F1430; --tx2:#545A7A; --sep:#DFE3EE; --hd:#1E2A78; }
        @media (prefers-color-scheme: dark) { :root { --bg:#000; --sf:#10142A; --tx:#EEF0FA; --tx2:#9AA1C4; --sep:#252B4D; } }
        body { margin:0; background:var(--bg); color:var(--tx); font: 15px/1.5 -apple-system, "DM Sans", sans-serif; }
        header { background:var(--hd); color:#fff; padding:24px 32px; }
        header h1 { margin:0; font-size:26px; } header p { margin:4px 0 0; color:#C3C9EE; }
        main { padding:24px 32px; display:grid; gap:24px; }
        section { background:var(--sf); border:1px solid var(--sep); border-radius:22px; padding:20px; }
        section h2 { margin:0; font-size:18px; } section p { margin:2px 0 12px; color:var(--tx2); }
        .par { display:grid; grid-template-columns: 1fr 1fr; gap:12px; }
        .par a { display:block; } .par img { width:100%; border-radius:12px; border:1px solid var(--sep); }
        @media (max-width: 900px) { .par { grid-template-columns: 1fr; } main { padding:16px; } }
        </style></head><body>
        <header><h1>\(esc(titulo))</h1>
        <p>Asesoría Ribera (ficticia), pintado fuera de pantalla con <code>make capturas</code> · \(fecha)</p></header>
        <main>

        """
        for c in capturas {
            html += """
            <section><h2>\(esc(c.titulo))</h2><p>\(esc(c.detalle))</p><div class="par">
            <a href="\(c.nombre)-claro.png"><img src="\(c.nombre)-claro.png" alt="\(esc(c.titulo)), en claro"></a>
            <a href="\(c.nombre)-oscuro.png"><img src="\(c.nombre)-oscuro.png" alt="\(esc(c.titulo)), en oscuro"></a>
            </div></section>

            """
        }
        html += "</main></body></html>\n"
        try Data(html.utf8).write(to: destino.appendingPathComponent("index.html"))
    }
}

/// La ventana de una empresa tal como se ve, compuesta para pintarla fuera de pantalla: barra lateral, barra de
/// la ventana (‹ ›, migas y «Buscar o hacer… ⌘K») y la pantalla del destino actual.
struct VentanaParaCaptura: View {
    let sesion: VaultSession
    let nav: Navegacion
    let model: AppModel
    @State private var ancho: CGFloat = 1100

    var body: some View {
        HStack(spacing: 0) {
            BarraLateral(sesion: sesion, nav: nav)
                .frame(width: TLSAncho.barraLateral)
                .frame(maxHeight: .infinity)
                .padding(.top, 52)
                .background(TLSPaleta.superficie.color)
            Rectangle().fill(TLSPaleta.separador.color).frame(width: 1)
            VStack(spacing: 0) {
                HStack(spacing: TLSEspacio.e8) {
                    BotonesAtrasAdelante(nav: nav, sesion: sesion)
                    MigasView(nav: nav, sesion: sesion, ancho: PlegadoMigas.anchoParaMigas(anchoDetalle: ancho))
                    Spacer(minLength: 8)
                    BotonBuscarTodo {}
                }
                .padding(.horizontal, TLSEspacio.e12)
                .frame(height: 52)
                .background(TLSPaleta.superficie.color)
                .overlay(alignment: .bottom) { Rectangle().fill(TLSPaleta.separador.color).frame(height: 1) }
                PantallaDestino(destino: nav.actual, sesion: sesion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
            }
        }
        .background(TLSPaleta.fondo.color)
        // Como en la ventana de verdad, el contenido llega hasta arriba (bajo los botones de la ventana).
        .ignoresSafeArea()
        .environment(\.navegar, NavegarAccion(nav: nav, empresa: sesion.entry.id) { _ in })
        .environment(\.navegacion, nav)
        .environment(model)
    }
}

/// La ventana con ⌘K abierta encima, como la hoja flotante de la app (velo y la paleta arriba, centrada).
struct ConPaleta: View {
    let sesion: VaultSession
    let nav: Navegacion
    let model: AppModel
    let texto: String

    var body: some View {
        ZStack(alignment: .top) {
            VentanaParaCaptura(sesion: sesion, nav: nav, model: model)
            TLSPaleta.velo.color.ignoresSafeArea()
            PaletaBusqueda(sesion: sesion, textoInicial: texto)
                .frame(height: 560)
                .clipShape(RoundedRectangle(cornerRadius: TLSRadio.ventanaFlotante, style: .continuous))
                .tlsSombra(.dos, radio: TLSRadio.ventanaFlotante)
                .padding(.top, 90)
                .environment(\.navegar, NavegarAccion(nav: nav, empresa: sesion.entry.id) { _ in })
                .environment(\.navegacion, nav)
                .environment(model)
        }
    }
}
