// A stand-in for `AppModel` so the SwiftUI screens can be type-checked without the Supabase
// SPM package, which is not resolvable on this machine (see tools/typecheck/run.sh).
//
// Every member mirrors the signature of the real `ios/Sidequest/AppModel.swift`. If a screen
// calls something that is not here, the typecheck fails — at which point either the stub is
// out of date or the screen is wrong, and the real AppModel decides which.
//
// KEEP IN SYNC with AppModel.swift. It is only used by the harness, never by the app target.

import Foundation
import Observation

#if os(macOS)

enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

enum StudentSignUpOutcome: Equatable {
    case signedIn
    case confirmationRequired
}

struct BackendConfiguration: Equatable {
    let url: URL?
    let publishableKey: String?
    var isConfigured: Bool { url != nil && publishableKey != nil }
}

enum SidequestError: LocalizedError {
    case notConfigured, authenticationRequired, attachmentTooLarge
    var errorDescription: String? { "" }
}

@MainActor
@Observable
final class AppModel {
    private(set) var events: [EventFeedItem] = []
    private(set) var eventImageURLs: [UUID: URL] = [:]
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
    private(set) var communityMessages: [CommunityMessage] = []
    private(set) var reports: [EventReport] = []
    private(set) var notifications: [InboxNotification] = []
    private(set) var channels: [CommunityChannel] = []
    private(set) var discussionThreads: [DiscussionThread] = []
    private(set) var discussionReplies: [UUID: [DiscussionReply]] = [:]
    private(set) var eventMedia: [UUID: [EventMediaPhoto]] = [:]
    private(set) var profile: StudentProfile?
    private(set) var colleges: [CollegeOption] = []
    private(set) var collegeProfiles: [CollegeProfile] = []
    private(set) var campuses: [CampusPoint] = []
    private(set) var sessionsByEdition: [UUID: [EventSessionScheduleItem]] = [:]
    private(set) var reviewSummariesByEvent: [UUID: [EditionReviewSummary]] = [:]
    private(set) var attendanceHistory: [AttendanceHistoryItem] = []
    private(set) var submittedReviews: [SubmittedReviewItem] = []
    private(set) var organizations: [OrganizationProfile] = []
    private(set) var followedOrganizationIds: Set<UUID> = []
    private(set) var communityState: LoadState = .idle
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

    let configuration = BackendConfiguration(url: nil, publishableKey: nil)

    func restoreSession() async {}
    func signIn(username: String, password: String) async throws {}
    func createStudentAccount(username: String, password: String) async throws -> StudentSignUpOutcome { .signedIn }
    func signOut() async {}
    func reloadEvents() async {}
    func loadNextPage() async {}
    func loadEventDetails(for event: EventFeedItem) async throws {}
    func reloadJourney() async {}
    func registration(for editionId: UUID) -> JourneyItem? { nil }
    func register(for event: EventFeedItem) async throws -> RegistrationResult {
        RegistrationResult(registrationId: UUID(), status: "", passToken: nil, waitlistPosition: nil, idempotentReplay: false)
    }
    func cancel(_ item: JourneyItem) async throws {}
    func reloadSavedEvents() async {}
    func toggleSaved(eventId: UUID) async throws {}
    func reloadLandmarks() async {}
    func calculateRoute(from start: Landmark, to destination: Landmark, accessibleOnly: Bool) async {}
    func clearRoute() {}
    func prepareNavigation(to landmarkId: UUID, from startLandmarkId: UUID? = nil) {}
    func consumeNavigationDestination() {}
    func reloadCommunity() async {}
    func postMessage(channelId: UUID, body: String) async throws {}
    func createDiscussionThread(title: String, body: String) async throws {}
    func reloadDiscussionReplies(threadId: UUID) async throws {}
    func replyToDiscussion(threadId: UUID, body: String) async throws {}
    func reloadEventMedia(editionId: UUID) async throws {}
    func uploadEventPhoto(editionId: UUID, data: Data, caption: String) async throws {}
    func reportMessage(messageId: UUID, description: String) async throws {}
    func submitReport(editionId: UUID, category: String, description: String, priority: String, attachmentData: Data? = nil) async throws -> String? { nil }
    func submitReview(editionId: UUID, rating: Int, body: String) async throws {}
    func registerDeviceToken(_ token: String) async throws {}
    func reloadProfile() async {}
    func saveProfile(fullName: String, collegeId: UUID?, interests: [String], preferences: [String: Bool]) async throws {}
    func toggleOrganizationFollow(_ organizationId: UUID) async throws {}
    func requestAccountDeletion() async throws {}
}

extension Notification.Name {
    static let sidequestDeviceToken = Notification.Name("sidequestDeviceToken")
}

#endif
