#if !os(iOS)
import Foundation
import NotimeCore
import XCTest

final class NotimeServiceTests: XCTestCase {
    private var directory: URL!
    private var store: AppGroupStateStore!
    private var shields: RecordingShieldApplier!
    private var scheduler: FakeScheduler!
    private let calendar = TestFixtures.calendar
    private let now = TestFixtures.morning

    override func setUp() {
        directory = TestFixtures.temporaryDirectory()
        store = AppGroupStateStore(directory: directory, role: .app)
        shields = RecordingShieldApplier()
        shields.store = store
        scheduler = FakeScheduler()
        _ = store.modify {
            $0.selection = TestFixtures.selectionWithAppAndSite()
            // Opens for 1 minute; no wait unless a test sets one.
            $0.policy = BlockPolicy(accessMinutes: 1, waitSeconds: 0, addedWaitSecondsPerOpening: 0)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func service(
        at date: Date,
        store: (any StateStore)? = nil,
        calendar: Calendar? = nil,
        retainedHotDayCount: Int = DailyUsageLedger.retainedDayCount,
        fallback: ShieldSideEffectsFallback? = nil
    ) -> NotimeService {
        NotimeService(
            store: store ?? self.store,
            shields: shields,
            scheduler: scheduler,
            clock: FixedClock(date: date),
            calendar: calendar ?? self.calendar,
            sideEffectsFallback: fallback,
            retainedHotDayCount: retainedHotDayCount
        )
    }

    private var storedState: NotimeState? { store.load().loadedValue }

    private var todaysLedger: DailyUsageLedger? { storedState?.ledger(for: DayKey(now, calendar: calendar)) }

    // MARK: Granting

    func testGrantOpensTargetAndMonitorsIt() throws {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)

        let grant = try XCTUnwrap(storedState?.grants.first)
        XCTAssertEqual(grant.expiresAt, now + 60)
        XCTAssertTrue(grant.activityName.hasPrefix(AccessGrant.activityNamePrefix))
        XCTAssertEqual(scheduler.monitoredActivityNames, [grant.activityName])
        XCTAssertEqual(shields.appliedStates.last?.grants, [grant])
        XCTAssertEqual(todaysLedger?.accessCount(for: TestFixtures.app), 1)
    }

    func testStateIsSavedBeforeShieldsAreApplied() throws {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        let grant = try XCTUnwrap(storedState?.grants.first)
        XCTAssertEqual(shields.storedStatesAtApply.last?.grants, [grant])

        service(at: now + 60).accessWindowEnded(activityName: grant.activityName, trigger: .intervalEnded)
        XCTAssertEqual(shields.storedStatesAtApply.last?.grants, [])
    }

    func testEachGrantGetsItsOwnActivityAndDoesNotStopOthers() {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.site), .granted)
        XCTAssertEqual(Set(storedState?.grants.map(\.activityName) ?? []).count, 2)
        XCTAssertEqual(scheduler.monitoredActivityNames.count, 2)
    }

    func testOpenTargetIsRefused() {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(service(at: now + 30).grantAccess(to: TestFixtures.app), .refused)
    }

    func testGrantIsRevokedWhenMonitoringFails() throws {
        scheduler.shouldFail = true

        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .refused)

        let state = try XCTUnwrap(storedState)
        XCTAssertTrue(state.grants.isEmpty)
        XCTAssertEqual(state.ledger(for: DayKey(now, calendar: calendar)).accessCount(for: TestFixtures.app), 0)
        XCTAssertEqual(shields.appliedStates.last?.grants, [])
    }

    // MARK: Ending

    func testAccessWindowEndedReshieldsAndStopsTheActivity() throws {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        let activityName = try XCTUnwrap(storedState?.grants.first?.activityName)

        service(at: now + 60).accessWindowEnded(activityName: activityName, trigger: .usageThresholdReached)

        XCTAssertEqual(storedState?.grants, [])
        XCTAssertEqual(shields.appliedStates.last?.grants, [])
        XCTAssertTrue(scheduler.stoppedActivityNames.contains(activityName))
    }

    func testEarlyThresholdIsIgnoredButEarlyIntervalEndIsNot() throws {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        let activityName = try XCTUnwrap(storedState?.grants.first?.activityName)
        let applyCount = shields.appliedStates.count

        service(at: now + 10).accessWindowEnded(activityName: activityName, trigger: .usageThresholdReached)
        XCTAssertEqual(storedState?.grants.count, 1, "spurious threshold right after starting must be ignored")
        XCTAssertEqual(shields.appliedStates.count, applyCount)

        // Within the 30 s tolerance of the 1-minute window it counts.
        service(at: now + 40).accessWindowEnded(activityName: activityName, trigger: .usageThresholdReached)
        XCTAssertEqual(storedState?.grants, [])
    }

    func testIntervalEndIsHonouredEvenEarly() {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        let activityName = storedState?.grants.first?.activityName ?? ""
        service(at: now + 10).accessWindowEnded(activityName: activityName, trigger: .intervalEnded)
        XCTAssertEqual(storedState?.grants, [])
    }

    func testReconcileRecoversFromMissedCallbacks() {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        let state = service(at: now + 30 * 60).reconcile()
        XCTAssertEqual(state?.grants, [])
        XCTAssertTrue(scheduler.monitoredActivityNames.isEmpty)
        XCTAssertEqual(shields.appliedStates.last?.grants, [])
    }

    // MARK: Fail closed

    func testAppReplacesACorruptFileInsideReconcileAndReportsIt() throws {
        try Data("{ broken".utf8).write(to: XCTUnwrap(store.stateFileURL))
        var reported = false

        let state = service(at: now).reconcile(rollingOverHistory: true) { reported = true }

        XCTAssertEqual(state, NotimeState())
        XCTAssertTrue(reported)
        XCTAssertEqual(shields.appliedStates, [NotimeState()])
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.corruptStateFileURL), encoding: .utf8), "{ broken")
    }

    func testMissingContainerRefusesAccessAndSaysWhy() {
        let service = service(at: now, store: AppGroupStateStore(directory: nil, role: .app))

        XCTAssertNil(service.reconcile())
        XCTAssertEqual(service.grantAccess(to: TestFixtures.app), .refused)
        service.accessWindowEnded(activityName: "grant-x", trigger: .intervalEnded)
        XCTAssertNil(service.change { $0.selection = BlockedSelection() })
        XCTAssertEqual(service.prepareShield(for: TestFixtures.app), shieldWithoutState(ShieldPresentation.unreadableStateBody))
        XCTAssertTrue(shields.appliedStates.isEmpty)
        XCTAssertTrue(scheduler.monitoredActivityNames.isEmpty)
    }

    func testExtensionWithoutAStateFileNeverAppliesShields() {
        let service = service(at: now, store: AppGroupStateStore(directory: TestFixtures.temporaryDirectory(), role: .appExtension))

        XCTAssertNil(service.reconcile())
        XCTAssertEqual(service.grantAccess(to: TestFixtures.app), .refused)
        service.accessWindowEnded(activityName: "grant-x", trigger: .intervalEnded)
        XCTAssertEqual(service.prepareShield(for: TestFixtures.app), shieldWithoutState(ShieldPresentation.missingStateBody))
        XCTAssertTrue(shields.appliedStates.isEmpty)
    }

    func testExtensionWithACorruptFileRefusesAndLeavesTheFile() throws {
        try Data("{ broken".utf8).write(to: XCTUnwrap(store.stateFileURL))
        let service = service(at: now, store: AppGroupStateStore(directory: directory, role: .appExtension))

        XCTAssertNil(service.reconcile())
        XCTAssertEqual(service.grantAccess(to: TestFixtures.app), .refused, "the action refuses without readable state")
        XCTAssertEqual(service.prepareShield(for: TestFixtures.app), shieldWithoutState(ShieldPresentation.unreadableStateBody))
        XCTAssertTrue(shields.appliedStates.isEmpty)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.stateFileURL), encoding: .utf8), "{ broken")
    }

    func testExtensionWorksOnAValidStateFile() {
        let service = service(at: now, store: AppGroupStateStore(directory: directory, role: .appExtension))
        XCTAssertEqual(service.grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(shields.appliedStates.last?.selection, TestFixtures.selectionWithAppAndSite())
    }

    // MARK: Shield

    func testShieldShowsTodaysOpeningsAndCountsImpressions() {
        XCTAssertEqual(
            service(at: now).prepareShield(for: TestFixtures.app),
            ShieldPresentation(body: "Blocked. Opened 0× today.", buttonTitle: "Open for 1 min")
        )
        XCTAssertEqual(service(at: now + 10).grantAccess(to: TestFixtures.app), .granted)
        _ = service(at: now + 2 * 60).reconcile()
        XCTAssertEqual(service(at: now + 2 * 60).prepareShield(for: TestFixtures.app).body, "Blocked. Opened 1× today.")
        XCTAssertEqual(service(at: now + 2 * 60).prepareShield(for: nil), .closeOnly)
        XCTAssertEqual(todaysLedger?.totals.shieldImpressions, 3, "the tap 10 s after a counted shield adds nothing")
    }

    func testShieldWithoutStateStillOffersToOpenForAppsButNotCategories() {
        let presentation = shieldWithoutState(ShieldPresentation.missingStateBody)
        XCTAssertEqual(presentation.body, "Blocked. Open notime once to finish setup.")
        XCTAssertEqual(presentation.buttonTitle, "Open for 12 min")
        XCTAssertEqual(ShieldPresentation.withoutState(for: nil, body: ShieldPresentation.missingStateBody), .closeOnly)
    }

    func testAccessLengthComesFromSettings() {
        _ = store.modify { $0.policy.accessMinutes = 20 }
        XCTAssertEqual(service(at: now).prepareShield(for: TestFixtures.site).buttonTitle, "Open for 20 min")
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.site), .granted)
        XCTAssertEqual(storedState?.grants.first?.expiresAt, now + 20 * 60)
    }

    // MARK: Growing wait

    private func setWait(_ seconds: Int, added: Int = 0) {
        _ = store.modify {
            $0.policy.waitSeconds = seconds
            $0.policy.addedWaitSecondsPerOpening = added
        }
    }

    func testFirstTapStartsTheWaitAndDoesNotOpen() throws {
        setWait(100)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        let state = try XCTUnwrap(storedState)
        XCTAssertEqual(state.grants, [])
        XCTAssertEqual(state.waitToOpen(for: TestFixtures.app), WaitingToOpen(target: TestFixtures.app, startedAt: now, seconds: 100))
        XCTAssertEqual(
            service(at: now + 0.5).prepareShield(for: TestFixtures.app),
            ShieldPresentation(body: "wait 1m 40s", buttonTitle: "Open for 1 min")
        )
    }

    func testTapBeforeTheWaitIsOverShowsWhatIsLeft() {
        setWait(60)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(service(at: now + 23).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(service(at: now + 23).prepareShield(for: TestFixtures.app).body, "wait 37s")
        XCTAssertEqual(service(at: now + 59).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(storedState?.waitToOpen(for: TestFixtures.app)?.startedAt, now, "a tap does not restart the wait")
    }

    func testTapOnceTheWaitIsOverOpensAndClearsTheWait() throws {
        setWait(60)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(service(at: now + 60).grantAccess(to: TestFixtures.app), .granted)
        let state = try XCTUnwrap(storedState)
        XCTAssertEqual(state.grants.first?.expiresAt, now + 120)
        XCTAssertEqual(state.waitsToOpen, [])
    }

    func testWaitGrowsWithEachOpeningToday() throws {
        setWait(40, added: 60)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(service(at: now + 40).grantAccess(to: TestFixtures.app), .granted)
        let later = now + 10 * 60
        XCTAssertEqual(service(at: later).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(storedState?.waitToOpen(for: TestFixtures.app)?.seconds, 100)
        XCTAssertEqual(service(at: later + 99).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(service(at: later + 100).grantAccess(to: TestFixtures.app), .granted)
    }

    func testAbandonedWaitIsDroppedAndTheNextTapStartsOver() {
        setWait(60)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        service(at: now + 60 + 4 * 60).reconcile()
        XCTAssertNotNil(storedState?.waitToOpen(for: TestFixtures.app))
        let gone = now + 60 + 5 * 60
        service(at: gone).reconcile()
        XCTAssertNil(storedState?.waitToOpen(for: TestFixtures.app))
        XCTAssertEqual(service(at: gone).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(storedState?.waitToOpen(for: TestFixtures.app)?.startedAt, gone)
    }

    func testNoWaitOpensOnTheFirstTap() {
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(storedState?.waitsToOpen, [])
    }

    func testReconcileDropsAWaitOnceTheTargetIsOpen() {
        let state = NotimeState(
            grants: [AccessGrant(target: TestFixtures.app, grantedAt: now, expiresAt: now + 60, activityName: "grant-a")],
            waitsToOpen: [WaitingToOpen(target: TestFixtures.app, startedAt: now, seconds: 40)]
        )
        let reconciled = StateReconciler.reconcile(state, now: now + 1, calendar: calendar, monitoredActivityNames: nil).state
        XCTAssertEqual(reconciled.waitsToOpen, [])
    }

    // MARK: Impressions counted on taps

    func testTapWithoutARecordedShieldCountsOneImpression() {
        setWait(60)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(todaysLedger?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 1)
    }

    func testTapTenSecondsAfterARecordedShieldDoesNotDoubleCount() {
        _ = service(at: now).prepareShield(for: TestFixtures.app)
        XCTAssertEqual(service(at: now + 10).grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(todaysLedger?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 1)
    }

    func testTapSixtySecondsAfterARecordedShieldCounts() {
        _ = service(at: now).prepareShield(for: TestFixtures.app)
        XCTAssertEqual(service(at: now + 60).grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(todaysLedger?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 2)
    }

    func testTapAfterAShieldRecordedOnlyInTheFallbackDoesNotDoubleCount() {
        let fallback = ShieldSideEffectsFallback(defaults: TestFixtures.temporaryDefaults())
        fallback.recordShieldImpression(for: TestFixtures.app, at: now, calendar: calendar)
        let service = NotimeService(
            store: store, shields: shields, scheduler: scheduler, clock: FixedClock(date: now + 10), calendar: calendar,
            sideEffectsFallback: fallback
        )
        XCTAssertEqual(service.grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(todaysLedger?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 1)
    }

    // MARK: Shield that can't write the state file

    func testShieldRendersFromALockFreeReadAndReconcileFoldsItsCountIntoToday() throws {
        let fallback = ShieldSideEffectsFallback(defaults: TestFixtures.temporaryDefaults())
        let lockURL = directory.appendingPathComponent("state.lock")
        try? FileManager.default.removeItem(at: lockURL)
        try FileManager.default.createDirectory(at: lockURL, withIntermediateDirectories: true)

        let extensionService = NotimeService(
            store: AppGroupStateStore(directory: directory, role: .appExtension),
            shields: shields, scheduler: scheduler, clock: FixedClock(date: now), calendar: calendar,
            sideEffectsFallback: fallback
        )
        XCTAssertEqual(extensionService.prepareShield(for: TestFixtures.app).body, "Blocked. Opened 0× today.")

        try FileManager.default.removeItem(at: lockURL)
        let appService = NotimeService(
            store: store, shields: shields, scheduler: scheduler, clock: FixedClock(date: now + 1), calendar: calendar,
            sideEffectsFallback: fallback
        )
        let state = try XCTUnwrap(appService.reconcile(rollingOverHistory: true))
        XCTAssertEqual(state.ledger(for: DayKey(now, calendar: calendar)).statisticsByTarget[TestFixtures.app]?.shieldImpressions, 1)
        XCTAssertEqual(state.lastImpressionAt[TestFixtures.app], now)
        var empty = NotimeState()
        XCTAssertEqual(fallback.fold(into: &empty), [], "folded entries are cleared")
    }

    func testFoldingCountsRepeatedAndCategoryImpressions() {
        let fallback = ShieldSideEffectsFallback(defaults: TestFixtures.temporaryDefaults())
        fallback.recordShieldImpression(for: TestFixtures.site, at: now, calendar: calendar)
        fallback.recordShieldImpression(for: TestFixtures.site, at: now + 5, calendar: calendar)
        fallback.recordShieldImpression(for: nil, at: now, calendar: calendar)

        var state = NotimeState()
        let keys = fallback.fold(into: &state)

        let today = DayKey(now, calendar: calendar)
        XCTAssertEqual(keys.count, 3)
        XCTAssertEqual(state.ledger(for: today).totals.shieldImpressions, 3)
        XCTAssertEqual(state.ledger(for: today).statisticsByTarget[TestFixtures.site]?.shieldImpressions, 2)
        XCTAssertEqual(state.lastImpressionAt[TestFixtures.site], now + 5)
    }

    private func shieldWithoutState(_ body: String) -> ShieldPresentation {
        ShieldPresentation.withoutState(for: TestFixtures.app, body: body)
    }

    // MARK: History

    func testAppReconcileRollsPastLedgersIntoHistoryAndExtensionsDoNot() throws {
        let yesterday = now - 24 * 3600
        _ = service(at: yesterday).prepareShield(for: TestFixtures.app)
        _ = service(at: now).prepareShield(for: TestFixtures.site)

        service(at: now).reconcile()
        XCTAssertEqual(storedState?.ledgers.count, 2, "extension-style reconcile keeps history out")
        XCTAssertTrue(store.loadHistory().isEmpty)

        service(at: now).reconcile(rollingOverHistory: true)
        XCTAssertEqual(storedState?.ledgers.map(\.day), [DayKey(now, calendar: calendar)])
        XCTAssertEqual(store.loadHistory().loadedValue?.ledgers.map(\.day), [DayKey(yesterday, calendar: calendar)])

        let merged = service(at: now).statisticsLedgers()
        let report = UsageReport(ledgers: merged, period: .lastSevenDays, today: DayKey(now, calendar: calendar), calendar: calendar)
        XCTAssertEqual(report.totals.shieldImpressions, 2)
    }

    func testDailySeriesCoversEveryDayEndingTodayWithZeros() {
        let today = DayKey(now, calendar: calendar)
        var state = NotimeState()
        state.recordShieldImpression(for: TestFixtures.app, on: today)
        state.recordShieldImpression(for: TestFixtures.app, on: today)
        state.recordShieldImpression(for: nil, on: today.adding(days: -2, calendar: calendar))
        state.recordShieldImpression(for: nil, on: today.adding(days: -9, calendar: calendar))

        let series = UsageReport.dailyShieldImpressions(ledgers: state.ledgers, dayCount: 7, today: today, calendar: calendar)
        XCTAssertEqual(series.map(\.day), (0..<7).reversed().map { today.adding(days: -$0, calendar: calendar) })
        XCTAssertEqual(series.map(\.shieldImpressions), [0, 0, 0, 0, 1, 0, 2])
        XCTAssertEqual(StatisticsPeriod.allTime.chartDayCount, 30)
    }

    func testUsageReportRanksTargetsByImpressions() {
        var state = NotimeState()
        let today = DayKey(now, calendar: calendar)
        state.recordShieldImpression(for: TestFixtures.app, on: today)
        state.recordShieldImpression(for: TestFixtures.site, on: today)
        state.recordShieldImpression(for: TestFixtures.site, on: today.adding(days: -3, calendar: calendar))
        state.recordShieldImpression(for: TestFixtures.app, on: today.adding(days: -30, calendar: calendar))
        state.recordShieldImpression(for: TestFixtures.app, on: today.adding(days: -31, calendar: calendar))

        let week = UsageReport(ledgers: state.ledgers, period: .lastSevenDays, today: today, calendar: calendar)
        XCTAssertEqual(week.totals.shieldImpressions, 3)
        XCTAssertEqual(week.targetsByImpressions, [TestFixtures.site, TestFixtures.app])

        let allTime = UsageReport(ledgers: state.ledgers, period: .allTime, today: today, calendar: calendar)
        XCTAssertEqual(allTime.targetsByImpressions, [TestFixtures.app, TestFixtures.site])
    }

    // MARK: Pre-release review

    func testShieldReRenderedAfterATapThatStartsTheWaitCountsOnce() {
        setWait(60)
        _ = service(at: now).prepareShield(for: TestFixtures.app)
        XCTAssertEqual(service(at: now + 5).grantAccess(to: TestFixtures.app), .waiting)
        // `.defer` makes the system render the shield again, during the wait and past 30 s.
        XCTAssertEqual(service(at: now + 6).prepareShield(for: TestFixtures.app).body, "wait 59s")
        _ = service(at: now + 45).prepareShield(for: TestFixtures.app)
        XCTAssertEqual(todaysLedger?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 1)

        // Once the wait has run out, a shield shown again is a new block.
        _ = service(at: now + 2 * 60).prepareShield(for: TestFixtures.app)
        XCTAssertEqual(todaysLedger?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 2)
    }

    func testFallbackImpressionFoldedAfterRolloverAddsToThatDayInHistory() throws {
        let yesterday = now - 24 * 3600
        _ = service(at: yesterday).prepareShield(for: TestFixtures.app)
        _ = service(at: yesterday + 60).prepareShield(for: TestFixtures.app)
        service(at: now).reconcile(rollingOverHistory: true)
        let yesterdayKey = DayKey(yesterday, calendar: calendar)
        XCTAssertEqual(store.loadHistory().loadedValue?.ledgers.first?.totals.shieldImpressions, 2)

        // The shield could only write the fallback late yesterday; it is folded in today.
        let fallback = ShieldSideEffectsFallback(defaults: TestFixtures.temporaryDefaults())
        fallback.recordShieldImpression(for: TestFixtures.app, at: yesterday + 120, calendar: calendar)
        service(at: now, fallback: fallback).reconcile(rollingOverHistory: true)

        let history = try XCTUnwrap(store.loadHistory().loadedValue)
        XCTAssertEqual(history.ledgers.map(\.day), [yesterdayKey])
        XCTAssertEqual(history.ledgers.first?.totals.shieldImpressions, 3)
        let stats = service(at: now).statisticsLedgers()
        XCTAssertEqual(stats.first { $0.day == yesterdayKey }?.totals.shieldImpressions, 3)
    }

    func testShieldsAreAppliedUnderTheLockAndMonitoringStartsOutsideIt() throws {
        let lockPath = directory.appendingPathComponent("state.lock").path
        var lockHeldAtApply: [Bool] = []
        var lockHeldAtStart: [Bool] = []
        shields.onApply = { lockHeldAtApply.append(isLockHeld(at: lockPath)) }
        scheduler.onStart = { lockHeldAtStart.append(isLockHeld(at: lockPath)) }

        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        service(at: now).ensureSweepMonitoring()
        let activityName = try XCTUnwrap(storedState?.grants.first?.activityName)
        service(at: now + 60).accessWindowEnded(activityName: activityName, trigger: .intervalEnded)
        service(at: now + 60).change { $0.policy.accessMinutes = 3 }
        service(at: now + 60).reconcile()

        XCTAssertEqual(lockHeldAtApply, [true, true, true, true, true])
        XCTAssertEqual(lockHeldAtStart, [false, false], "grant monitoring and the sweep start without the lock")
    }

    func testTargetStaysShieldedUntilItsMonitoringRuns() throws {
        var grantsWhenMonitoringStarted: [AccessGrant]?
        scheduler.onStart = { grantsWhenMonitoringStarted = self.shields.appliedStates.last?.grants }
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        XCTAssertEqual(grantsWhenMonitoringStarted, [], "saved, but not unshielded before monitoring")
        XCTAssertEqual(shields.appliedStates.last?.grants, storedState?.grants)
    }

    func testRevokeRestoresTheFinishedWait() throws {
        setWait(60)
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .waiting)
        scheduler.shouldFail = true
        XCTAssertEqual(service(at: now + 60).grantAccess(to: TestFixtures.app), .refused)
        let state = try XCTUnwrap(storedState)
        XCTAssertEqual(state.grants, [])
        XCTAssertEqual(state.waitToOpen(for: TestFixtures.app), WaitingToOpen(target: TestFixtures.app, startedAt: now, seconds: 60))

        scheduler.shouldFail = false
        XCTAssertEqual(service(at: now + 61).grantAccess(to: TestFixtures.app), .granted, "no second wait")
    }

    func testShieldConfigurationNeverAppliesShields() {
        _ = service(at: now).prepareShield(for: TestFixtures.app)
        _ = service(at: now).prepareShield(for: nil)
        XCTAssertTrue(shields.appliedStates.isEmpty)
    }

    func testSweepIsStartedOnceAndNeverStoppedByReconcile() {
        let service = service(at: now)
        service.ensureSweepMonitoring()
        service.ensureSweepMonitoring()
        XCTAssertEqual(scheduler.sweepStartCount, 1)
        service.reconcile()
        XCTAssertTrue(scheduler.monitoredActivityNames.contains(SweepSchedule.activityName))
        XCTAssertFalse(scheduler.stoppedActivityNames.contains(SweepSchedule.activityName))
    }

    func testGrantWhoseMonitoringWasLostIsEndedAndReshielded() {
        _ = store.modify { $0.policy.accessMinutes = 60 }
        XCTAssertEqual(service(at: now).grantAccess(to: TestFixtures.app), .granted)
        scheduler.monitoredActivityNames.removeAll()

        let state = service(at: now + 5 * 60).reconcile()

        XCTAssertEqual(state?.grants, [], "nothing would re-shield it, so it ends before expiresAt")
        XCTAssertEqual(shields.appliedStates.last?.grants, [])
    }

    func testMonitorRollsPastDaysIntoHistoryAndShieldExtensionsKeepSevenDays() throws {
        let today = DayKey(now, calendar: calendar)
        _ = store.modify { state in
            for offset in 0..<20 {
                state.recordShieldImpression(for: nil, on: today.adding(days: -offset, calendar: calendar))
            }
        }
        let extensionStore = AppGroupStateStore(directory: directory, role: .appExtension)
        let limit = DailyUsageLedger.extensionRetainedDayCount

        // A shield render keeps today + 7 days and never writes history.
        _ = service(at: now, store: extensionStore, retainedHotDayCount: limit).prepareShield(for: TestFixtures.app)
        XCTAssertEqual(storedState?.ledgers.count, 8)
        XCTAssertEqual(storedState?.ledgers.first?.day, today.adding(days: -7, calendar: calendar))
        XCTAssertTrue(store.loadHistory().isEmpty)

        // The monitor rolls past days into history under the state lock.
        service(at: now, store: extensionStore, retainedHotDayCount: limit).reconcile(rollingOverHistory: true)
        XCTAssertEqual(storedState?.ledgers.map(\.day), [today])
        XCTAssertEqual(store.loadHistory().loadedValue?.ledgers.count, 7)
    }

    func testDayBoundaryFollowsTheInjectedCalendar() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        setWait(30, added: 30)
        // 23:50 in Los Angeles is already the next morning in Zurich.
        let lateEvening = try XCTUnwrap(losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 23, minute: 50)))

        XCTAssertEqual(service(at: lateEvening, calendar: losAngeles).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(service(at: lateEvening + 30, calendar: losAngeles).grantAccess(to: TestFixtures.app), .granted)
        let ledger = storedState?.ledger(for: DayKey(year: 2026, month: 10, day: 20))
        XCTAssertEqual(ledger?.accessCount(for: TestFixtures.app), 1)

        // After local midnight (00:10) the count starts over: the first wait again, not 60 s.
        let afterMidnight = lateEvening + 20 * 60
        XCTAssertEqual(service(at: afterMidnight, calendar: losAngeles).grantAccess(to: TestFixtures.app), .waiting)
        XCTAssertEqual(storedState?.waitToOpen(for: TestFixtures.app)?.seconds, 30)
        XCTAssertEqual(service(at: afterMidnight, calendar: losAngeles).today, DayKey(year: 2026, month: 10, day: 21))
    }
}
#endif
