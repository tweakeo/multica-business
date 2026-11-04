import Foundation
import TLSCore
@testable import TLSIntegrations

/// Doble en memoria del Calendario del Mac. Nunca toca EventKit ni TCC. Se porta como EventKit en lo que importa:
/// la app no puede poner invitados (si un evento los tiene, es porque «Manu» los puso fuera), los identificadores los
/// da el almacén y de los otros calendarios guarda títulos y asistentes **para comprobar que no salen**.
final class AlmacenEnMemoria: AlmacenDeEventos, @unchecked Sendable {
    struct Calendario: Hashable {
        let id: String
        var titulo: String
    }

    /// Un evento de otro calendario, con todo lo que nunca debe salir.
    struct EventoAjeno: Hashable {
        let calendario: String
        let titulo: String
        let asistentes: [String]
        let inicio: Date
        let fin: Date
        var todoElDia = false
    }

    private let lock = NSLock()
    private var _permiso: PermisoCalendario
    private var _calendarios: [Calendario] = []
    private var _eventos: [String: EventoDelCalendario] = [:]
    private var _ajenos: [EventoAjeno] = []
    private var siguiente = 0
    /// Lo que la app pidió guardar (para comprobar que nunca pide invitados).
    private(set) var guardados: [EventoDelCalendario] = []
    private(set) var calendariosCreados = 0
    private(set) var retiradas: [String] = []

    init(permiso: PermisoCalendario = .concedido) {
        _permiso = permiso
    }

    private func c<T>(_ f: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try f()
    }

    // MARK: Para las pruebas

    var calendarios: [Calendario] { c { _calendarios } }
    var eventos: [EventoDelCalendario] { c { Array(_eventos.values).sorted { ($0.id ?? "") < ($1.id ?? "") } } }
    func ponerPermiso(_ p: PermisoCalendario) { c { _permiso = p } }

    @discardableResult
    func anadirCalendarioAjeno(_ titulo: String) -> String {
        c {
            siguiente += 1
            let id = "cal-\(siguiente)"
            _calendarios.append(Calendario(id: id, titulo: titulo))
            return id
        }
    }

    func anadirAjeno(_ e: EventoAjeno) { c { _ajenos.append(e) } }

    /// «Manu» cambia el evento en la app Calendario.
    func editarFuera(_ id: String, _ cambio: (inout EventoDelCalendario) -> Void) {
        c {
            guard var e = _eventos[id] else { return }
            cambio(&e)
            _eventos[id] = e
        }
    }

    /// «Manu» quita el evento en la app Calendario.
    func quitarFuera(_ id: String) { c { _eventos[id] = nil } }

    func evento(url: String) -> EventoDelCalendario? { c { _eventos.values.first { $0.url?.absoluteString == url } } }

    // MARK: AlmacenDeEventos

    func permiso() -> PermisoCalendario { c { _permiso } }

    func calendario(llamado nombre: String) throws -> String? {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario.sinPermiso }
            return _calendarios.first { $0.titulo == nombre }?.id
        }
    }

    func crearCalendario(llamado nombre: String) throws -> String {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario.sinPermiso }
            siguiente += 1
            calendariosCreados += 1
            let id = "cal-\(siguiente)"
            _calendarios.append(Calendario(id: id, titulo: nombre))
            return id
        }
    }

    func evento(id: String) throws -> EventoDelCalendario? { c { _eventos[id] } }

    func evento(url: URL, enCalendario calendario: String) throws -> EventoDelCalendario? {
        c { _eventos.values.first { $0.url == url && $0.calendario == calendario } }
    }

    func guardar(_ e: EventoDelCalendario, enCalendario calendario: String) throws -> String {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario.sinPermiso }
            guard _calendarios.contains(where: { $0.id == calendario }) else { throw ErrorDeCalendario("No existe ese calendario") }
            guardados.append(e)
            var nuevo = e
            let id: String
            if let i = e.id, let viejo = _eventos[i] {
                id = i
                nuevo.invitados = viejo.invitados   // la app no puede tocar invitados
            } else {
                siguiente += 1
                id = "ev-\(siguiente)"
                nuevo.invitados = 0
            }
            nuevo.id = id
            nuevo.calendario = calendario
            _eventos[id] = nuevo
            return id
        }
    }

    func retirar(id: String) throws {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario.sinPermiso }
            _eventos[id] = nil
            retiradas.append(id)
        }
    }

    func ocupado(desde: Date, hasta: Date, excepto: Set<String>) throws -> [BloqueOcupado] {
        try c {
            guard _permiso == .concedido else { throw ErrorDeCalendario.sinPermiso }
            let ajenos = _ajenos.filter { !excepto.contains($0.calendario) && $0.inicio < hasta && $0.fin > desde }
                .map { BloqueOcupado(inicio: $0.inicio, fin: $0.fin, todoElDia: $0.todoElDia) }
            // Lo nuestro también está en el almacén: solo sale si no se excluye.
            let propios = _eventos.values.filter { e in
                !excepto.contains(e.calendario ?? "") && e.repeticion == nil && e.inicio < hasta && e.fin > desde
            }.map { BloqueOcupado(inicio: $0.inicio, fin: $0.fin, todoElDia: $0.todoElDia) }
            return ajenos + propios
        }
    }
}

/// Copia de Asesoría Ribera (ficticia, `hoy: 2026-10-19`, lunes) en un temporal, con una rutina que pide Calendario,
/// un portal con su Viaje y un expediente privado de nombre neutro. Nunca se toca el ejemplo del repositorio.
struct CarpetaCalendario {
    static var riberaRepo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../../App/Recursos/Ejemplos/Asesoria-Ribera").standardizedFileURL
    }

    static let rutina = "1 · Dirección/Rutinas/revision-de-la-semana.md"
    static let portal = "3 · Entrega/Proyectos/Expediente de prueba/Portal.md"
    static let privada = "3 · Entrega/Expediente privado"
    static let portalPrivado = "3 · Entrega/Expediente privado/Portal.md"
    static let zona = TimeZone(identifier: "Europe/Madrid")!
    static let hoy = LocalDate(year: 2026, month: 10, day: 19)!

    let base: URL
    var root: URL { base.appendingPathComponent("Ribera", isDirectory: true) }

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("tls-cal-" + String(UUID().uuidString.lowercased().prefix(8)), isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.riberaRepo, to: root)
        // Lo privado (nombre neutro) marcado en la configuración de la copia.
        let config = url(".tls/config.yaml")
        let texto = try String(contentsOf: config, encoding: .utf8)
            .replacingOccurrences(of: "privado: []", with: "privado: [\"\(Self.privada)\"]")
        try texto.write(to: config, atomically: true, encoding: .utf8)
        try escribir(Self.rutina, Self.textoRutina())
        try escribir(Self.portal, Self.textoPortal(id: "portal-prueba", empresa: "Cliente de prueba"))
        try escribir(Self.portalPrivado, Self.textoPortal(id: "portal-privado", empresa: "Expediente privado"))
    }

    func url(_ p: String) -> URL { VaultPath(p).url(in: root) }

    func escribir(_ p: String, _ texto: String) throws {
        let u = url(p)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try texto.write(to: u, atomically: true, encoding: .utf8)
    }

    func leer(_ p: String) -> String? { try? String(contentsOf: url(p), encoding: .utf8) }

    /// Retirar = mover a `Archivo/<misma ruta>` (como `WriteOp.retire`).
    func retirar(_ p: String) throws {
        let destino = url("Archivo/" + p)
        try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url(p), to: destino)
    }

    var foto: VaultSnapshot { VaultSnapshot.read(root: root) }

    func borrar() { try? FileManager.default.removeItem(at: base) }

    static func textoRutina(dia: String = "lunes", hora: String = "9:00", duracion: Int = 45, calendario: Bool = true,
                            activa: Bool = true) -> String {
        """
        ---
        tls_type: routine
        tls_schema: 1
        id: "rutina-semana-prueba"
        nombre: "Revisión de la semana"
        area: "direccion"
        cadencia: semanal
        dia: \(dia)
        hora: \(hora)
        duracion_min: \(duracion)
        pregunta: "¿Qué decidí esta semana?"
        activa: \(activa)
        calendario: \(calendario)
        plantilla: "Rutina v1"
        ---
        # Revisión de la semana

        ## Pregunta
        ¿Qué decidí esta semana?

        """
    }

    static func textoPortal(id: String, empresa: String) -> String {
        """
        ---
        tls_type: portal
        tls_schema: 1
        id: "\(id)"
        empresa: "\(empresa)"
        estado: Publicado
        plantilla: "Portal v1"
        ---
        # Portal de \(empresa)

        ## Viaje
        | Sesión | Estado | Fecha | Resumen para el cliente | Nota interna |
        |---|---|---|---|---|
        | S1 · Arranque | Programada | 2026-10-21 10:00 | | |
        | S2 · Revisión | Pendiente | 2026-10-28 | | |
        | S3 · Cierre | No incluida | 2026-11-04 | | |
        | S4 · Seguimiento | Pendiente | | | |

        ## Tareas del cliente

        """
    }

    /// Una fecha en Madrid.
    static func fecha(_ d: Int, _ h: Int, _ m: Int = 0, mes: Int = 10) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zona
        return cal.date(from: DateComponents(year: 2026, month: mes, day: d, hour: h, minute: m))!
    }
}
