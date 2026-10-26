import Foundation

/// Source of the current time, injected so time-dependent logic is testable.
public protocol Clock: Sendable {
    func now() -> Date
}
