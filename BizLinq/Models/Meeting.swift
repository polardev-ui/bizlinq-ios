import CoreLocation
import Foundation
import SwiftUI

/// Search radius in miles. `nationwide` means no distance filtering.
enum SearchRadius: Double, CaseIterable, Identifiable, Hashable {
    case five = 5
    case ten = 10
    case twentyFive = 25
    case fifty = 50
    case hundred = 100
    case nationwide = -1

    var id: Double { rawValue }

    var miles: Double? {
        self == .nationwide ? nil : rawValue
    }

    var label: String {
        switch self {
        case .five: return "5 mi"
        case .ten: return "10 mi"
        case .twentyFive: return "25 mi"
        case .fifty: return "50 mi"
        case .hundred: return "100 mi"
        case .nationwide: return "Nationwide"
        }
    }
}

enum MeetingCategory: String, CaseIterable, Identifiable, Codable, Hashable {
    case realEstate = "Real Estate Meetings"
    case businessNetworking = "Business Networking"
    case technology = "Technology Meetings"
    case networkMarketing = "Network Marketing"
    case specialEvents = "Special Events"

    var id: String { rawValue }

    /// Old category names still present in previously imported rows.
    /// Maps them forward so legacy content keeps working.
    /// "Business Start Ups" was merged into Business Networking.
    init(fromLegacy rawValue: String) {
        if let exact = MeetingCategory(rawValue: rawValue) {
            self = exact
            return
        }
        switch rawValue {
        case "Founders & Startups", "Business Start Ups": self = .businessNetworking
        case "Tech & Software": self = .technology
        case "Sales & Marketing": self = .networkMarketing
        default: self = .businessNetworking
        }
    }

    var systemImage: String {
        switch self {
        case .realEstate: return "building.2.fill"
        case .businessNetworking: return "person.2.fill"
        case .technology: return "laptopcomputer"
        case .networkMarketing: return "megaphone.fill"
        case .specialEvents: return "star.fill"
        }
    }

    var tint: Color {
        switch self {
        case .realEstate: return .brown
        case .businessNetworking: return .teal
        case .technology: return .blue
        case .networkMarketing: return .pink
        case .specialEvents: return .purple
        }
    }
}

struct Meeting: Identifiable, Hashable {
    var id: UUID = UUID()
    var hostID: UUID? = nil
    var title: String
    var groupName: String
    var category: MeetingCategory
    var tagline: String
    var description: String
    var startsAt: Date
    var venue: String
    var address: String
    var city: String
    var state: String
    var zipCode: String
    var latitude: Double
    var longitude: Double
    var hostName: String
    var attendeeCount: Int
    var attendeeLimit: Int? = nil
    var isVirtual: Bool = false
    var costDescription: String = "Free"
    var status: String = "live"
    /// Set by the server on insert. Never sent back up.
    var createdAt: Date? = nil
    /// Curation provenance, e.g. source="meetup". Nil for user-posted meetings.
    var source: String? = nil
    var sourceURL: String? = nil

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationLine: String {
        if isVirtual {
            return "Virtual event"
        }
        return "\(venue) - \(city), \(state)"
    }

    var spotsLeftText: String? {
        guard let limit = attendeeLimit else { return nil }
        let left = max(0, limit - attendeeCount)
        if left == 0 { return "Sold out" }
        return "\(left) of \(limit) spots left"
    }

    /// Great-circle distance in miles (haversine).
    func distanceMiles(from other: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let lon2 = other.longitude * .pi / 180
        let h = pow(sin((lat2 - lat1) / 2), 2)
            + cos(lat1) * cos(lat2) * pow(sin((lon2 - lon1) / 2), 2)
        return 2 * 3958.8 * asin(sqrt(h))
    }
}

/// Snake-case Codable that never depends on the JSON decoder's key or date
/// strategy, so it survives SDK and backend formatting changes.
extension Meeting: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case hostID = "host_id"
        case hostName = "host_name"
        case title
        case groupName = "group_name"
        case category
        case tagline
        case description
        case startsAt = "starts_at"
        case venue
        case address
        case city
        case state
        case zipCode = "zip_code"
        case latitude
        case longitude
        case isVirtual = "is_virtual"
        case costDescription = "cost_description"
        case attendeeCount = "attendee_count"
        case attendeeLimit = "attendee_limit"
        case status
        case createdAt = "created_at"
        case source
        case sourceURL = "source_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        hostID = try c.decodeIfPresent(UUID.self, forKey: .hostID)
        hostName = try c.decodeIfPresent(String.self, forKey: .hostName) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        groupName = try c.decodeIfPresent(String.self, forKey: .groupName) ?? ""
        let rawCategory = try c.decodeIfPresent(String.self, forKey: .category)
        category = rawCategory.map(MeetingCategory.init(fromLegacy:)) ?? .businessNetworking
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        startsAt = try Self.decodeDate(c, key: .startsAt) ?? Date()
        venue = try c.decodeIfPresent(String.self, forKey: .venue) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        zipCode = try c.decodeIfPresent(String.self, forKey: .zipCode) ?? ""
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude) ?? 0
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude) ?? 0
        isVirtual = try c.decodeIfPresent(Bool.self, forKey: .isVirtual) ?? false
        costDescription = try c.decodeIfPresent(String.self, forKey: .costDescription) ?? "Free"
        attendeeCount = try c.decodeIfPresent(Int.self, forKey: .attendeeCount) ?? 0
        attendeeLimit = try c.decodeIfPresent(Int.self, forKey: .attendeeLimit)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "live"
        createdAt = try Self.decodeDate(c, key: .createdAt)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(hostID, forKey: .hostID)
        try c.encode(hostName, forKey: .hostName)
        try c.encode(title, forKey: .title)
        try c.encode(groupName, forKey: .groupName)
        try c.encode(category.rawValue, forKey: .category)
        try c.encode(tagline, forKey: .tagline)
        try c.encode(description, forKey: .description)
        try c.encode(Self.isoString(startsAt), forKey: .startsAt)
        try c.encode(venue, forKey: .venue)
        try c.encode(address, forKey: .address)
        try c.encode(city, forKey: .city)
        try c.encode(state, forKey: .state)
        try c.encode(zipCode, forKey: .zipCode)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(isVirtual, forKey: .isVirtual)
        try c.encode(costDescription, forKey: .costDescription)
        try c.encode(attendeeCount, forKey: .attendeeCount)
        try c.encodeIfPresent(attendeeLimit, forKey: .attendeeLimit)
        try c.encode(status, forKey: .status)
    }

    static func decodeDate<K: CodingKey>(_ c: KeyedDecodingContainer<K>, key: K) throws -> Date? {
        if let direct = try? c.decode(Date.self, forKey: key) {
            return direct
        }
        guard let string = try c.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseISO(string)
    }

    static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO(_ string: String) -> Date? {
        isoWithFraction.date(from: string) ?? isoPlain.date(from: string)
    }

    static func isoString(_ date: Date) -> String {
        isoWithFraction.string(from: date)
    }
}

enum Formatters {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d 'at' h:mm a"
        return f
    }()

    static func dateLine(for date: Date) -> String {
        "\(day.string(from: date)) at \(time.string(from: date))"
    }
}
