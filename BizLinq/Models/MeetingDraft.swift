import Foundation

/// Editable draft for posting or editing a meeting. Shared by the Post,
/// Edit, and Review screens so all three always submit the same data.
struct MeetingDraft {
    var groupName = ""
    /// Distinct meeting title. Blank means "same as the group name".
    var meetingTitle = ""
    var audience = ""
    var category = MeetingCategory.businessNetworking
    var contactName = ""
    var phone = ""
    var email = ""
    var website = ""
    var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    var isVirtual = false
    var location = ""
    var onlineAccess = ""
    var isPaid = false
    var feeAmount = ""
    var feeCurrency = "USD"

    var resolvedTitle: String {
        let custom = meetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var meetingDateTime: Date? {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = day.year
        merged.month = day.month
        merged.day = day.day
        merged.hour = clock.hour
        merged.minute = clock.minute
        return calendar.date(from: merged)
    }

    /// Fee in minor units, nil when unpaid/invalid.
    var feeCentsValue: Int? {
        guard isPaid else { return nil }
        let cleaned = feeAmount.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let major = Double(cleaned), major > 0 else { return nil }
        return Int((major * 100).rounded())
    }

    var contactValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
            && !contactName.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.filter({ $0.isNumber }).count >= 7
            && email.contains("@") && email.contains(".")
            && !website.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var scheduleValid: Bool {
        (meetingDateTime ?? Date.distantPast) > Date()
    }

    var costValid: Bool {
        if !isPaid { return true }
        return feeCentsValue != nil
    }

    var contactLine: String {
        "Contact: \(contactName.trimmingCharacters(in: .whitespaces)) · \(phone.trimmingCharacters(in: .whitespaces)) · \(email.trimmingCharacters(in: .whitespaces)) · \(website.trimmingCharacters(in: .whitespaces))"
    }

    var costDescriptionValue: String {
        if let cents = feeCentsValue {
            let major = Double(cents) / 100.0
            let symbol = Meeting.currencySymbol(for: feeCurrency)
            return String(format: "%@%.2f", symbol, major).replacingOccurrences(of: ".00", with: "")
        }
        return isPaid ? "Paid (see organizer)" : "Free"
    }

    /// Builds the submittable meeting. Location must already be resolved.
    func buildMeeting(preserving existing: Meeting? = nil, place: LocatedAddress, hostName: String) -> Meeting {
        var meeting = existing ?? Meeting(
            title: "", groupName: "", category: .businessNetworking,
            tagline: "", description: "", startsAt: Date(),
            venue: "", address: "", city: "", state: "", zipCode: "",
            latitude: 0, longitude: 0, hostName: "",
            attendeeCount: 1, costDescription: "Free"
        )
        let title = resolvedTitle
        meeting.title = title
        meeting.groupName = groupName.trimmingCharacters(in: .whitespaces)
        meeting.category = category
        let audienceTrimmed = audience.trimmingCharacters(in: .whitespacesAndNewlines)
        meeting.audience = audienceTrimmed.isEmpty ? nil : audienceTrimmed
        meeting.tagline = "\(title) — \(place.city)"
        meeting.description = contactLine
        meeting.startsAt = meetingDateTime ?? Date()
        if isVirtual {
            meeting.isVirtual = true
            meeting.venue = "Online"
            meeting.address = onlineAccess.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            meeting.isVirtual = false
            meeting.venue = location.trimmingCharacters(in: .whitespaces)
            meeting.address = location.trimmingCharacters(in: .whitespaces)
        }
        meeting.city = place.city
        meeting.state = place.state
        meeting.zipCode = place.zip
        meeting.latitude = place.coordinate.latitude
        meeting.longitude = place.coordinate.longitude
        meeting.hostName = hostName
        meeting.costDescription = costDescriptionValue
        meeting.feeCents = feeCentsValue
        meeting.feeCurrency = isPaid ? feeCurrency : nil
        return meeting
    }

    /// Prefills every field from an already-live meeting.
    init() {}

    init(from meeting: Meeting) {
        groupName = meeting.groupName
        meetingTitle = meeting.title == meeting.groupName ? "" : meeting.title
        audience = meeting.audience ?? ""
        category = meeting.category
        let contact = Self.parseContact(meeting.description)
        contactName = contact.name
        phone = contact.phone
        email = contact.email
        website = contact.website
        date = meeting.startsAt
        time = meeting.startsAt
        isVirtual = meeting.isVirtual
        if meeting.isVirtual {
            onlineAccess = meeting.address
        } else {
            location = meeting.address.isEmpty ? meeting.venue : meeting.address
        }
        if let cents = meeting.feeCents, cents > 0 {
            isPaid = true
            feeAmount = String(format: "%.2f", Double(cents) / 100.0)
            feeCurrency = meeting.feeCurrency ?? "USD"
        } else {
            isPaid = !meeting.isFreeEntry
            feeAmount = ""
            feeCurrency = meeting.feeCurrency ?? "USD"
        }
    }

    static func parseContact(_ description: String) -> (name: String, phone: String, email: String, website: String) {
        var text = description
        if let range = text.range(of: "Contact: ") {
            text = String(text[range.upperBound...])
        }
        if let range = text.range(of: " More info:") {
            text = String(text[..<range.lowerBound])
        }
        let parts = text.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        return (
            name: parts.indices.contains(0) ? parts[0] : "",
            phone: parts.indices.contains(1) ? parts[1] : "",
            email: parts.indices.contains(2) ? parts[2] : "",
            website: parts.indices.contains(3) ? parts[3] : ""
        )
    }
}
