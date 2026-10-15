import Foundation
import Observation
import Supabase

struct ChatRoom: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let kind: String
    let title: String
    let description: String?
    let collegeName: String?
    let startsAt: Date?
    let lastMessageBody: String?
    let lastMessageAuthor: String?
    let lastMessageAt: Date?
    let unreadCount: Int
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, kind, title, description
        case collegeName = "college_name", startsAt = "starts_at"
        case lastMessageBody = "last_message_body", lastMessageAuthor = "last_message_author", lastMessageAt = "last_message_at"
        case unreadCount = "unread_count", sortOrder = "sort_order"
    }
}

private struct EventChannelReference: Decodable {
    let id: UUID
    let kind: String
    let title: String?
    let description: String?
}

struct ChatMessage: Decodable, Identifiable, Equatable {
    let id: UUID
    let seq: Int64
    let channelId: UUID
    let authorId: UUID
    let authorName: String
    let authorCollege: String?
    let body: String
    let createdAt: Date
    let isMine: Bool
    /// Storage path of the sender's profile picture; nil shows the default avatar.
    var authorAvatarPath: String? = nil
    /// Students tagged in this message, in the order they appear in the body.
    var mentions: [ChatMention] = []

    enum CodingKeys: String, CodingKey {
        case id, seq, body, mentions
        case channelId = "channel_id", authorId = "author_id", authorName = "author_name", authorCollege = "author_college"
        case createdAt = "created_at", isMine = "is_mine", authorAvatarPath = "author_avatar_path"
    }
}

extension ChatMessage {
    // Picture and mentions are optional so rows from a server without them still decode.
    init(from decoder: Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try row.decode(UUID.self, forKey: .id), seq: try row.decode(Int64.self, forKey: .seq),
            channelId: try row.decode(UUID.self, forKey: .channelId), authorId: try row.decode(UUID.self, forKey: .authorId),
            authorName: try row.decode(String.self, forKey: .authorName), authorCollege: try row.decodeIfPresent(String.self, forKey: .authorCollege),
            body: try row.decode(String.self, forKey: .body), createdAt: try row.decode(Date.self, forKey: .createdAt),
            isMine: try row.decode(Bool.self, forKey: .isMine),
            authorAvatarPath: try row.decodeIfPresent(String.self, forKey: .authorAvatarPath),
            mentions: try row.decodeIfPresent([ChatMention].self, forKey: .mentions) ?? []
        )
    }
}

/// A tagged student. The id is the identity; the name is how the tag was written in the body.
struct ChatMention: Codable, Hashable {
    let userId: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey { case userId = "user_id", displayName = "display_name" }
}

/// A student who can see the room and may be tagged in it.
struct MentionCandidate: Decodable, Identifiable, Hashable {
    let userId: UUID
    let displayName: String
    let collegeName: String?
    let avatarPath: String?
    let recentlyActive: Bool
    var id: UUID { userId }
    enum CodingKeys: String, CodingKey {
        case userId = "user_id", displayName = "display_name", collegeName = "college_name", avatarPath = "avatar_path", recentlyActive = "recently_active"
    }
}

/// A message the student sent that the server has not confirmed yet. Its id is the client request id,
/// so retrying can never create a duplicate.
struct PendingChatMessage: Identifiable, Equatable {
    let id: UUID
    let body: String
    let createdAt: Date
    var failed: Bool
    var mentionIds: [UUID] = []
}

enum ChatConnection: Equatable { case connecting, live, reconnecting, offline }

@MainActor
@Observable
final class ChatModel {
    nonisolated static let pageSize = 50
    nonisolated static let maxLength = 2000

    private(set) var rooms: [ChatRoom] = []
    private(set) var roomsState: LoadState = .idle
    private(set) var messages: [UUID: [ChatMessage]] = [:]
    private(set) var historyState: [UUID: LoadState] = [:]
    private(set) var hasOlder: [UUID: Bool] = [:]
    private(set) var pending: [UUID: [PendingChatMessage]] = [:]
    private(set) var connection: [UUID: ChatConnection] = [:]
    private(set) var sendErrors: [UUID: String] = [:]
    /// Signed URLs for profile pictures, keyed by storage path. Shared by every room.
    private(set) var avatarURLs: [String: URL] = [:]

    var totalUnread: Int { rooms.reduce(0) { $0 + $1.unreadCount } }

    private let client: SupabaseClient?
    private var roomChannels: [UUID: RealtimeChannelV2] = [:]
    private var roomTasks: [UUID: [Task<Void, Never>]] = [:]
    private var roomsRefreshTask: Task<Void, Never>?
    /// The same room can be on screen from Discover and Community; live updates stop when the last one closes.
    private var openCount: [UUID: Int] = [:]
    private var avatarURLsSignedAt: Date?
    private var avatarRequests: Set<String> = []

    init(client: SupabaseClient?) { self.client = client }

    // MARK: Validation (shared with the composer; the server enforces the same rules)

    nonisolated static func validationError(for body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Write something before sending." }
        if trimmed.count > maxLength { return "Messages can be up to \(maxLength) characters." }
        return nil
    }

    /// The "@query" being typed at the end of the draft, if any. Names have spaces, so up to three words count.
    nonisolated static func activeMentionQuery(in draft: String) -> String? {
        guard let at = draft.lastIndex(of: "@") else { return nil }
        if at != draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
        let query = draft[draft.index(after: at)...]
        if query.contains(where: \.isNewline) || query.count > 40 || query.split(separator: " ", omittingEmptySubsequences: false).count > 3 { return nil }
        return String(query)
    }

    /// Replaces the "@query" being typed with the chosen student's tag.
    nonisolated static func insertingMention(_ name: String, into draft: String) -> String {
        guard activeMentionQuery(in: draft) != nil, let at = draft.lastIndex(of: "@") else { return draft }
        return String(draft[..<at]) + "@" + name + " "
    }

    /// Ids of chosen students whose tag is still in the text (edited-out tags are not sent).
    nonisolated static func mentionIds(in body: String, chosen: [MentionCandidate]) -> [UUID] {
        var seen = Set<UUID>()
        return chosen.filter { body.contains("@" + $0.displayName) && seen.insert($0.userId).inserted }.map(\.userId)
    }

    /// Ranges of every tag in a message body, longest names first so "@Asha Rao" is not split by "@Asha".
    nonisolated static func mentionRanges(in body: String, mentions: [ChatMention]) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        for name in Set(mentions.map(\.displayName)).sorted(by: { $0.count > $1.count }) {
            var searchStart = body.startIndex
            while let found = body.range(of: "@" + name, range: searchStart..<body.endIndex) {
                if !ranges.contains(where: { $0.overlaps(found) }) { ranges.append(found) }
                searchStart = found.upperBound
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Merges server rows into a room's history: unique by id, ordered by the server sequence.
    nonisolated static func merge(_ existing: [ChatMessage], with incoming: [ChatMessage]) -> [ChatMessage] {
        var byId = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for message in incoming { byId[message.id] = message }
        return byId.values.sorted { $0.seq < $1.seq }
    }

    // MARK: Rooms

    func reloadRooms() async {
        guard let client else { roomsState = .failed(SidequestError.notConfigured.localizedDescription); return }
        if rooms.isEmpty { roomsState = .loading }
        do {
            rooms = try await client.rpc("get_my_chat_rooms").execute().value
            roomsState = .loaded
        } catch { roomsState = .failed(Self.friendly(error).localizedDescription) }
    }

    func eventRoom(for editionId: UUID, startsAt: Date) async throws -> ChatRoom {
        guard let client else { throw SidequestError.notConfigured }
        let channel: EventChannelReference? = try await client
            .from("channels")
            .select("id,kind,title,description")
            .eq("edition_id", value: editionId.uuidString)
            .maybeSingle()
            .execute()
            .value
        guard let channel, channel.kind == "event" else { throw SidequestError.chatUnavailable }
        return ChatRoom(
            id: channel.id,
            kind: channel.kind,
            title: channel.title ?? "Event chat",
            description: channel.description,
            collegeName: nil,
            startsAt: startsAt,
            lastMessageBody: nil,
            lastMessageAuthor: nil,
            lastMessageAt: nil,
            unreadCount: 0,
            sortOrder: 100
        )
    }

    /// Coalesces bursts of message events into one room-list refresh (unread badges and previews).
    func scheduleRoomsRefresh() {
        roomsRefreshTask?.cancel()
        roomsRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            await self?.reloadRooms()
        }
    }

    // MARK: Opening a room

    func open(_ roomId: UUID) async {
        openCount[roomId, default: 0] += 1
        await load(roomId)
    }

    /// (Re)loads the newest page and starts live updates; also used by "Try again".
    func load(_ roomId: UUID) async {
        guard let client else { historyState[roomId] = .failed(SidequestError.notConfigured.localizedDescription); return }
        if messages[roomId] == nil { historyState[roomId] = .loading }
        do {
            let latest: [ChatMessage] = try await client.rpc("get_channel_messages", params: MessagePageRequest(channelId: roomId, beforeSeq: nil, afterSeq: nil, limit: Self.pageSize)).execute().value
            messages[roomId] = Self.merge(messages[roomId] ?? [], with: latest)
            requestAvatarURLs(for: latest.compactMap(\.authorAvatarPath))
            if hasOlder[roomId] == nil { hasOlder[roomId] = latest.count == Self.pageSize }
            historyState[roomId] = .loaded
        } catch {
            historyState[roomId] = .failed(Self.friendly(error).localizedDescription)
            return
        }
        guard openCount[roomId, default: 0] > 0 else { return }
        await subscribe(roomId, client: client)
        await markRead(roomId)
    }

    func close(_ roomId: UUID) async {
        openCount[roomId] = max(0, openCount[roomId, default: 0] - 1)
        guard openCount[roomId] == 0 else { return }
        openCount[roomId] = nil
        roomTasks[roomId]?.forEach { $0.cancel() }
        roomTasks[roomId] = nil
        if let channel = roomChannels.removeValue(forKey: roomId), let client { await client.removeChannel(channel) }
        connection[roomId] = nil
        await markRead(roomId)
    }

    func loadOlder(_ roomId: UUID) async {
        guard let client, hasOlder[roomId] == true, historyState[roomId] != .loading,
              let oldest = messages[roomId]?.first?.seq else { return }
        historyState[roomId] = .loading
        do {
            let older: [ChatMessage] = try await client.rpc("get_channel_messages", params: MessagePageRequest(channelId: roomId, beforeSeq: oldest, afterSeq: nil, limit: Self.pageSize)).execute().value
            messages[roomId] = Self.merge(messages[roomId] ?? [], with: older)
            requestAvatarURLs(for: older.compactMap(\.authorAvatarPath))
            hasOlder[roomId] = older.count == Self.pageSize
            historyState[roomId] = .loaded
        } catch { historyState[roomId] = .failed(Self.friendly(error).localizedDescription) }
    }

    /// Fetches everything newer than what we have (after a live event, reconnect, or returning to the app).
    func catchUp(_ roomId: UUID, afterSeq hint: Int64? = nil) async {
        guard let client else { return }
        let known = messages[roomId]?.last?.seq
        let after = [known, hint].compactMap { $0 }.min()
        do {
            var batch: [ChatMessage]
            var cursor = after
            repeat {
                batch = try await client.rpc("get_channel_messages", params: MessagePageRequest(channelId: roomId, beforeSeq: nil, afterSeq: cursor ?? 0, limit: 100)).execute().value
                messages[roomId] = Self.merge(messages[roomId] ?? [], with: batch)
                requestAvatarURLs(for: batch.compactMap(\.authorAvatarPath))
                cursor = batch.last?.seq ?? cursor
            } while batch.count == 100
            if roomChannels[roomId] != nil { await markRead(roomId) }
        } catch { /* The next live event or reconnect retries; history stays as loaded. */ }
    }

    private func subscribe(_ roomId: UUID, client: SupabaseClient) async {
        guard roomChannels[roomId] == nil else { return }
        connection[roomId] = .connecting
        let channel = client.channel("chat-room-\(roomId.uuidString.lowercased())")
        // Postgres changes are delivered only for rows the signed-in student may read (messages RLS).
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "messages", filter: .eq("channel_id", value: roomId.uuidString.lowercased()))
        let statuses = channel.statusChange
        roomChannels[roomId] = channel
        roomTasks[roomId] = [
            Task { [weak self] in
                for await insert in inserts {
                    let seq = insert.record["seq"]?.intValue.map { Int64($0) - 1 }
                    await self?.catchUp(roomId, afterSeq: seq)
                }
            },
            Task { [weak self] in
                var wasLive = false
                for await status in statuses {
                    guard let self else { return }
                    switch status {
                    case .subscribed:
                        if wasLive { await self.catchUp(roomId) }
                        wasLive = true
                        self.connection[roomId] = .live
                    case .subscribing:
                        self.connection[roomId] = wasLive ? .reconnecting : .connecting
                    case .unsubscribing, .unsubscribed:
                        if self.roomChannels[roomId] != nil { self.connection[roomId] = .offline }
                    }
                }
            },
        ]
        do { try await channel.subscribeWithError() }
        catch { connection[roomId] = .offline }
    }

    // MARK: Sending

    func send(_ body: String, mentioning chosen: [MentionCandidate] = [], in roomId: UUID) async {
        if let problem = Self.validationError(for: body) { sendErrors[roomId] = problem; return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = PendingChatMessage(id: UUID(), body: trimmed, createdAt: .now, failed: false, mentionIds: Self.mentionIds(in: trimmed, chosen: chosen))
        pending[roomId, default: []].append(item)
        await deliver(item, in: roomId)
    }

    func retry(_ pendingId: UUID, in roomId: UUID) async {
        guard let index = pending[roomId]?.firstIndex(where: { $0.id == pendingId }) else { return }
        pending[roomId]?[index].failed = false
        if let item = pending[roomId]?[index] { await deliver(item, in: roomId) }
    }

    func discard(_ pendingId: UUID, in roomId: UUID) {
        pending[roomId]?.removeAll { $0.id == pendingId }
    }

    func clearSendError(_ roomId: UUID) { sendErrors[roomId] = nil }

    private func deliver(_ item: PendingChatMessage, in roomId: UUID) async {
        guard let client else { markFailed(item.id, in: roomId, SidequestError.notConfigured.localizedDescription); return }
        sendErrors[roomId] = nil
        do {
            let result: SendResult = try await client.rpc("send_channel_message", params: SendRequest(channelId: roomId, body: item.body, clientMessageId: item.id, mentions: item.mentionIds.isEmpty ? nil : item.mentionIds)).execute().value
            await catchUp(roomId, afterSeq: result.seq - 1)
            pending[roomId]?.removeAll { $0.id == item.id }
        } catch {
            markFailed(item.id, in: roomId, Self.friendly(error).localizedDescription)
        }
    }

    private func markFailed(_ id: UUID, in roomId: UUID, _ message: String) {
        if let index = pending[roomId]?.firstIndex(where: { $0.id == id }) { pending[roomId]?[index].failed = true }
        sendErrors[roomId] = message
    }

    // MARK: Mentions

    /// Students who can see this room, matched by name on the server (which also enforces room access).
    func mentionCandidates(in roomId: UUID, matching query: String) async throws -> [MentionCandidate] {
        guard let client else { throw SidequestError.notConfigured }
        let rows: [MentionCandidate] = try await client.rpc("search_chat_mention_candidates", params: MentionSearchRequest(channelId: roomId, query: query, limit: 20)).execute().value
        requestAvatarURLs(for: rows.compactMap(\.avatarPath))
        return rows
    }

    // MARK: Profile pictures

    /// Signs any picture paths not signed yet, in one batch. URLs last an hour; the cache is re-signed after 50 minutes.
    func requestAvatarURLs(for paths: [String]) {
        guard let client else { return }
        if let signedAt = avatarURLsSignedAt, Date.now.timeIntervalSince(signedAt) > 50 * 60 {
            avatarURLs = [:]; avatarURLsSignedAt = nil
        }
        let missing = Array(Set(paths).subtracting(avatarURLs.keys).subtracting(avatarRequests))
        guard !missing.isEmpty else { return }
        avatarRequests.formUnion(missing)
        Task { [weak self] in
            let results = (try? await client.storage.from("profile-avatars").createSignedURLs(paths: missing, expiresIn: 3600)) ?? []
            guard let self else { return }
            for case let .success(path, url) in results { self.avatarURLs[path] = url }
            if self.avatarURLsSignedAt == nil { self.avatarURLsSignedAt = .now }
            // Paths that failed (deleted or no longer shared) stay unsigned and show the default avatar.
            self.avatarRequests.subtract(missing)
        }
    }

    // MARK: Read state

    private func markRead(_ roomId: UUID) async {
        guard let client else { return }
        if let index = rooms.firstIndex(where: { $0.id == roomId }), rooms[index].unreadCount > 0 {
            let room = rooms[index]
            rooms[index] = ChatRoom(id: room.id, kind: room.kind, title: room.title, description: room.description, collegeName: room.collegeName, startsAt: room.startsAt, lastMessageBody: room.lastMessageBody, lastMessageAuthor: room.lastMessageAuthor, lastMessageAt: room.lastMessageAt, unreadCount: 0, sortOrder: room.sortOrder)
        }
        _ = try? await client.rpc("mark_channel_read", params: ["p_channel_id": roomId.uuidString]).execute()
    }

    func reset() async {
        for roomId in Array(roomChannels.keys) { openCount[roomId] = 1; await close(roomId) }
        roomsRefreshTask?.cancel()
        rooms = []; roomsState = .idle; messages = [:]; historyState = [:]; hasOlder = [:]; pending = [:]; connection = [:]; sendErrors = [:]
        openCount = [:]; avatarURLs = [:]; avatarURLsSignedAt = nil; avatarRequests = []
    }

    private static func friendly(_ error: Error) -> Error {
        AppModel.isMissingMeetupBackend(code: (error as? PostgrestError)?.code) ? SidequestError.chatUnavailable : error
    }
}

private struct MessagePageRequest: Encodable {
    let channelId: UUID
    let beforeSeq: Int64?
    let afterSeq: Int64?
    let limit: Int
    enum CodingKeys: String, CodingKey { case channelId = "p_channel_id", beforeSeq = "p_before_seq", afterSeq = "p_after_seq", limit = "p_limit" }
}

private struct SendRequest: Encodable {
    let channelId: UUID
    let body: String
    let clientMessageId: UUID
    let mentions: [UUID]?
    enum CodingKeys: String, CodingKey { case channelId = "p_channel_id", body = "p_body", clientMessageId = "p_client_message_id", mentions = "p_mentions" }

    // Omit p_mentions when there are none, so a server without mention support still accepts the call.
    func encode(to encoder: Encoder) throws {
        var row = encoder.container(keyedBy: CodingKeys.self)
        try row.encode(channelId, forKey: .channelId)
        try row.encode(body, forKey: .body)
        try row.encode(clientMessageId, forKey: .clientMessageId)
        try row.encodeIfPresent(mentions, forKey: .mentions)
    }
}

private struct MentionSearchRequest: Encodable {
    let channelId: UUID
    let query: String
    let limit: Int
    enum CodingKeys: String, CodingKey { case channelId = "p_channel_id", query = "p_query", limit = "p_limit" }
}

private struct SendResult: Decodable {
    let messageId: UUID
    let seq: Int64
    enum CodingKeys: String, CodingKey { case seq; case messageId = "message_id" }
}
