import FamilyControls
import Foundation
import NotimeCore
import Observation

/// Main-actor façade over `NotimeService` for the SwiftUI screens.
/// Every change is a locked load → change → reconcile → save in the core, so the app never
/// overwrites counters an extension recorded while the app was in the background.
@MainActor
@Observable
final class AppModel {
    /// Last state successfully read. Kept on screen when the store becomes unavailable.
    private(set) var state: NotimeState
    private(set) var isStateAvailable: Bool
    private(set) var authorizationStatus: AuthorizationStatus
    private(set) var authorizationErrorMessage: String?
    private(set) var selectionNotice: String?
    /// Set when a corrupt state file was moved aside and Notime started fresh.
    private(set) var wasStateReset = false
    /// Refreshed on every reconcile, so Home switches to the new day at midnight.
    private(set) var today: DayKey

    @ObservationIgnored private let service: NotimeService

    init(service: NotimeService = .live(role: .app)) {
        self.service = service
        self.authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        self.today = service.today
        switch service.loadState() {
        case .loaded(let state):
            self.state = state
            self.isStateAvailable = true
        case .empty:
            self.state = NotimeState()
            self.isStateAvailable = true
        case .unavailable(let error):
            self.state = NotimeState()
            self.isStateAvailable = false
            noteResetIfCorrupt(error)
        }
    }

    var calendar: Calendar { service.calendar }

    /// Also keeps the daily sweep monitored, which reconciles from the monitor extension.
    func reconcile() {
        accept(service.reconcile(rollingOverHistory: true) { wasStateReset = true })
        today = service.today
        service.ensureSweepMonitoring()
    }

    func statisticsLedgers() -> [DailyUsageLedger] {
        service.statisticsLedgers()
    }

    func updateAuthorizationStatus(_ status: AuthorizationStatus) {
        authorizationStatus = status
    }

    func requestAuthorization() async {
        authorizationErrorMessage = nil
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            NotimeLog.app.error("Authorization failed: \(error.localizedDescription, privacy: .public)")
            authorizationErrorMessage = error.localizedDescription
        }
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        reconcile()
    }

    /// Refuses selections the shield can't fully enforce and keeps the previous one.
    func updateSelection(_ selection: FamilyActivitySelection) {
        let blockedSelection = selection.blockedSelection
        guard !blockedSelection.exceedsShieldLimit else {
            selectionNotice = "Not saved: pick at most \(BlockedSelection.maximumIndividualItemCount) apps and websites combined."
            return
        }
        selectionNotice = nil
        accept(service.change { $0.selection = blockedSelection })
    }

    func updatePolicy(_ change: (inout BlockPolicy) -> Void) {
        accept(service.change { change(&$0.policy) })
    }

    private func noteResetIfCorrupt(_ error: any Error) {
        if error as? AppGroupStateStore.StoreError == .corruptFileMovedAside {
            wasStateReset = true
        }
    }

    private func accept(_ newState: NotimeState?) {
        if let newState {
            state = newState
        }
        isStateAvailable = newState != nil
    }
}
