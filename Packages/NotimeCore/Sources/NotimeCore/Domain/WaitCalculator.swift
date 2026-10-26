/// Pure rule for the wait before the n-th opening of a target today (n from 1):
/// `min(wait + (n - 1) * addedPerOpening, maximumWaitSeconds)` seconds.
public enum WaitCalculator {
    /// The wait never grows beyond this; not a setting.
    public static let maximumWaitSeconds = 180

    public static func waitSeconds(forOpeningNumber openingNumber: Int, policy: BlockPolicy) -> Int {
        let furtherOpenings = max(openingNumber, 1) - 1
        let grown = policy.waitSeconds + furtherOpenings * policy.addedWaitSecondsPerOpening
        return min(grown, maximumWaitSeconds)
    }

    /// "40s", "1m", "1m 40s".
    public static func describe(seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        let remainder = seconds % 60
        return remainder == 0 ? "\(seconds / 60)m" : "\(seconds / 60)m \(remainder)s"
    }
}
