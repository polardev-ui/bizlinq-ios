import CoreLocation
import XCTest

@testable import BizLinq

final class MeetingTests: XCTestCase {
    private func sample(
        title: String = "T",
        category: MeetingCategory = .technology,
        latitude: Double = 40.75,
        longitude: Double = -74.0
    ) -> Meeting {
        Meeting(
            title: title,
            groupName: "G",
            category: category,
            tagline: "tg",
            description: "A test meeting description.",
            startsAt: Date(timeIntervalSince1970: 1_800_000_000),
            venue: "V",
            address: "A",
            city: "New York",
            state: "NY",
            zipCode: "10001",
            latitude: latitude,
            longitude: longitude,
            hostName: "H",
            attendeeCount: 3
        )
    }

    func testHaversineNYCtoLA() {
        let nyc = sample(latitude: 40.75, longitude: -74.0)
        let la = CLLocationCoordinate2D(latitude: 34.05, longitude: -118.24)
        XCTAssertEqual(nyc.distanceMiles(from: la), 2445, accuracy: 40)
    }

    func testHaversineSamePointIsZero() {
        let nyc = sample()
        XCTAssertEqual(nyc.distanceMiles(from: nyc.coordinate), 0, accuracy: 0.001)
    }

    func testCodableRoundTripUsesSnakeCase() throws {
        var meeting = sample()
        meeting.hostID = UUID()
        meeting.attendeeLimit = 10
        let data = try JSONEncoder().encode(meeting)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["group_name"] as? String, "G")
        XCTAssertEqual(json?["zip_code"] as? String, "10001")
        XCTAssertEqual(json?["attendee_limit"] as? Int, 10)
        XCTAssertEqual(json?["is_virtual"] as? Bool, false)
        XCTAssertNil(json?["created_at"], "created_at is server-set and must not be sent")
        let decoded = try JSONDecoder().decode(Meeting.self, from: data)
        XCTAssertEqual(decoded, meeting)
    }

    func testDecodeToleratesUnknownCategoryAndSparsePayload() throws {
        let json = #"{"title":"T","category":"Nope","starts_at":"2026-11-01T18:00:00.123Z"}"#
        let meeting = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
        XCTAssertEqual(meeting.category, .exploreAll)
        XCTAssertEqual(meeting.title, "T")
        XCTAssertNotNil(Meeting.parseISO("2026-11-01T18:00:00.123Z"))
    }

    func testDecodePlainISODateWithoutFraction() throws {
        XCTAssertNotNil(Meeting.parseISO("2026-11-01T18:00:00Z"))
        XCTAssertNotNil(Meeting.parseISO("2026-11-01T18:00:00+00:00"))
        let json = #"{"title":"T","starts_at":"2026-11-01T18:00:00+00:00"}"#
        let meeting = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
        XCTAssertEqual(meeting.startsAt.timeIntervalSince1970, 1_793_556_000, accuracy: 1)
    }

    func testDecodeKeepsCurationFields() throws {
        let json = #"{"title":"T","source":"meetup","source_url":"https://www.meetup.com/g/events/1/"}"#
        let meeting = try JSONDecoder().decode(Meeting.self, from: Data(json.utf8))
        XCTAssertEqual(meeting.source, "meetup")
        XCTAssertEqual(meeting.sourceURL, "https://www.meetup.com/g/events/1/")
        // Never sent back up: encode must omit server-managed fields.
        let data = try JSONEncoder().encode(meeting)
        let round = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNil(round?["created_at"])
        XCTAssertNil(round?["source"])
        XCTAssertNil(round?["source_url"])
    }

    func testSpotsLeftText() {
        var meeting = sample()
        XCTAssertNil(meeting.spotsLeftText)
        meeting.attendeeLimit = 10
        meeting.attendeeCount = 10
        XCTAssertEqual(meeting.spotsLeftText, "Sold out")
        meeting.attendeeCount = 7
        XCTAssertEqual(meeting.spotsLeftText, "3 of 10 spots left")
    }
}
