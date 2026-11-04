import AppKit
import Foundation
import SwiftUI
import Testing
import TLSCore
import TLSDesign
@testable import TLSUI

/// Apoyo de las pruebas de Hoy, Decisiones y los módulos: copias de Asesoría Ribera (ficticia, `hoy: 2026-10-19`,
/// lunes) en un temporal propio. Nunca se toca el ejemplo del repositorio.
enum HoyApoyo {
    static var riberaRepo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    /// Reloj fijo en Madrid a una hora de `hoy`.
    static func reloj(_ hoy: String = "2026-10-19", hora: Int = 9, minuto: Int = 0) -> Reloj {
        let d = LocalDate(parsing: hoy)!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        let ahora = cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: hora, minute: minuto))!
        return Reloj(hoy: d, ahora: ahora, zona: madrid)
    }

    static let t1 = "1 · Dirección/Tareas/t-0001-subir-trimestrales-a-165-desde-t1-2027.md"
    static let t2 = "6 · Equipo/Tareas/t-0002-dejar-que-comercial-prepare-los-recordatorios.md"
    static let registro = "1 · Dirección/Decisiones.md"

    struct Copia {
        let base: URL
        let root: URL

        var entry: VaultEntry { VaultEntry(nombre: "Asesoría Ribera", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida) }

        var options: VaultWriter.Options {
            VaultWriter.Options(stateDirectory: base.appendingPathComponent("estado"), appSupport: base.appendingPathComponent("asup"),
                                app: "The Last System pruebas")
        }

        func bus() async throws -> CommandBus {
            CommandBus(writer: try await VaultWriter.open(entry: entry, root: root, options: options))
        }

        func url(_ p: String) -> URL { VaultPath(p).url(in: root) }
        func datos(_ p: String) -> Data? { try? Data(contentsOf: url(p)) }
        func texto(_ p: String) -> String { datos(p).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        func existe(_ p: String) -> Bool { FileManager.default.fileExists(atPath: url(p).path) }

        func escribir(_ p: String, _ texto: String) {
            let u = url(p)
            try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(texto.utf8).write(to: u)
        }

        /// Prepara el caso (no es la app escribiendo).
        func cambiar(_ p: String, _ de: String, _ a: String) {
            let t = texto(p)
            precondition(t.contains(de), "«\(de)» no está en \(p)")
            escribir(p, t.replacingOccurrences(of: de, with: a))
        }

        func foto() -> VaultSnapshot { VaultSnapshot.read(root: root) }

        func hoy(conflictos: [ConflictRecord] = [], estado: EstadoHoy = EstadoHoy(), reloj: Reloj = HoyApoyo.reloj()) -> DatosHoy {
            DatosHoy.calcular(foto: foto(), conflictos: conflictos, persona: "Manu", estados: estado.tarjetas,
                              historial: estado.historial, pospuestas: estado.fechasPospuestas, reloj: reloj)
        }

        /// Huella de todos los ficheros (sin el cerrojo del escritor).
        func huella() -> [String: String] {
            var out: [String: String] = [:]
            let fm = FileManager.default
            var pila = [root]
            while let dir = pila.popLast() {
                for n in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                    let u = dir.appendingPathComponent(n)
                    var esDir: ObjCBool = false
                    fm.fileExists(atPath: u.path, isDirectory: &esDir)
                    let rel = String(u.path.dropFirst(root.path.count + 1)).precomposedStringWithCanonicalMapping
                    if esDir.boolValue { pila.append(u) } else if rel != ".tls/escritor.json" {
                        out[rel] = ContentHash.of((try? Data(contentsOf: u)) ?? Data())
                    }
                }
            }
            return out
        }

        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    static func ribera() -> Copia {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-hoy-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Ribera", isDirectory: true)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: riberaRepo, to: root)
        return Copia(base: base, root: root)
    }

    /// Una tarea 1-3-1 con sus tres opciones (la 1, recomendada) y una evidencia enlazada.
    static func decision131(_ n: Int, titulo: String, area: String = "1 · Dirección", creada: String = "2026-10-19",
                            vence: String? = nil, responsable: String? = nil) -> (String, String) {
        let ruta = "\(area)/Tareas/t-\(String(format: "%04d", n))-decision-\(n).md"
        var fm = "---\ntls_type: task\ntls_schema: 1\nid: d\(n)-aaaa-bbbb\nnumero: T-\(String(format: "%04d", n))\ntitulo: \(titulo)\n"
        fm += "estado: En revisión\ntipo: decision\n"
        if let responsable { fm += "responsable: \(responsable)\n" }
        if let vence { fm += "vence: \(vence)\n" }
        fm += "creada: \(creada)\n---\n"
        let cuerpo = """
        # \(titulo)

        ## Problema
        Hay que elegir cómo seguir con [Jorge Martín](../../2%20·%20Ventas/Contactos/jorge-martin.md) antes del viernes.

        ## Opciones
        | # | Opción | A favor | En contra | Coste o riesgo |
        |---|---|---|---|---|
        | 1 | Llamarle el lunes (recomendada) | Rápido | | |
        | 2 | Escribirle un correo | Queda por escrito | Más lento | |
        | 3 | Esperar a que conteste | | Se enfría | |

        ## Por qué recomiendo la 1
        Es el que más rápido responde por teléfono.

        ## Datos que hay
        - [Oportunidad de Jorge](../../2%20·%20Ventas/Oportunidades/jorge-martin-trimestrales.md)

        ## Actividad
        <!-- tls:actividad · para comentar, escribe debajo de la última entrada -->

        """
        return (ruta, fm + cuerpo)
    }

    /// Quita lo que Ribera tiene en rojo (como las pruebas de alertas del núcleo): responsable en las oportunidades
    /// abiertas, empresa en los contactos particulares y sin alerta los tres números que la pasaban.
    static func quitarRojos(_ c: Copia) async throws {
        for o in ["amparo-ribera-trimestrales", "carlos-gil-renta", "irene-lucuma-trimestrales", "javier-ortega-renta",
                  "jorge-martin-trimestrales", "nerea-blasco-renta", "sergio-nexo-trimestrales"] {
            c.cambiar("2 · Ventas/Oportunidades/\(o).md", "\norigen: importacion", "\nresponsable: Manu\norigen: importacion")
        }
        for p in ["andres-vidal", "carlos-gil", "javier-ortega", "lucia-ferrer", "marta-soler", "nerea-blasco", "pablo-ruiz"] {
            c.cambiar("2 · Ventas/Contactos/\(p).md", "\norigen: importacion", "\nempresa: \"[[\(p)]]\"\norigen: importacion")
        }
        let metas = "1 · Dirección/Metas.md"
        c.cambiar(metas, "| FIN-MARGIN | Margen de gestión del mes | 30 % | 15 % |", "| FIN-MARGIN | Margen de gestión del mes | 30 % |  |")
        c.cambiar(metas, "| MAR-QCONV | Conversaciones cualificadas del mes | 8 | 3 |", "| MAR-QCONV | Conversaciones cualificadas del mes | 8 |  |")
        c.cambiar(metas, "| VEN-WON | Ventas cobradas del mes | 6000 € | 3000 € |", "| VEN-WON | Ventas cobradas del mes | 6000 € |  |")
    }

    /// Deja los registros de Finanzas (facturas, pagos y movimientos del banco) con solo su cabecera.
    static func vaciarRegistros(_ c: Copia) {
        for p in ["4 · Finanzas/Registros/emitidas.csv", "4 · Finanzas/Registros/recibidas.csv", "4 · Finanzas/Registros/pagos.csv",
                  "4 · Finanzas/Registros/Bancos/cuenta-corriente-banco-demo/movimientos.csv",
                  "4 · Finanzas/Registros/Bancos/cuenta-ahorro-banco-demo/movimientos.csv"] {
            let cabecera = c.texto(p).split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            c.escribir(p, cabecera + "\n")
        }
    }

    /// Una vista pintada fuera de pantalla (PNG), con tiempo para que carguen sus tareas.
    @MainActor
    static func png<V: View>(_ vista: V, ancho: CGFloat, alto: CGFloat, oscuro: Bool, pasadas: Int = 14) async throws -> Data {
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
        for _ in 0..<pasadas {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
        }
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    /// Las cifras que enseñan los módulos (para buscar ceros inventados).
    static func cifras(_ d: DatosModulos) -> [String] {
        d.cifras.values.compactMap(\.cifra) + [d.caja.saldoTexto]
    }
}
