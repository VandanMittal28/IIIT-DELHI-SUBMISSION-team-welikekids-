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

    func testRouteContractDistinguishesCoordinateSystemsAndValidation() throws {
        let json = #"{"route_version_id":"00000000-0000-0000-0000-000000000020","total_distance_meters":42.5,"physical_validation_complete":false,"nodes":[{"id":"00000000-0000-0000-0000-000000000021","coordinate_kind":"outdoor_geographic","floor_id":null,"latitude":28.5,"longitude":77.2,"x_pixels":null,"y_pixels":null,"node_kind":"landmark"},{"id":"00000000-0000-0000-0000-000000000022","coordinate_kind":"indoor_floor","floor_id":"00000000-0000-0000-0000-000000000023","latitude":null,"longitude":null,"x_pixels":125.0,"y_pixels":80.0,"node_kind":"hall"}],"edges":[{"id":"00000000-0000-0000-0000-000000000024","kind":"entrance","distance_meters":42.5,"instruction":"Enter the main door","from_node_id":"00000000-0000-0000-0000-000000000021","to_node_id":"00000000-0000-0000-0000-000000000022"}]}"#.data(using:.utf8)!
        let route=try JSONDecoder().decode(RoutePlan.self,from:json)
        XCTAssertFalse(route.physicalValidationComplete)
        XCTAssertEqual(route.nodes[0].coordinateKind,"outdoor_geographic")
        XCTAssertEqual(route.nodes[1].coordinateKind,"indoor_floor")
        XCTAssertEqual(route.edges.first?.instruction,"Enter the main door")
    }

    func testProfilePreferencesDecode() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000030","college_id":null,"full_name":"Student","interests":["music","volunteering"],"notification_preferences":{"announcements":true,"reminders":false}}"#.data(using:.utf8)!
        let profile=try JSONDecoder().decode(StudentProfile.self,from:json)
        XCTAssertEqual(profile.interests.count,2)
        XCTAssertEqual(profile.notificationPreferences["reminders"],false)
    }
}
