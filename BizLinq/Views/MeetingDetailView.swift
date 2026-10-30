import SwiftUI

/// Screen 3 — Meeting details. Cost is visible before the RSVP action:
/// free events read "RSVP for free"; paid events read "RSVP" with the fee
/// shown. No payment is collected in-app.
struct MeetingDetailView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    let ranked: RankedMeeting

    @State private var showingPaywall = false
    @State private var paywallClaimMode = false
    @State private var showingSignIn = false
    @State private var rsvpError: String?
    @State private var showingReport = false
    @State private var reportReason = MeetingStore.reportReasons[0]
    @State private var reportDone = false
    @State private var confirmingBlock = false
    @Environment(\.dismiss) private var dismiss

    private var meeting: Meeting { ranked.meeting }

    /// Live copy from the store so RSVP counts update in place.
    private var live: Meeting {
        store.meetings.first(where: { $0.id == meeting.id }) ?? meeting
    }

    private var rsvpd: Bool { store.hasRSVPd(meeting) }

    private let heroHeight: CGFloat = 260

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 20) {
                    titleBlock
                    metaBlock
                    if !meeting.isVirtual {
                        BizMapCard(title: meeting.venue, coordinate: meeting.coordinate)
                    }
                    NavigationLink {
                        GroupProfileView(groupName: meeting.groupName)
                    } label: {
                        BizHostRow(
                            hostName: meeting.hostName.isEmpty ? meeting.groupName : meeting.hostName,
                            subtitle: "Organizer · \(meeting.groupName)"
                        )
                        .padding(14)
                        .bizCard()
                    }
                    .buttonStyle(BizPressStyle())
                    .accessibilityLabel("Hosted by \(meeting.hostName). View group profile for \(meeting.groupName)")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("About this meeting")
                            .font(.headline)
                            .foregroundStyle(BizStyle.ink)
                        Text(meeting.description)
                            .font(.subheadline)
                            .foregroundStyle(BizStyle.ink.opacity(0.8))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if meeting.source != nil || meeting.sourceURL != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            if let source = meeting.source {
                                Label("Curated listing · sourced from \(source)", systemImage: "checkmark.seal.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let urlString = meeting.sourceURL, let url = URL(string: urlString),
                               urlString.hasPrefix("http") {
                                Link(destination: url) {
                                    Label("More info on the event page", systemImage: "arrow.up.right.square")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(BizStyle.teal)
                                }
                            }
                        }
                    }

                    NavigationLink {
                        GroupProfileView(groupName: meeting.groupName)
                    } label: {
                        Text("View group profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BizStyle.teal)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, BizStyle.gutter)
                .padding(.top, 18)
                .padding(.bottom, 24)
                .background(BizStyle.canvas)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(BizStyle.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                BizSaveButton(meetingID: meeting.id, onImage: false)
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share meeting")
                Menu {
                    Button {
                        if auth.userID == nil {
                            showingSignIn = true
                        } else {
                            showingReport = true
                        }
                    } label: {
                        Label("Report meeting", systemImage: "flag")
                    }
                    if meeting.hostID != nil {
                        Button(role: .destructive) {
                            confirmingBlock = true
                        } label: {
                            Label("Block host", systemImage: "nosign")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Meeting options")
            }
        }
        .tint(BizStyle.teal)
        .safeAreaInset(edge: .bottom) {
            rsvpBar
        }
        .sensoryFeedback(.success, trigger: rsvpd) { _, new in new }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack {
                PaywallView(context: paywallClaimMode ? .claim : .standard) {
                    // After subscribing in claim mode, claim the meeting.
                    if paywallClaimMode {
                        Task {
                            do {
                                try await store.claimMeeting(meeting)
                            } catch {
                                rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                    }
                }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                paywallClaimMode = false
                                showingPaywall = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView(prompt: "Sign in with a free account to RSVP for this meeting.")
        }
        .alert("Couldn't update RSVP", isPresented: Binding(
            get: { rsvpError != nil },
            set: { if !$0 { rsvpError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rsvpError ?? "Try again later.")
        }
        .sheet(isPresented: $showingReport) {
            NavigationStack {
                Form {
                    Section {
                        Text("Flag this meeting for review. We remove spam, scams, and inappropriate content.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Reason") {
                        Picker("Reason", selection: $reportReason) {
                            ForEach(MeetingStore.reportReasons, id: \.self) { reason in
                                Text(reason).tag(reason)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    Section {
                        Button("Submit report") {
                            Task {
                                do {
                                    try await store.reportMeeting(meeting, reason: reportReason)
                                    showingReport = false
                                    reportDone = true
                                } catch {
                                    rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                    showingReport = false
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Report meeting")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingReport = false }
                    }
                }
            }
        }
        .alert("Thanks - report received", isPresented: $reportDone) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We'll review this meeting and remove it if it breaks the rules.")
        }
        .confirmationDialog("Block this host?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block host", role: .destructive) {
                store.blockHost(of: meeting)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer see meetings from this host.")
        }
    }

    /// Cover with a stretchy pull-down effect.
    private var hero: some View {
        GeometryReader { geo in
            let pull = max(0, geo.frame(in: .scrollView).minY)
            BizCover(seed: meeting.groupName, category: meeting.category)
                .frame(width: geo.size.width, height: heroHeight + pull)
                .clipped()
                .overlay(alignment: .top) {
                    // Keeps toolbar buttons legible over bright skies.
                    LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                }
                .offset(y: -pull)
        }
        .frame(height: heroHeight)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.category.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(BizStyle.teal)
            Text(meeting.title)
                .font(.title2.bold())
                .foregroundStyle(BizStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !meeting.audienceLine.isEmpty {
                Text(meeting.audienceLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .bizAppear(index: 1)
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            BizMetaRow(
                icon: "calendar",
                title: Formatters.fullWithZone.string(from: meeting.startsAt),
                detail: "Local time on your device"
            )
            if meeting.isVirtual {
                BizMetaRow(
                    icon: "video",
                    title: "Online event",
                    detail: "Check the event page for access instructions."
                )
            } else {
                BizMetaRow(
                    icon: "mappin.and.ellipse",
                    title: meeting.venue,
                    detail: [
                        "\(meeting.address), \(meeting.city), \(meeting.state) \(meeting.zipCode)",
                        store.distanceText(for: meeting)
                    ].compactMap { $0 }.joined(separator: "\n")
                )
            }
            HStack(spacing: 8) {
                BizTag(
                    text: meeting.isFreeEntry ? "Free to attend" : "\(meeting.costBadgeText) to attend",
                    systemImage: "tag"
                )
                if let spots = live.spotsLeftText {
                    BizTag(text: spots, systemImage: "person.2")
                } else if live.attendeeCount > 0 {
                    BizTag(text: "\(live.attendeeCount) going", systemImage: "person.2")
                        .contentTransition(.numericText())
                }
            }
            if !meeting.isFreeEntry {
                Text("Pay the host directly — BizLinq never charges attendees.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .bizAppear(index: 2)
    }

    private var claimButton: some View {
        Group {
            if auth.userID == nil {
                BizPrimaryButton(title: "Sign in to claim this listing") {
                    showingSignIn = true
                }
            } else if !subscriptions.isPosterActive {
                BizPrimaryButton(title: "Subscribe to claim — $10/month") {
                    paywallClaimMode = true
                    showingPaywall = true
                }
            } else {
                BizPrimaryButton(title: "Claim this listing") {
                    Task {
                        do {
                            try await store.claimMeeting(meeting)
                            rsvpError = nil
                        } catch {
                            rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private var rsvpBar: some View {
        VStack {
            if meeting.isClaimable {
                claimButton
            }
            Group {
                if rsvpd {
                    BizSecondaryButton(title: "You're going", systemImage: "checkmark.circle.fill") {
                        toggleRSVP()
                    }
                    .accessibilityHint("Double tap to cancel your RSVP")
                } else {
                    BizPrimaryButton(title: meeting.isFreeEntry ? "RSVP for free" : "RSVP · \(meeting.costBadgeText)") {
                        toggleRSVP()
                    }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
        .animation(BizStyle.spring, value: rsvpd)
        .padding(.horizontal, BizStyle.gutter)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func toggleRSVP() {
        if auth.userID == nil {
            showingSignIn = true
            return
        }
        Task {
            do {
                try await store.toggleRSVP(for: meeting)
            } catch {
                rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private var shareText: String {
        "\(meeting.title) - \(meeting.groupName) on \(Formatters.dateLine(for: meeting.startsAt)) at \(meeting.venue), \(meeting.city). Found on BizLinq."
    }
}
