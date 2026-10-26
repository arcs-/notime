import Foundation
#if os(iOS)
@preconcurrency import ManagedSettings
#endif

/// A single app or website that can be shielded and temporarily opened.
/// Categories are intentionally not targets: access is never granted to a whole category.
public enum BlockedTarget: Codable, Hashable, Sendable {
    case application(ApplicationToken)
    case webDomain(WebDomainToken)
}
