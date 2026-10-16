import CoreLocation
import Foundation

/// A meeting paired with its distance from the search origin, if known.
struct RankedMeeting: Identifiable {
    let meeting: Meeting
    let distanceMiles: Double?
    var id: UUID { meeting.id }
}

/// A free-text location resolved to coordinates plus city/state/ZIP.
struct LocatedAddress {
    var coordinate: CLLocationCoordinate2D
    var city: String
    var state: String
    var zip: String
    var label: String
}

/// In-person vs virtual filter on Discover.
enum VisibilityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case inPerson = "In-person"
    case virtual = "Virtual"

    var id: String { rawValue }
}

@MainActor
final class MeetingStore: ObservableObject {
    private enum Keys {
        static let zip = "bizlinq.zip"
        static let radius = "bizlinq.radius"
        static let myIDs = "bizlinq.myMeetingIDs"
        static let rsvps = "bizlinq.rsvpIDs"
        static let blocked = "bizlinq.blockedHostIDs"
        static let trialStart = "bizlinq.trialStartDate"
        static let trialDeclined = "bizlinq.trialDeclined"
    }

    @Published var meetings: [Meeting] = []
    @Published var searchZip: String = ""
    @Published var radius: SearchRadius = .twentyFive
    @Published var query: String = ""
    @Published var selectedCategory: MeetingCategory? = nil
    @Published var visibility: VisibilityFilter = .all
    @Published var sortByDistance: Bool = true

    @Published var userCoordinate: CLLocationCoordinate2D? = nil
    @Published var resolvedPlace: String? = nil
    @Published var isResolving: Bool = false

    @Published var myMeetingIDs: Set<UUID> = []
    @Published var rsvpIDs: Set<UUID> = []
    @Published var backendError: String? = nil
    /// Hosts the user has blocked. Their meetings are hidden everywhere.
    @Published var blockedHostIDs: Set<UUID> = []
    /// Start of the 14-day posting trial (server-stamped, cached locally).
    @Published var trialStartDate: Date? = nil
    @Published var trialDeclined: Bool = false

    /// Nil in tests, screenshots, and offline mode: the store then behaves
    /// exactly like the original local-only prototype.
    var backend: BackendServiceProtocol?
    var auth: AuthManager?

    private let defaults: UserDefaults

    init(meetings: [Meeting]? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.meetings = meetings ?? []
        self.searchZip = defaults.string(forKey: Keys.zip) ?? ""
        if let saved = defaults.object(forKey: Keys.radius) as? Double,
           let r = SearchRadius(rawValue: saved) {
            radius = r
        }
        let ids = defaults.stringArray(forKey: Keys.myIDs) ?? []
        myMeetingIDs = Set(ids.compactMap { UUID(uuidString: $0) })
        let blocked = defaults.stringArray(forKey: Keys.blocked) ?? []
        blockedHostIDs = Set(blocked.compactMap { UUID(uuidString: $0) })
        let rsvps = defaults.stringArray(forKey: Keys.rsvps) ?? []
        rsvpIDs = Set(rsvps.compactMap { UUID(uuidString: $0) })
        let trialStamp = defaults.double(forKey: Keys.trialStart)
        if trialStamp > 0 {
            trialStartDate = Date(timeIntervalSince1970: trialStamp)
        }
        trialDeclined = defaults.bool(forKey: Keys.trialDeclined)
        if !searchZip.isEmpty {
            Task { await resolveZip() }
        }
    }

    // MARK: - Backend sync

    /// Pulls the live list from Supabase. Server is the source of truth;
    /// locally posted meetings are preserved across the refresh.
    func refreshFromBackend() async {
        guard let backend else { return }
        do {
            let remote = try await backend.fetchMeetings()
            let localOnly = meetings.filter { local in
                !remote.contains(where: { $0.id == local.id })
                    && myMeetingIDs.contains(local.id)
            }
            meetings = remote + localOnly
            backendError = nil
        } catch {
            backendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshMyMeetings() async {
        guard let backend, let uid = auth?.userID else { return }
        do {
            let mine = try await backend.fetchMyMeetings(userID: uid)
            myMeetingIDs = Set(mine.map { $0.id })
            persistMyIDs()
            backendError = nil
        } catch {
            backendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Pulls the server-stamped trial start (authoritative; survives reinstalls).
    func refreshTrialFromServer() async {
        guard let backend, let uid = auth?.userID else { return }
        do {
            if let server = try await backend.fetchTrialStart(userID: uid) {
                trialStartDate = server
                persistTrial()
            }
        } catch {
            // Offline: keep the local cache.
        }
    }

    func setTrialDeclined(_ declined: Bool) {
        trialDeclined = declined
        defaults.set(declined, forKey: Keys.trialDeclined)
    }

    private func persistTrial() {
        if let trialStartDate {
            defaults.set(trialStartDate.timeIntervalSince1970, forKey: Keys.trialStart)
        } else {
            defaults.removeObject(forKey: Keys.trialStart)
        }
    }

    /// Publishes a meeting. Throws BackendError.notSignedIn when logged out.
    /// There are no posting limits: posters may publish as often as they like.
    func publish(_ draft: Meeting) async throws {
        guard let backend, let auth, let uid = auth.userID else {
            post(draft)
            return
        }
        var meeting = draft
        meeting.hostID = uid
        if meeting.hostName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            meeting.hostName = auth.displayName.isEmpty ? "Host" : auth.displayName
        }
        do {
            let created = try await backend.postMeeting(meeting)
            meetings.append(created)
            myMeetingIDs.insert(created.id)
            persistMyIDs()
            backendError = nil
            if trialStartDate == nil {
                trialStartDate = Date()
                persistTrial()
                await TrialNotifications.requestPermission()
                TrialNotifications.scheduleTrialReminders(start: Date())
            }
            await refreshTrialFromServer()
        } catch {
            throw error
        }
    }

    /// Saves edits to a meeting the user already posted.
    /// Throws BackendError.notSignedIn when logged out.
    func saveEdits(_ meeting: Meeting) async throws {
        guard let backend, auth?.userID != nil else {
            throw BackendError.notSignedIn
        }
        let updated = try await backend.updateMeeting(meeting)
        if let index = meetings.firstIndex(where: { $0.id == updated.id }) {
            meetings[index] = updated
        }
        backendError = nil
    }

    // MARK: - Location

    func updateLocation(zip: String, radius: SearchRadius) async {
        searchZip = zip
        self.radius = radius
        saveLocation()
        await resolveZip()
        if let auth, auth.isSignedIn {
            await auth.saveHomeLocation(zip: zip, radiusMiles: radius.miles.map { Int($0) })
        }
    }

    func saveLocation() {
        defaults.set(searchZip, forKey: Keys.zip)
        defaults.set(radius.rawValue, forKey: Keys.radius)
    }

    func resolveZip() async {
        let zip = searchZip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !zip.isEmpty else {
            userCoordinate = nil
            resolvedPlace = nil
            return
        }
        if let local = ZipDatabase.lookup(zip) {
            userCoordinate = local.coordinate
            resolvedPlace = local.placeLabel
            return
        }
        isResolving = true
        defer { isResolving = false }
        if let result = await geocode(zip) {
            userCoordinate = result.coordinate
            resolvedPlace = result.label
        } else {
            userCoordinate = nil
            resolvedPlace = nil
        }
    }

    /// Coordinates for a ZIP: local database first, CLGeocoder fallback.
    func coordinates(for zip: String) async -> CLLocationCoordinate2D? {
        await locate(zip)?.coordinate
    }

    /// Resolves free text ("Grand Hall, Orlando, FL 32801") to coordinates
    /// plus city/state/ZIP for the listing form.
    func locate(_ text: String) async -> LocatedAddress? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let local = ZipDatabase.lookup(trimmed), trimmed.filter({ $0.isNumber }).count == 5 {
            return LocatedAddress(
                coordinate: local.coordinate, city: local.city,
                state: local.state, zip: local.zip, label: local.placeLabel
            )
        }
        let found: [CLPlacemark]? = await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(trimmed) { placemarks, _ in
                continuation.resume(returning: placemarks)
            }
        }
        guard let place = found?.first, let location = place.location,
              let city = place.locality, !city.isEmpty,
              let state = place.administrativeArea, !state.isEmpty else {
            return nil
        }
        let label = "\(city), \(state) \(place.postalCode ?? "")".trimmingCharacters(in: .whitespaces)
        return LocatedAddress(
            coordinate: location.coordinate, city: city, state: state,
            zip: place.postalCode ?? "", label: label
        )
    }

    private func geocode(_ zip: String) async -> (coordinate: CLLocationCoordinate2D, label: String)? {
        await withCheckedContinuation { continuation in
            CLGeocoder().geocodeAddressString(zip) { placemarks, _ in
                guard let place = placemarks?.first, let location = place.location else {
                    continuation.resume(returning: nil)
                    return
                }
                let city = place.locality ?? ""
                let state = place.administrativeArea ?? ""
                let label = "\(city), \(state) \(zip)".trimmingCharacters(in: .whitespaces)
                continuation.resume(returning: (location.coordinate, label.isEmpty ? zip : label))
            }
        }
    }

    // MARK: - Search

    func distance(for meeting: Meeting) -> Double? {
        guard !meeting.isVirtual, let user = userCoordinate else { return nil }
        return meeting.distanceMiles(from: user)
    }

    func distanceText(for meeting: Meeting) -> String? {
        if meeting.isVirtual { return "Virtual - join from anywhere" }
        guard let miles = distance(for: meeting) else { return nil }
        if miles < 1 { return "Less than a mile away" }
        return String(format: "%.0f mi away", miles)
    }

    func filteredMeetings() -> [RankedMeeting] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        var out: [RankedMeeting] = meetings
            .filter { $0.status == "live" }
            .filter { meeting in
                guard let host = meeting.hostID else { return true }
                return !blockedHostIDs.contains(host)
            }
            .filter {
                switch visibility {
                case .all: return true
                case .inPerson: return !$0.isVirtual
                case .virtual: return $0.isVirtual
                }
            }
            .filter { $0.startsAt > now }
            .filter { selectedCategory == nil || $0.category == selectedCategory! }
            .filter { meeting in
                guard !q.isEmpty else { return true }
                let haystack = "\(meeting.title) \(meeting.groupName) \(meeting.city) \(meeting.state) \(meeting.description)".lowercased()
                return haystack.contains(q)
            }
            .map { RankedMeeting(meeting: $0, distanceMiles: distance(for: $0)) }
            .filter { ranked in
                if ranked.meeting.isVirtual { return true }
                guard let cap = radius.miles else { return true }
                guard let d = ranked.distanceMiles else { return true }
                return d <= cap
            }
        if sortByDistance, userCoordinate != nil {
            out.sort {
                let a = $0.distanceMiles ?? Double.infinity
                let b = $1.distanceMiles ?? Double.infinity
                if a != b { return a < b }
                return $0.meeting.startsAt < $1.meeting.startsAt
            }
        } else {
            out.sort { $0.meeting.startsAt < $1.meeting.startsAt }
        }
        return out
    }

    /// Live upcoming counts per category, respecting the current search,
    /// radius, and virtual toggle (but not the selected category itself).
    /// Powers the category tiles on Discover.
    func count(for category: MeetingCategory) -> Int {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let now = Date()
        return meetings.filter { meeting in
            guard meeting.status == "live" else { return false }
            guard meeting.category == category else { return false }
            switch visibility {
            case .all: break
            case .inPerson: guard !meeting.isVirtual else { return false }
            case .virtual: guard meeting.isVirtual else { return false }
            }
            guard meeting.startsAt > now else { return false }
            if !q.isEmpty {
                let haystack = "\(meeting.title) \(meeting.groupName) \(meeting.city) \(meeting.state) \(meeting.description)".lowercased()
                guard haystack.contains(q) else { return false }
            }
            if meeting.isVirtual { return true }
            guard let cap = radius.miles else { return true }
            guard let user = userCoordinate else { return true }
            return meeting.distanceMiles(from: user) <= cap
        }.count
    }

    var locationSummary: String {
        if radius == .nationwide { return "Nationwide" }
        if searchZip.isEmpty { return "Nationwide" }
        if let place = resolvedPlace { return "Near \(place)" }
        return "Near \(searchZip)"
    }

    /// A ZIP was entered but could not be resolved to coordinates. Showing
    /// unfiltered results in that case (the old behavior) is worse than
    /// saying so — a 10-mile search must never show Philadelphia.
    var locationUnresolved: Bool {
        !searchZip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && radius != .nationwide
            && userCoordinate == nil
            && !isResolving
    }

    // MARK: - Posting

    func post(_ meeting: Meeting) {
        meetings.append(meeting)
        myMeetingIDs.insert(meeting.id)
        persistMyIDs()
        if trialStartDate == nil {
            trialStartDate = Date()
            persistTrial()
            Task {
                await TrialNotifications.requestPermission()
                TrialNotifications.scheduleTrialReminders(start: Date())
            }
        }
    }

    func cancelMeeting(_ meeting: Meeting) async {
        if let backend, auth?.userID != nil {
            do {
                try await backend.cancelMeeting(id: meeting.id)
                backendError = nil
            } catch {
                backendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        meetings.removeAll { $0.id == meeting.id }
        myMeetingIDs.remove(meeting.id)
        persistMyIDs()
    }

    var myMeetings: [Meeting] {
        meetings
            .filter { myMeetingIDs.contains($0.id) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    // MARK: - RSVP (free; requires a free account when online)

    func toggleRSVP(for meeting: Meeting) async throws {
        guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { return }
        if let backend, let auth {
            guard let uid = auth.userID else { throw BackendError.notSignedIn }
            let going = !rsvpIDs.contains(meeting.id)
            try await backend.setRSVP(meetingID: meeting.id, userID: uid, rsvp: going)
            if going {
                rsvpIDs.insert(meeting.id)
                meetings[index].attendeeCount += 1
            } else {
                rsvpIDs.remove(meeting.id)
                meetings[index].attendeeCount = max(0, meetings[index].attendeeCount - 1)
            }
            persistRSVPs()
            backendError = nil
            return
        }
        if backend != nil {
            throw BackendError.notSignedIn
        }
        if rsvpIDs.contains(meeting.id) {
            rsvpIDs.remove(meeting.id)
            meetings[index].attendeeCount = max(0, meetings[index].attendeeCount - 1)
        } else {
            rsvpIDs.insert(meeting.id)
            meetings[index].attendeeCount += 1
        }
        persistRSVPs()
    }

    func hasRSVPd(_ meeting: Meeting) -> Bool {
        rsvpIDs.contains(meeting.id)
    }

    // MARK: - Safety (report + block)

    static let reportReasons = [
        "Spam or scam",
        "Inappropriate content",
        "Wrong date or location",
        "Something else",
    ]

    func reportMeeting(_ meeting: Meeting, reason: String) async throws {
        guard let backend, let uid = auth?.userID else {
            throw BackendError.notSignedIn
        }
        try await backend.submitReport(meetingID: meeting.id, userID: uid, reason: reason)
    }

    func blockHost(of meeting: Meeting) {
        guard let host = meeting.hostID else { return }
        blockedHostIDs.insert(host)
        defaults.set(blockedHostIDs.map { $0.uuidString }, forKey: Keys.blocked)
    }

    // MARK: - Persistence

    private func persistMyIDs() {
        defaults.set(myMeetingIDs.map { $0.uuidString }, forKey: Keys.myIDs)
    }

    private func persistRSVPs() {
        defaults.set(rsvpIDs.map { $0.uuidString }, forKey: Keys.rsvps)
    }
}
