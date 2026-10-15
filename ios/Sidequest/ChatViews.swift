import ImageIO
import SwiftUI

/// Chat rooms the student can join: their college lounge, inter-college topic rooms, and their event rooms.
struct ChatHomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var chat: ChatModel { model.chat }
    private func rooms(_ kind: String) -> [ChatRoom] { chat.rooms.filter { $0.kind == kind } }

    var body: some View {
        NavigationStack {
            Group {
                switch chat.roomsState {
                case .idle where chat.rooms.isEmpty, .loading where chat.rooms.isEmpty:
                    ProgressView()
                case .failed(let message) where chat.rooms.isEmpty:
                    VStack(alignment: .leading, spacing: SQSpace.lg) {
                        SQEmptyState(message: message, systemImage: "wifi.exclamationmark")
                        SQSecondaryButton(title: "Try again") { Task { await chat.reloadRooms() } }
                    }
                    .padding(.horizontal, SQSpace.margin)
                default:
                    if chat.rooms.isEmpty {
                        SQEmptyState(
                            message: "Chat opens once your college confirms your student membership. Event rooms appear when you register for an event.",
                            systemImage: "bubble.left.and.bubble.right"
                        )
                        .padding(.horizontal, SQSpace.margin)
                    } else {
                        List {
                            roomSection("Your college", rooms("college"))
                            roomSection("Open to all colleges", rooms("topic"))
                            roomSection("Your event rooms", rooms("event"))
                            Section { Text("Be kind. Long-press a message to report it to moderators.").font(.footnote).foregroundStyle(.secondary) }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .background(SQColor.background.ignoresSafeArea())
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ChatRoom.self) { room in ChatRoomView(room: room) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await chat.reloadRooms() }
            .refreshable { await chat.reloadRooms() }
        }
    }

    @ViewBuilder private func roomSection(_ title: String, _ rooms: [ChatRoom]) -> some View {
        if !rooms.isEmpty {
            Section(title) {
                ForEach(rooms) { room in NavigationLink(value: room) { ChatRoomRow(room: room) } }
            }
        }
    }
}

struct ChatRoomRow: View {
    let room: ChatRoom
    private var icon: String {
        switch room.kind {
        case "college": "building.columns.fill"
        case "event": "ticket.fill"
        default: room.title == "SideQuest Commons" ? "globe.asia.australia.fill" : "number"
        }
    }
    var body: some View {
        HStack(spacing: SQSpace.md) {
            SQIconTile(systemImage: icon, color: SQColor.hueBlue)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: SQSpace.sm) {
                    Text(room.title)
                        .font(SQFont.rowLabel)
                        .foregroundStyle(SQColor.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let last = room.lastMessageAt {
                        Text(last.formatted(.relative(presentation: .numeric)))
                            .font(SQFont.meta)
                            .foregroundStyle(SQColor.textTertiary)
                    }
                }
                Group {
                    if let body = room.lastMessageBody, let author = room.lastMessageAuthor { Text("\(author): \(body)") }
                    else { Text(room.description ?? "Say hello to start the conversation.") }
                }
                .font(SQFont.body)
                .foregroundStyle(SQColor.textSecondary)
                .lineLimit(2)
            }
            if room.unreadCount > 0 {
                Text(room.unreadCount >= 99 ? "99+" : "\(room.unreadCount)")
                    .font(SQFont.meta)
                    .foregroundStyle(SQColor.onPrimary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(SQColor.primaryFill, in: Capsule())
            }
        }
        .padding(.vertical, SQSpace.sm)
        .accessibilityElement(children: .combine)
        .accessibilityValue(room.unreadCount > 0 ? "\(room.unreadCount) unread" : "")
    }
}

struct ChatRoomView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let room: ChatRoom
    @State private var draft = ""
    @State private var reporting: ChatMessage?
    @State private var chosenMentions: [MentionCandidate] = []
    @State private var mentionQuery: String?
    @State private var suggestions: [MentionCandidate] = []
    @FocusState private var composerFocused: Bool

    private var chat: ChatModel { model.chat }
    private var messages: [ChatMessage] { chat.messages[room.id] ?? [] }
    private var pending: [PendingChatMessage] { chat.pending[room.id] ?? [] }
    private var draftProblem: String? { ChatModel.validationError(for: draft) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    historyHeader
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        let showsAuthor = index == 0 || messages[index - 1].authorId != message.authorId
                        ChatBubble(message: message, showsAuthor: showsAuthor, avatarURL: message.authorAvatarPath.flatMap { chat.avatarURLs[$0] })
                            .contextMenu {
                                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.body }
                                if !message.isMine { Button("Report message", systemImage: "flag") { reporting = message } }
                            }
                    }
                    ForEach(pending) { item in PendingBubble(item: item, roomId: room.id) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            .onChange(of: pending.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        .background(Color.sidequestMist)
        .safeAreaInset(edge: .top) { connectionBanner }
        .safeAreaInset(edge: .bottom) { composer }
        .navigationTitle(room.title)
        .navigationBarTitleDisplayMode(.inline)
        // Opened from the Community tab: give the composer and mention list the tab bar's space.
        .toolbar(.hidden, for: .tabBar)
        .task { await chat.open(room.id) }
        .onDisappear { Task { await chat.close(room.id) } }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await chat.catchUp(room.id) } } }
        .sheet(item: $reporting) { message in ChatReportSheet(message: message) }
    }

    @ViewBuilder private var historyHeader: some View {
        switch chat.historyState[room.id] {
        case .loading where messages.isEmpty, .idle where messages.isEmpty, nil:
            ProgressView("Loading messages…").padding(.top, 40)
        case .failed(let message) where messages.isEmpty:
            ContentUnavailableView {
                Label("Couldn’t load messages", systemImage: "wifi.exclamationmark")
            } description: { Text(message) } actions: {
                Button("Try again") { Task { await chat.load(room.id) } }
            }
        default:
            if messages.isEmpty && pending.isEmpty {
                ContentUnavailableView("No messages yet", systemImage: "hand.wave", description: Text(room.description ?? "Say hello to start the conversation."))
                    .padding(.top, 40)
            } else if chat.hasOlder[room.id] == true {
                Button { Task { await chat.loadOlder(room.id) } } label: {
                    if chat.historyState[room.id] == .loading { ProgressView() } else { Text("Load earlier messages").font(.footnote.bold()) }
                }
                .buttonStyle(.bordered)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private var connectionBanner: some View {
        switch chat.connection[room.id] {
        case .reconnecting, .offline:
            Label(chat.connection[room.id] == .offline ? "Offline — messages will refresh when you reconnect." : "Reconnecting…", systemImage: "wifi.exclamationmark")
                .font(.footnote.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.2))
        default:
            EmptyView()
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = chat.sendErrors[room.id] {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let mentionQuery { mentionSuggestions(mentionQuery) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message \(room.title)", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .onChange(of: draft) {
                        chat.clearSendError(room.id)
                        mentionQuery = ChatModel.activeMentionQuery(in: draft)
                    }
                Button { send() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)).foregroundStyle(Color.sidequestInk, Color.sidequestLime)
                }
                .disabled(draftProblem != nil)
                .accessibilityLabel("Send message")
            }
            if draft.count > ChatModel.maxLength - 200 {
                Text("\(draft.count)/\(ChatModel.maxLength)").font(.caption2).foregroundStyle(draft.count > ChatModel.maxLength ? .red : .secondary)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
        .task(id: mentionQuery) { await searchMentions() }
    }

    /// Students in this room matching the "@query"; kept short so it fits above the keyboard on small iPhones.
    private func mentionSuggestions(_ query: String) -> some View {
        Group {
            if suggestions.isEmpty {
                Text(query.isEmpty ? "Type a name to tag someone in this room." : "No one in this room matches “\(query)”.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { candidate in
                            Button { pickMention(candidate) } label: {
                                HStack(spacing: 10) {
                                    ChatAvatar(name: candidate.displayName, path: candidate.avatarPath, size: 28)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(candidate.displayName).font(.subheadline.bold()).foregroundStyle(Color.sidequestInk)
                                        if let college = candidate.collegeName { Text(college).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Mention \(candidate.displayName)")
                        }
                    }
                }
                .frame(maxHeight: 168)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private func searchMentions() async {
        guard let query = mentionQuery else { suggestions = []; return }
        if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
        guard !Task.isCancelled else { return }
        let found = (try? await chat.mentionCandidates(in: room.id, matching: query)) ?? []
        if !Task.isCancelled { suggestions = found }
    }

    private func pickMention(_ candidate: MentionCandidate) {
        draft = ChatModel.insertingMention(candidate.displayName, into: draft)
        if !chosenMentions.contains(candidate) { chosenMentions.append(candidate) }
        composerFocused = true
    }

    private func send() {
        let body = draft
        guard ChatModel.validationError(for: body) == nil else { return }
        let mentions = chosenMentions
        draft = ""
        chosenMentions = []
        Task { await chat.send(body, mentioning: mentions, in: room.id) }
    }
}

private struct ChatBubble: View {
    static let avatarSize: CGFloat = 30
    let message: ChatMessage
    let showsAuthor: Bool
    let avatarURL: URL?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isMine { Spacer(minLength: 48) }
            else if showsAuthor {
                ChatAvatar(name: message.authorName, path: message.authorAvatarPath, url: avatarURL, size: Self.avatarSize).padding(.top, 6)
            } else {
                Color.clear.frame(width: Self.avatarSize, height: 1)
            }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
                if showsAuthor && !message.isMine {
                    Text([message.authorName, message.authorCollege].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                Text(styledBody)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(Color.sidequestInk)
                    .background(message.isMine ? Color.sidequestLime : .white, in: RoundedRectangle(cornerRadius: 16))
                    .textSelection(.enabled)
                Text(message.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.tertiary)
            }
            if !message.isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.isMine ? "You" : message.authorName), \(message.body), \(message.createdAt.formatted(date: .omitted, time: .shortened))")
    }
}

extension ChatBubble {
    /// Tags are bold on a tinted background so they stand out in both bubble colours.
    var styledBody: AttributedString {
        var text = AttributedString(message.body)
        for range in ChatModel.mentionRanges(in: message.body, mentions: message.mentions) {
            let start = text.characters.index(text.startIndex, offsetBy: message.body.distance(from: message.body.startIndex, to: range.lowerBound))
            let end = text.characters.index(start, offsetBy: message.body.distance(from: range.lowerBound, to: range.upperBound))
            text[start..<end].font = .body.bold()
            text[start..<end].backgroundColor = message.isMine ? Color.white.opacity(0.6) : Color.sidequestLime.opacity(0.6)
        }
        return text
    }
}

/// A student's profile picture, or their initials when there is none or it can't be loaded.
struct ChatAvatar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let name: String
    let path: String?
    var url: URL? = nil
    var size: CGFloat = 30
    @State private var image: UIImage?

    private var resolvedURL: URL? { url ?? path.flatMap { model.chat.avatarURLs[$0] } }
    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color.sidequestInk
                Text(initials).font(.system(size: size * 0.38, weight: .bold, design: .rounded)).foregroundStyle(Color.sidequestLime)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
        .task(id: resolvedURL) {
            guard let path else { image = nil; return }
            if let cached = AvatarImageCache.shared.cached(path) { image = cached; return }
            guard let resolvedURL else { return }
            image = await AvatarImageCache.shared.image(for: path, url: resolvedURL, pixelSize: size * displayScale)
        }
    }
}

/// In-memory cache of small, already-decoded profile pictures keyed by storage path (signed URLs change, paths don't).
@MainActor
final class AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var loading: [String: Task<UIImage?, Never>] = [:]

    private init() { cache.countLimit = 300 }

    func cached(_ path: String) -> UIImage? { cache.object(forKey: path as NSString) }

    func image(for path: String, url: URL, pixelSize: CGFloat) async -> UIImage? {
        if let hit = cached(path) { return hit }
        if let running = loading[path] { return await running.value }
        let task = Task.detached(priority: .utility) { () -> UIImage? in
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return AvatarImageCache.downsample(data, maxPixels: pixelSize)
        }
        loading[path] = task
        let image = await task.value
        loading[path] = nil
        if let image { cache.setObject(image, forKey: path as NSString) }
        return image
    }

    /// Decodes straight to avatar size so scrolling never decodes full-size photos. Invalid data returns nil.
    nonisolated static func downsample(_ data: Data, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 1),
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

private struct PendingBubble: View {
    @Environment(AppModel.self) private var model
    let item: PendingChatMessage
    let roomId: UUID
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.body)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(Color.sidequestInk.opacity(item.failed ? 1 : 0.6))
                    .background(Color.sidequestLime.opacity(item.failed ? 0.4 : 0.7), in: RoundedRectangle(cornerRadius: 16))
                if item.failed {
                    HStack(spacing: 12) {
                        Button("Retry") { Task { await model.chat.retry(item.id, in: roomId) } }
                        Button("Delete", role: .destructive) { model.chat.discard(item.id, in: roomId) }
                    }
                    .font(.caption.bold())
                    Label("Not sent", systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(.red)
                } else {
                    Text("Sending…").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

private struct ChatReportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let message: ChatMessage
    @State private var reason = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Reported message") {
                    Text(message.authorName).font(.caption.bold())
                    Text(message.body).foregroundStyle(.secondary)
                }
                Section("Reason") { TextField("Why should moderators review this?", text: $reason, axis: .vertical).lineLimit(3...8) }
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? "Submitting…" : "Submit report") {
                    busy = true
                    Task {
                        do { try await model.reportMessage(messageId: message.id, description: reason); dismiss() }
                        catch { self.error = error.localizedDescription; busy = false }
                    }
                }
                .disabled(busy || reason.trimmingCharacters(in: .whitespacesAndNewlines).count < 5)
            }
            .navigationTitle("Report message")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
