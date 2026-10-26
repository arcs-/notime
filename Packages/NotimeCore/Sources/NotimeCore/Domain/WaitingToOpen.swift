import Foundation

/// The first tap on "Open" for a target started a wait of `seconds`; a tap once it is over opens.
public struct WaitingToOpen: Codable, Hashable, Sendable {
    /// A wait not used this long after it ended is dropped: the user left, the next tap starts over.
    public static let abandonedAfter: TimeInterval = 5 * 60

    public let target: BlockedTarget
    public let startedAt: Date
    public let seconds: Int

    public init(target: BlockedTarget, startedAt: Date, seconds: Int) {
        self.target = target
        self.startedAt = startedAt
        self.seconds = seconds
    }

    public func isAbandoned(at now: Date) -> Bool {
        now >= startedAt.addingTimeInterval(TimeInterval(seconds) + Self.abandonedAfter)
    }

    /// Whole seconds still to wait, rounded up; 0 when the wait is over.
    public func remainingSeconds(at now: Date) -> Int {
        let remaining = startedAt.addingTimeInterval(TimeInterval(seconds)).timeIntervalSince(now)
        return max(0, Int(remaining.rounded(.up)))
    }
}
