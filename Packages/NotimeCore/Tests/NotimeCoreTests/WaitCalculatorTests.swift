#if !os(iOS)
import NotimeCore
import XCTest

final class WaitCalculatorTests: XCTestCase {
    func testDefaultsGrowByTenSecondsUpToThreeMinutes() {
        let seconds = [1, 2, 3, 15, 16, 100].map { WaitCalculator.waitSeconds(forOpeningNumber: $0, policy: BlockPolicy()) }
        XCTAssertEqual(seconds, [40, 50, 60, 180, 180, 180])
    }

    func testCapAppliesToLargeSettings() {
        let policy = BlockPolicy(waitSeconds: 300, addedWaitSecondsPerOpening: 300)
        XCTAssertEqual(WaitCalculator.waitSeconds(forOpeningNumber: 1, policy: policy), 180)
    }

    func testZeroAddedKeepsTheFirstWait() {
        let policy = BlockPolicy(waitSeconds: 30, addedWaitSecondsPerOpening: 0)
        XCTAssertEqual(WaitCalculator.waitSeconds(forOpeningNumber: 9, policy: policy), 30)
    }

    func testNoWaitAndNothingAddedMeansNoWait() {
        let policy = BlockPolicy(waitSeconds: 0, addedWaitSecondsPerOpening: 0)
        XCTAssertEqual(WaitCalculator.waitSeconds(forOpeningNumber: 3, policy: policy), 0)
    }

    func testNonPositiveOpeningNumberIsTreatedAsFirst() {
        XCTAssertEqual(WaitCalculator.waitSeconds(forOpeningNumber: 0, policy: BlockPolicy()), 40)
    }

    func testPolicyClampsOutOfRangeValuesAndHasTheDefaults() {
        let clamped = BlockPolicy(accessMinutes: 0, waitSeconds: 999, addedWaitSecondsPerOpening: -1)
        XCTAssertEqual([clamped.accessMinutes, clamped.waitSeconds, clamped.addedWaitSecondsPerOpening], [1, WaitCalculator.maximumWaitSeconds, 0])
        let defaults = BlockPolicy()
        XCTAssertEqual([defaults.accessMinutes, defaults.waitSeconds, defaults.addedWaitSecondsPerOpening], [12, 40, 10])
    }

    func testDescribesSecondsAndMinutes() {
        XCTAssertEqual(WaitCalculator.describe(seconds: 32), "32s")
        XCTAssertEqual(WaitCalculator.describe(seconds: 60), "1m")
        XCTAssertEqual(WaitCalculator.describe(seconds: 100), "1m 40s")
    }
}
#endif
