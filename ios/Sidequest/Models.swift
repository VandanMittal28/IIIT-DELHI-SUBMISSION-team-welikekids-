import Foundation

struct EventFeedItem: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let editionId: UUID
    let title: String
    let description: String
    let category: String
    let organizationName: String
    let collegeName: String
    let startsAt: Date
    let endsAt: Date
    let priceMinor: Int
    let currency: String
    let eligibility: String?
    let coverImagePath: String?
    let venueId: UUID?
    let venueName: String?
    let destinationLandmarkId: UUID?
    let designatedGateLandmarkId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, currency, eligibility
        case coverImagePath = "cover_image_path", venueId = "venue_id"
        case venueName = "venue_name", destinationLandmarkId = "destination_landmark_id", designatedGateLandmarkId = "designated_gate_landmark_id"
        case editionId = "edition_id"
        case organizationName = "organization_name"
        case collegeName = "college_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case priceMinor = "price_minor"
    }

    var priceLabel: String {
        guard priceMinor > 0 else { return "Free" }
        return (Double(priceMinor) / 100).formatted(.currency(code: currency))
    }
}

struct CampusPoint: Decodable, Identifiable, Equatable {
    let id: UUID; let name: String; let latitude: Double; let longitude: Double
}

struct VenueMapLocation: Decodable, Identifiable, Equatable {
    let id: UUID
    let campusId: UUID
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude
        case campusId = "campus_id"
    }
}

struct EventSessionScheduleItem:Decodable,Identifiable,Equatable {
    let id:UUID;let editionId:UUID;let title:String;let startsAt:Date;let endsAt:Date;let venueName:String?;let campusName:String?
    enum CodingKeys:String,CodingKey { case id,title;case editionId="edition_id",startsAt="starts_at",endsAt="ends_at",venueName="venue_name",campusName="campus_name" }
}

struct EditionReviewSummary:Decodable,Identifiable,Equatable {
    var id:UUID{editionId};let eventId:UUID;let editionId:UUID;let sampleSize:Int;let averageRating:Double
    enum CodingKeys:String,CodingKey { case eventId="event_id",editionId="edition_id",sampleSize="sample_size",averageRating="average_rating" }
}

struct AttendanceHistoryItem:Decodable,Identifiable,Equatable {
    let id:UUID;let editionId:UUID;let eventId:UUID;let title:String;let action:String;let recordedAt:Date
    enum CodingKeys:String,CodingKey { case id,title,action;case editionId="edition_id",eventId="event_id",recordedAt="recorded_at" }
}

struct SubmittedReviewItem:Decodable,Identifiable,Equatable {
    let id:UUID;let eventId:UUID;let editionId:UUID;let title:String;let rating:Int;let body:String?;let createdAt:Date;let updatedAt:Date
    enum CodingKeys:String,CodingKey { case id,title,rating,body;case eventId="event_id",editionId="edition_id",createdAt="created_at",updatedAt="updated_at" }
}

struct RegistrationResult: Decodable, Equatable {
    let registrationId: UUID
    let status: String
    let passToken: UUID?
    let waitlistPosition: Int?
    let idempotentReplay: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case registrationId = "registration_id"
        case passToken = "pass_token"
        case waitlistPosition = "waitlist_position"
        case idempotentReplay = "idempotent_replay"
    }
}

struct JourneyItem: Decodable, Identifiable, Equatable, Hashable {
    var id: UUID { registrationId }
    let registrationId: UUID
    let status: String
    let editionId: UUID
    let eventId: UUID
    let title: String
    let category: String
    let eventStatus: String
    let organizationName: String
    let registrationOpensAt: Date
    let registrationClosesAt: Date
    let startsAt: Date
    let endsAt: Date
    let passToken: UUID?
    let passStatus: String?
    let waitlistPosition: Int?
    let venueName: String?
    let destinationLandmarkId: UUID?
    let designatedGateLandmarkId: UUID?

    enum CodingKeys: String, CodingKey {
        case status, title, category
        case registrationId = "registration_id"
        case editionId = "edition_id"
        case eventId = "event_id"
        case eventStatus = "event_status"
        case organizationName = "organization_name"
        case registrationOpensAt = "registration_opens_at"
        case registrationClosesAt = "registration_closes_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case passToken = "pass_token"
        case passStatus = "pass_status"
        case waitlistPosition = "waitlist_position"
        case venueName = "venue_name", destinationLandmarkId = "destination_landmark_id", designatedGateLandmarkId = "designated_gate_landmark_id"
    }
}

struct Landmark: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let campusId: UUID
    let floorId: UUID?
    let name: String
    let coordinateKind: String
    let latitude: Double?
    let longitude: Double?
    let xPixels: Double?
    let yPixels: Double?
    let referencePhotoPath: String?
    let facingDegrees: Double?
    let facingInstruction: String?

    enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude
        case campusId = "campus_id", floorId = "floor_id", coordinateKind = "coordinate_kind"
        case xPixels = "x_pixels", yPixels = "y_pixels", referencePhotoPath = "reference_photo_path"
        case facingDegrees = "facing_degrees", facingInstruction = "facing_instruction"
    }
}

struct RoutePlan: Decodable, Equatable {
    let routeVersionId: UUID
    let totalDistanceMeters: Double
    let physicalValidationComplete: Bool
    let nodes: [RouteNode]
    let edges: [RouteEdge]

    enum CodingKeys: String, CodingKey {
        case nodes, edges
        case routeVersionId = "route_version_id"
        case totalDistanceMeters = "total_distance_meters"
        case physicalValidationComplete = "physical_validation_complete"
    }
}

struct RouteNode: Decodable, Identifiable, Equatable {
    let id: UUID
    let coordinateKind: String
    let floorId: UUID?
    let latitude: Double?
    let longitude: Double?
    let xPixels: Double?
    let yPixels: Double?
    let nodeKind: String

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude
        case coordinateKind = "coordinate_kind", floorId = "floor_id"
        case xPixels = "x_pixels", yPixels = "y_pixels", nodeKind = "node_kind"
    }
}

struct RouteEdge: Decodable, Identifiable, Equatable {
    let id: UUID
    let kind: String
    let distanceMeters: Double
    let instruction: String
    let fromNodeId: UUID
    let toNodeId: UUID

    enum CodingKeys: String, CodingKey {
        case id, kind, instruction
        case distanceMeters = "distance_meters", fromNodeId = "from_node_id", toNodeId = "to_node_id"
    }
}

struct RouteCameraStep: Identifiable, Equatable {
    let id: UUID
    let instruction: String
    let distanceMeters: Double
    let kind: String
    let bearingDegrees: Double?

    func bearingRelativeToConfirmedFacing(_ facingDegrees: Double) -> Double? {
        guard let bearingDegrees else { return nil }
        let remainder = (bearingDegrees - facingDegrees).truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}

extension RoutePlan {
    func cameraSteps(floorPlans: [UUID: FloorPlan]) -> [RouteCameraStep] {
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        return edges.map { edge in
            let bearing = nodesByID[edge.fromNodeId].flatMap { start in
                nodesByID[edge.toNodeId].flatMap { end in
                    Self.bearing(from: start, to: end, floorPlans: floorPlans)
                }
            }
            return RouteCameraStep(
                id: edge.id,
                instruction: edge.instruction,
                distanceMeters: edge.distanceMeters,
                kind: edge.kind,
                bearingDegrees: bearing
            )
        }
    }

    private static func bearing(from start: RouteNode, to end: RouteNode, floorPlans: [UUID: FloorPlan]) -> Double? {
        if let latitude1 = start.latitude, let longitude1 = start.longitude,
           let latitude2 = end.latitude, let longitude2 = end.longitude {
            let phi1 = latitude1 * .pi / 180
            let phi2 = latitude2 * .pi / 180
            let deltaLongitude = (longitude2 - longitude1) * .pi / 180
            let y = sin(deltaLongitude) * cos(phi2)
            let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLongitude)
            return normalizedDegrees(atan2(y, x) * 180 / .pi)
        }

        guard let floorID = start.floorId, floorID == end.floorId,
              let startX = start.xPixels, let startY = start.yPixels,
              let endX = end.xPixels, let endY = end.yPixels,
              let floor = floorPlans[floorID] else { return nil }
        let pixelBearing = atan2(endX - startX, -(endY - startY)) * 180 / .pi
        return normalizedDegrees(pixelBearing + floor.rotationDegrees)
    }

    private static func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}

struct FloorPlan: Decodable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let level: Int
    let floorPlanPath: String
    let imageWidthPixels: Int
    let imageHeightPixels: Int
    let rotationDegrees: Double
    enum CodingKeys: String, CodingKey {
        case id, name, level
        case floorPlanPath = "floor_plan_path", imageWidthPixels = "image_width_pixels", imageHeightPixels = "image_height_pixels", rotationDegrees = "rotation_degrees"
    }
}

struct Announcement: Decodable, Identifiable, Equatable {
    let id: UUID
    let editionId: UUID
    let title: String
    let body: String
    let kind: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, title, body, kind; case editionId = "edition_id", createdAt = "created_at" }
}

struct EventReport: Decodable, Identifiable, Equatable {
    let id: UUID
    let editionId: UUID
    let category: String
    let description: String
    let priority: String
    let status: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, category, description, priority, status; case editionId = "edition_id", createdAt = "created_at" }
}

struct InboxNotification: Decodable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let body: String
    let kind: String
    let readAt: Date?
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, title, body, kind; case readAt = "read_at", createdAt = "created_at" }
}

struct StudentProfile: Decodable, Equatable {
    let id: UUID
    let collegeId: UUID?
    let fullName: String?
    let interests: [String]
    let notificationPreferences: [String: Bool]
    let avatarPath: String?
    enum CodingKeys:String,CodingKey { case id, interests; case collegeId="college_id", fullName="full_name", notificationPreferences="notification_preferences", avatarPath="avatar_path" }
}

struct CollegeOption: Decodable, Identifiable, Equatable { let id:UUID; let name:String }

struct CollegeProfile:Decodable,Identifiable,Equatable {
    let id:UUID;let name:String;let timezone:String;let latitude:Double?;let longitude:Double?
}

struct OrganizationProfile: Decodable, Identifiable, Equatable {
    let id:UUID; let name:String; let description:String?; let collegeId:UUID
    enum CodingKeys:String,CodingKey { case id,name,description; case collegeId="college_id" }
}

struct OpenMeetup: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
    let title: String
    let description: String
    let locationNote: String?
    let icebreaker: String
    let audience: String
    let capacity: Int
    let goingCount: Int
    let startsAt: Date
    let endsAt: Date
    let status: String
    let collegeName: String
    let hostName: String
    let hostHeadline: String?
    let hostVerified: Bool
    let venueId: UUID?
    let venueName: String
    let campusName: String
    let destinationLandmarkId: UUID?
    let participatingColleges: [String]
    let myStatus: String?
    let isEligible: Bool
    let isHost: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, description, icebreaker, audience, capacity, status
        case locationNote = "location_note", goingCount = "going_count"
        case startsAt = "starts_at", endsAt = "ends_at", collegeName = "college_name"
        case hostName = "host_name", hostHeadline = "host_headline", hostVerified = "host_verified"
        case venueId = "venue_id", venueName = "venue_name", campusName = "campus_name", destinationLandmarkId = "destination_landmark_id"
        case participatingColleges = "participating_colleges", myStatus = "my_status", isEligible = "is_eligible", isHost = "is_host"
    }

    var isGoing: Bool { myStatus == "going" }
    var amHost: Bool { isHost == true }
    var isCancelled: Bool { status == "cancelled" }
    var isFull: Bool { goingCount >= capacity }
    var spotsLeft: Int { max(0, capacity - goingCount) }
    var audienceLabel: String {
        if audience == "all_colleges" { return "Open to all participating colleges" }
        if participatingColleges.count <= 1 { return "Open to \(participatingColleges.first ?? collegeName) students" }
        return "Open to \(participatingColleges.joined(separator: ", "))"
    }
}

/// A campus venue a student can host a meetup at.
struct HostVenueOption: Decodable, Identifiable, Hashable {
    struct Campus: Decodable, Hashable { let name: String; let collegeId: UUID; enum CodingKeys: String, CodingKey { case name; case collegeId = "college_id" } }
    let id: UUID
    let name: String
    let destinationLandmarkId: UUID?
    let campus: Campus
    enum CodingKeys: String, CodingKey { case id, name, campus; case destinationLandmarkId = "destination_landmark_id" }
}

/// Student-entered meetup details. Validation mirrors `host_open_meetup` so mistakes surface before the request.
struct MeetupDraft: Equatable {
    enum Audience: String, CaseIterable, Identifiable {
        case myCollege, selectedColleges, allColleges
        var id: String { rawValue }
        var label: String {
            switch self {
            case .myCollege: "My college"
            case .selectedColleges: "My college + selected colleges"
            case .allColleges: "All participating colleges"
            }
        }
    }
    enum Field: Hashable { case title, description, hostName, college, venue, startsAt, duration, capacity, colleges, icebreaker, locationNote }

    var title = ""
    var description = ""
    var hostName = ""
    var collegeId: UUID?
    var venueId: UUID?
    var startsAt: Date
    var durationMinutes = 60
    var capacity = 10
    var audience: Audience = .myCollege
    var extraCollegeIds: Set<UUID> = []
    var icebreaker = ""
    var locationNote = ""

    static let capacityRange = 2...500
    static let durationRange = 15...720

    init(now: Date = .now) {
        // Default to a sociable time: tomorrow at 5 PM local time.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        startsAt = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    var serverAudience: String { audience == .allColleges ? "all_colleges" : "selected_colleges" }
    var serverCollegeIds: [UUID] { audience == .selectedColleges ? extraCollegeIds.filter { $0 != collegeId }.sorted { $0.uuidString < $1.uuidString } : [] }

    func errors(now: Date = .now) -> [Field: String] {
        var errors: [Field: String] = [:]
        func length(_ text: String) -> Int { text.trimmingCharacters(in: .whitespacesAndNewlines).count }
        if !(3...120).contains(length(title)) { errors[.title] = "Give your meetup a title (3–120 characters)." }
        if !(10...2000).contains(length(description)) { errors[.description] = "Describe the meetup in at least 10 characters." }
        if !(2...80).contains(length(hostName)) { errors[.hostName] = "Enter the name attendees will see (2–80 characters)." }
        if collegeId == nil { errors[.college] = "You need an active college membership to host." }
        if venueId == nil { errors[.venue] = "Choose a venue." }
        if startsAt <= now.addingTimeInterval(5 * 60) { errors[.startsAt] = "Pick a start time at least 5 minutes from now." }
        else if startsAt > now.addingTimeInterval(180 * 24 * 3600) { errors[.startsAt] = "Meetups can be scheduled up to 180 days ahead." }
        if !Self.durationRange.contains(durationMinutes) { errors[.duration] = "Meetups can last 15 minutes to 12 hours." }
        if !Self.capacityRange.contains(capacity) { errors[.capacity] = "Capacity must be between 2 and 500." }
        if audience == .selectedColleges && serverCollegeIds.isEmpty { errors[.colleges] = "Select at least one other college." }
        let icebreakerLength = length(icebreaker)
        if icebreakerLength > 0 && !(10...280).contains(icebreakerLength) { errors[.icebreaker] = "Icebreakers need 10–280 characters, or leave it blank for a suggested one." }
        let noteLength = length(locationNote)
        if noteLength > 0 && !(2...160).contains(noteLength) { errors[.locationNote] = "Keep the location tip to 2–160 characters." }
        return errors
    }
}

struct HostMeetupResult: Decodable, Equatable {
    let meetupId: UUID
    let status: String
    let idempotentReplay: Bool
    enum CodingKeys: String, CodingKey { case status; case meetupId = "meetup_id", idempotentReplay = "idempotent_replay" }
}

struct MeetupRegistrationResult: Decodable, Equatable {
    let registrationId: UUID
    let status: String
    let goingCount: Int
    let capacity: Int
    let idempotentReplay: Bool
    enum CodingKeys: String, CodingKey {
        case status, capacity
        case registrationId = "registration_id", goingCount = "going_count", idempotentReplay = "idempotent_replay"
    }
}

struct DiscussionThread: Decodable, Identifiable, Equatable {
    let id:UUID; let collegeId:UUID; let authorId:UUID; let title:String; let body:String; let createdAt:Date; let updatedAt:Date
    enum CodingKeys:String,CodingKey { case id,title,body; case collegeId="college_id",authorId="author_id",createdAt="created_at",updatedAt="updated_at" }
}

struct DiscussionReply: Decodable, Identifiable, Equatable {
    let id:UUID; let threadId:UUID; let authorId:UUID; let body:String; let createdAt:Date
    enum CodingKeys:String,CodingKey { case id,body; case threadId="thread_id",authorId="author_id",createdAt="created_at" }
}

struct EventMediaRecord: Decodable, Identifiable, Equatable {
    let id:UUID; let editionId:UUID; let uploadedBy:UUID; let storagePath:String; let caption:String?; let createdAt:Date
    enum CodingKeys:String,CodingKey { case id,caption; case editionId="edition_id",uploadedBy="uploaded_by",storagePath="storage_path",createdAt="created_at" }
}

struct EventMediaPhoto: Identifiable, Equatable {
    let id:UUID; let caption:String?; let createdAt:Date; let url:URL
}
