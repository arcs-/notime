/// The result of a tap on "Open for N min".
public enum AccessGrantOutcome: Sendable {
    case granted
    /// Already open, monitoring failed, or the state is unavailable.
    case refused
    /// A wait before opening started or is still running; show the shield again.
    case waiting
}
