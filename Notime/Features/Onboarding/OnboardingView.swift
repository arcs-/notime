import FamilyControls
import SwiftUI

/// First intro step: Screen Time access.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var isRequesting = false

    var body: some View {
        IntroScreen(
            heading: "notime",
            description: "notime uses Screen Time to block the apps and websites you choose. Your choices stay on this iPhone, and notime cannot see which apps or sites they are.",
            buttonTitle: "Continue",
            buttonHint: "Shows the Screen Time permission request.",
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
