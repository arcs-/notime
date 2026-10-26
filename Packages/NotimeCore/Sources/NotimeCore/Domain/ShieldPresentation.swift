import Foundation

/// What the shield says and its single button. Pure, so the copy is testable.
/// An app or site shield always offers "Open for N min"; the action extension is the gate.
public struct ShieldPresentation: Hashable, Sendable {
    public static let title = "notime"
    public static let unreadableStateBody = "Blocked. notime could not read its settings."
    public static let missingStateBody = "Blocked. Open notime once to finish setup."

    /// Category shields and token-less items: Notime never opens a whole category.
    public static let closeOnly = ShieldPresentation(body: "Blocked.", buttonTitle: "Close")

    public let body: String
    public let buttonTitle: String

    public init(body: String, buttonTitle: String) {
        self.body = body
        self.buttonTitle = buttonTitle
    }

    /// `target` is nil for category shields and token-less items: those are close-only.
    public static func make(
        for target: BlockedTarget?,
        in state: NotimeState,
        now: Date,
        calendar: Calendar
    ) -> ShieldPresentation {
        guard let target else { return closeOnly }
        let body: String
        if let wait = state.waitToOpen(for: target), case let remaining = wait.remainingSeconds(at: now), remaining > 0 {
            body = "wait \(WaitCalculator.describe(seconds: remaining))"
        } else {
            let openedToday = state.ledger(for: DayKey(now, calendar: calendar)).accessCount(for: target)
            body = "Blocked. Opened \(openedToday)× today."
        }
        return offeringAccess(body: body, policy: state.policy)
    }

    /// Used when the state could not be read: still offers to open, because the action
    /// extension refuses there if the state is still unreadable.
    public static func withoutState(for target: BlockedTarget?, body: String) -> ShieldPresentation {
        guard target != nil else { return closeOnly }
        return offeringAccess(body: body, policy: BlockPolicy())
    }

    private static func offeringAccess(body: String, policy: BlockPolicy) -> ShieldPresentation {
        ShieldPresentation(body: body, buttonTitle: "Open for \(policy.accessMinutes) min")
    }
}
