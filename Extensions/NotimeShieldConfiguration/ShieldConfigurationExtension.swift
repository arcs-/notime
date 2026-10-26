import ManagedSettings
import ManagedSettingsUI
import NotimeCore
import UIKit

/// Renders the shield in host-resolved system colours, so it follows light and dark. Category shields are
/// close-only, because access is never granted to a whole category. Any app or site
/// shield offers access, even when the state can't be read: the action extension refuses then.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(for: application.token.map(BlockedTarget.application))
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(for: nil)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(for: webDomain.token.map(BlockedTarget.webDomain))
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(for: nil)
    }

    /// Only system colours resolved by the host at draw time. Nothing here may read traits or
    /// resolve colours itself (no `UITraitCollection`, `UIScreen`, `resolvedColor`, asset-catalog
    /// colours): in the shield extension the traits are stale or unspecified, so self-resolved
    /// colours come out in the wrong theme at random (Apple Developer Forums thread 735785).
    /// `.systemBackground` as a text colour rendered blue on device, so the button keeps the
    /// host's default look (nil background) with `.label` text; text is only ever `.label`.
    private func makeConfiguration(for target: BlockedTarget?) -> ShieldConfiguration {
        let presentation = NotimeService.live(role: .appExtension).prepareShield(for: target)
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: .systemBackground,
            icon: ShieldIcon.image(),
            title: ShieldConfiguration.Label(text: ShieldPresentation.title, color: .label),
            subtitle: ShieldConfiguration.Label(text: presentation.body, color: .label),
            primaryButtonLabel: ShieldConfiguration.Label(text: presentation.buttonTitle, color: .label),
            primaryButtonBackgroundColor: nil
        )
    }
}
