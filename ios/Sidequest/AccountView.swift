import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !model.configuration.isConfigured {
                    Section("Setup required") { Text(SidequestError.notConfigured.localizedDescription) }
                } else if model.isAuthenticated {
                    Section { Label("Signed in", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                } else {
                    Section("Student account") {
                        TextField("Email", text: $email).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(.password)
                        Button(isWorking ? "Signing in…" : "Sign in") { Task { await signIn() } }.disabled(isWorking || email.isEmpty || password.isEmpty)
                    }
                    if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                    Section { Text("Public sign-up never grants staff access. Organization and college roles require an audited invitation.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Profile")
            .task { await model.restoreSession() }
        }
    }

    private func signIn() async {
        isWorking = true; errorMessage = nil
        do { try await model.signIn(email: email, password: password) }
        catch { errorMessage = error.localizedDescription }
        isWorking = false
    }
}
