import SwiftUI

/// Edits a meeting the user already posted. Same fields as the listing form,
/// prefilled from the live meeting. Saving PATCHes the row (RLS: hosts may
/// only update their own meetings) and refreshes it in place.
struct EditMeetingView: View {
    @EnvironmentObject private var store: MeetingStore
    @Environment(\.dismiss) private var dismiss

    let meeting: Meeting

    @State private var groupName: String
    @State private var contactName: String
    @State private var phone: String
    @State private var email: String
    @State private var website: String
    @State private var date: Date
    @State private var time: Date
    @State private var location: String
    @State private var category: MeetingCategory
    @State private var located: LocatedAddress?
    @State private var isLocating = false

    @State private var isSaving = false
    @State private var showGeoError = false
    @State private var saveError: String?

    init(meeting: Meeting) {
        self.meeting = meeting
        let contact = Self.parseContact(meeting.description)
        _groupName = State(initialValue: meeting.groupName)
        _contactName = State(initialValue: contact.name)
        _phone = State(initialValue: contact.phone)
        _email = State(initialValue: contact.email)
        _website = State(initialValue: contact.website)
        _date = State(initialValue: meeting.startsAt)
        _time = State(initialValue: meeting.startsAt)
        _location = State(initialValue: meeting.address.isEmpty ? meeting.venue : meeting.address)
        _category = State(initialValue: meeting.category)
    }

    private static func parseContact(_ description: String) -> (name: String, phone: String, email: String, website: String) {
        var text = description
        if let range = text.range(of: "Contact: ") {
            text = String(text[range.upperBound...])
        }
        // Descriptions end with " More info: ..." — cut it off.
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

    private var meetingDateTime: Date? {
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

    private var contactValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
            && !contactName.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.filter({ $0.isNumber }).count >= 7
            && email.contains("@") && email.contains(".")
            && !website.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isValid: Bool {
        contactValid
            && (meetingDateTime ?? Date.distantPast) > Date()
            && located != nil
    }

    var body: some View {
        Form {
            Section("Group") {
                TextField("Name of group", text: $groupName)
                Picker("Category", selection: $category) {
                    ForEach(MeetingCategory.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            Section("Contact") {
                TextField("Name of contact", text: $contactName)
                TextField("Phone number", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Website", text: $website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }

            Section("Meeting") {
                DatePicker("Date of meeting", selection: $date, in: Date()..., displayedComponents: [.date])
                DatePicker("Time of meeting", selection: $time, displayedComponents: [.hourAndMinute])
                TextField("Location (venue, city, state, ZIP)", text: $location)
                if let located {
                    Label("Found: \(located.label)", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        locate()
                    } label: {
                        if isLocating {
                            ProgressView()
                        } else {
                            Text("Find location")
                        }
                    }
                    .disabled(location.trimmingCharacters(in: .whitespaces).isEmpty || isLocating)
                }
            }

            Section {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Save changes")
                    }
                }
                .disabled(!isValid || isSaving)
                if !isValid {
                    Text("Fill in every field, pick a future date and time, and find the location to save.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit meeting")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            // Pre-resolve the existing address so Save works without re-finding.
            if located == nil, !location.trimmingCharacters(in: .whitespaces).isEmpty {
                located = await store.locate(location)
            }
        }
        .alert("Couldn't locate that address", isPresented: $showGeoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Include the venue, city, state, and ZIP — e.g. Grand Hall, Orlando, FL 32801.")
        }
        .alert("Couldn't save", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "Try again later.")
        }
        .onChange(of: location) { _, _ in
            located = nil
        }
    }

    private func locate() {
        guard !location.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLocating = true
        Task { @MainActor in
            if let found = await store.locate(location) {
                located = found
            } else {
                showGeoError = true
            }
            isLocating = false
        }
    }

    private func save() {
        guard isValid, let startsAt = meetingDateTime, let place = located else { return }
        isSaving = true
        Task { @MainActor in
            let contact = "Contact: \(contactName.trimmingCharacters(in: .whitespaces)) · \(phone.trimmingCharacters(in: .whitespaces)) · \(email.trimmingCharacters(in: .whitespaces)) · \(website.trimmingCharacters(in: .whitespaces))"
            var updated = meeting
            updated.groupName = groupName.trimmingCharacters(in: .whitespaces)
            updated.title = groupName.trimmingCharacters(in: .whitespaces)
            updated.category = category
            updated.tagline = "\(groupName.trimmingCharacters(in: .whitespaces)) — \(place.city)"
            updated.description = contact
            updated.startsAt = startsAt
            updated.venue = location.trimmingCharacters(in: .whitespaces)
            updated.address = location.trimmingCharacters(in: .whitespaces)
            updated.city = place.city
            updated.state = place.state
            updated.zipCode = place.zip
            updated.latitude = place.coordinate.latitude
            updated.longitude = place.coordinate.longitude
            updated.hostName = contactName.trimmingCharacters(in: .whitespaces)
            do {
                try await store.saveEdits(updated)
                dismiss()
            } catch let error as BackendError {
                saveError = error.errorDescription
            } catch {
                saveError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
