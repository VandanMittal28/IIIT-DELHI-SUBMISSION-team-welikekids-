import SwiftUI
import UIKit
import UserNotifications

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var notificationStatus = "Not requested"
    @State private var fullName = ""
    @State private var collegeId: UUID?
    @State private var interests = ""
    @State private var announcementNotifications = true
    @State private var venueNotifications = true
    @State private var reminderNotifications = true
    @State private var reportNotifications = true
    @State private var showDeletionConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                if !model.configuration.isConfigured {
                    Section("Setup required") { Text(SidequestError.notConfigured.localizedDescription) }
                } else if model.isAuthenticated {
                    Section { Label("Signed in", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    Section("Student profile") {
                        TextField("Full name",text:$fullName)
                        Picker("College",selection:$collegeId) { Text("Not selected").tag(nil as UUID?);ForEach(model.colleges){college in Text(college.name).tag(Optional(college.id))} }
                        TextField("Interests, comma separated",text:$interests)
                        Button("Save profile") { Task { do { try await model.saveProfile(fullName:fullName,collegeId:collegeId,interests:interests.split(separator:",").map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty},preferences:["announcements":announcementNotifications,"venue_changes":venueNotifications,"reminders":reminderNotifications,"reports":reportNotifications]);notificationStatus="Profile preferences saved" } catch { errorMessage=error.localizedDescription } } }
                    }
                    Section("Notifications") {
                        Toggle("Announcements",isOn:$announcementNotifications)
                        Toggle("Venue changes",isOn:$venueNotifications)
                        Toggle("Deadline reminders",isOn:$reminderNotifications)
                        Toggle("Report updates",isOn:$reportNotifications)
                        Text(notificationStatus).font(.footnote).foregroundStyle(.secondary)
                        Button("Enable event notifications") { Task { await requestNotifications() } }
                    }
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                    Section("Account lifecycle") { Button("Request account deletion",role:.destructive){showDeletionConfirmation=true};Text("This immediately deactivates notification delivery and marks the account for secure deletion processing.").font(.footnote).foregroundStyle(.secondary) }
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
            .onChange(of:model.profile) { _,profile in guard let profile else{return};fullName=profile.fullName ?? "";collegeId=profile.collegeId;interests=profile.interests.joined(separator:", ");announcementNotifications=profile.notificationPreferences["announcements"] ?? true;venueNotifications=profile.notificationPreferences["venue_changes"] ?? true;reminderNotifications=profile.notificationPreferences["reminders"] ?? true;reportNotifications=profile.notificationPreferences["reports"] ?? true }
            .onReceive(NotificationCenter.default.publisher(for: .sidequestDeviceToken)) { note in
                if let token = note.object as? String {
                    Task { do { try await model.registerDeviceToken(token); notificationStatus = "Enabled and registered" } catch { notificationStatus = "Permission granted, but backend registration failed: \(error.localizedDescription)" } }
                } else { notificationStatus = note.userInfo?["error"] as? String ?? "APNs registration failed" }
            }
            .alert("Request account deletion?",isPresented:$showDeletionConfirmation){Button("Cancel",role:.cancel){};Button("Request deletion",role:.destructive){Task{do{try await model.requestAccountDeletion()}catch{errorMessage=error.localizedDescription}}}} message:{Text("You will be signed out. An administrator must complete identity deletion under the retention policy.")}
        }
    }

    private func signIn() async {
        isWorking = true; errorMessage = nil
        do { try await model.signIn(email: email, password: password) }
        catch { errorMessage = error.localizedDescription }
        isWorking = false
    }

    private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { notificationStatus = "Denied — updates remain available in the in-app inbox"; return }
            notificationStatus = "Permission granted; registering this device…"
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        } catch { notificationStatus = error.localizedDescription }
    }
}
