#if os(iOS)
import Foundation

extension NotimeService {
    /// The real service: app group JSON store, ManagedSettings shields, DeviceActivity monitoring.
    /// Pass `.app` only from the app; extensions pass `.appExtension`.
    public static func live(role: StateStoreRole) -> NotimeService {
        NotimeService(
            store: AppGroupStateStore.shared(role: role),
            shields: ShieldApplier(),
            scheduler: AccessWindowScheduler(),
            calendar: .autoupdatingCurrent,
            sideEffectsFallback: .shared(),
            retainedHotDayCount: role == .app
                ? DailyUsageLedger.retainedDayCount
                : DailyUsageLedger.extensionRetainedDayCount
        )
    }
}
#endif
