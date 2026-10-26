import Foundation

/// Port for the one place that computes and applies the shield set.
public protocol ShieldApplying {
    /// Shields everything selected except targets with an unexpired grant. Idempotent.
    func applyShields(for state: NotimeState, now: Date)
}
