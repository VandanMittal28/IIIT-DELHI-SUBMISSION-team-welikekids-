import Foundation
import Observation
import Supabase

enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

enum StudentSignUpOutcome: Equatable {
    case signedIn
    case confirmationRequired
}

@MainActor
@Observable
final class AppModel {
    private(set) var events: [EventFeedItem] = []
    private(set) var mapEvents: [EventFeedItem] = []
    private(set) var mapVenueLocations: [UUID: VenueMapLocation] = [:]
    private(set) var eventImageURLs: [UUID: URL] = [:]
    private var eventImagePaths: [UUID: String] = [:]
    private(set) var eventState: LoadState = .idle
    private(set) var isAuthenticated = false
    private(set) var canLoadMore = false
    private(set) var journey: [JourneyItem] = []
    private(set) var journeyState: LoadState = .idle
    private(set) var registrationStates: [UUID: LoadState] = [:]
    private(set) var landmarks: [Landmark] = []
    private(set) var landmarkPhotoURLs: [UUID: URL] = [:]
    private(set) var navigationState: LoadState = .idle
    private(set) var routePlan: RoutePlan?
    private(set) var floorPlans: [UUID: FloorPlan] = [:]
    private(set) var floorPlanURLs: [UUID: URL] = [:]
    private(set) var announcements: [Announcement] = []
    private(set) var reports: [EventReport] = []
    private(set) var notifications: [InboxNotification] = []
    private(set) var discussionThreads: [DiscussionThread] = []
    private(set) var discussionReplies: [UUID: [DiscussionReply]] = [:]
    private(set) var eventMedia: [UUID: [EventMediaPhoto]] = [:]
    private(set) var profile: StudentProfile?
    private(set) var colleges: [CollegeOption] = []
    private(set) var collegeProfiles:[CollegeProfile]=[]
    private(set) var campuses: [CampusPoint] = []
    private(set) var sessionsByEdition: [UUID:[EventSessionScheduleItem]] = [:]
    private(set) var reviewSummariesByEvent: [UUID:[EditionReviewSummary]] = [:]
    private(set) var attendanceHistory:[AttendanceHistoryItem]=[]
    private(set) var submittedReviews:[SubmittedReviewItem]=[]
    private(set) var organizations: [OrganizationProfile] = []
    private(set) var followedOrganizationIds: Set<UUID> = []
    private(set) var communityState: LoadState = .idle
    private(set) var meetups: [OpenMeetup] = []
    private(set) var meetupState: LoadState = .idle
    private(set) var meetupActionStates: [UUID: LoadState] = [:]
    private(set) var hostedMeetups: [OpenMeetup] = []
    private(set) var hostVenues: [HostVenueOption] = []
    private(set) var hostCollegeIds: [UUID] = []
    private(set) var hostingOptionsState: LoadState = .idle
    var searchText = ""
    var categoryFilter = ""
    var collegeFilter = ""
    var freeOnly = false
    var maxPrice = ""
    var eligibilityFilter = ""
    var upcomingDays = 0
    var selectedTab = 0
    private(set) var pendingNavigationDestinationId: UUID?
    private(set) var pendingNavigationStartId: UUID?
    private(set) var savedEventIds: Set<UUID> = []

    let configuration: BackendConfiguration
    let chat: ChatModel
    private let client: SupabaseClient?
    private let pageSize = 20
    private var page = 0
    private var liveChannel: RealtimeChannelV2?
    private var liveUpdateTasks: [Task<Void, Never>] = []

    init(bundle: Bundle = .main) {
        configuration = BackendConfiguration(bundle: bundle)
        if let url = configuration.url, let key = configuration.publishableKey {
            client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        } else {
            client = nil
        }
        chat = ChatModel(client: client)
    }

    func restoreSession() async {
        guard let client else { return }
        isAuthenticated = (try? await client.auth.session) != nil
        if isAuthenticated, journeyState == .idle { await reloadJourney(); await reloadSavedEvents(); await reloadProfile(); await startLiveUpdates() }
    }

    private func authEmail(for username: String) -> String {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("@") ? normalized : "\(normalized.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression))@sidequest.local"
    }

    func signIn(username: String, password: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        try await client.auth.signIn(email: authEmail(for: username), password: password)
        isAuthenticated = true
        await reloadJourney()
        await reloadSavedEvents()
        await reloadProfile()
        await startLiveUpdates()
    }

    func createStudentAccount(username: String, password: String) async throws -> StudentSignUpOutcome {
        guard let client else { throw SidequestError.notConfigured }
        let response = try await client.auth.signUp(
            email: authEmail(for: username),
            password: password
        )
        guard response.session != nil else {
            isAuthenticated = false
            return .confirmationRequired
        }
        isAuthenticated = true
        await reloadJourney()
        await reloadSavedEvents()
        await reloadProfile()
        await startLiveUpdates()
        return .signedIn
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
        isAuthenticated = false
        journey = []
        journeyState = .idle
        savedEventIds = []
        profile = nil
        attendanceHistory=[]
        submittedReviews=[]
        await chat.reset()
        meetups = []
        meetupState = .idle
        meetupActionStates = [:]
        hostedMeetups = []
        hostVenues = []
        hostCollegeIds = []
        hostingOptionsState = .idle
        await stopLiveUpdates()
    }

    func reloadEvents() async {
        page = 0
        events = []
        await loadEvents(reset: true)
    }

    func reloadMapEvents() async {
        guard let client else { mapEvents = events.filter { $0.endsAt >= .now }; return }
        do {
            mapEvents = try await client
                .from("published_event_feed")
                .select("id,edition_id,title,description,category,organization_name,college_name,starts_at,ends_at,price_minor,currency,eligibility,cover_image_path,venue_id,venue_name,destination_landmark_id,designated_gate_landmark_id")
                .gte("ends_at", value: Date.now.ISO8601Format())
                .order("starts_at", ascending: true)
                .limit(500)
                .execute()
                .value
        } catch {
            mapEvents = events.filter { $0.endsAt >= .now }
        }
    }

    func reloadMapVenueLocations() async {
        guard let client else { mapVenueLocations = [:]; return }
        if campuses.isEmpty {
            campuses = (try? await client.from("campuses").select("id,name,latitude,longitude").order("name").execute().value) ?? []
        }
        let venueIds = Set(mapEvents.compactMap(\.venueId) + meetups.compactMap(\.venueId))
        guard !venueIds.isEmpty else { mapVenueLocations = [:]; return }
        do {
            let locations: [VenueMapLocation] = try await client
                .from("venues")
                .select("id,campus_id,latitude,longitude")
                .in("id", values: venueIds.map(\.uuidString))
                .execute()
                .value
            mapVenueLocations = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        } catch {
            mapVenueLocations = [:]
        }
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
                .select("id,edition_id,title,description,category,organization_name,college_name,starts_at,ends_at,price_minor,currency,eligibility,cover_image_path,venue_id,venue_name,destination_landmark_id,designated_gate_landmark_id")
            let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSearch.isEmpty {
                let safeSearch = trimmedSearch.replacingOccurrences(of: "%", with: "")
                query = query.ilike("title", pattern: "%\(safeSearch)%")
            }
            if !categoryFilter.isEmpty { query = query.eq("category", value: categoryFilter) }
            if !collegeFilter.isEmpty { query = query.eq("college_name", value: collegeFilter) }
            if freeOnly { query = query.eq("price_minor", value: 0) }
            else if let maximum=Double(maxPrice),maximum>=0 { query=query.lte("price_minor",value:Int((maximum*100).rounded())) }
            let trimmedEligibility=eligibilityFilter.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:"%",with:"")
            if !trimmedEligibility.isEmpty { query=query.ilike("eligibility",pattern:"%\(trimmedEligibility)%") }
            if upcomingDays > 0 {
                let upper = Calendar.current.date(byAdding: .day, value: upcomingDays, to: .now) ?? .now
                query = query.gte("starts_at", value: Date.now.ISO8601Format()).lte("starts_at", value: upper.ISO8601Format())
            }
            let start = page * pageSize
            let response: [EventFeedItem] = try await query
                .order("starts_at", ascending: true)
                .range(from: start, to: start + pageSize - 1)
                .execute()
                .value
            events = reset ? response : events + response
            await loadEventImages(for: events)
            if reset { campuses = (try? await client.from("campuses").select("id,name,latitude,longitude").order("name").execute().value) ?? [] }
            canLoadMore = response.count == pageSize
            eventState = .loaded
        } catch {
            if !reset { page = max(0, page - 1) }
            eventState = .failed(error.localizedDescription)
        }
    }

    private func loadEventImages(for events: [EventFeedItem]) async {
        guard let client else { return }
        let paths = Dictionary(uniqueKeysWithValues: events.compactMap { event in
            event.coverImagePath.map { (event.id, $0) }
        })
        var urls = eventImageURLs.filter { event in paths[event.key] == eventImagePaths[event.key] }
        for event in events where urls[event.id] == nil {
            guard let path = event.coverImagePath else { continue }
            urls[event.id] = try? await client.storage.from("event-media").createSignedURL(path: path, expiresIn: 3600)
        }
        eventImageURLs = urls
        eventImagePaths = paths
    }

    func loadEventDetails(for event:EventFeedItem) async throws {
        guard let client else { throw SidequestError.notConfigured }
        async let sessions:[EventSessionScheduleItem] = client.from("published_event_session_schedule")
            .select("id,edition_id,title,starts_at,ends_at,venue_name,campus_name")
            .eq("edition_id",value:event.editionId).order("starts_at").execute().value
        async let summaries:[EditionReviewSummary] = client.from("edition_review_summary")
            .select("event_id,edition_id,sample_size,average_rating")
            .eq("event_id",value:event.id).execute().value
        let (loadedSessions,loadedSummaries)=try await(sessions,summaries)
        sessionsByEdition[event.editionId]=loadedSessions
        reviewSummariesByEvent[event.id]=loadedSummaries
    }

    private func refreshLoadedEventDetails() async {
        let loadedEditionIDs=Set(sessionsByEdition.keys)
        for event in events where loadedEditionIDs.contains(event.editionId) { try? await loadEventDetails(for:event) }
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
                .select("registration_id,status,edition_id,event_id,title,category,event_status,organization_name,registration_opens_at,registration_closes_at,starts_at,ends_at,pass_token,pass_status,waitlist_position,venue_name,destination_landmark_id,designated_gate_landmark_id")
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

    func reloadMeetups() async {
        guard let client else { meetupState = .failed(SidequestError.notConfigured.localizedDescription); return }
        guard isAuthenticated else { meetups = []; meetupState = .loaded; return }
        meetupState = .loading
        do {
            meetups = try await client.from("open_meetup_feed")
                .select("id,title,description,location_note,icebreaker,audience,capacity,going_count,starts_at,ends_at,status,college_name,host_name,host_headline,host_verified,venue_id,venue_name,campus_name,destination_landmark_id,participating_colleges,my_status,is_eligible,is_host")
                .eq("status", value: "published")
                .gte("ends_at", value: Date.now.ISO8601Format())
                .order("starts_at", ascending: true)
                .limit(50)
                .execute()
                .value
            meetupState = .loaded
        } catch { meetupState = .failed(Self.meetupError(error).localizedDescription) }
    }

    /// PostgREST reports a missing view (PGRST205) or function (PGRST202) when the
    /// Open Meetups migration has not been applied to the connected project.
    nonisolated static func isMissingMeetupBackend(code: String?) -> Bool {
        code == "PGRST202" || code == "PGRST205"
    }

    private static func meetupError(_ error: Error) -> Error {
        isMissingMeetupBackend(code: (error as? PostgrestError)?.code) ? SidequestError.meetupsUnavailable : error
    }

    func meetup(id: UUID) -> OpenMeetup? { meetups.first { $0.id == id } ?? hostedMeetups.first { $0.id == id } }

    /// Meetups the signed-in student hosts, including cancelled and past ones (RLS limits rows to the caller's own).
    func reloadHostedMeetups() async {
        guard let client, isAuthenticated else { hostedMeetups = []; return }
        do {
            hostedMeetups = try await client.from("open_meetup_feed")
                .select("id,title,description,location_note,icebreaker,audience,capacity,going_count,starts_at,ends_at,status,college_name,host_name,host_headline,host_verified,venue_id,venue_name,campus_name,destination_landmark_id,participating_colleges,my_status,is_eligible,is_host")
                .eq("is_host", value: true)
                .order("starts_at", ascending: false)
                .limit(30)
                .execute()
                .value
        } catch { /* Hosting list is secondary; discovery remains usable. */ }
    }

    /// Colleges the student can host for (active administrator-granted memberships) and their campus venues.
    func loadHostingOptions() async {
        guard let client else { hostingOptionsState = .failed(SidequestError.notConfigured.localizedDescription); return }
        guard isAuthenticated else { hostingOptionsState = .failed(SidequestError.authenticationRequired.localizedDescription); return }
        struct MembershipRow: Decodable { let collegeId: UUID; enum CodingKeys: String, CodingKey { case collegeId = "college_id" } }
        hostingOptionsState = .loading
        do {
            let userId = try await client.auth.session.user.id
            let memberships: [MembershipRow] = try await client.from("college_memberships")
                .select("college_id").eq("user_id", value: userId).eq("status", value: "active").execute().value
            hostCollegeIds = memberships.map(\.collegeId)
            hostVenues = hostCollegeIds.isEmpty ? [] : try await client.from("venues")
                .select("id,name,destination_landmark_id,campus:campuses!inner(name,college_id)")
                .in("campus.college_id", values: hostCollegeIds)
                .order("name")
                .execute()
                .value
            if colleges.isEmpty || profile == nil { await reloadProfile() }
            hostingOptionsState = .loaded
        } catch { hostingOptionsState = .failed(Self.meetupError(error).localizedDescription) }
    }

    /// Publishes a meetup hosted by the signed-in student. The server derives the host from the session.
    func hostMeetup(_ draft: MeetupDraft, requestId: UUID) async throws -> HostMeetupResult {
        guard let client else { throw SidequestError.notConfigured }
        guard isAuthenticated else { throw SidequestError.authenticationRequired }
        guard let collegeId = draft.collegeId, let venueId = draft.venueId else { throw SidequestError.meetupDetailsIncomplete }
        func trimmed(_ text: String) -> String? { let value = text.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
        do {
            let result: HostMeetupResult = try await client.rpc("host_open_meetup", params: HostMeetupRequest(
                pClientRequestId: requestId, pCollegeId: collegeId, pVenueId: venueId,
                pTitle: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
                pDescription: draft.description.trimmingCharacters(in: .whitespacesAndNewlines),
                pStartsAt: draft.startsAt.ISO8601Format(), pEndsAt: draft.endsAt.ISO8601Format(),
                pCapacity: draft.capacity, pHostDisplayName: draft.hostName.trimmingCharacters(in: .whitespacesAndNewlines),
                pAudience: draft.serverAudience, pCollegeIds: draft.serverCollegeIds,
                pIcebreaker: trimmed(draft.icebreaker), pLocationNote: trimmed(draft.locationNote)
            )).execute().value
            await reloadMeetups()
            await reloadHostedMeetups()
            return result
        } catch { throw Self.meetupError(error) }
    }

    func cancelHostedMeetup(_ meetup: OpenMeetup) async throws {
        guard let client else { throw SidequestError.notConfigured }
        guard isAuthenticated else { throw SidequestError.authenticationRequired }
        meetupActionStates[meetup.id] = .loading
        do {
            _ = try await client.rpc("set_open_meetup_status", params: ["p_meetup_id": meetup.id.uuidString, "p_status": "cancelled"]).execute()
            meetupActionStates[meetup.id] = .loaded
        } catch {
            let mapped = Self.meetupError(error)
            meetupActionStates[meetup.id] = .failed(mapped.localizedDescription)
            throw mapped
        }
        await reloadMeetups()
        await reloadHostedMeetups()
    }

    @discardableResult
    func joinMeetup(_ meetup: OpenMeetup) async throws -> MeetupRegistrationResult {
        try await changeMeetupRegistration(meetup, rpc: "join_open_meetup")
    }

    @discardableResult
    func leaveMeetup(_ meetup: OpenMeetup) async throws -> MeetupRegistrationResult {
        try await changeMeetupRegistration(meetup, rpc: "leave_open_meetup")
    }

    private func changeMeetupRegistration(_ meetup: OpenMeetup, rpc: String) async throws -> MeetupRegistrationResult {
        guard let client else { throw SidequestError.notConfigured }
        guard isAuthenticated else { throw SidequestError.authenticationRequired }
        meetupActionStates[meetup.id] = .loading
        do {
            let result: MeetupRegistrationResult = try await client
                .rpc(rpc, params: ["p_meetup_id": meetup.id.uuidString])
                .execute()
                .value
            meetupActionStates[meetup.id] = .loaded
            await reloadMeetups()
            return result
        } catch {
            let mapped = Self.meetupError(error)
            meetupActionStates[meetup.id] = .failed(mapped.localizedDescription)
            // Capacity or eligibility may have changed server-side; show the authoritative state.
            await reloadMeetups()
            throw mapped
        }
    }

    func reloadSavedEvents() async {
        guard let client, isAuthenticated else { savedEventIds=[]; return }
        struct SavedRow: Decodable { let eventId: UUID; enum CodingKeys:String,CodingKey { case eventId="event_id" } }
        do {
            let rows: [SavedRow] = try await client.from("saved_events").select("event_id").execute().value
            savedEventIds = Set(rows.map(\.eventId))
        } catch { /* saved state is secondary; discovery remains usable */ }
    }

    func toggleSaved(eventId: UUID) async throws {
        guard let client else { throw SidequestError.notConfigured }
        guard isAuthenticated else { throw SidequestError.authenticationRequired }
        if savedEventIds.contains(eventId) {
            try await client.from("saved_events").delete().eq("event_id", value: eventId).execute()
            savedEventIds.remove(eventId)
        } else {
            struct SavedInsert: Encodable { let userId: UUID; let eventId: UUID; enum CodingKeys:String,CodingKey { case userId="user_id", eventId="event_id" } }
            let userId = try await client.auth.session.user.id
            try await client.from("saved_events").insert(SavedInsert(userId:userId,eventId:eventId)).execute()
            savedEventIds.insert(eventId)
        }
    }

    func reloadLandmarks() async {
        guard let client else { navigationState = .failed(SidequestError.notConfigured.localizedDescription); return }
        navigationState = .loading
        do {
            landmarks = try await client.from("landmarks")
                .select("id,campus_id,floor_id,name,coordinate_kind,latitude,longitude,x_pixels,y_pixels,reference_photo_path,facing_degrees,facing_instruction")
                .eq("is_active", value: true).order("name").execute().value
            var urls: [UUID: URL] = [:]
            for landmark in landmarks {
                guard let path = landmark.referencePhotoPath else { continue }
                urls[landmark.id] = try? await client.storage.from("campus-media").createSignedURL(path: path, expiresIn: 3600)
            }
            landmarkPhotoURLs = urls
            navigationState = .loaded
        } catch { landmarkPhotoURLs = [:]; navigationState = .failed(error.localizedDescription) }
    }

    func calculateRoute(from start: Landmark, to destination: Landmark, accessibleOnly: Bool) async {
        guard let client else { navigationState = .failed(SidequestError.notConfigured.localizedDescription); return }
        guard start.id != destination.id else { navigationState = .failed("Choose two different landmarks."); return }
        navigationState = .loading
        routePlan = nil
        do {
            let calculated: RoutePlan = try await client.rpc("calculate_route", params: RouteRequest(
                pStartLandmarkId: start.id, pDestinationLandmarkId: destination.id,
                pAccessibleOnly: accessibleOnly
            )).execute().value
            routePlan = calculated
            await loadFloorPlans(for: calculated)
            navigationState = .loaded
        } catch { navigationState = .failed(error.localizedDescription) }
    }

    func clearRoute() { routePlan = nil; floorPlans = [:]; floorPlanURLs = [:] }
    func prepareNavigation(to landmarkId: UUID, from startLandmarkId: UUID? = nil) { pendingNavigationDestinationId = landmarkId; pendingNavigationStartId = startLandmarkId; selectedTab = 2 }
    func consumeNavigationDestination() { pendingNavigationDestinationId = nil; pendingNavigationStartId = nil }

    private func loadFloorPlans(for plan: RoutePlan) async {
        guard let client else { return }
        let ids = Array(Set(plan.nodes.compactMap(\.floorId)))
        guard !ids.isEmpty else { floorPlans = [:]; floorPlanURLs = [:]; return }
        do {
            let rows: [FloorPlan] = try await client.from("floors")
                .select("id,name,level,floor_plan_path,image_width_pixels,image_height_pixels,rotation_degrees")
                .in("id", values: ids).eq("is_published", value: true).execute().value
            floorPlans = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
            var urls: [UUID: URL] = [:]
            for floor in rows {
                urls[floor.id] = try await client.storage.from("campus-media").createSignedURL(path: floor.floorPlanPath, expiresIn: 3600)
            }
            floorPlanURLs = urls
        } catch {
            floorPlans = [:]; floorPlanURLs = [:]
        }
    }

    func reloadCommunity() async {
        guard let client else { communityState = .failed(SidequestError.notConfigured.localizedDescription); return }
        guard isAuthenticated else { communityState = .failed(SidequestError.authenticationRequired.localizedDescription); return }
        communityState = .loading
        do {
            async let announcementRows: [Announcement] = client.from("announcements")
                .select("id,edition_id,title,body,kind,created_at").order("created_at", ascending: false).limit(100).execute().value
            async let reportRows: [EventReport] = client.from("reports")
                .select("id,edition_id,category,description,priority,status,created_at").order("created_at", ascending: false).limit(100).execute().value
            async let notificationRows: [InboxNotification] = client.from("notifications")
                .select("id,title,body,kind,read_at,created_at").order("created_at", ascending: false).limit(100).execute().value
            async let threadRows: [DiscussionThread] = client.from("discussion_threads")
                .select("id,college_id,author_id,title,body,created_at,updated_at").order("updated_at",ascending:false).limit(100).execute().value
            (announcements, reports, notifications, discussionThreads) = try await (announcementRows, reportRows, notificationRows, threadRows)
            communityState = .loaded
        } catch { communityState = .failed(error.localizedDescription) }
    }

    private func startLiveUpdates() async {
        guard let client, isAuthenticated, liveChannel == nil else { return }
        let channel = client.channel("sidequest-authoritative-refresh")
        let communityChanges = ["announcements", "messages", "reports", "notifications"].map { channel.postgresChange(AnyAction.self, schema: "public", table: $0) }
        let journeyChanges = ["registrations", "attendance_transitions", "event_sessions"].map { channel.postgresChange(AnyAction.self, schema: "public", table: $0) }
        let chatChanges = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        let routeChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "route_closures")
        let venueChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "event_sessions")
        do {
            try await channel.subscribeWithError()
            liveChannel = channel
            for stream in communityChanges { liveUpdateTasks.append(Task { for await _ in stream { await self.reloadCommunity() } }) }
            for stream in journeyChanges { liveUpdateTasks.append(Task { for await _ in stream { await self.reloadJourney() } }) }
            // Unread badges: RLS limits these events to rooms the student can read.
            liveUpdateTasks.append(Task { for await _ in chatChanges { self.chat.scheduleRoomsRefresh() } })
            liveUpdateTasks.append(Task { for await _ in routeChanges { self.clearRoute(); await self.reloadLandmarks() } })
            liveUpdateTasks.append(Task { for await _ in venueChanges { self.clearRoute(); await self.reloadEvents(); await self.refreshLoadedEventDetails() } })
        } catch {
            await client.removeChannel(channel)
        }
    }

    private func stopLiveUpdates() async {
        liveUpdateTasks.forEach { $0.cancel() }; liveUpdateTasks = []
        if let liveChannel, let client { await client.removeChannel(liveChannel) }
        liveChannel = nil
    }

    func createDiscussionThread(title: String, body: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("create_discussion_thread", params: ["p_title": title, "p_body": body]).execute()
        await reloadCommunity()
    }

    func reloadDiscussionReplies(threadId: UUID) async throws {
        guard let client else { throw SidequestError.notConfigured }
        let rows: [DiscussionReply] = try await client.from("discussion_replies")
            .select("id,thread_id,author_id,body,created_at").eq("thread_id",value:threadId)
            .order("created_at").execute().value
        discussionReplies[threadId] = rows
    }

    func replyToDiscussion(threadId: UUID, body: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("reply_discussion_thread",params:["p_thread_id":threadId.uuidString,"p_body":body]).execute()
        try await reloadDiscussionReplies(threadId:threadId)
        await reloadCommunity()
    }

    func reloadEventMedia(editionId: UUID) async throws {
        guard let client else { throw SidequestError.notConfigured }
        let rows: [EventMediaRecord] = try await client.from("event_media")
            .select("id,edition_id,uploaded_by,storage_path,caption,created_at")
            .eq("edition_id",value:editionId).order("created_at",ascending:false).limit(100).execute().value
        var photos: [EventMediaPhoto] = []
        for row in rows {
            let url = try await client.storage.from("event-attendee-media").createSignedURL(path:row.storagePath,expiresIn:3600)
            photos.append(EventMediaPhoto(id:row.id,caption:row.caption,createdAt:row.createdAt,url:url))
        }
        eventMedia[editionId] = photos
    }

    func uploadEventPhoto(editionId: UUID, data: Data, caption: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        guard data.count <= 10 * 1024 * 1024 else { throw SidequestError.attachmentTooLarge }
        let userID = try await client.auth.session.user.id
        let path = "\(editionId.uuidString.lowercased())/\(userID.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        let bucket = client.storage.from("event-attendee-media")
        try await bucket.upload(path,data:data,options:FileOptions(contentType:"image/jpeg",upsert:false))
        do {
            _ = try await client.rpc("add_event_media",params:["p_edition_id":editionId.uuidString,"p_storage_path":path,"p_caption":caption]).execute()
            try await reloadEventMedia(editionId:editionId)
        } catch {
            _ = try? await bucket.remove(paths:[path])
            throw error
        }
    }

    func reportMessage(messageId: UUID, description: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("submit_message_report", params: [
            "p_message_id": messageId.uuidString,
            "p_description": description,
        ]).execute()
        await reloadCommunity()
    }

    func submitReport(editionId: UUID, category: String, description: String, priority: String, attachmentData: Data? = nil) async throws -> String? {
        guard let client else { throw SidequestError.notConfigured }
        if let attachmentData, attachmentData.count > 10 * 1024 * 1024 {
            throw SidequestError.attachmentTooLarge
        }
        let submitted: SubmittedReport = try await client.rpc("submit_report", params: [
            "p_edition_id": editionId.uuidString, "p_category": category,
            "p_description": description, "p_priority": priority,
        ]).execute().value
        var attachmentWarning: String?
        if let attachmentData {
            let userID = try await client.auth.session.user.id
            let path = "\(userID.uuidString.lowercased())/\(submitted.reportId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            let bucket = client.storage.from("report-attachments")
            do {
                try await bucket.upload(path, data: attachmentData, options: FileOptions(contentType: "image/jpeg", upsert: false))
                _ = try await client.rpc("add_report_attachment", params: [
                    "p_report_id": submitted.reportId.uuidString,
                    "p_storage_path": path,
                ]).execute()
            } catch {
                _ = try? await bucket.remove(paths: [path])
                attachmentWarning = "Your report was submitted, but the evidence photo could not be attached: \(error.localizedDescription)"
            }
        }
        await reloadCommunity()
        return attachmentWarning
    }

    func submitReview(editionId: UUID, rating: Int, body: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("submit_review", params: ReviewRequest(
            pEditionId: editionId, pRating: rating, pBody: body
        )).execute()
        await reloadProfile()
    }

    func registerDeviceToken(_ token: String) async throws {
        guard let client else { throw SidequestError.notConfigured }
#if DEBUG
        let environment = "sandbox"
#else
        let environment = "production"
#endif
        _ = try await client.rpc("register_device_token", params: ["p_token": token, "p_environment": environment]).execute()
    }

    func reloadProfile() async {
        guard let client, isAuthenticated else { return }
        struct FollowRow: Decodable { let organizationId:UUID; enum CodingKeys:String,CodingKey { case organizationId="organization_id" } }
        do {
            let userId = try await client.auth.session.user.id
            async let profileRows: [StudentProfile] = client.from("profiles").select("id,college_id,full_name,interests,notification_preferences,avatar_path").eq("id", value:userId).limit(1).execute().value
            async let collegeRows: [CollegeProfile] = client.from("colleges").select("id,name,timezone,latitude,longitude").order("name").execute().value
            async let organizationRows: [OrganizationProfile] = client.from("organizations").select("id,name,description,college_id").eq("is_active",value:true).order("name").execute().value
            async let followRows: [FollowRow] = client.from("follows").select("organization_id").execute().value
            async let attendanceRows:[AttendanceHistoryItem] = client.from("my_attendance_history").select("id,edition_id,event_id,title,action,recorded_at").order("recorded_at",ascending:false).limit(100).execute().value
            async let reviewRows:[SubmittedReviewItem] = client.from("my_submitted_reviews").select("id,event_id,edition_id,title,rating,body,created_at,updated_at").order("updated_at",ascending:false).limit(100).execute().value
            let values = try await (profileRows,collegeRows,organizationRows,followRows,attendanceRows,reviewRows)
            profile=values.0.first; collegeProfiles=values.1;colleges=values.1.map{CollegeOption(id:$0.id,name:$0.name)}; organizations=values.2; followedOrganizationIds=Set(values.3.map(\.organizationId));attendanceHistory=values.4;submittedReviews=values.5
        } catch { /* Profile form displays the current authenticated defaults. */ }
    }

    func saveProfile(fullName:String,collegeId:UUID?,interests:[String],preferences:[String:Bool]) async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("update_profile_preferences",params:ProfilePreferenceRequest(pFullName:fullName,pCollegeId:collegeId,pInterests:interests,pNotificationPreferences:preferences)).execute()
        await reloadProfile()
    }

    /// Stores a small JPEG in the student's own avatar folder, points the profile at it, then removes the old one.
    func saveProfilePhoto(_ source: Data) async throws {
        guard let client else { throw SidequestError.notConfigured }
        guard let image = AvatarImageCache.downsample(source, maxPixels: 512), let jpeg = image.jpegData(compressionQuality: 0.82) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let userId = try await client.auth.session.user.id
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        let bucket = client.storage.from("profile-avatars")
        try await bucket.upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: false))
        do {
            try await replaceProfilePhoto(with: path)
        } catch {
            _ = try? await bucket.remove(paths: [path])
            throw error
        }
    }

    func removeProfilePhoto() async throws {
        try await replaceProfilePhoto(with: nil)
    }

    private func replaceProfilePhoto(with path: String?) async throws {
        guard let client else { throw SidequestError.notConfigured }
        struct Result: Decodable { let previousPath: String?; enum CodingKeys: String, CodingKey { case previousPath = "previous_path" } }
        let result: Result = try await client.rpc("set_profile_avatar", params: ["p_path": path]).execute().value
        if let previous = result.previousPath, previous != path {
            _ = try? await client.storage.from("profile-avatars").remove(paths: [previous])
        }
        await reloadProfile()
    }

    func toggleOrganizationFollow(_ organizationId:UUID) async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("toggle_organization_follow",params:["p_organization_id":organizationId.uuidString]).execute()
        await reloadProfile()
    }

    func requestAccountDeletion() async throws {
        guard let client else { throw SidequestError.notConfigured }
        _ = try await client.rpc("request_account_deletion").execute()
        await signOut()
    }
}

private struct RouteRequest: Encodable {
    let pStartLandmarkId: UUID
    let pDestinationLandmarkId: UUID
    let pAccessibleOnly: Bool
    enum CodingKeys: String, CodingKey {
        case pStartLandmarkId = "p_start_landmark_id"
        case pDestinationLandmarkId = "p_destination_landmark_id"
        case pAccessibleOnly = "p_accessible_only"
    }
}

private struct HostMeetupRequest: Encodable {
    let pClientRequestId: UUID
    let pCollegeId: UUID
    let pVenueId: UUID
    let pTitle: String
    let pDescription: String
    let pStartsAt: String
    let pEndsAt: String
    let pCapacity: Int
    let pHostDisplayName: String
    let pAudience: String
    let pCollegeIds: [UUID]
    let pIcebreaker: String?
    let pLocationNote: String?
    enum CodingKeys: String, CodingKey {
        case pClientRequestId = "p_client_request_id", pCollegeId = "p_college_id", pVenueId = "p_venue_id"
        case pTitle = "p_title", pDescription = "p_description", pStartsAt = "p_starts_at", pEndsAt = "p_ends_at"
        case pCapacity = "p_capacity", pHostDisplayName = "p_host_display_name", pAudience = "p_audience"
        case pCollegeIds = "p_college_ids", pIcebreaker = "p_icebreaker", pLocationNote = "p_location_note"
    }
}

private struct ReviewRequest: Encodable {
    let pEditionId: UUID
    let pRating: Int
    let pBody: String
    enum CodingKeys: String, CodingKey {
        case pEditionId = "p_edition_id", pRating = "p_rating", pBody = "p_body"
    }
}

private struct ProfilePreferenceRequest: Encodable {
    let pFullName:String
    let pCollegeId:UUID?
    let pInterests:[String]
    let pNotificationPreferences:[String:Bool]
    enum CodingKeys:String,CodingKey { case pFullName="p_full_name",pCollegeId="p_college_id",pInterests="p_interests",pNotificationPreferences="p_notification_preferences" }
}

private struct SubmittedReport: Decodable {
    let reportId: UUID
    enum CodingKeys: String, CodingKey { case reportId = "report_id" }
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
    case notConfigured, authenticationRequired, attachmentTooLarge, meetupsUnavailable, meetupDetailsIncomplete, chatUnavailable
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Sidequest is not connected to an authorized backend. Add the Supabase URL and publishable key to Config/Local.xcconfig."
        case .authenticationRequired:
            "Sign in from Profile before registering."
        case .attachmentTooLarge:
            "The report photo must be 10 MB or smaller."
        case .meetupsUnavailable:
            "Open Meetups isn’t available on this server yet. They’ll appear here once the database update is applied."
        case .meetupDetailsIncomplete:
            "Choose your college and a venue before publishing."
        case .chatUnavailable:
            "Chat rooms aren’t available on this server yet. They’ll appear once the database update is applied."
        }
    }
}
