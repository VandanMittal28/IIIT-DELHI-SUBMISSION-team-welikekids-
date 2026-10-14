import SwiftUI
import UIKit
import PhotosUI
import UserNotifications

// Rebuilt after screenshot 01: grouped white cards on `SQColor.background`, each row led by a
// coloured icon tile, with grey section headers between groups.
//
// The original screen was a single long `Form`. The same features are all here, regrouped so
// that editing (profile, notifications) happens in pushed screens and the root stays a short,
// scannable list — which is what makes Luma's settings read the way it does.

struct AccountView: View {
    @Environment(AppModel.self) private var model

    @State private var username = ""
    @State private var password = ""
    @State private var isCreatingAccount = false
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
    @State private var showEditProfile = false
    @State private var saveNotice: String?

    private var displayName: String {
        let name = (model.profile?.fullName ?? fullName).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your profile" : name
    }

    private var collegeName: String {
        guard let id = model.profile?.collegeId ?? collegeId,
              let match = model.colleges.first(where: { $0.id == id }) else { return "College not set" }
        return match.name
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SQScreenHeader(title: "Profile", avatarSeed: displayName) {
                    if model.isAuthenticated {
                        SQActionCapsule {
                            SQCapsuleGlyph(systemImage: "square.and.pencil", accessibilityTitle: "Edit profile") {
                                showEditProfile = true
                            }
                        }
                    }
                }
                .padding(.bottom, SQSpace.lg)

                ScrollView {
                    VStack(alignment: .leading, spacing: SQSpace.cardToHeader) {
                        if !model.configuration.isConfigured {
                            setupRequiredCard
                        } else if model.isAuthenticated {
                            signedInContent
                        } else {
                            signedOutContent
                        }
                    }
                    .padding(.horizontal, SQSpace.margin)
                    .padding(.bottom, SQSpace.tabBarClearance)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(SQColor.background.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .task {
                await model.restoreSession()
                if model.isAuthenticated { await model.reloadCommunity() }
            }
            .onChange(of: model.profile) { _, profile in applyProfile(profile) }
            .onChange(of: avatarItem) { _, item in
                Task { avatarData = try? await item?.loadTransferable(type: Data.self) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sidequestDeviceToken)) { note in
                handleDeviceToken(note)
            }
            .alert("Request account deletion?", isPresented: $showDeletionConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Request deletion", role: .destructive) {
                    Task {
                        do { try await model.requestAccountDeletion() }
                        catch { errorMessage = error.localizedDescription }
                    }
                }
            } message: {
                Text("You will be signed out. An administrator must complete identity deletion under the retention policy.")
            }
            .sheet(item: $reportEdition) { item in EventIssueForm(item: item) }
            .sheet(isPresented: $showEditProfile) { editProfileSheet }
        }
    }

    // MARK: - Signed in

    @ViewBuilder private var signedInContent: some View {
        SQCard {
            SQProfileRow(name: displayName, subtitle: collegeName, seed: displayName) {
                showEditProfile = true
            }
            SQInsetDivider(leading: SQSize.avatarLarge + SQSpace.cardInset + 14)
            SQListRow(title: "Edit Profile", action: { showEditProfile = true })
        }

        if let saveNotice {
            SQNotice(text: saveNotice, kind: .success)
        }
        if let errorMessage {
            SQNotice(text: errorMessage, kind: .error)
        }

        group(title: "Preferences") {
            SQCard {
                NavigationLink { notificationsScreen } label: {
                    SQListRow(title: "Notifications", systemImage: "bell.fill", iconColor: SQColor.hueRed)
                }
                .buttonStyle(.plain)
                SQInsetDivider()
                NavigationLink { interestsScreen } label: {
                    SQListRow(title: "Interests", systemImage: "sparkles", iconColor: SQColor.hueViolet)
                }
                .buttonStyle(.plain)
                SQInsetDivider()
                NavigationLink { AttendanceHistoryScreen() } label: {
                    SQListRow(title: "Attendance History", systemImage: "checkmark.seal.fill", iconColor: SQColor.hueGreen)
                }
                .buttonStyle(.plain)
            }
        }

        group(title: "Your activity") {
            SQCard {
                NavigationLink { SubmittedReviewsScreen() } label: {
                    SQListRow(title: "Submitted Reviews", systemImage: "star.fill", iconColor: SQColor.hueYellow)
                }
                .buttonStyle(.plain)
                SQInsetDivider()
                NavigationLink { MyReportsScreen() } label: {
                    SQListRow(title: "My Reports", systemImage: "flag.fill", iconColor: SQColor.hueOrange)
                }
                .buttonStyle(.plain)
            }
        }

        group(title: "Resources") {
            SQCard {
                SQListRow(
                    title: "Report an Event Issue",
                    subtitle: "Goes to the IIIT Delhi operations team",
                    systemImage: "envelope.fill",
                    iconColor: SQColor.hueBlue,
                    action: { reportEdition = model.journey.first(where: { $0.status != "cancelled" }) }
                )
                .disabled(model.journey.filter { $0.status != "cancelled" }.isEmpty)
                .opacity(model.journey.filter { $0.status != "cancelled" }.isEmpty ? 0.45 : 1)
            }
        }

        SQCard {
            SQListRow(title: "Sign Out", systemImage: "rectangle.portrait.and.arrow.right", accessory: .none, destructive: true) {
                Task { await model.signOut() }
            }
            SQInsetDivider()
            SQListRow(title: "Request Account Deletion", systemImage: "trash.fill", accessory: .none, destructive: true) {
                showDeletionConfirmation = true
            }
        }

        Text("This immediately deactivates notification delivery and marks the account for secure deletion processing.")
            .font(SQFont.meta)
            .foregroundStyle(SQColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SQSpace.cardInset)
    }

    // MARK: - Signed out

    @ViewBuilder private var signedOutContent: some View {
        SQCard(padding: SQSpace.cardInset) {
            VStack(alignment: .leading, spacing: SQSpace.lg) {
                Picker("Account action", selection: $isCreatingAccount) {
                    Text("Sign in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)

                SQField(placeholder: "Username", text: $username, systemImage: "person")
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SQField(placeholder: "Password", text: $password, systemImage: "lock", isSecure: true)
                    .textContentType(isCreatingAccount ? .newPassword : .password)

                if isCreatingAccount {
                    Text("Creates a student account only. Staff permissions require a separate audited invitation.")
                        .font(SQFont.meta)
                        .foregroundStyle(SQColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SQPrimaryButton(
                    title: isWorking ? "Working…" : (isCreatingAccount ? "Create account" : "Sign in"),
                    isLoading: isWorking,
                    isEnabled: canSubmitAuthentication
                ) {
                    Task { await submitAuthentication() }
                }
            }
        }

        if let errorMessage { SQNotice(text: errorMessage, kind: .error) }
        if let authNotice { SQNotice(text: authNotice, kind: .success) }

        Text("Public sign-up never grants staff access. Organization and college roles require an audited invitation.")
            .font(SQFont.meta)
            .foregroundStyle(SQColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SQSpace.cardInset)
    }

    private var canSubmitAuthentication: Bool {
        guard !isWorking, !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return isCreatingAccount ? password.count >= 8 : !password.isEmpty
    }

    private var setupRequiredCard: some View {
        SQCard(padding: SQSpace.cardInset) {
            VStack(alignment: .leading, spacing: SQSpace.sm) {
                Text("Setup required").font(SQFont.rowTitle).foregroundStyle(SQColor.textPrimary)
                Text(SidequestError.notConfigured.localizedDescription)
                    .font(SQFont.body)
                    .foregroundStyle(SQColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pushed screens

    private var notificationsScreen: some View {
        SQDetailScreen(title: "Notifications") {
            SQCard {
                toggleRow("Announcements", systemImage: "megaphone.fill", color: SQColor.hueRed, isOn: $announcementNotifications)
                SQInsetDivider()
                toggleRow("Venue changes", systemImage: "arrow.triangle.swap", color: SQColor.hueOrange, isOn: $venueNotifications)
                SQInsetDivider()
                toggleRow("Deadline reminders", systemImage: "clock.fill", color: SQColor.hueBlue, isOn: $reminderNotifications)
                SQInsetDivider()
                toggleRow("Report updates", systemImage: "flag.fill", color: SQColor.hueGreen, isOn: $reportNotifications)
            }

            Text("Important updates remain available in your in-app inbox even when a push category is off.")
                .font(SQFont.meta)
                .foregroundStyle(SQColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, SQSpace.cardInset)

            SQCard {
                SQListRow(title: "Enable event notifications", subtitle: notificationStatus, systemImage: "bell.badge.fill", iconColor: SQColor.hueViolet, accessory: .none) {
                    Task { await requestNotifications() }
                }
            }

            SQPrimaryButton(title: "Save preferences", systemImage: "checkmark") {
                Task { await saveProfile() }
            }
            if let saveNotice { SQNotice(text: saveNotice, kind: .success) }
            if let errorMessage { SQNotice(text: errorMessage, kind: .error) }
        }
    }

    private var interestsScreen: some View {
        SQDetailScreen(title: "Interests") {
            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.md) {
                    SQField(placeholder: "Interests, comma separated", text: $interests)
                    Text("A clear name, college, interests and photo help your campus community recognize you.")
                        .font(SQFont.meta)
                        .foregroundStyle(SQColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SQPrimaryButton(title: "Save interests", systemImage: "checkmark") {
                Task { await saveProfile() }
            }
            if let saveNotice { SQNotice(text: saveNotice, kind: .success) }
            if let errorMessage { SQNotice(text: errorMessage, kind: .error) }
        }
    }

    private var editProfileSheet: some View {
        SQSheet(title: "Edit Profile", onClose: { showEditProfile = false }) {
            HStack {
                Spacer()
                VStack(spacing: SQSpace.md) {
                    Group {
                        if let avatarData, let image = UIImage(data: avatarData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            SQAvatar(seed: displayName, size: 96)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())

                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text("Change photo")
                            .font(SQFont.bodyEmphasis)
                            .foregroundStyle(SQColor.accent)
                    }
                }
                Spacer()
            }

            Text("Your profile photo is kept on this device in this demo build.")
                .font(SQFont.meta)
                .foregroundStyle(SQColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)

            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.md) {
                    SQField(placeholder: "Full name", text: $fullName, systemImage: "person")
                    SQField(placeholder: "Interests, comma separated", text: $interests, systemImage: "sparkles")
                }
            }

            SQGroupHeader(title: "College")
                .padding(.horizontal, -SQSpace.margin)
            SQCard {
                SQListRow(title: "College", accessory: .none) {
                    Picker("College", selection: $collegeId) {
                        Text("Not selected").tag(nil as UUID?)
                        ForEach(model.colleges) { college in
                            Text(college.name).tag(Optional(college.id))
                        }
                    }
                    .labelsHidden()
                }
            }

            SQPrimaryButton(title: "Save profile", systemImage: "checkmark") {
                Task {
                    await saveProfile()
                    if errorMessage == nil { showEditProfile = false }
                }
            }
            if let errorMessage { SQNotice(text: errorMessage, kind: .error) }
        }
    }

    // MARK: - Building blocks

    @ViewBuilder private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SQSpace.headerToCard) {
            SQGroupHeader(title: title)
                .padding(.horizontal, -SQSpace.margin)
            content()
        }
    }

    private func toggleRow(_ title: String, systemImage: String, color: Color, isOn: Binding<Bool>) -> some View {
        SQListRow(title: title, systemImage: systemImage, iconColor: color, accessory: .none) {
            Toggle("", isOn: isOn).labelsHidden()
        }
    }

    // MARK: - Behaviour

    private func applyProfile(_ profile: StudentProfile?) {
        guard let profile else { return }
        fullName = profile.fullName ?? ""
        collegeId = profile.collegeId
        interests = profile.interests.joined(separator: ", ")
        announcementNotifications = profile.notificationPreferences["announcements"] ?? true
        venueNotifications = profile.notificationPreferences["venue_changes"] ?? true
        reminderNotifications = profile.notificationPreferences["reminders"] ?? true
        reportNotifications = profile.notificationPreferences["reports"] ?? true
    }

    private func saveProfile() async {
        errorMessage = nil
        saveNotice = nil
        do {
            try await model.saveProfile(
                fullName: fullName,
                collegeId: collegeId,
                interests: interests
                    .split(separator: ",")
                    .map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
                preferences: [
                    "announcements": announcementNotifications,
                    "venue_changes": venueNotifications,
                    "reminders": reminderNotifications,
                    "reports": reportNotifications
                ]
            )
            saveNotice = "Profile preferences saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitAuthentication() async {
        isWorking = true
        errorMessage = nil
        authNotice = nil
        do {
            if isCreatingAccount {
                let outcome = try await model.createStudentAccount(username: username, password: password)
                if outcome == .confirmationRequired {
                    authNotice = "Check your email to confirm the account, then return here and sign in. No staff access was granted."
                    isCreatingAccount = false
                    password = ""
                }
            } else {
                try await model.signIn(username: username, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func requestNotifications() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                notificationStatus = "Denied — updates remain available in the in-app inbox"
                return
            }
            notificationStatus = "Permission granted; registering this device…"
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            notificationStatus = error.localizedDescription
        }
    }

    private func handleDeviceToken(_ note: Notification) {
        if let token = note.object as? String {
            Task {
                do {
                    try await model.registerDeviceToken(token)
                    notificationStatus = "Enabled and registered"
                } catch {
                    notificationStatus = "Permission granted, but backend registration failed: \(error.localizedDescription)"
                }
            }
        } else {
            notificationStatus = note.userInfo?["error"] as? String ?? "APNs registration failed"
        }
    }
}

// MARK: - Pushed screen scaffold

/// A pushed settings sub-screen: centered nav title with a circular back button, grouped
/// cards beneath — the layout of screenshot 01.
struct SQDetailScreen<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            SQNavBar(title: title) {
                SQCircleButton(systemImage: "chevron.left") { dismiss() }
                    .accessibilityLabel("Back")
            } trailing: {
                Color.clear.frame(width: SQSize.floatingCircle, height: SQSize.floatingCircle)
            }
            .padding(.bottom, SQSpace.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: SQSpace.xl) {
                    content
                }
                .padding(.horizontal, SQSpace.margin)
                .padding(.bottom, SQSpace.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(SQColor.background.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Activity screens

private struct AttendanceHistoryScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SQDetailScreen(title: "Attendance History") {
            if model.attendanceHistory.isEmpty {
                SQEmptyState(
                    message: "No attendance transitions recorded.",
                    systemImage: "checkmark.seal"
                )
            } else {
                SQCard {
                    ForEach(Array(model.attendanceHistory.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SQInsetDivider(leading: SQSpace.cardInset) }
                        VStack(alignment: .leading, spacing: SQSpace.xs) {
                            Text(item.title)
                                .font(SQFont.rowTitle)
                                .foregroundStyle(SQColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.action.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(SQFont.body)
                                .foregroundStyle(SQColor.textSecondary)
                            Text(item.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(SQFont.meta)
                                .foregroundStyle(SQColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SQSpace.cardInset)
                    }
                }
            }
        }
    }
}

private struct SubmittedReviewsScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SQDetailScreen(title: "Submitted Reviews") {
            if model.submittedReviews.isEmpty {
                SQEmptyState(
                    message: "No verified-attendee reviews submitted.",
                    systemImage: "star"
                )
            } else {
                SQCard {
                    ForEach(Array(model.submittedReviews.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SQInsetDivider(leading: SQSpace.cardInset) }
                        VStack(alignment: .leading, spacing: SQSpace.xs) {
                            HStack {
                                Text(item.title)
                                    .font(SQFont.rowTitle)
                                    .foregroundStyle(SQColor.textPrimary)
                                Spacer(minLength: SQSpace.sm)
                                SQStarRating(rating: item.rating)
                            }
                            if let body = item.body, !body.isEmpty {
                                Text(body)
                                    .font(SQFont.body)
                                    .foregroundStyle(SQColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("Updated \(item.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(SQFont.meta)
                                .foregroundStyle(SQColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SQSpace.cardInset)
                    }
                }
            }
        }
    }
}

private struct MyReportsScreen: View {
    @Environment(AppModel.self) private var model

    private var reports: [EventReport] { model.reports.sorted { $0.createdAt > $1.createdAt } }

    var body: some View {
        SQDetailScreen(title: "My Reports") {
            if reports.isEmpty {
                SQEmptyState(
                    message: "Your submitted event reports will appear here with their latest status.",
                    systemImage: "flag"
                )
            } else {
                SQCard {
                    ForEach(Array(reports.enumerated()), id: \.element.id) { index, report in
                        if index > 0 { SQInsetDivider(leading: SQSpace.cardInset) }
                        VStack(alignment: .leading, spacing: SQSpace.sm) {
                            HStack {
                                Text(report.category)
                                    .font(SQFont.rowTitle)
                                    .foregroundStyle(SQColor.textPrimary)
                                Spacer(minLength: SQSpace.sm)
                                SQBadge(
                                    text: report.status.replacingOccurrences(of: "_", with: " ").capitalized,
                                    foreground: report.status == "resolved" ? SQColor.positive : SQColor.textSecondary,
                                    background: report.status == "resolved" ? SQColor.positive.opacity(0.15) : SQColor.surfaceAlt
                                )
                            }
                            Text(report.description)
                                .font(SQFont.body)
                                .foregroundStyle(SQColor.textSecondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(SQFont.meta)
                                .foregroundStyle(SQColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SQSpace.cardInset)
                    }
                }
            }
        }
    }
}

/// Five-star display used by reviews.
struct SQStarRating: View {
    let rating: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= rating ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(index <= rating ? SQColor.hueYellow : SQColor.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) out of 5")
    }
}

// MARK: - Event issue form

private struct EventIssueForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem

    @State private var detail = ""
    @State private var error: String?
    @State private var busy = false
    @State private var attachment: PhotosPickerItem?
    @State private var submitted = false

    var body: some View {
        SQSheet(title: "Report Issue", onClose: { dismiss() }) {
            SQGroupHeader(title: item.title)
                .padding(.horizontal, -SQSpace.margin)

            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.md) {
                    SQField(placeholder: "What happened?", text: $detail, axisVertical: true, lineLimit: 4...8)

                    PhotosPicker(selection: $attachment, matching: .images) {
                        HStack(spacing: SQSpace.md) {
                            SQIconTile(systemImage: "paperclip", color: SQColor.hueBlue)
                            Text(attachment == nil ? "Add photo evidence" : "Evidence photo selected")
                                .font(SQFont.rowLabel)
                                .foregroundStyle(SQColor.textPrimary)
                            Spacer()
                            if attachment != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SQColor.positive)
                            }
                        }
                    }

                    Text("Photos are stored privately and visible only to you and authorized event staff. Max 10 MB.")
                        .font(SQFont.meta)
                        .foregroundStyle(SQColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error { SQNotice(text: error, kind: submitted ? .warning : .error) }

            SQPrimaryButton(
                title: submitted ? "Done" : (busy ? "Sending…" : "Send report"),
                systemImage: submitted ? "checkmark" : "paperplane.fill",
                isLoading: busy,
                isEnabled: submitted || detail.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
            ) {
                if submitted { dismiss() } else { busy = true; Task { await submit() } }
            }
        }
    }

    private func submit() async {
        defer { busy = false }
        do {
            var evidence: Data?
            if let attachment {
                guard let source = try await attachment.loadTransferable(type: Data.self),
                      let image = UIImage(data: source),
                      let jpeg = image.jpegData(compressionQuality: 0.82) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                evidence = jpeg
            }
            let warning = try await model.submitReport(
                editionId: item.editionId,
                category: "Event issue",
                description: detail,
                priority: "normal",
                attachmentData: evidence
            )
            if let warning {
                submitted = true
                error = warning
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
