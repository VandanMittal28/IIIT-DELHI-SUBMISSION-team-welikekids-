import XCTest
@testable import Sidequest

final class ModelsTests: XCTestCase {
    func testPublishedEventDecodingAndPrice() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","title":"Real event","description":"Entered through the backend","category":"Workshop","organization_name":"Club","college_name":"College","starts_at":"2026-10-12T10:00:00Z","ends_at":"2026-10-12T11:00:00Z","price_minor":0,"currency":"INR","eligibility":null}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(EventFeedItem.self, from: json)
        XCTAssertEqual(event.title, "Real event")
        XCTAssertEqual(event.priceLabel, "Free")
    }
}
