import XCTest
@testable import Sidequest

final class ModelsTests: XCTestCase {
    func testPublishedEventDecodingAndPrice() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","edition_id":"00000000-0000-0000-0000-000000000002","title":"Real event","description":"Entered through the backend","category":"Workshop","organization_name":"Club","college_name":"College","starts_at":"2026-10-12T10:00:00Z","ends_at":"2026-10-12T11:00:00Z","price_minor":0,"currency":"INR","eligibility":null}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(EventFeedItem.self, from: json)
        XCTAssertEqual(event.title, "Real event")
        XCTAssertEqual(event.priceLabel, "Free")
    }

    func testRegistrationAndJourneyContractsDecode() throws {
        let registrationJSON = #"{"registration_id":"00000000-0000-0000-0000-000000000010","status":"registered","pass_token":"00000000-0000-0000-0000-000000000011","waitlist_position":null,"idempotent_replay":false}"#.data(using: .utf8)!
        let registration = try JSONDecoder().decode(RegistrationResult.self, from: registrationJSON)
        XCTAssertEqual(registration.status, "registered")
        XCTAssertNotNil(registration.passToken)

        let journeyJSON = #"{"registration_id":"00000000-0000-0000-0000-000000000010","status":"registered","edition_id":"00000000-0000-0000-0000-000000000002","event_id":"00000000-0000-0000-0000-000000000001","title":"Real event","category":"Workshop","event_status":"published","organization_name":"Club","starts_at":"2026-10-12T10:00:00Z","ends_at":"2026-10-12T11:00:00Z","pass_token":"00000000-0000-0000-0000-000000000011","pass_status":"active","waitlist_position":null}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let journey = try decoder.decode(JourneyItem.self, from: journeyJSON)
        XCTAssertEqual(journey.title, "Real event")
        XCTAssertEqual(journey.status, "registered")
    }
}
