import Foundation

public enum StatisticsPeriod: String, CaseIterable, Hashable, Sendable {
    case today
    case lastSevenDays
    case allTime

    public var title: String {
        switch self {
        case .today: "Today"
        case .lastSevenDays: "Last 7 days"
        case .allTime: "All time"
        }
    }

    /// Days in the chart. Counts are kept per day, so "Today" shows the last 7 days too.
    public var chartDayCount: Int {
        switch self {
        case .today, .lastSevenDays: 7
        case .allTime: 30
        }
    }

    public func includes(_ day: DayKey, today: DayKey, calendar: Calendar) -> Bool {
        switch self {
        case .today: day == today
        case .lastSevenDays: day >= today.adding(days: -6, calendar: calendar) && day <= today
        case .allTime: true
        }
    }
}
