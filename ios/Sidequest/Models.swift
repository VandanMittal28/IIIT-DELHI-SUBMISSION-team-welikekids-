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
    let venueName: String?
    let destinationLandmarkId: UUID?
    let designatedGateLandmarkId: UUID?

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, currency, eligibility
        case coverImagePath = "cover_image_path"
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

struct JourneyItem: Decodable, Identifiable, Equatable {
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

struct CommunityMessage: Decodable, Identifiable, Equatable {
    let id: UUID
    let channelId: UUID
    let body: String
    let status: String
    let createdAt: Date
    enum CodingKeys: String, CodingKey { case id, body, status; case channelId = "channel_id", createdAt = "created_at" }
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
    enum CodingKeys:String,CodingKey { case id, interests; case collegeId="college_id", fullName="full_name", notificationPreferences="notification_preferences" }
}

struct CollegeOption: Decodable, Identifiable, Equatable { let id:UUID; let name:String }

struct CollegeProfile:Decodable,Identifiable,Equatable {
    let id:UUID;let name:String;let timezone:String;let latitude:Double?;let longitude:Double?
}

struct OrganizationProfile: Decodable, Identifiable, Equatable {
    let id:UUID; let name:String; let description:String?; let collegeId:UUID
    enum CodingKeys:String,CodingKey { case id,name,description; case collegeId="college_id" }
}

struct CommunityChannel: Decodable, Identifiable, Equatable {
    let id:UUID; let editionId:UUID; let eventId:UUID; let title:String; let organizationId:UUID; let organizationName:String; let startsAt:Date
    enum CodingKeys:String,CodingKey { case id,title; case editionId="edition_id",eventId="event_id",organizationId="organization_id",organizationName="organization_name",startsAt="starts_at" }
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
