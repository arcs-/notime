import Foundation

/// A target the user temporarily opened from the shield.
public struct AccessGrant: Codable, Hashable, Sendable {
    /// Every grant gets its own Device Activity name; reusing names stops thresholds from firing.
    public static let activityNamePrefix = "grant-"

    public let target: BlockedTarget
    public let grantedAt: Date
    public let expiresAt: Date
    public let activityName: String

    public init(target: BlockedTarget, grantedAt: Date, expiresAt: Date, activityName: String) {
        self.target = target
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.activityName = activityName
    }

    public static func makeActivityName() -> String {
        activityNamePrefix + UUID().uuidString
    }

    /// The access window this grant was given.
    public var accessWindow: TimeInterval {
        expiresAt.timeIntervalSince(grantedAt)
    }

    public func isActive(at now: Date) -> Bool {
        expiresAt > now
    }

    /// A usage threshold reported this early cannot be genuine: the target has not
    /// even existed unshielded for the access window (minus `tolerance`).
    public func isTooEarlyForUsageThreshold(at now: Date, tolerance: TimeInterval) -> Bool {
        now < grantedAt.addingTimeInterval(accessWindow - tolerance)
    }
}
