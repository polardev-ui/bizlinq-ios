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
        // New-era trial: 14 days.
        let era = Calendar.current.date(byAdding: .day, value: 1, to: TrialStatus.cutoverDate)!
        let eraNow = Calendar.current.date(byAdding: .day, value: 5, to: era)!
        XCTAssertEqual(
            TrialStatus.current(start: era, now: era, subscribed: true),
            .active(daysLeft: TrialStatus.lengthDays)
        )
        XCTAssertEqual(TrialStatus.current(start: era, now: eraNow, subscribed: false), .active(daysLeft: 9))
        let eraEdge = Calendar.current.date(byAdding: .day, value: 14, to: era)!
        XCTAssertEqual(TrialStatus.current(start: era, now: eraEdge, subscribed: false), .expired)
        // Pre-cutover trials keep their original 30-day terms.
        let legacy = Calendar.current.date(byAdding: .day, value: -5, to: TrialStatus.cutoverDate)!
        let legacyNow = Calendar.current.date(byAdding: .day, value: 5, to: legacy)!
        XCTAssertEqual(
            TrialStatus.current(start: legacy, now: legacyNow, subscribed: false),
            .active(daysLeft: 25)
        )
        let legacyOld = Calendar.current.date(byAdding: .day, value: -40, to: TrialStatus.cutoverDate)!
        XCTAssertEqual(TrialStatus.current(start: legacyOld, now: legacyNow, subscribed: false), .expired)
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

    func testCostFilterTreatsUnknownAsPaid() {
        var free = meeting(title: "Free one")
        free.costDescription = "Free"
        var paid = meeting(title: "Paid one")
        paid.costDescription = "$25"
        var unknown = meeting(title: "Unknown one")
        unknown.costDescription = "See organizer"
        var page = meeting(title: "Page one")
        page.costDescription = "Paid (see event page)"
        var structured = meeting(title: "Structured one")
        structured.feeCents = 2000
        structured.feeCurrency = "USD"
        XCTAssertTrue(free.isFreeEntry)
        XCTAssertFalse(paid.isFreeEntry)
        XCTAssertFalse(unknown.isFreeEntry)
        XCTAssertFalse(page.isFreeEntry)
        XCTAssertFalse(structured.isFreeEntry)
        XCTAssertEqual(structured.costBadgeText, "$20")
        XCTAssertEqual(unknown.costBadgeText, "Fee varies")
        let store = MeetingStore(meetings: [free, paid, unknown, page, structured], defaults: testDefaults())
        store.costFilter = .free
        XCTAssertEqual(store.filteredMeetings().map { $0.meeting.title }, ["Free one"])
        store.costFilter = .paid
        XCTAssertEqual(store.filteredMeetings().count, 4)
        store.costFilter = .any
        XCTAssertEqual(store.filteredMeetings().count, 5)
    }

    func testDraftCopiesForwardToFuture() {
        var draft = MeetingDraft()
        draft.groupName = "G"
        draft.contactName = "C"
        draft.phone = "5551234567"
        draft.email = "a@b.co"
        draft.website = "https://b.co"
        XCTAssertTrue(draft.contactValid)
        draft.isPaid = true
        draft.feeAmount = ""
        XCTAssertFalse(draft.costValid)
        draft.feeAmount = "25"
        XCTAssertTrue(draft.costValid)
        XCTAssertEqual(draft.feeCentsValue, 2500)
        XCTAssertEqual(draft.costDescriptionValue, "$25")
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

    // MARK: - Trial decision flow

    private func expiredStore() -> MeetingStore {
        let store = MeetingStore(meetings: [], defaults: testDefaults())
        // Post-cutover start, 15 days ago: past the 14-day trial.
        store.trialStartDate = Date().addingTimeInterval(-15 * 86_400)
        return store
    }

    func testTrialEndedPromptShowsOnceWhenExpired() {
        let store = expiredStore()
        XCTAssertTrue(store.shouldShowTrialEnded(subscribed: false))
        XCTAssertFalse(store.shouldShowTrialEnded(subscribed: true))
        store.markTrialEndedPromptSeen()
        XCTAssertFalse(store.shouldShowTrialEnded(subscribed: false))
        XCTAssertTrue(store.trialAwaitingDecision(subscribed: false))
    }

    func testNoPromptDuringActiveTrial() {
        let store = MeetingStore(meetings: [], defaults: testDefaults())
        store.trialStartDate = Date().addingTimeInterval(-3 * 86_400)
        XCTAssertFalse(store.trialAwaitingDecision(subscribed: false))
        XCTAssertFalse(store.shouldShowTrialEnded(subscribed: false))
    }

    func testRemindTomorrowComesDueTheNextDay() {
        let store = expiredStore()
        let now = Date()
        store.remindAboutTrialTomorrow(now: now)
        XCTAssertFalse(store.shouldShowTrialEnded(subscribed: false))
        XCTAssertFalse(store.isTrialReminderDue(subscribed: false, now: now.addingTimeInterval(3_600)))
        XCTAssertTrue(store.isTrialReminderDue(subscribed: false, now: now.addingTimeInterval(86_400 + 60)))
        XCTAssertFalse(store.isTrialReminderDue(subscribed: true, now: now.addingTimeInterval(86_400 + 60)))
    }

    func testJustBrowsingStopsPromptsButKeepsPostingLocked() {
        let store = expiredStore()
        store.remindAboutTrialTomorrow()
        store.stopHostingAfterTrial()
        XCTAssertFalse(store.trialAwaitingDecision(subscribed: false))
        XCTAssertNil(store.trialReminderDate)
        XCTAssertEqual(TrialStatus.current(start: store.trialStartDate, now: Date(), subscribed: false), .expired)
    }

    func testSubscribingResolvesTheTrial() {
        let store = expiredStore()
        store.stopHostingAfterTrial()
        store.trialResolvedBySubscription()
        XCTAssertFalse(store.trialDeclined)
        XCTAssertNil(store.trialReminderDate)
    }

    func testSameTimeTomorrowKeepsWallClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        // 2026-11-01 is a DST change in New York: still the same clock time.
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 18, minute: 45))!
        let next = TrialNotifications.sameTimeTomorrow(from: start, calendar: calendar)
        let parts = calendar.dateComponents([.day, .hour, .minute], from: next)
        XCTAssertEqual(parts.day, 1)
        XCTAssertEqual(parts.hour, 18)
        XCTAssertEqual(parts.minute, 45)
    }

    func testHostRulesPersistPerAccount() {
        let defaults = testDefaults()
        let store = MeetingStore(meetings: [], defaults: defaults)
        XCTAssertFalse(store.hostRulesAccepted)
        store.acceptHostRules()
        XCTAssertTrue(store.hostRulesAccepted)
        XCTAssertTrue(defaults.bool(forKey: HostRules.defaultsKey(for: nil)))
    }
}
