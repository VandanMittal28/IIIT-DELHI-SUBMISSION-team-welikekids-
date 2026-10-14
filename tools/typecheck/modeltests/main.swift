// Executable mirror of ios/SidequestTests/ModelsTests.swift.
//
// The real XCTest bundle needs an iOS Simulator, which this machine does not have. Everything
// those tests touch is pure Foundation, so the same assertions can be compiled against
// Models.swift and actually *run* on macOS. This is the one part of the app whose behaviour is
// genuinely executed rather than only type-checked.
//
// Keep in step with ModelsTests.swift. Run via tools/typecheck/run.sh. Lives in its own
// directory because Swift only allows top-level statements in a file named main.swift.

import Foundation

private var failures: [String] = []

private func expect(_ condition: Bool, _ message: String) {
    if !condition { failures.append(message) }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs { failures.append("\(message) — got \(lhs), expected \(rhs)") }
}

private func expectClose(_ lhs: Double, _ rhs: Double, accuracy: Double, _ message: String) {
    if abs(lhs - rhs) > accuracy { failures.append("\(message) — got \(lhs), expected \(rhs)") }
}

private func iso() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

func testPublishedEventDecodingAndPrice() throws {
    let json = #"{"id":"00000000-0000-0000-0000-000000000001","edition_id":"00000000-0000-0000-0000-000000000002","title":"Real event","description":"Entered through the backend","category":"Workshop","organization_name":"Club","college_name":"College","starts_at":"2026-10-12T10:00:00Z","ends_at":"2026-10-12T11:00:00Z","price_minor":0,"currency":"INR","eligibility":null}"#.data(using: .utf8)!
    let event = try iso().decode(EventFeedItem.self, from: json)
    expectEqual(event.title, "Real event", "event title")
    expectEqual(event.priceLabel, "Free", "free price label")
}

func testRegistrationAndJourneyContractsDecode() throws {
    let registrationJSON = #"{"registration_id":"00000000-0000-0000-0000-000000000010","status":"registered","pass_token":"00000000-0000-0000-0000-000000000011","waitlist_position":null,"idempotent_replay":false}"#.data(using: .utf8)!
    let registration = try JSONDecoder().decode(RegistrationResult.self, from: registrationJSON)
    expectEqual(registration.status, "registered", "registration status")
    expect(registration.passToken != nil, "registration pass token present")

    let journeyJSON = #"{"registration_id":"00000000-0000-0000-0000-000000000010","status":"registered","edition_id":"00000000-0000-0000-0000-000000000002","event_id":"00000000-0000-0000-0000-000000000001","title":"Real event","category":"Workshop","event_status":"published","organization_name":"Club","registration_opens_at":"2026-10-01T10:00:00Z","registration_closes_at":"2026-10-11T10:00:00Z","starts_at":"2026-10-12T10:00:00Z","ends_at":"2026-10-12T11:00:00Z","pass_token":"00000000-0000-0000-0000-000000000011","pass_status":"active","waitlist_position":null,"venue_name":null,"destination_landmark_id":null,"designated_gate_landmark_id":null}"#.data(using: .utf8)!
    let journey = try iso().decode(JourneyItem.self, from: journeyJSON)
    expectEqual(journey.title, "Real event", "journey title")
    expectEqual(journey.status, "registered", "journey status")

    // The redesign made JourneyItem Hashable so it can drive `navigationDestination(for:)`.
    expectEqual(Set([journey, journey]).count, 1, "JourneyItem hashes by value")
}

func testRouteContractDistinguishesCoordinateSystemsAndValidation() throws {
    let json = #"{"route_version_id":"00000000-0000-0000-0000-000000000020","total_distance_meters":42.5,"physical_validation_complete":false,"nodes":[{"id":"00000000-0000-0000-0000-000000000021","coordinate_kind":"outdoor_geographic","floor_id":null,"latitude":28.5,"longitude":77.2,"x_pixels":null,"y_pixels":null,"node_kind":"landmark"},{"id":"00000000-0000-0000-0000-000000000022","coordinate_kind":"indoor_floor","floor_id":"00000000-0000-0000-0000-000000000023","latitude":null,"longitude":null,"x_pixels":125.0,"y_pixels":80.0,"node_kind":"hall"}],"edges":[{"id":"00000000-0000-0000-0000-000000000024","kind":"entrance","distance_meters":42.5,"instruction":"Enter the main door","from_node_id":"00000000-0000-0000-0000-000000000021","to_node_id":"00000000-0000-0000-0000-000000000022"}]}"#.data(using: .utf8)!
    let route = try JSONDecoder().decode(RoutePlan.self, from: json)
    expect(!route.physicalValidationComplete, "route not physically validated")
    expectEqual(route.nodes[0].coordinateKind, "outdoor_geographic", "outdoor node kind")
    expectEqual(route.nodes[1].coordinateKind, "indoor_floor", "indoor node kind")
    expectEqual(route.edges.first?.instruction, "Enter the main door", "edge instruction")
}

func testProfilePreferencesDecode() throws {
    let json = #"{"id":"00000000-0000-0000-0000-000000000030","college_id":null,"full_name":"Student","interests":["music","volunteering"],"notification_preferences":{"announcements":true,"reminders":false}}"#.data(using: .utf8)!
    let profile = try JSONDecoder().decode(StudentProfile.self, from: json)
    expectEqual(profile.interests.count, 2, "interest count")
    expectEqual(profile.notificationPreferences["reminders"], false, "reminders preference")
}

func testCameraStepsUseStoredOutdoorAndIndoorGeometry() throws {
    let json = #"{"route_version_id":"00000000-0000-0000-0000-000000000040","total_distance_meters":20,"physical_validation_complete":true,"nodes":[{"id":"00000000-0000-0000-0000-000000000041","coordinate_kind":"outdoor_geographic","floor_id":null,"latitude":28.5,"longitude":77.2,"x_pixels":null,"y_pixels":null,"node_kind":"landmark"},{"id":"00000000-0000-0000-0000-000000000042","coordinate_kind":"outdoor_geographic","floor_id":null,"latitude":28.5,"longitude":77.201,"x_pixels":null,"y_pixels":null,"node_kind":"entrance"},{"id":"00000000-0000-0000-0000-000000000043","coordinate_kind":"indoor_floor","floor_id":"00000000-0000-0000-0000-000000000044","latitude":null,"longitude":null,"x_pixels":10,"y_pixels":10,"node_kind":"landmark"},{"id":"00000000-0000-0000-0000-000000000045","coordinate_kind":"indoor_floor","floor_id":"00000000-0000-0000-0000-000000000044","latitude":null,"longitude":null,"x_pixels":20,"y_pixels":10,"node_kind":"hall"}],"edges":[{"id":"00000000-0000-0000-0000-000000000046","kind":"walkway","distance_meters":10,"instruction":"Walk east","from_node_id":"00000000-0000-0000-0000-000000000041","to_node_id":"00000000-0000-0000-0000-000000000042"},{"id":"00000000-0000-0000-0000-000000000047","kind":"corridor","distance_meters":10,"instruction":"Use the corridor","from_node_id":"00000000-0000-0000-0000-000000000043","to_node_id":"00000000-0000-0000-0000-000000000045"}]}"#.data(using: .utf8)!
    let route = try JSONDecoder().decode(RoutePlan.self, from: json)
    let floorID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
    let floor = FloorPlan(id: floorID, name: "Ground", level: 0, floorPlanPath: "path", imageWidthPixels: 100, imageHeightPixels: 100, rotationDegrees: 30)
    let steps = route.cameraSteps(floorPlans: [floorID: floor])
    expectClose(steps[0].bearingDegrees!, 90, accuracy: 0.1, "outdoor bearing")
    expectClose(steps[1].bearingDegrees!, 120, accuracy: 0.1, "indoor bearing with floor rotation")
    expectClose(steps[0].bearingRelativeToConfirmedFacing(30)!, 60, accuracy: 0.1, "bearing relative to confirmed facing")
}

/// The redesign added this; it decides the colour of every cover-tinted event page.
func testCoverTintNormalisesTowardALegibleBand() {
    // A bright cover must come back dark enough to carry white text.
    let bright = SQTint.fromCoverSample(red: 0.95, green: 0.93, blue: 0.90)
    let brightLuminance = 0.2126 * bright.red + 0.7152 * bright.green + 0.0722 * bright.blue
    expect(brightLuminance < 0.45, "bright cover is darkened (luminance \(brightLuminance))")

    // A very dark cover must not be pushed so far that it becomes pure black.
    let dark = SQTint.fromCoverSample(red: 0.02, green: 0.02, blue: 0.03)
    let darkLuminance = 0.2126 * dark.red + 0.7152 * dark.green + 0.0722 * dark.blue
    expect(darkLuminance > 0.01, "dark cover keeps some lift (luminance \(darkLuminance))")

    // Hue must survive normalisation: a red cover stays red-dominant.
    let red = SQTint.fromCoverSample(red: 0.80, green: 0.20, blue: 0.20)
    expect(red.red > red.green && red.red > red.blue, "hue survives normalisation")

    // Components always stay in range.
    for tint in [bright, dark, red, SQTint.fromCoverSample(red: 2, green: -1, blue: 0.5)] {
        expect((0...1).contains(tint.red), "red in range")
        expect((0...1).contains(tint.green), "green in range")
        expect((0...1).contains(tint.blue), "blue in range")
    }
}

// MARK: - Runner

do {
    try testPublishedEventDecodingAndPrice()
    try testRegistrationAndJourneyContractsDecode()
    try testRouteContractDistinguishesCoordinateSystemsAndValidation()
    try testProfilePreferencesDecode()
    try testCameraStepsUseStoredOutdoorAndIndoorGeometry()
    testCoverTintNormalisesTowardALegibleBand()
} catch {
    failures.append("threw: \(error)")
}

if failures.isEmpty {
    print("   ok — 6 model tests pass")
    exit(0)
}
for failure in failures { print("MODEL TEST FAIL: \(failure)") }
exit(1)
