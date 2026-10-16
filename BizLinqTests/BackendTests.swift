import Foundation
import XCTest

@testable import BizLinq

/// Stubs URLSession for SupabaseRESTClient: no network leaves the test host.
final class StubURLProtocol: URLProtocol {
    static var status: Int = 200
    static var body: Data = Data()
    static var lastURL: URL?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastURL = request.url
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class BackendTests: XCTestCase {
    private func service(status: Int, body: String) -> SupabaseBackendService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        StubURLProtocol.status = status
        StubURLProtocol.body = Data(body.utf8)
        return SupabaseBackendService(client: SupabaseRESTClient(urlSession: URLSession(configuration: config)))
    }

    func testRSVPConflictTreatedAsSuccess() async throws {
        let service = service(status: 409, body: #"{"code":"23505","message":"duplicate key value"}"#)
        try await service.setRSVP(meetingID: UUID(), userID: UUID(), rsvp: true)
    }

    func testServerMessageSurfacesToCaller() async {
        let service = service(status: 401, body: #"{"code":"42501","message":"new row violates row-level security policy"}"#)
        do {
            _ = try await service.fetchMeetings()
            XCTFail("expected an error")
        } catch let error as BackendError {
            XCTAssertEqual(error, .server("(42501) new row violates row-level security policy"))
        } catch {
            XCTFail("wrong error type: \(error)")
        }
    }

    func testMeetingListURLIsWellFormed() async throws {
        let service = service(status: 200, body: "[]")
        let meetings: [Meeting] = try await service.fetchMeetings()
        XCTAssertTrue(meetings.isEmpty)
        XCTAssertEqual(StubURLProtocol.lastURL?.path, "/rest/v1/meetings")
        XCTAssertTrue(StubURLProtocol.lastURL?.query?.contains("select=*") ?? false)
        XCTAssertTrue(StubURLProtocol.lastURL?.query?.contains("order=starts_at.asc") ?? false)
    }

    func testAuthStyleErrorSurfacesDescription() {
        let error = SupabaseRESTClient.APIError(code: nil, message: nil, error: "invalid_grant", errorDetail: "Token has expired")
        XCTAssertEqual(error.errorDescription, "Token has expired")
    }
}
