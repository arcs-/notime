import Foundation

/// Statistics aggregated over a period, with targets ranked by shield impressions.
public struct UsageReport: Hashable, Sendable {
    public let totals: BlockStatistics
    public let statisticsByTarget: [BlockedTarget: BlockStatistics]
    public let targetsByImpressions: [BlockedTarget]

    /// Shields shown per day for the `dayCount` days ending today, oldest first, zeros included.
    public static func dailyShieldImpressions(
        ledgers: [DailyUsageLedger],
        dayCount: Int,
        today: DayKey,
        calendar: Calendar
    ) -> [(day: DayKey, shieldImpressions: Int)] {
        let byDay = Dictionary(ledgers.map { ($0.day, $0.totals.shieldImpressions) }, uniquingKeysWith: +)
        return (0..<dayCount).reversed().map { offset in
            let day = today.adding(days: -offset, calendar: calendar)
            return (day, byDay[day] ?? 0)
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
