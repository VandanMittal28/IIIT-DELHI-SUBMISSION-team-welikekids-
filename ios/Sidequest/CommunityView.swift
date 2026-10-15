import PhotosUI
import SwiftUI
import UIKit

// Community, rebuilt with the chat-list rows of screenshot 07 and the grouped cards of
// screenshot 01. The three areas (Updates / Forum / Clubs) are now selected with a chip row
// under the header instead of a segmented control buried in a `List` section.

private enum CommunitySection: String, CaseIterable, Identifiable {
    case updates = "Updates"
    case discussions = "Forum"
    case organizations = "Clubs"
    var id: Self { self }

    var glyph: String {
        switch self {
        case .updates: "megaphone"
        case .discussions: "text.bubble"
        case .organizations: "person.3"
        }
    }
}

struct CommunityView: View {
    @Environment(AppModel.self) private var model
    @State private var section = CommunitySection.updates
    @State private var organizationSearch = ""
    @State private var creatingThread = false

    private var visibleOrganizations: [OrganizationProfile] {
        let query = organizationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.organizations }
        return model.organizations.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var unreadCount: Int {
        model.notifications.filter { $0.readAt == nil }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SQScreenHeader(title: "Community", avatarSeed: "Sidequest") {
                    if model.isAuthenticated {
                        SQActionCapsule {
                            SQCapsuleGlyph(
                                systemImage: "bell",
                                showsBadge: unreadCount > 0,
                                accessibilityTitle: unreadCount > 0 ? "\(unreadCount) unread notifications" : "Notifications"
                            ) {
                                section = .updates
                            }
                            SQCapsuleGlyph(systemImage: "square.and.pencil", accessibilityTitle: "Start a discussion") {
                                section = .discussions
                                creatingThread = true
                            }
                        }
                    }
                }
                .padding(.bottom, SQSpace.lg)

                if model.isAuthenticated {
                    sectionPicker.padding(.bottom, SQSpace.lg)
                }

                content
            }
            .background(SQColor.plainBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .task { if model.isAuthenticated { await model.reloadCommunity(); await model.chat.reloadRooms() } }
            .sheet(isPresented: $creatingThread) { NewDiscussionThreadView() }
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: SQSpace.sm) {
                ForEach(CommunitySection.allCases) { item in
                    SQChip(
                        title: item.rawValue,
                        systemImage: item.glyph,
                        color: SQColor.categorical(for: item.rawValue),
                        isSelected: section == item
                    ) {
                        section = item
                    }
                }
            }
            .padding(.horizontal, SQSpace.margin)
        }
    }

    @ViewBuilder private var content: some View {
        if !model.isAuthenticated {
            wrapper {
                SQEmptyState(
                    message: "Official updates and discussions are scoped to your real event registrations. Sign in from Profile.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .padding(.horizontal, SQSpace.margin)
            }
        } else if case .loading = model.communityState, model.announcements.isEmpty {
            wrapper {
                SQEmptyState(message: "Loading authoritative updates…", systemImage: "megaphone")
                    .padding(.horizontal, SQSpace.margin)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SQSpace.cardToHeader) {
                    switch section {
                    case .updates: updatesSection
                    case .discussions: forumSection
                    case .organizations: clubsSection
                    }
                }
                .padding(.horizontal, SQSpace.margin)
                .padding(.bottom, SQSpace.tabBarClearance)
            }
            .refreshable { await model.reloadCommunity(); await model.chat.reloadRooms() }
        }
    }

    private func wrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpace.xxl) { content() }
                .padding(.top, SQSpace.sm)
                .padding(.bottom, SQSpace.tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Updates

    @ViewBuilder private var updatesSection: some View {
        group("Official event announcements") {
            if model.announcements.isEmpty {
                SQEmptyState(message: "No announcements for your events.", systemImage: "megaphone")
            } else {
                SQCard {
                    ForEach(Array(model.announcements.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SQInsetDivider() }
                        HStack(alignment: .top, spacing: 14) {
                            SQIconTile(
                                systemImage: item.kind == "venue_change" ? "arrow.triangle.swap" : "megaphone.fill",
                                color: item.kind == "venue_change" ? SQColor.hueOrange : SQColor.hueRed
                            )
                            VStack(alignment: .leading, spacing: SQSpace.xs) {
                                Text(item.title)
                                    .font(SQFont.rowTitle)
                                    .foregroundStyle(SQColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.body)
                                    .font(SQFont.body)
                                    .foregroundStyle(SQColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(SQFont.meta)
                                    .foregroundStyle(SQColor.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(SQSpace.cardInset)
                    }
                }
            }
        }

        group("Your inbox") {
            if model.notifications.isEmpty {
                SQEmptyState(message: "No notifications yet.", systemImage: "bell")
            } else {
                SQCard {
                    ForEach(Array(model.notifications.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SQInsetDivider() }
                        HStack(alignment: .top, spacing: 14) {
                            SQIconTile(systemImage: "bell.fill", color: item.readAt == nil ? SQColor.hueBlue : SQColor.textTertiary)
                            VStack(alignment: .leading, spacing: SQSpace.xs) {
                                Text(item.title)
                                    .font(SQFont.rowTitle)
                                    .foregroundStyle(SQColor.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.body)
                                    .font(SQFont.body)
                                    .foregroundStyle(SQColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(SQFont.meta)
                                    .foregroundStyle(SQColor.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(SQSpace.cardInset)
                    }
                }
            }
        }

        // Chat list, styled like screenshot 07: avatar, title, subtitle, no dividers.
        // Rooms, history and the composer all come from the shared ChatModel.
        group("Chat rooms") {
            if model.chat.rooms.isEmpty {
                if case .failed(let message) = model.chat.roomsState {
                    SQEmptyState(message: message, systemImage: "exclamationmark.triangle")
                } else {
                    SQEmptyState(
                        message: "Chat opens once your college confirms your membership. Register for an event to join its room.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(model.chat.rooms) { room in
                        NavigationLink {
                            ChatRoomView(room: room)
                        } label: {
                            ChatRoomRow(room: room)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Forum

    @ViewBuilder private var forumSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.headerToCard) {
            SQSectionHeader(title: "Campus forum")
                .padding(.horizontal, -SQSpace.margin)
            Text("Start a topic and let your college community join in.")
                .font(SQFont.body)
                .foregroundStyle(SQColor.textSecondary)
            SQPrimaryButton(title: "Start a thread", systemImage: "square.and.pencil") {
                creatingThread = true
            }
        }

        if model.discussionThreads.isEmpty {
            SQEmptyState(
                message: "No discussions yet. Be the first to start a thread. Set your college in Profile if prompted.",
                systemImage: "text.bubble"
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(model.discussionThreads.enumerated()), id: \.element.id) { index, thread in
                    NavigationLink {
                        DiscussionThreadView(thread: thread)
                    } label: {
                        VStack(alignment: .leading, spacing: SQSpace.xs) {
                            Text(thread.title)
                                .font(SQFont.rowTitle)
                                .foregroundStyle(SQColor.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(thread.body)
                                .font(SQFont.body)
                                .foregroundStyle(SQColor.textSecondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(SQFont.meta)
                                .foregroundStyle(SQColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, SQSpace.lg)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < model.discussionThreads.count - 1 {
                        Rectangle().fill(SQColor.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - Clubs

    @ViewBuilder private var clubsSection: some View {
        group("College profiles") {
            if model.collegeProfiles.isEmpty {
                SQEmptyState(message: "No colleges available.", systemImage: "building.columns")
            } else {
                SQCard {
                    ForEach(Array(model.collegeProfiles.enumerated()), id: \.element.id) { index, college in
                        if index > 0 { SQInsetDivider() }
                        NavigationLink {
                            CollegeProfileView(
                                college: college,
                                organizations: model.organizations.filter { $0.collegeId == college.id }
                            )
                        } label: {
                            SQListRow(title: college.name, systemImage: "building.columns.fill", iconColor: SQColor.hueIndigo)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }

        group("Find a society or organization") {
            SQField(placeholder: "Search societies and clubs", text: $organizationSearch, systemImage: "magnifyingglass")
                .textInputAutocapitalization(.never)

            if visibleOrganizations.isEmpty {
                SQEmptyState(
                    message: organizationSearch.isEmpty
                        ? "No organizations published yet."
                        : "No societies match “\(organizationSearch)”.",
                    systemImage: "person.3"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleOrganizations) { organization in
                        HStack(spacing: SQSpace.lg) {
                            NavigationLink {
                                OrganizationProfileView(
                                    organization: organization,
                                    collegeName: model.collegeProfiles.first { $0.id == organization.collegeId }?.name
                                )
                            } label: {
                                HStack(spacing: SQSpace.lg) {
                                    SQAvatar(seed: organization.name, size: SQSize.avatarLarge)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(organization.name)
                                            .font(SQFont.rowLabel)
                                            .foregroundStyle(SQColor.textPrimary)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(1)
                                        if let detail = organization.description {
                                            Text(detail)
                                                .font(SQFont.body)
                                                .foregroundStyle(SQColor.textSecondary)
                                                .multilineTextAlignment(.leading)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            FollowButton(organizationId: organization.id)
                        }
                        .frame(height: 68)
                    }
                }
            }
        }
    }

    @ViewBuilder private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SQSpace.headerToCard) {
            SQGroupHeader(title: title)
                .padding(.horizontal, -SQSpace.margin)
            content()
        }
    }
}

private struct FollowButton: View {
    @Environment(AppModel.self) private var model
    let organizationId: UUID

    private var isFollowing: Bool { model.followedOrganizationIds.contains(organizationId) }

    var body: some View {
        Button {
            Task { try? await model.toggleOrganizationFollow(organizationId) }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(SQFont.metaEmphasis)
                .foregroundStyle(isFollowing ? SQColor.textSecondary : SQColor.onLight)
                .padding(.horizontal, SQSpace.lg)
                .frame(height: 36)
                .background(
                    isFollowing ? SQColor.surfaceAlt : SQColor.lime,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - New thread

private struct NewDiscussionThreadView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var bodyText = ""
    @State private var error: String?
    @State private var busy = false

    private var canPost: Bool {
        !busy
            && title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
            && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
    }

    var body: some View {
        SQSheet(title: "New Thread", onClose: { dismiss() }) {
            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.md) {
                    SQField(placeholder: "Thread title", text: $title, systemImage: "text.cursor")
                    SQField(placeholder: "What do you want to discuss?", text: $bodyText, axisVertical: true, lineLimit: 4...10)
                }
            }
            if let error { SQNotice(text: error, kind: .error) }
            SQPrimaryButton(
                title: busy ? "Posting…" : "Create thread",
                systemImage: "paperplane.fill",
                isLoading: busy,
                isEnabled: canPost
            ) {
                busy = true
                Task {
                    do {
                        try await model.createDiscussionThread(title: title, body: bodyText)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                        busy = false
                    }
                }
            }
        }
    }
}

// MARK: - Thread

private struct DiscussionThreadView: View {
    @Environment(AppModel.self) private var model
    let thread: DiscussionThread
    @State private var reply = ""
    @State private var error: String?
    @State private var busy = false

    private var replies: [DiscussionReply] { model.discussionReplies[thread.id] ?? [] }

    var body: some View {
        SQDetailScreen(title: "Discussion") {
            VStack(alignment: .leading, spacing: SQSpace.sm) {
                Text(thread.title)
                    .font(SQFont.sectionTitle)
                    .foregroundStyle(SQColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(thread.body)
                    .font(SQFont.rowLabel)
                    .foregroundStyle(SQColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Started \(thread.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(SQFont.meta)
                    .foregroundStyle(SQColor.textTertiary)
            }

            SQGroupHeader(title: "\(replies.count) \(replies.count == 1 ? "reply" : "replies")")
                .padding(.horizontal, -SQSpace.margin)

            if replies.isEmpty {
                SQEmptyState(message: "No replies yet. Add the first one.", systemImage: "text.bubble")
            } else {
                SQCard {
                    ForEach(Array(replies.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { SQInsetDivider(leading: SQSpace.cardInset) }
                        VStack(alignment: .leading, spacing: SQSpace.xs) {
                            Text(item.body)
                                .font(SQFont.body)
                                .foregroundStyle(SQColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(SQFont.meta)
                                .foregroundStyle(SQColor.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SQSpace.cardInset)
                    }
                }
            }

            SQField(placeholder: "Write a reply", text: $reply, axisVertical: true, lineLimit: 2...6)
            if let error { SQNotice(text: error, kind: .error) }
            SQPrimaryButton(
                title: busy ? "Posting…" : "Reply",
                systemImage: "paperplane.fill",
                isLoading: busy,
                isEnabled: !busy && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                busy = true
                Task {
                    do {
                        try await model.replyToDiscussion(threadId: thread.id, body: reply)
                        reply = ""
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                    busy = false
                }
            }
        }
        .task {
            do { try await model.reloadDiscussionReplies(threadId: thread.id) }
            catch { self.error = error.localizedDescription }
        }
    }
}

// MARK: - College / organization

private struct CollegeProfileView: View {
    let college: CollegeProfile
    let organizations: [OrganizationProfile]

    var body: some View {
        SQDetailScreen(title: college.name) {
            SQCard {
                SQListRow(title: "Name", subtitle: college.name, accessory: .none)
                SQInsetDivider(leading: SQSpace.cardInset)
                SQListRow(title: "Time zone", subtitle: college.timezone, accessory: .none)
                if let latitude = college.latitude, let longitude = college.longitude {
                    SQInsetDivider(leading: SQSpace.cardInset)
                    SQListRow(
                        title: "Coordinates",
                        subtitle: "\(latitude.formatted()), \(longitude.formatted())",
                        accessory: .none
                    )
                }
            }

            SQGroupHeader(title: "Clubs and organizations")
                .padding(.horizontal, -SQSpace.margin)

            if organizations.isEmpty {
                SQEmptyState(message: "No active organizations yet.", systemImage: "person.3")
            } else {
                SQCard {
                    ForEach(Array(organizations.enumerated()), id: \.element.id) { index, organization in
                        if index > 0 { SQInsetDivider(leading: SQSpace.cardInset) }
                        VStack(alignment: .leading, spacing: SQSpace.xs) {
                            Text(organization.name)
                                .font(SQFont.rowTitle)
                                .foregroundStyle(SQColor.textPrimary)
                            if let description = organization.description {
                                Text(description)
                                    .font(SQFont.body)
                                    .foregroundStyle(SQColor.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SQSpace.cardInset)
                    }
                }
            }
        }
    }
}

private struct OrganizationProfileView: View {
    @Environment(AppModel.self) private var model
    let organization: OrganizationProfile
    let collegeName: String?

    var body: some View {
        SQDetailScreen(title: organization.name) {
            HStack(spacing: SQSpace.lg) {
                SQAvatar(seed: organization.name, size: 72)
                VStack(alignment: .leading, spacing: 2) {
                    Text(organization.name)
                        .font(SQFont.sectionTitle)
                        .foregroundStyle(SQColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let collegeName {
                        Text(collegeName)
                            .font(SQFont.body)
                            .foregroundStyle(SQColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            if let description = organization.description {
                Text(description)
                    .font(SQFont.rowLabel)
                    .foregroundStyle(SQColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SQPrimaryButton(
                title: model.followedOrganizationIds.contains(organization.id) ? "Unfollow organization" : "Follow organization",
                systemImage: model.followedOrganizationIds.contains(organization.id) ? "checkmark" : "plus"
            ) {
                Task { try? await model.toggleOrganizationFollow(organization.id) }
            }
        }
    }
}

// MARK: - Channel

// MARK: - Reporting

struct ReportForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem

    @State private var category = "Safety"
    @State private var detail = ""
    @State private var priority = "normal"
    @State private var error: String?
    @State private var busy = false
    @State private var attachment: PhotosPickerItem?
    @State private var submitted = false

    private var canSubmit: Bool {
        submitted || (!busy
            && category.trimmingCharacters(in: .whitespaces).count >= 2
            && detail.trimmingCharacters(in: .whitespaces).count >= 5)
    }

    var body: some View {
        SQSheet(title: "Report an Issue", onClose: { dismiss() }) {
            SQGroupHeader(title: item.title)
                .padding(.horizontal, -SQSpace.margin)

            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.md) {
                    SQField(placeholder: "Category", text: $category, systemImage: "tag")
                    Picker("Priority", selection: $priority) {
                        Text("Low").tag("low")
                        Text("Normal").tag("normal")
                        Text("High").tag("high")
                        Text("Urgent").tag("urgent")
                    }
                    .pickerStyle(.segmented)
                    SQField(placeholder: "What happened?", text: $detail, axisVertical: true, lineLimit: 4...10)

                    // See the note in AccountView: the label closure is nonisolated.
                    let hasAttachment = attachment != nil
                    PhotosPicker(selection: $attachment, matching: .images) {
                        HStack(spacing: SQSpace.md) {
                            SQIconTile(systemImage: "paperclip", color: SQColor.hueBlue)
                            Text(hasAttachment ? "Evidence photo selected" : "Choose evidence photo")
                                .font(SQFont.rowLabel)
                                .foregroundStyle(SQColor.textPrimary)
                            Spacer()
                            if hasAttachment {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(SQColor.positive)
                            }
                        }
                    }

                    Text("The photo stays in protected report storage and is visible only to you and authorized event staff.")
                        .font(SQFont.meta)
                        .foregroundStyle(SQColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let error { SQNotice(text: error, kind: submitted ? .warning : .error) }

            SQPrimaryButton(
                title: submitted ? "Done" : (busy ? "Submitting…" : "Submit report"),
                systemImage: submitted ? "checkmark" : "flag.fill",
                isLoading: busy,
                isEnabled: canSubmit
            ) {
                if submitted { dismiss() } else { busy = true; Task { await submit() } }
            }
        }
    }

    @MainActor private func submit() async {
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
                category: category,
                description: detail,
                priority: priority,
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
