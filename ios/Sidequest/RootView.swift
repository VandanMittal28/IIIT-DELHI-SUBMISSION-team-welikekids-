import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model=model
        Group {
        if model.isAuthenticated {
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
        } else { StudentLoginView() }
        }
        .task { await model.restoreSession() }
    }
}

private struct StudentLoginView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            ZStack { RoundedRectangle(cornerRadius: 24).fill(Color.sidequestInk); Text("SQ").font(.system(size: 42, weight: .black, design: .rounded)).foregroundStyle(Color.sidequestLime) }.frame(width: 96, height: 96)
            VStack(spacing: 8) { Text("Sidequest").font(.system(size: 34, weight: .bold, design: .rounded)); Text("IIIT Delhi · Your next starts outside class.").foregroundStyle(.secondary).multilineTextAlignment(.center) }
            VStack(spacing: 14) {
                TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password).textContentType(.password).textFieldStyle(.roundedBorder)
                if let error { Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
                Button(working ? "Signing in…" : "Sign in to IIIT Delhi") { Task { await signIn() } }.buttonStyle(.borderedProminent).controlSize(.large).disabled(working || username.isEmpty || password.isEmpty)
            }.padding(.horizontal, 28)
            Text("Use the username and password issued by IIIT Delhi operations.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }.padding()
    }
    private func signIn() async { working = true; error = nil; do { try await model.signIn(username: username, password: password) } catch let signInError { error = signInError.localizedDescription }; working = false }
}

extension Color {
    static let sidequestInk = Color(red: 0.09, green: 0.13, blue: 0.10)
    static let sidequestLime = Color(red: 0.91, green: 1.0, blue: 0.39)
    static let sidequestMist = Color(red: 0.95, green: 0.96, blue: 0.93)
}
