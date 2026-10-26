import Foundation

/// Statistics aggregated over a period, with targets ranked by shield impressions.
public struct UsageReport: Hashable, Sendable {
    public let totals: BlockStatistics
    public let statisticsByTarget: [BlockedTarget: BlockStatistics]
    public let targetsByImpressions: [BlockedTarget]

    /// Counts per local hour of `ledger`'s day, hours 0 through 23, zeros included.
    public static func hourlyStatistics(for ledger: DailyUsageLedger?) -> [(hour: Int, statistics: BlockStatistics)] {
        (0..<24).map { hour in (hour, ledger?.statisticsByHour[hour] ?? BlockStatistics()) }
    }

    /// Counts per day for the `dayCount` days ending today, oldest first, zeros included.
    public static func dailyStatistics(
        ledgers: [DailyUsageLedger],
        dayCount: Int,
        today: DayKey,
        calendar: Calendar
    ) -> [(day: DayKey, statistics: BlockStatistics)] {
        let byDay = Dictionary(ledgers.map { ($0.day, $0.totals) }, uniquingKeysWith: +)
        return (0..<dayCount).reversed().map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            return (day, byDay[day] ?? BlockStatistics())
        }
    }

    public init(ledgers: [DailyUsageLedger], period: StatisticsPeriod, today: DayKey, calendar: Calendar) {
        let included = ledgers.filter { period.includes($0.day, today: today, calendar: calendar) }
        totals = included.reduce(BlockStatistics()) { $0 + $1.totals }
        var byTarget: [BlockedTarget: BlockStatistics] = [:]
        for ledger in included {
            byTarget.merge(ledger.statisticsByTarget, uniquingKeysWith: +)
        }
        statisticsByTarget = byTarget
        targetsByImpressions = byTarget.sorted { lhs, rhs in
            if lhs.value.shieldImpressions != rhs.value.shieldImpressions {
                return lhs.value.shieldImpressions > rhs.value.shieldImpressions
            }
            return lhs.value.accessesGranted > rhs.value.accessesGranted
        }.map(\.key)
    }
}
