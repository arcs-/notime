import ManagedSettings
import NotimeCore

/// Handles the shield buttons. All work is finished before the completion handler is
/// called, because the system may terminate the extension right after it.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action, for: .application(application)))
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(respond(to: action, for: .webDomain(webDomain)))
    }

    /// Category shields only ever offer "Close".
    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        NotimeService.live(role: .appExtension).reconcile()
        completionHandler(.close)
    }

    /// The one button is "Open for N min". This is the gate: every refusal closes.
    /// The service also counts the shield as shown here, in case the configuration
    /// extension could not save its impression.
    private func respond(to action: ShieldAction, for target: BlockedTarget) -> ShieldActionResponse {
        let service = NotimeService.live(role: .appExtension)
        guard action == .primaryButtonPressed else {
            // No other button is configured; treat anything else as Close.
            service.reconcile()
            return .close
        }
        switch service.grantAccess(to: target) {
        case .granted:
            // `.defer` makes the system ask the configuration extension again; the target is
            // no longer shielded, so the shield goes away and the user lands in the app.
            return .defer
        case .waiting:
            // Re-render with the current state: how long the wait still is.
            return .defer
        case .refused:
            return .close
        }
    }
}
