import Foundation

/// Brings persisted state back in line with the clock and with Device Activity. Pure; run on
/// every app foreground and every extension entry point.
public enum StateReconciler {
    /// A grant this young is kept even if its activity is not (yet) listed as monitored:
    /// monitoring starts right after the grant is saved and the lock is released.
    public static let unmonitoredGrantGracePeriod: TimeInterval = 60

    /// `monitoredActivityNames` is nil where the monitored activities are not known (the shield
    /// configuration extension); grants are then only expired by the clock.
    /// A grant whose activity is no longer monitored is ended even before its `expiresAt`:
    /// nothing would re-shield its target otherwise.
    /// Returns the `grant-` activities that no longer belong to a grant, to stop.
    public static func reconcile(
        _ state: NotimeState,
        now: Date,
        calendar: Calendar,
        monitoredActivityNames: Set<String>?
    ) -> (state: NotimeState, orphanedActivityNames: Set<String>) {
        var reconciled = state
        reconciled.grants.removeAll { grant in
            guard grant.isActive(at: now) else { return true }
            guard let monitoredActivityNames else { return false }
            let isYoung = now.timeIntervalSince(grant.grantedAt) < unmonitoredGrantGracePeriod
            return !isYoung && !monitoredActivityNames.contains(grant.activityName)
        }
        // A wait ends when the user left or once the target is open.
        let current = reconciled
        reconciled.waitsToOpen.removeAll { $0.isAbandoned(at: now) || current.activeGrant(for: $0.target, at: now) != nil }
        reconciled.lastImpressionAt = reconciled.lastImpressionAt.filter {
            now.timeIntervalSince($0.value) < NotimeState.impressionDeduplicationWindow
        }
        reconciled.pruneLedgers(today: DayKey(now, calendar: calendar), calendar: calendar)

        let grantActivityNames = Set(reconciled.grants.map(\.activityName))
        let orphanedActivityNames = (monitoredActivityNames ?? []).filter {
            $0.hasPrefix(AccessGrant.activityNamePrefix) && !grantActivityNames.contains($0)
        }
        return (reconciled, orphanedActivityNames)
    }
}
