import SwiftUI
import UIKit
import PhotosUI
import UserNotifications

struct AccountView: View {
    private enum AuthMode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case createAccount = "Create account"
        var id: Self { self }
    }

    @Environment(AppModel.self) private var model
    @State private var authMode: AuthMode = .signIn
    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var authNotice: String?
    @State private var notificationStatus = "Not requested"
    @State private var fullName = ""
    @State private var collegeId: UUID?
    @State private var interests = ""
    @State private var announcementNotifications = true
    @State private var venueNotifications = true
    @State private var reminderNotifications = true
    @State private var reportNotifications = true
    @State private var showDeletionConfirmation = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var reportEdition: JourneyItem?

    var body: some View {
        NavigationStack {
            Form {
                if !model.configuration.isConfigured {
                    Section("Setup required") { Text(SidequestError.notConfigured.localizedDescription) }
                } else if model.isAuthenticated {
                    Section { Label("Signed in", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                    Section("Student profile") {
                        HStack { Spacer(); if let avatarData, let image = UIImage(data: avatarData) { Image(uiImage: image).resizable().scaledToFill().frame(width: 78, height: 78).clipShape(Circle()) } else { Image(systemName: "person.crop.circle.fill").font(.system(size: 72)).foregroundStyle(Color.sidequestLime, Color.sidequestInk) }; Spacer() }
                        PhotosPicker(selection: $avatarItem, matching: .images) { Label("Add profile photo", systemImage: "camera.fill") }
                        Text("Your profile photo is kept on this device in this demo build.").font(.caption).foregroundStyle(.secondary)
                        TextField("Full name",text:$fullName)
                        Picker("College",selection:$collegeId) { Text("Not selected").tag(nil as UUID?);ForEach(model.colleges){college in Text(college.name).tag(Optional(college.id))} }
                        TextField("Interests, comma separated",text:$interests)
                        Button("Save profile") { Task { do { try await model.saveProfile(fullName:fullName,collegeId:collegeId,interests:interests.split(separator:",").map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty},preferences:["announcements":announcementNotifications,"venue_changes":venueNotifications,"reminders":reminderNotifications,"reports":reportNotifications]);notificationStatus="Profile preferences saved" } catch { errorMessage=error.localizedDescription } } }
                    }
                    Section("Notifications") {
                        Toggle("Push announcements",isOn:$announcementNotifications)
                        Toggle("Push venue changes",isOn:$venueNotifications)
                        Toggle("Push deadline reminders",isOn:$reminderNotifications)
                        Toggle("Push report updates",isOn:$reportNotifications)
                        Text("Important updates remain available in your in-app inbox even when a push category is off.").font(.footnote).foregroundStyle(.secondary)
                        Text(notificationStatus).font(.footnote).foregroundStyle(.secondary)
                        Button("Enable event notifications") { Task { await requestNotifications() } }
                    }
                    Section("Attendance history") {
                        if model.attendanceHistory.isEmpty { Text("No attendance transitions recorded.").foregroundStyle(.secondary) }
                        ForEach(model.attendanceHistory) { item in
                            VStack(alignment:.leading,spacing:3){Text(item.title).font(.headline);Text(item.action.replacingOccurrences(of:"_",with:" ").capitalized);Text(item.recordedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}
                        }
                    }
                    Section("Submitted reviews") {
                        if model.submittedReviews.isEmpty { Text("No verified-attendee reviews submitted.").foregroundStyle(.secondary) }
                        ForEach(model.submittedReviews) { item in
                            VStack(alignment:.leading,spacing:3){Text(item.title).font(.headline);Text("\(item.rating) / 5");if let body=item.body{Text(body).foregroundStyle(.secondary)};Text("Updated \(item.updatedAt.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)}
                        }
                    }
                    Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                    Section("Support") { Text("Send an event issue directly to the IIIT Delhi operations team.").font(.footnote); Button { reportEdition = model.journey.first(where: { $0.status != "cancelled" }) } label: { Label("Report an event issue", systemImage: "flag") }.disabled(model.journey.filter { $0.status != "cancelled" }.isEmpty) }
                    Section("Account lifecycle") { Button("Request account deletion",role:.destructive){showDeletionConfirmation=true};Text("This immediately deactivates notification delivery and marks the account for secure deletion processing.").font(.footnote).foregroundStyle(.secondary) }
                } else {
                    Section("Student account") {
                        Picker("Account action", selection: $authMode) {
                            ForEach(AuthMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(authMode == .signIn ? .password : .newPassword)
                        if authMode == .createAccount {
                            Text("Creates a student account only. Staff permissions require a separate audited invitation.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button(isWorking ? "Working…" : authMode.rawValue) { Task { await submitAuthentication() } }
                            .disabled(isWorking || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (authMode == .createAccount ? password.count < 8 : password.isEmpty))
                    }
                    if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                    if let authNotice { Section { Text(authNotice).foregroundStyle(.green) } }
                    Section { Text("Public sign-up never grants staff access. Organization and college roles require an audited invitation.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Profile")
            .task { await model.restoreSession() }
            .onChange(of:model.profile) { _,profile in guard let profile else{return};fullName=profile.fullName ?? "";collegeId=profile.collegeId;interests=profile.interests.joined(separator:", ");announcementNotifications=profile.notificationPreferences["announcements"] ?? true;venueNotifications=profile.notificationPreferences["venue_changes"] ?? true;reminderNotifications=profile.notificationPreferences["reminders"] ?? true;reportNotifications=profile.notificationPreferences["reports"] ?? true }
            .onChange(of: avatarItem) { _, item in Task { avatarData = try? await item?.loadTransferable(type: Data.self) } }
            .onReceive(NotificationCenter.default.publisher(for: .sidequestDeviceToken)) { note in
                if let token = note.object as? String {
                    Task { do { try await model.registerDeviceToken(token); notificationStatus = "Enabled and registered" } catch { notificationStatus = "Permission granted, but backend registration failed: \(error.localizedDescription)" } }
                } else { notificationStatus = note.userInfo?["error"] as? String ?? "APNs registration failed" }
            }
            .alert("Request account deletion?",isPresented:$showDeletionConfirmation){Button("Cancel",role:.cancel){};Button("Request deletion",role:.destructive){Task{do{try await model.requestAccountDeletion()}catch{errorMessage=error.localizedDescription}}}} message:{Text("You will be signed out. An administrator must complete identity deletion under the retention policy.")}
            .sheet(item: $reportEdition) { item in EventIssueForm(item: item) }
        }
    }

    private func submitAuthentication() async {
        isWorking = true; errorMessage = nil; authNotice = nil
        do {
            switch authMode {
            case .signIn:
                try await model.signIn(username: username, password: password)
            case .createAccount:
                let outcome = try await model.createStudentAccount(username: username, password: password)
                if outcome == .confirmationRequired {
                    authNotice = "Check your email to confirm the account, then return here and sign in. No staff access was granted."
                    authMode = .signIn
                    password = ""
                }
            }
        }
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

private struct EventIssueForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem
    @State private var detail = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View { NavigationStack { Form { Section(item.title) { TextField("What happened?", text: $detail, axis: .vertical).lineLimit(4...8) }; if let error { Text(error).foregroundStyle(.red) }; Button(busy ? "Sending…" : "Send report") { busy = true; Task { do { _ = try await model.submitReport(editionId: item.editionId, category: "Event issue", description: detail, priority: "normal", attachmentData: nil); dismiss() } catch { self.error = error.localizedDescription; busy = false } } }.disabled(busy || detail.trimmingCharacters(in: .whitespacesAndNewlines).count < 5) }.navigationTitle("Report issue").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
}
