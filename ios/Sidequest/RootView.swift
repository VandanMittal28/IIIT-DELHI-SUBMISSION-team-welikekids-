import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DiscoverView().tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            MyJourneyView()
                .tabItem { Label("My Journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            NavigateView().tabItem { Label("Navigate", systemImage: "location.north.line.fill") }
            CommunityView().tabItem { Label("Community", systemImage: "person.3") }
            AccountView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

extension Color {
    static let sidequestInk = Color(red: 0.09, green: 0.13, blue: 0.10)
    static let sidequestLime = Color(red: 0.91, green: 1.0, blue: 0.39)
    static let sidequestMist = Color(red: 0.95, green: 0.96, blue: 0.93)
}
