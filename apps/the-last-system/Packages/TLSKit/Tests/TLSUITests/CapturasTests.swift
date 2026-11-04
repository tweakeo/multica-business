import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas renderizadas fuera de pantalla (sin abrir la app ni tocar el ratón): solo se hacen con
/// `TLS_CAPTURAS=<carpeta>` en el entorno. Sirven para revisar Mosaico v2 a ojo, en claro y en oscuro.
@Suite("Capturas fuera de pantalla", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasTests {
    var destino: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] ?? NSTemporaryDirectory(), isDirectory: true)
    }

    /// Pinta una vista en una ventana que nunca se enseña y guarda el PNG.
    func capturar<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, nombre: String,
                           ventana conVentana: Bool = false) async throws {
        _ = NSApplication.shared
        TLSFuentes.registrar()
        let hosting = NSHostingView(rootView: vista.frame(width: ancho, height: alto))
        hosting.frame = NSRect(x: 0, y: 0, width: ancho, height: alto)
        let apariencia = NSAppearance(named: oscuro ? .darkAqua : .aqua)
        hosting.appearance = apariencia
        var ventana: NSWindow?
        if conVentana {
            let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable],
                             backing: .buffered, defer: false)
            w.appearance = apariencia
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            ventana = w
        }
        for _ in 0..<(conVentana ? 10 : 4) {
            hosting.layoutSubtreeIfNeeded()
            // Deja correr las tareas del actor principal (lecturas, `.task`) entre pasadas.
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        ventana?.close()
    }

    @Test("Galería de componentes")
    func componentes() async throws {
        for oscuro in [false, true] {
            try await capturar(GaleriaComponentes(), ancho: 1100, alto: 980, oscuro: oscuro, nombre: "componentes")
        }
    }

    @Test("Ventana de empresa con Ribera: Hoy, un área, la barra en edición, Revisar y una ficha")
    func ventana() async throws {
        let pruebas = SesionEscrituraTests()
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        try FileManager.default.copyItem(at: pruebas.jorge.url(in: e.carpeta),
                                         to: VaultPath("2 · Ventas/Contactos/jorge-martin 2.md").url(in: e.carpeta))
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        await pruebas.esperar { !sesion.tarjetas.isEmpty }
        sesion.registrarVisita(.ficha(pruebas.jorge))
        sesion.barraLateral.datos[.base("contactos")] = DatoFilaBarra(derecha: "16")

        func pantalla(_ nav: Navegacion) -> some View {
            ContenidoEmpresa(sesion: sesion, nav: nav)
                .environment(e.model)
                .environment(\.navegacion, nav)
        }
        for oscuro in [false, true] {
            try await capturar(pantalla(Navegacion(raiz: .hoy)), ancho: 1280, alto: 860, oscuro: oscuro, nombre: "hoy", ventana: true)
            try await capturar(pantalla(Navegacion(raiz: .area(.ventas))), ancho: 1280, alto: 860, oscuro: oscuro, nombre: "area-ventas", ventana: true)
            let profunda = Navegacion(raiz: .area(.ventas))
            profunda.entrar(.base("contactos"))
            profunda.entrar(.ficha(pruebas.jorge))
            try await capturar(pantalla(profunda), ancho: 1280, alto: 860, oscuro: oscuro, nombre: "ficha-jorge", ventana: true)
        }
        try await capturar(PantallaDestino(destino: .ficha(pruebas.jorge), sesion: sesion).environment(e.model)
                        .environment(\.navegacion, Navegacion(raiz: .ficha(pruebas.jorge))),
                     ancho: 1000, alto: 760, oscuro: false, nombre: "ficha-sola", ventana: true)
        try await capturar(pantalla(Navegacion(raiz: .revisar)), ancho: 1280, alto: 860, oscuro: false, nombre: "revisar", ventana: true)
        try await capturar(pantalla(Navegacion(raiz: .todasLasBases)), ancho: 1280, alto: 860, oscuro: false, nombre: "todas-las-bases", ventana: true)
        sesion.barraLateral.editando = true
        sesion.barraLateral.ocultar(.area(.equipo))
        try await capturar(BarraLateral(sesion: sesion, nav: Navegacion(raiz: .hoy)).environment(e.model),
                     ancho: 260, alto: 1100, oscuro: false, nombre: "barra-edicion")
        sesion.barraLateral.editando = false
        try await capturar(BarraLateral(sesion: sesion, nav: Navegacion(raiz: .area(.ventas))).environment(e.model),
                     ancho: 260, alto: 1100, oscuro: true, nombre: "barra")
    }
}

/// Todos los componentes de TLSDesign en una pantalla.
private struct GaleriaComponentes: View {
    @State private var pestana = "Resumen"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    CabeceraAzulNoche(rotulo: "Empresa · 2 · Ventas", titulo: "Arquitectura Nexo",
                                      subtitulo: "Estudio de arquitectura · cliente desde 2025", codigo: "EMP-0007",
                                      estado: EstadoCabecera("Activo", estado: .bien,
                                                             opciones: [OpcionEstado(id: "a", titulo: "Activo"),
                                                                        OpcionEstado(id: "g", titulo: "Ganada", motivoDesactivado: "Necesita un cobro confirmado")]),
                                      datos: [DatoClave("Relación", "Cliente"), DatoClave("Personas", "2")]) {
                        AvatarCabecera(iniciales: "AN")
                    } acciones: {
                        Button("Escribir un correo") {}.tlsBoton(.sobreCabecera)
                    }
                    Destacado(rotulo: "Siguiente paso", accion: "Revisar y emitir", alPulsar: {}) {
                        CifraDestacada("290,40 €", contexto: "Factura inicial en borrador · hoy")
                    }
                    .frame(width: 280)
                }
                .frame(height: 190)
                HStack(spacing: 8) {
                    ForEach(TLSEstado.allCases, id: \.self) { PastillaEstado($0) }
                    InsigniaAviso(3, palabra: "esperan tu decisión")
                    PuntoNovedad()
                    Chip("Sergio Nexo", icono: "person.crop.circle", quitar: {})
                    Chip("Trimestrales", area: .ventas, estado: .atencion)
                    Tecla("⇧⌘B")
                }
                HStack(spacing: 8) {
                    Button("Principal") {}.tlsBoton(.principal)
                    Button("Desactivado") {}.tlsBoton(.principal).disabled(true)
                    Button("Secundario") {}.tlsBoton(.secundario)
                    Button("Deshacer") {}.tlsBoton(.enlace)
                    ForEach(TLSArea.allCases, id: \.self) { IconoArea($0) }
                    ForEach(TLSArea.allCases, id: \.self) { IconoArea($0, tamano: 32) }
                    Monograma(nombre: "Asesoría Ribera")
                }
                PestanasCapsula(seleccion: $pestana, pestanas: [
                    PestanaCapsula(id: "Resumen", titulo: "Resumen"),
                    PestanaCapsula(id: "Personas", titulo: "Personas", contador: 1),
                    PestanaCapsula(id: "Facturas", titulo: "Facturas", contador: 2, urgente: .atencion, aviso: (1, "Por confirmar")),
                    PestanaCapsula(id: "Notas", titulo: "Notas"),
                ], mas: [PestanaCapsula(id: "Incidencias", titulo: "Incidencias")])
                MosaicoLayout(altoFila: 120) {
                    Mosaico("Caja", area: .finanzas, tamano: .grande, pie: "Sale de movimientos.csv") {
                        Text("12.430 €").tlsTexto(TLSTipo.cifraGrande).foregroundStyle(TLSPaleta.texto.color)
                    }
                    Mosaico("Decisiones", icono: "signpost.right.and.left") {
                        Text("3").tlsTexto(TLSTipo.cifraMedia).foregroundStyle(TLSPaleta.texto.color)
                    }
                    Mosaico("Ritmo", area: .ventas) { PastillaEstado(.bien, palabra: "En ritmo") }
                    Mosaico("Proyectos", area: .entrega, tamano: .mediano) {
                        FilaLista("Trimestrales 2026", detalle: "Talleres Martín · En curso", icono: "square.stack.3d.up", accion: {}) {
                            PastillaEstado(.atencion, palabra: "Vence hoy")
                        }
                    }
                    DestacadoVacio(rotulo: "Número clave", texto: "Aquí verás el número clave del área.")
                        .tamanoMosaico(.pequeno)
                    Mosaico("Ancho", icono: "tablecells", tamano: .ancho) {
                        Text("Un mosaico ancho ocupa las cuatro columnas.").tlsTexto(TLSTipo.lectura).foregroundStyle(TLSPaleta.texto.color)
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    VacioExplicado(icono: "tray", titulo: "Aún no hay proyecto",
                                   porQue: "Nace cuando se confirme el cobro de la factura inicial (290,40 €, en borrador).",
                                   accion: "Abrir la factura", alPulsar: {}, compacto: true)
                        .background(RoundedRectangle(cornerRadius: 22).fill(TLSPaleta.superficie.color))
                    AvisoDeshacer(Aviso("Enlacé la reunión del 14 oct a Arquitectura Nexo") {}) {}
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(TLSTipo.todos, id: \.0) { nombre, estilo in
                        Text("\(nombre) · 1.234,56 € · Ágil y claro").tlsTexto(estilo).foregroundStyle(TLSPaleta.texto.color)
                            .lineLimit(1)
                    }
                }
            }
            .padding(24)
        }
        .background(TLSPaleta.fondo.color)
    }
}
