#if !os(iOS)
/// Host-only stand-in for the Screen Time tokens, which are unavailable on macOS.
/// It exists so the pure domain compiles and is unit-tested with `swift test` on a Mac.
/// On iOS the real `ManagedSettings` token types are used instead.
public struct HostTokenStandIn: Codable, Hashable, Sendable {
    public let identifier: String

    public init(_ identifier: String) {
        self.identifier = identifier
    }
}

public typealias ApplicationToken = HostTokenStandIn
public typealias WebDomainToken = HostTokenStandIn
public typealias ActivityCategoryToken = HostTokenStandIn
#endif
