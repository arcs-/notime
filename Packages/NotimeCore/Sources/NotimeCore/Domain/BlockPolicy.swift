import Foundation

/// User settings: how long an opening lasts and the wait before it, which grows with each
/// opening of the same app or site today.
public struct BlockPolicy: Codable, Hashable, Sendable {
    public static let accessRange: ClosedRange<Int> = 1...120
    /// Up to the cap, since a longer first wait would be cut to it anyway.
    public static let waitRange: ClosedRange<Int> = 0...WaitCalculator.maximumWaitSeconds
    public static let addedWaitRange: ClosedRange<Int> = 0...300

    /// "Open for N min" opens for this long.
    public var accessMinutes: Int {
        didSet { accessMinutes = accessMinutes.clamped(to: Self.accessRange) }
    }
    /// Wait before the first opening of a target today.
    public var waitSeconds: Int {
        didSet { waitSeconds = waitSeconds.clamped(to: Self.waitRange) }
    }
    /// Added to the wait for each further opening of the same target today.
    public var addedWaitSecondsPerOpening: Int {
        didSet { addedWaitSecondsPerOpening = addedWaitSecondsPerOpening.clamped(to: Self.addedWaitRange) }
    }

    public init(accessMinutes: Int = 12, waitSeconds: Int = 40, addedWaitSecondsPerOpening: Int = 10) {
        self.accessMinutes = accessMinutes.clamped(to: Self.accessRange)
        self.waitSeconds = waitSeconds.clamped(to: Self.waitRange)
        self.addedWaitSecondsPerOpening = addedWaitSecondsPerOpening.clamped(to: Self.addedWaitRange)
    }

    /// Missing keys fall back to the defaults; keys from earlier versions are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = BlockPolicy()
        self.init(
            accessMinutes: try container.decodeIfPresent(Int.self, forKey: .accessMinutes) ?? defaults.accessMinutes,
            waitSeconds: try container.decodeIfPresent(Int.self, forKey: .waitSeconds) ?? defaults.waitSeconds,
            addedWaitSecondsPerOpening: try container.decodeIfPresent(Int.self, forKey: .addedWaitSecondsPerOpening)
                ?? defaults.addedWaitSecondsPerOpening
        )
    }

    private enum CodingKeys: String, CodingKey {
        case accessMinutes, waitSeconds, addedWaitSecondsPerOpening
    }
}
