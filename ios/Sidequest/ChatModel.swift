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

    enum CodingKeys: String, CodingKey {
        case id, seq, body
        case channelId = "channel_id", authorId = "author_id", authorName = "author_name", authorCollege = "author_college"
        case createdAt = "created_at", isMine = "is_mine"
    }
}

/// A message the student sent that the server has not confirmed yet. Its id is the client request id,
/// so retrying can never create a duplicate.
struct PendingChatMessage: Identifiable, Equatable {
    let id: UUID
    let body: String
    let createdAt: Date
    var failed: Bool
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

    var totalUnread: Int { rooms.reduce(0) { $0 + $1.unreadCount } }

    private let client: SupabaseClient?
    private var roomChannels: [UUID: RealtimeChannelV2] = [:]
    private var roomTasks: [UUID: [Task<Void, Never>]] = [:]
    private var roomsRefreshTask: Task<Void, Never>?

    init(client: SupabaseClient?) { self.client = client }

    // MARK: Validation (shared with the composer; the server enforces the same rules)

    nonisolated static func validationError(for body: String) -> String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Write something before sending." }
        if trimmed.count > maxLength { return "Messages can be up to \(maxLength) characters." }
        return nil
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
        guard let client else { historyState[roomId] = .failed(SidequestError.notConfigured.localizedDescription); return }
        if messages[roomId] == nil { historyState[roomId] = .loading }
        do {
            let latest: [ChatMessage] = try await client.rpc("get_channel_messages", params: MessagePageRequest(channelId: roomId, beforeSeq: nil, afterSeq: nil, limit: Self.pageSize)).execute().value
            messages[roomId] = Self.merge(messages[roomId] ?? [], with: latest)
            if hasOlder[roomId] == nil { hasOlder[roomId] = latest.count == Self.pageSize }
            historyState[roomId] = .loaded
        } catch {
            historyState[roomId] = .failed(Self.friendly(error).localizedDescription)
            return
        }
        await subscribe(roomId, client: client)
        await markRead(roomId)
    }

    func close(_ roomId: UUID) async {
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

    func send(_ body: String, in roomId: UUID) async {
        if let problem = Self.validationError(for: body) { sendErrors[roomId] = problem; return }
        let item = PendingChatMessage(id: UUID(), body: body.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: .now, failed: false)
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
            let result: SendResult = try await client.rpc("send_channel_message", params: SendRequest(channelId: roomId, body: item.body, clientMessageId: item.id)).execute().value
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
        for roomId in Array(roomChannels.keys) { await close(roomId) }
        roomsRefreshTask?.cancel()
        rooms = []; roomsState = .idle; messages = [:]; historyState = [:]; hasOlder = [:]; pending = [:]; connection = [:]; sendErrors = [:]
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
    enum CodingKeys: String, CodingKey { case channelId = "p_channel_id", body = "p_body", clientMessageId = "p_client_message_id" }
}

private struct SendResult: Decodable {
    let messageId: UUID
    let seq: Int64
    enum CodingKeys: String, CodingKey { case seq; case messageId = "message_id" }
}
