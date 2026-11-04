import Foundation
import Testing
@testable import TLSCore

/// Apoyo de las pruebas de métricas: copias de Asesoría Ribera (ficticia, `hoy: 2026-10-19`, lunes) y carpetas
/// mínimas hechas a mano. Nunca se toca el ejemplo del repositorio.
enum MetricasApoyo {
    static var riberaRepo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    static let madrid = TimeZone(identifier: "Europe/Madrid")!

    static func dia(_ s: String) -> LocalDate { LocalDate(parsing: s)! }

    /// Reloj fijo en Madrid a las 9:00 de `hoy`.
    static func reloj(_ hoy: String) -> Reloj {
        let d = dia(hoy)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = madrid
        let ahora = cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 9))!
        return Reloj(hoy: d, ahora: ahora, zona: madrid)
    }

    /// Una carpeta temporal propia con lo que haga falta dentro.
    struct Carpeta {
        let base: URL
        let root: URL

        var options: VaultWriter.Options {
            VaultWriter.Options(stateDirectory: base.appendingPathComponent("estado"), appSupport: base.appendingPathComponent("asup"),
                                app: "The Last System pruebas")
        }

        var entry: VaultEntry { VaultEntry(nombre: "Pruebas de métricas", ruta: root.path, bookmark: nil, clase: .demo, escritura: .permitida) }

        func bus() async throws -> CommandBus {
            CommandBus(writer: try await VaultWriter.open(entry: entry, root: root, options: options))
        }

        func url(_ p: String) -> URL { VaultPath(p).url(in: root) }
        func datos(_ p: String) -> Data? { try? Data(contentsOf: url(p)) }
        func texto(_ p: String) -> String { datos(p).map { String(decoding: $0, as: UTF8.self) } ?? "" }

        func escribir(_ p: String, _ texto: String) {
            let u = url(p)
            try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try! Data(texto.utf8).write(to: u)
        }

        /// Cambia un trozo de texto de un fichero (preparar el caso de prueba, no es la app escribiendo).
        func cambiar(_ p: String, _ de: String, _ a: String) {
            let t = texto(p)
            precondition(t.contains(de), "«\(de)» no está en \(p)")
            escribir(p, t.replacingOccurrences(of: de, with: a))
        }

        func foto() -> VaultSnapshot { VaultSnapshot.read(root: root) }

        func panel(_ hoy: String? = nil, estados: [EstadoTarjeta] = [], historial: [DecisionTarjeta] = []) -> PanelMetricas {
            PanelMetricas.calcular(snapshot: foto(), reloj: hoy.map(MetricasApoyo.reloj), estados: estados, historial: historial)
        }

        func limpiar() { try? FileManager.default.removeItem(at: base) }
    }

    /// Copia de Ribera en un temporal propio.
    static func ribera() -> Carpeta {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-metricas-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Ribera", isDirectory: true)
        try! FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try! FileManager.default.copyItem(at: riberaRepo, to: root)
        return Carpeta(base: base, root: root)
    }

    /// Carpeta vacía con `.tls/config.yaml` (demo, reloj fijo) y lo que se pase.
    static func vacia(hoy: String = "2026-10-19", config extra: String = "", ficheros: [String: String] = [:]) -> Carpeta {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("tls-metricas-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("Empresa", isDirectory: true)
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let c = Carpeta(base: base, root: root)
        c.escribir(".tls/layout.json", #"{"preset":"humana"}"#)
        c.escribir(".tls/config.yaml", "version: 1\nid: 00000000-0000-0000-0000-000000000001\nclase: demo\nhoy: \(hoy)\nprivado: []\n\(extra)")
        for (p, t) in ficheros { c.escribir(p, t) }
        return c
    }

    /// Ficha de tarea mínima.
    static func tarea(_ n: Int, _ titulo: String, estado: String = "Por hacer", tipo: String = "tarea", planificada: String? = nil,
                      vence: String? = nil, estimacion: Double? = nil, creada: String = "2026-10-01", extra: String = "") -> String {
        var fm = "---\ntls_type: task\ntls_schema: 1\nid: tarea-\(n)\nnumero: T-\(String(format: "%04d", n))\ntitulo: \(titulo)\nestado: \(estado)\ntipo: \(tipo)\n"
        if let planificada { fm += "planificada: \(planificada)\n" }
        if let vence { fm += "vence: \(vence)\n" }
        if let estimacion { fm += "estimacion_h: \(estimacion)\n" }
        fm += "creada: \(creada)\n\(extra)---\n# \(titulo)\n\n## Descripción\n\n## Actividad\n"
        return fm
    }

    static func ruta(tarea n: Int, area: String = "1 · Dirección") -> String {
        "\(area)/Tareas/t-\(String(format: "%04d", n))-tarea.md"
    }

    /// Las palabras que nunca salen en pantalla (las del lint del glosario de la interfaz).
    static let jerga = ["vault", "frontmatter", "yaml", "mcp", "null", "nan", "backlog", "issue", "run", "hash", "kpi", "pipeline", "undefined"]

    static func palabrasDeJerga(_ texto: String) -> [String] {
        let palabras = Set(texto.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return jerga.filter { palabras.contains($0) }
    }
}
