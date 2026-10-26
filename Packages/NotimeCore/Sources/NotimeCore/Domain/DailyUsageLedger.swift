import Foundation

/// Everything counted on one local day. A fresh day starts a fresh ledger, which is
/// what resets the growing wait at local midnight.
public struct DailyUsageLedger: Codable, Hashable, Sendable {
    /// How many days of ledgers are kept, today included.
    public static let retainedDayCount = 90
    /// How many days the extensions keep in the hot state, today included (today + 7).
    /// The shield extensions run in about 6 MB, so the file they decode stays small.
    public static let extensionRetainedDayCount = 8

    public let day: DayKey
    public private(set) var totals: BlockStatistics
    public private(set) var statisticsByTarget: [BlockedTarget: BlockStatistics]
    /// Keyed by the local hour of day (0...23) the count was recorded in. Counts recorded
    /// without an hour (older files, older fallback entries) are only in the totals.
    public private(set) var statisticsByHour: [Int: BlockStatistics]

    public init(day: DayKey) {
        self.day = day
        self.totals = BlockStatistics()
        self.statisticsByTarget = [:]
        self.statisticsByHour = [:]
    }

    /// Files written before hours were counted have no `statisticsByHour`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        day = try container.decode(DayKey.self, forKey: .day)
        totals = try container.decode(BlockStatistics.self, forKey: .totals)
        statisticsByTarget = try container.decode([BlockedTarget: BlockStatistics].self, forKey: .statisticsByTarget)
        statisticsByHour = try container.decodeIfPresent([Int: BlockStatistics].self, forKey: .statisticsByHour) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case day, totals, statisticsByTarget, statisticsByHour
    }

    /// The oldest day still kept when today is `today` and `dayCount` days are kept.
    public static func oldestRetainedDay(today: DayKey, calendar: Calendar, dayCount: Int = retainedDayCount) -> DayKey {
        today.adding(days: -(max(dayCount, 1) - 1), calendar: calendar)
    }

    /// Adds `other`'s counts for the same day to this ledger. Ledgers of other days are ignored.
    public mutating func add(_ other: DailyUsageLedger) {
        guard other.day == day else { return }
        totals = totals + other.totals
        statisticsByTarget.merge(other.statisticsByTarget, uniquingKeysWith: +)
        statisticsByHour.merge(other.statisticsByHour, uniquingKeysWith: +)
    }

    /// Accesses granted to `target` on this day; drives the growing wait.
    public func accessCount(for target: BlockedTarget) -> Int {
        statisticsByTarget[target]?.accessesGranted ?? 0
    }

    /// `target` is nil when the shield was for a category or a token-less item; `hour` is nil
    /// only for counts whose hour is unknown.
    public mutating func recordShieldImpression(for target: BlockedTarget?, hour: Int?) {
        totals.shieldImpressions += 1
        if let target {
            statisticsByTarget[target, default: BlockStatistics()].shieldImpressions += 1
        }
        if let hour {
            statisticsByHour[hour, default: BlockStatistics()].shieldImpressions += 1
        }
    }

    /// Returns the new access count for `target`.
    @discardableResult
    public mutating func recordAccessGranted(for target: BlockedTarget, hour: Int) -> Int {
        totals.accessesGranted += 1
        statisticsByTarget[target, default: BlockStatistics()].accessesGranted += 1
        statisticsByHour[hour, default: BlockStatistics()].accessesGranted += 1
        return accessCount(for: target)
    }

    /// Reverts `recordAccessGranted` for a grant that could not be monitored.
    public mutating func undoAccessGranted(for target: BlockedTarget, hour: Int) {
        guard accessCount(for: target) > 0 else { return }
        totals.accessesGranted -= 1
        statisticsByTarget[target, default: BlockStatistics()].accessesGranted -= 1
        if let accesses = statisticsByHour[hour]?.accessesGranted, accesses > 0 {
            statisticsByHour[hour]?.accessesGranted -= 1
        }
    }
}
