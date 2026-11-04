import Foundation
import TLSCore

/// Lo que se apunta al cerrar un trabajo de un asistente (PLAN §5.3 «Stream», §4.2 «Actividad», §4.4 «Bitácora»).
public struct CierreDeTrabajo: Sendable, Hashable {
    public var ejecucion: String
    public var agente: String
    /// «Comercial».
    public var nombre: String
    public var tarea: VaultPath?
    public var estado: EstadoDeEjecucion
    public var motivo: FailureReason?
    public var nota: String?
    public var resumen: String?
    public var costeUSD: Double
    public var simulado: Bool
    /// Capacidad (VEN-08…), si se sabe.
    public var capacidad: String?
    /// `rutina:algo-rojo`, `tarea`, `mencion`…
    public var origen: String
    public var pregunta: String?
    public var intento: Int
    /// Usó `tls_solicitar_accion`: queda «pendiente de aprobación».
    public var pidioAprobacion: Bool
    public var fecha: Date

    public init(ejecucion: String, agente: String, nombre: String, tarea: VaultPath?, estado: EstadoDeEjecucion,
                motivo: FailureReason? = nil, nota: String? = nil, resumen: String? = nil, costeUSD: Double = 0,
                simulado: Bool = false, capacidad: String? = nil, origen: String, pregunta: String? = nil, intento: Int = 0,
                pidioAprobacion: Bool = false, fecha: Date) {
        self.ejecucion = ejecucion; self.agente = agente; self.nombre = nombre; self.tarea = tarea; self.estado = estado
        self.motivo = motivo; self.nota = nota; self.resumen = resumen; self.costeUSD = costeUSD; self.simulado = simulado
        self.capacidad = capacidad; self.origen = origen; self.pregunta = pregunta; self.intento = intento
        self.pidioAprobacion = pidioAprobacion; self.fecha = fecha
    }

    /// Cómo quedó, en palabras («hecho», «espera tu respuesta», «no terminó: …»).
    public var comoQuedo: String {
        switch estado {
        case .completada: "hecho"
        case .esperandoRespuesta: "espera tu respuesta"
        case .cancelada: "cancelado" + (nota.map { " (\($0))" } ?? "")
        case .fallida: "no terminó: " + (motivo?.explanation ?? nota ?? "error")
        default: estado.rawValue
        }
    }
}

/// Quien apunta los cierres en la carpeta. La app usa `ActivityWriter` (por `CommandBus`); las pruebas, uno en memoria.
public protocol RegistroDeTrabajo: Sendable {
    func registrar(_ cierre: CierreDeTrabajo) async throws
}

/// Escribe el cierre de un trabajo **una sola vez, al terminar** (nunca evento a evento: PLAN §11), con la API de
/// gobierno (`ActividadDeAsistente.plan`, `Bitacora`):
/// - en la tarea (si la hay), una entrada de Actividad `### AAAA-MM-DD HH:MM · agente:<slug>` con el resumen y su
///   `tls:evento {"tipo":"ejecucion",…}`; si el trabajo terminó bien y la tarea seguía Por hacer o En curso, en el
///   mismo plan pasa a **En revisión** (PLAN §4.2: ningún asistente pone Hecha ni Cancelada);
/// - una línea en `6 · Equipo/Bitácora/AAAA-MM.md` (la crea si no existe).
///
/// Lo escribe la app (`Autor.sistema`): es el registro del motor, no algo que decida el asistente. Todo va por
/// `CommandBus` (y por el `Autorizador`); todo se deshace; nada se borra. Lo simulado lo dice («Simulado: …»).
public struct ActivityWriter: RegistroDeTrabajo {
    public typealias Escribir = @Sendable (WritePlan) async throws -> WriteResult
    public typealias Foto = @Sendable () async -> VaultSnapshot

    let escribir: Escribir
    let foto: Foto
    let zona: TimeZone

    public init(escribir: @escaping Escribir, foto: @escaping Foto, zona: TimeZone) {
        self.escribir = escribir; self.foto = foto; self.zona = zona
    }

    public init(bus: CommandBus, foto: @escaping Foto, zona: TimeZone) {
        self.init(escribir: { try await bus.ejecutar($0) }, foto: foto, zona: zona)
    }

    public func registrar(_ c: CierreDeTrabajo) async throws {
        let snapshot = await foto()
        let reloj = Reloj(hoy: LocalDate(date: c.fecha, timeZone: zona), ahora: c.fecha, zona: zona)
        let plan = try ActividadDeAsistente.plan(Self.resumen(c, snapshot: snapshot), snapshot: snapshot, reloj: reloj)
        _ = try await escribir(plan)
    }

    /// El cierre en el formato de gobierno.
    public static func resumen(_ c: CierreDeTrabajo, snapshot: VaultSnapshot) -> ResumenDeTrabajo {
        var tarea = c.tarea
        if let t = tarea, snapshot.existing(t) == nil || snapshot.layout.isPrivate(t) { tarea = nil }
        var texto: String
        let fin: FinDeTrabajo
        switch c.estado {
        case .completada:
            texto = c.resumen.map(limpio) ?? "Trabajo terminado."
            fin = c.pidioAprobacion ? .pendienteDeAprobacion : .hecho
        case .esperandoRespuesta:
            texto = (c.resumen.map { limpio($0) + " " } ?? "") + "Te he hecho una pregunta; sigo cuando contestes."
            if let p = c.pregunta, p.hasSuffix(".md"), let t = tarea {
                texto += " [Ver la pregunta](\(enlaceRelativo(desde: t, a: VaultPath(p))))"
            }
            fin = .esperandoRespuesta
        case .cancelada:
            texto = "Trabajo cancelado" + (c.nota.map { ": \(limpio($0))" } ?? "") + "."
            fin = .cancelado
        default:
            let porque = c.motivo?.explanation ?? c.nota.map(limpio) ?? "error"
            texto = "No pude terminar: " + porque
            fin = .fallido(c.motivo?.rawValue.replacingOccurrences(of: "_", with: " ") ?? "error")
        }
        // Lo simulado lo dice delante, como las líneas de ejemplo de Ribera («Simulado: preparó…»).
        if c.simulado { texto = "Simulado: " + texto }
        var estadoDe: String?
        var estadoA: EstadoTarea?
        // Solo la tarea que es suya (`responsable: agente:<slug>`): una mención en una tarea de Manu no le cambia el estado.
        if c.estado == .completada, let t = tarea,
           DetectorDeDisparos.slug(snapshot.frontmatter(t).text("responsable")) == c.agente,
           let actual = snapshot.frontmatter(t).text("estado").flatMap(EstadoTarea.init(leyendo:)),
           actual == .porHacer || actual == .enCurso {
            estadoDe = actual.rawValue
            estadoA = .enRevision
        }
        var detalle: [String: String] = ["origen": c.origen, "estado_trabajo": c.estado.rawValue]
        if c.simulado { detalle["simulado"] = "si" }
        if let m = c.motivo { detalle["motivo"] = m.rawValue }
        if c.intento > 0 { detalle["intento"] = "\(c.intento)" }
        if let p = c.pregunta { detalle["pregunta"] = p }
        let frase = c.resumen.map { String(ActividadDeAsistenteFrase.primera(limpio($0)).prefix(200)) }
        return ResumenDeTrabajo(
            ejecucion: c.ejecucion, agente: c.agente, tarea: tarea, capacidad: c.capacidad, texto: texto,
            frase: frase.map { c.simulado ? "Simulado: " + $0 : $0 }, fin: fin, estadoDe: estadoDe, estadoA: estadoA,
            costeUSD: c.costeUSD > 0 ? c.costeUSD : nil, detalle: detalle)
    }

    /// Una línea, sin saltos ni marcas de comentario.
    static func limpio(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "<!--", with: "‹!--").replacingOccurrences(of: "-->", with: "--›")
            .trimmingCharacters(in: .whitespaces)
    }

    static func enlaceRelativo(desde origen: VaultPath, a destino: VaultPath) -> String {
        let a = Array(origen.components.dropLast())
        let b = destino.components
        var i = 0
        while i < a.count, i < b.count - 1, a[i] == b[i] { i += 1 }
        let camino = (Array(repeating: "..", count: a.count - i) + b[i...]).joined(separator: "/")
        return camino.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? camino
    }
}

/// Primera frase de un texto (para la Bitácora).
enum ActividadDeAsistenteFrase {
    static func primera(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: ". ") { return String(t[..<r.lowerBound]) }
        return t.hasSuffix(".") ? String(t.dropLast()) : t
    }
}

/// Registro en memoria (pruebas).
public final class RegistroEnMemoria: RegistroDeTrabajo, @unchecked Sendable {
    private let lock = NSLock()
    private var _cierres: [CierreDeTrabajo] = []
    public init() {}
    public func registrar(_ cierre: CierreDeTrabajo) async throws { lock.withLock { _cierres.append(cierre) } }
    public var cierres: [CierreDeTrabajo] { lock.withLock { _cierres } }
}
