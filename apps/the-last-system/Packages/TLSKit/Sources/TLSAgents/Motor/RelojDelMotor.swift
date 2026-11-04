import Foundation
import TLSCore

/// El reloj del motor (inyectado en todo: cola, reintentos, rutinas, uso, simulación).
public protocol RelojDelMotor: Sendable {
    func ahora() -> Date
}

extension RelojDelMotor {
    /// Día de hoy en la zona.
    public func hoy(zona: TimeZone) -> LocalDate { LocalDate(date: ahora(), timeZone: zona) }

    /// `AAAA-MM` en la zona.
    public func mes(zona: TimeZone) -> String {
        let d = hoy(zona: zona)
        return String(format: "%04d-%02d", d.year, d.month)
    }

    /// El `Reloj` de TLSCore para las escrituras (Actividad y Bitácora llevan la fecha y la hora de este reloj).
    public func relojDeEscritura(zona: TimeZone) -> Reloj {
        Reloj(hoy: hoy(zona: zona), ahora: ahora(), zona: zona)
    }
}

/// El del sistema.
public struct RelojDelSistema: RelojDelMotor {
    public init() {}
    public func ahora() -> Date { Date() }
}

/// Reloj de la demo: el día fijo de `hoy:` (Ribera: 2026-10-19) con la hora de verdad.
public struct RelojDeDemo: RelojDelMotor {
    public var hoy: LocalDate
    public var zona: TimeZone

    public init(hoy: LocalDate, zona: TimeZone) { self.hoy = hoy; self.zona = zona }

    public func ahora() -> Date {
        let real = Date()
        let medianoche = LocalDate(date: real, timeZone: zona).date(timeZone: zona)
        return hoy.date(timeZone: zona).addingTimeInterval(real.timeIntervalSince(medianoche))
    }
}

/// Reloj que solo avanza cuando se le dice (pruebas y los 14 días simulados).
public final class RelojManual: RelojDelMotor, @unchecked Sendable {
    private let lock = NSLock()
    private var actual: Date

    public init(_ inicio: Date) { actual = inicio }

    public func ahora() -> Date { lock.withLock { actual } }

    public func avanzar(_ segundos: TimeInterval) { lock.withLock { actual = actual.addingTimeInterval(segundos) } }

    public func fijar(_ fecha: Date) { lock.withLock { actual = fecha } }
}
