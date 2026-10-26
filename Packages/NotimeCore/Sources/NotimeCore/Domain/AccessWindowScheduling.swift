import Foundation

/// Port for the Device Activity monitoring that re-shields a target when its grant ends.
public protocol AccessWindowScheduling {
    /// Names of all activities currently monitored by this app.
    var monitoredActivityNames: Set<String> { get }
    func startMonitoring(_ grant: AccessGrant, accessWindowMinutes: Int, now: Date, calendar: Calendar) throws
    /// Starts the daily `SweepSchedule`.
    func startSweepMonitoring() throws
    /// Stops only the named activities; never stops everything.
    func stopMonitoring(activityNames: Set<String>)
}
