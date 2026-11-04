import Foundation

/// Fecha de calendario sin hora, en hora local.
///
/// La única forma de escribir fechas en la carpeta es `AAAA-MM-DD`. Nunca
/// `toISOString()`: desplazaba días en Madrid. Al leer se toleran los restos
/// heredados `2026-09-10T22:00:00.000Z`, que se convierten a la fecha local.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        guard (1...12).contains(month), (1...31).contains(day),
              let date = Self.gregorian(.current).date(from: c),
              Self.gregorian(.current).component(.day, from: date) == day
        else { return nil }
        self.year = year; self.month = month; self.day = day
    }

    public init(date: Date, timeZone: TimeZone = .current) {
        let c = Self.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.year = c.year!; self.month = c.month!; self.day = c.day!
    }

    /// Acepta `AAAA-MM-DD`, `DD/MM/AAAA` y la forma heredada ISO con hora y zona.
    public init?(parsing text: String, timeZone: TimeZone = .current) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count == 10, s[s.index(s.startIndex, offsetBy: 4)] == "-" {
            let p = s.split(separator: "-").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            self.init(year: p[0], month: p[1], day: p[2])
            return
        }
        if s.count == 10, s[s.index(s.startIndex, offsetBy: 2)] == "/" {
            let p = s.split(separator: "/").compactMap { Int($0) }
            guard p.count == 3 else { return nil }
            self.init(year: p[2], month: p[1], day: p[0])
            return
        }
        if s.count > 10, s.contains("T") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let fallback = ISO8601DateFormatter()
            if let d = iso.date(from: s) ?? fallback.date(from: s) {
                self.init(date: d, timeZone: timeZone)
                return
            }
            // Sin zona: se toma la parte de fecha tal cual.
            self.init(parsing: String(s.prefix(10)), timeZone: timeZone)
            return
        }
        return nil
    }

    public static func today(timeZone: TimeZone = .current, now: Date = Date()) -> LocalDate {
        LocalDate(date: now, timeZone: timeZone)
    }

    /// Medianoche local de este día.
    public func date(timeZone: TimeZone = .current) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return Self.gregorian(timeZone).date(from: c)!
    }

    public func adding(days: Int, timeZone: TimeZone = .current) -> LocalDate {
        let d = Self.gregorian(timeZone).date(byAdding: .day, value: days, to: date(timeZone: timeZone))!
        return LocalDate(date: d, timeZone: timeZone)
    }

    /// 1 = lunes … 7 = domingo.
    public var weekday: Int {
        let w = Self.gregorian(.current).component(.weekday, from: date())
        return w == 1 ? 7 : w - 1
    }

    public var isWeekend: Bool { weekday >= 6 }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let d = LocalDate(parsing: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Fecha no válida: \(s)"))
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }

    private static func gregorian(_ tz: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        return cal
    }
}
