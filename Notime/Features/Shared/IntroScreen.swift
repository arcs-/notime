import SwiftUI

/// The layout both intro steps share: the mark, a heading, a short description and one
/// full-width action, centred on the screen. `notice` shows below the button when set.
/// The content is at least as tall as the screen (to centre it) and scrolls when taller,
/// e.g. at the largest accessibility text sizes.
struct IntroScreen: View {
    let heading: String
    let description: String
    let buttonTitle: String
    var buttonHint: String = ""
    var isButtonDisabled = false
    var notice: String?
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    AppMark()
                    Text(heading)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(description)
                    Button(action: action) {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .prominentButton()
                    .accessibilityHint(buttonHint)
                    .disabled(isButtonDisabled)
                    if let notice {
                        Text(notice)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
    }
}
