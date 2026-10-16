import Foundation
import OSLog

private let backendLog = Logger(subsystem: "com.bizlinq.app", category: "backend")

/// Thin URLSession client for the Supabase Auth + PostgREST HTTP APIs.
/// No third-party dependencies: every request, the session lifecycle, and
/// the Codable mapping are owned by this file and covered by tests.
final class SupabaseRESTClient {
    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var userID: UUID

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
            case userID = "user_id"
        }
    }

    /// PostgREST errors look like {"code":"42501","message":"..."}; Auth errors
    /// look like {"error":"...","error_description":"..."}. Conforming to
    /// LocalizedError guarantees the server's message reaches the user
    /// instead of a useless "operation couldn't be completed" string.
    struct APIError: Decodable, Error, LocalizedError {
        var code: String?
        var message: String?
        var error: String?
        var errorDetail: String?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case error
            case errorDetail = "error_description"
        }

        var errorDescription: String? {
            if let message, !message.isEmpty {
                return code.map { "(\($0)) \(message)" } ?? message
            }
            if let detail = errorDetail ?? error, !detail.isEmpty {
                return detail
            }
            return "Request failed."
        }
    }

    let baseURL: URL
    let anonKey: String
    var session: Session?

    private let urlSession: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = BackendConfig.projectURL, anonKey: String = BackendConfig.anonKey, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.anonKey = anonKey
        self.urlSession = urlSession
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.encoder = JSONEncoder()
    }

    // MARK: - Auth

    /// Exchanges an Apple identity token for a Supabase session.
    func signInWithApple(idToken: String, nonce: String) async throws -> Session {
        struct Body: Encodable {
            let provider: String
            let id_token: String
            let nonce: String
        }
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
            let user: User
            struct User: Decodable { let id: UUID }
        }
        let response: Response = try await post(
            path: "/auth/v1/token?grant_type=id_token",
            body: Body(provider: "apple", id_token: idToken, nonce: nonce),
            bearer: nil,
            prefer: nil
        )
        let session = Session(
            accessToken: response.access_token,
            refreshToken: response.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in - 60)),
            userID: response.user.id
        )
        self.session = session
        return session
    }

    func refreshSession() async throws -> Session {
        guard let current = session else {
            throw BackendError.notSignedIn
        }
        struct Body: Encodable { let refresh_token: String }
        struct Response: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Int
            let user: User
            struct User: Decodable { let id: UUID }
        }
        do {
            let response: Response = try await post(
                path: "/auth/v1/token?grant_type=refresh_token",
                body: Body(refresh_token: current.refreshToken),
                bearer: nil,
                prefer: nil
            )
            let renewed = Session(
                accessToken: response.access_token,
                refreshToken: response.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(response.expires_in - 60)),
                userID: response.user.id
            )
            session = renewed
            return renewed
        } catch {
            session = nil
            throw BackendError.notSignedIn
        }
    }

    func signOut() async {
        if session != nil, var request = try? request(path: "/auth/v1/logout", method: "POST", bearer: session?.accessToken) {
            request.httpBody = Data()
            try? await urlSession.data(for: request)
        }
        session = nil
    }

    /// Bearer for API calls: the user token when signed in (refreshing first
    /// if expired), otherwise the anon key.
    func bearer() async -> String {
        if var current = session {
            if current.expiresAt <= Date() {
                current = (try? await refreshSession()) ?? current
                if session == nil { return anonKey }
            }
            return current.accessToken
        }
        return anonKey
    }

    // MARK: - Database

    func getMeetings() async throws -> [Meeting] {
        // Catalogues grow well past the PostgREST default page; pull every
        // upcoming/live row in bounded pages so nearby meetings are never
        // hidden behind an earlier date's entries.
        var all: [Meeting] = []
        var offset = 0
        let pageSize = 1000
        while true {
            let page: [Meeting] = try await get(
                path: "/rest/v1/meetings?select=*&order=starts_at.asc&limit=\(pageSize)&offset=\(offset)"
            )
            if page.isEmpty { break }
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += page.count
        }
        return all
    }

    func getMyMeetings(userID: UUID) async throws -> [Meeting] {
        try await get(path: "/rest/v1/meetings?select=*&host_id=eq.\(userID.uuidString)&order=starts_at.asc")
    }

    func insertMeeting(_ meeting: Meeting) async throws -> Meeting {
        do {
            let rows: [Meeting] = try await post(path: "/rest/v1/meetings", body: meeting, prefer: "return=representation")
            guard let created = rows.first else {
                throw BackendError.server("The server did not return the new meeting.")
            }
            return created
        } catch let error as APIError {
            throw BackendError.server(error.message ?? "Request failed.")
        }
    }

    /// Saves the host's edits to an existing meeting. Only editable listing
    /// fields are sent; ownership and server-stamped columns stay untouched.
    func updateMeeting(_ meeting: Meeting) async throws -> Meeting {
        struct Payload: Encodable {
            let title: String
            let group_name: String
            let category: String
            let tagline: String
            let description: String
            let starts_at: String
            let venue: String
            let address: String
            let city: String
            let state: String
            let zip_code: String
            let latitude: Double
            let longitude: Double
            let host_name: String
            let cost_description: String
            let is_virtual: Bool
        }
        let payload = Payload(
            title: meeting.title,
            group_name: meeting.groupName,
            category: meeting.category.rawValue,
            tagline: meeting.tagline,
            description: meeting.description,
            starts_at: Meeting.isoString(meeting.startsAt),
            venue: meeting.venue,
            address: meeting.address,
            city: meeting.city,
            state: meeting.state,
            zip_code: meeting.zipCode,
            latitude: meeting.latitude,
            longitude: meeting.longitude,
            host_name: meeting.hostName,
            cost_description: meeting.costDescription,
            is_virtual: meeting.isVirtual
        )
        do {
            let rows: [Meeting] = try await patchReturning(
                path: "/rest/v1/meetings?id=eq.\(meeting.id.uuidString)", body: payload
            )
            guard let updated = rows.first else {
                throw BackendError.server("The server did not return the updated meeting.")
            }
            return updated
        } catch let error as APIError {
            throw BackendError.server(error.message ?? "Request failed.")
        }
    }

    func cancelMeeting(id: UUID) async throws {
        struct Status: Encodable { let status: String }
        try await patch(path: "/rest/v1/meetings?id=eq.\(id.uuidString)", body: Status(status: "cancelled"))
    }

    func insertRSVP(meetingID: UUID, userID: UUID) async throws {
        struct Row: Encodable {
            let meeting_id: String
            let user_id: String
        }
        let _: EmptyResponse = try await post(path: "/rest/v1/rsvps", body: Row(meeting_id: meetingID.uuidString, user_id: userID.uuidString), prefer: "return=minimal")
    }

    func deleteRSVP(meetingID: UUID, userID: UUID) async throws {
        try await delete(path: "/rest/v1/rsvps?meeting_id=eq.\(meetingID.uuidString)&user_id=eq.\(userID.uuidString)")
    }

    func fetchProfile(id: UUID) async throws -> ProfileRow? {
        let rows: [ProfileRow] = try await get(path: "/rest/v1/profiles?select=*&id=eq.\(id.uuidString)&limit=1")
        return rows.first
    }

    /// Flags a meeting for review. Reporters never see reports; hosts never
    /// see who reported them. Reviewed in the Supabase dashboard.
    func submitReport(meetingID: UUID, userID: UUID, reason: String) async throws {
        struct Row: Encodable {
            let meeting_id: String
            let reporter_id: String
            let reason: String
        }
        let _: EmptyResponse = try await post(
            path: "/rest/v1/reports",
            body: Row(meeting_id: meetingID.uuidString, reporter_id: userID.uuidString, reason: reason),
            prefer: "return=minimal"
        )
    }

    func upsertProfile(_ row: ProfileRow) async throws {
        let _: EmptyResponse = try await post(path: "/rest/v1/profiles", body: row, prefer: "resolution=merge-duplicates")
    }

    // MARK: - HTTP plumbing

    private func request(path: String, method: String, bearer: String?, prefer: String? = nil) throws -> URLRequest {
        // NOTE: never build this with appendingPathComponent — it percent-encodes
        // "?" and "&", turning the query string into a literal table name.
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw BackendError.server("Bad request.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let bearer {
            request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        return request
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        let token = await bearer()
        let (data, response) = try await urlSession.data(for: try request(path: path, method: "GET", bearer: token))
        try validate(response: response, data: data, path: path)
        return try decoder.decode(T.self, from: data)
    }

    @discardableResult
    private func post<Resp: Decodable>(path: String, body: some Encodable, bearer: String? = nil, prefer: String? = nil) async throws -> Resp {
        let token: String
        if let bearer {
            token = bearer
        } else if path.hasPrefix("/auth/") {
            token = anonKey
        } else {
            token = await self.bearer()
        }
        var request = try request(path: path, method: "POST", bearer: token, prefer: prefer)
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, path: path)
        if data.isEmpty, Resp.self == EmptyResponse.self {
            return EmptyResponse() as! Resp
        }
        return try decoder.decode(Resp.self, from: data)
    }

    private func patch<Req: Encodable>(path: String, body: Req) async throws {
        var request = try request(path: path, method: "PATCH", bearer: await bearer())
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, path: path)
    }

    private func patchReturning<Req: Encodable, Resp: Decodable>(path: String, body: Req) async throws -> Resp {
        var request = try request(path: path, method: "PATCH", bearer: await bearer(), prefer: "return=representation")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await urlSession.data(for: request)
        try validate(response: response, data: data, path: path)
        return try decoder.decode(Resp.self, from: data)
    }

    private func delete(path: String) async throws {
        let (data, response) = try await urlSession.data(for: try request(path: path, method: "DELETE", bearer: await bearer()))
        try validate(response: response, data: data, path: path)
    }

    private func validate(response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.server("No response from the server.")
        }
        guard 200..<300 ~= http.statusCode else {
            if let apiError = try? decoder.decode(APIError.self, from: data),
               apiError.code != nil || apiError.error != nil || apiError.errorDetail != nil {
                backendLog.error("Request failed: \(path, privacy: .public) HTTP \(http.statusCode, privacy: .public) code \(apiError.code ?? "-", privacy: .public)")
                throw apiError
            }
            backendLog.error("Request failed: \(path, privacy: .public) HTTP \(http.statusCode, privacy: .public)")
            throw BackendError.server("Request failed (HTTP \(http.statusCode)).")
        }
    }

    private struct EmptyResponse: Decodable {}
}
