/// Counters shown on the stats screen.
public struct BlockStatistics: Codable, Hashable, Sendable {
    public var shieldImpressions: Int
    public var accessesGranted: Int

    public init(shieldImpressions: Int = 0, accessesGranted: Int = 0) {
        self.shieldImpressions = shieldImpressions
        self.accessesGranted = accessesGranted
    }

    public static func + (lhs: BlockStatistics, rhs: BlockStatistics) -> BlockStatistics {
        BlockStatistics(
            shieldImpressions: lhs.shieldImpressions + rhs.shieldImpressions,
            accessesGranted: lhs.accessesGranted + rhs.accessesGranted
        )
    }
}
