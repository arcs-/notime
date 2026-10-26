import FamilyControls
import NotimeCore

/// Converts between the picker's selection and the core's FamilyControls-free copy of it.
extension FamilyActivitySelection {
    init(_ blockedSelection: BlockedSelection) {
        self.init()
        applicationTokens = blockedSelection.applicationTokens
        categoryTokens = blockedSelection.categoryTokens
        webDomainTokens = blockedSelection.webDomainTokens
    }

    var blockedSelection: BlockedSelection {
        BlockedSelection(
            applicationTokens: applicationTokens,
            categoryTokens: categoryTokens,
            webDomainTokens: webDomainTokens
        )
    }
}
