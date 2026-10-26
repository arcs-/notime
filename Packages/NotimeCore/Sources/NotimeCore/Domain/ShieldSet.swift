import Foundation
#if os(iOS)
@preconcurrency import ManagedSettings
#endif

/// The shields to apply for a state: everything selected except targets with an unexpired
/// grant. Granted apps and sites are also exempt from their category's shield. Pure, so it is
/// tested on the host; `ShieldApplier` only writes it to ManagedSettings.
public struct ShieldSet: Hashable, Sendable {
    public let applications: Set<ApplicationToken>
    public let webDomains: Set<WebDomainToken>
    public let categories: Set<ActivityCategoryToken>
    /// Granted apps, exempt from the category shield.
    public let applicationCategoryExceptions: Set<ApplicationToken>
    /// Granted sites, exempt from the category shield.
    public let webDomainCategoryExceptions: Set<WebDomainToken>

    public init(state: NotimeState, now: Date) {
        var grantedApplications = Set<ApplicationToken>()
        var grantedWebDomains = Set<WebDomainToken>()
        for grant in state.grants where grant.isActive(at: now) {
            switch grant.target {
            case .application(let token): grantedApplications.insert(token)
            case .webDomain(let token): grantedWebDomains.insert(token)
            }
        }
        let selection = state.selection
        applications = selection.applicationTokens.subtracting(grantedApplications)
        webDomains = selection.webDomainTokens.subtracting(grantedWebDomains)
        categories = selection.categoryTokens
        applicationCategoryExceptions = grantedApplications
        webDomainCategoryExceptions = grantedWebDomains
    }
}
