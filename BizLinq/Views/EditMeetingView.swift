import SwiftUI

/// Edits a meeting the host already posted. Same fields as the listing form,
/// prefilled from the live meeting. Saving PATCHes the row (RLS: hosts may
/// only update their own meetings) — it never creates a second post.
struct EditMeetingView: View {
    @EnvironmentObject private var store: MeetingStore
    @Environment(\.dismiss) private var dismiss

    let meeting: Meeting

    @State private var draft: MeetingDraft
    @State private var located: LocatedAddress?
    @State private var isLocating = false
    @State private var showGeoError = false
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var showingReview = false

    init(meeting: Meeting) {
        self.meeting = meeting
        _draft = State(initialValue: MeetingDraft(from: meeting))
    }

    private var locationReady: Bool {
        draft.isVirtual ? !draft.onlineAccess.trimmingCharacters(in: .whitespaces).isEmpty : located != nil
    }

    private var isValid: Bool {
        draft.contactValid && draft.scheduleValid && draft.costValid && locationReady
    }

    private var reviewPlace: LocatedAddress? {
        if draft.isVirtual {
            return LocatedAddress(
                coordinate: store.userCoordinate ?? .init(latitude: 28.54, longitude: -81.38),
                city: "", state: "", zip: "", label: "Online"
            )
        }
        return located
    }

    var body: some View {
        Form {
            MeetingFormFields(
                draft: $draft,
                located: $located,
                isLocating: $isLocating,
                showGeoError: $showGeoError
            )

            Section {
                Button {
                    showingReview = true
                } label: {
                    Text("Review changes")
                }
                .disabled(!isValid)
                if !isValid {
                    Text("Fill in every field, pick a future date and time, and find the location to save.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .task {
            if located == nil {
                if draft.isVirtual {
                    located = nil
                } else if !draft.location.trimmingCharacters(in: .whitespaces).isEmpty {
                    located = await store.locate(draft.location)
                }
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
        .onChange(of: draft.location) { _, _ in
            located = nil
        }
        .navigationDestination(isPresented: $showingReview) {
            if let place = reviewPlace {
                ReviewMeetingView(
                    draft: draft,
                    place: place,
                    confirmTitle: "Save changes",
                    isBusy: isSaving,
                    onConfirm: save,
                    onEdit: { showingReview = false }
                )
            }
        }
    }

    private func save() {
        guard let place = reviewPlace else { return }
        isSaving = true
        Task { @MainActor in
            let hostName = draft.contactName.trimmingCharacters(in: .whitespaces)
            var updated = draft.buildMeeting(preserving: meeting, place: place, hostName: hostName.isEmpty ? meeting.hostName : hostName)
            updated.id = meeting.id
            updated.hostID = meeting.hostID
            do {
                try await store.saveEdits(updated)
                isSaving = false
                dismiss()
            } catch let error as BackendError {
                isSaving = false
                saveError = error.errorDescription
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
