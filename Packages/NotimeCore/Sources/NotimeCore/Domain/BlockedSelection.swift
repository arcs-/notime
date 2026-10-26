import Foundation
#if os(iOS)
@preconcurrency import ManagedSettings
#endif

/// What the user chose to block. Mirrors `FamilyActivitySelection` without depending on
/// FamilyControls (which pulls in SwiftUI), so the extensions stay small.
public struct BlockedSelection: Codable, Hashable, Sendable {
    /// ManagedSettings shields at most 50 apps and 50 websites per set; Notime caps the
    /// combined count so every selected item is really enforced. Categories don't count.
    public static let maximumIndividualItemCount = 50

    public var applicationTokens: Set<ApplicationToken>
    public var categoryTokens: Set<ActivityCategoryToken>
    public var webDomainTokens: Set<WebDomainToken>

    public init(
        applicationTokens: Set<ApplicationToken> = [],
        categoryTokens: Set<ActivityCategoryToken> = [],
        webDomainTokens: Set<WebDomainToken> = []
    ) {
        self.applicationTokens = applicationTokens
        self.categoryTokens = categoryTokens
        self.webDomainTokens = webDomainTokens
    }

    public var isEmpty: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    public var exceedsShieldLimit: Bool {
        applicationTokens.count + webDomainTokens.count > Self.maximumIndividualItemCount
    }
}
