import CoreLocation
import XCTest

@testable import BizLinq

@MainActor
final class StoreLogicTests: XCTestCase {
    private func testDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "BizLinqTests")!
        defaults.removePersistentDomain(forName: "BizLinqTests")
        return defaults
    }

    private func meeting(
        title: String,
        latitude: Double = 40.75,
        longitude: Double = -74.0,
        category: MeetingCategory = .technology,
        city: String = "New York",
        daysOut: Int = 3,
        virtual: Bool = false
    ) -> Meeting {
        Meeting(
            title: title,
            groupName: "Test Group",
            category: category,
            tagline: "tg",
            description: "A test meeting description.",
            startsAt: Date().addingTimeInterval(Double(daysOut) * 86400),
            venue: virtual ? "Online" : "V",
            address: virtual ? "Online event" : "A",
            city: city,
            state: "NY",
            zipCode: "10001",
            latitude: latitude,
            longitude: longitude,
            hostName: "H",
            attendeeCount: 5,
            isVirtual: virtual
        )
    }

    func testUnresolvedZipIsFlaggedNotSilent() {
        let store = MeetingStore(meetings: [], defaults: testDefaults())
        XCTAssertFalse(store.locationUnresolved)
        store.searchZip = "00000"
        store.radius = .ten
        store.userCoordinate = nil
        XCTAssertTrue(store.locationUnresolved)
        store.radius = .nationwide
        XCTAssertFalse(store.locationUnresolved)
    }

    func testVisibilityFilter() {
        let store = MeetingStore(meetings: [
            meeting(title: "In person", virtual: false),
            meeting(title: "Online", virtual: true),
        ], defaults: testDefaults())

        store.visibility = .all
        XCTAssertEqual(store.filteredMeetings().count, 2)
        store.visibility = .inPerson
        XCTAssertEqual(store.filteredMeetings().map { $0.meeting.title }, ["In person"])
        store.visibility = .virtual
        XCTAssertEqual(store.filteredMeetings().map { $0.meeting.title }, ["Online"])
    }

    func testTrialStatusMath() {
        let now = Date()
        XCTAssertEqual(TrialStatus.current(start: nil, now: now, subscribed: false), .notStarted)
        XCTAssertEqual(
            TrialStatus.current(start: now, now: now, subscribed: true),
            .active(daysLeft: TrialStatus.lengthDays)
        )
        let fresh = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        XCTAssertEqual(TrialStatus.current(start: fresh, now: now, subscribed: false), .active(daysLeft: 25))
        let old = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        XCTAssertEqual(TrialStatus.current(start: old, now: now, subscribed: false), .expired)
        let edge = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        XCTAssertEqual(TrialStatus.current(start: edge, now: now, subscribed: false), .expired)
    }

    func testWeeklyLimitBlocksSecondPost() {
        let store = MeetingStore(meetings: [], defaults: testDefaults())
        XCTAssertTrue(store.canPostBySchedule)
        XCTAssertNil(store.nextEligiblePostDate)

        store.lastPostDate = Date().addingTimeInterval(-86400)
        XCTAssertFalse(store.canPostBySchedule)
        XCTAssertNotNil(store.nextEligiblePostDate)

        store.lastPostDate = Date().addingTimeInterval(-8 * 86400)
        XCTAssertTrue(store.canPostBySchedule)
        XCTAssertNil(store.nextEligiblePostDate)
    }

    func testRadiusFilterKeepsNearbyAndVirtual() {
        let store = MeetingStore(meetings: [
            meeting(title: "NYC one"),
            meeting(title: "LA one", latitude: 34.05, longitude: -118.24, city: "Los Angeles"),
            meeting(title: "Virtual one", virtual: true),
        ], defaults: testDefaults())
        store.userCoordinate = CLLocationCoordinate2D(latitude: 40.75, longitude: -74.0)
        store.searchZip = "10001"
        store.radius = .twentyFive

        let titles = store.filteredMeetings().map { $0.meeting.title }
        XCTAssertTrue(titles.contains("NYC one"))
        XCTAssertTrue(titles.contains("Virtual one"))
        XCTAssertFalse(titles.contains("LA one"))
    }

    func testNationwideShowsEverything() {
        let store = MeetingStore(meetings: [
            meeting(title: "NYC one"),
            meeting(title: "LA one", latitude: 34.05, longitude: -118.24, city: "Los Angeles"),
        ], defaults: testDefaults())
        store.userCoordinate = CLLocationCoordinate2D(latitude: 40.75, longitude: -74.0)
        store.searchZip = "10001"
        store.radius = .nationwide

        XCTAssertEqual(store.filteredMeetings().count, 2)
    }

    func testQueryAndCategoryFilter() {
        let store = MeetingStore(meetings: [
            meeting(title: "Founders Coffee", category: .businessNetworking),
            meeting(title: "Tech Mixer", category: .technology),
        ], defaults: testDefaults())

        store.query = "coffee"
        XCTAssertEqual(store.filteredMeetings().map { $0.meeting.title }, ["Founders Coffee"])

        store.query = ""
        store.selectedCategory = .technology
        XCTAssertEqual(store.filteredMeetings().map { $0.meeting.title }, ["Tech Mixer"])
    }

    func testPastMeetingsAreHidden() {
        let store = MeetingStore(meetings: [
            meeting(title: "Future", daysOut: 3),
            meeting(title: "Past", daysOut: -3),
        ], defaults: testDefaults())

        XCTAssertEqual(store.filteredMeetings().map { $0.meeting.title }, ["Future"])
    }

    func testToggleRSVPOffline() async throws {
        let first = meeting(title: "RSVP me")
        let store = MeetingStore(meetings: [first], defaults: testDefaults())
        XCTAssertNil(store.backend)

        try await store.toggleRSVP(for: first)
        XCTAssertTrue(store.hasRSVPd(first))
        XCTAssertEqual(store.meetings.first?.attendeeCount, 6)

        try await store.toggleRSVP(for: first)
        XCTAssertFalse(store.hasRSVPd(first))
        XCTAssertEqual(store.meetings.first?.attendeeCount, 5)
    }
}
