import NotimeCore

/// One editable number on Home: its title, unit, allowed range and place in the policy.
enum PolicySetting: String, CaseIterable, Identifiable {
    case accessLength
    case wait
    case addedPerOpening

    var id: Self { self }

    var title: String {
        switch self {
        case .accessLength: "Access length"
        case .wait: "Wait before opening"
        case .addedPerOpening: "Added per opening"
        }
    }

    /// Short unit for rows ("min", "s"); `unitName` spells it out for the sheet.
    var unit: String { self == .accessLength ? "min" : "s" }
    var unitName: String { self == .accessLength ? "minutes" : "seconds" }

    var range: ClosedRange<Int> {
        switch self {
        case .accessLength: BlockPolicy.accessRange
        case .wait: BlockPolicy.waitRange
        case .addedPerOpening: BlockPolicy.addedWaitRange
        }
    }

    var keyPath: WritableKeyPath<BlockPolicy, Int> {
        switch self {
        case .accessLength: \.accessMinutes
        case .wait: \.waitSeconds
        case .addedPerOpening: \.addedWaitSecondsPerOpening
        }
    }
}
