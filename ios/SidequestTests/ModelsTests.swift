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

        let journeyJSON = #"{"registration_id":"00000000-0000-0000-0000-000000000010","status":"registered","edition_id":"00000000-0000-0000-0000-000000000002","event_id":"00000000-0000-0000-0000-000000000001","title":"Real event","category":"Workshop","event_status":"published","organization_name":"Club","registration_opens_at":"2026-10-01T10:00:00Z","registration_closes_at":"2026-10-11T10:00:00Z","starts_at":"2026-10-12T10:00:00Z","ends_at":"2026-10-12T11:00:00Z","pass_token":"00000000-0000-0000-0000-000000000011","pass_status":"active","waitlist_position":null}"#.data(using: .utf8)!
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

    func testCameraStepsUseStoredOutdoorAndIndoorGeometry() throws {
        let json = #"{"route_version_id":"00000000-0000-0000-0000-000000000040","total_distance_meters":20,"physical_validation_complete":true,"nodes":[{"id":"00000000-0000-0000-0000-000000000041","coordinate_kind":"outdoor_geographic","floor_id":null,"latitude":28.5,"longitude":77.2,"x_pixels":null,"y_pixels":null,"node_kind":"landmark"},{"id":"00000000-0000-0000-0000-000000000042","coordinate_kind":"outdoor_geographic","floor_id":null,"latitude":28.5,"longitude":77.201,"x_pixels":null,"y_pixels":null,"node_kind":"entrance"},{"id":"00000000-0000-0000-0000-000000000043","coordinate_kind":"indoor_floor","floor_id":"00000000-0000-0000-0000-000000000044","latitude":null,"longitude":null,"x_pixels":10,"y_pixels":10,"node_kind":"landmark"},{"id":"00000000-0000-0000-0000-000000000045","coordinate_kind":"indoor_floor","floor_id":"00000000-0000-0000-0000-000000000044","latitude":null,"longitude":null,"x_pixels":20,"y_pixels":10,"node_kind":"hall"}],"edges":[{"id":"00000000-0000-0000-0000-000000000046","kind":"walkway","distance_meters":10,"instruction":"Walk east","from_node_id":"00000000-0000-0000-0000-000000000041","to_node_id":"00000000-0000-0000-0000-000000000042"},{"id":"00000000-0000-0000-0000-000000000047","kind":"corridor","distance_meters":10,"instruction":"Use the corridor","from_node_id":"00000000-0000-0000-0000-000000000043","to_node_id":"00000000-0000-0000-0000-000000000045"}]}"#.data(using: .utf8)!
        let route = try JSONDecoder().decode(RoutePlan.self, from: json)
        let floorID = UUID(uuidString: "00000000-0000-0000-0000-000000000044")!
        let floor = FloorPlan(id: floorID, name: "Ground", level: 0, floorPlanPath: "path", imageWidthPixels: 100, imageHeightPixels: 100, rotationDegrees: 30)
        let steps = route.cameraSteps(floorPlans: [floorID: floor])
        XCTAssertEqual(steps[0].bearingDegrees!, 90, accuracy: 0.1)
        XCTAssertEqual(steps[1].bearingDegrees!, 120, accuracy: 0.1)
        XCTAssertEqual(steps[0].bearingRelativeToConfirmedFacing(30)!, 60, accuracy: 0.1)
    }

    func testOpenMeetupFeedAndRegistrationDecode() throws {
        let json = #"[{"id":"00000000-0000-0000-0000-000000000050","title":"Canteen Chai Meetup","description":"Grab chai and meet someone new.","location_note":null,"icebreaker":"What's been the best part of your week?","audience":"selected_colleges","capacity":12,"going_count":12,"starts_at":"2026-10-14T10:30:00+00:00","ends_at":"2026-10-14T11:30:00+00:00","status":"published","college_name":"IIIT Delhi","host_name":"Aarav","host_headline":"Final-year CSE","host_verified":true,"venue_name":"Student Activity Centre","campus_name":"IIIT Delhi Campus","destination_landmark_id":null,"participating_colleges":["DTU","IIIT Delhi"],"my_status":null,"is_eligible":true}]"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meetup = try XCTUnwrap(decoder.decode([OpenMeetup].self, from: json).first)
        XCTAssertTrue(meetup.hostVerified)
        XCTAssertTrue(meetup.isFull)
        XCTAssertFalse(meetup.isGoing)
        XCTAssertEqual(meetup.spotsLeft, 0)
        XCTAssertEqual(meetup.audienceLabel, "Open to DTU, IIIT Delhi")

        let resultJSON = #"{"registration_id":"00000000-0000-0000-0000-000000000051","status":"going","going_count":5,"capacity":12,"idempotent_replay":false}"#.data(using: .utf8)!
        let result = try JSONDecoder().decode(MeetupRegistrationResult.self, from: resultJSON)
        XCTAssertEqual(result.status, "going")
        XCTAssertEqual(result.goingCount, 5)
    }

    func testOpenMeetupAudienceAndCapacityLabels() throws {
        func meetup(audience: String, colleges: [String], going: Int, capacity: Int) throws -> OpenMeetup {
            let json = #"{"id":"00000000-0000-0000-0000-000000000060","title":"Just Talk","description":"No agenda.","location_note":null,"icebreaker":"What's been the best part of your week?","audience":"\#(audience)","capacity":\#(capacity),"going_count":\#(going),"starts_at":"2026-10-14T10:30:00Z","ends_at":"2026-10-14T11:30:00Z","status":"published","college_name":"IIIT Delhi","host_name":"Aarav","host_headline":null,"host_verified":false,"venue_name":"Canteen","campus_name":"Main","destination_landmark_id":null,"participating_colleges":\#(colleges.description),"my_status":"going","is_eligible":true}"#.data(using: .utf8)!
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(OpenMeetup.self, from: json)
        }
        XCTAssertEqual(try meetup(audience: "all_colleges", colleges: [], going: 1, capacity: 5).audienceLabel, "Open to all participating colleges")
        XCTAssertEqual(try meetup(audience: "selected_colleges", colleges: [], going: 1, capacity: 5).audienceLabel, "Open to IIIT Delhi students")
        XCTAssertEqual(try meetup(audience: "selected_colleges", colleges: ["IIIT Delhi"], going: 1, capacity: 5).audienceLabel, "Open to IIIT Delhi students")
        let overfull = try meetup(audience: "all_colleges", colleges: [], going: 6, capacity: 5)
        XCTAssertEqual(overfull.spotsLeft, 0)
        XCTAssertTrue(overfull.isFull)
        XCTAssertTrue(overfull.isGoing)
        XCTAssertFalse(overfull.hostVerified)
    }

    func testMissingMeetupBackendCodesAreRecognised() {
        XCTAssertTrue(AppModel.isMissingMeetupBackend(code: "PGRST205"))
        XCTAssertTrue(AppModel.isMissingMeetupBackend(code: "PGRST202"))
        XCTAssertFalse(AppModel.isMissingMeetupBackend(code: "PGRST116"))
        XCTAssertFalse(AppModel.isMissingMeetupBackend(code: nil))
        XCTAssertNotNil(SidequestError.meetupsUnavailable.errorDescription)
    }

    private func validDraft(now: Date) -> MeetupDraft {
        var draft = MeetupDraft(now: now)
        draft.title = "Canteen Chai Meetup"
        draft.description = "Grab chai and meet someone new."
        draft.hostName = "Riya"
        draft.collegeId = UUID()
        draft.venueId = UUID()
        return draft
    }

    func testMeetupDraftValidationAcceptsCompleteDraft() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let draft = validDraft(now: now)
        XCTAssertTrue(draft.errors(now: now).isEmpty)
        XCTAssertGreaterThan(draft.startsAt, now)
        XCTAssertEqual(draft.endsAt.timeIntervalSince(draft.startsAt), 3600)
        XCTAssertEqual(draft.serverAudience, "selected_colleges")
        XCTAssertTrue(draft.serverCollegeIds.isEmpty)
    }

    func testMeetupDraftValidationRejectsInvalidFields() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = validDraft(now: now)
        draft.title = "  "
        draft.description = "short"
        draft.hostName = ""
        draft.venueId = nil
        draft.collegeId = nil
        draft.startsAt = now.addingTimeInterval(60)
        draft.capacity = 1
        draft.icebreaker = "Hi?"
        let errors = draft.errors(now: now)
        for field in [MeetupDraft.Field.title, .description, .hostName, .venue, .college, .startsAt, .capacity, .icebreaker] {
            XCTAssertNotNil(errors[field], "expected error for \(field)")
        }
        draft = validDraft(now: now)
        draft.capacity = 501
        draft.startsAt = now.addingTimeInterval(200 * 24 * 3600)
        XCTAssertNotNil(draft.errors(now: now)[.capacity])
        XCTAssertNotNil(draft.errors(now: now)[.startsAt])
    }

    func testMeetupDraftCollegeAudiences() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var draft = validDraft(now: now)
        let partner = UUID()
        draft.audience = .selectedColleges
        XCTAssertNotNil(draft.errors(now: now)[.colleges], "selected colleges needs at least one other college")
        draft.extraCollegeIds = [partner, draft.collegeId!]
        XCTAssertEqual(draft.serverCollegeIds, [partner], "host college is added by the server, not duplicated")
        XCTAssertNil(draft.errors(now: now)[.colleges])
        draft.audience = .allColleges
        XCTAssertEqual(draft.serverAudience, "all_colleges")
        XCTAssertTrue(draft.serverCollegeIds.isEmpty)
    }

    func testHostedMeetupFlagsAndResultDecode() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000070","title":"Campus walk","description":"A casual campus walk.","location_note":null,"icebreaker":"What's been the best part of your week?","audience":"all_colleges","capacity":10,"going_count":0,"starts_at":"2026-10-14T10:30:00Z","ends_at":"2026-10-14T11:30:00Z","status":"cancelled","college_name":"IIIT Delhi","host_name":"Riya","host_headline":null,"host_verified":false,"venue_name":"Canteen","campus_name":"Main","destination_landmark_id":null,"participating_colleges":[],"my_status":null,"is_eligible":true,"is_host":true}"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let meetup = try decoder.decode(OpenMeetup.self, from: json)
        XCTAssertTrue(meetup.amHost)
        XCTAssertTrue(meetup.isCancelled)
        XCTAssertFalse(meetup.hostVerified, "hosting never implies recognition")
        let result = try JSONDecoder().decode(HostMeetupResult.self, from: #"{"meetup_id":"00000000-0000-0000-0000-000000000070","status":"published","idempotent_replay":true}"#.data(using: .utf8)!)
        XCTAssertTrue(result.idempotentReplay)
    }

    private func chatMessage(_ seq: Int64, id: UUID = UUID(), body: String = "hi") -> ChatMessage {
        ChatMessage(id: id, seq: seq, channelId: UUID(), authorId: UUID(), authorName: "Asha", authorCollege: "IIIT Delhi", body: body, createdAt: Date(timeIntervalSince1970: TimeInterval(seq)), isMine: false)
    }

    func testChatValidationRejectsEmptyAndOversizedMessages() {
        XCTAssertNotNil(ChatModel.validationError(for: ""))
        XCTAssertNotNil(ChatModel.validationError(for: "   \n  "))
        XCTAssertNotNil(ChatModel.validationError(for: String(repeating: "x", count: ChatModel.maxLength + 1)))
        XCTAssertNil(ChatModel.validationError(for: "  Hello  "))
        XCTAssertNil(ChatModel.validationError(for: String(repeating: "x", count: ChatModel.maxLength)))
    }

    func testChatMergeDeduplicatesAndOrdersBySequence() {
        let shared = UUID()
        let existing = [chatMessage(2), chatMessage(5, id: shared, body: "old")]
        let incoming = [chatMessage(7), chatMessage(5, id: shared, body: "new"), chatMessage(1)]
        let merged = ChatModel.merge(existing, with: incoming)
        XCTAssertEqual(merged.map(\.seq), [1, 2, 5, 7])
        XCTAssertEqual(merged.first { $0.id == shared }?.body, "new", "a re-delivered row replaces, not duplicates")
    }

    func testChatRoomAndMessageDecode() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rooms = try decoder.decode([ChatRoom].self, from: #"[{"id":"00000000-0000-0000-0000-000000000080","kind":"topic","title":"Coding","description":"Projects","college_name":null,"starts_at":null,"last_message_body":"Anyone up for a hackathon?","last_message_author":"Asha","last_message_at":"2026-10-14T10:00:00Z","unread_count":3,"sort_order":20}]"#.data(using: .utf8)!)
        XCTAssertEqual(rooms.first?.unreadCount, 3)
        let messages = try decoder.decode([ChatMessage].self, from: #"[{"id":"00000000-0000-0000-0000-000000000081","seq":42,"channel_id":"00000000-0000-0000-0000-000000000080","author_id":"00000000-0000-0000-0000-000000000082","author_name":"Asha","author_college":"IIIT Delhi","body":"Hello","created_at":"2026-10-14T10:00:00Z","is_mine":true}]"#.data(using: .utf8)!)
        XCTAssertEqual(messages.first?.seq, 42)
        XCTAssertTrue(messages.first?.isMine == true)
    }
}
