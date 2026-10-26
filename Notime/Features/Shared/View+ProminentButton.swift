import SwiftUI

extension View {
    /// The one prominent button look: full width, at least 40 pt tall, 12 pt corners,
    /// background in the text colour and text in the background colour, so it inverts in dark mode.
    /// The label should use `.frame(maxWidth: .infinity, minHeight: 40)`.
    func prominentButton() -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(.primary)
            .foregroundStyle(Color(uiColor: .systemBackground))
    }
}
