import SwiftUI

/// The notime mark shown in headers: the app icon's shield as a template image in the text
/// colour, with the hands transparent so the background shows through. Decorative; scales
/// with Dynamic Type.
struct AppMark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 32

    var body: some View {
        Image("ShieldMark")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: side, height: side)
            .padding(4)
            .accessibilityHidden(true)
    }
}
