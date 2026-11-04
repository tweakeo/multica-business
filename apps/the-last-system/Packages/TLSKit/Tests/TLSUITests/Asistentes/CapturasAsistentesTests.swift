import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TLSAgents
import TLSCore
import TLSDesign
@testable import TLSUI

/// Capturas de las pantallas de asistentes, fuera de pantalla (sin abrir la app ni tocar el ratón), en claro y en
/// oscuro: Asistentes, la ficha de Mika, la del Contable con sus permisos, una tarea con su asistente trabajando y la
/// Bitácora. Solo con `TLS_CAPTURAS=<carpeta>` (p. ej. `build/capturas/f4-asistentes`). Copia de Ribera y estado en vivo
/// simulado: nunca se lanza Claude.
@Suite("Capturas · asistentes", .serialized, .enabled(if: ProcessInfo.processInfo.environment["TLS_CAPTURAS"] != nil))
@MainActor
struct CapturasAsistentesTests {
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
        for _ in 0..<14 {
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

    /// Algunos trabajos simulados del motor (como los que deja `SimulatedRuntime` en el ejemplo), con su registro técnico.
    func sembrarTrabajos(_ a: ApoyoAsistentes) throws {
        let m = try a.motor()
        let dir = a.sesion.writer?.stateDirectory ?? a.entorno.estado
        func uno(_ agente: String, _ disparo: Disparo, resumen: String, coste: Double, estado: EstadoDeEjecucion = .completada,
                 grabacion: String?, minutos: Double) throws {
            let hora = ApoyoAsistentes.lunes(8, 0).addingTimeInterval(minutos * 60)
            var e = try #require(try m.encolar(disparo, ahora: hora, simulado: true))
            e.estado = estado
            e.resumen = resumen
            e.costeUSD = coste
            e.empezada = hora
            e.terminada = estado.esFinal ? hora.addingTimeInterval(90) : nil
            e.sesion = UUID()
            try m.guardar(e)
            try m.apuntarUso(ejecucion: e.id, agente: agente, mes: "2026-10", usd: coste, fecha: hora, simulado: true)
            if let g = grabacion, let origen = GrabacionesDeEjemplo.carpeta?.appendingPathComponent("\(g).jsonl") {
                let carpeta = dir.appendingPathComponent("ejecuciones/\(e.id)", isDirectory: true)
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: origen, to: carpeta.appendingPathComponent("stream.jsonl"))
            }
        }
        let rojo = TLSAgents.RutinaDeAsistente(id: "algo-rojo", nombre: "¿Algo rojo?", hora: 8, minuto: 45, soloSiHayRojo: true)
        try uno("mika", Disparo.rutina(rojo, agente: "mika", hueco: ApoyoAsistentes.lunes(8, 45), zona: ApoyoAsistentes.madrid),
                resumen: "Revisé a las 8:45: una cosa en rojo (Ventas). Te he preparado una tarjeta para decidir.", coste: 0.07,
                grabacion: "mika-algo-rojo", minutos: 45)
        let embudo = TLSAgents.RutinaDeAsistente(id: "repaso-embudo", nombre: "Repaso del embudo", dias: [.lunes], hora: 10)
        try uno("comercial", Disparo.rutina(embudo, agente: "comercial", hueco: ApoyoAsistentes.lunes(10, 0), zona: ApoyoAsistentes.madrid),
                resumen: "Preparé el seguimiento del día 7 para Javier Ortega: espera tu OK en Decisiones.", coste: 0.04,
                grabacion: "comercial-repaso-embudo", minutos: 120)
        try uno("contable", Disparo.accion(agente: "contable", instruccion: "Prueba", datos: ["peticion": "Concilia el extracto de octubre"]),
                resumen: "Propuse casar el cobro de Talleres Martín con la factura F-2026-0007 y te pregunté por la de agosto de Móvil Levante.",
                coste: 0.06, estado: .esperandoRespuesta, grabacion: "contable-extracto-importado", minutos: 30)
    }

    @Test("Asistentes, ficha de Mika, ficha del Contable (permisos, rutinas y trabajos), tarea con su asistente trabajando y Bitácora")
    func capturas() async throws {
        // Equipo activa en la copia, para ver también Equipo › Operación › Asistentes (en Ribera está en reposo).
        let a = try await ApoyoAsistentes.abrir { carpeta in
            let u = carpeta.appendingPathComponent("6 · Equipo/Área.md")
            let t = try String(contentsOf: u, encoding: .utf8).replacingOccurrences(of: "estado: en reposo", with: "estado: activa")
            try Data(t.utf8).write(to: u)
        }
        defer { a.cerrar() }
        try sembrarTrabajos(a)
        let hoy = try #require(LocalDate(parsing: "2026-10-19"))
        let tarea = try await NuevaTareaHoja.crear(titulo: "Preparar la ficha previa de Frutas Ribera", area: .ventas, proyecto: nil,
                                                   responsable: "agente:comercial", planificada: hoy, sesion: a.sesion)
        await SesionEscrituraTests().esperar({ a.sesion.resumen(de: tarea) != nil })
        // Estado en vivo como el que da el motor con la simulación del ejemplo.
        let enVivo = EstadoEnVivo()
        enVivo.poner(TrabajoEnVivo(ejecucion: "sim-vivo", agente: "comercial", tarea: tarea, fase: .trabajando,
                                   frase: "Creando tarea…", desde: Date(), simulado: true))
        RegistroDeAsistentes.compartido.conectar(ConexionAsistentes(enVivo: enVivo), a: a.sesion)

        func pantalla(_ nav: Navegacion) -> some View {
            ContenidoEmpresa(sesion: a.sesion, nav: nav)
                .environment(a.entorno.model)
                .environment(\.navegacion, nav)
        }
        func ficha(_ slug: String, pestana: PestanaAsistente) -> Navegacion {
            let nav = Navegacion(raiz: .asistentes)
            nav.entrar(.asistente(slug))
            if pestana != .resumen {
                nav.actualizarRecuerdo(de: .asistente(slug)) { $0.extra[AsistenteFichaPantalla.clavePestana] = pestana.rawValue }
            }
            return nav
        }
        for oscuro in [false, true] {
            try await capturar(pantalla(Navegacion(raiz: .asistentes)), ancho: 1360, alto: 1180, oscuro: oscuro, nombre: "01-asistentes")
            try await capturar(pantalla(ficha("mika", pestana: .resumen)), ancho: 1360, alto: 1080, oscuro: oscuro, nombre: "02-ficha-mika")
            try await capturar(pantalla(ficha("contable", pestana: .permisos)), ancho: 1360, alto: 1180, oscuro: oscuro,
                               nombre: "03-ficha-contable-permisos")
            let nt = Navegacion(raiz: .tareas)
            nt.entrar(.tarea(tarea))
            try await capturar(pantalla(nt), ancho: 1360, alto: 900, oscuro: oscuro, nombre: "04-tarea-asistente-trabajando")
            let ne = Navegacion(raiz: .area(.equipo, pestana: PestanaArea.operacion.rawValue))
            ne.actualizarRecuerdo(de: .area(.equipo)) { $0.extra[EquipoOperacion.claveSeccion] = SeccionEquipo.asistentes.rawValue }
            try await capturar(pantalla(ne), ancho: 1360, alto: 1700, oscuro: oscuro, nombre: "05-equipo-bitacora")
            try await capturar(pantalla(ficha("contable", pestana: .rutinas)), ancho: 1360, alto: 1180, oscuro: oscuro,
                               nombre: "06-ficha-contable-rutinas")
            try await capturar(pantalla(ficha("comercial", pestana: .trabajos)), ancho: 1360, alto: 900, oscuro: oscuro,
                               nombre: "07-ficha-comercial-trabajos")
            // La barra lateral sola (la de la ventana no se pinta fuera de pantalla): la fila Asistentes y el interruptor del pie.
            try await capturar(BarraLateral(sesion: a.sesion, nav: Navegacion(raiz: .asistentes)).environment(a.entorno.model),
                               ancho: 260, alto: 1100, oscuro: oscuro, nombre: "08-barra-lateral")
        }
        #expect(FileManager.default.fileExists(atPath: destino.appendingPathComponent("01-asistentes-claro.png").path))
    }
}
