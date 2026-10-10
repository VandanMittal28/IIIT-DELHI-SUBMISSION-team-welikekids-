import SwiftUI

@main
struct SidequestApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Color.sidequestInk)
        }
    }
}
