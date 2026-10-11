import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model=model
        TabView(selection:$model.selectedTab) {
            DiscoverView().tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
                .tag(0)
            MyJourneyView()
                .tabItem { Label("My Journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(1)
            NavigateView().tabItem { Label("Navigate", systemImage: "location.north.line.fill") }.tag(2)
            CommunityView().tabItem { Label("Community", systemImage: "person.3") }.tag(3)
            AccountView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
        }
    }
}

extension Color {
    static let sidequestInk = Color(red: 0.09, green: 0.13, blue: 0.10)
    static let sidequestLime = Color(red: 0.91, green: 1.0, blue: 0.39)
    static let sidequestMist = Color(red: 0.95, green: 0.96, blue: 0.93)
}
