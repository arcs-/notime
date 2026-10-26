import FamilyControls
import SwiftUI

/// First intro step: Screen Time access.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var isRequesting = false

    var body: some View {
        IntroScreen(
            heading: "notime",
            description: "notime blocks the apps and sites you choose. It needs Screen Time access to do that.",
            buttonTitle: model.authorizationStatus == .denied ? "Try again" : "Allow Screen Time access",
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
