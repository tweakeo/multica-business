import EventKit
import Foundation

/// El Calendario del Mac de verdad (EventKit). Lo usa la app; **las pruebas nunca lo crean** (usan un doble en memoria):
/// nada de TCC ni de EventKit real fuera de la app firmada.
///
/// - Acceso completo con `requestFullAccessToEvents()`, que lanza `PuertaDePermisos` (`.calendarios`) tras la explicación
///   (Info.plist ya declara `NSCalendarsFullAccessUsageDescription`). Aquí solo se mira el estado.
/// - Nuestro calendario «The Last System» va en iCloud si hay cuenta; si no, en «En mi Mac».
/// - Lo que se guarda **nunca lleva invitados** (EventKit tampoco deja ponerlos; aquí ni se intenta).
/// - De los demás calendarios solo salen bloques de ocupado: ni títulos, ni lugares, ni asistentes, ni notas.
public final class AlmacenEventKit: AlmacenDeEventos, @unchecked Sendable {
    private var _store: EKEventStore?
    /// El permiso con el que se creó `_store`: si cambia (Manu lo concede en la explicación o en Ajustes), se rehace,
    /// porque un `EKEventStore` creado sin permiso no ve los calendarios.
    private var creadoCon: EKAuthorizationStatus?
    private let lock = NSLock()

    public init() {}

    /// Solo dentro del cerrojo.
    private var store: EKEventStore {
        let ahora = EKEventStore.authorizationStatus(for: .event)
        if let s = _store, creadoCon == ahora { return s }
        let s = EKEventStore()
        _store = s
        creadoCon = ahora
        return s
    }

    private func conCerrojo<T>(_ cuerpo: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try cuerpo()
    }

    // MARK: Permiso

    public func permiso() -> PermisoCalendario {
        Self.traducir(EKEventStore.authorizationStatus(for: .event))
    }

    static func traducir(_ s: EKAuthorizationStatus) -> PermisoCalendario {
        switch s {
        case .notDetermined: .sinPreguntar
        case .fullAccess: .concedido
        case .writeOnly: .soloAnadir
        case .restricted: .restringido
        case .denied: .denegado
        @unknown default: .denegado
        }
    }

    // MARK: Calendarios

    public func calendario(llamado nombre: String) throws -> String? {
        conCerrojo {
            store.calendars(for: .event).first { $0.title == nombre && $0.allowsContentModifications }?.calendarIdentifier
        }
    }

    public func crearCalendario(llamado nombre: String) throws -> String {
        try conCerrojo {
            if let c = store.calendars(for: .event).first(where: { $0.title == nombre && $0.allowsContentModifications }) {
                return c.calendarIdentifier
            }
            let fuentes = store.sources
            let icloud = fuentes.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("iCloud") }
            let local = fuentes.first { $0.sourceType == .local }
            guard let fuente = icloud ?? local ?? store.defaultCalendarForNewEvents?.source else { throw ErrorDeCalendario.sinCuenta }
            let cal = EKCalendar(for: .event, eventStore: store)
            cal.title = nombre
            cal.source = fuente
            try store.saveCalendar(cal, commit: true)
            return cal.calendarIdentifier
        }
    }

    // MARK: Eventos

    public func evento(id: String) throws -> EventoDelCalendario? {
        conCerrojo { store.event(withIdentifier: id).map(Self.leer) }
    }

    public func evento(url: URL, enCalendario calendario: String) throws -> EventoDelCalendario? {
        conCerrojo {
            guard let cal = store.calendar(withIdentifier: calendario) else { return nil }
            let ahora = Date()
            let p = store.predicateForEvents(withStart: ahora.addingTimeInterval(-400 * 86_400),
                                             end: ahora.addingTimeInterval(400 * 86_400), calendars: [cal])
            guard let ocurrencia = store.events(matching: p).first(where: { $0.url == url }) else { return nil }
            // De una serie, el evento principal (el de la primera fecha).
            let principal = ocurrencia.eventIdentifier.flatMap { store.event(withIdentifier: $0) } ?? ocurrencia
            return Self.leer(principal)
        }
    }

    public func guardar(_ e: EventoDelCalendario, enCalendario calendario: String) throws -> String {
        try conCerrojo {
            guard let cal = store.calendar(withIdentifier: calendario) else {
                throw ErrorDeCalendario("No encuentro el calendario «The Last System».")
            }
            let ev = e.id.flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
            ev.calendar = cal
            ev.title = e.titulo
            ev.startDate = e.inicio
            ev.endDate = e.fin
            ev.isAllDay = e.todoElDia
            ev.url = e.url
            ev.notes = e.notas
            ev.availability = .busy
            ev.recurrenceRules = e.repeticion.map { [Self.regla($0)] }
            // Sin invitados: no hay nada que poner (invitar sería enviar).
            try store.save(ev, span: .futureEvents, commit: true)
            guard let id = ev.eventIdentifier else { throw ErrorDeCalendario("El Calendario no devolvió el evento guardado.") }
            return id
        }
    }

    public func retirar(id: String) throws {
        try conCerrojo {
            guard let ev = store.event(withIdentifier: id) else { return }
            try store.remove(ev, span: .futureEvents, commit: true)
        }
    }

    public func ocupado(desde: Date, hasta: Date, excepto: Set<String>) throws -> [BloqueOcupado] {
        conCerrojo {
            let cals = store.calendars(for: .event).filter { !excepto.contains($0.calendarIdentifier) && $0.type != .birthday }
            guard !cals.isEmpty, desde < hasta else { return [] }
            let p = store.predicateForEvents(withStart: desde, end: hasta, calendars: cals)
            // Solo cuándo: nada del título, del lugar, de las notas ni de los asistentes sale de aquí.
            return store.events(matching: p).filter { $0.availability != .free }.map {
                BloqueOcupado(inicio: $0.startDate, fin: $0.endDate, todoElDia: $0.isAllDay)
            }
        }
    }

    // MARK: Traducción

    static func leer(_ ev: EKEvent) -> EventoDelCalendario {
        EventoDelCalendario(id: ev.eventIdentifier, calendario: ev.calendar?.calendarIdentifier, titulo: ev.title ?? "",
                            inicio: ev.startDate, fin: ev.endDate, todoElDia: ev.isAllDay,
                            repeticion: ev.recurrenceRules?.first.flatMap { repeticion($0, inicio: ev.startDate) }, url: ev.url, notas: ev.notes,
                            invitados: ev.attendees?.count ?? 0)
    }

    /// 1 = lunes … 7 = domingo ↔ `EKWeekday` (1 = domingo … 7 = sábado).
    static func ekDia(_ d: Int) -> EKWeekday { EKWeekday(rawValue: d % 7 + 1) ?? .monday }
    static func diaSemana(_ w: EKWeekday) -> Int { w.rawValue == 1 ? 7 : w.rawValue - 1 }

    static func regla(_ r: RepeticionEvento) -> EKRecurrenceRule {
        switch r {
        case .semanal(let d):
            EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(ekDia(d))],
                             daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
                             setPositions: nil, end: nil)
        case .mensual(let dia, let cada):
            EKRecurrenceRule(recurrenceWith: .monthly, interval: max(1, cada), daysOfTheWeek: nil,
                             daysOfTheMonth: [NSNumber(value: dia)], monthsOfTheYear: nil, weeksOfTheYear: nil,
                             daysOfTheYear: nil, setPositions: nil, end: nil)
        }
    }

    /// Sin días explícitos (como lo deja a veces Calendario al editar), cuenta el día del inicio.
    static func repeticion(_ r: EKRecurrenceRule, inicio: Date) -> RepeticionEvento? {
        let cal = Calendar(identifier: .gregorian)
        switch r.frequency {
        case .weekly:
            let d = r.daysOfTheWeek?.first?.dayOfTheWeek ?? EKWeekday(rawValue: cal.component(.weekday, from: inicio))
            return d.map { .semanal(diaSemana: diaSemana($0)) }
        case .monthly:
            let d = r.daysOfTheMonth?.first?.intValue ?? cal.component(.day, from: inicio)
            return .mensual(diaMes: d, cadaMeses: r.interval)
        default:
            return nil
        }
    }
}
