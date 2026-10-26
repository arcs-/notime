#if os(iOS)
import DeviceActivity
import Foundation
@preconcurrency import ManagedSettings

/// Starts one Device Activity per grant, with two independent ways to end it:
/// a usage threshold event (fires after N minutes of actual use) and a wall-clock
/// interval end (`AccessWindowSchedule`). Also starts the daily `SweepSchedule`.
public struct AccessWindowScheduler: AccessWindowScheduling {
    public init() {}

    public var monitoredActivityNames: Set<String> {
        Set(DeviceActivityCenter().activities.map(\.rawValue))
    }

    public func startMonitoring(
        _ grant: AccessGrant,
        accessWindowMinutes: Int,
        now: Date,
        calendar: Calendar
    ) throws {
        let window = AccessWindowSchedule(accessWindowMinutes: accessWindowMinutes, now: now, calendar: calendar)
        let schedule = DeviceActivitySchedule(intervalStart: window.start, intervalEnd: window.end, repeats: false)

        let threshold = DateComponents(minute: accessWindowMinutes)
        let event = Self.makeEvent(for: grant.target, threshold: threshold)

        try DeviceActivityCenter().startMonitoring(
            DeviceActivityName(grant.activityName),
            during: schedule,
            events: [DeviceActivityEvent.Name(grant.activityName): event]
        )
        NotimeLog.screenTime.info("Monitoring \(grant.activityName, privacy: .public) for \(window.intervalMinutes) min")
    }

    public func startSweepMonitoring() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: SweepSchedule.start,
            intervalEnd: SweepSchedule.end,
            repeats: true
        )
        try DeviceActivityCenter().startMonitoring(DeviceActivityName(SweepSchedule.activityName), during: schedule)
        NotimeLog.screenTime.info("Monitoring the daily sweep")
    }

    /// `includesPastActivity: false` (iOS 17.4+) so earlier use today doesn't count toward the threshold.
    private static func makeEvent(for target: BlockedTarget, threshold: DateComponents) -> DeviceActivityEvent {
        let applications: Set<ApplicationToken>
        let webDomains: Set<WebDomainToken>
        switch target {
        case .application(let token):
            applications = [token]
            webDomains = []
        case .webDomain(let token):
            applications = []
            webDomains = [token]
        }
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: applications,
                webDomains: webDomains,
                threshold: threshold,
                includesPastActivity: false
            )
        }
        return DeviceActivityEvent(applications: applications, webDomains: webDomains, threshold: threshold)
    }

    public func stopMonitoring(activityNames: Set<String>) {
        guard !activityNames.isEmpty else { return }
        DeviceActivityCenter().stopMonitoring(activityNames.map { DeviceActivityName($0) })
    }
}
#endif
