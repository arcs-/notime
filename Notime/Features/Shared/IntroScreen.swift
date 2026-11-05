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
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        AppMark()
                        Text(heading)
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(description)
                        .padding(.top, 40)
                        .padding(.bottom, 32)
                    Button(action: action) {
                        Text(buttonTitle)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .prominentButton()
                    .accessibilityHint(buttonHint)
                    .disabled(isButtonDisabled)
                    if let notice {
                        Text(notice)
                            .padding(.top, 20)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                // Extra space below lifts the content above the true centre, which reads as centred.
                .padding(.bottom, 16 + proxy.size.height * 0.12)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
    }
}
