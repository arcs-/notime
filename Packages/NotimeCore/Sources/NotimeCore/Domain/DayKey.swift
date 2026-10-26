import Foundation

/// A local calendar day. Escalation and statistics are bucketed by it.
public struct DayKey: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 0, day: components.day ?? 0)
    }

    /// Noon of this day, which exists even on daylight-saving change days.
    public func noon(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    public func adding(days: Int, calendar: Calendar) -> DayKey {
        guard
            let noon = noon(in: calendar),
            let shifted = calendar.date(byAdding: .day, value: days, to: noon)
        else { return self }
        return DayKey(shifted, calendar: calendar)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
