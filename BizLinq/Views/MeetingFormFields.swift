import SwiftUI

/// Shared listing form fields for Post and Edit. Validation lives on
/// MeetingDraft; location resolution binds back to the host screen.
struct MeetingFormFields: View {
    @EnvironmentObject private var store: MeetingStore
    @Binding var draft: MeetingDraft
    @Binding var located: LocatedAddress?
    @Binding var isLocating: Bool
    @Binding var showGeoError: Bool

    private var timezoneNote: String {
        let abbrev = TimeZone.current.abbreviation() ?? ""
        return abbrev.isEmpty ? "Times use your device clock." : "Times in \(abbrev) (your device clock)."
    }

    var body: some View {
        BizFormSection(title: "Group") {
            TextField("Name of group", text: $draft.groupName)
            TextField("Meeting title (optional — defaults to group name)", text: $draft.meetingTitle)
            TextField("Who is it for? (e.g. first-time founders)", text: $draft.audience)
            Picker("Category", selection: $draft.category) {
                ForEach(MeetingCategory.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        }

        BizFormSection(title: "Contact") {
            TextField("Name of contact", text: $draft.contactName)
            TextField("Phone number", text: $draft.phone)
                .keyboardType(.phonePad)
            TextField("Email", text: $draft.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("Website", text: $draft.website)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
        }

        BizFormSection(title: "Meeting", footnote: timezoneNote) {
            DatePicker("Date of meeting", selection: $draft.date, in: Date()..., displayedComponents: [.date])
            DatePicker("Time of meeting", selection: $draft.time, displayedComponents: [.hourAndMinute])
            Picker("Format", selection: $draft.isVirtual) {
                Text("In person").tag(false)
                Text("Online").tag(true)
            }
            .pickerStyle(.segmented)
            if draft.isVirtual {
                TextField("Online access info (e.g. Zoom link sent via event page)", text: $draft.onlineAccess)
            } else {
                TextField("Location (venue, city, state, ZIP)", text: $draft.location)
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
                    .disabled(draft.location.trimmingCharacters(in: .whitespaces).isEmpty || isLocating)
                }
            }
        }

        BizFormSection(title: "Attendance cost") {
            Picker("Cost", selection: $draft.isPaid) {
                Text("Free").tag(false)
                Text("Paid").tag(true)
            }
            .pickerStyle(.segmented)
            if draft.isPaid {
                HStack {
                    TextField("Amount", text: $draft.feeAmount)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $draft.feeCurrency) {
                        ForEach(["USD", "EUR", "GBP", "CAD", "AUD"], id: \.self) { code in
                            Text("\(Meeting.currencySymbol(for: code)) \(code)").tag(code)
                        }
                    }
                }
                Text("Attendees pay you directly — BizLinq never collects event fees.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func locate() {
        guard !draft.location.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLocating = true
        Task { @MainActor in
            if let found = await store.locate(draft.location) {
                located = found
            } else {
                showGeoError = true
            }
            isLocating = false
        }
    }
}
