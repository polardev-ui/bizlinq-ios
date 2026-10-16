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
    @State private var showingRules = false
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
                    // Day 14 has passed: posting is locked until a plan is active.
                    if store.trialDeclined {
                        TrialPausedView(showingSubscribe: $showingSubscribe)
                    } else {
                        TrialEndedView(
                            style: .inline,
                            onPlans: { showingSubscribe = true },
                            onBrowse: { store.stopHostingAfterTrial() },
                            onRemind: { store.remindAboutTrialTomorrow() }
                        )
                    }
                } else if !store.hostRulesAccepted {
                    HostRulesRequiredView { showingRules = true }
                } else {
                    listingForm
                }
            }
            .navigationTitle(prefilled ? "Post next meeting" : "Post a meeting")
            .task {
                await store.refreshTrialFromServer()
                await store.refreshHostRules()
                if auth.userID != nil, !store.hostRulesAccepted, trialStatus != .expired || subscriptions.isPosterActive {
                    showingRules = true
                }
            }
            .fullScreenCover(isPresented: $showingRules) {
                HostRulesView(
                    onAccept: {
                        store.acceptHostRules()
                        showingRules = false
                    },
                    onNotNow: { showingRules = false }
                )
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
                PaywallView(context: trialStatus == .expired ? .trialEnded : .standard) {
                    store.trialResolvedBySubscription()
                    showingSubscribe = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingSubscribe = false }
                    }
                }
            }
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
                        .listRowBackground(BizStyle.tealSoft)
                }
            }

            MeetingFormFields(
                draft: $draft,
                located: $located,
                isLocating: $isLocating,
                showGeoError: $showGeoError
            )

            Section {
                Button("Discard draft", role: .destructive) {
                    withAnimation(BizStyle.spring) {
                        draft = MeetingDraft()
                        located = nil
                    }
                }
                .font(.subheadline)
            }
        }
        .animation(BizStyle.spring, value: draft.isVirtual)
        .animation(BizStyle.spring, value: draft.isPaid)
        .animation(BizStyle.spring, value: located != nil)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                if !isValid {
                    Text(invalidReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }
                BizPrimaryButton(title: "Review meeting", enabled: isValid) {
                    showingReview = true
                }
            }
            .animation(BizStyle.snappy, value: isValid)
            .padding(.horizontal, BizStyle.gutter)
            .padding(.top, 10)
            .padding(.bottom, 6)
            .background(.bar)
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
            if subscriptions.isPosterActive {
                // Make sure the server has the verified plan before it checks can_post.
                await subscriptions.resyncWithServer()
            }
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
                    if message.localizedCaseInsensitiveContains("row-level security") {
                        // Server-side can_post said no: trial over, no verified plan.
                        await store.refreshTrialFromServer()
                        showingReview = false
                        publishError = "Your free trial has ended, so new posts need an active plan. Choose a plan to keep posting."
                    } else {
                        publishError = message
                    }
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
        BizIntroView(
            systemImage: "person.badge.key.fill",
            title: "Sign in to post",
            message: "Posting requires a free BizLinq account. Your first 14 days are free.",
            actionTitle: "Sign in with Apple"
        ) { showingSignIn = true }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
    }
}

struct TrialPausedView: View {
    @Binding var showingSubscribe: Bool

    var body: some View {
        BizIntroView(
            systemImage: "pause.circle.fill",
            title: "Posting is paused",
            message: "You cancelled your trial. Resubscribe anytime to post new meetings.",
            actionTitle: "Subscribe — $10/month"
        ) { showingSubscribe = true }
    }
}

struct PostSuccessView: View {
    let title: String
    let onDone: () -> Void
    @State private var celebrate = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 104, height: 104)
                .background(BizStyle.teal, in: Circle())
                .background(Circle().fill(BizStyle.tealSoft).scaleEffect(celebrate ? 1.45 : 0.8))
                .scaleEffect(celebrate ? 1 : 0.4)
                .opacity(celebrate ? 1 : 0)
            Text("Meeting published")
                .font(.title2.bold())
                .foregroundStyle(BizStyle.ink)
                .bizAppear(index: 2)
            Text("\"\(title)\" is now live for people across the US to discover. Find it under Host.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .bizAppear(index: 3)
            BizPrimaryButton(title: "Done", action: onDone)
                .padding(.top, 8)
                .bizAppear(index: 4)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
        .sensoryFeedback(.success, trigger: celebrate)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { celebrate = true }
        }
    }
}
