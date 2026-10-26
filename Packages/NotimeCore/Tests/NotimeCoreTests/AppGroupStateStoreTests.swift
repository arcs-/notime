#if !os(iOS)
import Foundation
import NotimeCore
import XCTest

final class AppGroupStateStoreTests: XCTestCase {
    private var directory: URL!
    private var store: AppGroupStateStore!

    override func setUpWithError() throws {
        directory = TestFixtures.temporaryDirectory().appendingPathComponent("nested")
        store = AppGroupStateStore(directory: directory, role: .app)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
        }
    }

    private func writeRawState(_ text: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: XCTUnwrap(store.stateFileURL))
    }

    func testRoundTripPreservesEveryField() {
        let now = TestFixtures.morning
        var state = NotimeState(
            policy: BlockPolicy(accessMinutes: 7, waitSeconds: 10, addedWaitSecondsPerOpening: 20),
            selection: TestFixtures.selectionWithAppAndSite()
        )
        state.lastImpressionAt[TestFixtures.site] = now
        state.waitsToOpen = [WaitingToOpen(target: TestFixtures.app, startedAt: now, seconds: 40)]
        _ = state.grantAccess(to: TestFixtures.app, minutes: 5, now: now, calendar: TestFixtures.calendar, activityName: "grant-x")
        state.recordShieldImpression(for: TestFixtures.site, on: DayKey(now, calendar: TestFixtures.calendar))

        XCTAssertNotNil(store.modify { $0 = state })

        XCTAssertEqual(store.load().loadedValue, state)
    }

    func testMissingFileIsEmptyAndModifyStartsFresh() {
        XCTAssertTrue(store.load().isEmpty)
        let policy = store.modify { state -> BlockPolicy in state.policy }
        XCTAssertEqual(policy, BlockPolicy())
        XCTAssertEqual(store.load().loadedValue, NotimeState())
    }

    func testAppModifyMovesACorruptFileAsideAndStartsFresh() throws {
        try writeRawState("{ not json")
        var replaced: Bool?

        let accessMinutes = store.modify({ state -> Int in
            state.policy.accessMinutes = 9
            return state.policy.accessMinutes
        }, afterSave: { _, replacedCorruptFile in replaced = replacedCorruptFile })

        XCTAssertEqual(accessMinutes, 9, "the change runs on a fresh state")
        XCTAssertEqual(replaced, true)
        let corruptURL = try XCTUnwrap(store.corruptStateFileURL)
        XCTAssertEqual(try String(contentsOf: corruptURL, encoding: .utf8), "{ not json")
        XCTAssertEqual(store.load().loadedValue?.policy.accessMinutes, 9)
    }

    func testAfterSaveRunsWithTheSavedStateOnlyWhenSaved() {
        var saved: NotimeState?
        _ = store.modify({ $0.policy.accessMinutes = 7 }, afterSave: { state, replaced in
            saved = state
            XCTAssertFalse(replaced)
        })
        XCTAssertEqual(saved?.policy.accessMinutes, 7)

        var ran = false
        let missing = AppGroupStateStore(directory: nil, role: .app)
        XCTAssertNil(missing.modify({ _ in }, afterSave: { _, _ in ran = true }))
        XCTAssertFalse(ran)
    }

    func testUnreadableFileIsUnavailableAndLeftUntouched() throws {
        try writeRawState(#"{"policy":{"accessMinutes":9}}"#)
        let stateURL = try XCTUnwrap(store.stateFileURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: stateURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stateURL.path) }

        XCTAssertTrue(store.load().isUnavailable)
        var changeRan = false
        XCTAssertNil(store.modify { _ in changeRan = true })
        XCTAssertFalse(changeRan)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: stateURL.path)
        XCTAssertEqual(store.load().loadedValue?.policy.accessMinutes, 9)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.corruptStateFileURL).path))
    }

    func testAppReportsTheResetWhenItMovesACorruptFileAside() throws {
        try writeRawState("{ not json")
        guard case .unavailable(let error) = store.load() else { return XCTFail("expected unavailable") }
        XCTAssertEqual(error as? AppGroupStateStore.StoreError, .corruptFileMovedAside)
    }

    func testExtensionLeavesACorruptFileInPlaceAndStaysUnavailable() throws {
        try writeRawState("{ not json")
        let extensionStore = AppGroupStateStore(directory: directory, role: .appExtension)

        XCTAssertTrue(extensionStore.load().isUnavailable)
        XCTAssertNil(extensionStore.modify { $0.policy.accessMinutes = 9 })
        XCTAssertTrue(extensionStore.load().isUnavailable, "still unavailable: nothing was moved")

        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.stateFileURL), encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.corruptStateFileURL).path))
    }

    func testExtensionNeverStartsFreshWhenTheFileIsMissing() throws {
        let extensionStore = AppGroupStateStore(directory: directory, role: .appExtension)
        var changeRan = false
        XCTAssertNil(extensionStore.modify { _ in changeRan = true })
        XCTAssertFalse(changeRan)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(store.stateFileURL).path))
    }

    func testMissingContainerIsUnavailable() {
        let store = AppGroupStateStore(directory: nil, role: .app)
        XCTAssertTrue(store.load().isUnavailable)
        XCTAssertTrue(store.loadHistory().isUnavailable)
        XCTAssertNil(store.modify { _ in () })
        XCTAssertNil(store.modifyHistory { _ in () })
    }

    func testMissingKeysFallBackToDefaults() throws {
        try writeRawState(#"{"policy":{"accessMinutes":9}}"#)
        let loaded = try XCTUnwrap(store.load().loadedValue)
        XCTAssertEqual(loaded.policy.accessMinutes, 9)
        XCTAssertEqual(loaded.policy.addedWaitSecondsPerOpening, 10)
        XCTAssertTrue(loaded.grants.isEmpty)
    }

    func testPolicyFromEarlierVersionsDecodesToTheNewDefaults() throws {
        try writeRawState(#"""
        {"policy":{"initialBlockMinutes":5,"maxCooldownMinutes":60,"shortAccessMinutes":3,"maxWaitSeconds":900},
         "cooldowns":[{"x":1}],"lastShieldRendering":[]}
        """#)
        XCTAssertEqual(try XCTUnwrap(store.load().loadedValue).policy, BlockPolicy())
    }

    func testLockFreeReadNeverRecoversOrWrites() throws {
        try writeRawState("{ not json")
        XCTAssertTrue(store.loadWithoutLock().isUnavailable)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(store.stateFileURL), encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("state.lock").path))
    }

    func testConcurrentModificationsAreSerializedByTheLock() {
        let day = DayKey(year: 2026, month: 10, day: 25)
        let store = self.store!
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            // A separate store value per thread, like separate processes, sharing only the files.
            let independentStore = AppGroupStateStore(directory: store.directory, role: .app)
            _ = independentStore.modify { $0.recordShieldImpression(for: nil, on: day) }
        }
        XCTAssertEqual(store.load().loadedValue?.ledger(for: day).totals.shieldImpressions, 64)
    }

    func testHistoryRoundTripIsSeparateFromState() {
        let ledger = DailyUsageLedger(day: DayKey(year: 2026, month: 10, day: 24))
        XCTAssertTrue(store.loadHistory().isEmpty)
        XCTAssertNotNil(store.modifyHistory { $0.merge([ledger]) })
        XCTAssertEqual(store.loadHistory().loadedValue?.ledgers, [ledger])
        XCTAssertTrue(store.load().isEmpty)
    }
}
#endif
