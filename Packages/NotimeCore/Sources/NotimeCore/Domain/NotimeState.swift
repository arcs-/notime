import Foundation

/// The single source of truth ("hot state"), persisted as one small JSON file shared by the
/// app and its extensions. Past days' ledgers move to `UsageHistory` when the app or the monitor
/// extension reconciles.
public struct NotimeState: Codable, Hashable, Sendable {
    /// A tap within this long after a counted impression of the same target is the same shield.
    public static let impressionDeduplicationWindow: TimeInterval = 30

    public var policy: BlockPolicy
    public var selection: BlockedSelection
    public var grants: [AccessGrant]
    /// Today's ledger plus any past days not yet rolled into history. Sorted, oldest first.
    public var ledgers: [DailyUsageLedger]
    /// When an impression was last counted per target; the reconciler drops old entries.
    public var lastImpressionAt: [BlockedTarget: Date]
    /// Targets whose first "Open" tap started a wait, at most one per target.
    public var waitsToOpen: [WaitingToOpen]

    public init(
        policy: BlockPolicy = BlockPolicy(),
        selection: BlockedSelection = BlockedSelection(),
        grants: [AccessGrant] = [],
        ledgers: [DailyUsageLedger] = [],
        lastImpressionAt: [BlockedTarget: Date] = [:],
        waitsToOpen: [WaitingToOpen] = []
    ) {
        self.policy = policy
        self.selection = selection
        self.grants = grants
        self.ledgers = ledgers
        self.lastImpressionAt = lastImpressionAt
        self.waitsToOpen = waitsToOpen
    }

    /// Tolerates missing keys so a newer or older file never wipes everything.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        policy = try container.decodeIfPresent(BlockPolicy.self, forKey: .policy) ?? BlockPolicy()
        selection = try container.decodeIfPresent(BlockedSelection.self, forKey: .selection) ?? BlockedSelection()
        grants = try container.decodeIfPresent([AccessGrant].self, forKey: .grants) ?? []
        ledgers = try container.decodeIfPresent([DailyUsageLedger].self, forKey: .ledgers) ?? []
        lastImpressionAt = try container.decodeIfPresent([BlockedTarget: Date].self, forKey: .lastImpressionAt) ?? [:]
        waitsToOpen = try container.decodeIfPresent([WaitingToOpen].self, forKey: .waitsToOpen) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case policy, selection, grants, ledgers, lastImpressionAt, waitsToOpen
    }

    // MARK: Queries

    public func activeGrant(for target: BlockedTarget, at now: Date) -> AccessGrant? {
        grants.first { $0.target == target && $0.isActive(at: now) }
    }

    public func waitToOpen(for target: BlockedTarget) -> WaitingToOpen? {
        waitsToOpen.first { $0.target == target }
    }

    public func ledger(for day: DayKey) -> DailyUsageLedger {
        ledgers.first { $0.day == day } ?? DailyUsageLedger(day: day)
    }

    public func hasRecentImpression(of target: BlockedTarget, at now: Date) -> Bool {
        guard let last = lastImpressionAt[target] else { return false }
        return now.timeIntervalSince(last) < Self.impressionDeduplicationWindow
    }

    // MARK: Mutations

    /// Counts a shield shown on `now`'s day and remembers when, per target.
    public mutating func recordShieldImpression(for target: BlockedTarget?, at now: Date, calendar: Calendar) {
        recordShieldImpression(for: target, on: DayKey(now, calendar: calendar))
        if let target {
            lastImpressionAt[target] = max(lastImpressionAt[target] ?? now, now)
        }
    }

    public mutating func recordShieldImpression(for target: BlockedTarget?, on day: DayKey) {
        updateLedger(for: day) { $0.recordShieldImpression(for: target) }
    }

    /// Opens `target` for `minutes`. Returns nil (and changes nothing) while it is already open.
    public mutating func grantAccess(
        to target: BlockedTarget,
        minutes: Int,
        now: Date,
        calendar: Calendar,
        activityName: String
    ) -> AccessGrant? {
        guard activeGrant(for: target, at: now) == nil else { return nil }
        updateLedger(for: DayKey(now, calendar: calendar)) { $0.recordAccessGranted(for: target) }
        let grant = AccessGrant(
            target: target,
            grantedAt: now,
            expiresAt: now.addingTimeInterval(TimeInterval(minutes * 60)),
            activityName: activityName
        )
        waitsToOpen.removeAll { $0.target == target }
        grants.removeAll { $0.target == target }
        grants.append(grant)
        return grant
    }

    /// Ends the grant monitored under `activityName`, whether or not its wall-clock window has passed.
    public mutating func endGrant(activityName: String) {
        grants.removeAll { $0.activityName == activityName }
    }

    /// Undoes `grantAccess` (grant and access count) for a grant whose monitoring could not start.
    public mutating func revokeGrant(_ grant: AccessGrant, calendar: Calendar) {
        guard grants.contains(grant) else { return }
        grants.removeAll { $0 == grant }
        updateLedger(for: DayKey(grant.grantedAt, calendar: calendar)) { $0.undoAccessGranted(for: grant.target) }
    }

    /// Drops ledgers older than the last `dayCount` days (today included).
    public mutating func pruneLedgers(
        today: DayKey,
        calendar: Calendar,
        keepingDays dayCount: Int = DailyUsageLedger.retainedDayCount
    ) {
        let oldestKept = DailyUsageLedger.oldestRetainedDay(today: today, calendar: calendar, dayCount: dayCount)
        ledgers.removeAll { $0.day < oldestKept }
    }

    /// True while `target`'s wait before opening is still running.
    public func isWaiting(toOpen target: BlockedTarget, at now: Date) -> Bool {
        (waitToOpen(for: target)?.remainingSeconds(at: now) ?? 0) > 0
    }

    /// Whether a shield render for `target` is a new block shown. Re-renders the system asks
    /// for after a tap (`.defer`) are not: there is an impression within the last 30 s or the
    /// target's wait is running. Category and token-less shields (`nil`) always count.
    public func countsShieldImpression(of target: BlockedTarget?, at now: Date) -> Bool {
        guard let target else { return true }
        return !hasRecentImpression(of: target, at: now) && !isWaiting(toOpen: target, at: now)
    }

    private mutating func updateLedger(for day: DayKey, _ change: (inout DailyUsageLedger) -> Void) {
        if let index = ledgers.firstIndex(where: { $0.day == day }) {
            change(&ledgers[index])
        } else {
            var ledger = DailyUsageLedger(day: day)
            change(&ledger)
            ledgers.append(ledger)
            ledgers.sort { $0.day < $1.day }
        }
    }
}
