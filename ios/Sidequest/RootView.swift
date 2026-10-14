import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tabBarHidden = false

    /// Tags must stay 0–4: `AppModel.prepareNavigation` jumps to tab 2 to show a route.
    private static let tabs: [SQTabItem] = [
        SQTabItem(id: 0, title: "Discover", systemImage: "safari", selectedSystemImage: "safari.fill"),
        SQTabItem(id: 1, title: "Journey", systemImage: "ticket", selectedSystemImage: "ticket.fill"),
        SQTabItem(id: 2, title: "Navigate", systemImage: "location.north.line", selectedSystemImage: "location.north.line.fill"),
        SQTabItem(id: 3, title: "Community", systemImage: "bubble.left.and.bubble.right", selectedSystemImage: "bubble.left.and.bubble.right.fill"),
        SQTabItem(id: 4, title: "Profile", systemImage: "person.crop.circle", selectedSystemImage: "person.crop.circle.fill")
    ]

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isAuthenticated {
                // The system tab bar is hidden on every tab root and replaced by the floating
                // capsule from screenshots 01–06. Screens reserve `SQSpace.tabBarClearance`
                // at the bottom so content scrolls under the bar instead of being clipped.
                // Each screen hides the system tab bar from inside its own NavigationStack,
                // which is where the modifier reliably takes effect.
                ZStack(alignment: .bottom) {
                    TabView(selection: $model.selectedTab) {
                        DiscoverView().tag(0)
                        MyJourneyView().tag(1)
                        NavigateView().tag(2)
                        CommunityView().tag(3)
                        AccountView().tag(4)
                    }
                    .onPreferenceChange(SQTabBarHiddenKey.self) { tabBarHidden = $0 }

                    if !tabBarHidden {
                        SQTabBar(items: Self.tabs, selection: $model.selectedTab)
                            .padding(.bottom, SQSpace.xs)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: tabBarHidden)
                .ignoresSafeArea(.keyboard, edges: .bottom)
            } else {
                StudentLoginView()
            }
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
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpace.xxl) {
                Spacer(minLength: SQSpace.xxxl)

                ZStack {
                    RoundedRectangle(cornerRadius: SQRadius.card, style: .continuous)
                        .fill(SQColor.ink)
                    Text("SQ")
                        .font(SQFont.monogram(42))
                        .foregroundStyle(SQColor.lime)
                }
                .frame(width: 96, height: 96)
                .sqShadow(SQShadow.card)

                VStack(alignment: .leading, spacing: SQSpace.sm) {
                    HStack(spacing: 2) {
                        Text("Sidequest").font(SQFont.display)
                        Image(systemName: "sparkle")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(SQColor.accent)
                            .offset(y: -10)
                    }
                    .foregroundStyle(SQColor.textPrimary)
                    Text("IIIT Delhi · Your next starts outside class.")
                        .font(SQFont.rowLabel)
                        .foregroundStyle(SQColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: SQSpace.md) {
                    SQField(placeholder: "Username", text: $username, systemImage: "person")
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SQField(placeholder: "Password", text: $password, systemImage: "lock", isSecure: true)
                        .textContentType(.password)
                    if let error {
                        SQNotice(text: error, kind: .error)
                    }
                    SQPrimaryButton(
                        title: working ? "Signing in…" : "Sign in to IIIT Delhi",
                        systemImage: working ? nil : "arrow.right",
                        isLoading: working,
                        isEnabled: !username.isEmpty && !password.isEmpty
                    ) {
                        Task { await signIn() }
                    }
                }

                Text("Use the username and password issued by IIIT Delhi operations.")
                    .font(SQFont.body)
                    .foregroundStyle(SQColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: SQSpace.xxxl)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SQSpace.margin)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(SQColor.plainBackground.ignoresSafeArea())
    }

    private func signIn() async {
        working = true
        error = nil
        do {
            try await model.signIn(username: username, password: password)
        } catch let signInError {
            error = signInError.localizedDescription
        }
        working = false
    }
}

// Retained for source compatibility with anything still referencing the original palette
// constants. New code should use `SQColor`.
extension Color {
    static let sidequestInk = SQColor.ink
    static let sidequestLime = SQColor.lime
    static let sidequestMist = SQColor.background
}
