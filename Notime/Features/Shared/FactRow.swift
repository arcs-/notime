import SwiftUI

/// A name and a value on one row. The value is essential, so it is not dimmed,
/// and VoiceOver reads it as the row's value.
struct FactRow: View {
    let name: String
    let value: String

    init(_ name: String, value: String) {
        self.name = name
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(value).foregroundStyle(.primary)
        } label: {
            Text(name)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(value)
    }
}
