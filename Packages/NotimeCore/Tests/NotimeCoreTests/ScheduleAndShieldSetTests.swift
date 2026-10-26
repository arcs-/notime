#if !os(iOS)
import Foundation
import NotimeCore
import XCTest

final class AccessWindowScheduleTests: XCTestCase {
    private let calendar = TestFixtures.calendar

    /// The instant the components name, in the time zone they carry.
    private func date(_ components: DateComponents) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(components.timeZone)
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func minutes(_ schedule: AccessWindowSchedule) throws -> Double {
        try date(schedule.end).timeIntervalSince(date(schedule.start)) / 60
    }

    func testIntervalIsAtLeastFifteenMinutesAfterTruncation() throws {
        let lateInTheMinute = TestFixtures.date(year: 2026, month: 10, day: 20, hour: 10, minute: 7) + 59
        for accessMinutes in [1, 5, 14, 15] {
            let schedule = AccessWindowSchedule(accessWindowMinutes: accessMinutes, now: lateInTheMinute, calendar: calendar)
            XCTAssertEqual(try minutes(schedule), 16)
            XCTAssertGreaterThanOrEqual(try minutes(schedule), 15)
        }
        let long = AccessWindowSchedule(accessWindowMinutes: 40, now: lateInTheMinute, calendar: calendar)
        XCTAssertEqual(try minutes(long), 41)
        XCTAssertEqual(long.start.minute, 7)
        XCTAssertNil(long.start.second)
        XCTAssertNotNil(long.start.timeZone)
    }

    func testIntervalCrossesMidnight() throws {
        let beforeMidnight = TestFixtures.date(year: 2026, month: 12, day: 31, hour: 23, minute: 55)
        let schedule = AccessWindowSchedule(accessWindowMinutes: 12, now: beforeMidnight, calendar: calendar)
        XCTAssertEqual(schedule.start.day, 31)
        XCTAssertEqual([schedule.end.year, schedule.end.month, schedule.end.day, schedule.end.hour, schedule.end.minute], [2027, 1, 1, 0, 11])
        XCTAssertEqual(try minutes(schedule), 16)
    }

    func testIntervalAcrossDaylightSavingChangesIsNeitherAmbiguousNorNegative() throws {
        // 2026-10-25 02:50 CEST, 16 minutes before 02:06 CET (clocks go back at 03:00).
        let fallBack = Date(timeIntervalSince1970: 1_792_889_400)
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: fallBack), DateComponents(hour: 2, minute: 50))
        let autumn = AccessWindowSchedule(accessWindowMinutes: 5, now: fallBack, calendar: calendar)
        XCTAssertEqual(try minutes(autumn), 16)
        XCTAssertEqual(try date(autumn.start), fallBack)

        // 2026-03-29 01:50 CET; 02:06 does not exist locally (clocks go forward at 02:00).
        let springForward = Date(timeIntervalSince1970: 1_774_745_400)
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: springForward), DateComponents(hour: 1, minute: 50))
        let spring = AccessWindowSchedule(accessWindowMinutes: 5, now: springForward, calendar: calendar)
        XCTAssertEqual(try minutes(spring), 16)
    }
}

final class ShieldSetTests: XCTestCase {
    private let now = TestFixtures.morning

    func testShieldsTheSelectionMinusUnexpiredGrants() {
        let state = NotimeState(
            selection: BlockedSelection(
                applicationTokens: [ApplicationToken("app"), ApplicationToken("other")],
                categoryTokens: [ActivityCategoryToken("games")],
                webDomainTokens: [WebDomainToken("site")]
            ),
            grants: [
                AccessGrant(target: TestFixtures.app, grantedAt: now - 60, expiresAt: now + 60, activityName: "grant-a"),
                AccessGrant(target: TestFixtures.site, grantedAt: now - 600, expiresAt: now - 1, activityName: "grant-s"),
            ]
        )
        let shields = ShieldSet(state: state, now: now)
        XCTAssertEqual(shields.applications, [ApplicationToken("other")])
        XCTAssertEqual(shields.webDomains, [WebDomainToken("site")], "an expired grant no longer exempts")
        XCTAssertEqual(shields.categories, [ActivityCategoryToken("games")])
        XCTAssertEqual(shields.applicationCategoryExceptions, [ApplicationToken("app")])
        XCTAssertEqual(shields.webDomainCategoryExceptions, [])
    }

    func testEmptySelectionShieldsNothing() {
        let shields = ShieldSet(state: NotimeState(), now: now)
        XCTAssertTrue(shields.applications.isEmpty && shields.webDomains.isEmpty && shields.categories.isEmpty)
    }
}
#endif
