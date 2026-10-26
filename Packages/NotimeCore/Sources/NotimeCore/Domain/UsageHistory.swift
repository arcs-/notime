import Foundation

/// Past days' ledgers. Lives in its own file, written by the app and the monitor extension, so
/// the shield extensions (about 6 MB) only ever decode the small hot state.
public struct UsageHistory: Codable, Hashable, Sendable {
    /// Sorted by day, oldest first; at most one ledger per day.
    public private(set) var ledgers: [DailyUsageLedger]

    public init(ledgers: [DailyUsageLedger] = []) {
        self.ledgers = []
        merge(ledgers)
    }

    /// Adds the counts of `other` ledgers; a day already stored is summed, not replaced, so
    /// counts folded in after a day was rolled over are added to it.
    public mutating func merge(_ other: [DailyUsageLedger]) {
        for ledger in other {
            if let index = ledgers.firstIndex(where: { $0.day == ledger.day }) {
                ledgers[index].add(ledger)
            } else {
                ledgers.append(ledger)
            }
        }
        ledgers.sort { $0.day < $1.day }
    }

    public mutating func prune(today: DayKey, calendar: Calendar) {
        let oldestKept = DailyUsageLedger.oldestRetainedDay(today: today, calendar: calendar)
        ledgers.removeAll { $0.day < oldestKept }
    }
}
