import FamilyControls
import NotimeCore
import SwiftUI

/// Shows an app or website by its Screen Time token; the system renders name and icon.
struct BlockedTargetLabel: View {
    let target: BlockedTarget

    var body: some View {
        switch target {
        case .application(let token): Label(token)
        case .webDomain(let token): Label(token)
        }
    }
}
