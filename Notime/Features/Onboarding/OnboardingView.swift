import FamilyControls
import SwiftUI

/// First intro step: Screen Time access.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var isRequesting = false

    var body: some View {
        IntroScreen(
            heading: "notime",
            description: "notime blocks the apps and sites you choose. When you open one, you wait a moment before it lets you in.\n\nTo block them, notime needs Screen Time access. It never sees which apps or sites you pick, and nothing leaves your phone.",
            buttonTitle: "Continue",
            buttonHint: "Shows the system request for Screen Time access.",
            isButtonDisabled: isRequesting,
            notice: notice
        ) {
            isRequesting = true
            Task {
                await model.requestAuthorization()
                isRequesting = false
            }
        }
    }

    private var notice: String? {
        model.authorizationErrorMessage
            ?? (model.authorizationStatus == .denied ? "Screen Time access was not allowed. notime cannot block anything without it." : nil)
    }
}
