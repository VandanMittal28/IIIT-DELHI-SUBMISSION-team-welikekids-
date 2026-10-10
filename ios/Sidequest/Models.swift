import Foundation

struct EventFeedItem: Decodable, Identifiable, Equatable, Hashable {
    let id: UUID
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
