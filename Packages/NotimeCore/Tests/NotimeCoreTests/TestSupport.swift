#if !os(iOS)
import Foundation
import NotimeCore

struct FixedClock: Clock {
    let date: Date
    func now() -> Date { date }
}

final class RecordingShieldApplier: ShieldApplying, @unchecked Sendable {
    /// When set, the stored state is captured at the moment shields are applied. Read without
    /// the lock: shields are applied while the service holds it.
    var store: (any StateStore)?
    private(set) var appliedStates: [NotimeState] = []
    private(set) var storedStatesAtApply: [NotimeState] = []
    /// Runs on every apply, e.g. to check that the state lock is held.
    var onApply: (() -> Void)?

    func applyShields(for state: NotimeState, now: Date) {
        appliedStates.append(state)
        onApply?()
        if let store, case .loaded(let stored) = store.loadWithoutLock() {
            storedStatesAtApply.append(stored)
        }
    }
}

final class FakeScheduler: AccessWindowScheduling, @unchecked Sendable {
    struct Failure: Error {}
    var shouldFail = false
    var monitoredActivityNames: Set<String> = []
    private(set) var stoppedActivityNames: Set<String> = []
    private(set) var sweepStartCount = 0
    /// Runs on every start, e.g. to check that the state lock is not held.
    var onStart: (() -> Void)?

    func startMonitoring(_ grant: AccessGrant, accessWindowMinutes: Int, now: Date, calendar: Calendar) throws {
        onStart?()
        if shouldFail { throw Failure() }
        monitoredActivityNames.insert(grant.activityName)
    }

    func startSweepMonitoring() throws {
        onStart?()
        if shouldFail { throw Failure() }
        sweepStartCount += 1
        monitoredActivityNames.insert(SweepSchedule.activityName)
    }

    func stopMonitoring(activityNames: Set<String>) {
        stoppedActivityNames.formUnion(activityNames)
        monitoredActivityNames.subtract(activityNames)
    }
}

enum TestFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .gmt
        return calendar
    }()

    static let app = BlockedTarget.application(ApplicationToken("app"))
    static let site = BlockedTarget.webDomain(WebDomainToken("site"))

    /// 2026-10-25 10:00 local.
    static let morning = date(year: 2026, month: 10, day: 25, hour: 10)

    static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func selectionWithAppAndSite() -> BlockedSelection {
        BlockedSelection(applicationTokens: [ApplicationToken("app")], webDomainTokens: [WebDomainToken("site")])
    }

    /// A fresh, empty defaults suite; nothing else reads it.
    static func temporaryDefaults() -> UserDefaults {
        let name = "NotimeTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    static func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("NotimeTests-\(UUID().uuidString)")
    }
}

/// Whether another holder has the `flock` on `path` right now.
func isLockHeld(at path: String) -> Bool {
    let descriptor = open(path, O_RDWR)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    let gotLock = flock(descriptor, LOCK_EX | LOCK_NB) == 0
    if gotLock { flock(descriptor, LOCK_UN) }
    return !gotLock
}

extension LoadResult {
    var loadedValue: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }
}
#endif
