#if os(iOS)
import Foundation
@preconcurrency import ManagedSettings

/// The single place that writes shields. Always writes all four shield properties as whole
/// sets computed from state (`ShieldSet`), so calling it repeatedly is safe and self-healing.
public struct ShieldApplier: ShieldApplying {
    public static let storeName = ManagedSettingsStore.Name("art.stillh.notime.shields")

    public init() {}

    public func applyShields(for state: NotimeState, now: Date) {
        let shields = ShieldSet(state: state, now: now)
        let store = ManagedSettingsStore(named: Self.storeName)
        store.shield.applications = shields.applications.isEmpty ? nil : shields.applications
        store.shield.webDomains = shields.webDomains.isEmpty ? nil : shields.webDomains
        store.shield.applicationCategories = shields.categories.isEmpty
            ? nil
            : .specific(shields.categories, except: shields.applicationCategoryExceptions)
        store.shield.webDomainCategories = shields.categories.isEmpty
            ? nil
            : .specific(shields.categories, except: shields.webDomainCategoryExceptions)
        NotimeLog.screenTime.debug(
            "Shielding \(shields.applications.count) apps, \(shields.webDomains.count) domains, \(shields.categories.count) categories"
        )
    }
}
#endif
