import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas fuera de pantalla de Tareas con Ribera (lista, tablero, ficha de una tarea de asistente y de una de
/// persona, y la hoja ⌘N), en claro y en oscuro. Solo con `TLS_CAPTURAS=<carpeta>`; las deja en esa carpeta
/// (`build/capturas/f2-tareas/`). A la copia temporal de Ribera se le añaden unas tareas de ejemplo (y un proyecto)
/// para que la lista y el tablero tengan de todo; el ejemplo del repositorio no se toca.
@Suite("Capturas de Tareas (F2)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasTareasTests {
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
        let w = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .fullSizeContentView, .resizable],
                         backing: .buffered, defer: false)
        w.appearance = apariencia
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        for _ in 0..<16 {
            hosting.layoutSubtreeIfNeeded()
            // Deja correr las tareas del actor principal (lectura de la carpeta en segundo plano) entre pasadas.
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)
        try png.write(to: destino.appendingPathComponent("\(nombre)-\(oscuro ? "oscuro" : "claro").png"))
        w.close()
    }

    static let proyecto = "3 · Entrega/Proyectos/trimestrales-2026-dra-ana-pons"

    /// Tareas de ejemplo en la copia temporal (hoy, en Ribera, es el lunes 19 de octubre de 2026).
    static func sembrar(_ raiz: URL) throws {
        func escribir(_ ruta: String, _ texto: String) throws {
            let u = raiz.appendingPathComponent(ruta)
            try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(texto.utf8).write(to: u)
        }
        func tarea(_ n: Int, _ carpeta: String, _ slug: String, _ titulo: String, _ props: String, cuerpo: String = "", actividad: String = "") throws {
            try escribir("\(carpeta)/Tareas/t-\(String(format: "%04d", n))-\(slug).md", """
            ---
            tls_type: task
            tls_schema: 1
            id: 00000000-0000-4000-8000-\(String(format: "%012d", n))
            numero: T-\(String(format: "%04d", n))
            titulo: \(titulo)
            \(props)
            creada: 2026-10-15
            ---
            # \(titulo)

            ## Descripción
            \(cuerpo.isEmpty ? "> Guía: qué hay que hacer y cómo sabrás que está hecho." : cuerpo)

            ## Actividad
            <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->
            \(actividad)
            """)
        }
        let enlace = "proyecto: \"[[\(proyecto)/Proyecto|Trimestrales 2026 · Dra. Ana Pons]]\""
        try escribir("\(proyecto)/Proyecto.md", """
        ---
        tls_type: project
        tls_schema: 1
        id: 00000000-0000-4000-8000-0000000000aa
        nombre: Trimestrales 2026 · Dra. Ana Pons
        clase: entrega
        estado: En curso
        oportunidad: "[[dra-ana-pons-trimestrales]]"
        ---
        # Trimestrales 2026 · Dra. Ana Pons
        """)
        try tarea(3, proyecto, "pedir-la-documentacion", "Pedir la documentación de 1T–3T y los accesos",
                  "estado: En revisión\nprioridad: Alta\ntipo: tarea\nresponsable: agente:implementador\nplanificada: 2026-10-19\nvence: 2026-10-21\nestimacion_h: 1\narea: entrega\n\(enlace)\ncapacidad: ENT-02\norigen: regla:proyecto.creado",
                  cuerpo: "Pedir a la clínica las facturas de enero a septiembre y los accesos al banco. Está hecha cuando todo esté en Materiales.\n\n- [x] Facturas emitidas y recibidas\n- [ ] Extractos del banco",
                  actividad: """

                  ### 2026-10-19 09:12 · sistema
                  Creó la tarea del plan Trimestrales (paso Recogida).
                  <!-- tls:evento {"id":"ev-a1","tipo":"regla","regla":"proyecto.creado"} -->

                  ### 2026-10-19 10:32 · agente:implementador
                  Preparé el correo para pedir la documentación de enero a septiembre: [borrador](../Borradores/peticion-documentacion.md). Espera tu OK en Decisiones.
                  <!-- tls:evento {"id":"ev-a2","tipo":"ejecucion","de":"Por hacer","a":"En revisión","run":"r-7f3a","coste_usd":0.04,"aprobacion":"apr-91c2","capacidad":"ENT-02"} -->

                  ### 2026-10-19 11:02 · Manu
                  Añade que pueden mandarlo todo respondiendo a este mismo correo. @Implementador
                  <!-- tls:evento {"id":"ev-a3","tipo":"comentario","menciones":"agente:implementador"} -->

                  """)
        try tarea(4, proyecto, "contabilizar-cada-mes", "Contabilizar cada mes y clasificar los gastos",
                  "estado: Por hacer\nresponsable: Manu\nplanificada: 2026-10-27\nvence: 2026-11-06\nestimacion_h: 3\narea: entrega\n\(enlace)")
        try tarea(5, proyecto, "conciliar-los-bancos", "Conciliar los bancos y listar las diferencias",
                  "estado: Sin programar\nresponsable: agente:contable\nestimacion_h: 2\narea: entrega\n\(enlace)")
        try tarea(6, "2 · Ventas", "llamar-a-javier-ortega", "Llamar a Javier Ortega por la renta",
                  "estado: Por hacer\nprioridad: Urgente\nresponsable: Manu\nplanificada: 2026-10-19\nvence: 2026-10-16\nestimacion_h: 0.5\narea: ventas\noportunidad: \"[[javier-ortega-renta]]\"",
                  cuerpo: "Confirmar si sigue interesado y cuándo puede traer los papeles.",
                  actividad: """

                  ### 2026-10-15 17:40 · Manu
                  Estado: Sin programar → Por hacer.
                  <!-- tls:evento {"a":"Por hacer","de":"Sin programar","id":"ev-b1","tipo":"estado"} -->

                  """)
        try tarea(7, "2 · Ventas", "seguimiento-dia-7-irene", "Preparar el seguimiento del día 7 de Irene Lúcuma",
                  "estado: En curso\nresponsable: agente:comercial\nplanificada: 2026-10-20\nvence: 2026-10-22\narea: ventas")
        try tarea(8, "5 · Marca", "publicar-caso-panaderia", "Publicar el caso de éxito de la panadería",
                  "estado: Bloqueada\nresponsable: lucia\nvence: 2026-10-23\nestimacion_h: 1.5\narea: marca")
        try tarea(9, "4 · Finanzas", "cerrar-t3-gestoria", "Cerrar el T3 con la gestoría",
                  "estado: Hecha\nresponsable: Manu\nvence: 2026-10-20\ncerrada: 2026-10-17\narea: finanzas")
        try escribir(".tls/secuencias.json", "{\"tarea\":9}\n")
        // Un Tareas.md heredado (G1) para la tarjeta de «Revisar».
        try escribir("5 · Marca/Tareas.md", """
        # Tareas

        - [ ] Grabar el vídeo de la renta · 2026-10-22 · Urgente · 1h · @area:MAR · #m1
        - [ ] Responder a las reseñas de octubre · @area:MAR · #m2
        """)
    }

    func sesion() async throws -> (SesionEscrituraTests.Entorno, VaultSession) {
        let (e, entry) = try SesionEscrituraTests().entorno(clase: .demo, escritura: .permitida)
        try Self.sembrar(e.carpeta)
        let s = VaultSession(entry: entry, estado: e.estado)
        s.persona = "Manu"
        await s.start(using: e.model)
        return (e, s)
    }

    @Test("Lista y tablero de Tareas")
    func listaYTablero() async throws {
        let (e, s) = try await sesion()
        defer { s.close(); e.limpiar() }
        for oscuro in [false, true] {
            let nav = Navegacion(raiz: .tareas)
            try await capturar(PantallaDestino(destino: .tareas, sesion: s).environment(e.model).environment(\.navegacion, nav),
                               ancho: 1240, alto: 1060, oscuro: oscuro, nombre: "tareas-lista")
            let navT = Navegacion(raiz: .tareas)
            navT.actualizarRecuerdo(de: .tareas) { $0.extra["tareas.vista"] = VistaTareas.tablero.rawValue }
            try await capturar(PantallaDestino(destino: .tareas, sesion: s).environment(e.model).environment(\.navegacion, navT),
                               ancho: 1400, alto: 900, oscuro: oscuro, nombre: "tareas-tablero")
            let navF = Navegacion(raiz: .tareas)
            navF.actualizarRecuerdo(de: .tareas) {
                $0.filtros["loMio"] = "1"
                $0.extra["tareas.agrupar"] = AgrupacionTareas.contenedor.rawValue
            }
            try await capturar(PantallaDestino(destino: .tareas, sesion: s).environment(e.model).environment(\.navegacion, navF),
                               ancho: 980, alto: 760, oscuro: oscuro, nombre: "tareas-lo-mio-estrecha")
            let navR = Navegacion(raiz: .tareas)
            navR.actualizarRecuerdo(de: .tareas) { $0.extra["tareas.revisar"] = "1"; $0.filtros["fecha"] = FiltroFecha.vencidas.rawValue }
            try await capturar(PantallaDestino(destino: .tareas, sesion: s).environment(e.model).environment(\.navegacion, navR),
                               ancho: 1240, alto: 1000, oscuro: oscuro, nombre: "tareas-revisar")
        }
    }

    @Test("Ficha de una tarea: de un asistente (con su actividad) y de una persona (vencida)")
    func ficha() async throws {
        let (e, s) = try await sesion()
        defer { s.close(); e.limpiar() }
        let agente = VaultPath("\(Self.proyecto)/Tareas/t-0003-pedir-la-documentacion.md")
        let persona = VaultPath("2 · Ventas/Tareas/t-0006-llamar-a-javier-ortega.md")
        for oscuro in [false, true] {
            for (ruta, nombre) in [(agente, "tarea-ficha-asistente"), (persona, "tarea-ficha-persona")] {
                let nav = Navegacion(raiz: .tareas)
                try await capturar(PantallaDestino(destino: .tarea(ruta), sesion: s).environment(e.model).environment(\.navegacion, nav),
                                   ancho: 1240, alto: 1180, oscuro: oscuro, nombre: nombre)
            }
        }
    }

    @Test("Hoja ⌘N «Nueva tarea»")
    func hoja() async throws {
        let (e, s) = try await sesion()
        defer { s.close(); e.limpiar() }
        for oscuro in [false, true] {
            let vista = NuevaTareaHoja(contexto: .area(.ventas), sesion: s)
                .background(TLSPaleta.superficieElevada.color)
                .environment(e.model)
            try await capturar(vista, ancho: 480, alto: 360, oscuro: oscuro, nombre: "nueva-tarea")
        }
    }
}
