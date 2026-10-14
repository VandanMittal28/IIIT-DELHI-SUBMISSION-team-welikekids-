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
                    ProgressView("Finding your chat rooms…")
                case .failed(let message) where chat.rooms.isEmpty:
                    ContentUnavailableView {
                        Label("Couldn’t load chat rooms", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try again") { Task { await chat.reloadRooms() } }
                    }
                default:
                    if chat.rooms.isEmpty {
                        ContentUnavailableView("No chat rooms yet", systemImage: "bubble.left.and.bubble.right", description: Text("Chat opens once your college confirms your student membership. Event rooms appear when you register for an event."))
                    } else {
                        List {
                            roomSection("Your college", rooms("college"))
                            roomSection("Open to all colleges", rooms("topic"))
                            roomSection("Your event rooms", rooms("event"))
                            Section { Text("Be kind. Long-press a message to report it to moderators.").font(.footnote).foregroundStyle(.secondary) }
                        }
                        .listStyle(.insetGrouped)
                    }
                }
            }
            .background(Color.sidequestMist)
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

private struct ChatRoomRow: View {
    let room: ChatRoom
    private var icon: String {
        switch room.kind {
        case "college": "building.columns.fill"
        case "event": "ticket.fill"
        default: room.title == "SideQuest Commons" ? "globe.asia.australia.fill" : "number"
        }
    }
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline).foregroundStyle(Color.sidequestInk)
                .frame(width: 40, height: 40)
                .background(Color.sidequestLime, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(room.title).font(.headline).lineLimit(1)
                    Spacer()
                    if let last = room.lastMessageAt { Text(last.formatted(.relative(presentation: .numeric))).font(.caption2).foregroundStyle(.secondary) }
                }
                Group {
                    if let body = room.lastMessageBody, let author = room.lastMessageAuthor { Text("\(author): \(body)") }
                    else { Text(room.description ?? "Say hello to start the conversation.") }
                }
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            if room.unreadCount > 0 {
                Text(room.unreadCount >= 99 ? "99+" : "\(room.unreadCount)")
                    .font(.caption.bold()).foregroundStyle(Color.sidequestInk)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.sidequestLime, in: Capsule())
            }
        }
        .padding(.vertical, 2)
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
                        ChatBubble(message: message, showsAuthor: showsAuthor)
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
                Button("Try again") { Task { await chat.open(room.id) } }
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
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message \(room.title)", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .onChange(of: draft) { chat.clearSendError(room.id) }
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
    }

    private func send() {
        let body = draft
        guard ChatModel.validationError(for: body) == nil else { return }
        draft = ""
        Task { await chat.send(body, in: room.id) }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let showsAuthor: Bool
    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 48) }
            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
                if showsAuthor && !message.isMine {
                    Text([message.authorName, message.authorCollege].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption.bold()).foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                Text(message.body)
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
