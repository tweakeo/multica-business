import Foundation

// F5 · rol calendario (PLAN §7.2, §9 F5 criterio 2). Todo lo del Calendario del Mac pasa por `AlmacenDeEventos`:
// la implementación de verdad es `AlmacenEventKit` (EventKit, `requestFullAccessToEvents()`); en las pruebas, un doble
// en memoria. Nada de este protocolo sabe escribir invitados: **invitar sería enviar** (PLAN §7.2), así que no se puede.

/// El permiso del Calendario (TCC), dicho sin jerga en la interfaz.
public enum PermisoCalendario: String, Sendable, Hashable, Codable {
    /// Aún no se ha pedido: antes de pedirlo, la app lo explica (PLAN §8, «Permisos»).
    case sinPreguntar
    case concedido
    case denegado
    /// Lo impide una política del Mac (control parental, gestión de la empresa).
    case restringido
    /// Solo puede añadir: no basta para leer lo ocupado ni para ver si cambiaste un evento.
    case soloAnadir

    public var permiteTrabajar: Bool { self == .concedido }

    /// Como lo cuenta Permisos (Conexiones y la recuperación): «solo añadir» no basta, cuenta como sin permiso.
    public var estadoDePermiso: EstadoDePermiso {
        switch self {
        case .sinPreguntar: .sinPreguntar
        case .concedido: .concedido
        case .denegado, .soloAnadir: .denegado
        case .restringido: .restringido
        }
    }
}

/// Cómo se repite un evento nuestro (rituales). Nunca hay fecha de fin: mientras la ficha siga, sigue.
public enum RepeticionEvento: Sendable, Hashable, Codable {
    /// Cada semana, ese día (1 = lunes … 7 = domingo).
    case semanal(diaSemana: Int)
    /// Cada `cadaMeses` meses (1: mensual; 3: trimestral), ese día del mes.
    case mensual(diaMes: Int, cadaMeses: Int)
}

/// Un evento de **nuestro** calendario («The Last System»), tal como se escribe o se lee.
public struct EventoDelCalendario: Sendable, Hashable {
    /// Identificador del almacén (`eventIdentifier`); `nil` antes de guardarlo.
    public var id: String?
    /// Calendario en el que está (identificador del almacén).
    public var calendario: String?
    public var titulo: String
    public var inicio: Date
    public var fin: Date
    public var todoElDia: Bool
    public var repeticion: RepeticionEvento?
    /// `tls://<tipo>/<id>`: de dónde sale (la ficha manda).
    public var url: URL?
    public var notas: String?
    /// Solo lectura: cuántos invitados tiene en el almacén. La app nunca los pone (siempre 0 en lo que escribe).
    public var invitados: Int

    public init(id: String? = nil, calendario: String? = nil, titulo: String, inicio: Date, fin: Date, todoElDia: Bool = false,
                repeticion: RepeticionEvento? = nil, url: URL? = nil, notas: String? = nil, invitados: Int = 0) {
        self.id = id; self.calendario = calendario; self.titulo = titulo; self.inicio = inicio; self.fin = fin
        self.todoElDia = todoElDia; self.repeticion = repeticion; self.url = url; self.notas = notas; self.invitados = invitados
    }

    /// Minutos que dura (0 si es de todo el día).
    public var minutos: Int { todoElDia ? 0 : max(0, Int((fin.timeIntervalSince(inicio) / 60).rounded())) }
}

/// Un rato ocupado de **otro** calendario. A propósito no tiene título, lugar, notas ni asistentes: de los demás
/// calendarios solo sale cuándo estás ocupado (PLAN §7.2 y §8, «filtros de calendario»).
public struct BloqueOcupado: Sendable, Hashable {
    public let inicio: Date
    public let fin: Date
    public let todoElDia: Bool

    public init(inicio: Date, fin: Date, todoElDia: Bool = false) {
        self.inicio = inicio; self.fin = fin; self.todoElDia = todoElDia
    }
}

/// Lo que la app necesita del Calendario del Mac. Inyectable: `AlmacenEventKit` de verdad, un doble en las pruebas.
public protocol AlmacenDeEventos: Sendable {
    /// El permiso tal como está ahora (no pregunta nada). Pedirlo es cosa de `PuertaDePermisos` (`.calendarios`),
    /// siempre después de la explicación.
    func permiso() -> PermisoCalendario
    /// El calendario con ese nombre, si existe (su identificador).
    func calendario(llamado nombre: String) throws -> String?
    /// Crea un calendario con ese nombre en la cuenta de iCloud si la hay; si no, en la local.
    func crearCalendario(llamado nombre: String) throws -> String
    /// Un evento por su identificador (`nil` si ya no está).
    func evento(id: String) throws -> EventoDelCalendario?
    /// El evento de ese calendario cuya `url` es esa (por si el identificador cambió al sincronizar iCloud).
    func evento(url: URL, enCalendario calendario: String) throws -> EventoDelCalendario?
    /// Guarda (crea o cambia, la serie entera si se repite) **sin invitados**. Devuelve el identificador.
    func guardar(_ evento: EventoDelCalendario, enCalendario calendario: String) throws -> String
    /// Quita el evento (la serie entera si se repite).
    func retirar(id: String) throws
    /// Lo ocupado en los demás calendarios (sin los de `excepto`), sin títulos ni asistentes.
    func ocupado(desde: Date, hasta: Date, excepto: Set<String>) throws -> [BloqueOcupado]
}

/// Error del Calendario, dicho para personas.
public struct ErrorDeCalendario: Error, Sendable, Hashable, LocalizedError {
    public let mensaje: String
    public init(_ mensaje: String) { self.mensaje = mensaje }
    public var errorDescription: String? { mensaje }

    static let sinPermiso = ErrorDeCalendario("El Calendario no tiene permiso para The Last System.")
    static let sinCuenta = ErrorDeCalendario("No encuentro dónde crear el calendario «The Last System» en este Mac.")
}
