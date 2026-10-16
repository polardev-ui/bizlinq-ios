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
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(BizStyle.teal)
                        Text("Host your group on BizLinq")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("They don't need to know your group's name. They just need to be looking for their next connection. Sign in to set up your group and post your first meeting free.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        BizPrimaryButton(title: "Sign in with Apple") {
                            showingSignIn = true
                        }
                        .padding(.horizontal, BizStyle.gutter)
                        Spacer()
                    }
                    .padding()
                } else if ownedUpcoming.isEmpty && store.myMeetings.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 56))
                            .foregroundStyle(BizStyle.teal)
                        Text("Set up your first meeting")
                            .font(.title2.bold())
                        Text("Fill in your group once — your contact details carry over to every future post, and you can edit any live listing anytime.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        BizPrimaryButton(title: "Post your first meeting") {
                            showingPost = true
                        }
                        .padding(.horizontal, BizStyle.gutter)
                        Spacer()
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if let name = groupName {
                                BizGroupHeader(
                                    groupName: name,
                                    tagline: nextMeeting?.audienceLine ?? "",
                                    hostName: nil
                                )
                                NavigationLink {
                                    GroupProfileView(groupName: name)
                                } label: {
                                    HStack {
                                        Text("View public group profile").fontWeight(.semibold)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .foregroundStyle(BizStyle.teal)
                                    .padding(12)
                                    .background(BizStyle.teal.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }

                            eligibilityCard

                            if let next = nextMeeting {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Next published meeting")
                                        .font(.headline)
                                        .foregroundStyle(BizStyle.ink)
                                    NavigationLink {
                                        MeetingDetailView(
                                            ranked: RankedMeeting(
                                                meeting: next,
                                                distanceMiles: store.distance(for: next)
                                            )
                                        )
                                    } label: {
                                        BizMeetingCard(
                                            ranked: RankedMeeting(
                                                meeting: next,
                                                distanceMiles: store.distance(for: next)
                                            )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Reach")
                                    .font(.headline)
                                    .foregroundStyle(BizStyle.ink)
                                HStack(spacing: 10) {
                                    BizMetricTile(
                                        value: "\(ownedUpcoming.count)",
                                        label: "Live posts",
                                        footnote: "Upcoming meetings"
                                    )
                                    BizMetricTile(
                                        value: "\(rsvpCount)",
                                        label: "RSVPs",
                                        footnote: "Taps on live posts"
                                    )
                                }
                                HStack(spacing: 10) {
                                    BizMetricUnavailable(
                                        label: "Listing views",
                                        reason: "View tracking isn't collected yet."
                                    )
                                    BizMetricUnavailable(
                                        label: "Website taps",
                                        reason: "Link tracking isn't collected yet."
                                    )
                                }
                                Text("RSVPs show interest, not guaranteed attendance.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            BizPrimaryButton(title: "Post next meeting") {
                                showingPost = true
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("All posts (\(store.myMeetings.count))")
                                    .font(.headline)
                                    .foregroundStyle(BizStyle.ink)
                                ForEach(store.myMeetings) { meeting in
                                    MyMeetingRow(meeting: meeting)
                                        .padding(12)
                                        .background(Color(.systemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(BizStyle.hairline, lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(BizStyle.gutter)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("Host")
            .task {
                await store.refreshMyMeetings()
                await store.refreshTrialFromServer()
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView(prompt: "Sign in to host your group on BizLinq.")
            }
            .sheet(isPresented: $showingPaywall) {
                NavigationStack {
                    PaywallView()
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

    @ViewBuilder
    private var eligibilityCard: some View {
        if subscriptions.isPosterActive {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(subscriptions.activePlan?.name ?? "Poster plan active").font(.headline)
                    Text("Post as often as you like").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(BizStyle.hairline, lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                switch trialStatus {
                case .notStarted:
                    Text("Post your first meeting free")
                        .font(.headline)
                    Text("Your first post starts a 14-day trial.")
                        .font(.subheadline).foregroundStyle(.secondary)
                case .active(let days):
                    Text(days == 1 ? "1 day left in your free trial" : "\(days) days left in your free trial")
                        .font(.headline)
                    Text("Subscribe to keep posting after the trial.")
                        .font(.subheadline).foregroundStyle(.secondary)
                case .expired:
                    Text("Trial ended — subscribe to post")
                        .font(.headline)
                    Text("Browse free, or resubscribe anytime.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("See poster plans") { showingPaywall = true }
                    .buttonStyle(.borderedProminent)
                    .tint(BizStyle.teal)
            }
            .padding(12)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(BizStyle.hairline, lineWidth: 1))
        }
    }
}
