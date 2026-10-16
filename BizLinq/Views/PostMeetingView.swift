import SwiftUI

/// Screen 6 — Post a meeting. Prefills an editable draft from the host's
/// previous listing when available ("Copied from your previous listing.
/// Review and update."). "Review meeting" leads to Screen 7; nothing
/// publishes from this screen.
struct PostMeetingView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager

    @State private var draft: MeetingDraft
    @State private var located: LocatedAddress?
    @State private var isLocating = false
    @State private var showGeoError = false
    @State private var didPost = false
    @State private var postedTitle = ""
    @State private var showingSignIn = false
    @State private var showingSubscribe = false
    @State private var confirmingCancelTrial = false
    @State private var publishError: String?
    @State private var isPublishing = false
    @State private var showingReview = false
    private let prefilled: Bool

    init(prefill: Meeting? = nil) {
        if let prefill {
            var draft = MeetingDraft(from: prefill)
            // Copied dates must land in the future and still need confirmation.
            if (draft.meetingDateTime ?? Date.distantPast) <= Date() {
                let next = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
                draft.date = next
            }
            _draft = State(initialValue: draft)
            prefilled = true
        } else {
            _draft = State(initialValue: MeetingDraft())
            prefilled = false
        }
    }

    private var trialStatus: TrialStatus {
        TrialStatus.current(start: store.trialStartDate, now: Date(), subscribed: subscriptions.isPosterActive)
    }

    private var locationReady: Bool {
        draft.isVirtual ? !draft.onlineAccess.trimmingCharacters(in: .whitespaces).isEmpty : located != nil
    }

    private var isValid: Bool {
        draft.contactValid && draft.scheduleValid && draft.costValid && locationReady
    }

    /// Placeholder coordinate so virtual drafts can build a review preview.
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
        NavigationStack {
            Group {
                if auth.userID == nil {
                    SignInPrompt(showingSignIn: $showingSignIn)
                } else if didPost {
                    PostSuccessView(title: postedTitle) {
                        didPost = false
                    }
                } else if trialStatus == .expired && !subscriptions.isPosterActive {
                    if store.trialDeclined {
                        TrialPausedView(showingSubscribe: $showingSubscribe)
                    } else {
                        TrialExpiredView(
                            showingSubscribe: $showingSubscribe,
                            confirmingCancelTrial: $confirmingCancelTrial
                        )
                    }
                } else {
                    listingForm
                }
            }
            .navigationTitle("Post a meeting")
            .task {
                await store.refreshTrialFromServer()
            }
            .navigationDestination(isPresented: $showingReview) {
                if let place = reviewPlace {
                    ReviewMeetingView(
                        draft: draft,
                        place: place,
                        confirmTitle: "Publish meeting",
                        isBusy: isPublishing,
                        onConfirm: publish,
                        onEdit: { showingReview = false }
                    )
                }
            }
        }
        .sheet(isPresented: $showingSubscribe) {
            NavigationStack {
                PaywallView {
                    store.setTrialDeclined(false)
                    TrialNotifications.cancelTrialReminders()
                    showingSubscribe = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingSubscribe = false }
                    }
                }
            }
        }
        .confirmationDialog("Cancel your trial?", isPresented: $confirmingCancelTrial, titleVisibility: .visible) {
            Button("Cancel trial", role: .destructive) {
                store.setTrialDeclined(true)
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("You won't be able to post new meetings. You can resubscribe anytime.")
        }
    }

    private var listingForm: some View {
        Form {
            Section {
                switch trialStatus {
                case .notStarted:
                    Text("Post your first meeting free — it starts a 14-day trial, then subscribe to keep posting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .active(let days):
                    Label(days == 1 ? "1 day left in your free trial" : "\(days) days left in your free trial", systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(days <= TrialStatus.reminderDays ? .orange : .secondary)
                case .expired:
                    EmptyView()
                }
                if prefilled {
                    Label("Copied from your previous listing. Review and update.", systemImage: "doc.on.doc")
                        .font(.footnote)
                        .foregroundStyle(BizStyle.teal)
                }
            }

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
                    Text("Review meeting")
                }
                .disabled(!isValid)
                if !isValid {
                    Text(invalidReason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Discard draft", role: .destructive) {
                    draft = MeetingDraft()
                    located = nil
                }
                .font(.subheadline)
            }
        }
        .alert("Couldn't locate that address", isPresented: $showGeoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Include the venue, city, state, and ZIP — e.g. Grand Hall, Orlando, FL 32801.")
        }
        .alert("Couldn't publish", isPresented: Binding(
            get: { publishError != nil },
            set: { if !$0 { publishError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishError ?? "Try again later.")
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .onChange(of: draft.location) { _, _ in
            located = nil
        }
    }

    private var invalidReason: String {
        if !draft.contactValid { return "Fill in every group and contact field with a valid email and phone." }
        if !draft.scheduleValid { return "Pick a future date and time." }
        if !draft.costValid { return "Enter a valid fee amount for paid events." }
        if draft.isVirtual && draft.onlineAccess.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Add online access info for virtual events."
        }
        if !draft.isVirtual && located == nil { return "Find the location to continue." }
        return "Complete the form to continue."
    }

    private func publish() {
        guard let place = reviewPlace else { return }
        isPublishing = true
        Task { @MainActor in
            let hostName = draft.contactName.trimmingCharacters(in: .whitespaces)
            let meeting = draft.buildMeeting(place: place, hostName: hostName.isEmpty ? "Host" : hostName)
            do {
                try await store.publish(meeting)
                postedTitle = meeting.title
                draft = MeetingDraft()
                located = nil
                isPublishing = false
                showingReview = false
                didPost = true
            } catch let error as BackendError {
                isPublishing = false
                switch error {
                case .notSignedIn:
                    showingReview = false
                    showingSignIn = true
                case .server(let message):
                    publishError = message
                }
            } catch {
                isPublishing = false
                publishError = error.localizedDescription
            }
        }
    }
}

struct SignInPrompt: View {
    @Binding var showingSignIn: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 56))
                .foregroundStyle(BizStyle.teal)
            Text("Sign in to post")
                .font(.title2.bold())
            Text("Posting requires a free BizLinq account. Your first 14 days are free.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Sign in with Apple") {
                showingSignIn = true
            }
            .buttonStyle(.borderedProminent)
            .tint(BizStyle.teal)
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
    }
}

struct TrialExpiredView: View {
    @Binding var showingSubscribe: Bool
    @Binding var confirmingCancelTrial: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Your 14-day trial ended")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Subscribe to keep posting your meetings, or cancel and browse free like everyone else.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Subscribe — $10/month") {
                showingSubscribe = true
            }
            .buttonStyle(.borderedProminent)
            .tint(BizStyle.teal)
            Button("Cancel", role: .destructive) {
                confirmingCancelTrial = true
            }
            Spacer()
        }
        .padding()
    }
}

struct TrialPausedView: View {
    @Binding var showingSubscribe: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Posting is paused")
                .font(.title2.bold())
            Text("You cancelled your trial. Resubscribe anytime to post new meetings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Subscribe — $10/month") {
                showingSubscribe = true
            }
            .buttonStyle(.borderedProminent)
            .tint(BizStyle.teal)
            Spacer()
        }
        .padding()
    }
}

struct PostSuccessView: View {
    let title: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Meeting published")
                .font(.title2.bold())
            Text("\"\(title)\" is now live for people across the US to discover. Find it under Host.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(BizStyle.teal)
            Spacer()
        }
        .padding()
    }
}
