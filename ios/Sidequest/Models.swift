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

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, currency, eligibility
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
    let startsAt: Date
    let endsAt: Date
    let passToken: UUID?
    let passStatus: String?
    let waitlistPosition: Int?

    enum CodingKeys: String, CodingKey {
        case status, title, category
        case registrationId = "registration_id"
        case editionId = "edition_id"
        case eventId = "event_id"
        case eventStatus = "event_status"
        case organizationName = "organization_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case passToken = "pass_token"
        case passStatus = "pass_status"
        case waitlistPosition = "waitlist_position"
    }
}
