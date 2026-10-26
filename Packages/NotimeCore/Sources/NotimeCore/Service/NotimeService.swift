import Foundation

/// Every operation of the app and its extensions. Each one is a single locked
/// load-change-save; shields are applied and monitoring stopped right after the save, still
/// under the lock, so they always match the saved state. Monitoring is only ever started
/// outside the lock.
/// If the state can't be read, nothing is saved and the shields are left exactly as they are.
public struct NotimeService {
    /// Threshold events earlier than the access window minus this are treated as spurious
    /// (iOS 17/18 can fire them right after monitoring starts).
    public static let earlyThresholdTolerance: TimeInterval = 30

    private let store: any StateStore
    private let shields: any ShieldApplying
    private let scheduler: any AccessWindowScheduling
    private let clock: any Clock
    /// Impressions the shield could not save to the state file.
    private let sideEffectsFallback: ShieldSideEffectsFallback?
    /// Days of ledgers kept in the hot state, today included: 90 for the app, which rolls past
    /// days into history; 8 for the extensions, so the file the shield decodes stays small.
    private let retainedHotDayCount: Int
    public let calendar: Calendar

    public init(
        store: any StateStore,
        shields: any ShieldApplying,
        scheduler: any AccessWindowScheduling,
        clock: any Clock = SystemClock(),
        calendar: Calendar = .autoupdatingCurrent,
        sideEffectsFallback: ShieldSideEffectsFallback? = nil,
        retainedHotDayCount: Int = DailyUsageLedger.retainedDayCount
    ) {
        self.store = store
        self.shields = shields
        self.scheduler = scheduler
        self.clock = clock
        self.calendar = calendar
        self.sideEffectsFallback = sideEffectsFallback
        self.retainedHotDayCount = retainedHotDayCount
    }

    public var today: DayKey { DayKey(clock.now(), calendar: calendar) }

    /// Reads the hot state without changing anything.
    public func loadState() -> LoadResult<NotimeState> {
        store.load()
    }

    /// The last line of defence: fold in what the shield could not save, expire, prune,
    /// re-shield, stop orphaned monitoring. Only the app and the monitor extension pass
    /// `rollingOverHistory: true`; the shield extensions never touch history.
    /// `onCorruptFileReplaced` runs when (app only) a corrupt state file was moved aside and
    /// notime started fresh. Returns nil when the state is unavailable.
    @discardableResult
    public func reconcile(
        rollingOverHistory: Bool = false,
        onCorruptFileReplaced: () -> Void = {}
    ) -> NotimeState? {
        let now = clock.now()
        var foldedKeys: [String] = []
        var orphaned: Set<String> = []
        var replacedCorruptFile = false
        let state = store.modify({ state -> NotimeState in
            foldedKeys = sideEffectsFallback?.fold(into: &state) ?? []
            orphaned = reconcile(&state, now: now, monitored: scheduler.monitoredActivityNames, rollingOverHistory: rollingOverHistory)
            return state
        }, afterSave: { saved, replaced in
            replacedCorruptFile = replaced
            apply(shielding: saved, stopping: orphaned, now: now)
        })
        guard let state else {
            NotimeLog.service.error("Reconcile skipped, state unavailable; shields left as they are")
            return nil
        }
        sideEffectsFallback?.clear(foldedKeys)
        if replacedCorruptFile {
            onCorruptFileReplaced()
        }
        return state
    }

    /// Starts the daily `SweepSchedule` unless it is already monitored. Called by the app on
    /// every reconcile and by the monitor extension whenever it runs.
    public func ensureSweepMonitoring() {
        guard !scheduler.monitoredActivityNames.contains(SweepSchedule.activityName) else { return }
        do {
            try scheduler.startSweepMonitoring()
        } catch {
            NotimeLog.service.error("Daily sweep could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Handles "Open for N min". The first tap starts the wait for this opening (it grows with
    /// each opening today); a tap once it is over opens. Every tap also counts the shield as
    /// shown unless an impression of this target was counted within the last 30 s, because the
    /// configuration extension may not be able to save anything.
    /// Fails closed: if the state is unavailable nothing is opened, and if monitoring cannot
    /// start, nothing would re-shield the target, so the grant is revoked.
    ///
    /// Monitoring is started outside the state lock: if the system ever called the monitor
    /// extension synchronously from `startMonitoring`, that extension would wait for the same
    /// lock. Until monitoring runs the target stays shielded; the reconciler's grace period
    /// keeps the not-yet-monitored grant meanwhile.
    public func grantAccess(to target: BlockedTarget) -> AccessGrantOutcome {
        let now = clock.now()
        var foldedKeys: [String] = []
        var orphaned: Set<String> = []
        var newGrant: AccessGrant?
        var finishedWait: WaitingToOpen?
        let outcome = store.modify({ state -> AccessGrantOutcome in
            foldedKeys = sideEffectsFallback?.fold(into: &state) ?? []
            orphaned = reconcile(&state, now: now, monitored: scheduler.monitoredActivityNames)
            if !state.hasRecentImpression(of: target, at: now) {
                state.recordShieldImpression(for: target, at: now, calendar: calendar)
            }
            if mustWait(for: target, in: &state, now: now) {
                return .waiting
            }
            finishedWait = state.waitToOpen(for: target)
            newGrant = state.grantAccess(
                to: target,
                minutes: state.policy.accessMinutes,
                now: now,
                calendar: calendar,
                activityName: AccessGrant.makeActivityName()
            )
            return newGrant == nil ? .refused : .granted
        }, afterSave: { saved, _ in
            // The new grant does not unshield its target until its monitoring runs.
            var shielding = saved
            if let grant = newGrant {
                shielding.grants.removeAll { $0 == grant }
            }
            apply(shielding: shielding, stopping: orphaned, now: now)
        })
        guard let outcome else {
            NotimeLog.service.error("Open refused, state unavailable")
            return .refused
        }
        sideEffectsFallback?.clear(foldedKeys)
        guard let grant = newGrant else { return outcome }

        do {
            try scheduler.startMonitoring(
                grant,
                accessWindowMinutes: Int(grant.accessWindow / 60),
                now: now,
                calendar: calendar
            )
        } catch {
            NotimeLog.service.error("Monitoring could not start, open refused: \(error.localizedDescription, privacy: .public)")
            _ = store.modify({ state in
                state.revokeGrant(grant, calendar: calendar)
                // The wait was already served; the next tap opens without waiting again.
                if let finishedWait, state.waitToOpen(for: target) == nil {
                    state.waitsToOpen.append(finishedWait)
                }
            }, afterSave: { saved, _ in
                apply(shielding: saved, stopping: [], now: now)
            })
            return .refused
        }
        // Monitoring runs: unshield the target, from the state as saved now.
        _ = store.modify({ _ in }, afterSave: { saved, _ in
            apply(shielding: saved, stopping: [], now: now)
        })
        return .granted
    }

    /// A grant's usage threshold was reached or its wall-clock interval ended.
    public func accessWindowEnded(activityName: String, trigger: AccessWindowEndTrigger) {
        let now = clock.now()
        var orphaned: Set<String> = []
        var isIgnored = false
        let saved: Void? = store.modify({ state in
            if trigger == .usageThresholdReached,
               let grant = state.grants.first(where: { $0.activityName == activityName }),
               grant.isTooEarlyForUsageThreshold(at: now, tolerance: Self.earlyThresholdTolerance) {
                NotimeLog.service.notice("Ignoring early threshold for \(activityName, privacy: .public)")
                isIgnored = true
                return
            }
            state.endGrant(activityName: activityName)
            orphaned = reconcile(&state, now: now, monitored: scheduler.monitoredActivityNames)
        }, afterSave: { saved, _ in
            guard !isIgnored else { return }
            apply(shielding: saved, stopping: orphaned.union([activityName]), now: now)
        })
        if saved == nil {
            NotimeLog.service.error("Access window end not saved, state unavailable; shields left as they are")
        }
    }

    /// Builds the shield's content from a lock-free read, so rendering works even where the
    /// lock or file writes are denied. Only the state part of reconciliation runs, and no
    /// shields are ever applied from here: re-applying shields from inside the shield
    /// configuration extension could make the system re-render the shield and loop. Without
    /// readable state the shield still offers access for an app or site and says why it can't
    /// show more; the action extension then refuses.
    public func prepareShield(for target: BlockedTarget?) -> ShieldPresentation {
        let now = clock.now()
        let state: NotimeState
        switch store.loadWithoutLock() {
        case .loaded(let loaded):
            state = StateReconciler.reconcile(loaded, now: now, calendar: calendar, monitoredActivityNames: nil).state
        case .empty:
            return ShieldPresentation.withoutState(for: target, body: ShieldPresentation.missingStateBody)
        case .unavailable:
            return ShieldPresentation.withoutState(for: target, body: ShieldPresentation.unreadableStateBody)
        }
        let presentation = ShieldPresentation.make(for: target, in: state, now: now, calendar: calendar)
        recordShieldImpression(for: target, readState: state, now: now)
        return presentation
    }

    /// Applies a user change (selection, policy), reconciles, saves, then re-shields.
    @discardableResult
    public func change(_ change: (inout NotimeState) -> Void) -> NotimeState? {
        let now = clock.now()
        var orphaned: Set<String> = []
        return store.modify({ state -> NotimeState in
            change(&state)
            orphaned = reconcile(&state, now: now, monitored: scheduler.monitoredActivityNames)
            return state
        }, afterSave: { saved, _ in
            apply(shielding: saved, stopping: orphaned, now: now)
        })
    }

    /// App only: history and hot ledgers summed per day, for the stats screen.
    public func statisticsLedgers() -> [DailyUsageLedger] {
        var history = UsageHistory()
        if case .loaded(let stored) = store.loadHistory() {
            history = stored
        }
        if case .loaded(let state) = store.load() {
            history.merge(state.ledgers)
        }
        return history.ledgers
    }

    // MARK: Private

    /// The state part of every locked operation: reconcile, optionally roll past days into
    /// history, then cap the hot ledgers. Returns the orphaned activities to stop.
    private func reconcile(
        _ state: inout NotimeState,
        now: Date,
        monitored: Set<String>?,
        rollingOverHistory: Bool = false
    ) -> Set<String> {
        let result = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: monitored)
        state = result.state
        if rollingOverHistory {
            rollOverPastLedgers(of: &state, now: now)
        }
        state.pruneLedgers(today: DayKey(now, calendar: calendar), calendar: calendar, keepingDays: retainedHotDayCount)
        return result.orphanedActivityNames
    }

    /// Moves past days' ledgers into history (summed into any day already there). Runs inside
    /// the state lock, which serializes every history writer. They leave the hot state only
    /// once history is saved.
    private func rollOverPastLedgers(of state: inout NotimeState, now: Date) {
        let today = DayKey(now, calendar: calendar)
        let pastLedgers = state.ledgers.filter { $0.day != today }
        guard !pastLedgers.isEmpty else { return }
        let savedToHistory = store.modifyHistory { history -> Bool in
            history.merge(pastLedgers)
            history.prune(today: today, calendar: calendar)
            return true
        } ?? false
        if savedToHistory {
            state.ledgers.removeAll { $0.day != today }
        }
    }

    /// True while the target has to wait before this opening; the first tap starts the wait.
    /// An open target is not made to wait: `grantAccess` refuses it.
    private func mustWait(for target: BlockedTarget, in state: inout NotimeState, now: Date) -> Bool {
        guard state.activeGrant(for: target, at: now) == nil else { return false }
        if let wait = state.waitToOpen(for: target) {
            return wait.remainingSeconds(at: now) > 0
        }
        let openingNumber = state.ledger(for: DayKey(now, calendar: calendar)).accessCount(for: target) + 1
        let seconds = WaitCalculator.waitSeconds(forOpeningNumber: openingNumber, policy: state.policy)
        guard seconds > 0 else { return false }
        state.waitsToOpen.append(WaitingToOpen(target: target, startedAt: now, seconds: seconds))
        return true
    }

    /// Best effort: counts the impression in the state file, or in the shared-defaults fallback
    /// if that fails. If both are dropped, the action extension counts it on the next tap.
    /// Re-renders after a tap are not counted (`NotimeState.countsShieldImpression`).
    /// Never applies shields.
    private func recordShieldImpression(for target: BlockedTarget?, readState: NotimeState, now: Date) {
        let saved = store.modify { state -> Bool in
            state = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: nil).state
            if state.countsShieldImpression(of: target, at: now) {
                state.recordShieldImpression(for: target, at: now, calendar: calendar)
            }
            state.pruneLedgers(today: DayKey(now, calendar: calendar), calendar: calendar, keepingDays: retainedHotDayCount)
            return true
        }
        guard saved == nil else { return }
        guard readState.countsShieldImpression(of: target, at: now) else { return }
        NotimeLog.service.notice("Shield impression not saved to the state file; using shared defaults")
        sideEffectsFallback?.recordShieldImpression(for: target, at: now, calendar: calendar)
    }

    private func apply(shielding state: NotimeState, stopping activityNames: Set<String>, now: Date) {
        shields.applyShields(for: state, now: now)
        scheduler.stopMonitoring(activityNames: activityNames)
    }
}
