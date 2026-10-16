import SwiftUI

/// Screen 5 — Host dashboard. Owned group at a glance, genuine RSVP-based
/// metrics, upcoming posts with edit/cancel, subscription status, and a
/// prominent post action. Metrics without backing data show an honest
/// unavailable state — demo numbers never appear here.
struct HostDashboardView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    @State private var showingSignIn = false
    @State private var showingPaywall = false
    @State private var showingPost = false

    private var trialStatus: TrialStatus {
        TrialStatus.current(start: store.trialStartDate, now: Date(), subscribed: subscriptions.isPosterActive)
    }

    private var ownedUpcoming: [Meeting] {
        store.myMeetings.filter { $0.status == "live" && $0.startsAt > Date() }
    }

    private var nextMeeting: Meeting? { ownedUpcoming.first }

    private var groupName: String? {
        nextMeeting?.groupName ?? store.myMeetings.first?.groupName
    }

    /// Genuine RSVP taps on live owned posts, minus the host's own baseline.
    private var rsvpCount: Int {
        let total = ownedUpcoming.reduce(0) { $0 + $1.attendeeCount }
        return max(0, total - ownedUpcoming.count)
    }

    var body: some View {
        NavigationStack {
            Group {
                if auth.userID == nil {
                    BizIntroView(
                        systemImage: "person.3.fill",
                        title: "Host your group on BizLinq",
                        message: "Help local professionals find your group. Sign in to set up your group and post your first meeting free.",
                        actionTitle: "Sign in with Apple"
                    ) { showingSignIn = true }
                } else if ownedUpcoming.isEmpty && store.myMeetings.isEmpty {
                    BizIntroView(
                        systemImage: "calendar.badge.plus",
                        title: "Set up your first meeting",
                        message: "Fill in your group once — your contact details carry over to every future post, and you can edit any live listing anytime.",
                        actionTitle: "Post your first meeting"
                    ) { showingPost = true }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let name = groupName {
                                groupCard(name: name).bizAppear(index: 0)
                            }
                            eligibilityCard.bizAppear(index: 1)
                            reachCard.bizAppear(index: 2)
                            if let next = nextMeeting {
                                nextMeetingCard(next).bizAppear(index: 3)
                            }

                            VStack(spacing: 10) {
                                BizPrimaryButton(title: "Post next meeting", systemImage: "plus") {
                                    showingPost = true
                                }
                                if let name = groupName {
                                    NavigationLink {
                                        GroupProfileView(groupName: name)
                                    } label: {
                                        BizSecondaryLabel(title: "View public group profile")
                                    }
                                    .buttonStyle(BizPressStyle())
                                }
                            }
                            .bizAppear(index: 4)

                            VStack(alignment: .leading, spacing: 10) {
                                BizSectionHeader(title: "All posts (\(store.myMeetings.count))")
                                ForEach(store.myMeetings) { meeting in
                                    MyMeetingRow(meeting: meeting)
                                        .padding(14)
                                        .bizCard(radius: 14)
                                }
                            }
                            .id("allPosts")
                        }
                        .padding(BizStyle.gutter)
                    }
                    .background(BizStyle.canvas)
                }
            }
            .navigationTitle(auth.userID != nil && !store.myMeetings.isEmpty ? "Your group" : "Host")
            .task {
                await store.refreshMyMeetings()
                await store.refreshTrialFromServer()
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView(prompt: "Sign in to host your group on BizLinq.")
            }
            .sheet(isPresented: $showingPaywall) {
                NavigationStack {
                    PaywallView(context: trialStatus == .expired ? .trialEnded : .standard) {
                        store.trialResolvedBySubscription()
                        showingPaywall = false
                    }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showingPaywall = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showingPost) {
                NavigationStack {
                    PostMeetingView(prefill: nextMeeting)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { showingPost = false }
                            }
                        }
                }
            }
        }
    }

    private func groupCard(name: String) -> some View {
        NavigationLink {
            GroupProfileView(groupName: name)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                BizCover(seed: name, category: nextMeeting?.category ?? .businessNetworking)
                    .frame(height: 132)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        Label("View profile", systemImage: "eye")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BizStyle.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(10)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(BizStyle.ink)
                    if let tagline = nextMeeting?.audienceLine, !tagline.isEmpty {
                        Text(tagline)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
            .bizCard()
        }
        .buttonStyle(BizPressStyle())
        .accessibilityLabel("\(name). View public group profile.")
    }

    private var reachCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Reach")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BizStyle.ink)
                Spacer()
                Text("Upcoming posts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                BizMetricTile(value: "\(ownedUpcoming.count)", label: "Live posts", systemImage: "calendar")
                BizMetricTile(value: "\(rsvpCount)", label: "RSVPs", systemImage: "person.2.fill")
                BizMetricUnavailable(label: "Listing views", reason: "Not tracked yet", systemImage: "eye")
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("RSVPs are expressions of interest, not guaranteed attendance.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
    }

    private func nextMeetingCard(_ next: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Next meeting", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BizStyle.ink)
                Spacer()
            }
            NavigationLink {
                MeetingDetailView(ranked: RankedMeeting(meeting: next, distanceMiles: store.distance(for: next)))
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    BizMetaRow(icon: "clock", title: Formatters.dateLine(for: next.startsAt))
                    BizMetaRow(
                        icon: next.isVirtual ? "video" : "mappin.and.ellipse",
                        title: next.isVirtual ? "Online" : "\(next.venue) · \(next.city)"
                    )
                    BizMetaRow(
                        icon: "person.2",
                        title: next.attendeeCount == 1 ? "1 RSVP so far" : "\(next.attendeeCount) RSVPs so far"
                    )
                }
                .padding(14)
                .bizCard(radius: 14)
            }
            .buttonStyle(BizPressStyle())
        }
        .padding(12)
        .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private var eligibilityCard: some View {
        if subscriptions.isPosterActive {
            HStack(spacing: 12) {
                BizIconBadge(systemImage: "checkmark.seal.fill", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subscriptions.activePlan?.name ?? "Poster plan active")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BizStyle.ink)
                    Text("Post as often as you like").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .bizCard(radius: 14)
        } else {
            HStack(spacing: 12) {
                BizIconBadge(systemImage: trialStatus == .expired ? "exclamationmark.circle" : "sparkles", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    switch trialStatus {
                    case .notStarted:
                        Text("Post your first meeting free")
                            .font(.subheadline.weight(.semibold))
                        Text("Your first post starts a 14-day trial.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .active(let days):
                        Text(days == 1 ? "1 day left in your free trial" : "\(days) days left in your free trial")
                            .font(.subheadline.weight(.semibold))
                        Text("Subscribe to keep posting after the trial.")
                            .font(.caption).foregroundStyle(.secondary)
                    case .expired:
                        Text(store.trialDeclined ? "Hosting paused" : "Your free trial has ended")
                            .font(.subheadline.weight(.semibold))
                        Text("Your meetings stay live. Pick a plan to post again.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(BizStyle.ink)
                Spacer(minLength: 4)
                Button("Plans") { showingPaywall = true }
                    .font(.subheadline.weight(.semibold))
                    .tint(BizStyle.teal)
            }
            .padding(12)
            .bizCard(radius: 14)
        }
    }
}
