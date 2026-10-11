import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DiscoverView().tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            MyJourneyView()
                .tabItem { Label("My Journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            ConnectedSoonView(title: "Community is being connected", detail: "Discussions and announcements will use persistent backend channels—not sample conversations.")
                .tabItem { Label("Community", systemImage: "person.3") }
            AccountView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

struct ConnectedSoonView: View {
    let title: String
    let detail: String
    var body: some View {
        ContentUnavailableView(title, systemImage: "link.badge.plus", description: Text(detail))
    }
}

extension Color {
    static let sidequestInk = Color(red: 0.09, green: 0.13, blue: 0.10)
    static let sidequestLime = Color(red: 0.91, green: 1.0, blue: 0.39)
    static let sidequestMist = Color(red: 0.95, green: 0.96, blue: 0.93)
}
