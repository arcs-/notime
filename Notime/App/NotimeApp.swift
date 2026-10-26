import SwiftUI

@main
struct NotimeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.primary)
        }
    }
}
