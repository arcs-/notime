#if !os(iOS)
import Foundation
import NotimeCore
import XCTest

final class DailyUsageLedgerTests: XCTestCase {
    private let calendar = TestFixtures.calendar

    func testCountsImpressionsAndAccessesPerTargetAndInTotal() {
        var ledger = DailyUsageLedger(day: DayKey(year: 2026, month: 10, day: 25))
        ledger.recordShieldImpression(for: TestFixtures.app)
        ledger.recordShieldImpression(for: TestFixtures.app)
        ledger.recordShieldImpression(for: nil)
        XCTAssertEqual(ledger.recordAccessGranted(for: TestFixtures.app), 1)
        XCTAssertEqual(ledger.recordAccessGranted(for: TestFixtures.app), 2)

        XCTAssertEqual(ledger.totals, BlockStatistics(shieldImpressions: 3, accessesGranted: 2))
        XCTAssertEqual(ledger.statisticsByTarget[TestFixtures.app], BlockStatistics(shieldImpressions: 2, accessesGranted: 2))
        XCTAssertEqual(ledger.accessCount(for: TestFixtures.site), 0)

        ledger.undoAccessGranted(for: TestFixtures.app)
        XCTAssertEqual(ledger.accessCount(for: TestFixtures.app), 1)
        XCTAssertEqual(ledger.totals.accessesGranted, 1)
    }

    func testDayKeyRollsOverAtLocalMidnight() {
        let beforeMidnight = TestFixtures.date(year: 2026, month: 10, day: 25, hour: 23, minute: 59)
        let afterMidnight = TestFixtures.date(year: 2026, month: 10, day: 26, hour: 0, minute: 1)
        XCTAssertEqual(DayKey(beforeMidnight, calendar: calendar), DayKey(year: 2026, month: 10, day: 25))
        XCTAssertEqual(DayKey(afterMidnight, calendar: calendar), DayKey(year: 2026, month: 10, day: 26))
    }

    func testDayKeyArithmeticCrossesMonthsAndDaylightSavingChanges() {
        let day = DayKey(year: 2026, month: 10, day: 25) // DST ends in Zurich on this day.
        XCTAssertEqual(day.adding(days: 1, calendar: calendar), DayKey(year: 2026, month: 10, day: 26))
        XCTAssertEqual(day.adding(days: 7, calendar: calendar), DayKey(year: 2026, month: 11, day: 1))
        XCTAssertEqual(day.adding(days: -89, calendar: calendar), DayKey(year: 2026, month: 7, day: 28))
    }

    func testEscalationResetsOnANewDay() {
        var state = NotimeState()
        let evening = TestFixtures.date(year: 2026, month: 10, day: 25, hour: 20)
        _ = state.grantAccess(to: TestFixtures.app, minutes: 5, now: evening, calendar: calendar, activityName: "grant-1")
        let secondEvening = evening.addingTimeInterval(3600)
        _ = state.grantAccess(to: TestFixtures.app, minutes: 5, now: secondEvening, calendar: calendar, activityName: "grant-2")
        XCTAssertEqual(state.ledger(for: DayKey(evening, calendar: calendar)).accessCount(for: TestFixtures.app), 2)

        let nextMorning = TestFixtures.date(year: 2026, month: 10, day: 26, hour: 8)
        let grant = state.grantAccess(to: TestFixtures.app, minutes: 5, now: nextMorning, calendar: calendar, activityName: "grant-3")

        XCTAssertNotNil(grant)
        XCTAssertEqual(state.ledger(for: DayKey(nextMorning, calendar: calendar)).accessCount(for: TestFixtures.app), 1)
        let openingNumber = state.ledger(for: DayKey(nextMorning, calendar: calendar)).accessCount(for: TestFixtures.app)
        XCTAssertEqual(WaitCalculator.waitSeconds(forOpeningNumber: openingNumber, policy: state.policy), 40, "the first opening of the day waits the first wait again")
    }

    func testPruningKeepsExactlyNinetyDays() {
        var state = NotimeState()
        let today = DayKey(year: 2026, month: 10, day: 25)
        for offset in 0..<120 {
            state.recordShieldImpression(for: nil, on: today.adding(days: -offset, calendar: calendar))
        }
        state.pruneLedgers(today: today, calendar: calendar)
        XCTAssertEqual(state.ledgers.count, 90)
        XCTAssertEqual(state.ledgers.first?.day, today.adding(days: -89, calendar: calendar))
        XCTAssertEqual(state.ledgers.last?.day, today)
    }

    func testAddSumsTotalsAndPerTargetCountsOfTheSameDayOnly() {
        let day = DayKey(year: 2026, month: 10, day: 24)
        var ledger = DailyUsageLedger(day: day)
        ledger.recordShieldImpression(for: TestFixtures.app)
        ledger.recordAccessGranted(for: TestFixtures.app)
        var other = DailyUsageLedger(day: day)
        other.recordShieldImpression(for: TestFixtures.app)
        other.recordShieldImpression(for: TestFixtures.site)
        other.recordShieldImpression(for: nil)

        ledger.add(other)
        ledger.add(DailyUsageLedger(day: day.adding(days: 1, calendar: calendar)))

        XCTAssertEqual(ledger.totals, BlockStatistics(shieldImpressions: 4, accessesGranted: 1))
        XCTAssertEqual(ledger.statisticsByTarget[TestFixtures.app], BlockStatistics(shieldImpressions: 2, accessesGranted: 1))
        XCTAssertEqual(ledger.statisticsByTarget[TestFixtures.site], BlockStatistics(shieldImpressions: 1, accessesGranted: 0))
    }

    func testHistoryMergeSumsTheSameDayAndPrunesToNinetyDays() {
        let today = DayKey(year: 2026, month: 10, day: 25)
        let yesterday = today.adding(days: -1, calendar: calendar)
        var rolledOver = DailyUsageLedger(day: yesterday)
        rolledOver.recordShieldImpression(for: TestFixtures.app)
        rolledOver.recordShieldImpression(for: TestFixtures.app)
        var lateImpression = DailyUsageLedger(day: yesterday)
        lateImpression.recordShieldImpression(for: TestFixtures.app)

        var history = UsageHistory(ledgers: [rolledOver, DailyUsageLedger(day: today.adding(days: -95, calendar: calendar))])
        history.merge([lateImpression])
        history.prune(today: today, calendar: calendar)

        XCTAssertEqual(history.ledgers.map(\.day), [yesterday])
        XCTAssertEqual(history.ledgers.first?.totals.shieldImpressions, 3, "a late impression adds to the day, it does not replace it")
        XCTAssertEqual(history.ledgers.first?.statisticsByTarget[TestFixtures.app]?.shieldImpressions, 3)
    }

    func testPruningKeepsTodayAndSevenDaysForExtensions() {
        var state = NotimeState()
        let today = DayKey(year: 2026, month: 10, day: 25)
        for offset in 0..<20 {
            state.recordShieldImpression(for: nil, on: today.adding(days: -offset, calendar: calendar))
        }
        state.pruneLedgers(today: today, calendar: calendar, keepingDays: DailyUsageLedger.extensionRetainedDayCount)
        XCTAssertEqual(state.ledgers.map(\.day), (0..<8).reversed().map { today.adding(days: -$0, calendar: calendar) })
    }
}
#endif
