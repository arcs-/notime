import Foundation

/// A repeating daily Device Activity whose only job is to wake the monitor extension, which
/// then reconciles (expires grants, re-shields, rolls past days into history) even if the app
/// is never opened again. Its name has no `grant-` prefix, so reconcile never stops it.
public enum SweepSchedule {
    public static let activityName = "sweep"
    /// Local midnight to 23:59 every day, following the device's time zone.
    public static let start = DateComponents(hour: 0, minute: 0)
    public static let end = DateComponents(hour: 23, minute: 59)
}
