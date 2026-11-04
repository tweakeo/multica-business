import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas de las fichas renderizadas fuera de pantalla (sin abrir la app ni tocar el ratón), en claro y en
/// oscuro: la ficha de Jorge Martín (contacto) y la de Trimestrales 2026 (proyecto, con su tablero y el panel de
/// T-0042). Solo con `TLS_CAPTURAS=<carpeta>`; las de este rol van en `build/capturas/fichas/`.
@Suite("Capturas · fichas", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasFichasTests {
    let pruebas = SesionEscrituraTests()
    let jorge = VaultPath("2 · Ventas/Contactos/jorge-martin.md")
    let proyecto = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Proyecto.md")

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
        for _ in 0..<12 {
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

    func pantalla(_ destinoFicha: Destino, nav: Navegacion, sesion: VaultSession, model: AppModel) -> some View {
        PantallaDestino(destino: destinoFicha, sesion: sesion)
            .environment(model)
            .environment(\.navegacion, nav)
            .environment(\.navegar, NavegarAccion(nav: nav, empresa: sesion.entry.id) { _ in })
    }

    @Test("Contacto: Jorge Martín (Resumen, con el panel de propiedades) y su pestaña Proyectos")
    func contacto() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let nav = Navegacion(raiz: .area(.ventas))
        nav.entrar(.base("contactos"))
        nav.entrar(.ficha(jorge))
        // El panel de propiedades de verdad va en `.inspector`, que no se pinta fuera de pantalla: en la captura
        // «con propiedades» se pone al lado a mano, con el mismo `InspectorFicha`.
        let modeloPanel = FichaModelo(ruta: jorge, sesion: sesion)
        await modeloPanel.cargar()
        for oscuro in [false, true] {
            sesion.showInspector = false
            try await capturar(pantalla(.ficha(jorge), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1280, alto: 1300, oscuro: oscuro, nombre: "contacto-jorge")
            try await capturar(HStack(spacing: 0) {
                                   pantalla(.ficha(jorge), nav: nav, sesion: sesion, model: e.model)
                                   Divider()
                                   InspectorFicha(modelo: modeloPanel).frame(width: 300)
                                       .environment(e.model).environment(\.navegacion, nav)
                               },
                               ancho: 1440, alto: 1300, oscuro: oscuro, nombre: "contacto-jorge-con-propiedades")
            try await capturar(pantalla(.ficha(jorge, pestana: "Facturas"), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1100, alto: 1100, oscuro: oscuro, nombre: "contacto-jorge-facturas")
            try await capturar(ContenidoEmpresa(sesion: sesion, nav: nav).environment(e.model).environment(\.navegacion, nav),
                               ancho: 1280, alto: 860, oscuro: oscuro, nombre: "contacto-jorge-ventana")
        }
        // El panel de propiedades suelto (dentro de `.inspector` no se pinta fuera de pantalla).
        let modelo = FichaModelo(ruta: jorge, sesion: sesion)
        await modelo.cargar()
        for oscuro in [false, true] {
            try await capturar(InspectorFicha(modelo: modelo, desplazable: false).frame(maxHeight: .infinity, alignment: .top).environment(e.model).environment(\.navegacion, nav),
                               ancho: 320, alto: 1250, oscuro: oscuro, nombre: "contacto-jorge-propiedades")
        }
        try await capturar(VistaPreviaPopover(ruta: VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md"), sesion: sesion)
                            .environment(\.navegacion, nav).padding(20).background(TLSPaleta.fondo.color),
                           ancho: 400, alto: 380, oscuro: false, nombre: "vista-previa-oportunidad")
    }

    @Test("Proyecto: Trimestrales 2026 en curso, con las fases, el tablero y el panel de T-0042")
    func proyectoEnCurso() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        try Self.prepararProyecto(e.carpeta)
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let nav = Navegacion(raiz: .area(.ventas))
        nav.entrar(.base("contactos"))
        nav.entrar(.ficha(jorge, pestana: "Proyectos"))
        nav.entrar(.ficha(proyecto))
        for oscuro in [false, true] {
            sesion.showInspector = false
            try await capturar(pantalla(.ficha(proyecto), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1440, alto: 1600, oscuro: oscuro, nombre: "proyecto-trimestrales")
            try await capturar(pantalla(.ficha(proyecto, pestana: "Resumen"), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1280, alto: 1500, oscuro: oscuro, nombre: "proyecto-trimestrales-resumen")
            sesion.showInspector = false
            let tarea = VaultPath("3 · Entrega/Proyectos/talleres-martin-trimestrales-2026/Tareas/t-0042-pedir-la-documentacion-de-1t-3t-y-los-accesos.md")
            try await capturar(pantalla(.ficha(tarea), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1280, alto: 1100, oscuro: oscuro, nombre: "tarea-t0042")
        }
        try await capturar(pantalla(.ficha(jorge, pestana: "Proyectos"), nav: nav, sesion: sesion, model: e.model),
                           ancho: 1100, alto: 1000, oscuro: false, nombre: "contacto-jorge-proyectos-cobro-confirmado")
        try await capturar(pantalla(.ficha(proyecto, pestana: "Materiales"), nav: nav, sesion: sesion, model: e.model),
                           ancho: 1280, alto: 1150, oscuro: false, nombre: "proyecto-trimestrales-materiales")
    }

    @Test("Otras fichas: oportunidad, factura (con su PDF y la pestaña Fichero), empresa y la vista previa en oscuro")
    func otrasFichas() async throws {
        let (e, entry) = try pruebas.entorno(clase: .demo, escritura: .permitida)
        defer { e.limpiar() }
        // La factura de Jorge con un PDF en su carpeta (copia de un PDF del ejemplo), para ver su vista previa.
        let origenPDF = VaultPath("4 · Finanzas/Fiscal/2026/T4/Gastos/software-contable-nube/2026-10-05 Software Contable Nube SCN-2610 145,20€.pdf")
        let pdf = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/F-2026-0007 Talleres Martín.pdf")
        try FileManager.default.copyItem(at: origenPDF.url(in: e.carpeta), to: pdf.url(in: e.carpeta))
        let sesion = VaultSession(entry: entry, estado: e.estado)
        sesion.persona = "Manu"
        await sesion.start(using: e.model)
        defer { sesion.close() }
        let nav = Navegacion(raiz: .area(.ventas))
        let oportunidad = VaultPath("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md")
        let factura = VaultPath("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md")
        let empresa = VaultPath("2 · Ventas/Empresas/talleres-martin-e-hijos.md")
        sesion.showInspector = false
        for oscuro in [false, true] {
            try await capturar(pantalla(.ficha(oportunidad), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1180, alto: 1150, oscuro: oscuro, nombre: "oportunidad-jorge")
            try await capturar(pantalla(.ficha(factura), nav: nav, sesion: sesion, model: e.model),
                               ancho: 1180, alto: 1500, oscuro: oscuro, nombre: "factura-f-2026-0007")
            try await capturar(VistaPreviaPopover(ruta: oportunidad, sesion: sesion)
                                .environment(\.navegacion, nav).padding(20).background(TLSPaleta.fondo.color),
                               ancho: 400, alto: 380, oscuro: oscuro, nombre: "vista-previa-oportunidad")
        }
        try await capturar(pantalla(.ficha(factura, pestana: "Fichero"), nav: nav, sesion: sesion, model: e.model),
                           ancho: 1180, alto: 1700, oscuro: false, nombre: "factura-f-2026-0007-fichero")
        try await capturar(pantalla(.ficha(empresa), nav: nav, sesion: sesion, model: e.model),
                           ancho: 1180, alto: 1400, oscuro: false, nombre: "empresa-talleres")
        try await capturar(pantalla(.ficha(jorge), nav: nav, sesion: sesion, model: e.model),
                           ancho: 920, alto: 1100, oscuro: false, nombre: "contacto-jorge-920")
    }

    /// Ribera con el cobro de Talleres confirmado: la oportunidad Ganada, la factura Cobrada (con su cobro en
    /// `pagos.csv`) y el proyecto «Trimestrales 2026» en curso con las 6 tareas de su plan (fixture de la prueba,
    /// escrita en la copia temporal antes de abrirla).
    static func prepararProyecto(_ carpeta: URL) throws {
        func escribir(_ ruta: String, _ texto: String) throws {
            let u = VaultPath(ruta).url(in: carpeta)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(texto.utf8).write(to: u)
        }
        func cambiar(_ ruta: String, _ de: String, _ a: String) throws {
            let u = VaultPath(ruta).url(in: carpeta)
            let t = try String(contentsOf: u, encoding: .utf8).replacingOccurrences(of: de, with: a)
            try Data(t.utf8).write(to: u)
        }
        try cambiar("2 · Ventas/Oportunidades/jorge-martin-trimestrales.md", "estado: Aceptada", "estado: Ganada")
        try cambiar("2 · Ventas/Contactos/jorge-martin.md", "estado: Interesado", "estado: Activo")
        try cambiar("4 · Finanzas/Fiscal/2026/T4/Ingresos/f-2026-0007.md", "estado: Emitida", "estado: Cobrada")
        let base = "3 · Entrega/Proyectos/talleres-martin-trimestrales-2026"
        // Un material del cliente (copia de un PDF del ejemplo) para la galería de Materiales.
        let material = VaultPath("\(base)/Materiales/Extracto banco 3T.pdf").url(in: carpeta)
        try FileManager.default.createDirectory(at: material.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: VaultPath("4 · Finanzas/Fiscal/2026/T3/Gastos/movil-levante/2026-09-10 Movil Levante ML-09-2026 78,65€.pdf").url(in: carpeta),
                                         to: material)
        try escribir("\(base)/Proyecto.md", """
        ---
        tls_type: project
        tls_schema: 1
        id: 5f3c2a10-1111-4c4c-9a9a-000000000042
        nombre: Trimestrales 2026
        clase: entrega
        estado: En curso
        fase: Recogida
        empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
        contacto: "[[jorge-martin|Jorge Martín]]"
        oportunidad: "[[jorge-martin-trimestrales|Jorge Martín · Trimestrales]]"
        servicio: "[[2 · Ventas/Productos/trimestrales|Trimestrales]]"
        plan: "[[3 · Entrega/Planes de entrega/trimestrales|Plan de entrega · Trimestrales]]"
        responsable: lucia
        inicio: 2026-10-19
        plantilla: "Proyecto de entrega v1"
        ---
        # Trimestrales 2026
        > En curso · fase Recogida · Talleres Martín e Hijos SL · nació al confirmar el cobro de F-2026-0007

        ## Resultado prometido
        «Que en enero no me tenga que acordar de nada.» Frase destino de Jorge en el descubrimiento del 9 oct.

        ## Alcance
        Contabilidad al día cada mes y modelos 303 y 111 del 4T de 2026. Pago al inicio del trimestre de trabajo.

        ## Terminado cuando
        111 presentado antes del 20 ene y 303 antes del 30 ene, justificantes archivados y resumen enviado al cliente.

        ## Riesgos
        > Guía: lo que puede retrasar la entrega y qué haremos si pasa.

        """)
        let tareas: [(Int, String, String, String, String, String, String)] = [
            (42, "Pedir la documentación de 1T–3T y los accesos", "En revisión", "agente:implementador", "2026-10-19", "2026-10-23", "Recogida"),
            (43, "Contabilizar cada mes y clasificar los gastos", "Por hacer", "agente:implementador", "2026-10-26", "2026-12-31", "Contabilidad"),
            (44, "Conciliar los bancos y listar las diferencias", "Por hacer", "agente:implementador", "2026-12-28", "2026-12-31", "Contabilidad"),
            (45, "Preparar los borradores del 303 y el 111 del 4T", "Por hacer", "lucia", "2027-01-04", "2027-01-12", "Modelos"),
            (46, "Validación del cliente y aviso del cargo", "Por hacer", "lucia", "2027-01-13", "2027-01-15", "Modelos"),
            (47, "Presentar el 111 y el 303 y archivar justificantes", "Por hacer", "lucia", "2027-01-18", "2027-01-20", "Presentación"),
        ]
        for (n, titulo, estado, quien, plan, vence, fase) in tareas {
            let slug = NombresDeFicha.slug(titulo, maximo: TareaArchivo.maximoSlug)
            let actividad = n == 42 ? """

            ### 2026-10-19 09:05 · agente:implementador
            Preparé el correo a Jorge pidiendo las facturas de enero a septiembre, los extractos y su autorización. Queda en Borradores: siempre con tu OK.
            <!-- tls:evento {"id":"ev-a1","tipo":"comentario"} -->

            ### 2026-10-19 09:06 · agente:implementador
            Estado: Por hacer → En revisión.
            <!-- tls:evento {"a":"En revisión","de":"Por hacer","id":"ev-a2","tipo":"estado"} -->
            """ : ""
            try escribir("\(base)/Tareas/t-\(String(format: "%04d", n))-\(slug).md", """
            ---
            tls_type: task
            tls_schema: 1
            numero: T-\(String(format: "%04d", n))
            titulo: \(titulo)
            estado: \(estado)
            tipo: tarea
            responsable: \(quien)
            planificada: \(plan)
            vence: \(vence)
            area: entrega
            fase: \(fase)
            proyecto: "[[\(base)/Proyecto|Trimestrales 2026]]"
            empresa: "[[talleres-martin-e-hijos|Talleres Martín e Hijos SL]]"
            origen: regla:cobro-confirmado
            creada: 2026-10-19
            ---
            # \(titulo)
            > \(estado) · vence el \(vence)

            ## Descripción
            Del plan de entrega de Trimestrales, fase \(fase).

            ## Actividad
            <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->\(actividad)

            """)
        }
    }
}
