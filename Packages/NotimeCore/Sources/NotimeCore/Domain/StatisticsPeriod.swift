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

    /// What the chart shows: today by hour, or the last few days by day. "All time" charts the
    /// last 30 days; its totals cover every day kept.
    public var chartSpan: ChartSpan {
        switch self {
        case .today: .hoursOfToday
        case .lastSevenDays: .days(7)
        case .allTime: .days(30)
        }
    }

    public enum ChartSpan: Hashable, Sendable {
        case hoursOfToday
        case days(Int)
    }

    public func includes(_ day: DayKey, today: DayKey, calendar: Calendar) -> Bool {
        switch self {
        case .today: day == today
        case .lastSevenDays: day >= today.adding(days: -6, calendar: calendar) && day <= today
        case .allTime: true
        }
    }
}
