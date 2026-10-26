#if !os(iOS)
import Foundation
import NotimeCore
import XCTest

final class StateReconcilerTests: XCTestCase {
    private let calendar = TestFixtures.calendar
    private let now = TestFixtures.morning

    func testExpiredGrantsAreRemoved() {
        let state = NotimeState(grants: [
            AccessGrant(target: TestFixtures.app, grantedAt: now - 600, expiresAt: now - 1, activityName: "grant-old"),
            AccessGrant(target: TestFixtures.site, grantedAt: now - 60, expiresAt: now + 240, activityName: "grant-live"),
        ])
        let result = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: ["grant-old", "grant-live"])
        XCTAssertEqual(result.state.grants.map(\.activityName), ["grant-live"])
    }

    func testImpressionTimesOlderThanThirtySecondsAreDropped() {
        let state = NotimeState(lastImpressionAt: [TestFixtures.app: now - 30, TestFixtures.site: now - 29])
        let result = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: [])
        XCTAssertEqual(result.state.lastImpressionAt, [TestFixtures.site: now - 29])
    }

    func testStopsOnlyOrphanedGrantActivities() {
        let state = NotimeState(grants: [
            AccessGrant(target: TestFixtures.app, grantedAt: now, expiresAt: now + 300, activityName: "grant-live"),
        ])

        let result = StateReconciler.reconcile(
            state,
            now: now,
            calendar: calendar,
            monitoredActivityNames: ["grant-live", "grant-orphan", "someone-else", SweepSchedule.activityName]
        )

        XCTAssertEqual(result.orphanedActivityNames, ["grant-orphan"])
    }

    func testNoEffectsWhenNothingIsOrphaned() {
        let result = StateReconciler.reconcile(NotimeState(), now: now, calendar: calendar, monitoredActivityNames: [])
        XCTAssertEqual(result.orphanedActivityNames, [])
    }

    func testExpiredGrantActivityIsStopped() {
        let state = NotimeState(grants: [
            AccessGrant(target: TestFixtures.app, grantedAt: now - 600, expiresAt: now - 300, activityName: "grant-a"),
        ])
        let result = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: ["grant-a"])
        XCTAssertEqual(result.orphanedActivityNames, ["grant-a"])
    }

    func testUnmonitoredGrantIsEndedEvenBeforeItExpires() {
        let state = NotimeState(grants: [
            AccessGrant(target: TestFixtures.app, grantedAt: now - 120, expiresAt: now + 600, activityName: "grant-lost"),
            AccessGrant(target: TestFixtures.site, grantedAt: now - 120, expiresAt: now + 600, activityName: "grant-kept"),
        ])
        let result = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: ["grant-kept"])
        XCTAssertEqual(result.state.grants.map(\.activityName), ["grant-kept"])
    }

    func testUnmonitoredAndExpiredGrantIsEnded() {
        let state = NotimeState(grants: [
            AccessGrant(target: TestFixtures.app, grantedAt: now - 600, expiresAt: now - 1, activityName: "grant-gone"),
        ])
        XCTAssertEqual(StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: []).state.grants, [])
    }

    func testUnknownMonitoringOrAJustStartedGrantKeepsTheGrant() {
        let state = NotimeState(grants: [
            AccessGrant(target: TestFixtures.app, grantedAt: now - 120, expiresAt: now + 600, activityName: "grant-a"),
            AccessGrant(target: TestFixtures.site, grantedAt: now - 5, expiresAt: now + 600, activityName: "grant-new"),
        ])
        XCTAssertEqual(
            StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: nil).state.grants.count, 2,
            "the shield configuration extension does not know what is monitored"
        )
        XCTAssertEqual(
            StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: []).state.grants.map(\.activityName),
            ["grant-new"]
        )
    }

    func testOldLedgersArePruned() {
        var state = NotimeState()
        let today = DayKey(now, calendar: calendar)
        for offset in [0, -89, -90, -200] {
            state.recordShieldImpression(for: nil, on: today.adding(days: offset, calendar: calendar))
        }

        let result = StateReconciler.reconcile(state, now: now, calendar: calendar, monitoredActivityNames: [])

        XCTAssertEqual(result.state.ledgers.map(\.day), [today.adding(days: -89, calendar: calendar), today])
    }
}
#endif
