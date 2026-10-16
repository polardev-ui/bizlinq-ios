import Foundation

enum BackendError: LocalizedError, Equatable {
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to continue."
        case .server(let message):
            return message
        }
    }
}

protocol BackendServiceProtocol {
    func fetchMeetings() async throws -> [Meeting]
    func fetchMyMeetings(userID: UUID) async throws -> [Meeting]
    func postMeeting(_ meeting: Meeting) async throws -> Meeting
    func updateMeeting(_ meeting: Meeting) async throws -> Meeting
    func cancelMeeting(id: UUID) async throws
    func setRSVP(meetingID: UUID, userID: UUID, rsvp: Bool) async throws
    func submitReport(meetingID: UUID, userID: UUID, reason: String) async throws
    func fetchTrialStart(userID: UUID) async throws -> Date?
}

/// Row in public.profiles. Upserted on sign-in; extended in Profile.
struct ProfileRow: Codable {
    var id: UUID
    var displayName: String?
    var homeZip: String?
    var radiusMiles: Int?
    var trialStartedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case homeZip = "home_zip"
        case radiusMiles = "radius_miles"
        case trialStartedAt = "trial_started_at"
    }

    init(id: UUID, displayName: String?, homeZip: String?, radiusMiles: Int?, trialStartedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.homeZip = homeZip
        self.radiusMiles = radiusMiles
        self.trialStartedAt = trialStartedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        homeZip = try c.decodeIfPresent(String.self, forKey: .homeZip)
        radiusMiles = try c.decodeIfPresent(Int.self, forKey: .radiusMiles)
        trialStartedAt = try Meeting.decodeDate(c, key: .trialStartedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(homeZip, forKey: .homeZip)
        try c.encodeIfPresent(radiusMiles, forKey: .radiusMiles)
        // Never sent: the server trigger owns this field.
    }
}

final class SupabaseBackendService: BackendServiceProtocol {
    let client: SupabaseRESTClient

    init(client: SupabaseRESTClient) {
        self.client = client
    }

    func fetchMeetings() async throws -> [Meeting] {
        do {
            return try await client.getMeetings()
        } catch {
            throw mapError(error)
        }
    }

    func fetchMyMeetings(userID: UUID) async throws -> [Meeting] {
        do {
            return try await client.getMyMeetings(userID: userID)
        } catch {
            throw mapError(error)
        }
    }

    func postMeeting(_ meeting: Meeting) async throws -> Meeting {
        do {
            return try await client.insertMeeting(meeting)
        } catch {
            throw mapError(error)
        }
    }

    func updateMeeting(_ meeting: Meeting) async throws -> Meeting {
        do {
            return try await client.updateMeeting(meeting)
        } catch {
            throw mapError(error)
        }
    }

    func cancelMeeting(id: UUID) async throws {
        do {
            try await client.cancelMeeting(id: id)
        } catch {
            throw mapError(error)
        }
    }

    func setRSVP(meetingID: UUID, userID: UUID, rsvp: Bool) async throws {
        do {
            if rsvp {
                try await client.insertRSVP(meetingID: meetingID, userID: userID)
            } else {
                try await client.deleteRSVP(meetingID: meetingID, userID: userID)
            }
        } catch let apiError as SupabaseRESTClient.APIError where apiError.code == "23505" {
            // Already RSVP'd (e.g. double-tap race): desired end state holds.
            return
        } catch {
            throw mapError(error)
        }
    }

    func submitReport(meetingID: UUID, userID: UUID, reason: String) async throws {
        do {
            try await client.submitReport(meetingID: meetingID, userID: userID, reason: reason)
        } catch {
            throw mapError(error)
        }
    }

    func fetchTrialStart(userID: UUID) async throws -> Date? {
        try await client.fetchProfile(id: userID)?.trialStartedAt
    }

    private func mapError(_ error: Error) -> BackendError {
        if let backendError = error as? BackendError {
            return backendError
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return .server(description)
        }
        return .server(error.localizedDescription)
    }
}
