import DeviceActivity
import NotimeCore

/// Re-shields a target when its grant's usage threshold is reached or its interval ends,
/// whichever comes first. Both paths run the same idempotent operation; the threshold path
/// additionally ignores spurious early events. The daily sweep's interval start and end run
/// the normal reconcile, which also rolls past days into history. Every callback makes sure
/// the sweep is monitored, so everything stays healthy without the app being opened.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let service = NotimeService.live(role: .appExtension)
        service.reconcile(rollingOverHistory: true)
        service.ensureSweepMonitoring()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let service = NotimeService.live(role: .appExtension)
        if activity.rawValue == SweepSchedule.activityName {
            service.reconcile(rollingOverHistory: true)
        } else {
            service.accessWindowEnded(activityName: activity.rawValue, trigger: .intervalEnded)
        }
        service.ensureSweepMonitoring()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let service = NotimeService.live(role: .appExtension)
        service.accessWindowEnded(activityName: activity.rawValue, trigger: .usageThresholdReached)
        service.ensureSweepMonitoring()
    }
}
