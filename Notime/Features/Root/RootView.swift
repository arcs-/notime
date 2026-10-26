import Combine
import FamilyControls
import SwiftUI

/// Chooses between the two intro steps and home, and reconciles every time the app becomes
/// active, at midnight and when the clock or time zone changes while it is open.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.state.selection.isEmpty {
                HomeView()
            } else if model.authorizationStatus == .approved {
                ChooseTargetsView()
            } else {
                OnboardingView()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.updateAuthorizationStatus(AuthorizationCenter.shared.authorizationStatus)
                model.reconcile()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            model.reconcile()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            model.reconcile()
        }
        .onReceive(AuthorizationCenter.shared.$authorizationStatus.receive(on: DispatchQueue.main)) { status in
            model.updateAuthorizationStatus(status)
        }
    }
}
