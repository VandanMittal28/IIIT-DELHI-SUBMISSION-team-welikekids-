import Foundation
import Observation
import Supabase

enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

@MainActor
@Observable
final class AppModel {
    private(set) var events: [EventFeedItem] = []
    private(set) var eventState: LoadState = .idle
    private(set) var isAuthenticated = false
    private(set) var canLoadMore = false
    private(set) var journey: [JourneyItem] = []
    private(set) var journeyState: LoadState = .idle
    private(set) var registrationStates: [UUID: LoadState] = [:]
    var searchText = ""

    let configuration: BackendConfiguration
    private let client: SupabaseClient?
    private let pageSize = 20
    private var page = 0

    init(bundle: Bundle = .main) {
        configuration = BackendConfiguration(bundle: bundle)
        if let url = configuration.url, let key = configuration.publishableKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
    }

    func restoreSession() async {
        guard let client else { return }
        isAuthenticated = (try? await client.auth.session) != nil
        if isAuthenticated, journeyState == .idle { await reloadJourney() }
    }

    func signIn(email: String, password: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        try await client.auth.signIn(email: email, password: password)
        isAuthenticated = true
        await reloadJourney()
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
        isAuthenticated = false
        journey = []
        journeyState = .idle
    }

    func reloadEvents() async {
        page = 0
        events = []
        await loadEvents(reset: true)
    }

    func loadNextPage() async {
        guard canLoadMore, eventState != .loading else { return }
        page += 1
        await loadEvents(reset: false)
    }

    private func loadEvents(reset: Bool) async {
        guard let client else {
            eventState = .failed(SidequestError.notConfigured.localizedDescription)
            return
        }
        eventState = .loading
        do {
            var query = client
                .from("published_event_feed")
                .select("id,edition_id,title,description,category,organization_name,college_name,starts_at,ends_at,price_minor,currency,eligibility")
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSearch.isEmpty {
                let safeSearch = trimmedSearch.replacingOccurrences(of: "%", with: "")
                query = query.ilike("title", pattern: "%\(safeSearch)%")
            }
            let start = page * pageSize
            let response: [EventFeedItem] = try await query
                .order("starts_at", ascending: true)
                .range(from: start, to: start + pageSize - 1)
                .execute()
                .value
            events = reset ? response : events + response
            canLoadMore = response.count == pageSize
            eventState = .loaded
        } catch {
            if !reset { page = max(0, page - 1) }
            eventState = .failed(error.localizedDescription)
        }
    }

    func reloadJourney() async {
        guard let client else {
            journeyState = .failed(SidequestError.notConfigured.localizedDescription)
            return
        }
        guard isAuthenticated else {
            journey = []
            journeyState = .loaded
            return
        }
        journeyState = .loading
        do {
            let response: [JourneyItem] = try await client
                .from("my_journey")
                .select("registration_id,status,edition_id,event_id,title,category,event_status,organization_name,starts_at,ends_at,pass_token,pass_status,waitlist_position")
                .order("starts_at", ascending: true)
                .execute()
                .value
            journey = response
            journeyState = .loaded
        } catch {
            journeyState = .failed(error.localizedDescription)
        }
    }

    func registration(for editionId: UUID) -> JourneyItem? {
        journey.first { $0.editionId == editionId && $0.status != "cancelled" }
    }

    @discardableResult
    func register(for event: EventFeedItem) async throws -> RegistrationResult {
        guard let client else { throw SidequestError.notConfigured }
        guard isAuthenticated else { throw SidequestError.authenticationRequired }
        registrationStates[event.editionId] = .loading
        let defaultsKey = "registration-request-\(event.editionId.uuidString.lowercased())"
        let requestID: UUID
        if let saved = UserDefaults.standard.string(forKey: defaultsKey), let parsed = UUID(uuidString: saved) {
            requestID = parsed
        } else {
            requestID = UUID()
            UserDefaults.standard.set(requestID.uuidString, forKey: defaultsKey)
        }
        do {
            let result: RegistrationResult = try await client
                .rpc("register_for_event", params: [
                    "p_edition_id": event.editionId.uuidString,
                    "p_client_request_id": requestID.uuidString,
                ])
                .execute()
                .value
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            registrationStates[event.editionId] = .loaded
            await reloadJourney()
            return result
        } catch {
            registrationStates[event.editionId] = .failed(error.localizedDescription)
            throw error
        }
    }

    func cancel(_ item: JourneyItem) async throws {
        guard let client else { throw SidequestError.notConfigured }
        guard isAuthenticated else { throw SidequestError.authenticationRequired }
        _ = try await client
            .rpc("cancel_registration", params: ["p_registration_id": item.registrationId.uuidString])
            .execute()
        await reloadJourney()
    }
}

struct BackendConfiguration: Equatable {
    let url: URL?
    let publishableKey: String?

    init(bundle: Bundle) {
        let urlString = (bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (bundle.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        url = urlString.flatMap { $0.isEmpty ? nil : URL(string: $0) }
        publishableKey = key.flatMap { $0.isEmpty ? nil : $0 }
    }

    var isConfigured: Bool { url != nil && publishableKey != nil }
}

enum SidequestError: LocalizedError {
    case notConfigured, authenticationRequired
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Sidequest is not connected to an authorized backend. Add the Supabase URL and publishable key to Config/Local.xcconfig."
        case .authenticationRequired:
            "Sign in from Profile before registering."
        }
    }
}
